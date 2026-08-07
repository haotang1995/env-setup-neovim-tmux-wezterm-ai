#!/usr/bin/env bash
# Local GitHub Copilot → OpenAI/Anthropic API bridge.
#
# Runs caozhiyuan/copilot-api (npm @jeffreycao/copilot-api) as a persistent
# loopback service, so your Copilot entitlement backs:
#   • the Claude Code harness  (claude-copilot)
#   • the Codex harness        (codex-copilot)
#   • direct SDK/API calls     (OPENAI_BASE_URL / ANTHROPIC_BASE_URL → /v1)
#
# Two upstream defaults are UNSAFE and are corrected here:
#   1. There is no --api-key flag; unknown flags are silently ignored and the
#      server then runs with NO auth. Auth only works via config.json.
#   2. serve() is called without a hostname, so it binds *:PORT — reachable
#      from the LAN. HOST=127.0.0.1 is honored by srvx and fixes it.
#
# Usage:
#   copilot-proxy start|stop|restart|status      # lifecycle
#   copilot-proxy auth                           # GitHub device-flow login
#   copilot-proxy models [--claude|--gpt]        # list reachable models
#   copilot-proxy usage                          # Copilot quota / spend
#   copilot-proxy logs [-f]                      # tail the server log
#   copilot-proxy key                            # print the local API key
#   copilot-proxy env [--openai|--anthropic]     # eval-able export lines
#   copilot-proxy upgrade [VERSION]              # re-pin to a new version
#
# ⚠️  Routes a corporate Copilot seat through a third-party client. See AI.md.

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────
PROXY_PKG="@jeffreycao/copilot-api"
PROXY_VERSION="${COPILOT_PROXY_VERSION:-1.14.22}"   # pinned; bump deliberately
PROXY_PREFIX="${HOME}/.local/share/copilot-proxy-bin"
PROXY_BIN="${PROXY_PREFIX}/node_modules/.bin/copilot-api"

# Upstream's own data dir (token + config.json). Overridable so the proxy's
# credential store can be isolated from anything else.
export COPILOT_API_HOME="${COPILOT_API_HOME:-${HOME}/.local/share/copilot-api}"
CONFIG_JSON="${COPILOT_API_HOME}/config.json"
TOKEN_FILE="${COPILOT_API_HOME}/github_token"

PROXY_HOST="127.0.0.1"                              # NEVER 0.0.0.0 — see header
PROXY_PORT_DEFAULT="6868"
PROXY_PORT="${COPILOT_PROXY_PORT:-${PROXY_PORT_DEFAULT}}"
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

# State is per-port: COPILOT_PROXY_PORT is a supported override, so two proxies
# can legitimately coexist. A shared pid file would make `stop`/`status` on one
# port act on the other instance.
RUN_DIR="${HOME}/.local/state/copilot-proxy"
PID_FILE="${RUN_DIR}/proxy-${PROXY_PORT}.pid"
LOG_FILE="${RUN_DIR}/proxy-${PROXY_PORT}.log"

# Adopt the pre-port-scoped state files (default port only).
if [[ "${PROXY_PORT}" == "${PROXY_PORT_DEFAULT}" ]]; then
  if [[ -f "${RUN_DIR}/proxy.pid" && ! -f "${PID_FILE}" ]]; then
    mv "${RUN_DIR}/proxy.pid" "${PID_FILE}"
  fi
  if [[ -f "${RUN_DIR}/proxy.log" && ! -f "${LOG_FILE}" ]]; then
    mv "${RUN_DIR}/proxy.log" "${LOG_FILE}"
  fi
fi

SHELLRC_LOCAL="${HOME}/.shellrc.local"

# ── Helpers ───────────────────────────────────────────────────────────────
log()  { printf '  %s\n' "$*"; }
warn() { printf '  ⚠️  %s\n' "$*" >&2; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }

need_node() {
  command -v node >/dev/null 2>&1 || die "node not found (need Node.js ≥ 22.13 for token-usage storage)"
  command -v npm  >/dev/null 2>&1 || die "npm not found"
}

