#!/usr/bin/env bash
set -euo pipefail

# Načti výchozí adresář pro screenshoty
[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
OUTPUT_DIR="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  notify-send "Screenshot directory does not exist: $OUTPUT_DIR" -u critical -t 3000
  exit 1
fi

MODE="${1:-smart}"
PROCESSING="${2:-slurp}"

# Získání geometrie obrazovky (jediný výstup)
get_output_geometry() {
  swaymsg -t get_outputs -r | jq -r '.[] | select(.active == true) | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"' | head -n1
}

# Získání viditelných oken aktuálního workspace
get_window_rects() {
  swaymsg -t get_tree -r |
    jq -r '
      .. | objects
      | select(.type? == "con" and .visible == true)
      | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"'
}

# Výběr podle režimu
case "$MODE" in
region)
  SELECTION=$(slurp 2>/dev/null)
  ;;
windows)
  RECTS=$(get_window_rects)
  SELECTION=$(echo "$RECTS" | slurp -r 2>/dev/null)
  ;;
fullscreen)
  SELECTION=$(get_output_geometry)
  ;;
smart | *)
  RECTS=$(get_window_rects)
  SELECTION=$(echo "$RECTS" | slurp 2>/dev/null)

  # Pokud je výběr příliš malý, klik = vyber nejbližší okno
  if [[ "$SELECTION" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]]; then
    if ((${BASH_REMATCH[3]} * ${BASH_REMATCH[4]} < 20)); then
      click_x="${BASH_REMATCH[1]}"
      click_y="${BASH_REMATCH[2]}"

      while IFS= read -r rect; do
        if [[ "$rect" =~ ^([0-9]+),([0-9]+)[[:space:]]([0-9]+)x([0-9]+) ]]; then
          rect_x="${BASH_REMATCH[1]}"
          rect_y="${BASH_REMATCH[2]}"
          rect_width="${BASH_REMATCH[3]}"
          rect_height="${BASH_REMATCH[4]}"

          if ((click_x >= rect_x && click_x < rect_x + rect_width && click_y >= rect_y && click_y < rect_y + rect_height)); then
            SELECTION="${rect_x},${rect_y} ${rect_width}x${rect_height}"
            break
          fi
        fi
      done <<<"$RECTS"
    fi
  fi
  ;;
esac

[ -z "$SELECTION" ] && exit 0

# Název souboru
FILENAME="$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png"

# Pořízení screenshotu
grim -g "$SELECTION" "$FILENAME"

# Zkopírování do schránky
wl-copy <"$FILENAME"

# Notifikace
notify-send "📸 Screenshot captured" "Saved to $FILENAME" -t 1500
