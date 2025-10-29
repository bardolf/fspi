#!/usr/bin/env bash

MAC="84:AC:60:94:72:9F"

print_info() {
  info=$(bluetoothctl info "$MAC")

  if ! echo "$info" | grep -q "Connected: yes"; then
    # není připojeno → prázdný výstup
    echo "{\"text\": \"\", \"tooltip\": \"\"}"
    return
  fi

  # počkej, dokud není Battery Percentage k dispozici (max 5 pokusů)
  battery=""
  for i in {1..5}; do
    battery=$(echo "$info" | grep "Battery Percentage" | awk '{print $4}' | tr -d '()%')
    if [[ -n "$battery" ]]; then
      break
    fi
    sleep 1
    info=$(bluetoothctl info "$MAC")
  done

  # Název zařízení
  name=$(echo "$info" | grep "Name:" | cut -d ' ' -f2-)

  # Ikona podle stavu baterie
  icon=""
  if [[ -n "$battery" ]] && [[ "$battery" -lt 30 ]]; then
    icon="⚠️"
  fi

  # Výstup pro Waybar
  echo "{\"text\": \"${icon}${battery}%\", \"tooltip\": \"${name} (${MAC})\"}"
}

# Nejprve vypsat stav na start
print_info

# Sleduj události přes bluetoothctl --monitor
bluetoothctl --monitor | while read -r line; do
  if echo "$line" | grep -q "$MAC"; then
    print_info
  fi
done
