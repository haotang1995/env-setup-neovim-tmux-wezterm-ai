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
     │   ├─ avante.nvim  (Cursor-like AI agent, Claude API)
     │   ├─ copilot.lua  (inline ghost-text completions)
     │   └─ VimTeX       (LaTeX compilation + forward search)
     ├─ Terminal pane     (shell, git, builds)
     └─ AI Agent Popups   (gemini, claude, codex, aider)
```

## Repo layout

```
AI.md                            ← you are here
wezterm.lua                      ← WezTerm config (→ ~/.wezterm.lua)
tmux.conf                        ← tmux config    (→ ~/.tmux.conf)
scripts/                         ← Utility scripts for global use
  install.sh                     ← Installer (symlinks scripts + configs + skills)
  init-ai.sh                     ← Unified AI context bootstrapper
  review_skills.py               ← Interactive keep/remove review for skills
ai-skills/                       ← Shared AI skill library
  README.md                      ← Skill format docs & cross-agent reference
  .repos/superpowers/            ← git submodule: obra/superpowers
  .repos/openai-skills/          ← git submodule: openai/skills
  .repos/tob-skills/             ← git submodule: trailofbits/skills
nvim-config/                     ← Neovim config  (→ ~/.config/nvim/)
  init.lua                       ← LazyVim entry point
  lazyvim.json                   ← LazyVim metadata
  lazy-lock.json                 ← plugin lockfile (committed for reproducibility)
  stylua.toml                    ← Lua formatter config
  lua/config/
    lazy.lua                     ← lazy.nvim bootstrap + LazyVim extras
    options.lua                  ← editor options, clipboard, providers
    keymaps.lua                  ← custom key mappings
    autocmds.lua                 ← autocommands (reload, filetype, trim whitespace)
  lua/plugins/
    ai.lua                       ← avante.nvim + copilot.lua + CopilotChat
    vimtex.lua                   ← VimTeX overrides (lualatex engine, platform-detecting viewer)
    markdown.lua                 ← render-markdown.nvim + markdown-preview.nvim
    tmux-navigator.lua           ← vim-tmux-navigator (Ctrl+hjkl across panes)
.gemini/                         ← Gemini agent config (→ ~/.gemini/settings.json)
.claude/                         ← Claude agent config (→ ~/.claude/settings.json)
.codex/                          ← Codex agent config  (→ ~/.codex/config.toml)
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
- **Status bar:** top, minimal, Catppuccin-ish colors.
- **Automatic AI windows:** new sessions automatically open `gemini`, `claude`,
  and `codex` in windows 2, 3, and 4, then focus back to window 1.

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
- **Kitty graphics protocol** enabled for in-terminal images/PDF.
- **Ctrl+hjkl** explicitly passed through (never intercepted by WezTerm).

### Scripts

- **Location:** `scripts/` directory.
- **Installation:** Run `./scripts/install.sh` to symlink scripts to `~/.local/bin/`
  and config files (`wezterm.lua`, `tmux.conf`, `nvim-config/`, `.gemini/`, `.claude/`, `.codex/`) to their home locations.
  - Use `./scripts/install.sh -u` (or `--update`) to pull the latest repo changes,
    update AI skill submodules, and re-run the linking process.
- **Naming:** Scripts are symlinked without the `.sh` extension for cleaner CLI usage.
- **`init-ai`:** Bootstraps `AI.md`, `TODO/TODO.md`, copies the default sandbox `Dockerfile`, initializes a no-op `install.sh` when missing, and links `AI.md` to `CLAUDE.md`, `GEMINI.md`, and `CODEX.md` in the current directory.
- **`codex-sandbox`:** Runs Codex in Docker with `/workspace` bind-mounted, supports Dockerfile selection in this order: `SANDBOX_DOCKERFILE`, `./Dockerfile` in the caller directory, then the default `scripts/codex-sandbox.Dockerfile`, prints the selected sandbox image, uses `/root/.codex` as the container Codex home, mirrors host git config (`~/.gitconfig`, `~/.config/git`) into the container when available, and auto-migrates legacy nested skills path (`~/.codex/.codex/skills`) while bootstrapping skills when missing/empty or only broken symlinks are present.
- **`review_skills.py`:** Interactive skill decision tool (`y/n/q`) that writes
  `ai-skills/skill-decisions.json` and, by default, applies each answer
  immediately to `~/.claude/skills`, `~/.codex/skills`, and `~/.gemini/skills`.

### AI integration

- **CLI Agents (via tmux windows):**
  - `gemini`: Google's Gemini CLI for quick codebase queries and tasks.
  - `claude`: Claude Code for agentic coding and complex refactors.
  - `codex`: Codex CLI for AI-powered shell assistance and automation.
  - `aider`: Aider for AI pair programming (requires installation).
- **avante.nvim:** Claude as provider (`claude-sonnet-4-20250514`), needs `ANTHROPIC_API_KEY` env var.
- **copilot.lua:** inline ghost-text, `<Tab>` to accept. Needs Node 22+ and `:Copilot auth`.
- **CopilotChat.nvim:** quick Q&A via `<leader>ac`.
- **Shared skill library (`ai-skills/`):** Cross-agent skills from
  obra/superpowers, openai/skills, trailofbits/skills,
  K-Dense-AI/claude-scientific-skills, and Orchestra-Research/AI-Research-SKILLs
  added as git submodules. `install.sh` symlinks each skill into
  `~/.claude/skills/`, `~/.codex/skills/`, and `~/.gemini/skills/`. Update
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
- `lazy-lock.json` is committed so that plugin versions are reproducible.
  Run `:Lazy sync` (not `:Lazy update`) on fresh deploys to match the lockfile.

## Task tracking

- Source of truth for pending work: `TODO/TODO.md`.
- For each active task, maintain a progress note at
  `TODO/<task>_progress.md` (one file per task).
