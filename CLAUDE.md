# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a LaTeX project for creating a CKA (Certified Kubernetes Administrator) exam cheatsheet. The document is typeset with LuaLaTeX and compiled via `latexmk`. The devcontainer provides a full TeX Live installation, `poppler-utils`, and code assistants (Claude Code, Gemini CLI, Jules).

## Building

Compile a `.tex` file with latexmk, directing all output into `./out`:

```bash
latexmk --shell-escape -synctex=1 -interaction=nonstopmode -file-line-error \
  -pdflatex=lualatex -pdf \
  -aux-directory=./out -output-directory=./out \
  src/main.tex
```

The PDF is written to `./out/main.pdf`.

## Verifying Output

After building, use `poppler-utils` to render the PDF pages as PNG screenshots and inspect them:

```bash
# Render all pages at 150 dpi
pdftoppm -r 150 -png out/main.pdf /tmp/preview

# Files are written as /tmp/preview-1.png, /tmp/preview-2.png, …
```

Read the generated PNG files with the Read tool to visually verify the output. If the result is wrong, fix the source and re-compile.

## Project Structure

```
src/main.tex          # Active document (CKA cheatsheet — currently empty, work in progress)
old_version/main.tex  # Previous version of the cheatsheet (reference implementation)
old_version/out/      # Compiled output of the old version
logo/main.tex         # Logo document
.vscode/settings.json # LaTeX Workshop tool/recipe config (authoritative build flags)
.devcontainer/        # Devcontainer definition (Dockerfile + docker-compose.yml)
```

## LaTeX Conventions

- Engine: **LuaLaTeX** (use `fontspec`, `unicode-math`, `luacolor`, etc. — not `pdflatex`-only packages)
- `--shell-escape` is required (enabled for `minted` / `svg`)
- All auxiliary and output files go into `./out` — never pollute the source directory
- Available packages include: `tcolorbox`, `tabularray`, `tikz`/`pgf`, `pgfplots`, `bytefield`, `minted`, `biblatex`/`biber`, `fontspec`, `emoji`, `geometry`, `fancyhdr`, `hyperref`, and the full set listed in `.devcontainer/Dockerfile`
