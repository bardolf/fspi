#!/usr/bin/env bash
set -euo pipefail

# Drops the focused output to scale 1 for the duration of a game and puts the
# configured scale back afterwards.
#
# Why: the 4K Dell runs at scale 1.3 (see config.d/10-displays.conf), but
# XWayland clients cannot render at a fractional scale. Sway draws them at 1x
# and upscales the result, so an XWayland game — CS2 among them — comes out
# blurry while still rendering more pixels than it ends up showing. Native
# Wayland clients are unaffected; this is purely an XWayland workaround, which
# is why it is a manual toggle rather than a window rule.
#
# The pre-game scale is stashed under $XDG_RUNTIME_DIR (so it never survives a
# reboot with a stale value) rather than restored via `swaymsg reload`: reload
# would re-run every exec_always in the config as a side effect of putting one
# output property back.
#
# Requires: swaymsg, jq
# Binding:  see config.d/60-bindings-gamescale.conf

MODE="${1:-toggle}"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/sway-game-scale"
mkdir -p "$STATE_DIR"

notify() {
  command -v notify-send >/dev/null && notify-send -t 2000 "🎮 Display scale" "$1"
}

# `|| true` because read returns non-zero on empty input, which set -e would
# turn into a silent exit before the emptiness check below can report it.
OUTPUT=""
SCALE=""
read -r OUTPUT SCALE < <(swaymsg -t get_outputs |
  jq -r '.[] | select(.focused) | "\(.name) \(.scale)"') || true

if [[ -z "$OUTPUT" ]]; then
  echo "No focused output found" >&2
  exit 1
fi

STATE_FILE="$STATE_DIR/$OUTPUT"

# Sway reports the scale as a float that has been through a round trip, so 1.3
# comes back as 1.2999999523162842 and an exact == against 1 is meaningless.
is_unscaled() {
  awk -v s="$SCALE" 'BEGIN { exit !(s > 0.999 && s < 1.001) }'
}

enter_game_mode() {
  if is_unscaled; then
    notify "$OUTPUT is already 1:1"
    return
  fi
  printf '%s\n' "$SCALE" >"$STATE_FILE"
  swaymsg output "$OUTPUT" scale 1 >/dev/null
  notify "$(printf '%s → 1:1 (was %.2f)' "$OUTPUT" "$SCALE")"
}

leave_game_mode() {
  if [[ ! -f "$STATE_FILE" ]]; then
    notify "$OUTPUT has no saved scale to restore"
    return
  fi
  local saved
  saved=$(<"$STATE_FILE")
  swaymsg output "$OUTPUT" scale "$saved" >/dev/null
  rm -f "$STATE_FILE"
  notify "$(printf '%s → %.2f' "$OUTPUT" "$saved")"
}

case "$MODE" in
game)
  enter_game_mode
  ;;
restore)
  leave_game_mode
  ;;
toggle)
  # The state file, not the current scale, is what decides: an output that is
  # configured at scale 1 to begin with has nothing to restore.
  if [[ -f "$STATE_FILE" ]]; then
    leave_game_mode
  else
    enter_game_mode
  fi
  ;;
*)
  echo "Usage: $0 [toggle|game|restore]" >&2
  exit 1
  ;;
esac
