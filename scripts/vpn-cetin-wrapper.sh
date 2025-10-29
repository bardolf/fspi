#!/usr/bin/env bash

VPN_IF="tun0"
VPN_SCRIPT="/home/milan/scripts/vpn-cetin.sh"
VPN_PID_FILE="/run/vpn-cetin.pid"

# --- Stav ---
vpn_running() {
  ip link show "$VPN_IF" &>/dev/null
}

# --- Připojení VPN ---
start_vpn() {
  echo "🔐 Starting VPN..."
  # Spustíme původní skript jako root (na pozadí)
  sudo "$VPN_SCRIPT" &
  echo $! | sudo tee "$VPN_PID_FILE" >/dev/null
}

# --- Odpojení VPN ---
stop_vpn() {
  echo "🔓 Stopping VPN..."
  if [[ -f "$VPN_PID_FILE" ]]; then
    sudo kill "$(cat "$VPN_PID_FILE")" 2>/dev/null
    sudo rm -f "$VPN_PID_FILE"
  else
    sudo pkill -f "openconnect.*zamevpn.cetin.cz" 2>/dev/null
  fi
}

# --- Výstup pro Waybar ---
print_status() {
  if vpn_running; then
    echo '{"text":"| VPN","tooltip":"CETIN VPN connected","class":"connected"}'
  else
    echo '{"text":"| VPN","tooltip":"CETIN VPN disconnected","class":"disconnected"}'
  fi
}

# --- Main logic ---
case "$1" in
toggle)
  if vpn_running; then
    stop_vpn
  else
    start_vpn
  fi
  ;;
status | "")
  print_status
  ;;
*)
  echo "Usage: $0 [toggle|status]"
  exit 1
  ;;
esac
