#!/usr/bin/env bash
# Unified AI sandbox — launch Claude Code, Gemini CLI, or Codex inside a
# Docker container scoped to the current directory.
#
# Usage:
#   ai-sandbox <agent> [agent args...]    (agent = claude | gemini | codex)
#   claude-sandbox [args...]              (via compat symlink)
#   gemini-sandbox [args...]
#   codex-sandbox  [args...]

set -euo pipefail

# Resolve symlinks so REPO_DIR is correct when invoked via compat symlinks
# (e.g. ~/.local/bin/codex-sandbox -> .../scripts/ai-sandbox.sh)
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
  _dir="$(cd "$(dirname "$_source")" && pwd)"
  _source="$(readlink "$_source")"
  [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
REPO_DIR="$(cd "$(dirname "$_source")/.." && pwd)"

# ── Agent selection ──────────────────────────────────────────────────────
# Priority: explicit first arg > basename detection > error
AGENT=""
INVOKED_AS="$(basename "$0")"

case "${INVOKED_AS}" in
  claude-sandbox) AGENT="claude" ;;
  gemini-sandbox) AGENT="gemini" ;;
  codex-sandbox)  AGENT="codex"  ;;
esac

if [[ -z "${AGENT}" ]]; then
  case "${1:-}" in
    claude|gemini|codex) AGENT="$1"; shift ;;
    *)
      echo "Usage: ai-sandbox <claude|gemini|codex> [args...]" >&2
      exit 1
      ;;
  esac
fi

# ── Per-agent config ─────────────────────────────────────────────────────
AGENT_HOST=""
AGENT_CONTAINER=""
AGENT_HOME_VOL=""
AGENT_CMD=""
AGENT_NPM_PKG=""

case "${AGENT}" in
  claude)
    AGENT_HOST="${HOME}/.claude"
    AGENT_CONTAINER="/root/.claude"
    AGENT_HOME_VOL="claude-home"
    AGENT_CMD="claude"
    AGENT_NPM_PKG="@anthropic-ai/claude-code"
    ;;
  gemini)
    AGENT_HOST="${HOME}/.gemini"
    AGENT_CONTAINER="/root/.gemini"
    AGENT_HOME_VOL="gemini-home"
    AGENT_CMD="gemini"
    AGENT_NPM_PKG="@google/gemini-cli"
    ;;
  codex)
    AGENT_HOST="${HOME}/.codex"
    AGENT_CONTAINER="/root/.codex"
    AGENT_HOME_VOL="codex-home"
    AGENT_CMD="codex"
    AGENT_NPM_PKG="@openai/codex"
    ;;
esac

# ── Dockerfile / image selection ─────────────────────────────────────────
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
# 3) repository default scripts/ai-sandbox.Dockerfile
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
  DOCKERFILE_PATH="${REPO_DIR}/scripts/ai-sandbox.Dockerfile"
  BUILD_CONTEXT="${REPO_DIR}"
fi

if [[ -n "${SANDBOX_IMAGE:-}" ]]; then
  SANDBOX_IMAGE="${SANDBOX_IMAGE}"
elif [[ "${DOCKERFILE_SOURCE}" = "default" ]]; then
  SANDBOX_IMAGE="ai-sandbox:node22"
else
  dockerfile_hash="$(sha256sum "${DOCKERFILE_PATH}" | awk '{print substr($1,1,12)}')"
  SANDBOX_IMAGE="ai-sandbox:custom-${dockerfile_hash}"
fi

echo "Using sandbox image: ${SANDBOX_IMAGE}" >&2

if ! docker image inspect "${SANDBOX_IMAGE}" >/dev/null 2>&1; then
  docker build -q \
    -t "${SANDBOX_IMAGE}" \
    -f "${DOCKERFILE_PATH}" \
    "${BUILD_CONTEXT}" >/dev/null
fi

# ── Docker args (shared) ─────────────────────────────────────────────────
docker_args=(
  --rm -it
  -v "${PWD}:/workspace"
  -v "${AGENT_HOME_VOL}:${AGENT_CONTAINER}"
  -v "${REPO_DIR}:${REPO_DIR}:ro"
  -v ai-sandbox-npm-cache:/root/.npm
  --mount "type=bind,src=${AGENT_HOST},dst=/host-agent-home,readonly"
  -w /workspace
  -e HOME=/root
  -e TERM="${TERM:-xterm-256color}"
  -e COLORTERM="${COLORTERM:-truecolor}"
  -e AGENT="${AGENT}"
  -e AGENT_CONTAINER="${AGENT_CONTAINER}"
  -e AGENT_NPM_PKG="${AGENT_NPM_PKG}"
  -e REPO_DIR="${REPO_DIR}"
)

# Gemini: suppress auto-update (CLIs are pre-installed in the image;
# in-place npm updates corrupt the binary and crash on restart).
if [[ "${AGENT}" = "gemini" ]]; then
  docker_args+=(-e NO_UPDATE_NOTIFIER=1 -e GEMINI_AUTO_UPDATE=false)
fi

