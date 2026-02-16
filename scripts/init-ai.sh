#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DOCKERFILE="${SCRIPT_DIR}/codex-sandbox.Dockerfile"
TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR"
fi

cd "$TARGET_DIR"

# Always provide a default Dockerfile for codex-sandbox cwd builds.
cp "${DEFAULT_DOCKERFILE}" Dockerfile

# Initialize a null installer for project-specific setup hooks.
if [ ! -f install.sh ]; then
  cat > install.sh <<'DOC'
#!/usr/bin/env bash
set -euo pipefail

# No-op project installer. Add setup steps when needed.
exit 0
DOC
  chmod +x install.sh
fi

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
