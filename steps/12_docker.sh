#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 12: Installing Docker and Docker Compose"

# --- Install prerequisites ---
PACKAGES=(dnf-plugins-core device-mapper-persistent-data lvm2)
for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

# --- Add Docker official repository (Fedora 41+) ---
DOCKER_REPO_FILE="/etc/yum.repos.d/docker-ce.repo"
if [[ ! -f "$DOCKER_REPO_FILE" ]]; then
  log_info "Adding Docker repository"
  sudo curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o "$DOCKER_REPO_FILE"
else
  log_debug "Docker repository already exists"
fi

# --- Install Docker Engine, CLI, and Compose Plugin ---
PACKAGES=(docker-ce docker-ce-cli containerd.io docker-compose-plugin)
for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

# --- Enable and start Docker service ---
log_info "Enabling and starting Docker service"
sudo systemctl enable docker --now

# --- Add current user to docker group ---
CURRENT_USER=$(whoami)
if ! groups "$CURRENT_USER" | grep -q "\bdocker\b"; then
  log_info "Adding $CURRENT_USER to docker group"
  sudo usermod -aG docker "$CURRENT_USER"
  log_info "You may need to log out and log back in for group changes to take effect"
else
  log_debug "$CURRENT_USER is already in docker group"
fi

log_info "Docker installation complete"
