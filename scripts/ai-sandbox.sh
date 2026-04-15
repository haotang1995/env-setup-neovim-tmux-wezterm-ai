#!/usr/bin/env bash
# Unified AI sandbox — launch Claude Code, Gemini CLI, Codex, or Copilot CLI
# inside a Docker container scoped to the current directory.
#
# Usage:
#   ai-sandbox [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] <agent> [agent args...]
#   claude-sandbox [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] [args...]   (via compat symlink)
#   gemini-sandbox [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] [args...]
#   codex-sandbox  [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] [args...]
#   copilot-sandbox [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] [args...]
#
# GPU: auto-detected by default (enabled when NVIDIA Container Toolkit is
#      available). Override with --gpu / --no-gpu or SANDBOX_GPU=1|0.
#      Use --gpu-device ID (or SANDBOX_GPU_DEVICE=ID) to pass through a
#      specific GPU instead of all (e.g. --gpu-device 0). Implies --gpu.

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

# ── Flags ────────────────────────────────────────────────────────────────
FORCE_REBUILD="${SANDBOX_REBUILD:-0}"
USE_GPU="${SANDBOX_GPU:-auto}"
GPU_DEVICE="${SANDBOX_GPU_DEVICE:-}"
# claude only: --no-login seeds OAuth credentials from the host so the
# container does not require /login. Side effect: container shares the host's
# refresh-token chain, which Anthropic rotates ~every 11h; the container will
# typically need re-auth within ~1 day (suitable for short jobs). Default
# (no flag) skips the credential copy: the container holds its own
# OAuth grant that survives multi-day sessions.
NO_LOGIN="${SANDBOX_NO_LOGIN:-0}"
# claude only: per-workspace volume name. Defaults to the sanitized basename
# of PWD so two sandboxes in different projects get independent OAuth grants
# (avoids two containers racing on the same refresh-token chain inside a
# shared claude-home volume). Override with --workspace NAME when two
# projects have the same basename or you want to force shared state.
WORKSPACE_NAME="${SANDBOX_WORKSPACE:-}"

while [[ "${1:-}" = --* ]]; do
  case "$1" in
    --rebuild)    FORCE_REBUILD=1; shift ;;
    --gpu)        USE_GPU=1; shift ;;
    --no-gpu)     USE_GPU=0; shift ;;
    --gpu-device) GPU_DEVICE="${2:?--gpu-device requires an ID (e.g. 0)}"; USE_GPU=1; shift 2 ;;
    --no-login)   NO_LOGIN=1; shift ;;
    --workspace)  WORKSPACE_NAME="${2:?--workspace requires a name}"; shift 2 ;;
    *) break ;;
  esac
done

# Default workspace = sanitized basename of PWD (Docker volume names: [a-zA-Z0-9_.-])
if [[ -z "${WORKSPACE_NAME}" ]]; then
  _wsbase="$(basename "${PWD}")"
  _wsbase="$(printf '%s' "${_wsbase}" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9_.-]/-/g; s/--*/-/g; s/^[-.]*//; s/-*$//')"
  WORKSPACE_NAME="${_wsbase:-default}"
fi

# GPU_DEVICE (from flag or env) implies --gpu
[[ -n "${GPU_DEVICE}" ]] && USE_GPU=1

# ── Agent selection ──────────────────────────────────────────────────────
# Priority: explicit first arg > basename detection > error
AGENT=""
INVOKED_AS="$(basename "$0")"

case "${INVOKED_AS}" in
  claude-sandbox)  AGENT="claude"  ;;
  gemini-sandbox)  AGENT="gemini"  ;;
  codex-sandbox)   AGENT="codex"   ;;
  copilot-sandbox) AGENT="copilot" ;;
esac

