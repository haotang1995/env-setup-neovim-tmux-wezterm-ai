#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_CREATED=false
SKILL_DECISIONS_JSON="$REPO_DIR/ai-skills/skill-decisions.json"
SKILL_DECISIONS_TSV=""

log() {
  echo "[$1] $2"
}

cleanup() {
  if [ -n "${SKILL_DECISIONS_TSV:-}" ] && [ -f "$SKILL_DECISIONS_TSV" ]; then
    rm -f "$SKILL_DECISIONS_TSV"
  fi
}

trap cleanup EXIT

check_dependencies() {
  local missing=()
  for cmd in git nvim tmux; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log "WARN" "The following tools are missing: ${missing[*]}"
    log "WARN" "Please install them for the full experience."
    echo ""
  else
    log "OK" "All core dependencies found."
  fi
}

ensure_backup_dir() {
  if [ "$BACKUP_CREATED" = false ]; then
    mkdir -p "$BACKUP_DIR"
    log "INFO" "Created backup directory: $BACKUP_DIR"
    BACKUP_CREATED=true
  fi
}

safe_link() {
  local src="$1"
  local dest="$2"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    # Check if it's already a symlink to the correct source
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
      log "SKIP" "$dest is already correctly linked."
      return
    fi

    # Backup existing file/dir
    ensure_backup_dir
    local backup_name
    backup_name="$(basename "$dest")_$(date +%s)_$RANDOM"
    mv "$dest" "$BACKUP_DIR/$backup_name"
    log "BACKUP" "Moved $dest to $BACKUP_DIR/$backup_name"
  fi

  ln -sfn "$src" "$dest"
  log "LINK" "$dest -> $src"
}

update_repo() {
  log "INFO" "Updating repository..."
  git -C "$REPO_DIR" pull

  log "INFO" "Updating AI skill submodules..."
  git -C "$REPO_DIR" submodule update --init --recursive --remote
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -u|--update)
      update_repo
      shift
      ;;
    *)
      shift
      ;;
  esac
done

check_dependencies

mkdir -p "$BIN_DIR"

echo "Installing scripts to $BIN_DIR..."

