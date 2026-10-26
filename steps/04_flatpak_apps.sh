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
  "com.spotify.Client"
  "org.signal.Signal"
  "com.rtosta.zapzap"
  "com.bitwarden.desktop"
  "net.cozic.joplin_desktop"
  "com.jgraph.drawio.desktop"
  "org.fedoraproject.MediaWriter"
  "dev.zed.Zed"
  "org.freecad.FreeCAD"
)

for app in "${APPS[@]}"; do
  if flatpak list --app | grep -q "$app"; then
    log_debug "Flatpak app already installed: $app"
  else
    log_info "Installing Flatpak app: $app"
    flatpak install -y flathub "$app"
  fi
done

# Electron's tray icon requests the bus name
# org.freedesktop.StatusNotifierItem-<pid>-<n> and silently gives up when the
# flatpak D-Bus proxy refuses it, so Teams never shows up in the waybar tray.
# Inside the sandbox the app is always pid 2 and Teams has a single icon, so
# the name is fixed.
TEAMS_APP="com.github.IsmaelMartinez.teams_for_linux"
TEAMS_TRAY_NAME="org.freedesktop.StatusNotifierItem-2-1"
if flatpak override --user --show "$TEAMS_APP" | grep -qF "$TEAMS_TRAY_NAME=own"; then
  log_debug "Teams already allowed to own $TEAMS_TRAY_NAME"
else
  log_info "Allowing Teams to own $TEAMS_TRAY_NAME (tray icon)"
  flatpak override --user --own-name="$TEAMS_TRAY_NAME" "$TEAMS_APP"
fi

log_info "Flatpak applications installed successfully."