# Git config mounts (all agents)
if [[ -f "${HOME}/.gitconfig" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.gitconfig,dst=/host-gitconfig,readonly")
fi
if [[ -d "${HOME}/.config/git" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.config/git,dst=/host-git-config,readonly")
fi

# ── Claude-specific extras ───────────────────────────────────────────────
if [[ "${AGENT}" = "claude" ]]; then
  docker_args+=(
    -v claude-config:/root/.config
    -v claude-local-share:/root/.local/share
  )

  if [[ -f "${HOME}/.claude.json" ]]; then
    docker_args+=(--mount "type=bind,src=${HOME}/.claude.json,dst=/host-claude-json,readonly")
  fi
  if [[ -d "${HOME}/.config/claude" ]]; then
    docker_args+=(--mount "type=bind,src=${HOME}/.config/claude,dst=/host-claude-config,readonly")
  fi
  if [[ -d "${HOME}/.config/claude-code" ]]; then
    docker_args+=(--mount "type=bind,src=${HOME}/.config/claude-code,dst=/host-claude-code-config,readonly")
  fi

  # macOS Keychain credential extraction
  _CLAUDE_CREDS_JSON=""
  if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] && command -v security &>/dev/null; then
    _CLAUDE_CREDS_JSON="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
    if [[ -n "${_CLAUDE_CREDS_JSON}" ]]; then
      docker_args+=(-e "_CLAUDE_CREDS_JSON=${_CLAUDE_CREDS_JSON}")
    fi
  fi

  # Pass through common auth/environment overrides
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
fi

# ── Run container ────────────────────────────────────────────────────────
exec docker run "${docker_args[@]}" \
  "${SANDBOX_IMAGE}" \
  bash -c '
    mkdir -p "${AGENT_CONTAINER}"

    # ── Per-agent auth/config sync ──
    case "${AGENT}" in
      claude)
        # Seed only when files are missing (do not overwrite container state)
        # -L dereferences symlinks (install.sh creates symlinks in host agent dirs)
        cp -anL /host-agent-home/. "${AGENT_CONTAINER}/" 2>/dev/null || true
        cp -anL /host-claude-json "${HOME}/.claude.json" 2>/dev/null || true

        # Write Keychain-extracted credentials
        if [ -n "${_CLAUDE_CREDS_JSON:-}" ]; then
          printf "%s" "${_CLAUDE_CREDS_JSON}" > "${AGENT_CONTAINER}/.credentials.json"
          chmod 600 "${AGENT_CONTAINER}/.credentials.json"
          unset _CLAUDE_CREDS_JSON
        fi

        mkdir -p "${HOME}/.config/claude" "${HOME}/.config/claude-code"
        cp -an /host-claude-config/. "${HOME}/.config/claude/" 2>/dev/null || true
        cp -an /host-claude-code-config/. "${HOME}/.config/claude-code/" 2>/dev/null || true
        ;;
      gemini)
        # Keep Gemini auth/config in sync with host, including nested files
        # -L dereferences symlinks (install.sh creates symlinks in host agent dirs)
        cp -aL /host-agent-home/. "${AGENT_CONTAINER}/" 2>/dev/null || true
        # Patch settings: remove macOS-only sandbox-exec, disable auto-update
        if [ -f "${AGENT_CONTAINER}/settings.json" ]; then
          node -e '\''
            const fs = require("fs");
            const f = process.argv[1];
            const j = JSON.parse(fs.readFileSync(f, "utf8"));
            if (j.tools) delete j.tools.sandbox;
            if (!j.general) j.general = {};
            j.general.autoUpdate = false;
            fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n");
          '\'' "${AGENT_CONTAINER}/settings.json" 2>/dev/null || true
        fi
        ;;
      codex)
        # Always refresh OAuth + config from host (tokens expire)
        cp /host-agent-home/auth.json "${AGENT_CONTAINER}/" 2>/dev/null || true
        cp /host-agent-home/config.toml "${AGENT_CONTAINER}/" 2>/dev/null || true
        # Migrate legacy nested skills path
        if [ -d "${AGENT_CONTAINER}/.codex/skills" ]; then
          mkdir -p "${AGENT_CONTAINER}/skills"
          cp -a "${AGENT_CONTAINER}/.codex/skills/." "${AGENT_CONTAINER}/skills/" 2>/dev/null || true
        fi
        ;;
    esac

    # ── Git config (shared) ──
    cp /host-gitconfig "${HOME}/.gitconfig" 2>/dev/null || true
    mkdir -p "${HOME}/.config/git"
    cp -R /host-git-config/. "${HOME}/.config/git/" 2>/dev/null || true

    # ── Skill bootstrap (shared) ──
    if [ ! -d "${AGENT_CONTAINER}/skills" ] || \
       ! find "${AGENT_CONTAINER}/skills" -mindepth 1 -maxdepth 1 ! -name ".system" \
           -exec test -e {} \; -print -quit | grep -q .; then
      echo "Bootstrapping skills into ${AGENT_CONTAINER}/skills..." >&2
      if ! "${REPO_DIR}/scripts/install.sh" >/tmp/install.log 2>&1; then
        echo "Warning: skill bootstrap failed. Showing install output:" >&2
        cat /tmp/install.log >&2 || true
      fi
    fi

    # ── Fallback npm install (custom Dockerfiles without pre-installed CLIs) ──
    if ! command -v "${AGENT}" >/dev/null 2>&1; then
      npm i -g "${AGENT_NPM_PKG}" >/dev/null 2>&1
    fi

    # ── Launch ──
    case "${AGENT}" in
      claude)
        # Claude refuses --dangerously-skip-permissions as root;
        # drop to the sandbox user (uid 1000, created in Dockerfile).
        chmod 755 /root 2>/dev/null || true
        chown -R 1000:1000 "${AGENT_CONTAINER}" /workspace \
          /root/.config /root/.local 2>/dev/null || true
        [ -f "${HOME}/.claude.json" ] && chown 1000:1000 "${HOME}/.claude.json" 2>/dev/null || true
        git config --global --add safe.directory /workspace 2>/dev/null || true
        exec setpriv --reuid=1000 --regid=1000 --init-groups -- \
          claude --dangerously-skip-permissions "$@"
        ;;
      gemini) exec gemini --sandbox false --yolo "$@" ;;
      codex)  exec codex --sandbox danger-full-access "$@" ;;
    esac
  ' _ "$@"
