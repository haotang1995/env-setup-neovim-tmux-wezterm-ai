#!/usr/bin/env bash
# Launch Codex CLI inside a plain Docker container scoped to the current
# directory. Only the workspace is writable; everything else is read-only
# or absent.
#
# Mounts:
#   ${PWD}       -> /workspace     (rw)  workspace
#   ~/.codex     -> ~/.codex            (rw, named volume seeded from host)
#   REPO_DIR     -> REPO_DIR       (ro)  skill symlink targets + install.sh
#
# A named volume "codex-home" persists OAuth tokens and skill symlinks.
# A named volume "codex-npm-cache" caches npm so codex install is fast
# after first run.
#
# On first run, install.sh sets up skills inside the container.
#
# Usage: codex-sandbox [codex args...]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_HOST="${HOME}/.codex"
CODEX_CONTAINER="${HOME}/.codex"

exec docker run --rm -it \
  -v "${PWD}:/workspace" \
  -v codex-home:"${CODEX_CONTAINER}" \
  -v "${REPO_DIR}:${REPO_DIR}:ro" \
  -v codex-npm-cache:/root/.npm \
  --mount "type=bind,src=${CODEX_HOST},dst=/host-codex,readonly" \
  -w /workspace \
  -e HOME="${HOME}" \
  node:22-slim \
  bash -c '
    # Ensure CA certificates are present (needed by the Rust-based codex binary)
    apt-get update -qq && apt-get install -y -qq ca-certificates >/dev/null 2>&1
    # Always refresh OAuth + config from host (tokens expire)
    cp /host-codex/auth.json "'"${CODEX_CONTAINER}"'/" 2>/dev/null || true
    cp /host-codex/config.toml "'"${CODEX_CONTAINER}"'/" 2>/dev/null || true
    # Set up skills on first run
    if [ ! -d "'"${CODEX_CONTAINER}"'/skills" ]; then
      "'"${REPO_DIR}"'/scripts/install.sh" >/dev/null 2>&1 || true
    fi
    npm i -g @openai/codex >/dev/null 2>&1
    exec codex --sandbox danger-full-access "$@"
  ' _ "$@"
