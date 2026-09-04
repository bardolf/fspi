#!/usr/bin/env bash
set -euo pipefail

# Turns inbound RustDesk — someone controlling THIS machine — on and off for a
# single session, without ever enabling rustdesk.service at boot.
#
# Controlling someone else needs none of this: the GUI on its own connects out
# fine. Only the controlled side needs the pieces below, and on sway it needs
# all of them.
#
# Why opening the client on both sides is not enough:
#
#   * Which Wayland backends RustDesk uses is decided by whether a
#     `rustdesk --server` process exists — upstream's own is_server_running()
#     in libs/scrap/src/wayland/pipewire.rs. With one, capture goes through the
#     ScreenCast portal and input through /dev/uinput. Without one, BOTH screen
#     and input go through the RemoteDesktop portal instead. sway's portal
#     backend advertises Screenshot and ScreenCast only (see
#     /usr/share/xdg-desktop-portal/portals/wlr.portal), so that fallback has
#     nothing to talk to and the incoming session dies before it shows a frame.
#   * `--server` is spawned by the root service (`rustdesk --service`), which
#     also owns the /dev/uinput injection channel. Both need root, so a user
#     unit is not an option.
#   * RustDesk's own "stop service" switch writes `stop-service = 'Y'` into
#     RustDesk2.toml, and that flag gates the rendezvous registration for
#     `--server` (user config) while `rustdesk --service` disables and stops
#     *itself* at startup when it finds the flag (check_if_stop_service() in
#     src/platform/linux.rs, root config). 19b_rustdesk.sh sets the user one on
#     purpose — with it, merely opening the GUI does not put this machine on the
#     public rendezvous server — so both copies have to be cleared here first.
#   * A GUI started with no `--server` around runs a server inside its own
#     process and holds the IPC socket. The service's `--server` then finds the
#     socket taken and kills the GUI window (stop_main_window_process() in
#     src/server.rs), so the window goes down before the service starts and
#     comes back after.
#
# Nothing here is persistent: `off`, a logout or a reboot all end it, because
# the unit stays disabled either way.

MODE="${1:-status}"

UNIT="rustdesk.service"
CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/rustdesk/RustDesk2.toml"
CONF_ROOT="/root/.config/rustdesk/RustDesk2.toml"

# Full-cmdline pattern for the GUI window process: `rustdesk` with no arguments,
# as opposed to the service's `rustdesk --service` / `--server` / `--tray`.
GUI_PATTERN='(^|/)rustdesk$'
SERVER_PATTERN='rustdesk --server'

notify() {
  command -v notify-send >/dev/null || return 0
  notify-send -t 3000 "🖥️ RustDesk" "$1"
}

require_installed() {
  if ! command -v rustdesk >/dev/null; then
    echo "RustDesk is not installed — run steps/19b_rustdesk.sh" >&2
    exit 1
  fi
}

# --- stop-service flag ---------------------------------------------------
# Both helpers take the config file plus an optional command prefix, so the
# root-owned copy goes through sudo and the user one does not. An empty "$@"
# expands to nothing, which is exactly the local case.

flag_present() {
  local conf="$1"
  shift
  "$@" test -f "$conf" || return 1
  "$@" grep -qE "^[[:space:]]*stop-service[[:space:]]*=" "$conf"
}

flag_clear() {
  local conf="$1"
  shift
  flag_present "$conf" "$@" || return 0
  "$@" sed -i -E "/^[[:space:]]*stop-service[[:space:]]*=/d" "$conf"
}

flag_set() {
  local conf="$1"
  shift
  flag_present "$conf" "$@" && return 0
  if ! "$@" test -f "$conf"; then
    # The GUI has never run, so there is no config yet. Every Config2 field is
    # #[serde(default)], so a file holding nothing but [options] loads fine and
    # gets rewritten in full on the next save.
    "$@" mkdir -p "$(dirname "$conf")"
    printf "[options]\nstop-service = 'Y'\n" | "$@" tee "$conf" >/dev/null
  elif "$@" grep -qE "^\[options\]" "$conf"; then
    "$@" sed -i "/^\[options\]/a stop-service = 'Y'" "$conf"
  else
    # options is the last field of Config2 ("the other scalar value must before
    # this"), so a new table at the end of the file is where it belongs anyway.
    printf "\n[options]\nstop-service = 'Y'\n" | "$@" tee -a "$conf" >/dev/null
  fi
}

# --- processes -----------------------------------------------------------

