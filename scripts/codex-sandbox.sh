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
CODEX_CONTAINER="/root/.codex"
SANDBOX_IMAGE="${SANDBOX_IMAGE:-codex-sandbox:node22}"

# Build a local base image with required tooling (git, ssh, certs, pager).
if ! docker image inspect "${SANDBOX_IMAGE}" >/dev/null 2>&1; then
  docker build -q \
    -t "${SANDBOX_IMAGE}" \
    -f "${REPO_DIR}/scripts/codex-sandbox.Dockerfile" \
    "${REPO_DIR}" >/dev/null
fi

docker_args=(
  --rm -it
  -v "${PWD}:/workspace"
  -v codex-home:"${CODEX_CONTAINER}"
  -v "${REPO_DIR}:${REPO_DIR}:ro"
  -v codex-npm-cache:/root/.npm
  --mount "type=bind,src=${CODEX_HOST},dst=/host-codex,readonly"
  -w /workspace
  -e HOME=/root
  -e CODEX_CONTAINER="${CODEX_CONTAINER}"
  -e REPO_DIR="${REPO_DIR}"
)

# Optionally pass through host git configuration.
if [[ -f "${HOME}/.gitconfig" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.gitconfig,dst=/host-gitconfig,readonly")
fi
if [[ -d "${HOME}/.config/git" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.config/git,dst=/host-git-config,readonly")
fi

exec docker run "${docker_args[@]}" \
  "${SANDBOX_IMAGE}" \
  bash -c '
    mkdir -p "${CODEX_CONTAINER}"
    # Always refresh OAuth + config from host (tokens expire)
    cp /host-codex/auth.json "${CODEX_CONTAINER}/" 2>/dev/null || true
    cp /host-codex/config.toml "${CODEX_CONTAINER}/" 2>/dev/null || true
    # Keep git config aligned with host when available.
    cp /host-gitconfig "${HOME}/.gitconfig" 2>/dev/null || true
    mkdir -p "${HOME}/.config/git"
    cp -R /host-git-config/. "${HOME}/.config/git/" 2>/dev/null || true
    # Migrate legacy nested skills path if present.
    if [ -d "${CODEX_CONTAINER}/.codex/skills" ]; then
      mkdir -p "${CODEX_CONTAINER}/skills"
      cp -a "${CODEX_CONTAINER}/.codex/skills/." "${CODEX_CONTAINER}/skills/" 2>/dev/null || true
    fi

    # Set up skills when missing or effectively empty (only .system).
    if [ ! -d "${CODEX_CONTAINER}/skills" ] || \
       ! find "${CODEX_CONTAINER}/skills" -mindepth 1 -maxdepth 1 ! -name ".system" | grep -q .; then
      "${REPO_DIR}/scripts/install.sh" >/dev/null 2>&1 || true
    fi
    npm i -g @openai/codex >/dev/null 2>&1
    exec codex --sandbox danger-full-access "$@"
  ' _ "$@"
