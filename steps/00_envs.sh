#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

PROFILE_FILE="$HOME/.profile"
LINE='export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"'

if grep -Fxq "$LINE" "$PROFILE_FILE"; then
    log_debug "Flatpak XDG_DATA_DIRS already configured."
else
    log_info "Adding Flatpak XDG_DATA_DIRS fix to $PROFILE_FILE"
    echo -e "\n# Ensure Flatpak desktop exports are visible\n$LINE" >> "$PROFILE_FILE"
fi
