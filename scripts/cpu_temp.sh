#!/usr/bin/env bash

TEMP=$(sensors k10temp-pci-00c3 | awk '/Tctl:/ {print int($2)}') # int() odstraní desetinná místa

# Default ikona
ICON="󱃃"

if [[ "$TEMP" != "n/a" ]]; then
  if ((TEMP >= 90)); then
    ICON="󰀦"
  elif ((TEMP >= 60)); then
    ICON="󱃂"
  else
    ICON="󰔏"
  fi
fi

echo "$ICON $TEMP°C"
