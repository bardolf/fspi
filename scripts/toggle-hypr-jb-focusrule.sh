#!/usr/bin/env bash
CONF="$HOME/.config/hypr/hyprland.conf"
RULE='windowrulev2 = stayfocused, tag:jb'

if grep -Fxq "$RULE" "$CONF"; then
  # rule exists → remove it
  sed -i "\|$RULE|d" "$CONF"
  echo "off" >/tmp/jb_focus_state
  notify-send "Hyprland" "Rule disabled: stayfocused, tag:jb"
else
  # rule missing → add it at end of file
  echo "$RULE" >>"$CONF"
  echo "on" >/tmp/jb_focus_state
  notify-send "Hyprland" "Rule enabled: stayfocused, tag:jb"
fi

# reload config
hyprctl reload
