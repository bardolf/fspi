#!/usr/bin/env bash
# swap_workspace.sh - přepíná mezi aktuálním a předposledním workspace

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/sway_last_workspace"
PREV_FILE="${XDG_RUNTIME_DIR:-/tmp}/sway_prev_workspace"

# načteme workspace
current=$(cat "$STATE_FILE" 2>/dev/null || echo "")
prev=$(cat "$PREV_FILE" 2>/dev/null || echo "")

# pokud máme předposlední workspace, přepneme na něj
if [ -n "$prev" ] && [ "$prev" != "$current" ]; then
  swaymsg workspace "$prev"
  # po přepnutí zaměníme soubory, aby historie zůstala správná
  echo "$current" >"$PREV_FILE"
  echo "$prev" >"$STATE_FILE"
fi
