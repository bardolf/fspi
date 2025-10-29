#!/usr/bin/env bash
# last_workspace.sh - uchovává aktuální a předposlední workspace

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/sway_last_workspace"
PREV_FILE="${XDG_RUNTIME_DIR:-/tmp}/sway_prev_workspace"

mkdir -p "$(dirname "$STATE_FILE")"

swaymsg -m -t subscribe '["workspace"]' | while read -r line; do
  ws=$(echo "$line" | jq -r 'select(.change=="focus") | .current.name // empty')
  if [ -n "$ws" ]; then
    # pokud se změnil workspace, aktualizujeme soubory
    last=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    if [ "$ws" != "$last" ]; then
      # předchozí workspace je poslední uložený
      [ -n "$last" ] && echo "$last" >"$PREV_FILE"
      # aktuální workspace uložíme
      echo "$ws" >"$STATE_FILE"
    fi
  fi
done
