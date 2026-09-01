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
     │   ├─ LSP              (language intelligence)
     │   ├─ copilot.lua      (FIM ghost text + NES next-edit suggestions)
     │   ├─ CodeCompanion    (Copilot-backed T0.5 inline edits)
     │   ├─ claudecode.nvim  (Claude subscription proposals + native diffs)
     │   └─ VimTeX           (LaTeX compilation + forward search)
     ├─ Terminal pane     (shell, git, builds)
     └─ AI Agent Popups   (gemini, claude, codex, copilot)
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
  .repos/compound-engineering/  ← git submodule: EveryInc/compound-engineering-plugin
  .repos/karpathy-skills/        ← git submodule: multica-ai/andrej-karpathy-skills
  .repos/mattpocock-skills/      ← git submodule: mattpocock/skills
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
    claude_proposals.lua         ← proposal freshness guard + tmux inbox marker
  lua/plugins/
    ai.lua                       ← Copilot T0 + CodeCompanion T0.5 + Claude T1/T2
    vimtex.lua                   ← VimTeX overrides (lualatex engine, platform-detecting viewer)
    markdown.lua                 ← render-markdown.nvim + markdown-preview.nvim
    tmux-navigator.lua           ← vim-tmux-navigator (Ctrl+hjkl across panes)
  tests/                         ← headless regression tests (see "Neovim tests")
    ai_tiers_test.lua            ← AI tier routing: pins, adapters, keymap scopes
    claude_proposals_test.lua    ← proposal freshness, accept guard, marker count
    claude_tmux_marker_test.lua  ← tmux marker, via its own private tmux server
