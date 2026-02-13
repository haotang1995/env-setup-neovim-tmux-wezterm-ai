#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$BIN_DIR"

echo "Installing scripts to $BIN_DIR..."

for script in "$SCRIPT_DIR"/*.sh; do
  # Skip the installer itself
  [ "$(basename "$script")" = "install.sh" ] && continue
  
  # Remove .sh extension for the global command name
  name=$(basename "$script" .sh)
  dest="$BIN_DIR/$name"
  
  ln -sfn "$script" "$dest"
  echo "Linked: $name -> $dest"
done

echo ""
echo "Installing config symlinks..."

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# WezTerm config
ln -sfn "$REPO_DIR/wezterm.lua" "$HOME/.wezterm.lua"
echo "Linked: wezterm.lua -> ~/.wezterm.lua"

# tmux config
ln -sfn "$REPO_DIR/tmux.conf" "$HOME/.tmux.conf"
echo "Linked: tmux.conf -> ~/.tmux.conf"

# Neovim config
mkdir -p "$HOME/.config"
ln -sfn "$REPO_DIR/nvim-config" "$HOME/.config/nvim"
echo "Linked: nvim-config -> ~/.config/nvim"

echo ""
echo "Done. Ensure $BIN_DIR is in your PATH."
