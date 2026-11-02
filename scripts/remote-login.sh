#!/usr/bin/env bash
set -euo pipefail

# Graphical login over SSH: starts the sway session on THIS machine's seat0, so
# that VNC (vnc-desktop.sh → wayvnc) has a Wayland session to attach to. wayvnc
# runs inside the session; after a reboot there is only the SDDM greeter, and
# VNC has nothing to show until someone logs in at the keyboard.
#
#   ssh desktop ~/scripts/remote-login.sh     # then vnc-desktop.sh as usual
#
# SDDM nemá příkaz „přihlas uživatele X", autologin ale udělá při svém startu.
# Takže: dočasný drop-in s [Autologin] → restart sddm → počkat na session →
# drop-in hned smazat (trap i při chybě, takže další boot skončí zase na
# greeteru) → zamknout obrazovku (loginctl lock-session → `lock` handler
# swayidle), ať doma nezůstane odemčený desktop. Odemyká se heslem už ve VNC.
#
# Restart sddm by zabil sezení, které na seat0 už běží → v tom případě nic
# nemění: vlastní sezení = hotovo, cizí = odmítne.

SESSION_FILE="${REMOTE_LOGIN_SESSION:-sway.desktop}"
DROPIN_DIR=/etc/sddm.conf.d
DROPIN="$DROPIN_DIR/zz-remote-login.conf"

if [[ $# -gt 0 ]]; then
  echo "Usage: $(basename "$0")   (run on the machine to log in, e.g. ssh desktop ~/scripts/$(basename "$0"))" >&2
  exit 1
fi

command -v jq >/dev/null || {
  echo "jq is missing (sudo dnf install jq)" >&2
  exit 1
}

# "<session> <user>" for every user session on seat0 (greeter has class "greeter")
seat0_sessions() {
  loginctl list-sessions --json=short |
    jq -r '.[] | select(.seat == "seat0" and (.class | startswith("user"))) | "\(.session) \(.user)"'
}

my_seat0_session() {
  seat0_sessions | awk -v u="$USER" '$2 == u { print $1; exit }'
}

sid=$(my_seat0_session)
if [[ -n "$sid" ]]; then
  echo "Already logged in on seat0 (session $sid) — nothing to do, connect with vnc-desktop.sh"
  exit 0
fi

others=$(seat0_sessions | tr '\n' ' ')
if [[ -n "$others" ]]; then
  echo "Someone else is logged in on seat0 (session/user: $others) — restarting SDDM would end it, giving up" >&2
  exit 1
fi

if [[ ! -f "/usr/share/wayland-sessions/$SESSION_FILE" ]]; then
  echo "No /usr/share/wayland-sessions/$SESSION_FILE (set REMOTE_LOGIN_SESSION)" >&2
  exit 1
fi

# --- one-time autologin ----------------------------------------------------
created_dir=0
cleanup() {
  sudo rm -f "$DROPIN"
  if ((created_dir)); then
    sudo rmdir "$DROPIN_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -d "$DROPIN_DIR" ]]; then
  sudo mkdir -p "$DROPIN_DIR"
  created_dir=1
fi
printf '[Autologin]\nUser=%s\nSession=%s\n' "$USER" "$SESSION_FILE" | sudo tee "$DROPIN" >/dev/null

echo "Restarting SDDM with a one-time autologin for $USER ($SESSION_FILE)"
sudo systemctl restart sddm

for _ in $(seq 30); do
  sid=$(my_seat0_session)
  [[ -n "$sid" ]] && break
  sleep 1
done
cleanup # hned, ne až na konci: autologin má proběhnout jen tenhle jeden start sddm
if [[ -z "$sid" ]]; then
  echo "No session appeared on seat0 within 30 s — check: journalctl -u sddm -b | tail" >&2
  exit 1
fi

# --- lock the screen -------------------------------------------------------
# `loginctl lock-session` jen pošle signál; zamyká až swayidle (spouští ho
# config sway) svým `lock` handlerem → na něj je potřeba počkat.
uid=$(id -u)
for _ in $(seq 20); do
  pgrep -u "$uid" -x swayidle >/dev/null && break
  sleep 0.5
done
loginctl lock-session "$sid"

locked=0
for _ in $(seq 10); do
  # comm swaylock-effects je oříznuté na 15 znaků → bez -x
  if pgrep -u "$uid" swaylock >/dev/null; then
    locked=1
    break
  fi
  sleep 0.5
done

wl=
for f in "/run/user/$uid"/wayland-[0-9]*; do
  [[ -S "$f" ]] && { # socket, ne wayland-N.lock
    wl=${f##*/}
    break
  }
done
echo "Logged in: session $sid on seat0${wl:+ ($wl)}"
if ((locked)); then
  echo "Screen locked — unlock it in VNC with your password."
  echo "If typing into the lock screen over VNC does not work: pidof swaylock-effects | xargs -r kill -USR1"
else
  echo "WARNING: the screen is NOT locked (swayidle not running?) — the session is open at the keyboard" >&2
fi
echo "Connect from your machine with: vnc-desktop.sh"
