#!/usr/bin/env bash
set -euo pipefail

# WireGuard VPN home (router L009, wg-home, vpn.skybit.cz:51820) in two modes:
#
#   split  only home goes through the tunnel: router, desktop, NAS (samba, ssh),
#          Home Assistant and the VPN subnet; *.skybit.cz is resolved by the
#          router -> AdGuard, so the web apps go straight to the LAN too (even the
#          LAN-only ones like adguard.skybit.cz). Everything else stays local, so
#          vpn-cetin.sh can run next to it (172.16/12 vs 192.168.1/10.10 — no overlap).
#   full   everything through home: home public IP, AdGuard filtering on the go,
#          the local Wi-Fi sees only the tunnel. Capped by the home upload (CAKE
#          70 Mbit/s) and dead when the home internet is down.
#
# Both are NetworkManager profiles with the same key (one router peer per
# machine, 10.10.0.3 = this notebook); split vs full is decided only here on the
# client, the router lets the peer into the whole LAN either way.
#
#   vpn-home.sh setup <client.conf>   once per machine: create both profiles
#   vpn-home.sh split | full          connect (switches from the other mode)
#   vpn-home.sh down
#   vpn-home.sh status
#
# client.conf is the wg-quick style config made on the NAS
# (~/projects/home_network/vpn/notebook-wg.secret, not in git). After setup the
# private key lives in /etc/NetworkManager/system-connections and the copy can go.
#
# Only single hosts go through the split tunnel, not the whole 192.168.1.0/24:
# half of the foreign networks are 192.168.1.x too, and a /32 beats their
# connected /24, so the home hosts stay reachable there. If a host is missing,
# add it to SPLIT_IPS and run setup again.

SPLIT_IPS="192.168.1.1/32;192.168.1.10/32;192.168.1.11/32;192.168.1.120/32;10.10.0.0/24"
ROUTER_DNS="192.168.1.1"
HOME_GW_MAC="74:4d:28:f1:71:bf"     # LAN MAC of the router, same check as ~/.ssh/config
IFNAME="wg-home"

die() { echo "❌ $*" >&2; exit 1; }

at_home() {
    # Neighbour entry for the router with its MAC = we are on the home LAN. With
    # the split tunnel up, 192.168.1.1 goes via wg and has no neighbour entry.
    ip neigh show 192.168.1.1 | grep -qi "$HOME_GW_MAC" && return 0
    ping -c1 -W1 192.168.1.1 >/dev/null 2>&1 || true
    ip neigh show 192.168.1.1 | grep -qi "$HOME_GW_MAC"
}

active_mode() {
    nmcli -t -f NAME connection show --active | grep -E '^home-(split|full)$' || true
}

conf_value() {   # conf_value <file> <Key> — split on the FIRST "=" only, keys end with "="
    awk -v k="$2" '{ key = $0; sub(/[ \t]*=.*/, "", key) }
                   key == k { sub(/^[^=]*=[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$1"
}

setup() {
    local conf=${1:-}
    [[ -r "$conf" ]] || die "usage: $0 setup <client.conf>"
    local key addr pub endpoint
    key=$(conf_value "$conf" PrivateKey)
    addr=$(conf_value "$conf" Address)
    pub=$(conf_value "$conf" PublicKey)
    endpoint=$(conf_value "$conf" Endpoint)
    [[ -n "$key" && -n "$addr" && -n "$pub" && -n "$endpoint" ]] \
        || die "$conf: missing PrivateKey/Address/PublicKey/Endpoint"

    local mode
    for mode in split full; do
        nmcli connection delete "home-$mode" >/dev/null 2>&1 || true
    done

    # Common part. The key is on the nmcli command line for a moment (visible in
    # ps to other local users) — nmcli has no other way short of import.
    local common=(type wireguard ifname "$IFNAME" connection.autoconnect no
                  wireguard.private-key "$key" ipv4.method manual ipv4.addresses "$addr"
                  ipv4.dns "$ROUTER_DNS")

    # split: no default route; DNS only for *.skybit.cz (routing domain).
    nmcli connection add con-name home-split "${common[@]}" \
        ipv4.never-default yes ipv4.dns-search '~skybit.cz' \
        ipv6.method disabled \
        wireguard.peers "$pub endpoint=$endpoint allowed-ips=$SPLIT_IPS persistent-keepalive=25" \
        >/dev/null

    # full: default route via the tunnel (NM does it with policy routing, so the
    # more specific routes of vpn-cetin.sh still win); all DNS to the router,
    # dns-priority < 0 = exclusive, so nothing leaks to the local DNS. Home has no
    # IPv6: ::/0 goes into the tunnel too and the router drops it, otherwise IPv6
    # would bypass the tunnel on networks that have it.
    nmcli connection add con-name home-full "${common[@]}" \
        ipv4.dns-search '~.' ipv4.dns-priority -50 \
        ipv6.method manual ipv6.addresses fd00:10:10::3/128 \
        wireguard.peers "$pub endpoint=$endpoint allowed-ips=0.0.0.0/0;::/0 persistent-keepalive=25" \
        >/dev/null

    echo "✅ Profiles home-split and home-full created. The config copy can be deleted: $conf"
}

up() {
    local mode=$1
    at_home && die "This is the home LAN (router $HOME_GW_MAC) — no VPN needed."
    local cur
    cur=$(active_mode)
    [[ "$cur" == "home-$mode" ]] && { echo "Already connected: $cur"; return; }
    [[ -n "$cur" ]] && nmcli connection down "$cur" >/dev/null
    nmcli connection up "home-$mode" >/dev/null || die "home-$mode failed (setup done?)"
    echo "✅ VPN home: $mode"
    status
}

down() {
    local cur
    cur=$(active_mode)
    [[ -z "$cur" ]] && { echo "VPN home is not connected."; return; }
    nmcli connection down "$cur" >/dev/null
    echo "VPN home disconnected ($cur)."
}

status() {
    local cur
    cur=$(active_mode)
    if [[ -z "$cur" ]]; then
        echo "VPN home: off$(at_home && echo ' (home LAN)')"
        return
    fi
    echo "VPN home: ${cur#home-}"
    if ping -c1 -W2 192.168.1.11 >/dev/null 2>&1; then echo "  NAS 192.168.1.11: reachable"
    else echo "  NAS 192.168.1.11: NOT reachable"; fi
    echo "  photos.skybit.cz -> $(resolvectl query --legend=no photos.skybit.cz 2>/dev/null | awk '{print $2; exit}')"
    echo "  public IP: $(curl -s --max-time 5 https://ifconfig.me || echo '?')"
}

case "${1:-status}" in
    setup)      setup "${2:-}" ;;
    split|full) up "$1" ;;
    down)       down ;;
    status)     status ;;
    *)          die "usage: $0 setup <client.conf> | split | full | down | status" ;;
esac
