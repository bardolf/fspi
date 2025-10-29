#!/usr/bin/env bash
# Dell monitor brightness pro Waybar

# cesta k ddcutil nebo dell-brightness
# Zjistí aktuální jas a vrátí číslo 0-100
BRIGHTNESS=$(
  ddcutil getvcp 10 | awk -F= '{gsub(/ /,"",$2); print $2}' | cut -d',' -f1
)

echo "$BRIGHTNESS"
