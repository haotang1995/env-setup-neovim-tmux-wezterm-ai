#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR"
fi

cd "$TARGET_DIR"

if [ ! -f AI.md ]; then
  cat > AI.md <<'DOC'
# Project AI Instructions

Put shared instructions here once.
DOC
fi

if [ ! -d "TODO" ]; then
  mkdir -p "TODO"
fi

if [ ! -f "TODO/TODO.md" ]; then
  cat > "TODO/TODO.md" <<'DOC'
# Tasks

- [ ] Initial Setup
DOC
fi

ln -sfn AI.md CLAUDE.md
ln -sfn AI.md CODEX.md
ln -sfn AI.md GEMINI.md

echo "Bootstrapped AI docs in: $(pwd)"
ls -l AI.md CLAUDE.md CODEX.md GEMINI.md TODO/TODO.md
