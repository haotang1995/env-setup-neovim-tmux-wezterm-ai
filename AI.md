# Terminal Dev Environment — Dotfiles & Setup

Portable, keyboard-driven terminal development environment built around
**WezTerm + tmux + Neovim (LazyVim) + AI agents**. Designed to be deployed
across macOS, Win11/WSL, and headless Linux (HPC clusters via SSH).

## Project purpose

This repo is the **single source of truth** for the owner's terminal config.
It serves two goals:

1. **Iterate & improve** — configs are edited here, tested locally, then
   deployed to `~` / `~/.config/` on each machine.
2. **Fast (re)deployment** — clone the repo on a new machine, run the deploy
   script, and have a fully working environment in minutes.

When making changes, always consider cross-platform impact (macOS / WSL /
headless Linux). Configs should degrade gracefully — e.g. VimTeX disables
the viewer on headless, WezTerm detects the OS for font size and keybindings.

## Architecture

```
WezTerm (terminal emulator, cross-platform)
 └─ tmux (session/window/pane persistence, SSH detach/reattach)
     ├─ Neovim  (LazyVim distribution)
     │   ├─ LSP          (language intelligence)
     │   ├─ avante.nvim  (disabled — Cursor-like AI agent, Claude API)
     │   ├─ copilot.lua  (inline ghost-text completions)
     │   └─ VimTeX       (LaTeX compilation + forward search)
     ├─ Terminal pane     (shell, git, builds)
     └─ AI Agent Popups   (gemini, claude, codex, copilot, aider)
```

## Repo layout

```
AI.md                            ← you are here
wezterm.lua                      ← WezTerm config (→ ~/.wezterm.lua)
tmux.conf                        ← tmux config    (→ ~/.tmux.conf)
zshrc                            ← zsh config     (→ ~/.zshrc)
bashrc                           ← bash config    (→ ~/.bashrc; auto-execs zsh if available)
k_shortcuts.sh                   ← kubectl/helm shortcuts (→ ~/.k_shortcuts.sh; sourced by zsh+bash)
shellrc.local.example            ← Template for ~/.shellrc.local (machine-local, gitignored)
scripts/                         ← Utility scripts for global use
  install.sh                     ← Installer (symlinks scripts + configs + skills)
  init-ai.sh                     ← Unified AI context bootstrapper
  ai-sandbox.sh                  ← Unified Docker sandbox (claude/gemini/codex/copilot)
  ai-sandbox.Dockerfile          ← Shared sandbox image (ubuntu:24.04 + Node 22 + all four CLIs)
  openclaw-sandbox.sh            ← Long-running OpenClaw dev sandbox (start/stop/exec/status/destroy)
  openclaw-sandbox.Dockerfile    ← OpenClaw sandbox image (ubuntu:24.04 + Node 24 + sudo user)
  checkpoint-openclaw.sh         ← Checkpoint openclaw-live (docker commit + volume backup)
  restore-openclaw.sh            ← Restore openclaw-live from a checkpoint
  review_skills.py               ← Interactive keep/remove review for skills
  gpu-util-monitor.sh            ← Cheap long-horizon GPU-util tracking (cron sample + report)
  copilot-proxy.sh               ← Local GitHub Copilot → OpenAI/Anthropic bridge (start/stop/status/env)
  copilot-route.sh               ← claude-copilot / codex-copilot wrappers (harness → Copilot proxy)
ai-skills/                       ← Shared AI skill library
  README.md                      ← Skill format docs & cross-agent reference
  .repos/superpowers/            ← git submodule: obra/superpowers
  .repos/openai-skills/          ← git submodule: openai/skills
  .repos/tob-skills/             ← git submodule: trailofbits/skills
nvim-config/                     ← Neovim config  (→ ~/.config/nvim/)
  init.lua                       ← LazyVim entry point
  lazyvim.json                   ← LazyVim metadata
  lazy-lock.json                 ← plugin lockfile (gitignored; machine-local)
  stylua.toml                    ← Lua formatter config
  lua/config/
    lazy.lua                     ← lazy.nvim bootstrap + LazyVim extras
    options.lua                  ← editor options, clipboard, providers
    keymaps.lua                  ← custom key mappings
    autocmds.lua                 ← autocommands (reload, filetype, trim whitespace)
  lua/plugins/
    ai.lua                       ← copilot.lua + CopilotChat (avante.nvim disabled)
    vimtex.lua                   ← VimTeX overrides (lualatex engine, platform-detecting viewer)
    markdown.lua                 ← render-markdown.nvim + markdown-preview.nvim
    tmux-navigator.lua           ← vim-tmux-navigator (Ctrl+hjkl across panes)
.gemini/                         ← Gemini agent config  (→ ~/.gemini/settings.json)
.claude/                         ← Claude agent config  (→ ~/.claude/settings.json)
.codex/                          ← Codex agent config   (→ ~/.codex/config.toml)
.github/copilot-instructions.md  ← Copilot instructions (symlink → AI.md)
```

