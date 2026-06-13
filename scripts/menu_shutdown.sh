#!/usr/bin/env bash
set -euo pipefail

options="  Lock
󱄄  Screensaver
󰍃  Log off
󰤄  Suspend
󰜉  Restart
󰐥  Shutdown"

choice=$(echo "$options" | rofi -dmenu -i -p "System…")

case "$choice" in
*Lock*) "$HOME/.local/bin/swaylock-effects" -C "$HOME/.config/swaylock/effects.conf" ;;
*Screensaver*) gnome-screensaver-command -a ;;
*"Log off"*) swaymsg exit ;;
*Suspend*) systemctl suspend ;;
*Restart*) systemctl reboot ;;
*Shutdown*) systemctl poweroff ;;
*) exit 0 ;;
esac