for script in "$SCRIPT_DIR"/*.sh; do
  # Skip the installer itself
  [ "$(basename "$script")" = "install.sh" ] && continue

  # Remove .sh extension for the global command name
  name=$(basename "$script" .sh)
  dest="$BIN_DIR/$name"

  safe_link "$script" "$dest"
done

# Clean up stale symlinks from old per-agent sandbox scripts
for old_name in claude-sandbox gemini-sandbox codex-sandbox; do
  old_link="$BIN_DIR/$old_name"
  if [ -L "$old_link" ]; then
    old_target="$(readlink "$old_link")"
    case "$old_target" in
      *claude-sandbox.sh|*gemini-sandbox.sh|*codex-sandbox.sh)
        rm -f "$old_link"
        log "REMOVE" "Removed stale symlink: $old_link -> $old_target"
        ;;
    esac
  fi
done

# Backward-compat symlinks: old names -> unified ai-sandbox.sh
for compat_name in claude-sandbox gemini-sandbox codex-sandbox; do
  safe_link "$SCRIPT_DIR/ai-sandbox.sh" "$BIN_DIR/$compat_name"
done

echo ""
echo "Installing config symlinks..."

# WezTerm config
safe_link "$REPO_DIR/wezterm.lua" "$HOME/.wezterm.lua"

# tmux config
safe_link "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf"

# Neovim config
mkdir -p "$HOME/.config"
safe_link "$REPO_DIR/nvim-config" "$HOME/.config/nvim"

# Gemini config
mkdir -p "$HOME/.gemini"
safe_link "$REPO_DIR/.gemini/settings.json" "$HOME/.gemini/settings.json"

# Claude config
mkdir -p "$HOME/.claude"
safe_link "$REPO_DIR/.claude/settings.json" "$HOME/.claude/settings.json"

# Codex config
mkdir -p "$HOME/.codex"
safe_link "$REPO_DIR/.codex/config.toml" "$HOME/.codex/config.toml"

# --- AI skill library (from git submodules) ---
SKILLS_REPOS="$REPO_DIR/ai-skills/.repos"
AGENT_SKILL_DIRS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.gemini/skills"
)

load_skill_decisions() {
  if [ ! -f "$SKILL_DECISIONS_JSON" ]; then
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log "WARN" "python3 not found; ignoring $SKILL_DECISIONS_JSON"
    return
  fi

  SKILL_DECISIONS_TSV="$(mktemp)"
  if ! python3 - "$SKILL_DECISIONS_JSON" >"$SKILL_DECISIONS_TSV" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path, "r", encoding="utf-8"))
decisions = data.get("decisions", {})

# Resolve duplicates by latest updated_at per skill name.
by_name = {}
for rec in decisions.values():
    if not isinstance(rec, dict):
        continue
    name = rec.get("name")
    keep = rec.get("keep")
    updated_at = rec.get("updated_at", "")
    if not name or not isinstance(keep, bool):
        continue
    prev = by_name.get(name)
    if prev is None or updated_at >= prev[0]:
        by_name[name] = (updated_at, keep)

for name in sorted(by_name):
    keep = by_name[name][1]
    print(f"{name}\t{1 if keep else 0}")
PY
  then
    log "WARN" "Failed to parse $SKILL_DECISIONS_JSON; ignoring decisions"
    rm -f "$SKILL_DECISIONS_TSV"
    SKILL_DECISIONS_TSV=""
    return
  fi

  log "INFO" "Loaded skill decisions from $SKILL_DECISIONS_JSON"
}

should_install_skill() {
  local skill_name="$1"
  if [ -z "$SKILL_DECISIONS_TSV" ] || [ ! -f "$SKILL_DECISIONS_TSV" ]; then
    return 0
  fi

  local decision
  decision="$(awk -F '\t' -v n="$skill_name" '$1==n {print $2; exit}' "$SKILL_DECISIONS_TSV")"
  # Default install if no decision exists.
  if [ -z "$decision" ] || [ "$decision" = "1" ]; then
    return 0
  fi
  return 1
}

remove_denied_skill_links() {
  if [ -z "$SKILL_DECISIONS_TSV" ] || [ ! -f "$SKILL_DECISIONS_TSV" ]; then
    return
  fi

  while IFS=$'\t' read -r skill_name keep; do
    [ "$keep" = "0" ] || continue
    for agent_dir in "${AGENT_SKILL_DIRS[@]}"; do
      local target="$agent_dir/$skill_name"
      if [ -L "$target" ]; then
        rm -f "$target"
        log "REMOVE" "Removed denied skill link: $target"
      elif [ -e "$target" ]; then
        log "WARN" "Denied skill exists but is not a symlink, left unchanged: $target"
      fi
    done
  done < "$SKILL_DECISIONS_TSV"
}

install_skills_from() {
  local skill_dir="$1"
  [ -d "$skill_dir" ] || return
  local dir_name
  dir_name="$(basename "$skill_dir")"
  local skill_name
  skill_name="$(resolve_skill_name "$skill_dir")"
  if ! should_install_skill "$skill_name"; then
    log "SKIP" "Denied by skill decisions: $skill_name"
    return
  fi

  # Remove old alias links (directory-name based) when canonical name differs.
  if [ "$dir_name" != "$skill_name" ]; then
    for agent_dir in "${AGENT_SKILL_DIRS[@]}"; do
      local alias_target="$agent_dir/$dir_name"
      if [ -L "$alias_target" ] && [ "$(readlink "$alias_target")" = "${skill_dir%/}" ]; then
        rm -f "$alias_target"
        log "REMOVE" "Removed legacy alias skill link: $alias_target"
      fi
    done
  fi

  for agent_dir in "${AGENT_SKILL_DIRS[@]}"; do
    safe_link "${skill_dir%/}" "$agent_dir/$skill_name"
  done
}

resolve_skill_name() {
  local skill_dir="$1"
  local skill_md="$skill_dir/SKILL.md"
  local fallback
  fallback="$(basename "$skill_dir")"

  [ -f "$skill_md" ] || {
    echo "$fallback"
    return
  }

  # Parse frontmatter "name:" and fall back to directory name when absent.
  local parsed
  parsed="$(awk '
    NR == 1 && $0 ~ /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && $0 ~ /^---[[:space:]]*$/ { exit }
    in_fm && $0 ~ /^name:[[:space:]]*/ {
      sub(/^name:[[:space:]]*/, "", $0)
      gsub(/^[\"\047]|[\"\047]$/, "", $0)
      print $0
      exit
    }
  ' "$skill_md")"

  if [ -n "$parsed" ]; then
    echo "$parsed"
  else
    echo "$fallback"
  fi
}

if [ -d "$SKILLS_REPOS" ]; then
  echo ""
  echo "Installing AI skills..."

  for agent_dir in "${AGENT_SKILL_DIRS[@]}"; do
    mkdir -p "$agent_dir"
  done

  load_skill_decisions
  remove_denied_skill_links

  # obra/superpowers: skills/<name>/
  for d in "$SKILLS_REPOS"/superpowers/skills/*/; do
    install_skills_from "$d"
  done

  # openai/skills: skills/.curated/<name>/
  for d in "$SKILLS_REPOS"/openai-skills/skills/.curated/*/; do
    install_skills_from "$d"
  done

  # trailofbits/skills: plugins/<plugin>/skills/<skill>/
  for plugin in "$SKILLS_REPOS"/tob-skills/plugins/*/; do
    for d in "$plugin"skills/*/; do
      install_skills_from "$d"
    done
  done

  # K-Dense-AI/claude-scientific-skills: scientific-skills/<name>/
  for d in "$SKILLS_REPOS"/scientific-skills/scientific-skills/*/; do
    install_skills_from "$d"
  done

  # Custom my_skills repo: <skill-name>/SKILL.md
  for d in "$SKILLS_REPOS"/my_skills/*/; do
    [ -f "$d/SKILL.md" ] && install_skills_from "$d"
  done

  # Orchestra-Research/AI-Research-SKILLs: NN-topic/SKILL.md or NN-topic/<tool>/SKILL.md
  for topic in "$SKILLS_REPOS"/ai-research-skills/[0-9]*/; do
    if [ -f "$topic/SKILL.md" ]; then
      install_skills_from "$topic"
    fi
    for d in "$topic"*/; do
      [ -f "$d/SKILL.md" ] && install_skills_from "$d"
    done
  done
fi

echo ""
if [ "$BACKUP_CREATED" = true ]; then
  log "INFO" "Backups stored in: $BACKUP_DIR"
fi

if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
  echo ""
  log "WSL" "Detected WSL environment."
  distro="${WSL_DISTRO_NAME:-Ubuntu}"
  log "WSL" "Since WezTerm runs on Windows, you must link the config manually:"
  log "WSL" "  cmd.exe /c mklink %USERPROFILE%\\.wezterm.lua \"\\\\wsl\$\\$distro$REPO_DIR/wezterm.lua\""
fi

echo "Done. Ensure $BIN_DIR is in your PATH."
