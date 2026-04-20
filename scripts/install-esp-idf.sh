#!/usr/bin/env bash
# Install ESP-IDF and its dependencies on Fedora
# This script is not part of the automatic installation process.
set -euo pipefail

echo "=== Installing ESP-IDF system dependencies ==="
sudo dnf install -y \
    git wget flex bison gperf ccache dfu-util \
    libffi-devel openssl-devel \
    libusb1 libgcrypt glib2 pixman SDL2 libslirp \
    python3 python3-pip

# === Install eim (ESP-IDF Installation Manager) CLI ===
if command -v eim >/dev/null 2>&1; then
    echo "eim already installed: $(eim --version 2>/dev/null || echo unknown)"
else
    echo "=== Installing eim CLI from Espressif RPM ==="
    EIM_TAG=$(curl -fsSL https://api.github.com/repos/espressif/idf-im-ui/releases/latest \
              | grep -oP '"tag_name":\s*"\K[^"]+')
    EIM_RPM_URL="https://github.com/espressif/idf-im-ui/releases/download/${EIM_TAG}/eim-cli-linux-x64.rpm"
    echo "Installing ${EIM_RPM_URL}"
    sudo dnf install -y "$EIM_RPM_URL"
fi

# === Install ESP-IDF (latest stable) via eim ===
EIM_BASE="$HOME/.espressif"
if compgen -G "$EIM_BASE/v*/activate.sh" > /dev/null 2>&1 \
   || compgen -G "$EIM_BASE/esp-idf-*/export.sh" > /dev/null 2>&1; then
    echo "ESP-IDF already installed under $EIM_BASE — skipping eim install"
else
    echo "=== Installing ESP-IDF via eim (latest stable, headless) ==="
    eim install --cleanup true
fi

echo "=== Done. Activate ESP-IDF with the export/activate script under $EIM_BASE ==="
