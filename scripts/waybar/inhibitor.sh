#!/usr/bin/env bash
# Waybar module: System inhibitor (lid-switch + sleep)
# Prevents suspend on lid close and sleep triggers.
#
# Usage:
#   inhibitor.sh         - Output current state as JSON for waybar
#   inhibitor.sh toggle  - Toggle inhibitor on/off
#
# Uses systemd-inhibit to block handle-lid-switch and sleep.
# PID tracked via $XDG_RUNTIME_DIR/waybar-inhibitor.pid

PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/waybar-inhibitor.pid"

# ============================================
# Check if inhibitor is currently active
# ============================================
is_active() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    # Verify the process is still running
    if kill -0 "$pid" 2>/dev/null; then
      return 0
    else
      # Stale PID file — clean up
      rm -f "$PID_FILE"
    fi
  fi
  return 1
}

# ============================================
# Start the inhibitor
# ============================================
start_inhibitor() {
  if is_active; then
    return 0
  fi

  systemd-inhibit \
    --what=handle-lid-switch:sleep \
    --who="waybar-inhibitor" \
    --why="User activated inhibitor" \
    sleep infinity &

  echo $! > "$PID_FILE"
}

# ============================================
# Stop the inhibitor
# ============================================
stop_inhibitor() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null
    rm -f "$PID_FILE"
  fi
}

# ============================================
# Toggle inhibitor on/off
# ============================================
toggle() {
  if is_active; then
    stop_inhibitor
  else
    start_inhibitor
  fi
}

# ============================================
# Output JSON for waybar
# ============================================
output_json() {
  local text tooltip class

  if is_active; then
    text=$'\xef\x81\xae'   # U+F06E fa-eye
    tooltip=$'Inhibitor active\nLid-switch and sleep inhibited\nClick to deactivate'
    class="activated"
  else
    text=$'\xef\x81\xb0'   # U+F070 fa-eye-slash
    tooltip=$'Inhibitor inactive\nClick to activate'
    class="deactivated"
  fi

  jq -nc \
    --arg text "$text" \
    --arg tooltip "$tooltip" \
    --arg class "$class" \
    '{text: $text, tooltip: $tooltip, class: $class}'
}

# ============================================
# Main
# ============================================
case "${1:-}" in
  toggle)
    toggle
    ;;
  *)
    output_json
    ;;
esac
