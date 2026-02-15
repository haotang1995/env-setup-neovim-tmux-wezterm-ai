#!/usr/bin/env bash
# Launch Codex CLI inside a Docker sandbox scoped to the current directory.
# Uses `docker sandbox run` which creates a microVM with only the workspace
# directory accessible.
#
# A single persistent sandbox named "codex" is reused across all projects
# so OAuth login only needs to happen once.
#
# Usage: codex-sandbox [codex args...]

set -euo pipefail

exec docker sandbox run --name codex codex "${PWD}" -- "$@"
