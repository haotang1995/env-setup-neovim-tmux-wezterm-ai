#!/usr/bin/env bash
# Restore an openclaw-live container from a checkpoint.
#
# Usage:
#   restore-openclaw                    # list available checkpoints
#   restore-openclaw <tag>              # restore from specific checkpoint
#   restore-openclaw --latest           # restore from most recent checkpoint
#   restore-openclaw <tag> [--gpu|--no-gpu]

set -euo pipefail

CONTAINER_NAME="openclaw-live"
VOLUME_NAME="openclaw-home"
CHECKPOINT_DIR="${HOME}/openclaw-checkpoints"
WORKSPACE_HOST="${HOME}/agent-folder-check-security"
WORKSPACE_CONTAINER="/workspace"
USE_GPU="${SANDBOX_GPU:-auto}"

# ── Parse args ────────────────────────────────────────────────────────────
TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest) TAG="__latest__"; shift ;;
    --gpu)    USE_GPU=1; shift ;;
    --no-gpu) USE_GPU=0; shift ;;
    --help|-h)
      echo "Usage: restore-openclaw [--latest | <tag>] [--gpu|--no-gpu]" >&2
      exit 0
      ;;
    *) TAG="$1"; shift ;;
  esac
done

# ── List available checkpoints ────────────────────────────────────────────
list_checkpoints() {
  if [[ ! -d "${CHECKPOINT_DIR}" ]]; then
    echo "No checkpoints found (${CHECKPOINT_DIR} does not exist)." >&2
    return 1
  fi

  local manifests
  manifests="$(find "${CHECKPOINT_DIR}" -name 'manifest-*.txt' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | awk '{print $2}')"

  if [[ -z "${manifests}" ]]; then
    echo "No checkpoints found in ${CHECKPOINT_DIR}." >&2
    return 1
  fi

  echo "Available checkpoints (newest first):"
  echo ""
  while IFS= read -r manifest; do
    local name
    name="$(basename "${manifest}" .txt)"
    name="${name#manifest-}"
    local ts
    ts="$(grep '^timestamp:' "${manifest}" | awk '{print $2}')" 2>/dev/null || true
    printf "  %-30s  %s\n" "${name}" "${ts}"
  done <<< "${manifests}"
  echo ""
  echo "Usage: restore-openclaw <tag>"
}

# If no tag given, list and exit
if [[ -z "${TAG}" ]]; then
  list_checkpoints
  exit 0
fi

# Resolve --latest
if [[ "${TAG}" = "__latest__" ]]; then
  TAG="$(find "${CHECKPOINT_DIR}" -name 'manifest-*.txt' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}')"
  if [[ -z "${TAG}" ]]; then
    echo "No checkpoints found." >&2
    exit 1
  fi
  TAG="$(basename "${TAG}" .txt)"
  TAG="${TAG#manifest-}"
  echo "Latest checkpoint: ${TAG}" >&2
fi

# ── Validate checkpoint exists ────────────────────────────────────────────
IMAGE_TAG="openclaw-snap:${TAG}"
VOLUME_ARCHIVE="${CHECKPOINT_DIR}/volume-${TAG}.tar.gz"

if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "Error: Image '${IMAGE_TAG}' not found." >&2
  echo "Available images:" >&2
  docker images --format '  {{.Repository}}:{{.Tag}}  ({{.CreatedAt}})' \
    | grep 'openclaw-snap:' >&2 || echo "  (none)" >&2
  exit 1
fi

if [[ ! -f "${VOLUME_ARCHIVE}" ]]; then
  echo "Error: Volume archive not found: ${VOLUME_ARCHIVE}" >&2
  exit 1
fi

# ── Confirm ───────────────────────────────────────────────────────────────
echo "Restoring from checkpoint: ${TAG}" >&2
echo "  Image:  ${IMAGE_TAG}" >&2
echo "  Volume: ${VOLUME_ARCHIVE}" >&2

if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "" >&2
  echo "WARNING: This will destroy the current '${CONTAINER_NAME}' container and volume." >&2
  read -rp "Continue? [y/N] " confirm
  if [[ "${confirm}" != [yY] ]]; then
    echo "Aborted." >&2
    exit 1
  fi
fi

# ── GPU auto-detect ───────────────────────────────────────────────────────
if [[ "${USE_GPU}" = "auto" ]]; then
  if docker info --format '{{.Runtimes}}' 2>/dev/null | grep -q nvidia \
     || command -v nvidia-smi &>/dev/null; then
    USE_GPU=1
  else
    USE_GPU=0
  fi
fi

# ── Stop + remove existing container and volume ───────────────────────────
docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
docker volume rm "${VOLUME_NAME}" 2>/dev/null || true

# ── Restore volume from archive ──────────────────────────────────────────
echo "[restore] Restoring volume '${VOLUME_NAME}' from archive..." >&2
docker volume create "${VOLUME_NAME}" >/dev/null
docker run --rm \
  -v "${VOLUME_NAME}:/target" \
  -v "${CHECKPOINT_DIR}:/backup:ro" \
  ubuntu:24.04 \
  tar xzf "/backup/volume-${TAG}.tar.gz" -C /target

# ── Create container from committed image ─────────────────────────────────
echo "[restore] Creating container from ${IMAGE_TAG}..." >&2
mkdir -p "${WORKSPACE_HOST}"

docker_args=(
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

docker run "${docker_args[@]}" "${IMAGE_TAG}" \
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

echo "[restore] Container '${CONTAINER_NAME}' restored and running." >&2
echo "Use 'openclaw-sandbox exec' to attach." >&2
