#!/usr/bin/env bash
# VNC na desktop on demand: SSH tunel → wayvnc jen na 127.0.0.1 → VNC klient.
# wayvnc, který skript sám spustí, po zavření klienta zase zastaví; už běžící
# instanci jen použije a nechá být.
#
#   vnc-desktop.sh                  # remote-viewer (nativní Wayland, škáluje)
#   vnc-desktop.sh tigervnc         # vncviewer (X11 → na scale 1.3 přiblížený)
#   vnc-desktop.sh remote-viewer -f # další argumenty jdou klientovi (-f = fullscreen)
#   VNC_HOST=desktop-jump vnc-desktop.sh
#
# Zkratky ($mod+číslo, …) pošleš do VNC sway módem passthrough ($mod+Pause).

set -euo pipefail

HOST=${VNC_HOST:-desktop}
RPORT=5900
CLIENT=${1:-remote-viewer}
shift || true

# Vzdálená strana. READY až ve chvíli, kdy port poslouchá. Spojení drží `cat`
# na stdin: EOF (konec skriptu, pád SSH) → úklid wayvnc, pokud ho spustila.
REMOTE=$(cat <<'EOF'
port=$1
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
listening() { ss -Htln "sport = :$port" | grep -q .; }
pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null' EXIT
if ! listening; then
  WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -n1)
  [ -n "$WAYLAND_DISPLAY" ] || { echo "no wayland session on $(hostname)" >&2; exit 1; }
  export WAYLAND_DISPLAY
  wayvnc 127.0.0.1 "$port" </dev/null >"$XDG_RUNTIME_DIR/wayvnc-ondemand.log" 2>&1 &
  pid=$!
  for _ in $(seq 50); do listening && break; sleep 0.1; done
fi
listening || { echo "wayvnc did not start, see $XDG_RUNTIME_DIR/wayvnc-ondemand.log" >&2; exit 1; }
echo READY
cat >/dev/null
EOF
)

# První volný lokální port od 5900 (5900 může držet jiný tunel).
lport=$RPORT
while ss -Htln "sport = :$lport" | grep -q .; do
  lport=$((lport + 1))
done

coproc SSH {
  exec ssh -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 \
    -L "$lport:127.0.0.1:$RPORT" "$HOST" "bash -c $(printf '%q' "$REMOTE") _ $RPORT"
}
# shellcheck disable=SC2153  # SSH_PID nastavuje coproc
ssh_pid=$SSH_PID
ssh_in=${SSH[1]}
ssh_out=${SSH[0]}

cleanup() {
  # Zavřený stdin = EOF pro vzdálený `cat` → wayvnc skončí, ssh se odpojí.
  exec {ssh_in}>&- 2>/dev/null || true
  for _ in $(seq 30); do
    kill -0 "$ssh_pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill "$ssh_pid" 2>/dev/null || true
}
trap cleanup EXIT

if ! read -r -t 30 line <&"$ssh_out" || [[ $line != READY ]]; then
  echo "vnc-desktop: tunel na $HOST nenaběhl" >&2
  exit 1
fi

case $CLIENT in
  remote-viewer)
    # --auto-resize=never: ve fullscreenu by jinak chtěl po wayvnc rozlišení
    # monitoru v logických bodech (2953x1661 na scale 1.3); wayvnc ho nezmění,
    # posílá dál 3840x2160 a gtk-vnc spojení shodí ("outside boundary").
    remote-viewer --title "VNC $HOST" --auto-resize=never "$@" "vnc://127.0.0.1:$lport" ;;
  tigervnc|vncviewer)
    vncviewer "$@" "127.0.0.1::$lport" ;;
  *)
    echo "usage: vnc-desktop.sh [remote-viewer|tigervnc]" >&2
    exit 2 ;;
esac
