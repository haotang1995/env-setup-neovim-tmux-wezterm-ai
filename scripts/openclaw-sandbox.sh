#!/usr/bin/env bash
# Long-running OpenClaw development sandbox.
#
# Unlike ai-sandbox.sh (ephemeral, per-session), this container persists for
# months. Auth is managed inside the container. The host exposes only ONE
# folder: ~/agent-folder-check-security → /workspace.
#
# Usage:
#   openclaw-sandbox start   [--rebuild] [--gpu|--no-gpu]  # create or restart
#   openclaw-sandbox stop                                   # stop container
#   openclaw-sandbox exec    [command...]                   # exec into running container
#   openclaw-sandbox status                                 # show container state
#   openclaw-sandbox destroy                                # remove container + volume

set -euo pipefail

# ── Resolve script location ──────────────────────────────────────────────
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
  _dir="$(cd "$(dirname "$_source")" && pwd)"
  _source="$(readlink "$_source")"
  [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd "$(dirname "$_source")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Constants ─────────────────────────────────────────────────────────────
CONTAINER_NAME="openclaw-live"
IMAGE_NAME="openclaw-sandbox:latest"
VOLUME_NAME="openclaw-home"
WORKSPACE_HOST="${HOME}/agent-folder-check-security"
WORKSPACE_CONTAINER="/workspace"
DOCKERFILE="${SCRIPT_DIR}/openclaw-sandbox.Dockerfile"
CHECKPOINT_SCRIPT="${SCRIPT_DIR}/checkpoint-openclaw.sh"

# ── Flags ─────────────────────────────────────────────────────────────────
FORCE_REBUILD=0
USE_GPU="${SANDBOX_GPU:-auto}"
ACTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    start|stop|exec|status|destroy) ACTION="$1"; shift ;;
    --rebuild) FORCE_REBUILD=1; shift ;;
    --gpu)     USE_GPU=1; shift ;;
    --no-gpu)  USE_GPU=0; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if [[ -z "${ACTION}" ]]; then
  echo "Usage: openclaw-sandbox <start|stop|exec|status|destroy> [--rebuild] [--gpu|--no-gpu]" >&2
  exit 1
fi

# ── GPU auto-detect ───────────────────────────────────────────────────────
resolve_gpu() {
  if [[ "${USE_GPU}" = "auto" ]]; then
    if docker info --format '{{.Runtimes}}' 2>/dev/null | grep -q nvidia \
       || command -v nvidia-smi &>/dev/null; then
      USE_GPU=1
    else
      USE_GPU=0
    fi
  fi
}

# ── Build image if needed ─────────────────────────────────────────────────
build_image() {
  if [[ "${FORCE_REBUILD}" = "1" ]] || ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "Building ${IMAGE_NAME}..." >&2
    local build_flags=(-t "${IMAGE_NAME}" -f "${DOCKERFILE}")
    [[ "${FORCE_REBUILD}" = "1" ]] && build_flags+=(--no-cache)
    docker build "${build_flags[@]}" "${REPO_DIR}"
  fi
}

# ── Install checkpoint cron ───────────────────────────────────────────────
install_checkpoint_cron() {
  local cron_line="0 */6 * * * ${CHECKPOINT_SCRIPT} >> \${HOME}/openclaw-checkpoints/cron.log 2>&1"
  if crontab -l 2>/dev/null | grep -qF "checkpoint-openclaw.sh"; then
    return 0
  fi
  echo "Installing checkpoint cron (every 6 hours)..." >&2
  ( crontab -l 2>/dev/null || true; echo "${cron_line}" ) | crontab -
  echo "Cron installed. Checkpoints go to ~/openclaw-checkpoints/" >&2
}

# ── Actions ───────────────────────────────────────────────────────────────