.gemini/                         ← Gemini agent config  (→ ~/.gemini/settings.json)
.claude/                         ← Claude agent config  (→ ~/.claude/settings.json)
.codex/                          ← Codex agent config    (→ ~/.codex/config.toml)
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
  AI lives under `<leader>a*`; `<Tab>` is AI-accept in both insert (FIM) and
  normal (NES) mode, with passthrough to the native binding when idle.
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
  instead of its native auth. Reaching a loopback-bound host process from a
  container is **platform-specific**:
  - **Linux/WSL** — `--add-host host.docker.internal:host-gateway` maps to the
    bridge gateway (`172.17.0.1`), where nothing listens because the proxy binds
    `127.0.0.1` only; the container gets connection-refused. *Verified:
    host-gateway → HTTP 000, `--network host` → HTTP 200.* So `--copilot-route`
    implies **`--network host`** here. Consequence: the container shares the host
    network namespace, so ports the agent opens bind host ports — acceptable given
    the sandbox already runs the agent with permissions fully bypassed.
  - **macOS** — Docker Desktop's `host.docker.internal` does reach host loopback,
    and `--network host` is not reliably supported, so the bridge + host mapping
    is kept there.

  A bare `-e` passthrough of `ANTHROPIC_BASE_URL` would leak the host's
  `127.0.0.1` into a bridged container, so the URL is rewritten per platform. For
  codex there is no env passthrough for provider config at all, so the container's
  `config.toml` `base_url` is rewritten at startup and the provider is selected
  with `-c model_provider=…`. Fails fast if the proxy isn't running or the key is
  missing.
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
  - **`COPILOT_PROXY_PORT` propagates everywhere**, including host `codex-copilot`:
    the wrapper overrides `model_providers.copilot_proxy.base_url` with the
    *resolved* URL via `-c`, rather than relying on the literal in
    `.codex/config.toml`. State files are **per-port**
    (`~/.local/state/copilot-proxy/proxy-<port>.{pid,log}`) so two proxies on
    different ports can coexist without `stop`/`status` acting on the wrong one.
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
  - codex: selects the provider with **`-c` overrides, never `--profile`**. The
    provider is defined once in `.codex/config.toml` as
    `[model_providers.copilot_proxy]` (**inert** until selected) with
    `wire_api = "responses"` — mandatory, since Codex removed the
    chat/completions wire API in Feb 2026. Override via `CODEX_COPILOT_MODEL`
    (default `gpt-5.4`), `CODEX_COPILOT_EFFORT`, and
    `CODEX_COPILOT_APPROVALS_REVIEWER`.
    - **Why not `--profile`:** Codex changed the profile mechanism twice in one
      week, and it auto-updates, so `--profile` is a moving target:
      **0.116** required `[profiles.<name>]` in `config.toml` and *silently
      ignored* a `--profile` placed before a subcommand — falling through to the
      `openai` provider with no error at all;
      **0.147** hard-errors on that same table (`--profile X cannot be used
      while … contains legacy [profiles.X]`) and demands a standalone
      `~/.codex/<name>.config.toml`.
      `-c` behaves identically on both and is position-insensitive. There is
      deliberately **no** `[profiles.copilot]` table and no standalone profile
      file in this repo.
    - **Always confirm routing from the startup banner: `provider: copilot_proxy`,
      not `provider: openai`.** Silent fallback is the characteristic failure.
    - Codex rejects model ids newer than its build client-side ("requires a
      newer version of Codex") even when the proxy serves them fine.
    - Expect one benign `ERROR … failed to refresh available models … 404 …
      Provider 'codex' not found` line at startup: the proxy 404s Codex's
      model-catalog refresh (`/v1/models?client_version=…`; a plain `curl` of
      the same URL returns 200). Only the `/model` picker list is affected;
      completions go through.
    - **`approvals_reviewer` must be `"user"` on this lane; the wrapper forces
      it with `-c`.** `auto_review` (and `guardian_subagent`) makes codex issue
      a *side* `POST /v1/responses` with `model: "codex-auto-review"` to grade
      each escalation. No Copilot seat serves that model, so the proxy replies
      400 *"This model does not support the responses endpoint"* and codex turns
      the failed review into a hard denial — **every** command comes back
      `the escalation request was rejected` / `Rejected … Automatic approval
      review failed`. The host wrapper and sandbox force `user` with `-c`,
      while plain native Codex keeps `auto_review`. Override with
      `CODEX_COPILOT_APPROVALS_REVIEWER` if a seat ever serves the model.
      Symptom check: a bare `--> POST /v1/responses 400` in the proxy log with
      no preceding `<-- model:` line for your chat model.
    - **`stream disconnected before completion: stream closed before
      response.completed` is upstream and transient — not a config fault.**
      The proxy accepts the request (`200` in ~10–20 ms), then logs
      `WARN Copilot responses websocket stream error: { code: 'bad_request',
      message: 'internal server error' }` and the SSE stream ends without
      `response.completed`. Codex retries 6× and surfaces one error per turn.
      Observed only as short bursts on one model (`gpt-5.6-sol`); replaying the
      exact failing conversation afterwards succeeded, as did 200k-token
      payloads, so it is not context size, reasoning effort, or payload shape.
      Just retry the turn; if a model keeps failing, switch models
      (`CODEX_COPILOT_MODEL`) rather than editing config.
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

### Local inference (GPU box)

Deferred alternate backend experiment for the active CodeCompanion T0.5 lane.
The default route is Copilot HTTP; local inference is not active.

- **Hardware constraint: the A6000s are compute capability 8.6 (Ampere).**
  There is **no FP8 compute path** — FP8 is storage-only for the KV cache.
  Quantisation must therefore be **AWQ/GPTQ INT4** (Marlin kernels, native on
  Ampere). An FP8-only checkpoint has to be requantised; it will not just work.
- **Interconnect is pair-wise NVLink, not all-to-all.** `nvidia-smi topo -m`
  shows `GPU0–GPU1 = NV4` and `GPU2–GPU3 = NV4`, but `0/1 ↔ 2/3 = NODE`
  (host bridge). So `--tensor-parallel-size 2` **within a pair** is the sweet
  spot; TP=4 crosses the slow hop. Two independent servers (one per pair) is a
  better use of the box than one TP=4 server.
- **These are research GPUs.** Prefer a model that fits on one or two cards and
  leave the rest free. Do not hand the whole box to an inference server.
- **Current candidate: `Qwen3.6-27B` AWQ-INT4** (~16 GB, dense, fits one card).
  Dense rather than MoE because inline latency should be predictable
  request-to-request. Verified working on Ampere via Marlin.
- **Not defaulting to `Qwen3-Coder-Next` (80B-A3B)** despite the stronger
  agentic numbers: it is trained for tool-use loops, which is the opposite of
  the inline lane's single-shot bounded rewrite. Prefer it if you want the
  **chat** lane driving tools. Note also a community report of its
  `insert_edit_into_file` tool overwriting whole files under CodeCompanion.
- **Do not pick this model from SWE-bench.** Inline is judged on TTFT,
  edit-format compliance, and not touching anything outside the selection —
  none of which SWE-bench measures. Race candidates on real tasks from this
  repo.
- vLLM notes for Ampere: `--block-size 16` (hybrid attention layers),
  `--kv-cache-dtype fp8` (storage only), Marlin is selected automatically for
  AWQ. `--disable-custom-all-reduce` is needed only for PCIe-linked pairs, not
  for an NVLinked pair.

### AI integration

- **CLI agents:** `gemini`, `claude`, `codex`, and `copilot` remain
  available for T3 investigation and implementation. Code-producing T3 tasks
  belong in isolated worktrees; the main worktree remains human-owned.
- **In-editor AI uses explicit autonomy tiers.**

  | Tier | Plugin | Trigger | Authority |
  |------|--------|---------|-----------|
  | T0 FIM | `copilot.lua` | `<Tab>`, insert mode | insert suggestion |
  | T0 NES | `copilot.lua` + `copilot-lsp` | `<Tab>`, normal mode | next-edit suggestion |
  | T0.5 inline | `CodeCompanion` + Copilot HTTP | visual `<leader>ai` | selection-scoped inline diff |
  | T1/T2 proposal | `claudecode.nvim` | visual `<leader>as` + Claude prompt | explicit diff accept/reject |

- **copilot.lua (FIM):** inline ghost text, `<Tab>` to accept. Needs Node 22+
  and `:Copilot auth`.
- **copilot.lua (NES):** proposes the next edit anywhere in the buffer.
  `<Tab>` accepts and jumps; `<Esc>` dismisses.
  - `copilotlsp-nvim/copilot-lsp` is mandatory. Without it,
    `nes.enabled = true` is silently downgraded to false.
  - Insert-mode and normal-mode `<Tab>` do not collide. copilot.lua passes the
    native key through when no suggestion is pending.
- **CodeCompanion (T0.5 inline):** pinned to `v19.22.0` and configured only as
  the fast local edit lane. Select code and press `<leader>ai`.
  Review the inline diff with `ga` to accept or `gr` to reject. Keep requests
  selection/buffer-local; repository search, shell work, and multi-file edits
  belong in T1/T2 or T3. CodeCompanion chat is intentionally not mapped.
  - **The Copilot inline model must stay an explicit id — never `"auto"`.**
    `model = "auto"` deletes the model field from the request
    (`adapters/http/copilot/init.lua:193`) so GitHub picks its own default,
    which caps prompts at **12288 tokens** and returns HTTP 400 on anything
    larger. The synthetic `auto` entry also carries no `endpoint`
    (`copilot/get_models.lua`), so requests fall back to `/chat/completions`
    instead of `/responses`. Currently `gpt-5.6-luna` (1.05M context, 922k
    max prompt, `supported_endpoints: ["/responses", "ws:/responses"]`).
    `ai_tiers_test.lua` asserts the id so `auto` cannot creep back.
  - **Model availability is per-organisation and shifts.** The seat's raw
    catalog (`GET https://api.githubcopilot.com/models`) marks most of the
    frontier ids `policy: disabled`; `copilot-proxy models` does **not** filter
    on that, so it lists models the seat cannot actually use. Check
    `policy.state` in the raw catalog, or `:CodeCompanionModels`, before
    pinning. CodeCompanion routes to `/responses` only when the catalog entry
    advertises it (`adapters/utils/models/transform.lua:70`).
    Re-verified Aug 2026 on the `tanghao_microsoft` seat: the whole 5.6 family
    (`luna`, `sol`, `terra`) plus `gpt-5.4`/`gpt-5.5`, `claude-opus-5`,
    `claude-sonnet-5` and the gemini tier are all `enabled`, so the earlier
    "only enabled 5.6 model" note no longer holds. `gpt-5.3-codex`, `grok-4.*`
    and the `gpt-4o` family carry **no** `policy` block at all.
  - **CodeCompanion reads the Copilot OAuth token itself — not via copilot.lua.**
    `adapters/http/copilot/token.lua` tries `github-copilot/hosts.json` then
    `apps.json`, and only then falls back to
    `SELECT token_ciphertext FROM oauth_tokens` in `github-copilot/auth.db`,
    using that column **verbatim** as the token. Two consequences on this box:
    `sqlite3` must be on `PATH` (the adapter hard-errors without it), and the
    column is only usable because keytar can't load (`libsecret-1.so.0`
    missing), so the server writes the `ghu_…` token in plaintext with
    `token_schema_version = 0`. Installing libsecret would encrypt that column
    and break the inline lane while `:Copilot auth` still reports healthy.
    Re-running `:Copilot auth` is enough to re-point CodeCompanion at a new
    account; the adapter caches the token in memory only, so just restart nvim.
