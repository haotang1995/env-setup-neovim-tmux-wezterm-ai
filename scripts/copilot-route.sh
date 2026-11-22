#!/usr/bin/env bash
# Launch Claude Code / Codex / Antigravity CLI against the local Copilot proxy.
#
# Dispatched by argv[0] (same idiom as ai-sandbox.sh):
#   claude-copilot [args...]   → claude, routed through Copilot
#   codex-copilot  [args...]   → codex,  routed through Copilot
#   agy-copilot    [args...]   → agy,    routed through Copilot
#
# Plain `claude`, `codex`, and `agy` are untouched and keep their native auth.
# This is deliberate: ~/.claude/settings.json and ~/.codex/config.toml are
# symlinks into this repo, so putting proxy env there would route EVERY session
# through Copilot and hard-fail whenever the proxy is down.
#
# The proxy is started on demand if it isn't already up. agy speaks only the
# Gemini API, so each agy-copilot session also gets its own
# gemini_bridge.py (Gemini API → chat/completions) on a free loopback port,
# stopped when agy exits.
#
# Model overrides (any value already exported wins):
#   CLAUDE_COPILOT_OPUS   default claude-opus-5-5
#   CLAUDE_COPILOT_SONNET default claude-sonnet-5-5
#   CLAUDE_COPILOT_HAIKU  default claude-haiku-5-5
#   CODEX_COPILOT_MODEL   default: `model` from ~/.codex/config.toml
#   CODEX_COPILOT_EFFORT  default high
#   CODEX_COPILOT_APPROVALS_REVIEWER default user
#   AGY_COPILOT_MODEL       default gemini-4-argon   (agy's main model)
#   AGY_COPILOT_SMALL_MODEL default gemini-3.8-flash (when agy asks for flash/lite)
#
# COPILOT_PROXY_PORT is honored for all harnesses — the resolved URL is passed
# through at launch, not read from the literal in .codex/config.toml.
#
# ⚠️  Routes a corporate Copilot seat through a third-party client. See AI.md.

set -euo pipefail

# ── Resolve script location (follow symlinks) ─────────────────────────────
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
  _dir="$(cd "$(dirname "$_source")" && pwd)"
  _source="$(readlink "$_source")"
  [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd "$(dirname "$_source")" && pwd)"
PROXY_SH="${SCRIPT_DIR}/copilot-proxy.sh"

INVOKED="$(basename "$0")"

# ── Which harness? ────────────────────────────────────────────────────────
case "${INVOKED}" in
  claude-copilot) HARNESS="claude" ;;
  codex-copilot)  HARNESS="codex"  ;;
  agy-copilot)    HARNESS="agy"    ;;
  *)
    case "${1:-}" in
      claude|codex|agy) HARNESS="$1"; shift ;;
      *)
        echo "copilot-route: invoke as claude-copilot, codex-copilot, or agy-copilot" >&2
        echo "               (or: copilot-route <claude|codex|agy> [args...])" >&2
        exit 2 ;;
    esac ;;
esac

# ── Ensure the proxy is up ────────────────────────────────────────────────
[[ -x "${PROXY_SH}" ]] || { echo "copilot-route: missing ${PROXY_SH}" >&2; exit 1; }
"${PROXY_SH}" start >&2

PROXY_URL="$("${PROXY_SH}" env | sed -n 's/^export COPILOT_PROXY_URL=//p')"
PROXY_KEY="$("${PROXY_SH}" env | sed -n 's/^export COPILOT_PROXY_KEY=//p')"
[[ -n "${PROXY_URL}" && -n "${PROXY_KEY}" ]] || { echo "copilot-route: could not resolve proxy url/key" >&2; exit 1; }

