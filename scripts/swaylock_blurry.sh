#!/usr/bin/env bash
set -euo pipefail

LOCKSCREEN=/tmp/lockscreen.png
BLUR_TEMP=/tmp/lockscreen_blur.png

# --- Blur settings ---
RESIZE_PERCENT=25                           # intermediate resize, menší = víc rozmazání
BLUR_SIGMA=1.5                              # jemnější blur
RESIZE_BACK=$((100 * 100 / RESIZE_PERCENT)) # zpět na původní velikost

# --- Swaylock settings ---
BG_COLOR="1c1c1c" # pokud bys chtěl solid color místo image
RING_COLOR="777777"
RING_VER_COLOR="00ff00"
RING_WRONG_COLOR="ff0000"
INDICATOR_RADIUS=100
INDICATOR_THICKNESS=7
TEXT_COLOR="ffffff"
INSIDE_COLOR="1c1c1c"
FONT="Monospace 12"

# --- Take screenshot ---
grim "$LOCKSCREEN"

# --- Apply blur ---
ffmpeg -loglevel error -i "$LOCKSCREEN" -vf "gblur=sigma=14" -y "$BLUR_TEMP"
#magick "$LOCKSCREEN" -filter Gaussian -resize "${RESIZE_PERCENT}%" -blur 0x$BLUR_SIGMA -resize "${RESIZE_BACK}%" "$BLUR_TEMP"
mv "$BLUR_TEMP" "$LOCKSCREEN"

# --- Call swaylock ---
swaylock -f \
  -i "$LOCKSCREEN" \
  --indicator-radius $INDICATOR_RADIUS \
  --indicator-thickness $INDICATOR_THICKNESS \
  --ring-color $RING_COLOR \
  --ring-ver-color $RING_VER_COLOR \
  --ring-wrong-color $RING_WRONG_COLOR \
  --inside-color $INSIDE_COLOR \
  --text-color $TEXT_COLOR \
  --font "$FONT"
