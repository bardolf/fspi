#!/usr/bin/env bash
set -euo pipefail

# Toggle focus_follows_mouse based on the focused window's app_id.
# JetBrains IDEs need it off (modal popups close on hover-away); everything
# else gets the natural "focus follows the mouse" behavior. Sway has no
# per-criteria FFM, so we drive it from focus events on the IPC socket.

# Single-instance lock. `exec_always` re-runs us on `swaymsg reload`, but sway
# doesn't kill the previous child — the new copy just exits and leaves the
# already-running one in charge.
exec 200>"${XDG_RUNTIME_DIR:-/tmp}/sway-ffm-jetbrains.lock"
flock -n 200 || exit 0

last=""
apply() {
  local desired="yes"
  [[ "${1:-}" == jetbrains-* ]] && desired="no"
  if [[ "$desired" != "$last" ]]; then
    swaymsg "focus_follows_mouse $desired" >/dev/null
    last="$desired"
  fi
}

# Prime from the currently focused window — subscribe only fires on *changes*.
initial=$(swaymsg -t get_tree \
  | jq -r 'recurse(.nodes[]?, .floating_nodes[]?) | select(.focused == true and .app_id != null) | .app_id' \
  | head -n1)
apply "$initial"

swaymsg -t subscribe -m '["window"]' \
  | jq --unbuffered -r 'select(.change == "focus") | .container.app_id // ""' \
  | while IFS= read -r app_id; do
      apply "$app_id"
    done
