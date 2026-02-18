#!/usr/bin/env bash
# Launch Claude Code inside a plain Docker container scoped to the current
# directory. Only the workspace is writable; everything else is read-only
# or absent.
#
# Usage: claude-sandbox [claude args...]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOST="${HOME}/.claude"
CLAUDE_CONTAINER="/root/.claude"

resolve_abs_path() {
  local candidate="$1"
  if [[ "${candidate}" = /* ]]; then
    printf '%s\n' "${candidate}"
  else
    printf '%s\n' "${PWD}/${candidate}"
  fi
}

DOCKERFILE_PATH=""
BUILD_CONTEXT=""
DOCKERFILE_SOURCE="default"

# Dockerfile selection order:
# 1) SANDBOX_DOCKERFILE
# 2) ./Dockerfile in caller's current directory
# 3) repository default scripts/codex-sandbox.Dockerfile
if [[ -n "${SANDBOX_DOCKERFILE:-}" ]]; then
  DOCKERFILE_PATH="$(resolve_abs_path "${SANDBOX_DOCKERFILE}")"
  if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
    echo "Error: SANDBOX_DOCKERFILE does not exist: ${DOCKERFILE_PATH}" >&2
    exit 1
  fi
  BUILD_CONTEXT="${SANDBOX_DOCKER_CONTEXT:-$(cd "$(dirname "${DOCKERFILE_PATH}")" && pwd)}"
  DOCKERFILE_SOURCE="custom"
elif [[ -f "${PWD}/Dockerfile" ]]; then
  DOCKERFILE_PATH="${PWD}/Dockerfile"
  BUILD_CONTEXT="${PWD}"
  DOCKERFILE_SOURCE="cwd"
else
  DOCKERFILE_PATH="${REPO_DIR}/scripts/codex-sandbox.Dockerfile"
  BUILD_CONTEXT="${REPO_DIR}"
fi

# Keep the existing default tag for the built-in Dockerfile. For custom
# Dockerfiles, derive a content-based tag to avoid image collisions.
if [[ -n "${SANDBOX_IMAGE:-}" ]]; then
  SANDBOX_IMAGE="${SANDBOX_IMAGE}"
elif [[ "${DOCKERFILE_SOURCE}" = "default" ]]; then
  SANDBOX_IMAGE="claude-sandbox:node22"
else
  dockerfile_hash="$(sha256sum "${DOCKERFILE_PATH}" | awk '{print substr($1,1,12)}')"
  SANDBOX_IMAGE="claude-sandbox:custom-${dockerfile_hash}"
fi

echo "Using sandbox image: ${SANDBOX_IMAGE}" >&2

if ! docker image inspect "${SANDBOX_IMAGE}" >/dev/null 2>&1; then
  docker build -q \
    -t "${SANDBOX_IMAGE}" \
    -f "${DOCKERFILE_PATH}" \
    "${BUILD_CONTEXT}" >/dev/null
fi

docker_args=(
  --rm -it
  -v "${PWD}:/workspace"
  -v claude-home:"${CLAUDE_CONTAINER}"
  -v claude-config:/root/.config
  -v claude-local-share:/root/.local/share
  -v "${REPO_DIR}:${REPO_DIR}:ro"
  -v claude-npm-cache:/root/.npm
  --mount "type=bind,src=${CLAUDE_HOST},dst=/host-claude,readonly"
  -w /workspace
  -e HOME=/root
  -e CLAUDE_CONTAINER="${CLAUDE_CONTAINER}"
  -e REPO_DIR="${REPO_DIR}"
)

if [[ -f "${HOME}/.claude.json" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.claude.json,dst=/host-claude-json,readonly")
fi
if [[ -f "${HOME}/.gitconfig" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.gitconfig,dst=/host-gitconfig,readonly")
fi
if [[ -d "${HOME}/.config/git" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.config/git,dst=/host-git-config,readonly")
fi
if [[ -d "${HOME}/.config/claude" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.config/claude,dst=/host-claude-config,readonly")
fi
if [[ -d "${HOME}/.config/claude-code" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.config/claude-code,dst=/host-claude-code-config,readonly")
fi
# On macOS, Claude Code stores OAuth tokens in the Keychain (service:
# "Claude Code-credentials") rather than on disk.  Extract the full
# credentials JSON (access + refresh tokens) and inject it into the
# container as ~/.claude/.credentials.json so built-in refresh works.
_CLAUDE_CREDS_JSON=""
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] && command -v security &>/dev/null; then
  _CLAUDE_CREDS_JSON="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
  if [[ -n "${_CLAUDE_CREDS_JSON}" ]]; then
    docker_args+=(-e "_CLAUDE_CREDS_JSON=${_CLAUDE_CREDS_JSON}")
  fi
fi

# Pass through common auth/environment overrides when available.
for env_name in \
  ANTHROPIC_API_KEY \
  ANTHROPIC_AUTH_TOKEN \
  CLAUDE_CODE_OAUTH_TOKEN \
  ANTHROPIC_BASE_URL \
  ANTHROPIC_MODEL; do
  if [[ -n "${!env_name:-}" ]]; then
    docker_args+=(-e "${env_name}")
  fi
done

exec docker run "${docker_args[@]}" \
  "${SANDBOX_IMAGE}" \
  bash -c '
    mkdir -p "${CLAUDE_CONTAINER}"
    # Seed Claude auth/config from host only when files are missing.
    # Do not overwrite existing container state so login can persist.
    cp -an /host-claude/. "${CLAUDE_CONTAINER}/" 2>/dev/null || true
    cp -an /host-claude-json "${HOME}/.claude.json" 2>/dev/null || true

    # Write Keychain-extracted credentials so Claude Code can auth & refresh.
    if [ -n "${_CLAUDE_CREDS_JSON:-}" ]; then
      printf "%s" "${_CLAUDE_CREDS_JSON}" > "${CLAUDE_CONTAINER}/.credentials.json"
      chmod 600 "${CLAUDE_CONTAINER}/.credentials.json"
      unset _CLAUDE_CREDS_JSON
    fi

    cp /host-gitconfig "${HOME}/.gitconfig" 2>/dev/null || true
    mkdir -p "${HOME}/.config/git"
    cp -R /host-git-config/. "${HOME}/.config/git/" 2>/dev/null || true
    mkdir -p "${HOME}/.config/claude" "${HOME}/.config/claude-code"
    cp -an /host-claude-config/. "${HOME}/.config/claude/" 2>/dev/null || true
    cp -an /host-claude-code-config/. "${HOME}/.config/claude-code/" 2>/dev/null || true

    if [ ! -d "${CLAUDE_CONTAINER}/skills" ] || \
       ! find "${CLAUDE_CONTAINER}/skills" -mindepth 1 -maxdepth 1 ! -name ".system" \
           -exec test -e {} \; -print -quit | grep -q .; then
      echo "Bootstrapping skills into ${CLAUDE_CONTAINER}/skills..." >&2
      if ! "${REPO_DIR}/scripts/install.sh" >/tmp/claude-install.log 2>&1; then
        echo "Warning: skill bootstrap failed. Showing install output:" >&2
        cat /tmp/claude-install.log >&2 || true
      fi
    fi

    npm i -g @anthropic-ai/claude-code >/dev/null 2>&1
    exec claude "$@"
  ' _ "$@"
