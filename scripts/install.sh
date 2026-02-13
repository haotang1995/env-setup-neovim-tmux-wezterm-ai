#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_CREATED=false

log() {
  echo "[$1] $2"
}

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
    mv "$dest" "$BACKUP_DIR/"
    log "BACKUP" "Moved $dest to $BACKUP_DIR/"
  fi

  ln -sfn "$src" "$dest"
  log "LINK" "$dest -> $src"
}

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

echo ""
echo "Installing config symlinks..."

# WezTerm config
safe_link "$REPO_DIR/wezterm.lua" "$HOME/.wezterm.lua"

# tmux config
safe_link "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf"

# Neovim config
mkdir -p "$HOME/.config"
safe_link "$REPO_DIR/nvim-config" "$HOME/.config/nvim"

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
