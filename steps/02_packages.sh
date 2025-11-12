#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Installing essential packages"

# --- Basic command line tools ---
PACKAGES=(
  vim
  mc
  htop
  flatpak
  chromium
  qalc
  mpv
  xournalpp
  okular
  feh
  texlive-scheme-medium
  gimp
  inkscape
  graphviz
  libreoffice
  grim
  slurp
  flameshot
  jq
  wl-clipboard
  libnotify
  azure-cli
  k9s
  wayland-utils
  vivaldi-stable
  libxkbcommon-devel
  postgresql
)

for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

log_info "Base packages installed successfully."