if [[ -z "${AGENT}" ]]; then
  case "${1:-}" in
    claude|gemini|codex|copilot) AGENT="$1"; shift ;;
    *)
      echo "Usage: ai-sandbox [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] [--no-login] [--workspace NAME] <claude|gemini|codex|copilot> [args...]" >&2
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
    # Per-workspace volume: prevents two claude sandboxes in different
    # projects from sharing one OAuth grant and racing on refresh-token
    # rotation. One /login per workspace volume, independent thereafter.
    AGENT_HOME_VOL="claude-home-${WORKSPACE_NAME}"
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
  copilot)
    AGENT_HOST="${HOME}/.copilot"
    AGENT_CONTAINER="/root/.copilot"
    AGENT_HOME_VOL="copilot-home"
    AGENT_CMD="copilot"
    AGENT_NPM_PKG="@github/copilot"
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
  SANDBOX_IMAGE="ai-sandbox:w$(( $(date +%V) % 2 ))"
else
  dockerfile_hash="$(sha256sum "${DOCKERFILE_PATH}" | awk '{print substr($1,1,12)}')"
  SANDBOX_IMAGE="ai-sandbox:custom-${dockerfile_hash}"
fi

echo "Using sandbox image: ${SANDBOX_IMAGE}" >&2
if [[ "${AGENT}" = "claude" ]]; then
  echo "Using workspace: ${WORKSPACE_NAME} (volume: ${AGENT_HOME_VOL})" >&2
fi

if [[ "${FORCE_REBUILD}" = "1" ]] || ! docker image inspect "${SANDBOX_IMAGE}" >/dev/null 2>&1; then
  build_flags=(-q -t "${SANDBOX_IMAGE}" -f "${DOCKERFILE_PATH}")
  [[ "${FORCE_REBUILD}" = "1" ]] && build_flags+=(--no-cache)
  docker build "${build_flags[@]}" "${BUILD_CONTEXT}" >/dev/null
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
  -e HOST_UID="$(id -u)"
  -e HOST_GID="$(id -g)"
  -e NO_LOGIN="${NO_LOGIN}"
)

# Worktree support: mount external git metadata paths when /workspace/.git
# points outside the current directory.
if git -C "${PWD}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_dir_abs="$(cd "${PWD}" && cd "$(git rev-parse --git-dir)" && pwd -P)"
  git_common_dir_abs="$(cd "${PWD}" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"

  if [[ -n "${git_dir_abs}" && -d "${git_dir_abs}" ]]; then
    docker_args+=(--mount "type=bind,src=${git_dir_abs},dst=${git_dir_abs}")
  fi
  if [[ -n "${git_common_dir_abs}" && -d "${git_common_dir_abs}" && "${git_common_dir_abs}" != "${git_dir_abs}" ]]; then
    docker_args+=(--mount "type=bind,src=${git_common_dir_abs},dst=${git_common_dir_abs}")
  fi
fi

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

# Azure CLI profile (all agents) — bind-mount read-only so AzureCliCredential()
# inside the container reuses the host's `az login` session (MSAL token cache,
# active subscription). The entrypoint copies it into ${HOME}/.azure so `az`
# refresh writes stay inside the container and never mutate the host profile.
# Primarily needed for TRAPI (api://trapi/.default) and any other Azure AD
# OAuth scope.
if [[ -d "${HOME}/.azure" ]]; then
  docker_args+=(--mount "type=bind,src=${HOME}/.azure,dst=/host-azure,readonly")
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

# ── Codex-specific extras ───────────────────────────────────────────────
if [[ "${AGENT}" = "codex" ]]; then
  # Sync chat history to host: sessions/ (transcripts) and history.jsonl
  # (prompt history). Auth (auth.json) and settings (config.toml) stay
  # read-only via /host-agent-home and are copied in at startup.
  mkdir -p "${HOME}/.codex/sessions"
  [[ -f "${HOME}/.codex/history.jsonl" ]] || : > "${HOME}/.codex/history.jsonl"
  docker_args+=(
    -v "${HOME}/.codex/sessions:${AGENT_CONTAINER}/sessions"
    -v "${HOME}/.codex/history.jsonl:${AGENT_CONTAINER}/history.jsonl"
  )
fi

