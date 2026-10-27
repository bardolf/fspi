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

# Marker string the no_keymap patch below compiles into the binary; an
# installed binary without it predates the patch and gets rebuilt.
PATCH_MARKER="Ignoring keyboard without keymap (no_keymap)"

# --- Skip if already built, patched and installed ---
if [[ -x "$INSTALL_DIR/$BINARY_NAME" ]] && grep -qaF "$PATCH_MARKER" "$INSTALL_DIR/$BINARY_NAME"; then
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
  # Drop our patch first so the pull never conflicts with it.
  git -C "$BUILD_DIR" checkout -- seat.c
  git -C "$BUILD_DIR" pull --ff-only || log_warn "Could not update repository, continuing with existing checkout."
fi

# --- Patch: survive a keyboard without keymap ---
# wayvnc's virtual keyboard briefly has no keymap; sway then sends
# WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP and the fork exit(1)s with "Unknown keymap
# format 0, aborting" — the session stays locked behind a red screen. Upstream
# swaylock ignores no_keymap; the fork (unmaintained) never picked that up.
if ! grep -q 'WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP' "$BUILD_DIR/seat.c"; then
  log_info "Patching seat.c to ignore no_keymap keyboards (wayvnc)"
  sed -i "/if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {/i\\
\\tif (format == WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP) {\\
\\t\\tswaylock_log(LOG_DEBUG, \"$PATCH_MARKER\");\\
\\t\\tclose(fd);\\
\\t\\treturn;\\
\\t}" "$BUILD_DIR/seat.c"
  grep -q 'WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP' "$BUILD_DIR/seat.c" || {
    log_error "seat.c patch did not apply (upstream changed?)"
    exit 1
  }
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
# install(1) replaces the file instead of writing into it, so a running lock
# screen does not fail the copy with "Text file busy".
install -m 755 "$BUILD_DIR/build/swaylock" "$INSTALL_DIR/$BINARY_NAME"

log_info "swaylock-effects installed → $INSTALL_DIR/$BINARY_NAME"
log_info "PAM service name is 'swaylock' (hardcoded upstream) — existing /etc/pam.d/swaylock applies."
