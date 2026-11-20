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

# Codex's auto-review reviewer ("Approve for me") calls an OpenAI-internal
# model id that no Copilot seat serves; the proxy answers 400 and codex turns
# the failed review into a hard denial of EVERY escalation. modelMappings
# rewrites the id before it goes upstream. Any /responses-capable model works;
# the reviewer runs at low effort with the transcript as input.
AUTO_REVIEW_TARGET="${COPILOT_PROXY_AUTO_REVIEW_MODEL:-gpt-5.6-luna}"

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

# Print the inode of the listening socket on $1 (Linux), or nothing.
# Cheap: unlike `ss -p`, `ss -e` does not walk every /proc/*/fd.
listen_inode() {
  ss -ltne 2>/dev/null | awk -v p=":${1}$" '$4 ~ p {
    if (match($0, /ino:[0-9]+/)) { print substr($0, RSTART + 4, RLENGTH - 4); exit } }' || true
}

# Print the pid holding the listening socket on $1, or nothing if unknown.
# Without root, `ss -p` / `lsof` only see the caller's own processes. That
# covers the case that matters: a stray proxy of ours squatting the port.
# Slow on busy hosts (`ss -p` scans every process's fds: ~1.6s at 70k pids),
# so only error paths call it.
listen_pid() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {
      if (match($0, /pid=[0-9]+/)) { print substr($0, RSTART + 4, RLENGTH - 4); exit } }' || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -1 || true
  fi
  return 0
}

# One-line description of a pid: its systemd unit (Linux) and command line.
describe_pid() {
  local pid="$1" cmd unit=""
  cmd="$(ps -o args= -p "${pid}" 2>/dev/null | cut -c1-120 || true)"
  if [[ -r "/proc/${pid}/cgroup" ]]; then
    unit="$(awk -F/ '$NF ~ /\.service$/ {print $NF}' "/proc/${pid}/cgroup" 2>/dev/null | tail -1 || true)"
  fi
  printf 'pid %s%s: %s' "${pid}" "${unit:+ (systemd --user unit ${unit})}" "${cmd:-?}"
}

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
# Also seeds the codex-auto-review mapping (no-clobber: a hand-edited target
# in config.json wins over AUTO_REVIEW_TARGET).
ensure_config() {
  local key="$1"
  mkdir -p "${COPILOT_API_HOME}"
  COPILOT_PROXY_WANT_KEY="${key}" CONFIG_JSON="${CONFIG_JSON}" \
  COPILOT_PROXY_AUTO_REVIEW_TARGET="${AUTO_REVIEW_TARGET}" node -e '
    const fs = require("fs");
    const p = process.env.CONFIG_JSON;
    let cfg = {};
    try { const raw = fs.readFileSync(p, "utf8").trim(); if (raw) cfg = JSON.parse(raw); } catch {}
    cfg.auth = cfg.auth || {};
    const want = process.env.COPILOT_PROXY_WANT_KEY;
    const keys = Array.isArray(cfg.auth.apiKeys) ? cfg.auth.apiKeys : [];
    if (!keys.includes(want)) cfg.auth.apiKeys = [want, ...keys];
    const maps = (cfg.modelMappings && typeof cfg.modelMappings === "object") ? cfg.modelMappings : {};
    if (!maps["codex-auto-review"]) maps["codex-auto-review"] = process.env.COPILOT_PROXY_AUTO_REVIEW_TARGET;
    cfg.modelMappings = maps;
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

# True only if the pid in PID_FILE holds the listening socket.
# is_running + is_healthy are not enough. Upstream swallows EADDRINUSE
# (srvx: `this.serve().catch(() => {})`), so a proxy started on a taken port
# stays alive with no socket, and *another* server answers every check —
# with its own account and its own bind address.
# $! is the listener itself: nohup and the npm shim's `env node` both exec.
owns_port() {
  is_running || return 1
  local pid ino; pid="$(cat "${PID_FILE}")"
  if [[ -d "/proc/${pid}/fd" ]] && command -v ss >/dev/null 2>&1; then
    ino="$(listen_inode "${PROXY_PORT}")"
    [[ -n "${ino}" && "$(ls -l "/proc/${pid}/fd" 2>/dev/null)" == *"socket:[${ino}]"* ]]
  elif command -v lsof >/dev/null 2>&1; then
    [[ -n "$(lsof -nP -a -p "${pid}" -iTCP:"${PROXY_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)" ]]
  else
    is_healthy   # cannot tell owners apart here; fall back to the old check
  fi
}

# Wait up to ~20s for our pid to bind the port and answer. Stops early if it dies.
wait_owned() {
  local i
  for i in $(seq 1 40); do
    owns_port && is_healthy && return 0
    is_running || return 1
    sleep 0.5
  done
  return 1
}

# Describe whatever holds PROXY_PORT.
port_owner_desc() {
  local owner; owner="$(listen_pid "${PROXY_PORT}")"
  if [[ -n "${owner}" ]]; then describe_pid "${owner}"; else printf 'owner not visible (another user?)'; fi
}

die_port_taken() {
  warn "port ${PROXY_PORT} is held by another process — $(port_owner_desc)"
  warn "it would serve every request with its own GitHub account, quota, and bind address"
  die "free the port (systemctl --user stop <unit> / kill <pid>) or set COPILOT_PROXY_PORT, then retry"
}

authed() { [[ -s "${TOKEN_FILE}" ]]; }

# ── Actions ───────────────────────────────────────────────────────────────
do_start() {
  if owns_port && is_healthy; then
    log "already running on ${PROXY_URL} (pid $(cat "${PID_FILE}"))"
    return 0
  fi
  if is_running; then
    # Our pid is alive without the port. It is either still booting (a
    # concurrent `start`), or it lost a bind race and will never listen.
    if ! port_in_use "${PROXY_PORT}" && wait_owned; then
      log "already running on ${PROXY_URL} (pid $(cat "${PID_FILE}"))"
      return 0
    fi
    warn "pid $(cat "${PID_FILE}") is alive but not serving ${PROXY_URL} — stopping it"
    do_stop >/dev/null
  fi
  port_in_use "${PROXY_PORT}" && die_port_taken
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

  if ! wait_owned; then
    # Covers a bind race too: someone took the port after the check above.
    port_in_use "${PROXY_PORT}" && ! owns_port && { do_stop >/dev/null; die_port_taken; }
    warn "did not become healthy; last log lines:"
    tail -15 "${LOG_FILE}" >&2 || true
    do_stop >/dev/null
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

  if port_in_use "${PROXY_PORT}" && ! owns_port; then
    # Foreign server on our port: every check below would describe IT.
    printf '  %-14s %s\n' "state" "🔴 port ${PROXY_PORT} held by another process"
    printf '  %-14s %s\n' "owner" "$(port_owner_desc)"
    if is_running; then
      printf '  %-14s %s\n' "managed pid" "$(cat "${PID_FILE}") alive but has no socket (bind failed silently)"
    fi
    printf '  %-14s %s\n' "fix" "stop that process, then: copilot-proxy restart"
  elif owns_port && is_healthy; then
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
  elif is_running; then
    printf '  %-14s %s\n' "state" "✗ pid $(cat "${PID_FILE}") alive but not listening (starting, or bind failed)"
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
