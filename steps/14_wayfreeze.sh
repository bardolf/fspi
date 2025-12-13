#!/usr/bin/env bash
set -euo pipefail
set -x

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

REPO_URL="https://github.com/Jappie3/wayfreeze.git"
INSTALL_DIR="$HOME/.local/bin"
BUILD_DIR="$HOME/.cache/wayfreeze-build"

log_info "Installing wayfreeze (Wayland screenshot freeze helper)"

# --- Kontrola, jestli už je wayfreeze k dispozici ---
if command -v wayfreeze >/dev/null 2>&1; then
  log_info "wayfreeze already installed at $(command -v wayfreeze)"
  exit 0
fi

# --- Kontrola, že je cargo k dispozici ---
if ! command -v cargo >/dev/null 2>&1; then
  log_error "Rust toolchain (cargo) not found. Please install it first."
  log_info "Use: sudo dnf install rust cargo"
  exit 1
fi

# --- Klonování nebo update repozitáře ---
if [[ ! -d "$BUILD_DIR" ]]; then
  log_info "Cloning $REPO_URL into $BUILD_DIR"
  git clone --depth 1 "$REPO_URL" "$BUILD_DIR"
else
  log_info "Updating existing repository..."
  git -C "$BUILD_DIR" pull --ff-only || log_warn "Could not update repository, continuing with existing version."
fi

# --- Build ---
log_info "Building wayfreeze..."
(
  cd "$BUILD_DIR"
  cargo build --release
)

# --- Instalace ---
mkdir -p "$INSTALL_DIR"
cp "$BUILD_DIR/target/release/wayfreeze" "$INSTALL_DIR/"

log_info "wayfreeze installed successfully → $INSTALL_DIR/wayfreeze"