## Target machines

| Machine | OS | Sudo? | Notes |
|---------|----|-------|-------|
| MacBook (M1) | macOS | yes | Primary dev machine. Homebrew. |
| Win11 laptop | WSL Ubuntu | yes (inside WSL) | WezTerm on Windows side, everything else in WSL. |
| HPC cluster | Linux (various) | **no** | SSH-only, no GUI. AppImage/tarball installs to `~/local/bin/`. |

## Key conventions

### Neovim

- **Distribution:** LazyVim. Don't fight its defaults — override only when needed.
- **Plugin manager:** lazy.nvim (bundled with LazyVim).
- **LazyVim Extras enabled:** `lang.tex`, `lang.markdown`, `editor.mini-files`.
- **Markdown rendering parsers:** ensure `markdown`, `markdown_inline`, `latex`, and `html` tree-sitter parsers are installed.
- **Markdown math in-buffer:** `render-markdown.nvim` may rely on tools such as `utftex` or `latex2text` depending on your setup.
- **Custom plugins** go in `lua/plugins/<name>.lua`, one file per logical group.
- **Keymaps:** `jk` = exit insert, `\cc` = toggle comment, `Ctrl+d/u` = scroll centered.
- **Leader key:** `<Space>` (LazyVim default).
- **Conceal level 2** globally (shows α instead of \alpha in LaTeX).
- **OSC 52 clipboard** auto-enabled when `SSH_TTY` is set (copy works over SSH).
- **Auto-reload** files changed by external tools (Claude Code / Aider in tmux pane).
- **Trim trailing whitespace** on save, except in markdown.

### tmux

- **Prefix:** `Ctrl+B` (default, works everywhere).
- **Pane navigation:** `Ctrl+hjkl` seamlessly crosses Neovim splits and tmux panes
  (via `is_vim` detection in tmux + vim-tmux-navigator in Neovim).
- **Splits:** `prefix + |` or `\` (vertical), `prefix + -` (horizontal), in cwd.
- **Vi copy mode:** `v` to select, `y` to yank, `Ctrl+V` for block select.
  Copy uses explicit OSC 52 via `#{pane_tty}` (not tmux's built-in
  `set-clipboard`) for reliable clipboard through multi-hop SSH
  (WezTerm → WSL → SSH → tmux). Mouse drag-release also copies.
- **Hyperlinks:** OSC 8 passthrough enabled so clickable URLs work inside tmux.
  `Shift+Ctrl+Click` (or `Shift+Cmd+Click` on macOS) to open in browser.
  Shift bypasses tmux mouse capture.
- **Status bar:** top, minimal, Catppuccin-ish colors.
- **AI agent windows:** `gemini`, `claude`, `codex`, `copilot` in windows 2-5.
  Opt-in (not automatic):
  - **On session creation:** `TMUX_AI=1 tmux new -s work`
  - **On demand:** `prefix + A` (WIP — binding needs quoting fix)

### WezTerm

- **Single `wezterm.lua`** with platform detection (`is_mac` / `is_windows` / `is_linux`).
- **macOS:** Cmd+letter → Ctrl+letter (25 of 26), matching old iTerm2 behavior.
  Exception: Cmd+V → paste (not Ctrl+V). WezTerm-native actions (zoom, tabs)
  use Cmd directly.
- **Windows:** auto-launches into `WSL:Ubuntu` via `default_domain`.
- **Font:** JetBrains Mono + Symbols Nerd Font Mono fallback.
  Sizes: 17pt Mac, 14pt Windows, 15pt Linux.
- **Colors:** ported from iTerm2 "G33" profile (black bg, gray fg, classic ANSI).
- **New tab:** `Cmd+Shift+T` (macOS) / `Ctrl+Shift+T` (Windows/Linux).
- **Move tab left/right:** `Cmd+Shift+Left/Right` (macOS) / `Ctrl+Shift+Left/Right` (Windows/Linux).
- **Rename tab:** `Cmd+Shift+E` (macOS) / `Ctrl+Shift+E` (Windows/Linux).
- **Fullscreen:** `Cmd+Shift+F` (macOS) / `Ctrl+Shift+F` (Windows/Linux).
- **Kitty graphics protocol** enabled for in-terminal images/PDF.
- **Ctrl+hjkl** explicitly passed through (never intercepted by WezTerm).

