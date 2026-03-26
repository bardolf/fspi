#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Adding essential repositories (RPM Fusion, Flathub, Vivaldi, git-secret, Terra)"

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

# --- Vivaldi ---
VIVALDI_REPO="/etc/yum.repos.d/vivaldi.repo"
if [[ ! -f "$VIVALDI_REPO" ]]; then
  log_info "Adding Vivaldi repository"
  sudo tee "$VIVALDI_REPO" >/dev/null <<'EOF'
[vivaldi]
name=Vivaldi browser stable repository
baseurl=https://repo.vivaldi.com/stable/rpm/x86_64
enabled=1
gpgcheck=1
gpgkey=https://repo.vivaldi.com/stable/linux_signing_key.pub
EOF
  sudo dnf makecache -y || sudo dnf5 makecache -y
else
  log_debug "Vivaldi repository already present"
fi

# --- git-secret ---
GIT_SECRET_REPO="/etc/yum.repos.d/git-secret-rpm.repo"
if [[ ! -f "$GIT_SECRET_REPO" ]]; then
  log_info "Adding git-secret repository"
  sudo wget https://raw.githubusercontent.com/sobolevn/git-secret/master/utils/rpm/git-secret.repo \
    -O "$GIT_SECRET_REPO"
  sudo dnf makecache -y || sudo dnf5 makecache -y
else
  log_debug "git-secret repository already present"
fi

# --- Terra ---
if ! dnf repolist --enabled | grep -q terra; then
  log_info "Adding Terra repository"
  sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
else
  log_debug "Terra repository already enabled"
fi

log_info "Repository setup complete."
