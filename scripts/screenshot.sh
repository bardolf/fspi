#!/usr/bin/env bash
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH
# ---------------------------
# CONFIG
# ---------------------------
OUTPUT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$OUTPUT_DIR"

MODE="${1:-region}" # region | fullscreen | window
TMPFILE="$(mktemp --suffix=.png)"

# ---------------------------
# HELPER FUNCTIONS
# ---------------------------
notify() {
  command -v notify-send >/dev/null && notify-send -t 2000 "📸 Screenshot" "$1"
}

get_windows() {
  # Obtain approximate window rectangles (sway outputs clients with rects)
  swaymsg -t get_tree |
    jq -r '.. | objects | select(.type? == "con" and .window_rect?) |
        "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"'
}

# ---------------------------
# SELECT REGION
# ---------------------------
case "$MODE" in
region)
  wayfreeze &
  PID=$!
  sleep 0.1
  SELECTION=$(slurp 2>/dev/null || true)
  kill $PID 2>/dev/null
  ;;
fullscreen)
  SELECTION=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"')
  ;;
window)
  wayfreeze &
  PID=$!
  sleep 0.1
  SELECTION=$(get_windows | slurp -r 2>/dev/null || true)
  kill $PID 2>/dev/null
  ;;
*)
  echo "Usage: $0 [region|fullscreen|window]"
  exit 1
  ;;
esac

[ -z "$SELECTION" ] && exit 0

# ---------------------------
# TAKE & PROCESS IMAGE
# ---------------------------
grim -g "$SELECTION" "$TMPFILE"

if command -v satty >/dev/null; then
  satty \
    --filename "$TMPFILE" \
    --output-filename "$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" \
    --early-exit \
    --actions-on-enter save-to-clipboard \
    --save-after-copy \
    --copy-command 'wl-copy'
else
  wl-copy <"$TMPFILE"
  notify "Screenshot copied to clipboard"
fi

rm -f "$TMPFILE"