### Shell (zsh / bash)

- **Primary shell:** zsh via oh-my-zsh. `bashrc` auto-`exec`s `/usr/bin/zsh`
  when present, so a fresh login lands you in zsh even when the system default
  is bash.
- **The "autocomplete" experience** comes from three sources, all configured in
  `zshrc`:
  - `zsh-autosuggestions` — gray ghost-text from history, `→` to accept.
  - `zsh-syntax-highlighting` — live command coloring as you type.
  - oh-my-zsh per-tool tab-completion (`git`, `docker`, `python`, `node`,
    `npm`, `nvm`).
- **Theme:** `robbyrussell` (oh-my-zsh default).
- **Aliases:** `gs/gd/gds/gp/gl/glog`, `ll/la/l`, `..`/`...`, `dc/dps`,
  `py/serve/ports`, `reload`, `myip`, `weather`. See `zshrc` for the full list;
  `bashrc` mirrors them for the rare bash-only session.
- **Machine-local secrets / per-host env** live in `~/.shellrc.local`
  (gitignored, mode 0600). Both rc files source it at the end. Use this for
  `WANDB_KEY`, `HF_TOKEN`, conda PATH, etc. Template:
  `shellrc.local.example` in the repo.
- **First-run migration:** when `install.sh` replaces an existing `~/.zshrc`
  or `~/.bashrc`, it scans for lines matching common secret patterns
  (`*_KEY`, `*_TOKEN`, `*_SECRET`, `*_API_KEY`, `*_PASSWORD`, krew `PATH`)
  and appends them to `~/.shellrc.local` **before** backing up the old files.
  Anything else lives in the timestamped `dotfiles_backup_*` dir for manual
  review.
- **oh-my-zsh bootstrap:** `install.sh` clones oh-my-zsh and the two plugins
  (`zsh-autosuggestions`, `zsh-syntax-highlighting`) into
  `$ZSH/custom/plugins/` if missing. Skipped with a warning when `zsh` isn't
  installed (e.g. very stripped HPC nodes) — bash still gets the alias set
  and `~/.shellrc.local` sourcing.
- **kubectl/helm shortcuts (`k_shortcuts.sh`):** symlinked to `~/.k_shortcuts.sh`
  and sourced by both `zshrc` and `bashrc`. Provides `kpods`, `klogs`, `ksh`,
  `krun`, `kev`, `kpf`, `kgpu`, `knodes`, `kgpumon`, `kduc`, `kducs`, `kduci`,
  `kduc-install`, `kh`, `khrm`, `khclean`. Defaults
  to namespace `bonete51` and user `$(whoami | cut -d@ -f1)`; override via
  `KNS=otherns KUSER=somebody <cmd>` or by setting them in `~/.shellrc.local`
  (sourced after `k_shortcuts.sh`, so those overrides win).
  - **PVC disk usage (`kduc`):** wraps the GCR `kubectl duc` plugin (PVC Storage
    Viewer / gcr-duc), injecting `-n $KNS` unless the caller passes
    `-n/--namespace`. Bare `kduc` opens the interactive disk-usage UI; `-p NAME`
    targets a specific PVC and `-l` prints the UI navigation legend. `kducs`
    (indexer status) and `kduci` (launch a one-off index job) are shorthands for
    `kduc status` / `kduc index`; `help` and `version` subcommands pass through
    without a namespace. Note the DUC tree is rooted at the **PVC root** (the
    indexer mounts the PVC at `/bonete51-pvc`), not at the `/data` mount your
    pods see — so `/data/users/<you>` appears in the viewer as `users/<you>`
    under the root.
  - **Installing the plugin (`kduc-install`):** the `duc` plugin is **not** in
    the public krew index — it ships as gated artifacts on the GCR "PVC Storage
    Viewer" Azure DevOps wiki page. Download both `kubectl-duc_linux.tar.gz` and
    `kubectl-duc-krew-manifest-linux.yaml` (Linux/WSL), drop them in
    `./kubectl-dev/` (gitignored — internal MSR tooling, not redistributed via
    this repo), `~/kubectl-dev/`, or `~/Downloads/`, then run `kduc-install`
    (or `kduc-install <dir>` / `KDUC_ARTIFACT_DIR=<dir> kduc-install`). It
    resolves the artifact pair, checks `kubectl` + `krew`, runs
    `kubectl krew install --manifest=… --archive=…`, and is idempotent (reports
    the installed version if `duc` is already present, listed by krew as
    `detached/duc`). Requires krew (installed during GCR SSO setup).

