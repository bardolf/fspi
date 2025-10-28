#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Installing Visual Studio Code"

# --- Import Microsoft GPG key if missing ---
KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
if rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release}\n' | grep -q "microsoft"; then
    log_debug "Microsoft GPG key already imported"
else
    log_info "Importing Microsoft GPG key"
    sudo rpm --import "$KEY_URL"
fi

# --- Add VS Code repo if missing ---
REPO_FILE="/etc/yum.repos.d/vscode.repo"
if [[ -f "$REPO_FILE" ]]; then
    log_debug "VS Code repository already exists: $REPO_FILE"
else
    log_info "Adding VS Code repository"
    echo -e "[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=$KEY_URL" | sudo tee "$REPO_FILE" > /dev/null
fi

# --- Install VS Code if not installed ---
if rpm -q code >/dev/null 2>&1; then
    log_debug "VS Code already installed"
else
    log_info "Installing VS Code"
    sudo dnf check-update || true   # avoid error if no updates
    sudo dnf install -y code
fi

log_info "Visual Studio Code installation complete"
