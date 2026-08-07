# Copilot-backed routing for Claude Code + Codex

Route the Claude Code and Codex harnesses (and direct API calls) through the
company GitHub Copilot entitlement instead of Anthropic/OpenAI keys.

**Status:** implemented and verified end-to-end — host wrappers, both sandboxes,
and custom-port propagation. Remaining gap: a long multi-turn agentic run.

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

## 🔴 Codex gotcha: `--profile` is position-sensitive (cost two debug rounds)

Every codex subcommand declares its **own** `--profile`, so a global one placed
before the subcommand is **silently ignored** — no warning, no error. Codex just
falls through to the `openai` provider:

```
codex --profile copilot exec "…"   # ✗ banner: provider: openai   (silent)
codex exec --profile copilot "…"   # ✓ banner: provider: copilot_proxy
```

`-c` propagates from either position; `--profile` does not.

> **Superseded by round 2:** `--profile` was dropped entirely. Codex 0.147 then
> *hard-errored* on the very `[profiles.copilot]` table 0.116 required. Both
> wrappers now use `-c model_provider="copilot_proxy"`, which behaves identically
> on both versions. Kept here because the silent-fallback failure mode is the one
> to watch for.

Also: profiles in **0.116** live as `[profiles.<name>]` inside `config.toml`.
Newer Codex docs describe standalone `~/.codex/<name>.config.toml` files — that
mechanism does **not** exist in that version, and was the first wrong turn.

**Always verify from the banner: `provider: copilot_proxy`.**

## Verified end-to-end (2026-08-07)

- [x] `copilot-proxy start` → `LISTEN 127.0.0.1:6868`, anonymous → 401.
- [x] `claude-copilot -p …` → `CLAUDE_VIA_COPILOT_OK`.
      (Emits an expected warning that claude.ai connectors are disabled while a
      gateway credential is active.)
- [x] `codex-copilot exec …` → `provider: copilot_proxy`,
      `reasoning effort: high`, `CODEX_VIA_COPILOT_OK`.
- [x] Regression: plain `codex` → `provider: openai`; no `ANTHROPIC_*` /
      `OPENAI_*` leakage into the parent shell.

### Pre-existing, unrelated to this work
Plain `codex exec` fails with `The 'gpt-5.3-codex' model is not supported when
using Codex with a ChatGPT account` — the top-level `model` in `config.toml`
predates this change and isn't available on the current ChatGPT plan. Routing
through Copilot incidentally *fixes* it, since the proxy serves that model.
Codex also floods stderr with `skills::loader` errors from ~dozens of broken
symlinks in `~/.codex/skills` — also pre-existing; worth a separate cleanup.

## Review round 2 (2026-08-07) — 4 issues raised, all reproduced, all fixed

Codex **auto-updated 0.116.0 → 0.147.0 mid-session**, which broke the routing
that had just been verified. Good illustration of why this needs version-proofing.

1. **Codex profile mechanism churn (P1, real).** 0.147 hard-errors:
   `--profile copilot cannot be used while …/config.toml contains legacy
   [profiles.copilot]`. One week earlier, 0.116 *required* that exact table.
   → Fix: dropped `--profile` entirely. Both wrappers now use
   `-c model_provider="copilot_proxy"`, verified working on **both** versions and
   position-insensitive. No `[profiles.copilot]`, no standalone profile file.
2. **Sandbox could not reach the proxy on Linux/WSL (P1, real).**
   `--add-host host.docker.internal:host-gateway` points at the bridge gateway,
   but the proxy binds `127.0.0.1` only. Reproduced: host-gateway → HTTP 000,
   `--network host` → HTTP 200. → Fix: `--network host` on Linux/WSL,
   `host.docker.internal` kept for macOS Docker Desktop.
3. **macOS portability (P1, real).** `ss` is Linux-only, `stat -c` is GNU-only,
   and the M1 Mac is the primary dev machine. → Fix: `listen_addr` / `file_size`
   / `file_mode` shims falling back to `netstat` and `stat -f`.
4. **Destructive installer line (P1, real).** `rm -f ~/.codex/copilot.config.toml`
   ran unconditionally and would have deleted a real user file. → Fix: removes it
   only when it is a symlink whose target is exactly this repo's copy.

## Verified end-to-end (2026-08-07, Codex 0.147.0)

- [x] `codex-copilot exec …` → `provider: copilot_proxy`, `model: gpt-5.4`,
      `reasoning effort: high`.
- [x] `claude-copilot -p …` → OK.
- [x] Regression: plain `codex` → `provider: openai`.
- [x] `codex-sandbox --copilot-route exec …` → `provider: copilot_proxy`
      reaching `http://127.0.0.1:6868` from inside the container.
