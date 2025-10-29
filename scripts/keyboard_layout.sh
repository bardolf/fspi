#!/usr/bin/env bash

# zjisti aktivní layout
layout=$(swaymsg -t get_inputs | jq -r '
  .[] | select(.type=="keyboard") |
  .xkb_active_layout_name' | head -1)

# převedeme na krátký kód + vlajku
case "$layout" in
*Czech* | *cz*)
  echo "🇨🇿 CZ"
  ;;
*English* | *us*)
  echo "🇺🇸 US"
  ;;
*)
  echo "$layout"
  ;;
esac
