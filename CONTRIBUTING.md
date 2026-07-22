# Contributing

Open an issue before substantial content or layout changes so the intended
audience and page-density trade-offs are clear. Small corrections and
documentation fixes can go directly into a pull request.

The maintained source is `src/main.tex`. Keep generated files under `out/`
untracked. When changing layout or illustrations, build the PDF locally and,
when practical, include rendered page previews and the exact validation
command in the pull request.

This repository intentionally has no GitHub Actions or workflow files. Local
LuaLaTeX builds, manual PDF inspection, and human review are the verification
process.

The GitHub repository is the source and issue-tracking home; Codeberg is the
release-artifact host. Do not add credentials or release tokens to commits.
