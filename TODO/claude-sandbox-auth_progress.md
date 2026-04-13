# claude-sandbox auth drops after ~1 day (long-running container)

## Status: RESOLVED (2026-04-13)

**Root cause confirmed by 3-day instrumented experiment.** The container
script unconditionally seeded `.credentials.json` from the host via `cp -aL`
on every start. The host has long-running `claude` processes in tmux that
rotate the OAuth refresh token roughly every 11h. Because OAuth refresh-token
rotation invalidates the prior token at Anthropic's server, the container's
seeded copy became dead the moment the host did its first rotation (~3.5h
after launch). The container's claude held a valid access token in memory
and kept working until *it* needed to refresh — at which point the dead
refresh token triggered the `/login` prompt.

**Fix**: `scripts/ai-sandbox.sh` flipped the default. Bare `claude-sandbox`
no longer seeds OAuth credentials; the container holds its own grant in the
`claude-home` volume (one `/login` per fresh volume, then multi-day stable).
Old behavior is preserved behind the explicit `--no-login` flag (or
`SANDBOX_NO_LOGIN=1`) for short jobs where the user wants to skip the
interactive `/login`.

**Diagnostic infra (still running, safe to leave)**: hourly cron entry
`15 * * * * ~/claude-sandbox-diag/snapshot.sh` and log
`~/claude-sandbox-diag/snapshots.log`. Useful for one more validation pass
after the first sandbox is relaunched under the new default. Cleanup when
done:

```
crontab -l | grep -v claude-sandbox-diag | crontab -
rm -rf ~/claude-sandbox-diag
rm TODO/claude-sandbox-auth_progress.md
```

---

## Symptom (user-reported)
Launch `claude-sandbox`, use it continuously inside the **same** container for
several days. It works until ~24h in, then prompts `/login`. User re-logs in
inside the container; the prompt returns the next day. Loops.

## What has been ruled out
- **Host clobbering the volume on restart.** This is a single long-running
  container; the ai-sandbox.sh auth sync only runs at container start. The
  volume is not touched by the host between days.
- **Cron / systemd touching credentials.** Only cron entry is the openclaw
  checkpoint; no systemd user units; no claude-related timers.
- **Env var overrides.** No `ANTHROPIC_*` / `CLAUDE_*_TOKEN` in the host shell.
- **Clock drift in the container.** Container `date` matches host to the
  second (Docker shares the host kernel clock).

## Experiment in progress
User launched a fresh claude-sandbox at **2026-04-10 20:46:23 UTC**
(container `great_mendeleev`, id `e3abeb03ea18`, image `ai-sandbox:w1`).

### Baseline (captured 2026-04-10 21:44:57 UTC, claude PID 1 uptime 58:34)
```
creds_mtime:          2026-04-10 16:05:43 UTC   (== host mtime, cp -aL preserved)
creds_size:           471
access_token_prefix:  sk-ant-oat01-XzA4JGqYnrv
refresh_token_prefix: sk-ant-ort01-JmAek_7Snw8
expires_at_ms:        1775865943846  (2026-04-11 00:05:43 UTC, ~3h15m from baseline)
host_creds_mtime:     2026-04-10 09:05:43 PDT   (unchanged since before launch)
```
Container and host share the same refresh token at T=0 (forced `cp -aL` on
container start).

## Hourly snapshot
`~/claude-sandbox-diag/snapshot.sh` is wired into cron at `:15 * * * *` and
appends to `~/claude-sandbox-diag/snapshots.log`. Each snapshot records:
- running claude container id, uptime, PID 1 etime
- volume `.credentials.json` mtime, size, `expiresAt`, first 24 chars of
  access + refresh tokens (enough to detect rotation, not enough to use)
- host `.credentials.json` mtime + refresh token prefix (for cross-check)

Cron verified with `crontab -l`. Log path: `~/claude-sandbox-diag/snapshots.log`.

## What to check when resuming (tomorrow or after /login prompt)
1. `cat ~/claude-sandbox-diag/snapshots.log` — walk forward from baseline.
2. **Expected healthy pattern**: around T+3h (first access-token expiry) the
   `refresh_token_prefix` changes and `expires_at_ms` jumps forward. Subsequent
   refreshes every few hours do the same. `creds_mtime` advances each time.
3. **Failure modes to look for**:
   - `refresh_token_prefix` **never rotates** → claude isn't persisting refreshed
     tokens to `.credentials.json` (in-memory only); next container restart
     would then lose auth, but *this* scenario wouldn't explain failure in a
     still-running container. Keep looking.
   - `refresh_token_prefix` rotates once, then snapshots stop changing → refresh
     stopped working at a specific time. Note the timestamp and compare to
     when the `/login` prompt appeared.
   - `creds_mtime` advances but `expires_at_ms` stays fixed → bug in the
     written payload.
   - Container disappears (`container_id: <none>`) → claude exited; not a
     refresh issue but a process-death issue.
   - `host_refresh_token_prefix` changes mid-experiment → something on the host
     is writing to host creds (shouldn't happen; would mean user ran
     `claude` on host too, or another sandbox instance).
4. `docker exec <cid> bash -c 'ls -la /root/.claude; cat /tmp/install.log 2>/dev/null | tail'`
   to see if anything in the container wrote errors.
5. When the user reports `/login` showed up, note the approximate host time
   and correlate with the nearest snapshot.

## Cleanup when done
- `crontab -l | grep -v claude-sandbox-diag | crontab -`
- `rm -rf ~/claude-sandbox-diag`

## Hypotheses to confirm/refute with the data
- **H1**: Anthropic refresh tokens have a hard lifetime (~24h) and after that
  the only remedy is `/login`. → Data: `expires_at_ms` stops advancing around
  T+24h regardless of container activity. If true, there's no sandbox fix;
  the right move is to document it and possibly wire up a periodic host-side
  re-login mechanism.
- **H2**: Claude CLI refreshes tokens in memory but fails to persist to
  `.credentials.json` under some code path (e.g. when the file was seeded with
  an older mtime via `cp -aL`). → Data: `creds_mtime` never advances.
- **H3**: Docker's default DNS / network gets stale after ~24h on this host
  and refresh requests fail. → Data: `expires_at_ms` advances fine for the
  first N refreshes, then stops at a specific wall-clock time tied to an
  external cause (network change, DNS TTL, etc.).
- **H4**: The bind-mounted `/host-agent-home` (readonly) causes claude to
  read stale credentials at some point (e.g. if it re-reads the file and
  something replaces the fd). → Unlikely but keep in mind.
