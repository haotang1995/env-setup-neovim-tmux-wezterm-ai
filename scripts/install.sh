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

echo "Done. Ensure $BIN_DIR is in your PATH."
