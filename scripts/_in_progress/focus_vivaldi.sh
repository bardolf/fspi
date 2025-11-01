#!/bin/bash
set -euo pipefail

# adresář, kde je umístěn tento skript
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Python skript, který vrací workspace s Vivaldi
PYTHON_SCRIPT="$SCRIPT_DIR/find_vivaldi_workspace.py"

if [ ! -f "$PYTHON_SCRIPT" ]; then
  exit 1
fi

# získat workspace, kde běží Vivaldi
VIVALDI_WORKSPACE=$(swaymsg -t get_tree | python3 "$PYTHON_SCRIPT")

if [ -z "$VIVALDI_WORKSPACE" ]; then
  flatpak run com.vivaldi.Vivaldi &
  exit 0
fi

# přepnout na workspace s Vivaldi a fokusovat okno
swaymsg workspace "$VIVALDI_WORKSPACE"
