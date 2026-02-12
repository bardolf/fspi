#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Installing Flatpak applications"

# Ensure flatpak exists
if ! command -v flatpak >/dev/null 2>&1; then
  log_error "Flatpak not installed. Run steps/02_packages.sh first."
  exit 1
fi

# Ensure flathub remote exists
if ! flatpak remotes | grep -q flathub; then
  log_info "Adding Flathub remote"
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# --- List of Flatpak apps ---
APPS=(
  "com.github.IsmaelMartinez.teams_for_linux"
  "org.wezfurlong.wezterm"
  "com.spotify.Client"
  "org.signal.Signal"
  "com.rtosta.zapzap"
  "com.bitwarden.desktop"
  "net.cozic.joplin_desktop"
  "com.jetbrains.IntelliJ-IDEA-Ultimate"
  "com.jgraph.drawio.desktop"
  "org.fedoraproject.MediaWriter"
)

for app in "${APPS[@]}"; do
  if flatpak list --app | grep -q "$app"; then
    log_debug "Flatpak app already installed: $app"
  else
    log_info "Installing Flatpak app: $app"
    flatpak install -y flathub "$app"
  fi
done

log_info "Flatpak applications installed successfully."