- **claudecode.nvim (T1/T2 proposals):**
  - Uses the Claude Code CLI's normal subscription login. No Anthropic API key,
    CodeCompanion adapter, or ACP bridge is involved.
  - Pinned to commit
    `2390c6e45c4789072c293ac69de051d169668b29`. The policy depends on that
    commit's diff events and internal saved-diff function; do not bump it
    without rerunning the lifecycle and freshness tests.
  - Each Neovim creates its own WebSocket IDE endpoint and launches its own
    Claude terminal with `:ClaudeCode`. The endpoint—not repository path—routes
    proposals to the correct editor when several Neovims share one repository.
  - Uses the native terminal provider. `:ClaudeCode` toggles it,
    `<leader>af` focuses it, `<leader>ab` adds the current buffer, and visual
    `<leader>as` sends a selection. Hiding the terminal preserves the process.
  - Claude proposals open as native vertical diffs. On the proposed side use
    `gda` or `:w` to accept and `gdr` or `:q` to reject. The mappings are
    buffer-local.
  - `ClaudeCodeDiffOpened` and `ClaudeCodeDiffClosed` maintain a counted tmux
    window marker (`🤖`) and announce background arrivals with
    `tmux display-message`. They never select a pane or window.
  - **Freshness is fail-closed for documented accept paths.** The policy
    captures file and buffer hashes on `ClaudeCodeSendComplete` when possible
    (falling back to diff-open), replaces the proposal scratch buffer's
    `BufWriteCmd`, and wraps `:ClaudeCodeDiffAccept`. If the disk file or
    original buffer changes, acceptance is blocked and regeneration is required.
  - The wrapper uses `claudecode.diff._resolve_diff_as_saved` from the pinned
    commit because upstream has no public pre-accept hook.
  - **Never `return true` from the `BufWriteCmd` guard.** In a Lua autocmd
    callback that means *delete this autocmd*, not *handled*. Because the guard
    replaces the plugin's own `BufWriteCmd`, deleting itself after a **blocked**
    write leaves the proposal buffer with no write handler at all — `:w` then
    fails `E676` and the documented accept path is dead for that proposal
    (`gda` still works, and nothing is ever written, so it fails safe).
    `buftype=acwrite` has no default write to suppress, so returning nothing is
    correct. The plugin's own handler can return `true` only because it always
    resolves the diff. `claude_proposals_test.lua` covers a second `:w` after a
    blocked one, which is the case a fresh-proposal-only test misses.
  - The hash wrapper is not a filesystem sandbox. Claude shell commands can
    bypass IDE `openDiff`; do not auto-approve write-capable tools until the V0
    normal-edit/new/delete/rename/shell bypass matrix passes. If it fails, use
    the shadow-worktree broker.
  - Keep at most one Neovim with unsaved edits to a given file. The existing
    `FocusGained`/`BufEnter` `checktime` autocmd reloads saved external changes.
