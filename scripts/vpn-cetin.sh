#!/bin/bash

# --- Check for root privileges ---
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ This script must be run as root. Try:"
  echo "   sudo $0"
  exit 1
fi

VPN_SERVER="zamevpn.cetin.cz"
CERT="/home/milan/work/cetin/vpn/nemecm.crt.pem"
KEY="/home/milan/work/cetin/vpn/nemecm.key.pem"
CAFILE="/home/milan/work/cetin/vpn/cacerts/complete-with-defaults.crt"

# Původní DNS uložíme pro obnovu
ORIG_DNS=$(resolvectl status | awk '/DNS Servers:/ {print $3}' | head -n1)
ORIG_DOMAIN=$(resolvectl status | awk '/DNS Domain:/ {print $3}' | head -n1)

echo "Původní DNS: $ORIG_DNS, původní domain: $ORIG_DOMAIN"

# Spustíme openconnect s vpn-slice na pozadí
openconnect --protocol=anyconnect $VPN_SERVER \
  --cafile=$CAFILE \
  --certificate=$CERT \
  --sslkey=$KEY \
  --script "vpn-slice \
    -d cetin \
    -d ad.cetin \
    -d privatelink.germanywestcentral.azmk8s.io \
    -d postgres.database.azure.com \
    -d privatelink.azurecr.io \
    -d acrniintdevgwc01.azurecr.io \
    -d crninpaksgwc.azurecr.io \
    -d crnipaksgwc.azurecr.io \
    172.16.0.0/12 \
    172.25.41.0/24" &

VPN_PID=$!
echo "Čekám, až se vytvoří tun0..."
while ! ip link show tun0 &>/dev/null; do
  sleep 1
done
echo "tun0 existuje, čekám na inicializaci vpn-slice..."
sleep 3

echo "Nastavujeme DNS..."
# Nastavení firemních DNS a search domén
resolvectl dns tun0 172.29.128.11 172.29.128.10
resolvectl domain tun0 cetin ad.cetin \
  privatelink.germanywestcentral.azmk8s.io \
  postgres.database.azure.com \
  privatelink.azurecr.io \
  acrniintdevgwc01.azurecr.io \
  crninpaksgwc.azurecr.io \
  crnipaksgwc.azurecr.io

echo "VPN připojena a DNS nastavena."

# Po odpojení VPN obnovíme původní DNS
wait $VPN_PID
echo "VPN odpojena, obnovuji původní DNS..."
if [ -n "$ORIG_DNS" ]; then
  sudo resolvectl dns tun0 $ORIG_DNS
fi
if [ -n "$ORIG_DOMAIN" ]; then
  sudo resolvectl domain tun0 $ORIG_DOMAIN
fi
echo "Hotovo."
