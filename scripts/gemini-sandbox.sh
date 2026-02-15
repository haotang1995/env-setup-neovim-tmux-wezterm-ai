#!/usr/bin/env bash
# Launch Gemini CLI with Seatbelt sandbox (macOS) for filesystem isolation.
# Uses restrictive-open profile: strict read/write limits, network allowed.
#
# Usage: gemini-sandbox [gemini args...]

set -euo pipefail

export GEMINI_SANDBOX="${GEMINI_SANDBOX:-sandbox-exec}"
export SEATBELT_PROFILE="${SEATBELT_PROFILE:-restrictive-open}"

exec gemini "$@"
