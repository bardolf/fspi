#!/usr/bin/env bash
# Install PlatformIO Core and its dependencies on Fedora
# This script is not part of the automatic installation process.
set -euo pipefail

echo "=== Installing PlatformIO system dependencies ==="
sudo dnf install -y \
    git curl python3 python3-pip python3-virtualenv

# === Install PlatformIO Core via official installer ===
PIO_HOME="$HOME/.platformio"
PIO_PENV="$PIO_HOME/penv/bin"
PIO_BIN="$PIO_PENV/pio"
if [[ -x "$PIO_BIN" ]]; then
    echo "PlatformIO already installed: $("$PIO_BIN" --version 2>/dev/null || echo unknown)"
else
    echo "=== Installing PlatformIO Core (headless) ==="
    TMP_INSTALLER=$(mktemp --suffix=.py)
    trap 'rm -f "$TMP_INSTALLER"' EXIT
    curl -fsSL https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py \
        -o "$TMP_INSTALLER"
    python3 "$TMP_INSTALLER"
fi

# === Symlink pio into ~/.local/bin (already on PATH) ===
mkdir -p "$HOME/.local/bin"
for cmd in pio platformio piodebuggdb; do
    if [[ -x "$PIO_PENV/$cmd" ]]; then
        ln -sf "$PIO_PENV/$cmd" "$HOME/.local/bin/$cmd"
    fi
done

# === Install PlatformIO udev rules for serial device access ===
UDEV_RULES="/etc/udev/rules.d/99-platformio-udev.rules"
if [[ ! -f "$UDEV_RULES" ]]; then
    echo "=== Installing PlatformIO udev rules ==="
    sudo curl -fsSL \
        https://raw.githubusercontent.com/platformio/platformio-core/develop/platformio/assets/system/99-platformio-udev.rules \
        -o "$UDEV_RULES"
    sudo udevadm control --reload-rules
    sudo udevadm trigger
else
    echo "udev rules already present: $UDEV_RULES"
fi

# === Ensure user is in dialout group for serial access ===
if id -nG "$USER" | grep -qw dialout; then
    echo "$USER already in dialout group"
else
    echo "=== Adding $USER to dialout group (re-login required) ==="
    sudo usermod -aG dialout "$USER"
fi

echo "=== Done. PlatformIO installed under $PIO_HOME ==="
echo "    CLI: $PIO_BIN (symlinked into ~/.local/bin)"
echo "    Verify: pio --version   (open a new shell if PATH isn't refreshed)"
