#!/usr/bin/env bash
set -euo pipefail

# URL, kterou chceme otevřít
URL="$1"

# Skript, který najde workspace s Vivaldi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/find_vivaldi_workspace.py"

# Zjistit workspace s Vivaldi
VIVALDI_WS=$(swaymsg -t get_tree | python3 "$PYTHON_SCRIPT")

if [ -z "$VIVALDI_WS" ]; then
  echo "Vivaldi neběží, spouštím ho..."
  flatpak run com.vivaldi.Vivaldi &
  sleep 2
  VIVALDI_WS=$(swaymsg -t get_tree | python3 "$PYTHON_SCRIPT")
fi

# Přepnout na workspace a fokusovat Vivaldi
swaymsg workspace "$VIVALDI_WS"
swaymsg "[app_id=\"vivaldi\"] focus"

# Otevřít URL ve spuštěném Vivaldi
flatpak run com.vivaldi.Vivaldi --new-tab "$URL" &
