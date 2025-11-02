#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 23: Installing desktop entries and icons"

# -------------------------
# Paths
# -------------------------
DESKTOP_SRC="$SCRIPT_DIR/files/desktop"
ICONS_SRC="$SCRIPT_DIR/files/icons"

DESKTOP_TARGET="$HOME/.local/share/applications"
ICONS_TARGET="$HOME/.local/share/icons"

# -------------------------
# Create target directories if needed
# -------------------------
mkdir -p "$DESKTOP_TARGET"
mkdir -p "$ICONS_TARGET"

# -------------------------
# Copy .desktop files
# -------------------------
log_info "Copying .desktop files to $DESKTOP_TARGET"
find "$DESKTOP_SRC" -type f -name "*.desktop" -print0 | while IFS= read -r -d '' file; do
  log_info "→ Installing $(basename "$file")"
  cp -f "$file" "$DESKTOP_TARGET/"
done

# -------------------------
# Copy icon files
# -------------------------
log_info "Copying icon files to $ICONS_TARGET"
find "$ICONS_SRC" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \) -print0 | while IFS= read -r -d '' file; do
  log_info "→ Installing $(basename "$file")"
  cp -f "$file" "$ICONS_TARGET/"
done

# -------------------------
# Update desktop database
# -------------------------
if command -v update-desktop-database >/dev/null 2>&1; then
  log_info "Updating desktop database..."
  update-desktop-database "$HOME/.local/share/applications" || true
else
  log_warn "Command update-desktop-database not found; skipping cache update."
fi

log_info "Desktop entries and icons installed successfully."