### Scripts

- **Location:** `scripts/` directory.
- **Installation:** Run `./scripts/install.sh` to symlink scripts to `~/.local/bin/`
  and config files (`wezterm.lua`, `tmux.conf`, `nvim-config/`, `.gemini/`, `.claude/`, `.codex/`) to their home locations.
  Copilot reads `.github/copilot-instructions.md` (symlinked to `AI.md` by `init-ai`)
  and manages its own `~/.copilot/config.json` (auth tokens); `install.sh` only
  ensures `~/.copilot/` exists for the skills directory.
  - **WSL note:** `wezterm.lua` is **copied** (not symlinked) to the Windows
    user profile (`C:\Users\<user>\.wezterm.lua`) because Windows apps cannot
    follow symlinks into `\\wsl$\...`. Re-run `install.sh` after editing
    `wezterm.lua` to push changes to Windows.
  - Use `./scripts/install.sh -u` (or `--update`) to pull the latest repo changes,
    update AI skill submodules, and re-run the linking process.
- **Naming:** Scripts are symlinked without the `.sh` extension for cleaner CLI usage.
- **`init-ai`:** Bootstraps `AI.md`, `TODO/TODO.md`, copies the default sandbox `Dockerfile` (`ai-sandbox.Dockerfile`), initializes a no-op `install.sh` when missing, and links `AI.md` to `CLAUDE.md`, `GEMINI.md`, `CODEX.md`, and `.github/copilot-instructions.md` in the current directory.
- **`ai-sandbox`:** Unified Docker sandbox for all four AI CLI agents. Usage:
  `ai-sandbox [--rebuild] [--gpu|--no-gpu] [--gpu-device ID] <claude|gemini|codex|copilot> [args...]`,
  or via backward-compat symlinks (`claude-sandbox`, `gemini-sandbox`,
  `codex-sandbox`, `copilot-sandbox`). Run `ai-sandbox --help` (or `-h`) for
  the full list of flags, env vars, and image-selection rules.
  All agents share a single Docker image (built from `scripts/ai-sandbox.Dockerfile`,
  based on `ubuntu:24.04` with python3, build-essential, ripgrep, Node.js 22, all
  four CLIs, and `wandb`) pre-installed at build time for near-instant startup.
  **Biweekly auto-rebuild:** the default image uses a rotating tag (`ai-sandbox:w0`
  / `ai-sandbox:w1`) based on ISO week number, so every other week the tag flips,
  the old image is unused, and a fresh build picks up the latest CLI versions.
  At most two default images exist at any time.
  **Force rebuild:** pass `--rebuild` (or set `SANDBOX_REBUILD=1`) to force a
  `docker build --no-cache` even when the image already exists — useful for
  mid-week CLI updates.
  **GPU passthrough:** auto-detected by default — enabled only when
  `nvidia-smi -L` runs successfully and lists at least one adapter (the
  presence of Docker's nvidia runtime alone is not enough, since on WSL
  hosts with the toolkit installed but no GPU exposed `--gpus all` errors
  out with "no adapters were found"). Override with `--gpu` / `--no-gpu`
  flags or `SANDBOX_GPU=1|0` env var. Passes `--gpus all` to `docker run`.
  Use `--gpu-device ID` (or `SANDBOX_GPU_DEVICE=ID`) to pass through a
  specific GPU instead of all (e.g. `--gpu-device 0`); implies `--gpu`.
  **Sibling containers:** pass `--docker-sock` (or `SANDBOX_DOCKER_SOCK=1`) to
  mount `/var/run/docker.sock` into the sandbox. Any `docker run` calls inside
  the agent then start on the host daemon alongside (not inside) the sandbox —
  shared image cache, no nested storage drivers. The `docker` CLI
  (`docker-ce-cli`) is pre-installed in the default image so agents can use it
  immediately. Skipped with a warning when the socket is absent. Warning:
  grants root-equivalent access to the host Docker daemon — only use on
  machines you control.
  **Copilot routing:** pass `--copilot-route` (or `SANDBOX_COPILOT_ROUTE=1`) with
  `claude` or `codex` to back the sandboxed agent with the host's `copilot-proxy`
  instead of its native auth. The proxy binds host loopback, which is the
  *container itself* from inside, so the launcher maps
  `host.docker.internal:host-gateway` and rewrites the URL — a bare `-e` passthrough
  of `ANTHROPIC_BASE_URL` would leak `127.0.0.1` into the container. For codex there
  is no env passthrough for provider config at all, so the container's `config.toml`
  `base_url` is rewritten at startup and `copilot.config.toml` is copied in from
  `/host-agent-home`. Fails fast if the proxy isn't running or the key is missing.
  **W&B (Weights & Biases):** token is resolved from `WANDB_KEY` > `WANDB_TOKEN`
  > `WANDB_API_KEY` env vars > `~/.bashrc` extraction, and passed into the
  container as both `WANDB_API_KEY` (Python library) and `WANDB_KEY` (MS Research
  convention). `WANDB_BASE_URL` defaults to `https://microsoft-research.wandb.io`.
  Optional env vars `WANDB_PROJECT`, `WANDB_ENTITY`, `WANDB_RUN_GROUP`, and
  `WANDB_MODE` are passed through when set.
  **Hugging Face:** token is resolved from `HF_TOKEN` > `HUGGING_FACE_HUB_TOKEN`
  > `HUGGINGFACE_TOKEN` env vars > `~/.bashrc` extraction, and passed into the
  container as both `HF_TOKEN` (modern) and `HUGGING_FACE_HUB_TOKEN` (legacy).
  Optional env vars `HF_HOME`, `HF_HUB_CACHE`, and `HF_ENDPOINT` are passed
  through when set.
  **Azure CLI / TRAPI:** host `~/.azure` is bind-mounted read-only at
  `/host-azure` and copied into the container's `~/.azure` at startup, so
  `AzureCliCredential()` (and any other `az` subcommand) inside the container
  reuses the host's `az login` session. `azure-cli` is pre-installed in the
  default image. Refresh tokens written during the container session stay
  inside the container and never mutate the host profile. Enables TRAPI
  (`api://trapi/.default`) and any other Azure AD OAuth scope.
  Supports Dockerfile selection: `SANDBOX_DOCKERFILE` > `./Dockerfile` > default.
  Mounts `/workspace`, agent home (named volume), repo (read-only), npm cache.
  Mirrors host git config, marks `/workspace` as a Git `safe.directory`, and
  auto-mounts external Git metadata paths (`git-dir` / `git-common-dir`) when
  running inside linked worktrees. Agent-specific behavior:
  **claude** — extra named volumes for `/root/.config` and `/root/.local/share`,
  mounts `~/.claude.json` and `~/.config/claude{,-code}`, macOS Keychain credential
  extraction (service `Claude Code-credentials`), Anthropic env var passthrough.
  Bind-mounts host `~/.claude/projects/` read-write over the agent-home volume
  so chat transcripts (used by `/resume`) persist on host disk regardless of
  the per-workspace volume name.
  **Per-workspace agent-home volume**: the volume name is
  `claude-home-<workspace>` where `<workspace>` defaults to the sanitized
  basename of the launch directory (lowercased, non-alphanumerics collapsed
  to `-`, with `default` as the fallback). Override with `--workspace NAME`
  or `SANDBOX_WORKSPACE=NAME`. This keeps two concurrent claude sandboxes
  (e.g. in different projects) from sharing one OAuth grant and racing on
  refresh-token rotation. Launch logs the resolved workspace + volume name
  so you can see where your state lives. Only claude uses this scheme; the
  other agents keep the single shared `*-home` volume.
  Auth handling has two modes:
  - **Default (`--no-login` / `SANDBOX_NO_LOGIN=1`)** — copies `.claude.json`
    and `.credentials.json` from the host on every start (and uses macOS
    Keychain when present). The container shares the host's OAuth refresh
    chain; Anthropic rotates these tokens roughly every 11h and the
    container typically loses auth within ~1 day. Suitable for most jobs.
  - **`--login` (or `SANDBOX_NO_LOGIN=0`)** — credentials are **not** seeded
    from the host. The container holds its own OAuth grant inside the
    `claude-home` volume; the first launch on a fresh volume prompts `/login`
    once and subsequent launches reuse it. This grant is independent of host
    token rotations, so a single container can run for many days without re-auth.

  Non-auth agent-home files and `~/.config/claude{,-code}/` use no-clobber seeding in both modes;
  drops to non-root user matching the host UID/GID (`HOST_UID`/`HOST_GID` env vars,
  defaults to 1000) via `setpriv` then launches with `--dangerously-skip-permissions`;
  **gemini** — full `cp -aL` sync from host `~/.gemini`, strips macOS-only
  `sandbox-exec` setting, disables auto-update, launches with `--sandbox false --yolo`;
  **codex** — selective `auth.json`/`config.toml` refresh, legacy `~/.codex/.codex/skills`
  migration; bind-mounts host `~/.codex/sessions` and `~/.codex/history.jsonl`
  read-write so chat transcripts and prompt history sync to the host (auth
  and settings stay read-only); drops to non-root user matching host UID/GID
  via `setpriv`, launches with `--sandbox danger-full-access`;
  marks `/workspace` as `trust_level = "trusted"` in the container's
  `config.toml` so the "Do you trust this directory?" prompt doesn't reappear
  every session (the sandbox already runs with full access anyway);
  **copilot** — no-clobber sync from host `~/.copilot`, merges host config keys
  into container `config.json` without clobbering auth tokens (no keychain in
  Docker), always refreshes `mcp-config.json`; resolves a GitHub token from
  `GITHUB_TOKEN`/`GH_TOKEN` env, macOS Keychain (`copilot-cli`), or
  `gh auth token` (GitHub CLI) and passes it as `GITHUB_TOKEN`;
  drops to non-root user matching host UID/GID via `setpriv`,
  launches with `--yolo`.
  Bootstraps skills when missing/empty or only broken symlinks are present.
  Falls back to `npm i -g` only when the CLI binary is not found (custom Dockerfiles).
  **Writable agent config:** the repo is bind-mounted read-only at its host
  path, and `install.sh` (run inside the container for the skill bootstrap)
  symlinks `~/.codex/config.toml` and `~/.<agent>/settings.json` back into it.
  Agents that persist settings then fail (`failed to persist config.toml`).
  The launcher therefore de-symlinks those two files — before seeding and
  again after the skill bootstrap — replacing any link into the repo with a
  real copy in the agent-home volume. This also repairs volumes where an
  earlier run already left a symlink behind.