# ── Copilot-specific extras ──────────────────────────────────────────────
if [[ "${AGENT}" = "copilot" ]]; then
  # Resolve a GitHub token from available sources (first wins):
  #   1) GITHUB_TOKEN / GH_TOKEN already in env
  #   2) macOS Keychain (service "copilot-cli")
  #   3) gh auth token (GitHub CLI)
  _GH_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

  if [[ -z "${_GH_TOKEN}" ]] && command -v security &>/dev/null; then
    _GH_TOKEN="$(security find-generic-password -s "copilot-cli" -w 2>/dev/null || true)"
  fi

  if [[ -z "${_GH_TOKEN}" ]] && command -v gh &>/dev/null; then
    _GH_TOKEN="$(gh auth token 2>/dev/null || true)"
  fi

  if [[ -n "${_GH_TOKEN}" ]]; then
    docker_args+=(-e "GITHUB_TOKEN=${_GH_TOKEN}")
  fi

  if [[ -n "${COPILOT_HOME:-}" ]]; then
    docker_args+=(-e "COPILOT_HOME")
  fi
fi

# ── W&B (Weights & Biases) passthrough (all agents) ─────────────────────
# Resolve token: WANDB_KEY > WANDB_TOKEN > WANDB_API_KEY > ~/.bashrc extraction
_WANDB_TOKEN="${WANDB_KEY:-${WANDB_TOKEN:-${WANDB_API_KEY:-}}}"

if [[ -z "${_WANDB_TOKEN}" ]]; then
  for _var in WANDB_KEY WANDB_TOKEN; do
    _WANDB_TOKEN="$(grep -oP "^export ${_var}=\\K.*" "${HOME}/.bashrc" 2>/dev/null | tail -1 | tr -d "\"'" || true)"
    [[ -n "${_WANDB_TOKEN}" ]] && break
  done
fi

if [[ -n "${_WANDB_TOKEN}" ]]; then
  # WANDB_API_KEY is what the wandb Python library reads; WANDB_KEY is the
  # Microsoft Research convention. Pass both so either path works.
  docker_args+=(-e "WANDB_API_KEY=${_WANDB_TOKEN}" -e "WANDB_KEY=${_WANDB_TOKEN}")
fi

# Default to Microsoft Research self-hosted instance
docker_args+=(-e "WANDB_BASE_URL=${WANDB_BASE_URL:-https://microsoft-research.wandb.io}")

for env_name in WANDB_PROJECT WANDB_ENTITY WANDB_RUN_GROUP WANDB_MODE; do
  if [[ -n "${!env_name:-}" ]]; then
    docker_args+=(-e "${env_name}")
  fi
done

# ── Hugging Face passthrough (all agents) ────────────────────────────────
# Resolve token: HF_TOKEN > HUGGING_FACE_HUB_TOKEN > HUGGINGFACE_TOKEN > ~/.bashrc extraction
_HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-${HUGGINGFACE_TOKEN:-}}}"

if [[ -z "${_HF_TOKEN}" ]]; then
  for _var in HF_TOKEN HUGGING_FACE_HUB_TOKEN HUGGINGFACE_TOKEN; do
    _HF_TOKEN="$(grep -oP "^export ${_var}=\\K.*" "${HOME}/.bashrc" 2>/dev/null | tail -1 | tr -d "\"'" || true)"
    [[ -n "${_HF_TOKEN}" ]] && break
  done
fi

if [[ -n "${_HF_TOKEN}" ]]; then
  # HF_TOKEN is the modern env var; HUGGING_FACE_HUB_TOKEN is the legacy name
  # still read by huggingface_hub. Pass both so either path works.
  docker_args+=(-e "HF_TOKEN=${_HF_TOKEN}" -e "HUGGING_FACE_HUB_TOKEN=${_HF_TOKEN}")
fi

for env_name in HF_HOME HF_HUB_CACHE HF_ENDPOINT; do
  if [[ -n "${!env_name:-}" ]]; then
    docker_args+=(-e "${env_name}")
  fi
done

# ── GPU passthrough ──────────────────────────────────────────────────────
# Auto-detect: enable GPU if nvidia-container-runtime or nvidia-smi is available.
if [[ "${USE_GPU}" = "auto" ]]; then
  if docker info --format '{{.Runtimes}}' 2>/dev/null | grep -q nvidia \
     || command -v nvidia-smi &>/dev/null; then
    USE_GPU=1
  else
    USE_GPU=0
  fi
