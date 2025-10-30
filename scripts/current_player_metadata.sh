#!/usr/bin/env bash
# ~/bin/now_playing.sh
# chmod +x ~/bin/now_playing.sh

# Získat metadata
ARTIST=$(playerctl metadata artist 2>/dev/null || echo "Unknown Artist")
TITLE=$(playerctl metadata title 2>/dev/null || echo "Unknown Title")
ALBUM=$(playerctl metadata album 2>/dev/null || echo "Unknown Album")
ART_URL=$(playerctl metadata mpris:artUrl 2>/dev/null || echo "")

ICON_PATH=""

# Pokud existuje URL obrázku, stáhnout do /tmp
if [[ -n "$ART_URL" ]]; then
  # pokud je file://, použít přímo
  if [[ "$ART_URL" =~ ^file:// ]]; then
    ICON_PATH="${ART_URL#file://}"
  else
    # stáhnout přes curl/wget
    ICON_PATH="/tmp/now_playing_album.png"
    curl -sSL "$ART_URL" -o "$ICON_PATH"
  fi
fi

# Zobrazit notifikaci
if [[ -n "$ICON_PATH" && -f "$ICON_PATH" ]]; then
  notify-send "Now Playing" "$ARTIST - $TITLE\n$ALBUM" -i "$ICON_PATH" -t 5000
else
  notify-send "Now Playing" "$ARTIST - $TITLE\n$ALBUM" -t 5000
fi
