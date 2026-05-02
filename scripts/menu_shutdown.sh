#!/usr/bin/env bash
set -euo pipefail

options="  Lock
󱄄  Screensaver
󰤄  Suspend
󰜉  Restart
󰐥  Shutdown"

choice=$(echo "$options" | rofi -dmenu -i -p "System…")

case "$choice" in
*Lock*) "$HOME/.local/bin/swaylock-effects" -C "$HOME/.config/swaylock/effects.conf" ;;
*Screensaver*) gnome-screensaver-command -a ;;
*Suspend*) systemctl suspend ;;
*Restart*) systemctl reboot ;;
*Shutdown*) systemctl poweroff ;;
*) exit 0 ;;
esac