# ── Portability shims (macOS is the primary dev machine) ──────────────────
# `ss` is Linux-only and `stat -c` is GNU-only; macOS has netstat and `stat -f`.
# Every caller tolerates an empty result, so these never abort under `set -e`.

# Print the listen address for $1, or nothing if not listening.
listen_addr() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {print $4; exit}'
  elif command -v netstat >/dev/null 2>&1; then
    # macOS/BSD netstat: "tcp4  0  0  127.0.0.1.6868  *.*  LISTEN"
    netstat -an -p tcp 2>/dev/null \
      | awk -v p="\\.${port}$" '$NF == "LISTEN" && $4 ~ p {print $4; exit}'
  fi
  return 0
}

port_in_use() { [[ -n "$(listen_addr "$1")" ]]; }

# stat helpers: GNU `-c` vs BSD `-f`.
file_size() {
  stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo "?"
}
file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null || echo "?"
}

# Resolve the local API key that gates this proxy. Order:
#   $COPILOT_PROXY_KEY  >  ~/.shellrc.local  >  generate & persist
resolve_key() {
  if [[ -n "${COPILOT_PROXY_KEY:-}" ]]; then
    printf '%s' "${COPILOT_PROXY_KEY}"
    return
  fi

  if [[ -f "${SHELLRC_LOCAL}" ]]; then
    local existing
    existing="$(sed -n 's/^[[:space:]]*export[[:space:]]\{1,\}COPILOT_PROXY_KEY=["'"'"']\{0,1\}\([^"'"'"']*\)["'"'"']\{0,1\}[[:space:]]*$/\1/p' \
                "${SHELLRC_LOCAL}" | tail -1)"
    if [[ -n "${existing}" ]]; then
      printf '%s' "${existing}"
      return
    fi
  fi

  # Generate once and persist to the machine-local (gitignored) secrets file.
  local new_key
  new_key="ck-$(openssl rand -hex 24)"
  touch "${SHELLRC_LOCAL}"
  chmod 600 "${SHELLRC_LOCAL}"
  {
    printf '\n# Local Copilot proxy (copilot-proxy) — gates http://127.0.0.1:%s\n' "${PROXY_PORT}"
    printf 'export COPILOT_PROXY_KEY=%s\n' "${new_key}"
    printf 'export COPILOT_PROXY_URL=%s\n' "${PROXY_URL}"
  } >> "${SHELLRC_LOCAL}"
  warn "generated a new proxy API key and appended it to ${SHELLRC_LOCAL}"
  printf '%s' "${new_key}"
}

# Ensure config.json enforces auth. Upstream skips auth entirely when
# auth.apiKeys is empty (lib/request-auth.ts), so this is load-bearing.
ensure_config() {
  local key="$1"
  mkdir -p "${COPILOT_API_HOME}"
  COPILOT_PROXY_WANT_KEY="${key}" CONFIG_JSON="${CONFIG_JSON}" node -e '
    const fs = require("fs");
    const p = process.env.CONFIG_JSON;
    let cfg = {};
    try { const raw = fs.readFileSync(p, "utf8").trim(); if (raw) cfg = JSON.parse(raw); } catch {}
    cfg.auth = cfg.auth || {};
    const want = process.env.COPILOT_PROXY_WANT_KEY;
    const keys = Array.isArray(cfg.auth.apiKeys) ? cfg.auth.apiKeys : [];
    if (!keys.includes(want)) cfg.auth.apiKeys = [want, ...keys];
    fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
    fs.chmodSync(p, 0o600);
  '
}