# ── Launch ────────────────────────────────────────────────────────────────
case "${HARNESS}" in
  claude)
    # Bearer auth (ANTHROPIC_AUTH_TOKEN), not x-api-key — the latter triggers a
    # one-time interactive "use custom API key?" approval prompt.
    export ANTHROPIC_BASE_URL="${PROXY_URL}/"
    export ANTHROPIC_AUTH_TOKEN="${PROXY_KEY}"

    : "${ANTHROPIC_DEFAULT_OPUS_MODEL:=${CLAUDE_COPILOT_OPUS:-claude-opus-5-5}}"
    : "${ANTHROPIC_DEFAULT_SONNET_MODEL:=${CLAUDE_COPILOT_SONNET:-claude-sonnet-5-5}}"
    : "${ANTHROPIC_DEFAULT_HAIKU_MODEL:=${CLAUDE_COPILOT_HAIKU:-claude-haiku-5-5}}"
    export ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL

    # Don't phone home to api.anthropic.com when a gateway is in front.
    : "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:=1}"
    # Copilot rejects beta headers it doesn't know; Claude Code adds new ones
    # every release. Unset this if you want to try a fresh beta feature.
    : "${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS:=1}"
    export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS

    command -v claude >/dev/null 2>&1 || { echo "copilot-route: claude not found in PATH" >&2; exit 1; }
    exec claude "$@"
    ;;

  codex)
    # The provider block lives in ~/.codex/config.toml and reads the key from
    # this env var (env_key = "COPILOT_PROXY_KEY").
    export COPILOT_PROXY_KEY="${PROXY_KEY}"
    command -v codex >/dev/null 2>&1 || { echo "copilot-route: codex not found in PATH" >&2; exit 1; }

    # Select the provider with -c, NOT --profile. Codex changed the profile
    # mechanism twice in one week:
    #   0.116 — profiles must be [profiles.x] in config.toml, and a --profile
    #           placed before a subcommand is SILENTLY ignored (falls through
    #           to the openai provider with no error at all).
    #   0.147 — hard-errors on a legacy [profiles.x] table and requires a
    #           standalone ~/.codex/<name>.config.toml.
    # Codex auto-updates, so --profile is a moving target. `-c` behaves the
    # same on both and is position-insensitive.
    # base_url must be overridden from the RESOLVED proxy URL, not left to the
    # literal in config.toml — otherwise COPILOT_PROXY_PORT silently has no
    # effect here (it works for claude via ANTHROPIC_BASE_URL and for the
    # sandbox, so a custom port would break host codex only).
    #
    # Force user approval review on the Copilot lane. auto_review and
    # guardian_subagent call models that Copilot does not serve, turning every
    # escalation into a hard denial.
    #
    # The model is NOT overridden by default: codex reads `model` from
    # ~/.codex/config.toml, so both lanes share one model and a bump there
    # carries over. CODEX_COPILOT_MODEL pins a Copilot-only model instead.
    # (The `${a[@]+…}` form: an empty "${a[@]}" trips `set -u` on bash 3.2.)
    model_args=()
    [[ -n "${CODEX_COPILOT_MODEL:-}" ]] && model_args=(-c "model=\"${CODEX_COPILOT_MODEL}\"")
    exec codex \
      -c "model_provider=\"copilot_proxy\"" \
      -c "model_providers.copilot_proxy.base_url=\"${PROXY_URL}/v1\"" \
      ${model_args[@]+"${model_args[@]}"} \
      -c "model_reasoning_effort=\"${CODEX_COPILOT_EFFORT:-high}\"" \
      -c "approvals_reviewer=\"${CODEX_COPILOT_APPROVALS_REVIEWER:-user}\"" \
      "$@"
    ;;

  agy)
    command -v agy >/dev/null 2>&1 || { echo "copilot-route: agy not found in PATH (Antigravity CLI; see AI.md)" >&2; exit 1; }
    command -v python3 >/dev/null 2>&1 || { echo "copilot-route: python3 not found (runs the Gemini bridge)" >&2; exit 1; }
    BRIDGE_PY="${SCRIPT_DIR}/gemini_bridge.py"
    [[ -f "${BRIDGE_PY}" ]] || { echo "copilot-route: missing ${BRIDGE_PY}" >&2; exit 1; }

    # API-key mode is switched on per session via --settings, so the global
    # ~/.gemini/antigravity-cli/settings.json (and plain `agy`) stay on the
    # Google login. A second --settings REPLACES ours (verified on agy 1.5.14):
    # agy then silently falls back to that login instead of Copilot.
    for arg in "$@"; do
      case "${arg}" in
        --settings|--settings=*|-settings|-settings=*)
          echo "copilot-route: agy-copilot passes --settings itself; put other keys in" >&2
          echo "               ~/.gemini/antigravity-cli/settings.json instead" >&2
          exit 2 ;;
      esac
    done

    state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/copilot-proxy"
    mkdir -p "${state_dir}"
    bridge_log="${state_dir}/agy-bridge.log"
    agy_model="${AGY_COPILOT_MODEL:-gemini-4-argon}"
    run_dir="$(mktemp -d)"
    # Per-session key: the box is shared, and loopback is reachable by every
    # local user. Keys travel by env, never argv (argv is world-readable in ps).
    bridge_key="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    BRIDGE_KEY="${bridge_key}" UPSTREAM_URL="${PROXY_URL}" UPSTREAM_KEY="${PROXY_KEY}" \
    BRIDGE_MODEL="${agy_model}" BRIDGE_SMALL_MODEL="${AGY_COPILOT_SMALL_MODEL:-gemini-3.8-flash}" \
    BRIDGE_PORT_FILE="${run_dir}/port" \
      python3 -I "${BRIDGE_PY}" </dev/null >/dev/null 2>>"${bridge_log}" &
    bridge_pid=$!
    trap 'kill "${bridge_pid}" 2>/dev/null; rm -f "${run_dir}/port"; rmdir "${run_dir}" 2>/dev/null' EXIT

    port=""
    for _ in $(seq 150); do
      if [[ -s "${run_dir}/port" ]]; then port="$(cat "${run_dir}/port")"; break; fi
      kill -0 "${bridge_pid}" 2>/dev/null || break
      sleep 0.1
    done
    [[ -n "${port}" ]] || { echo "copilot-route: Gemini bridge did not start; see ${bridge_log}" >&2; exit 1; }
    echo "copilot-route: agy → gemini_bridge 127.0.0.1:${port} → copilot-proxy (${agy_model}); log: ${bridge_log}" >&2

    # The bridge is also agy's HTTPS proxy, refusing play.googleapis.com: agy
    # uploads usage logs there even with "Enable Telemetry" off. Commands agy
    # runs inherit the proxy and tunnel through it. Set unconditionally: an
    # inherited proxy would carry the upload past the bridge, and an inherited
    # NO_PROXY entry such as `.googleapis.com` or `*` makes Go skip the proxy
    # for that host. The bridge dials other hosts directly, so a corporate
    # egress proxy is not used inside agy sessions.
    if [[ -n "${HTTPS_PROXY:-}${https_proxy:-}${NO_PROXY:-}${no_proxy:-}" ]]; then
      echo "copilot-route: replacing HTTPS_PROXY/NO_PROXY for this session (blocks agy's usage-log upload)" >&2
    fi
    export HTTPS_PROXY="http://127.0.0.1:${port}" https_proxy="http://127.0.0.1:${port}"
    export NO_PROXY="127.0.0.1,localhost,::1" no_proxy="127.0.0.1,localhost,::1"

    # Not exec: the EXIT trap must outlive agy to stop the bridge.
    GEMINI_API_KEY="${bridge_key}" GOOGLE_GEMINI_BASE_URL="http://127.0.0.1:${port}" \
      agy --settings '{"modelProvider":"gemini"}' "$@"
    ;;
esac
