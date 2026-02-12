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
ensure_package autojump
ensure_package fzf
ensure_package kubectl
ensure_package azure-cli

# -------------------------
# Backup existing .zshrc
# -------------------------
ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  timestamp=$(date +%Y%m%d%H%M%S)
  backup="$ZSHRC.$timestamp.bak"
  log_info "Backing up existing $ZSHRC → $backup"
  cp "$ZSHRC" "$backup"
fi

# -------------------------
# Create new .zshrc
# -------------------------
log_info "Writing new .zshrc"

cat >"$ZSHRC" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
export EDITOR=nvim
ZSH_THEME="robbyrussell"

plugins=(
  git
  zsh-syntax-highlighting
  zsh-autosuggestions
  z
  azure
  dnf
  kubectl
  fzf
  autojump
)

source $ZSH/oh-my-zsh.sh

# Optional: make suggestions visible
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# History
HISTSIZE=500000
SAVEHIST=500000

# Custom aliases
alias k=kubectl
alias open='xdg-open'
eval "$(/home/milan/.local/bin/mise activate bash)"
EOF

# -------------------------
# Set Zsh as default shell
# -------------------------
CURRENT_SHELL=$(basename "$SHELL")
if [[ "$CURRENT_SHELL" != "zsh" ]]; then
  log_info "Changing default shell to Zsh"
  sudo chsh -s "$(which zsh)" "$USER"
fi

log_info "Zsh setup complete. Run 'source ~/.zshrc' or restart terminal."