fi

if [[ "${USE_GPU}" = "1" ]]; then
  if [[ -n "${GPU_DEVICE}" ]]; then
    docker_args+=(--gpus "device=${GPU_DEVICE}")
    echo "GPU passthrough enabled (--gpus device=${GPU_DEVICE})" >&2
  else
    docker_args+=(--gpus all)
    echo "GPU passthrough enabled (--gpus all)" >&2
  fi
  # NVIDIA recommends these for PyTorch: shared memory, locked memory, stack size
  docker_args+=(--ipc=host --ulimit memlock=-1 --ulimit stack=67108864)
fi

# ── Run container ────────────────────────────────────────────────────────
exec docker run "${docker_args[@]}" \
  "${SANDBOX_IMAGE}" \
  bash -c '
    mkdir -p "${AGENT_CONTAINER}"

    # ── Per-agent auth/config sync ──
    case "${AGENT}" in
      claude)
        # -L dereferences symlinks (install.sh creates symlinks in host agent dirs)
        # Seed non-auth files only when missing (no-clobber). Credential
        # files are excluded here so the default mode never accidentally
        # bootstraps a shared OAuth grant; --no-login handles them below.
        for _src in /host-agent-home/.[!.]* /host-agent-home/*; do
          [ -e "$_src" ] || continue
          case "$(basename "$_src")" in
            .credentials.json|credentials.json) continue ;;
          esac
          cp -anL "$_src" "${AGENT_CONTAINER}/" 2>/dev/null || true
        done

        if [ "${NO_LOGIN:-0}" = "1" ]; then
          # --no-login: copy host OAuth credentials into the container so the
          # user is not prompted for /login. Container will share the host'\''s
          # refresh-token chain; Anthropic rotates these and the container
          # typically loses auth within ~1 day. Suitable for short jobs.
          cp -aL /host-claude-json "${HOME}/.claude.json" 2>/dev/null || true
          for _f in .credentials.json credentials.json; do
            [ -f "/host-agent-home/${_f}" ] && \
              cp -aL "/host-agent-home/${_f}" "${AGENT_CONTAINER}/${_f}" 2>/dev/null || true
          done

          # Keychain-extracted credentials (macOS) override the file-based copy
          if [ -n "${_CLAUDE_CREDS_JSON:-}" ]; then
            printf "%s" "${_CLAUDE_CREDS_JSON}" > "${AGENT_CONTAINER}/.credentials.json"
            chmod 600 "${AGENT_CONTAINER}/.credentials.json"
            unset _CLAUDE_CREDS_JSON
          fi
        else
          # Default: do not seed OAuth credentials. Container has its own
          # OAuth grant living in the claude-home volume; first launch
          # prompts /login (once per volume), subsequent launches reuse it.
          # .claude.json is non-auth (user prefs + project index) — seed it
          # only when /root has none yet so claude can start cleanly.
          [ ! -f "${HOME}/.claude.json" ] && \
            cp -aL /host-claude-json "${HOME}/.claude.json" 2>/dev/null || true
          unset _CLAUDE_CREDS_JSON
        fi

        mkdir -p "${HOME}/.config/claude" "${HOME}/.config/claude-code"
        cp -aL /host-claude-config/. "${HOME}/.config/claude/" 2>/dev/null || true
        cp -aL /host-claude-code-config/. "${HOME}/.config/claude-code/" 2>/dev/null || true
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
      copilot)
        # Seed non-auth files only when missing (no-clobber).
        # config.json holds auth tokens (no keychain in Docker), so never overwrite.
        cp -anL /host-agent-home/. "${AGENT_CONTAINER}/" 2>/dev/null || true
        # MCP config is pure settings — always refresh from host.
        cp /host-agent-home/mcp-config.json "${AGENT_CONTAINER}/" 2>/dev/null || true

        # Merge host config keys (model, banner, etc.) into container config
        # without clobbering auth tokens already present.
        if [ -f "/host-agent-home/config.json" ]; then
          node -e '\''
            const fs = require("fs");
            const hostF = process.argv[1], contF = process.argv[2];
            let host = {}, cont = {};
            try { host = JSON.parse(fs.readFileSync(hostF, "utf8")); } catch {}
            try { cont = JSON.parse(fs.readFileSync(contF, "utf8")); } catch {}
            const merged = { ...host, ...cont };
            fs.writeFileSync(contF, JSON.stringify(merged, null, 2) + "\n");
          '\'' "/host-agent-home/config.json" "${AGENT_CONTAINER}/config.json" \
            2>/dev/null || true
        fi

        ;;
    esac

    # ── Git config (shared) ──
    cp /host-gitconfig "${HOME}/.gitconfig" 2>/dev/null || true
    mkdir -p "${HOME}/.config/git"
    cp -R /host-git-config/. "${HOME}/.config/git/" 2>/dev/null || true

    # ── Azure CLI profile (shared) ──
    # Host ~/.azure is bind-mounted read-only at /host-azure; copy it into
    # the container so `az` (and AzureCliCredential via Python) can refresh
    # tokens in-place without mutating the host profile.
    if [ -d /host-azure ]; then
      mkdir -p "${HOME}/.azure"
      cp -R /host-azure/. "${HOME}/.azure/" 2>/dev/null || true
      chmod 700 "${HOME}/.azure" 2>/dev/null || true
      find "${HOME}/.azure" -type f -name "*token*" -exec chmod 600 {} + 2>/dev/null || true
    fi

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

    # Allow Git operations in bind-mounted repositories with differing ownership.
    git config --global --add safe.directory /workspace 2>/dev/null || true

    # ── Helper: create non-root user matching host UID/GID ──
    _ensure_host_user() {
      _UID="${HOST_UID:-1000}"
      _GID="${HOST_GID:-1000}"

      if ! getent group "${_GID}" >/dev/null 2>&1; then
        groupadd -g "${_GID}" hostgroup 2>/dev/null || true
      fi
      _EXISTING_USER="$(getent passwd 1000 | cut -d: -f1)"
      if [ "${_UID}" = "1000" ]; then
        : # pre-built sandbox user already matches
      elif [ -n "${_EXISTING_USER}" ]; then
        # Remap the pre-built sandbox user to the host UID/GID
        usermod -u "${_UID}" -g "${_GID}" -s /bin/bash "${_EXISTING_USER}" 2>/dev/null || true
      else
        useradd -M -u "${_UID}" -g "${_GID}" -s /bin/bash sandbox 2>/dev/null || true
      fi

      chmod 755 /root 2>/dev/null || true
      chown -R "${_UID}:${_GID}" "${AGENT_CONTAINER}" 2>/dev/null || true
    }

    # ── Launch ──
    case "${AGENT}" in
      claude)
        # Drop to a non-root user matching the host UID so bind-mounted
        # files keep their original ownership (Claude also refuses
        # --dangerously-skip-permissions as root).
        _ensure_host_user
        chown -R "${_UID}:${_GID}" /root/.config /root/.local /root/.cache /root/.azure 2>/dev/null || true
        [ -f "${HOME}/.claude.json" ] && chown "${_UID}:${_GID}" "${HOME}/.claude.json" 2>/dev/null || true
        exec setpriv --reuid="${_UID}" --regid="${_GID}" --init-groups -- \
          claude --dangerously-skip-permissions "$@"
        ;;
      gemini)  exec gemini --sandbox false --yolo "$@" ;;
      codex)
        _ensure_host_user
        mkdir -p /root/.cache 2>/dev/null || true
        chown -R "${_UID}:${_GID}" /root/.cache /root/.azure 2>/dev/null || true
        exec setpriv --reuid="${_UID}" --regid="${_GID}" --init-groups -- \
          codex --sandbox danger-full-access "$@"
        ;;
      copilot)
        _ensure_host_user
        mkdir -p /root/.cache 2>/dev/null || true
        chown -R "${_UID}:${_GID}" /root/.cache /root/.azure 2>/dev/null || true
        exec setpriv --reuid="${_UID}" --regid="${_GID}" --init-groups -- \
          copilot --yolo "$@"
        ;;
    esac
  ' _ "$@"
