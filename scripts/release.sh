#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <tag>

Build the Kubernetes Summary Sheet and publish it as a Codeberg release
with the compiled PDF attached as an asset.

Arguments:
  <tag>    Git tag for the release (e.g. v1.0.0)

Environment variables:
  CODEBERG_TOKEN   (required) Personal access token with write:repository scope.
                   Generate at: https://codeberg.org/user/settings/applications
  CODEBERG_OWNER   Repository owner (default: auto-detected from git remote)
  CODEBERG_REPO    Repository name  (default: auto-detected from git remote)
  ENV_FILE         Path to .env file (default: .env)

The script automatically loads a .env file (if present) before reading
environment variables. Create a .env file with KEY=VALUE lines, e.g.:

  CODEBERG_TOKEN=your_token_here

Examples:
  # Using .env file (recommended)
  echo 'CODEBERG_TOKEN=your_token' > .env
  $SCRIPT_NAME v1.0.0

  # Basic usage with inline variable
  CODEBERG_TOKEN=your_token $SCRIPT_NAME v1.0.0

  # With explicit owner/repo
  CODEBERG_OWNER=myuser CODEBERG_REPO=myrepo CODEBERG_TOKEN=tok $SCRIPT_NAME v1.2.0

  # Export token once, then release
  export CODEBERG_TOKEN=your_token
  $SCRIPT_NAME v1.0.0
EOF
  exit "${1:-0}"
}

die() { echo "Error: $*" >&2; exit 1; }

# --- Parse arguments --------------------------------------------------------
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

TAG="${1:?Error: missing <tag> argument. Run '$SCRIPT_NAME --help' for usage.}"

# --- Load .env file if present ------------------------------------------------
ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
  echo "==> Loading environment from ${ENV_FILE}"
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

: "${CODEBERG_TOKEN:?Error: CODEBERG_TOKEN is not set. Run '$SCRIPT_NAME --help' for usage.}"

# --- Check prerequisites -----------------------------------------------------
for cmd in latexmk curl jq git; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is not installed or not in PATH."
done

# --- Detect owner/repo from git remote -------------------------------------
detect_remote() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "$url" =~ codeberg\.org[:/]([^/]+)/([^/.]+) ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  fi
}

if [[ -z "${CODEBERG_OWNER:-}" || -z "${CODEBERG_REPO:-}" ]]; then
  read -r detected_owner detected_repo <<< "$(detect_remote)"
  CODEBERG_OWNER="${CODEBERG_OWNER:-$detected_owner}"
  CODEBERG_REPO="${CODEBERG_REPO:-$detected_repo}"
fi

if [[ -z "$CODEBERG_OWNER" || -z "$CODEBERG_REPO" ]]; then
  die "Could not detect owner/repo from git remote. Set CODEBERG_OWNER and CODEBERG_REPO."
fi

API="https://codeberg.org/api/v1/repos/${CODEBERG_OWNER}/${CODEBERG_REPO}"
PDF_NAME="k8s_summary_sheet_${TAG}.pdf"

echo "==> Repository: ${CODEBERG_OWNER}/${CODEBERG_REPO}"
echo "    API base:   ${API}"
echo "    Tag:        ${TAG}"
echo "    PDF name:   ${PDF_NAME}"

# --- Verify API access and token permissions ---------------------------------
echo "==> Verifying API access..."

# Check authenticated user
echo "    Checking token authentication..."
USER_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  "https://codeberg.org/api/v1/user")
USER_HTTP=$(echo "$USER_RESPONSE" | tail -1)
USER_JSON=$(echo "$USER_RESPONSE" | sed '$d')
if [[ "$USER_HTTP" != "200" ]]; then
  die "Token authentication failed (HTTP ${USER_HTTP}). Is CODEBERG_TOKEN valid?"
fi
TOKEN_USER=$(echo "$USER_JSON" | jq -r '.login')
echo "    Authenticated as: ${TOKEN_USER}"

# Check repo access and default branch
REPO_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  "${API}")
REPO_HTTP=$(echo "$REPO_RESPONSE" | tail -1)
REPO_JSON=$(echo "$REPO_RESPONSE" | sed '$d')
if [[ "$REPO_HTTP" != "200" ]]; then
  die "Cannot access repo (HTTP ${REPO_HTTP}). Check CODEBERG_OWNER/CODEBERG_REPO."
fi
DEFAULT_BRANCH=$(echo "$REPO_JSON" | jq -r '.default_branch')
REPO_PERMS=$(echo "$REPO_JSON" | jq -c '.permissions // empty')
echo "    Default branch: ${DEFAULT_BRANCH}"
echo "    Permissions:    ${REPO_PERMS:-"(not returned — token may lack scope)"}"

# Check write permission
HAS_PUSH=$(echo "$REPO_JSON" | jq -r '.permissions.push // false')
if [[ "$HAS_PUSH" != "true" ]]; then
  echo "    WARNING: Token does not appear to have push/write permission on this repo!" >&2
  echo "    The token needs 'write:repository' scope (or 'repository' with write access)." >&2
  echo "    Generate a new token at: https://codeberg.org/user/settings/applications" >&2
fi

# --- Build PDF ---------------------------------------------------------------
echo "==> Building PDF with LuaLaTeX..."
mkdir -p out
if ! latexmk --shell-escape -synctex=1 -interaction=nonstopmode -file-line-error \
  -pdflatex=lualatex -pdf \
  -aux-directory=./out -output-directory=./out \
  src/main.tex; then
  die "latexmk failed. Check the log at out/main.log"
