#!/usr/bin/env bash
set -euo pipefail

export PATH=$HOME/.local/bin:$PATH
# ---------------------------
# CONFIG
# ---------------------------
OUTPUT_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Screencasts"
mkdir -p "$OUTPUT_DIR"

MODE="${1:-region}" # region | fullscreen

# ---------------------------
# HELPER FUNCTIONS
# ---------------------------
notify() {
  command -v notify-send >/dev/null && notify-send -t 2000 "🎥 Screen recording" "$1"
}

# ---------------------------
# TOGGLE: already recording → stop and finalize the file
# ---------------------------
if pgrep -x wf-recorder >/dev/null; then
  pkill -INT -x wf-recorder
  notify "Stopped — saved to $OUTPUT_DIR"
  exit 0
fi

# ---------------------------
# SELECT REGION
# ---------------------------
case "$MODE" in
region)
  wayfreeze &
  PID=$!
  sleep 0.1
  SELECTION=$(slurp 2>/dev/null || true)
  kill $PID 2>/dev/null || true
  ;;
fullscreen)
  SELECTION=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"')
  ;;
*)
  echo "Usage: $0 [region|fullscreen]"
  exit 1
  ;;
esac

[ -z "$SELECTION" ] && exit 0

# ---------------------------
# RECORD (Super+Shift+Print again to stop; SIGINT finalizes the mp4)
# ---------------------------
FILENAME="$OUTPUT_DIR/screencast-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
notify "Recording… Super+Shift+Print again to stop"
exec wf-recorder -g "$SELECTION" -f "$FILENAME"
