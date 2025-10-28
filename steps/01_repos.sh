#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Adding essential repositories (RPM Fusion, Flathub)"

# --- RPM Fusion ---
FREE_URL="https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
NONFREE_URL="https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

if ! dnf repolist --enabled | grep -q rpmfusion-free; then
  log_info "Adding RPM Fusion Free"
  sudo dnf install -y "$FREE_URL"
else
  log_debug "RPM Fusion Free already enabled"
fi

if ! dnf repolist --enabled | grep -q rpmfusion-nonfree; then
  log_info "Adding RPM Fusion Nonfree"
  sudo dnf install -y "$NONFREE_URL"
else
  log_debug "RPM Fusion Nonfree already enabled"
fi

# --- Flathub ---
if ! flatpak remotes | grep -q flathub; then
  log_info "Adding Flathub remote"
  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
else
  log_debug "Flathub already added"
fi

log_info "Repository setup complete."
