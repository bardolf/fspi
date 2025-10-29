#!/usr/bin/env bash

MAC="84:AC:60:94:72:9F"

info=$(bluetoothctl info "$MAC")

if ! echo "$info" | grep -q "Connected: yes"; then
  # není připojeno → vrátíme prázdný text a tooltip
  echo '{"text": "", "tooltip": ""}'
  exit 0
fi

# Název zařízení
name=$(echo "$info" | grep "Name:" | cut -d ' ' -f2-)

# Baterie - rovnou v %
battery=$(echo "$info" | grep "Battery Percentage" | awk '{print $4}' | tr -d '()%')

# Ikona podle stavu baterie
icon=""
if [[ -n "$battery" ]] && [[ "$battery" -lt 20 ]]; then
  icon="⚠️" # varování při nízké baterii
fi

# Výstup pro Waybar
echo "{\"text\": \"${icon}${battery}\", \"tooltip\": \"${name} (${MAC})\"}"
