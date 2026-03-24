#!/usr/bin/env bash
# Checkpoint the openclaw-live container: commit image + backup volume.
# Designed to run unattended via cron (installed by openclaw-sandbox start).
#
# Usage:
#   checkpoint-openclaw              # auto-generate timestamped tag
#   checkpoint-openclaw my-milestone # use custom tag suffix
#
# Stores snapshots in ~/openclaw-checkpoints/. Prunes snapshots older than
# 30 days by default (override with CHECKPOINT_KEEP_DAYS).

set -euo pipefail

CONTAINER_NAME="openclaw-live"
VOLUME_NAME="openclaw-home"
CHECKPOINT_DIR="${HOME}/openclaw-checkpoints"
KEEP_DAYS="${CHECKPOINT_KEEP_DAYS:-30}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SUFFIX="${1:-${TIMESTAMP}}"
IMAGE_TAG="openclaw-snap:${SUFFIX}"
VOLUME_ARCHIVE="${CHECKPOINT_DIR}/volume-${SUFFIX}.tar.gz"
MANIFEST="${CHECKPOINT_DIR}/manifest-${SUFFIX}.txt"

# ── Preflight checks ─────────────────────────────────────────────────────
if ! docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "Container '${CONTAINER_NAME}' does not exist — nothing to checkpoint." >&2
  exit 0
fi

STATE="$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}")"
if [[ "${STATE}" != "running" ]]; then
  echo "Container '${CONTAINER_NAME}' is ${STATE} — skipping checkpoint." >&2
  exit 0
fi

mkdir -p "${CHECKPOINT_DIR}"

# ── 1. Commit container filesystem ────────────────────────────────────────
echo "[checkpoint] Committing container → ${IMAGE_TAG}" >&2
docker commit "${CONTAINER_NAME}" "${IMAGE_TAG}" >/dev/null

# ── 2. Backup named volume ───────────────────────────────────────────────
echo "[checkpoint] Backing up volume '${VOLUME_NAME}' → ${VOLUME_ARCHIVE}" >&2
docker run --rm \
  -v "${VOLUME_NAME}:/source:ro" \
  -v "${CHECKPOINT_DIR}:/backup" \
  ubuntu:24.04 \
  tar czf "/backup/volume-${SUFFIX}.tar.gz" -C /source .

# ── 3. Write manifest ────────────────────────────────────────────────────
cat > "${MANIFEST}" <<EOF
checkpoint: ${SUFFIX}
timestamp:  $(date -Iseconds)
image:      ${IMAGE_TAG}
volume:     ${VOLUME_ARCHIVE}
container:  ${CONTAINER_NAME}
state:      ${STATE}
EOF

echo "[checkpoint] Manifest written to ${MANIFEST}" >&2

# ── 4. Prune old snapshots ───────────────────────────────────────────────
echo "[checkpoint] Pruning snapshots older than ${KEEP_DAYS} days..." >&2
find "${CHECKPOINT_DIR}" -name 'volume-*.tar.gz' -mtime +"${KEEP_DAYS}" -delete 2>/dev/null || true
find "${CHECKPOINT_DIR}" -name 'manifest-*.txt' -mtime +"${KEEP_DAYS}" -delete 2>/dev/null || true

# Prune corresponding docker images (tagged openclaw-snap:YYYYMMDD-*)
# by checking image creation date.
docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedAt}}' \
  | grep '^openclaw-snap:' \
  | while read -r img_tag created_rest; do
      created_date="${created_rest%% *}"
      if [[ -n "${created_date}" ]]; then
        img_epoch="$(date -d "${created_date}" +%s 2>/dev/null || echo 0)"
        cutoff_epoch="$(date -d "${KEEP_DAYS} days ago" +%s)"
        if [[ "${img_epoch}" -gt 0 && "${img_epoch}" -lt "${cutoff_epoch}" ]]; then
          echo "[checkpoint] Pruning old image ${img_tag}" >&2
          docker rmi "${img_tag}" 2>/dev/null || true
        fi
      fi
    done

echo "[checkpoint] Done: ${SUFFIX}" >&2