do_start() {
  # If container exists and is running, just attach info
  if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    local state
    state="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}")"
    if [[ "${state}" = "running" ]]; then
      echo "Container '${CONTAINER_NAME}' is already running." >&2
      echo "Use 'openclaw-sandbox exec' to attach." >&2
      return 0
    fi
    # Stopped — restart it
    echo "Restarting stopped container '${CONTAINER_NAME}'..." >&2
    docker start "${CONTAINER_NAME}"
    echo "Container restarted. Use 'openclaw-sandbox exec' to attach." >&2
    return 0
  fi

  # Fresh start — build image, create host workspace, create container
  build_image
  resolve_gpu
  mkdir -p "${WORKSPACE_HOST}"

  local docker_args=(
    -d
    -u root
    --name "${CONTAINER_NAME}"
    --hostname openclaw
    -v "${VOLUME_NAME}:/home/claw"
    -v "${WORKSPACE_HOST}:${WORKSPACE_CONTAINER}"
    -w "${WORKSPACE_CONTAINER}"
    -e TERM="${TERM:-xterm-256color}"
    -e COLORTERM="${COLORTERM:-truecolor}"
    -e HOST_UID="$(id -u)"
    -e HOST_GID="$(id -g)"
    --restart unless-stopped
  )

  if [[ "${USE_GPU}" = "1" ]]; then
    docker_args+=(--gpus all)
    echo "GPU passthrough enabled (--gpus all)" >&2
  fi

  docker run "${docker_args[@]}" "${IMAGE_NAME}" \
    bash -c '
      _UID="${HOST_UID:-1000}"
      _GID="${HOST_GID:-1000}"
      if [ "${_UID}" != "1000" ] || [ "${_GID}" != "1000" ]; then
        groupmod -g "${_GID}" claw 2>/dev/null || true
        usermod -u "${_UID}" -g "${_GID}" claw 2>/dev/null || true
        chown -R "${_UID}:${_GID}" /home/claw 2>/dev/null || true
      fi
      git config --global --add safe.directory /workspace 2>/dev/null || true
      exec setpriv --reuid="${_UID}" --regid="${_GID}" --init-groups -- sleep infinity
    '

  install_checkpoint_cron

  echo "Container '${CONTAINER_NAME}' started." >&2
  echo "Run 'openclaw-sandbox exec' to get a shell inside." >&2
}

do_stop() {
  if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "Container '${CONTAINER_NAME}' does not exist." >&2
    return 1
  fi
  echo "Stopping '${CONTAINER_NAME}'..." >&2
  docker stop "${CONTAINER_NAME}"
}

do_exec() {
  if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "Container '${CONTAINER_NAME}' does not exist. Run 'openclaw-sandbox start' first." >&2
    return 1
  fi
  local state
  state="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}")"
  if [[ "${state}" != "running" ]]; then
    echo "Container '${CONTAINER_NAME}' is ${state}. Run 'openclaw-sandbox start' first." >&2
    return 1
  fi
  if [[ $# -gt 0 ]]; then
    exec docker exec -it -u claw "${CONTAINER_NAME}" "$@"
  else
    exec docker exec -it -u claw "${CONTAINER_NAME}" bash
  fi
}

do_status() {
  if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "Container '${CONTAINER_NAME}' does not exist." >&2
    return 0
  fi
  docker inspect -f 'Name:    {{.Name}}
State:   {{.State.Status}}
Started: {{.State.StartedAt}}
Image:   {{.Config.Image}}
Mounts:  {{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}})
         {{end}}' "${CONTAINER_NAME}"
}

do_destroy() {
  if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    echo "Container '${CONTAINER_NAME}' does not exist." >&2
    return 0
  fi
  echo "This will remove container '${CONTAINER_NAME}' and volume '${VOLUME_NAME}'." >&2
  read -rp "Are you sure? [y/N] " confirm
  if [[ "${confirm}" != [yY] ]]; then
    echo "Aborted." >&2
    return 1
  fi
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
  docker volume rm "${VOLUME_NAME}" 2>/dev/null || true
  echo "Destroyed." >&2
}

# ── Dispatch ──────────────────────────────────────────────────────────────
case "${ACTION}" in
  start)   do_start ;;
  stop)    do_stop ;;
  exec)    do_exec "$@" ;;
  status)  do_status ;;
  destroy) do_destroy ;;
esac