ensure_installed() {
  need_node
  local installed=""
  if [[ -x "${PROXY_BIN}" ]]; then
    installed="$(node -e '
      try { console.log(require(process.argv[1] + "/node_modules/'"${PROXY_PKG}"'/package.json").version) } catch { console.log("") }
    ' "${PROXY_PREFIX}" 2>/dev/null || true)"
  fi
  if [[ "${installed}" != "${PROXY_VERSION}" ]]; then
    log "installing ${PROXY_PKG}@${PROXY_VERSION} → ${PROXY_PREFIX}"
    mkdir -p "${PROXY_PREFIX}"
    npm install --prefix "${PROXY_PREFIX}" --silent --no-fund --no-audit \
      "${PROXY_PKG}@${PROXY_VERSION}" >/dev/null
    log "installed (lockfile: ${PROXY_PREFIX}/package-lock.json)"
  fi
}

is_running() {
  [[ -f "${PID_FILE}" ]] || return 1
  local pid; pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

is_healthy() {
  curl -fsS -o /dev/null -m 3 "${PROXY_URL}/" 2>/dev/null
}

authed() { [[ -s "${TOKEN_FILE}" ]]; }

# ── Actions ───────────────────────────────────────────────────────────────
do_start() {
  if is_running && is_healthy; then
    log "already running on ${PROXY_URL} (pid $(cat "${PID_FILE}"))"
    return 0
  fi
  authed || die "not authenticated — run: copilot-proxy auth"

  ensure_installed
  local key; key="$(resolve_key)"
  ensure_config "${key}"
  mkdir -p "${RUN_DIR}"

  # HOST=127.0.0.1 is the ONLY way to stop it binding all interfaces.
  HOST="${PROXY_HOST}" NODE_USE_SYSTEM_CA=1 \
    nohup "${PROXY_BIN}" start --port "${PROXY_PORT}" \
    >>"${LOG_FILE}" 2>&1 &
  echo $! > "${PID_FILE}"

  local i
  for i in $(seq 1 40); do
    sleep 0.5
    is_healthy && break
  done

  if ! is_healthy; then
    warn "did not become healthy; last log lines:"
    tail -15 "${LOG_FILE}" >&2 || true
    die "start failed"
  fi

  # Fail loudly if auth is somehow not enforced (guards against upstream drift).
  local anon; anon="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "${PROXY_URL}/v1/models" || echo 000)"
  if [[ "${anon}" != "401" ]]; then
    do_stop >/dev/null 2>&1 || true
    die "SECURITY: anonymous /v1/models returned HTTP ${anon} (expected 401). Refusing to run unauthenticated."
  fi

  local bind; bind="$(listen_addr "${PROXY_PORT}")"
  log "✓ listening on ${PROXY_URL} (bind: ${bind:-unknown}, auth: enforced)"
  log "  direct API base: ${PROXY_URL}/v1"
}

do_stop() {
  if ! is_running; then
    log "not running"
    rm -f "${PID_FILE}"
    return 0
  fi
  local pid; pid="$(cat "${PID_FILE}")"
  kill "${pid}" 2>/dev/null || true
  local i
  for i in $(seq 1 20); do
    kill -0 "${pid}" 2>/dev/null || break
    sleep 0.25
  done
  kill -9 "${pid}" 2>/dev/null || true
  rm -f "${PID_FILE}"
  log "stopped (pid ${pid})"
}

do_status() {
  printf '\n  copilot-proxy\n  ─────────────\n'
  printf '  %-14s %s\n' "package"  "${PROXY_PKG}@${PROXY_VERSION}"
  printf '  %-14s %s\n' "endpoint" "${PROXY_URL}/v1"
  printf '  %-14s %s\n' "data dir" "${COPILOT_API_HOME}"

  if authed; then
    printf '  %-14s %s\n' "github auth" "✓ token present ($(file_size "${TOKEN_FILE}") bytes, mode $(file_mode "${TOKEN_FILE}"))"
  else
    printf '  %-14s %s\n' "github auth" "✗ missing — run: copilot-proxy auth"
  fi

  if is_running && is_healthy; then
    local bind anon
    bind="$(listen_addr "${PROXY_PORT}")"
    anon="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "${PROXY_URL}/v1/models" || echo 000)"
    printf '  %-14s %s\n' "state"  "✓ running (pid $(cat "${PID_FILE}"))"
    printf '  %-14s %s\n' "bind"   "${bind:-unknown}"
    if [[ "${anon}" == "401" ]]; then
      printf '  %-14s %s\n' "auth"  "✓ enforced (anonymous → 401)"
    else
      printf '  %-14s %s\n' "auth"  "🔴 NOT ENFORCED (anonymous → ${anon})"
    fi
  else
    printf '  %-14s %s\n' "state" "✗ stopped"
  fi
  printf '\n'
}

do_models() {
  is_healthy || die "proxy not running — run: copilot-proxy start"
  local key filter; key="$(resolve_key)"; filter="${1:-}"
  curl -fsS -m 20 -H "Authorization: Bearer ${key}" "${PROXY_URL}/v1/models" \
    | MODEL_FILTER="${filter}" node -e '
      let raw = ""; process.stdin.on("data", d => raw += d).on("end", () => {
        const ids = (JSON.parse(raw).data || []).map(m => m.id).sort();
        const f = process.env.MODEL_FILTER;
        const pick =
          f === "--claude" ? ids.filter(i => i.includes("claude"))
          : f === "--gpt"  ? ids.filter(i => i.startsWith("gpt"))
          : ids;
        pick.forEach(i => console.log("  " + i));
        console.error(`  (${pick.length} of ${ids.length} models)`);
      });
    '
}

do_usage() {
  is_healthy || die "proxy not running — run: copilot-proxy start"
  curl -fsS -m 20 -H "Authorization: Bearer $(resolve_key)" "${PROXY_URL}/usage" \
    || die "usage endpoint failed"
  printf '\n'
}

do_env() {
  local key url; key="$(resolve_key)"; url="${PROXY_URL}"
  case "${1:-}" in
    --openai)
      printf 'export OPENAI_BASE_URL=%s/v1\n' "${url}"
      printf 'export OPENAI_API_KEY=%s\n'     "${key}"
      ;;
    --anthropic)
      printf 'export ANTHROPIC_BASE_URL=%s/\n'   "${url}"
      printf 'export ANTHROPIC_AUTH_TOKEN=%s\n'  "${key}"
      ;;
    *)
      # Neutral vars — safe to export globally; they hijack nothing.
      printf 'export COPILOT_PROXY_URL=%s\n' "${url}"
      printf 'export COPILOT_PROXY_KEY=%s\n' "${key}"
      ;;
  esac
}

