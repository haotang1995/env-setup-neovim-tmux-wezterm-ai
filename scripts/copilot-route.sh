#!/usr/bin/env bash
# Launch Claude Code / Codex against the local Copilot proxy.
#
# Dispatched by argv[0] (same idiom as ai-sandbox.sh):
#   claude-copilot [args...]   → claude, routed through Copilot
#   codex-copilot  [args...]   → codex,  routed through Copilot
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
#   CODEX_COPILOT_MODEL   default gpt-5.4
#   CODEX_COPILOT_EFFORT  default high
#
# COPILOT_PROXY_PORT is honored for both harnesses — the resolved URL is passed
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
    : "${CODEX_COPILOT_MODEL:=gpt-5.4}"
    exec codex \
      -c "model_provider=\"copilot_proxy\"" \
      -c "model_providers.copilot_proxy.base_url=\"${PROXY_URL}/v1\"" \
      -c "model=\"${CODEX_COPILOT_MODEL}\"" \
      -c "model_reasoning_effort=\"${CODEX_COPILOT_EFFORT:-high}\"" \
      "$@"
    ;;
esac
