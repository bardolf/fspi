#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

REPO_URL="https://github.com/Satty-org/Satty"
REPO_DIR="$SCRIPT_DIR/build/Satty"

log_info "Installing Satty dependencies"

# --- Native dependencies ---
PACKAGES=(
  glib2
  gtk4
  gdk-pixbuf2
  libadwaita
  libepoxy
  fontconfig
  make
  gcc
  git
  cargo
  pkg-config
)

for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

# --- Dev packages per distro ---
if command -v apt >/dev/null 2>&1; then
  ensure_package libcairo2-dev
  ensure_package libglib2.0-dev
  ensure_package libgtk-4-dev
  ensure_package libadwaita-1-dev
  ensure_package libepoxy-dev
elif command -v dnf >/dev/null 2>&1; then
  ensure_package cairo-gobject-devel
  ensure_package glib2-devel
  ensure_package gtk4-devel
  ensure_package libadwaita-devel
  ensure_package libepoxy-devel
elif command -v pacman >/dev/null 2>&1; then
  ensure_package gtk4
  ensure_package libadwaita
  ensure_package cairo
  ensure_package libepoxy
fi
log_info "All Satty dependencies installed successfully."

# --- Clone and build ---
if [ ! -d "$REPO_DIR" ]; then
  log_info "Cloning Satty repository..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  log_info "Satty repository already exists, skipping clone."
fi

cd "$REPO_DIR"
log_info "Building Satty (release mode)..."
make build-release

# --- Install binary ---
log_info "Installing Satty to /usr/local..."
PREFIX="$HOME/.local" make install

log_info "Satty installed successfully!"
