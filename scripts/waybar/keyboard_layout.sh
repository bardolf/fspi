#!/usr/bin/env bash

# Keyboard layout indicator for waybar (long-running custom module).
# Reacts instantly to sway IPC input events (layout switch), and re-checks
# every 10 s as a fallback to recover after lock/unlock or display power-off.

trap 'exit 0' INT TERM

get_layout() {
  swaymsg -t get_inputs | jq -r '
    [.[] | select(.type=="keyboard") | .xkb_active_layout_name] | first'
}

emit() {
  local layout="$1"
  case "$layout" in
  *Czech* | *cz*)
    text="CZ"; tooltip="Czech (QWERTY)" ;;
  *English* | *us*)
    text="US"; tooltip="English (US)" ;;
  *)
    text="${layout:-?}"; tooltip="$layout" ;;
  esac
  printf '{"text": "%s", "tooltip": "%s"}\n' "$text" "$tooltip"
}

while true; do
  emit "$(get_layout)"
  # Wait for an input event (instant) or 10 s timeout (fallback poll)
  timeout 10 swaymsg -t subscribe '["input"]' > /dev/null 2>&1 || true
done