- [x] `claude-sandbox --copilot-route -p …` → OK.
- [x] Container reaches proxy **with** auth (200 + model list); anonymous from
      inside the container still → 401.

Sandbox runs need a TTY (`ai-sandbox` uses `docker run -it`); test them under
`script -qec "…" /dev/null` from a non-interactive shell.

## Review round 3 (2026-08-07) — P2 custom-port propagation, real, fixed

**Reported:** `.codex/config.toml` hardcodes `127.0.0.1:6868` and
`copilot-route.sh` never overrode `model_providers.copilot_proxy.base_url`, so
`COPILOT_PROXY_PORT` worked for Claude and the sandboxes but silently not for
host Codex. **Reproduced and confirmed.**

Fix: both wrappers now pass the *resolved* URL at launch —
`-c model_providers.copilot_proxy.base_url="${PROXY_URL}/v1"` (host) and
`"${COPILOT_PROXY_CONTAINER_URL}/v1"` (sandbox). The old `sed`-based rewrite of
the container's `config.toml` was deleted rather than repaired: a `-c` override
cannot drift with config formatting.

### Second defect found while verifying it (not reported, fixed)

State files were **not port-scoped** — one shared `proxy.pid` / `proxy.log` for
every port. With two proxies up, `status` printed the *other* instance's pid and
`stop` would kill the wrong process (it did, mid-test). Since
`COPILOT_PROXY_PORT` is a supported override, coexistence has to work:
`PID_FILE`/`LOG_FILE` are now `proxy-<port>.{pid,log}`, with one-time adoption of
the legacy unsuffixed names on the default port.

### Verified (2026-08-07)

Port routing was proven by **observing the actual TCP destination** with
`ss -tnp` during the run, not just by the banner — the banner cannot distinguish
which port the provider resolved to.

- [x] `COPILOT_PROXY_PORT=7373 codex-copilot exec …` → **5 connections to
      `127.0.0.1:7373`, 0 to `:6868`**; `provider: copilot_proxy`,
      `model: gpt-5.4`, `reasoning effort: high`; correct answer returned.
- [x] `COPILOT_PROXY_PORT=7373 claude-copilot -p …` → connections to `:7373`,
      correct answer returned.
- [x] Default port unchanged: `codex-copilot` → `provider: copilot_proxy`.
- [x] Regression: plain `codex` → `provider: openai`.
- [x] A fresh login shell has **no** `ANTHROPIC_*` / `OPENAI_*` vars. (Checked
      with `env -i bash -lc` — a shell spawned *inside* a `claude-copilot`
      session legitimately inherits them, so that is not a valid leakage test.)
- [x] Per-port state: `status` on `:6868` now reports the true `:6868` pid.
- [x] `bash -n` clean on `ai-sandbox.sh`, `copilot-route.sh`, `copilot-proxy.sh`,
      `install.sh`.

> ⚠️ `ai-sandbox.sh` runs its container entrypoint as a **single-quoted**
> `bash -c '…'` string starting at line ~592. An apostrophe in a comment inside
> that block (`config's`, `there's`) silently terminates the quote and breaks the
> whole script. Keep comments in that region quote-free.

## Remaining

- [ ] Multi-turn agentic run to shake out tool-call translation and the 90s
      stream watchdog (the failure that looks like "the model got dumb").
      **This is the last substantive verification gap.**
- [ ] Benign but noisy: codex polls `/v1/models?client_version=…` and the proxy
      answers `404 Provider 'codex' not found or disabled`. Completions are
      unaffected; consider silencing.
- [ ] In-sandbox warning: `Ignored unsupported project-local config keys in
      /workspace/.codex/config.toml: model_providers` — harmless (the user-level
      copy supplies it) but appears because this repo *is* the workspace. The
      same warning shows on the host for the same reason.
- [ ] Decide whether to auto-start the proxy from `~/.shellrc.local`, or leave it
      on-demand via the wrappers (current behavior).
- [ ] Unrelated cleanup: ~30 broken symlinks in `~/.codex/skills` flood stderr
      with `skills::loader` errors (~230 KB per invocation).


## Watch list

- Copilot can change model availability per integration ID **silently, with no
  changelog**. If Claude models vanish, re-run `copilot-proxy models --claude`.
- Version bumps need a re-audit — this process holds a corporate credential.
  `copilot-proxy upgrade <ver>` warns about this.
- ToS: GitHub names *"proxy usage"* as a Copilot-revocation trigger, and on a
  Microsoft seat the contracting party is the employer. Accepted deliberately;
  sanctioned alternatives are documented in `AI.md`.
