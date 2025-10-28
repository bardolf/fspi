#!/bin/bash
URL="$1"
shift

# Najdi prohlížeč
BROWSER=$(command -v chromium-browser || command -v google-chrome || command -v brave-browser || command -v microsoft-edge || command -v vivaldi)

if [ -z "$BROWSER" ]; then
  echo "No Chrome-like browser found"
  exit 1
fi

# Spustíme webapp jako samostatné okno
exec "$BROWSER" --new-window --app="$URL" "$@"
