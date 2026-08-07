#!/usr/bin/env bash
# Launch Claude Code / Codex against the local Copilot proxy.
#
# Dispatched by argv[0] (same idiom as ai-sandbox.sh):
#   claude-copilot [args...]   → claude, routed through Copilot
#   codex-copilot  [args...]   → codex  --profile copilot
#
# Plain `claude` and `codex` are untouched and keep their native auth. This is
# deliberate: ~/.claude/settings.json and ~/.codex/config.toml are symlinks into
# this repo, so putting proxy env there would route EVERY session through
# Copilot and hard-fail whenever the proxy is down.
#
# The proxy is started on demand if it isn't already up.
#
# Model overrides (any value already exported wins):
#   CLAUDE_COPILOT_OPUS   default claude-opus-5
#   CLAUDE_COPILOT_SONNET default claude-sonnet-5
#   CLAUDE_COPILOT_HAIKU  default claude-haiku-4-5
#   CODEX_COPILOT_MODEL   default gpt-5.3-codex
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
  *)
    case "${1:-}" in
      claude|codex) HARNESS="$1"; shift ;;
      *)
        echo "copilot-route: invoke as claude-copilot or codex-copilot" >&2
        echo "               (or: copilot-route <claude|codex> [args...])" >&2
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

    : "${ANTHROPIC_DEFAULT_OPUS_MODEL:=${CLAUDE_COPILOT_OPUS:-claude-opus-5}}"
    : "${ANTHROPIC_DEFAULT_SONNET_MODEL:=${CLAUDE_COPILOT_SONNET:-claude-sonnet-5}}"
    : "${ANTHROPIC_DEFAULT_HAIKU_MODEL:=${CLAUDE_COPILOT_HAIKU:-claude-haiku-4-5}}"
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
    # this env var (env_key = "COPILOT_PROXY_KEY"). The profile selects it.
    export COPILOT_PROXY_KEY="${PROXY_KEY}"
    command -v codex >/dev/null 2>&1 || { echo "copilot-route: codex not found in PATH" >&2; exit 1; }

    # --profile is position-SENSITIVE: each subcommand declares its own
    # --profile, and a global one placed before the subcommand is silently
    # ignored — codex then falls straight through to the openai provider with
    # no error. So insert it *after* any subcommand. (`-c` propagates from
    # either position; --profile does not.)
    codex_args=()
    case "${1:-}" in
      exec|e|review|login|logout|mcp|mcp-server|app-server|completion|sandbox|debug|apply|a)
        codex_args+=("$1" --profile copilot); shift ;;
      *)
        codex_args+=(--profile copilot) ;;
    esac

    # Model comes from [profiles.copilot] unless explicitly overridden. Note
    # 0.116 rejects newer ids (gpt-5.5+) client-side with "requires a newer
    # version of Codex", even though the proxy serves them fine.
    [[ -n "${CODEX_COPILOT_MODEL:-}" ]] && codex_args+=(-c "model=\"${CODEX_COPILOT_MODEL}\"")

    exec codex "${codex_args[@]}" "$@"
    ;;
esac
