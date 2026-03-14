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
  echo "Error: could not detect owner/repo from git remote. Set CODEBERG_OWNER and CODEBERG_REPO." >&2
  exit 1
fi

API="https://codeberg.org/api/v1/repos/${CODEBERG_OWNER}/${CODEBERG_REPO}"
PDF_NAME="k8s_summary_sheet_${TAG}.pdf"

echo "==> Building PDF with LuaLaTeX..."
mkdir -p out
latexmk --shell-escape -synctex=1 -interaction=nonstopmode -file-line-error \
  -pdflatex=lualatex -pdf \
  -aux-directory=./out -output-directory=./out \
  src/main.tex

cp out/main.pdf "${PDF_NAME}"
echo "    Built ${PDF_NAME}"

# --- Create git tag (if not already present) --------------------------------
echo "==> Tagging ${TAG}..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "    Tag ${TAG} already exists, skipping."
else
  git tag -a "$TAG" -m "Release ${TAG}"
fi
git push origin "$TAG"

# --- Create the release -----------------------------------------------------
echo "==> Creating Codeberg release ${TAG}..."
RELEASE_RESPONSE=$(curl -sf -X POST \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  -H "Content-Type: application/json" \
  "${API}/releases" \
  -d "{
    \"tag_name\": \"${TAG}\",
    \"name\": \"${TAG}\",
    \"body\": \"Kubernetes CKA Summary Sheet ${TAG}\",
    \"draft\": false,
    \"prerelease\": false
  }")

RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')

if [[ -z "$RELEASE_ID" || "$RELEASE_ID" == "null" ]]; then
  echo "Error: failed to create release. Response:" >&2
  echo "$RELEASE_RESPONSE" >&2
  exit 1
fi
echo "    Created release ID: ${RELEASE_ID}"

# --- Upload the PDF as a release asset --------------------------------------
echo "==> Uploading ${PDF_NAME}..."
curl -sf -X POST \
  -H "Authorization: token ${CODEBERG_TOKEN}" \
  "${API}/releases/${RELEASE_ID}/assets?name=${PDF_NAME}" \
  -F "attachment=@${PDF_NAME};type=application/pdf" > /dev/null

echo "==> Done! Release ${TAG} published with ${PDF_NAME}"
echo "    https://codeberg.org/${CODEBERG_OWNER}/${CODEBERG_REPO}/releases/tag/${TAG}"

# Clean up local copy
rm -f "${PDF_NAME}"
