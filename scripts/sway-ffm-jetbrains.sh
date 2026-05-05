#!/usr/bin/env bash
set -euo pipefail

# Toggle focus_follows_mouse based on the focused window's app_id.
# JetBrains IDEs need it off (modal popups close on hover-away); everything
# else gets natural hover-to-focus. Sway has no per-criteria FFM, so we drive
# it from focus events on the IPC socket.

# Replace any prior instance. `exec_always` re-runs us on `swaymsg reload`,
# and we want the fresh copy in charge so it re-primes against live state
# (a stale `last`-state cache caused terminals to stop following the mouse
# after a reload).
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/sway-ffm-jetbrains.pid"
if [[ -f "$PID_FILE" ]]; then
  prior=$(cat "$PID_FILE" 2>/dev/null || true)
  if [[ -n "$prior" && "$prior" != "$$" ]]; then
    # Kill the prior's pipeline children (swaymsg/jq/while-subshell) before
    # the prior itself, otherwise they're reparented to init and keep firing
    # FFM toggles in parallel with the new watcher.
    pkill -P "$prior" 2>/dev/null || true
    kill "$prior" 2>/dev/null || true
  fi
fi
echo "$$" > "$PID_FILE"

apply() {
  local desired="yes"
  [[ "${1:-}" == jetbrains-* ]] && desired="no"
  swaymsg "focus_follows_mouse $desired" >/dev/null
}

# Prime from the currently focused window — subscribe only fires on changes.
initial=$(swaymsg -t get_tree \
  | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused == true and .app_id != null) | .app_id' \
  | head -n1)
apply "$initial"

swaymsg -t subscribe -m '["window"]' \
  | jq --unbuffered -r 'select(.change == "focus") | .container.app_id // ""' \
  | while IFS= read -r app_id; do
      apply "$app_id"
    done
