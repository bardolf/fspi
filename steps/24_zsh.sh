#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 24: Installing and configuring Zsh with Oh-My-Zsh and plugins"

# -------------------------
# Ensure Zsh is installed
# -------------------------
ensure_package zsh

# -------------------------
# Install Oh-My-Zsh if not already
# -------------------------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  log_info "Installing Oh-My-Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
  log_info "Oh-My-Zsh already installed, skipping."
fi

ZSH="$HOME/.oh-my-zsh"
CUSTOM="$ZSH/custom"

# -------------------------
# Install required plugins
# -------------------------
install_plugin() {
  local name="$1"
  local url="$2"
  local dir="$CUSTOM/plugins/$name"
  if [[ ! -d "$dir" ]]; then
    log_info "Installing plugin $name"
    git clone --depth=1 "$url" "$dir"
  else
    log_info "Plugin $name already installed"
  fi
}

install_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
install_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git

# -------------------------
# Install other useful tools
# -------------------------
ensure_package fzf
ensure_package kubectl
ensure_package azure-cli

# -------------------------
# Deploy .zshrc from repo
# -------------------------
ZSHRC="$HOME/.zshrc"
ZSHRC_SRC="$SCRIPT_DIR/config/zsh/zshrc"

if [[ -f "$ZSHRC" ]] && ! cmp -s "$ZSHRC_SRC" "$ZSHRC"; then
  timestamp=$(date +%Y%m%d%H%M%S)
  backup="$ZSHRC.$timestamp.bak"
  log_info "Backing up existing $ZSHRC → $backup"
  cp "$ZSHRC" "$backup"
fi

log_info "Writing new .zshrc from $ZSHRC_SRC"
cp "$ZSHRC_SRC" "$ZSHRC"

# -------------------------
# Set Zsh as default shell
# -------------------------
CURRENT_SHELL=$(basename "$SHELL")
if [[ "$CURRENT_SHELL" != "zsh" ]]; then
  log_info "Changing default shell to Zsh"
  sudo chsh -s "$(which zsh)" "$USER"
fi

log_info "Zsh setup complete. Run 'source ~/.zshrc' or restart terminal."
