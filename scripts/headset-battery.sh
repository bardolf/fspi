#!/bin/bash

DEVICE="/org/freedesktop/UPower/devices/headset_dev_84_AC_60_94_72_9F"

# Zjisti procenta
PERCENT=$(upower -i "$DEVICE" | awk '/percentage:/ {print $2}')

# Pokud není připojeno
if [ -z "$PERCENT" ]; then
  echo "N/A"
  exit 0
fi

# Výstup pro waybar (bez procentního znaku, přidáme v configu)
echo "${PERCENT%\%}"