- **`openclaw-sandbox`:** Long-running Docker sandbox for OpenClaw development.
  Unlike `ai-sandbox` (ephemeral, per-session), this container persists for months.
  Usage: `openclaw-sandbox <start|stop|exec|status|destroy> [--rebuild] [--gpu|--no-gpu]`.
  Built from `scripts/openclaw-sandbox.Dockerfile` (ubuntu:24.04 + Node 24 +
  build-essential + sudo user `claw`, no OpenClaw pre-installed — user builds
  their own inside the container).
  **Security:** the container can **only** see `~/agent-folder-check-security`
  mounted at `/workspace` — no other host paths, no host auth mirroring.
  Credentials are managed entirely inside the container.
  State persists in a named Docker volume (`openclaw-home`) mounted at `/home/claw`.
  Container name: `openclaw-live`, restart policy: `unless-stopped`.
  GPU passthrough auto-detected (override with `--gpu`/`--no-gpu` or `SANDBOX_GPU`).
  On start (and restore), the `claw` user is remapped to the host UID/GID via
  `usermod`/`groupmod` so files in `/workspace` keep host ownership; the
  container runs as root for the remapping then drops to `claw` via `setpriv`.
  **Checkpointing:** `openclaw-sandbox start` auto-installs a host cron job that
  runs `checkpoint-openclaw` every 6 hours. Each checkpoint performs a
  `docker commit` (→ `openclaw-snap:<timestamp>` image) plus a volume tar backup
  (→ `~/openclaw-checkpoints/volume-<timestamp>.tar.gz`) with a manifest file.
  Snapshots older than 30 days are pruned (override with `CHECKPOINT_KEEP_DAYS`).
  Manual checkpoint: `checkpoint-openclaw [custom-tag]`.
  **Restore:** `restore-openclaw [--latest | <tag>] [--gpu|--no-gpu]` stops the
  current container, restores the committed image + volume archive, and starts
  a new container. Run `restore-openclaw` with no args to list available checkpoints.
