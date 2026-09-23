#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 06d: Opening firewall ports for WinBox and qBittorrent"

# Fedora Sway (VARIANT_ID=sway) dostane při instalaci firewalld-standard.conf,
# tedy výchozí zónu public — ne FedoraWorkstation jako Workstation/KDE, která
# pouští všechno nad 1024. V public je jen ssh, mdns a dhcpv6-client, takže
# každý příchozí port se povoluje tady. Zóna se schválně nemění.
#
#   5678/udp      MNDP — ohlašování MikroTiků; bez něj je WinBox → Neighbors prázdné
#   7881/tcp+udp  qBittorrent — router předává 7881 z internetu na 192.168.1.10
#                 (repo home_network), qBittorrent musí poslouchat právě na něm
TORRENT_PORT=7881
PORTS=(5678/udp "$TORRENT_PORT/tcp" "$TORRENT_PORT/udp")

# WinBox přes MAC: klient posílá z náhodného portu na 255.255.255.255:20561 a
# MikroTik odpovídá z 0.0.0.0:20561 na 255.255.255.255:<ten náhodný port>.
# Conntrack takovou odpověď k dotazu nepřiřadí, takže otevřít cílový port 20561
# nestačí (tam nic nechodí) — pouští se pakety se ZDROJOVÝM portem 20561, a jen
# na broadcast, aby to nebyla díra do všech UDP portů. Bez toho WinBox hlásí
# "MacConnection syn timeout".
MAC_WINBOX_RULE='rule family="ipv4" destination address="255.255.255.255" source-port port="20561" protocol="udp" accept'

if ! systemctl is-active --quiet firewalld; then
  log_warn "firewalld is not running, skipping"
  exit 0
fi

zone=$(run_sudo firewall-cmd --get-default-zone)
reload=0
for port in "${PORTS[@]}"; do
  if run_sudo firewall-cmd --permanent --query-port="$port" >/dev/null 2>&1; then
    log_debug "Port $port already open in zone $zone"
  else
    log_info "Opening port $port in zone $zone"
    run_sudo firewall-cmd --permanent --add-port="$port" >/dev/null
    reload=1
  fi
done

if run_sudo firewall-cmd --permanent --query-rich-rule="$MAC_WINBOX_RULE" >/dev/null 2>&1; then
  log_debug "MAC-WinBox reply rule already present in zone $zone"
else
  log_info "Allowing MAC-WinBox replies (source port 20561/udp) in zone $zone"
  run_sudo firewall-cmd --permanent --add-rich-rule="$MAC_WINBOX_RULE" >/dev/null
  reload=1
fi

if [[ "$reload" -eq 1 ]]; then
  log_info "Reloading firewalld"
  run_sudo firewall-cmd --reload >/dev/null
fi

# --- qBittorrent musí poslouchat na přesměrovaném portu ---
# Při prvním spuštění si vylosuje náhodný port a nic neřekne — na desktopu tak
# poslouchal na 3530, zatímco router předával 7881. Jen upozornit: config si
# qBittorrent při ukončení přepisuje, nastavuje se v GUI.
QBT_CONF="$HOME/.config/qBittorrent/qBittorrent.conf"
if [[ -f "$QBT_CONF" ]]; then
  qbt_port=$(sed -n 's/^Session\\Port=//p' "$QBT_CONF")
  if [[ "$qbt_port" == "$TORRENT_PORT" ]]; then
    log_debug "qBittorrent already listens on $TORRENT_PORT"
  else
    log_warn "qBittorrent listens on ${qbt_port:-a random port}, but the router forwards $TORRENT_PORT"
    log_warn "  Fix: qBittorrent → Tools → Options → Connection → Port used for incoming connections"
  fi
fi

log_info "Step 06d complete"
