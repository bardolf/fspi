#!/bin/bash
URL="$1"
shift

# Najdi prohlížeč
BROWSER=$(command -v chromium-browser || command -v google-chrome || command -v brave-browser || command -v microsoft-edge || command -v vivaldi)

if [ -z "$BROWSER" ]; then
  echo "No Chrome-like browser found"
  exit 1
fi

# Host-specific flagy (NVIDIA Wayland: vypnout GPU kompozici kvůli artefaktům)
DIR=$(dirname "$(readlink -f "$0")")
read -ra EXTRA <<< "$("$DIR/chromium_host_flags.sh")"

# Spustíme webapp jako samostatné okno
exec "$BROWSER" "${EXTRA[@]}" --new-window --app="$URL" "$@"
