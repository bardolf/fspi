#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Starting full LazyVim setup..."

# --- Preconditions: install required packages ---
REQUIRED_PACKAGES=(neovim git nodejs npm ripgrep fd-find unzip curl rust cargo)
MISSING_PACKAGES=()

log_info "Checking required packages..."
for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! command -v "$pkg" &>/dev/null; then
    MISSING_PACKAGES+=("$pkg")
  fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
  log_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
  sudo dnf install -y "${MISSING_PACKAGES[@]}"
else
  log_debug "All required packages are already installed"
fi

# --- Prepare Neovim config directories ---
NVIM_CONFIG_DIR="$HOME/.config/nvim"
NVIM_DATA_DIR="$HOME/.local/share/nvim"

# --- Clone LazyVim starter config ---
STARTER_REPO="https://github.com/LazyVim/starter.git"
if [[ ! -d "$NVIM_CONFIG_DIR" ]]; then
  log_info "Cloning LazyVim starter config..."
  git clone --depth 1 "$STARTER_REPO" "$NVIM_CONFIG_DIR"
else
  if [[ -d "$NVIM_CONFIG_DIR/.git" ]]; then
    log_info "LazyVim starter already cloned, pulling latest changes..."
    git -C "$NVIM_CONFIG_DIR" pull --ff-only || log_warn "Failed to pull latest changes"
  else
    log_warn "$NVIM_CONFIG_DIR already exists and is not a git repo, skipping clone"
  fi
fi

# --- Symlink init.lua if missing ---
if [[ ! -f "$NVIM_CONFIG_DIR/init.lua" ]]; then
  log_info "Setting up init.lua for LazyVim..."
  cp "$NVIM_CONFIG_DIR/init.lua.example" "$NVIM_CONFIG_DIR/init.lua" 2>/dev/null || true
fi

# --- Ensure Node.js tooling is on PATH ---
export PATH="$HOME/.local/bin:$PATH"

# --- Install LazyVim plugins, Treesitter & LSP (headless) ---
log_info "Installing LazyVim plugins, Treesitter parsers, and LSP..."
nvim --headless "+Lazy! sync" "+TSUpdate" "+qa" >/dev/null 2>&1 || log_warn "Some plugin setup steps failed (safe to ignore)"

# --- Optional: install additional Neovim tooling (null-ls, formatter) ---
if ! command -v stylua &>/dev/null; then
  log_info "Installing stylua for Lua formatting..."
  if cargo install stylua >/dev/null 2>&1; then
    log_debug "stylua installed successfully."
  else
    log_warn "Failed to install stylua or already installed."
  fi
fi

# --- Setup convenient alias ---
SHELL_RC="$HOME/.bashrc"
if ! grep -q "alias nvim='nvim'" "$SHELL_RC"; then
  log_info "Adding alias 'nvim' to $SHELL_RC"
  echo "alias nvim='nvim'" >>"$SHELL_RC"
fi

log_info "Full LazyVim setup completed successfully!"
