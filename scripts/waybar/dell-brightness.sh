#!/usr/bin/env bash
# Dell monitor brightness for Waybar
# Requires: ddcutil (install with: sudo dnf install ddcutil)

# Check if ddcutil is available
if ! command -v ddcutil &>/dev/null; then
    echo "N/A"
    exit 0
fi

# Get current brightness (0-100)
BRIGHTNESS=$(
  ddcutil getvcp 10 2>/dev/null | awk -F= '{gsub(/ /,"",$2); print $2}' | cut -d',' -f1
)

echo "${BRIGHTNESS:-N/A}"