- **`copilot-proxy`:** Local bridge that backs Claude Code, Codex, and direct API
  calls with the **GitHub Copilot** entitlement instead of Anthropic/OpenAI keys.
  Runs [`caozhiyuan/copilot-api`](https://github.com/caozhiyuan/copilot-api)
  (npm `@jeffreycao/copilot-api`, **pinned** in the script) as a loopback service
  on `127.0.0.1:6868` (override with `COPILOT_PROXY_PORT`), exposing
  `/v1/messages` (Anthropic), `/v1/responses` and
  `/v1/chat/completions` (OpenAI), `/v1/models`, `/v1/embeddings`.
  Subcommands: `start|stop|restart|status|auth|models|usage|logs|key|env|upgrade`.
  - **First run:** `copilot-proxy auth` (GitHub device flow — its own OAuth grant,
    stored at `~/.local/share/copilot-api/`, independent of the Copilot CLI's and
    separately revocable). Then `copilot-proxy start`.
  - **Direct API use:** `eval "$(copilot-proxy env --openai)"` sets
    `OPENAI_BASE_URL`/`OPENAI_API_KEY` for the current shell;
    `--anthropic` does the same for `ANTHROPIC_*`; bare `env` emits the neutral
    `COPILOT_PROXY_URL`/`COPILOT_PROXY_KEY`, which is what `~/.shellrc.local`
    holds. Prefer the neutral vars globally — exporting `OPENAI_BASE_URL`
    machine-wide would silently redirect every other OpenAI client.
  - **⚠️ Two upstream defaults are unsafe and are corrected by this script.**
    (1) There is **no `--api-key` flag** — unknown flags are silently ignored and
    the server then runs with **no auth at all**; auth works only via
    `auth.apiKeys` in `~/.local/share/copilot-api/config.json`.
    (2) `serve()` is called without a hostname, so it binds `*:<port>` and is
    reachable from the LAN; `HOST=127.0.0.1` fixes it. `start` refuses to run if
    an anonymous `/v1/models` request does not return 401.
  - **Model IDs differ by family:** Claude uses dashes (`claude-opus-5`,
    `claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5`), GPT uses dots
    (`gpt-5.5`, `gpt-5.3-codex`). `copilot-proxy models [--claude|--gpt]` lists
    what the seat actually exposes — this varies and can change silently.
  - **Cost model:** Copilot performs **no prompt-cache writes**, and since
    Jun 2026 bills by token against a monthly AI-credits allowance. An agentic
    harness re-sends a growing conversation every turn, so this burns the
    allowance much faster than request-based intuition suggests.
  - **⚠️ Policy:** this routes a **corporate** Copilot seat through a third-party
    client that presents itself as VS Code (`copilot-integration-id: vscode-chat`
    plus a synthetic persistent device ID). GitHub's Copilot-restriction notice
    names *"proxy usage"* as a revocation trigger, and on Business/Enterprise the
    contracting party is the employer. Sanctioned alternatives that need no proxy:
    OpenCode on Copilot, the Copilot CLI, or `CLAUDE_CODE_USE_FOUNDRY=1` for
    Claude Code on Microsoft Foundry.
- **`copilot-route`** (`claude-copilot`, `codex-copilot`): argv[0]-dispatched
  wrappers — same idiom as the `*-sandbox` symlinks — that start the proxy if
  needed and launch the harness against it. **Plain `claude` and `codex` are
  untouched and keep native auth.** This split is deliberate:
  `~/.claude/settings.json` and `~/.codex/config.toml` are symlinks *into this
  repo*, so putting proxy env in them would route every session through Copilot
  and hard-fail whenever the proxy is down.
  - claude: sets `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` (Bearer — not
    `ANTHROPIC_API_KEY`, which triggers an interactive approval prompt), the
    three `ANTHROPIC_DEFAULT_*_MODEL` tiers, and disables non-essential traffic
    and experimental betas (Copilot rejects beta headers it doesn't know).
    Override models via `CLAUDE_COPILOT_{OPUS,SONNET,HAIKU}`.
  - codex: runs `codex --profile copilot`. The provider is defined once in
    `.codex/config.toml` as `[model_providers.copilot_proxy]` (**inert** until a
    profile selects it) with `wire_api = "responses"` — mandatory, since Codex
    removed the chat/completions wire API in Feb 2026. The profile itself lives
    in `.codex/copilot.config.toml` → `~/.codex/copilot.config.toml`, because
    `model_providers` cannot be set from project-level config. Override the model
    via `CODEX_COPILOT_MODEL`.
- **`review_skills.py`:** Interactive skill decision tool (`y/n/q`) that writes
  `ai-skills/skill-decisions.json` and, by default, applies each answer
  immediately to `~/.claude/skills`, `~/.codex/skills`, `~/.gemini/skills`, and `~/.copilot/skills`.
- **`gpu-util-monitor`:** Cheap, long-horizon GPU **utilization** tracking for a
  namespace (complements `kgpu`/`knodes`, which show GPU *allocation*, not live
  busy-ness — the K8s API has no GPU-util data, so this reads it via `nvidia-smi`
  exec). Each `sample` logs one CSV row per GPU pod incl. the pod's **node**
  (`.spec.nodeName`) to `~/gpu-util-logs/<ns>.csv`. Subcommands:
  - `sample` — exec `nvidia-smi` once in every Running pod (skips CPU-only pods);
    self-migrates an older-schema log out of the way if the header changed.
  - `report` — boxed, colour-graded scorecard ranking pods worst→best by mean
    GPU-compute util (chronic under-users at top); `IDLE%` column = share of
    samples under 5% util (flags bursty pods that look OK on average but idle most
    of the time); `--top N` to trim.
  - `idle` — node-first list of continuous idle **streaks** (longest per pod) in
    the form `NODE  POD  N GPU  idle 4h 21m  (start → end)  ●now`, sorted by
    duration, with a total `GPU·h wasted` summary; `--min-idle MIN` (default 60)
    filters short streaks. This mirrors the "idle pods" view other teams get from
    a cluster DCGM/Prometheus pipeline — which we confirmed is **not reachable at
    our RBAC level** (only metrics-server CPU/mem is exposed) — the difference is
    our window granularity equals the sample interval (≈2h), not minute-precise.
  - `install-cron` / `uninstall-cron` — self-installing crontab entry, default
    every 2h (`--every H` to change); `status` — cron state + log summary.

  Deliberately stateless-per-run: cron supplies the time spacing, so nothing
  depends on a week-long `sleep` that dies on SSH/laptop sleep. Namespace resolves
  from `-n`/`--namespace` > `$KNS` > `bonete51`; log path overridable via
  `$GPU_MON_LOG`. All reports auto-disable colour when not a TTY (clean pipes).
  Also exposed as `kgpumon <sub>` in `k_shortcuts.sh` (forwards the current
  `$KNS`).

### AI integration

- **CLI Agents (via tmux windows):**
  - `gemini`: Google's Gemini CLI for quick codebase queries and tasks.
  - `claude`: Claude Code for agentic coding and complex refactors.
  - `codex`: Codex CLI for AI-powered shell assistance and automation.
  - `copilot`: GitHub Copilot CLI for agentic coding with GitHub integration.
  - `aider`: Aider for AI pair programming (requires installation).
- **avante.nvim:** disabled (config preserved in `ai.lua`; flip the
  `avante_enabled` local at the top of the file to re-activate — it gates
  both the avante spec and the blink.cmp compat sources together, since the
  compat sources require `blink.compat.source`, which only ships as an
  avante dependency).
- **copilot.lua:** inline ghost-text, `<Tab>` to accept. Needs Node 22+ and `:Copilot auth`.
- **CopilotChat.nvim:** quick Q&A via `<leader>ac`.
- **Shared skill library (`ai-skills/`):** Cross-agent skills from
  obra/superpowers, openai/skills, trailofbits/skills,
  K-Dense-AI/claude-scientific-skills, and Orchestra-Research/AI-Research-SKILLs
  added as git submodules. `install.sh` symlinks each skill into
  `~/.claude/skills/`, `~/.codex/skills/`, `~/.gemini/skills/`, and
  `~/.copilot/skills/`. Update
  with `./scripts/install.sh -u` (or `git submodule update --remote`).
  Skill decisions in `ai-skills/skill-decisions.json` are enforced on each
  install run (denied skills are skipped and existing denied links are removed).
  Manage decisions with `python3 scripts/review_skills.py`:
  `--skill <name>` for one skill, `--redo` to revisit already-decided skills,
  and `--no-apply` for record-only mode.

## Editing guidelines

- Keep configs **minimal and well-commented** — future-you on a new machine
  will thank present-you.
- When adding a Neovim plugin, put it in the appropriate `lua/plugins/*.lua`
  file (or create a new one if it's a new category). One return table per file.
- When changing a keymap, check for conflicts with LazyVim defaults
  (`:Lazy keys` or which-key popup with `<Space>`).
- Test changes locally before committing. For Neovim: `:Lazy sync` then
  `:checkhealth`. For tmux: `prefix + r` reloads. For WezTerm: auto-reloads
  on save (or `Cmd+Shift+R`).
- Treat each environment change as a **sync workflow**:
  1. implement the feature/fix in the relevant config/scripts;
  2. verify cross-platform behavior or graceful fallback (macOS / WSL / headless Linux);
  3. update `AI.md` in the same change so setup and conventions stay reproducible on new machines.
- Before finalizing any local repo update (`git commit`, amend, rebase, merge, push),
  explicitly check whether `AI.md` should be updated; if behavior, workflow, tooling,
  dependencies, defaults, or operational decisions changed, include the `AI.md` update.
- **Don't hardcode paths** — use `vim.fn.has("mac")`, `vim.fn.executable()`,
  `vim.env.SSH_TTY`, `wezterm.target_triple`, etc. for platform detection.
- `lazy-lock.json` is gitignored (machine-local). Each machine manages its own
  plugin versions via `:Lazy sync` / `:Lazy update`.

## Task tracking

- Source of truth for pending work: `TODO/TODO.md`.
- For each active task, maintain a progress note at
  `TODO/<task>_progress.md` (one file per task).