gui_running() {
  pgrep -u "$USER" -f "$GUI_PATTERN" >/dev/null
}

server_running() {
  pgrep -f "$SERVER_PATTERN" >/dev/null
}

start_gui() {
  setsid -f rustdesk >/dev/null 2>&1
}

wait_for_server() {
  local tries=30
  while ((tries--)); do
    server_running && return 0
    sleep 0.5
  done
  return 1
}

my_id() {
  local id
  id=$(rustdesk --get-id 2>/dev/null | tr -d '[:space:]') || true
  [[ -n "$id" ]] && printf '%s\n' "$id"
}

# --- modes ---------------------------------------------------------------

inbound_on() {
  require_installed

  # The uinput module is what the root service injects keystrokes through; it is
  # usually already loaded, but nothing on a sway-only box guarantees it.
  if [[ ! -e /dev/uinput ]]; then
    echo "Loading the uinput module"
    sudo modprobe uinput
  fi

  flag_clear "$CONF_USER"
  flag_clear "$CONF_ROOT" sudo

  local had_gui=0
  if gui_running; then
    had_gui=1
    echo "Closing the RustDesk window (the service would kill it anyway)"
    pkill -u "$USER" -f "$GUI_PATTERN" || true
    sleep 1
  fi

  # `start`, never `enable`: inbound must not survive a reboot.
  echo "Starting $UNIT for this session"
  sudo systemctl start "$UNIT"

  if ! wait_for_server; then
    echo "$UNIT started but no 'rustdesk --server' appeared — check" >&2
    echo "  journalctl -u $UNIT -b --no-pager | tail" >&2
    exit 1
  fi

  [[ "$had_gui" -eq 1 ]] && start_gui

  local id
  id=$(my_id)
  echo "Inbound is ON${id:+ — ID $id}"
  echo "The one-time password is shown in the RustDesk window."
  # xdg-desktop-portal-wlr's default chooser_type runs the first of slurp,
  # wmenu, wofi, rofi, bemenu, mew, fuzzel it finds — slurp here — so the
  # ScreenCast consent looks like a selection overlay, not a dialog. Until it
  # is answered the peer just waits, which reads exactly like a failed connect.
  echo "When the peer connects, a slurp overlay appears here: click the monitor"
  echo "to share it. Turn this back off with: $(basename "$0") off"
  notify "Inbound ON${id:+ — ID $id}"
}

inbound_off() {
  require_installed

  echo "Stopping $UNIT"
  sudo systemctl stop "$UNIT" || true

  # Only the user copy: setting it in root's config would make a later
  # `sudo systemctl start rustdesk` silently disable itself, which is a
  # confusing way to be told "inbound is off".
  flag_set "$CONF_USER"

  # ExecStop pkills every `rustdesk --*` process, so the tray goes too, but the
  # GUI window has no arguments and survives. It read the flag at startup and
  # keeps whatever server it had, so it has to be restarted to go offline.
  if gui_running; then
    echo "Restart the RustDesk window to take this machine offline"
  fi

  echo "Inbound is OFF"
  notify "Inbound OFF"
}

inbound_status() {
  require_installed

  local enabled active
  enabled=$(systemctl is-enabled "$UNIT" 2>/dev/null || true)
  active=$(systemctl is-active "$UNIT" 2>/dev/null || true)

  printf '%-14s %s\n' "unit:" "${enabled:-unknown} at boot, currently ${active:-unknown}"
  printf '%-14s %s\n' "--server:" "$(server_running && echo running || echo "not running")"
  printf '%-14s %s\n' "gui:" "$(gui_running && echo running || echo "not running")"

  if flag_present "$CONF_USER"; then
    printf '%-14s %s\n' "stop-service:" "set (the GUI alone will not register this machine)"
  else
    printf '%-14s %s\n' "stop-service:" "not set"
  fi
  if flag_present "$CONF_ROOT" sudo; then
    printf '%-14s %s\n' "root config:" "stop-service set — 'rustdesk --service' would stop itself"
  fi

  local id
  id=$(my_id)
  printf '%-14s %s\n' "id:" "${id:-unknown}"

  if server_running; then
    echo "Inbound is ON"
  else
    echo "Inbound is OFF"
  fi
}

case "$MODE" in
on)
  inbound_on
  ;;
off)
  inbound_off
  ;;
status)
  inbound_status
  ;;
*)
  echo "Usage: $(basename "$0") [status|on|off]" >&2
  exit 1
  ;;
esac
