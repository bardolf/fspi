#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

REPO_URL="https://github.com/jirutka/swaylock-effects.git"
BUILD_DIR="$HOME/.cache/swaylock-effects-build"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="swaylock-effects"

log_info "Installing swaylock-effects (lock screen with blur/screenshot effects)"

# --- Skip if already built and installed ---
if [[ -x "$INSTALL_DIR/$BINARY_NAME" ]]; then
  log_debug "$BINARY_NAME already installed at $INSTALL_DIR/$BINARY_NAME"
  exit 0
fi

# --- Build dependencies (meson + native libs) ---
DEPS=(
  meson
  ninja-build
  scdoc
  gcc
  git
  pam-devel
  cairo-devel
  gdk-pixbuf2-devel
  wayland-devel
  wayland-protocols-devel
  libxkbcommon-devel
)

for pkg in "${DEPS[@]}"; do
  ensure_package "$pkg"
done

# --- Clone or update source ---
if [[ ! -d "$BUILD_DIR" ]]; then
  log_info "Cloning $REPO_URL into $BUILD_DIR"
  git clone --depth 1 "$REPO_URL" "$BUILD_DIR"
else
  log_info "Updating existing repository..."
  git -C "$BUILD_DIR" pull --ff-only || log_warn "Could not update repository, continuing with existing checkout."
fi

# --- Build with meson/ninja ---
log_info "Building swaylock-effects (meson + ninja)..."
(
  cd "$BUILD_DIR"
  # Reconfigure cleanly if a previous build dir exists with a different toolchain
  if [[ -d build ]]; then
    meson setup --reconfigure build
  else
    meson setup build
  fi
  ninja -C build
)

# --- Install renamed binary so it does not shadow stock /usr/bin/swaylock ---
mkdir -p "$INSTALL_DIR"
cp "$BUILD_DIR/build/swaylock" "$INSTALL_DIR/$BINARY_NAME"

log_info "swaylock-effects installed → $INSTALL_DIR/$BINARY_NAME"
log_info "PAM service name is 'swaylock' (hardcoded upstream) — existing /etc/pam.d/swaylock applies."
