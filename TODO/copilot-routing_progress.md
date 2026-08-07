# Copilot-backed routing for Claude Code + Codex

Route the Claude Code and Codex harnesses (and direct API calls) through the
company GitHub Copilot entitlement instead of Anthropic/OpenAI keys.

**Status:** implemented, host-side verified end-to-end at the API layer.
Harness-level and sandbox verification still pending (see below).

## Decisions

- **Proxy: `caozhiyuan/copilot-api`** (npm `@jeffreycao/copilot-api`), pinned to
  `1.14.22` in `scripts/copilot-proxy.sh`.
  - It is the **maintained, detached fork of `ericc-ch/copilot-api`** — the
    4,094-star repo every blog links to, dead since 2025-10-05.
  - `ericc-ch` was rejected on a hard fact, not vibes: its `src/server.ts` mounts
    no `/v1/responses` route, and Codex removed the `chat` wire API in Feb 2026.
    It **cannot** drive Codex.
  - Also rejected: `router-for-me/CLIProxyAPI` (46k stars, but `internal/auth`
    has no Copilot provider at all), `OmniRoute` (291-provider mega-gateway),
    LiteLLM (`github_copilot` documents no Claude models),
    `voidsteed/copilot-proxy-api` (audited clean but 38 stars, and translates
    Anthropic→OpenAI→Anthropic instead of using Copilot's native Messages API).
- **Opt-in wrappers, never default.** `~/.claude/settings.json` and
  `~/.codex/config.toml` are symlinks *into this repo*, so proxy env in them
  would route every session through Copilot and break whenever the proxy is down.
  Hence `claude-copilot` / `codex-copilot` alongside untouched `claude` / `codex`.

## Verified (2026-08-06)

- `GET /v1/models` → **23 models incl. 7 Claude** (`claude-opus-5`,
  `claude-opus-4-{6,7,8}`, `claude-sonnet-{5,4-6}`, `claude-haiku-4-5`) plus
  `gpt-5.5`, `gpt-5.3-codex`, gemini, grok. The community reports about
  `Copilot-Integration-Id` gating Claude models **do not apply to this seat**.
- `POST /v1/messages` · `claude-opus-5` → `PROXY_OK`, `stop_reason: end_turn`,
  `thinking_tokens: 18` (extended thinking survives the proxy).
- `POST /v1/responses` · `gpt-5.5` → `CODEX_OK`, `status: completed`.
- `cache_creation_input_tokens: 0` — confirms no prompt-cache writes.
- Auth enforcement after fix: anonymous → 401, wrong key → 401, correct → 200.
- Bind after fix: `LISTEN 127.0.0.1:<port>`.

> Note: the probes above ran on the upstream default port **4141**. The service
> has since been moved to **6868** (`COPILOT_PROXY_PORT` overrides). Findings are
> port-independent.

## 🔴 Two unsafe upstream defaults (fixed in `copilot-proxy.sh`)

1. **`--api-key` does not exist.** `start` accepts only `--port --verbose
   --github-token --claude-code --show-token --proxy-env`. citty silently
   ignores unknown flags, so passing `--api-key` leaves the proxy **fully open**.
   Auth works only via `auth.apiKeys` in `~/.local/share/copilot-api/config.json`
   (`lib/request-auth.ts:113` skips auth when the array is empty).
2. **Binds all interfaces.** `start.ts:192` calls `serve({fetch, port, bun})`
   with no `hostname`. During the first probe the proxy was briefly reachable
   *unauthenticated* from the corporate LAN (`10.209.224.175:4141` → HTTP 200).
   `HOST=127.0.0.1` fixes it. `copilot-proxy start` now hard-fails if an
   anonymous `/v1/models` doesn't return 401.

Neither is discoverable from `--help`. **Re-check both on every version bump.**

## Remaining

- [ ] Run `copilot-proxy start` (blocked by the tool-permission classifier during
      implementation — needs a manual first run).
- [ ] `claude-copilot -p "reply OK"` end-to-end through the harness.
- [ ] `codex-copilot exec "print hello"` — confirms the `--profile copilot` path.
- [ ] Regression: plain `claude` / `codex` still on native auth.
- [ ] `claude-sandbox --copilot-route` — confirms `host.docker.internal` reachability.
- [ ] `codex-sandbox --copilot-route` — confirms the config.toml `base_url` rewrite.
- [ ] Multi-turn agentic run to shake out tool-call translation and the 90s
      stream watchdog (the failure mode that looks like "the model got dumb").
- [ ] Decide whether to auto-start the proxy from `~/.shellrc.local`, or leave it
      on-demand via the wrappers (current behavior).

## Watch list

- Copilot can change model availability per integration ID **silently, with no
  changelog**. If Claude models vanish, re-run `copilot-proxy models --claude`.
- Version bumps need a re-audit — this process holds a corporate credential.
  `copilot-proxy upgrade <ver>` warns about this.
- ToS: GitHub names *"proxy usage"* as a Copilot-revocation trigger, and on a
  Microsoft seat the contracting party is the employer. Accepted deliberately;
  sanctioned alternatives are documented in `AI.md`.