do_auth() {
  ensure_installed
  exec "${PROXY_BIN}" auth
}

do_logs() {
  [[ -f "${LOG_FILE}" ]] || die "no log yet at ${LOG_FILE}"
  if [[ "${1:-}" == "-f" ]]; then tail -f "${LOG_FILE}"; else tail -40 "${LOG_FILE}"; fi
}

do_upgrade() {
  local target="${1:-}"
  [[ -n "${target}" ]] || die "usage: copilot-proxy upgrade <version>   (current pin: ${PROXY_VERSION})"
  warn "re-audit before trusting a new version — this proxy holds a corporate credential."
  PROXY_VERSION="${target}"
  rm -rf "${PROXY_PREFIX}"
  ensure_installed
  log "pinned locally to ${target}; update PROXY_VERSION in $(basename "${BASH_SOURCE[0]}") to persist"
}

usage() {
  sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── Dispatch ──────────────────────────────────────────────────────────────
ACTION="${1:-status}"; shift || true
case "${ACTION}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; do_start ;;
  status)  do_status ;;
  auth)    do_auth ;;
  models)  do_models "${1:-}" ;;
  usage)   do_usage ;;
  logs)    do_logs "${1:-}" ;;
  key)     resolve_key; printf '\n' ;;
  env)     do_env "${1:-}" ;;
  upgrade) do_upgrade "${1:-}" ;;
  -h|--help|help) usage ;;
  *) usage; die "unknown action: ${ACTION}" ;;
esac