fi

if [[ ! -f out/main.pdf ]]; then
  die "Build succeeded but out/main.pdf not found."
fi

cp out/main.pdf "${PDF_NAME}"
PDF_SIZE=$(stat -c%s "${PDF_NAME}" 2>/dev/null || stat -f%z "${PDF_NAME}" 2>/dev/null)
echo "    Built ${PDF_NAME} (${PDF_SIZE} bytes)"

if [[ "$PDF_SIZE" -lt 1000 ]]; then
  die "PDF is suspiciously small (${PDF_SIZE} bytes). Something may be wrong with the build."
fi

# --- Configure git to use the API token for pushing --------------------------
# git push over HTTPS doesn't use CODEBERG_TOKEN, so we inject credentials via
# a temporary credential helper to avoid expired/missing git credentials.
PUSH_URL="https://${TOKEN_USER}:${CODEBERG_TOKEN}@codeberg.org/${CODEBERG_OWNER}/${CODEBERG_REPO}.git"

git_push() {
  # Push using the token-authenticated URL; filter output to avoid leaking the token
  git push "${PUSH_URL}" "$@" 2>&1 | sed "s|${CODEBERG_TOKEN}|***|g"
  return "${PIPESTATUS[0]}"
}

# --- Push current branch to origin -------------------------------------------
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> Pushing branch '${BRANCH}' to origin..."
if ! git_push "${BRANCH}"; then
  die "Failed to push branch ${BRANCH} to origin."
fi

# --- Create the release (which also creates the tag on the remote) ----------
# Note: Codeberg/Forgejo requires target_commitish to be a branch name, not a
# SHA. The API also creates the tag itself — pushing the tag beforehand can
# cause a 404 "target couldn't be found" error (known Gitea issue #21681).
echo "==> Creating Codeberg release ${TAG}..."
echo "    Target branch: ${DEFAULT_BRANCH} (from API)"
RELEASE_BODY=$(cat <<BODY
{
  "tag_name": "${TAG}",
  "target_commitish": "${DEFAULT_BRANCH}",
  "name": "${TAG}",
  "body": "Kubernetes Summary Sheet ${TAG}",
  "draft": false,
  "prerelease": false
}
BODY
)
echo "    Request body: ${RELEASE_BODY}"

RELEASE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/releases" \
  -d "$RELEASE_BODY")

RELEASE_HTTP_CODE=$(echo "$RELEASE_RESPONSE" | tail -1)
RELEASE_JSON=$(echo "$RELEASE_RESPONSE" | sed '$d')

echo "    Response HTTP ${RELEASE_HTTP_CODE}"

if [[ "$RELEASE_HTTP_CODE" -lt 200 || "$RELEASE_HTTP_CODE" -ge 300 ]]; then
  echo "    Response body: ${RELEASE_JSON}" >&2
  die "Failed to create release (HTTP ${RELEASE_HTTP_CODE})."
fi

RELEASE_ID=$(echo "$RELEASE_JSON" | jq -r '.id')

if [[ -z "$RELEASE_ID" || "$RELEASE_ID" == "null" ]]; then
  echo "    Response body: ${RELEASE_JSON}" >&2
  die "Release created but could not extract release ID from response."
fi
echo "    Created release ID: ${RELEASE_ID}"

# --- Upload the PDF as a release asset --------------------------------------
echo "==> Uploading ${PDF_NAME} to release ${RELEASE_ID}..."
UPLOAD_URL="${API}/releases/${RELEASE_ID}/assets?name=${PDF_NAME}"
echo "    Upload URL: ${UPLOAD_URL}"

UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  "${UPLOAD_URL}" \
  -F "attachment=@${PDF_NAME};type=application/pdf")

UPLOAD_HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)
UPLOAD_JSON=$(echo "$UPLOAD_RESPONSE" | sed '$d')

echo "    Response HTTP ${UPLOAD_HTTP_CODE}"

if [[ "$UPLOAD_HTTP_CODE" -lt 200 || "$UPLOAD_HTTP_CODE" -ge 300 ]]; then
  echo "    Response body: ${UPLOAD_JSON}" >&2
  die "Failed to upload PDF (HTTP ${UPLOAD_HTTP_CODE})."
fi

ASSET_URL=$(echo "$UPLOAD_JSON" | jq -r '.browser_download_url // empty')
echo "    Upload OK. Asset URL: ${ASSET_URL:-"(not returned)"}"

# --- Verify the release has the asset ----------------------------------------
echo "==> Verifying release assets..."
ASSETS_JSON=$(curl -s \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  "${API}/releases/${RELEASE_ID}/assets")
ASSET_COUNT=$(echo "$ASSETS_JSON" | jq 'length')
echo "    Release has ${ASSET_COUNT} asset(s):"
echo "$ASSETS_JSON" | jq -r '.[] | "    - \(.name) (\(.size) bytes)"'

if [[ "$ASSET_COUNT" -eq 0 ]]; then
  die "Release has no assets — upload may have failed silently."
fi

# --- Sync local tag with remote ----------------------------------------------
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git fetch origin "refs/tags/${TAG}:refs/tags/${TAG}" 2>/dev/null || true
fi

echo ""
echo "==> Done! Release ${TAG} published with ${PDF_NAME}"
echo "    https://codeberg.org/${CODEBERG_OWNER}/${CODEBERG_REPO}/releases/tag/${TAG}"

# Clean up local copy
rm -f "${PDF_NAME}"