- **avante.nvim and CopilotChat.nvim:** removed; their roles are covered by the
  explicit proposal and T3 lanes.
- **Shared skill library (`ai-skills/`):** Cross-agent skills from
  obra/superpowers, openai/skills, trailofbits/skills,
  K-Dense-AI/claude-scientific-skills, Orchestra-Research/AI-Research-SKILLs,
  EveryInc/compound-engineering-plugin, multica-ai/andrej-karpathy-skills,
  and mattpocock/skills added as git submodules. `install.sh` symlinks each
  selected skill into
  `~/.claude/skills/`, `~/.codex/skills/`, `~/.gemini/skills/`, and
  `~/.copilot/skills/`. Update
  with `./scripts/install.sh -u` (or `git submodule update --remote`).
  Skill decisions in `ai-skills/skill-decisions.json` are enforced on each
  install run (denied skills are skipped and existing denied links are removed).
  Manage decisions with `python3 scripts/review_skills.py`:
  `--skill <name>` for one skill, `--redo` to revisit already-decided skills,
  and `--no-apply` for record-only mode.
  - **Curation policy — general-purpose skills are normally denied.**
    A skill costs a description line in every system prompt whether or not it
    ever fires, so the bar is *non-obvious, environment-specific, or long-tail
    API knowledge*. Skills that merely encode generic engineering **process**
    (plan → implement → verify → review ceremony) or restate a widely-known CLI
    were pruned in Aug 2026, in four passes that took the library 150 → 35:
    - **Process ceremony (25).** The whole `superpowers` bucket except
      `writing-skills` (which documents the SKILL.md format itself), plus
      `ask-questions-if-underspecified`, `differential-review`, `git-cleanup`,
      `second-opinion`, `using-gh-cli`, `gh-address-comments`, `gh-fix-ci`,
      `jupyter-notebook`, `yeet`, `get-available-resources`,
      `hypothesis-generation`, `scientific-brainstorming`,
      `scientific-critical-thinking`.
    - **Library documentation (40).** Skills that restate the docs of a
      well-known tool: the plotting/dataframe/scientific-Python layer
      (`matplotlib`, `seaborn`, `plotly`, `polars`, `scikit-learn`, `sympy`,
      `networkx`, `dask`, `vaex`, `simpy`, `zarr-python`, `torch-geometric`,
      `stable-baselines3`, `pymc-bayesian-modeling`, `transformers`,
      `markitdown`), the vector-store / LLM-plumbing layer (`faiss`,
      `pinecone`, `llamaindex`, `dspy`, `guidance`, `instructor`, `outlines`,
      `sentence-transformers`, `sentencepiece`, `huggingface-tokenizers`),
      the experiment-tracking layer (`mlflow`, `tensorboard`), single-model
      explainers (`whisper`, `llava`, `nanogpt`, `mamba-architecture`,
      `segment-anything-model`, `stable-diffusion-image-generation`), agent
      frameworks (`autogpt-agents`, `crewai-multi-agent`), and cloud-GPU
      vendors (`lambda-labs-gpu-cloud`, `modal`, `modal-serverless-gpu`).
      Two were straight duplicates of skills already tuned to this setup:
      `weights-and-biases` (vs `wandb-microsoft-research`) and `modal` (vs
      `modal-serverless-gpu`).
    - **Off-domain (8).** Skills bound to a product or system that is not part
      of this setup: the four `notion-*` workspace integrations, `figma` and
      `figma-implement-design` (both need a Figma MCP server plus design
      files), `develop-web-game`, and `debug-buttercup` (a debugger for the
      Buttercup CRS on Kubernetes).
    - **Whole buckets (42).** `ai-research-skills` and `tob-skills` are now
      denied in full — every remaining entry with those `source` values was
      flipped, so nothing from either submodule installs even when new skills
      land upstream. This retired the distributed-training / RL-post-training /
      serving-and-quantisation layer (Megatron, FSDP2, DeepSpeed,
      verl/slime/torchforge, TRL variants, vLLM, SGLang, TensorRT-LLM,
      bitsandbytes) along with the security/systems skills
      (`address-sanitizer`, `dwarf-expert`, `modern-python`,
      `devcontainer-setup`). Consult upstream docs when a task actually needs
      one; the submodules stay checked out, only the symlinks are gone.

    What survives is the academic writing / figure / poster / literature
    toolchain, a thin slice of OpenAI media-and-document skills, this machine's
    own MSR-specific skills (`trapi-llm`, `azureml-singularity-jobs`,
    `wandb-microsoft-research`) plus the rest of `my_skills`, and the explicitly
    added mattpocock/skills promoted set. Don't re-enable the pruned ones as a
    side effect of adding a submodule; `keep: false` in
    `skill-decisions.json` is the record. Note the `scripts` entry there is
    **synthetic** — that directory has no `SKILL.md`, so `review_skills.py`
    never sees it and undecided defaults to *install*; the hand-written entry
    is what keeps `install.sh`'s glob from linking it.
  - **mattpocock/skills installs only its promoted buckets.** `install.sh`
    links `skills/engineering/*` and `skills/productivity/*`, matching the
    upstream plugin's public set. The `misc`, `in-progress`, and `deprecated`
    buckets remain checked out in the submodule but are not installed.
  - **compound-engineering-plugin is installed at 3 of its 34 skills.**
    The plugin ships a full `ce-*` workflow suite (brainstorm → plan → work →
    review → commit → PR → babysit, plus `lfg`). That is precisely the *process
    ceremony* the Aug 2026 pruning removed, and much of it duplicates lanes that
    already exist here — `/code-review`, `/simplify`, `using-git-worktrees`,
    `plan-execute`, `finish-feature`. A further ~16 skills are bound to products
    this setup does not use (Every's Proof and Riffrec, Spiral, PostHog/Mixpanel/
    Stripe, Slack, Xcode) or to web-app browser QA. Only three are installed:
    - `ce-compound` — capture a solved problem as a durable repo learning.
    - `ce-compound-refresh` — audit that store for stale, overlapping,
      superseded, or drifted entries.
    - `ce-simplify-code` — behavior-preserving cleanup of settled changes.

    The other 31 carry `keep: false` in `skill-decisions.json`, which is what
    stops `install.sh`'s `compound-engineering/skills/*/` glob from linking
    them; **anything the plugin adds upstream arrives undecided and therefore
    installs**, so re-check after `install.sh -u`. The plugin's six
    `tests/fixtures/**/SKILL.md` files are deliberately **absent** from
    `skill-decisions.json`: the deny table is keyed by skill *name* across every
    source, and fixture names like `custom-skill` / `default-skill` /
    `skill-one` would silently deny a real skill of that name from another repo.
    Two operational notes if these skills are ever run in anger: `ce-compound`
    writes to `docs/solutions/` by default, which cuts across this repo's
    `TODO/<task>_progress.md` + `AI.md` convention (retarget with `docs_root` in
    a repo-local `.compound-engineering/config.yaml`), and the plugin's
    cross-model passes shell out to a second provider's CLI — set
    `cross_model_review_mode: off` in that same file to keep diffs off the
    Copilot lane.
  - **`karpathy-guidelines` is kept as a behavioral corrector, not process.**
    One 4 KB `SKILL.md`, MIT, no scripts — behavioral guidance derived from a
    Karpathy tweet on LLM coding pitfalls (third-party; not authored by
    Karpathy). It clears the curation bar on the "counters a demonstrated
    default tendency" leg rather than the non-obvious-knowledge leg: think
    before coding, minimum code, surgical diffs, verifiable success criteria.
    Two caveats to weigh before trusting it:
    - **Its trigger is very broad** ("writing, reviewing, or refactoring
      code"), so it can fire on most coding turns across all four agents.
    - **Section 1 tells the agent to stop and ask when unclear.** That is a
      poor fit for the unattended lanes on this box — `ai-sandbox` runs claude
      with `--dangerously-skip-permissions`, copilot/gemini with `--yolo`, and
      codex with `--sandbox danger-full-access`, where nobody is watching to
      answer. It also cuts against Claude Code's own "act when you have enough
      information" baseline, where sections 2–3 are largely redundant already.
      It has more headroom on the Codex/Gemini/Copilot lanes.

    Because it lives in a submodule, narrowing the trigger or adding
    `disable-model-invocation` is not possible without vendoring the file into
    `my_skills` instead. Deny it in `skill-decisions.json` if it proves noisy.
  - **Two known gaps in the tooling.** `review_skills.py`'s `detect_source()`
    still has no case for the `my_skills` submodule, so those skills bucket as
    `other` and are unreachable via `--source` (`compound-engineering` and
    `karpathy-skills` were added Aug 2026); and undecided skills default to
    *install* in both the script and `install.sh`. Separately, `install.sh`'s
    globs link two directories that have no `SKILL.md` of their own —
    `scientific-skills/document-skills/` (wraps `docx`/`pdf`/`pptx`/`xlsx`) and
    `tob-skills/plugins/burpsuite-project-parser/skills/scripts/` (a shell
    script). Agents scan only one level deep, so the four document skills are
    not actually loadable today.

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
- **Neovim tests** in `nvim-config/tests/` are headless and self-contained.
  Run each from the repository root; each prints a single `*_OK` line and
  `error()`s otherwise, so a non-zero exit is the failure signal:

  ```sh
  # Tier routing: reads lua/plugins/ai.lua via dofile, no plugins needed.
  nvim --headless -u NONE -l nvim-config/tests/ai_tiers_test.lua

  # Proposal policy: needs claudecode.nvim at the pinned commit on the rtp.
  # git clone https://github.com/coder/claudecode.nvim /tmp/claudecode-nvim-2390c6e \
  #   && git -C /tmp/claudecode-nvim-2390c6e checkout 2390c6e
  nvim --headless -u NONE \
    --cmd "set rtp^=/tmp/claudecode-nvim-2390c6e" \
    --cmd "set rtp^=$PWD/nvim-config" \
    -l nvim-config/tests/claude_proposals_test.lua

  # tmux marker: starts its own private tmux server; skips without tmux.
  nvim --headless -u NONE \
    --cmd "set rtp^=$PWD/nvim-config" \
    -l nvim-config/tests/claude_tmux_marker_test.lua
  ```

  Use `-u NONE` and an explicit `rtp`, **not** your real config — loading
  LazyVim registers lazy.nvim's command stubs, which clobber the policy's
  `ClaudeCodeDiffAccept` override and make the run fail spuriously.
  Rerun all three after bumping either pinned AI plugin.
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
- **Pin plugins whose config schema you depend on.** Because the lockfile is
  gitignored *and* `lua/config/lazy.lua` sets `defaults = { version = false }`,
  nothing holds two machines to the same plugin commit by default — an
  `install.sh -u` on a rarely-touched box can silently pull a breaking rename.
  For any plugin where this repo hard-codes option keys, set an explicit
  `version = "vX.Y.Z"` on that spec and bump it deliberately.
  Currently pinned: `CodeCompanion v19.22.0` and `claudecode.nvim` at
  `2390c6e45c4789072c293ac69de051d169668b29`.

## Task tracking

- Source of truth for pending work: `TODO/TODO.md`.
- For each active task, maintain a progress note at
  `TODO/<task>_progress.md` (one file per task).
