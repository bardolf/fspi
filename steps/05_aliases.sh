#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Setting up command aliases"

ALIASES_FILE="$HOME/.aliases"

declare -A ALIASES=(
    ["teams"]="flatpak run com.github.IsmaelMartinez.teams_for_linux"
    ["wezterm"]="flatpak run org.wezfurlong.wezterm"
    ["spotify"]="flatpak run com.spotify.Client"
    ["zapzap"]="flatpak run com.rtosta.zapzap"
    ["whatsapp"]="flatpak run com.rtosta.zapzap"
    ["vivaldi"]="flatpak run com.vivaldi.Vivaldi"
)

mkdir -p "$(dirname "$ALIASES_FILE")"

# Ensure file exists
touch "$ALIASES_FILE"

# Add aliases if missing
for name in "${!ALIASES[@]}"; do
    cmd="${ALIASES[$name]}"
    if grep -q "alias $name=" "$ALIASES_FILE" 2>/dev/null; then
        log_debug "Alias already exists: $name"
    else
        log_info "Adding alias: $name -> $cmd"
        echo "alias $name='$cmd'" >> "$ALIASES_FILE"
    fi
done

# Ensure both bash and zsh source the aliases file
for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rcfile" ]]; then
        if ! grep -q "source ~/.aliases" "$rcfile"; then
            log_info "Ensuring aliases are sourced from $rcfile"
            echo -e "\n# Load custom aliases\n[ -f ~/.aliases ] && source ~/.aliases" >> "$rcfile"
        fi
    fi
done

log_info "Alias setup complete. Restart your shell or 'source ~/.aliases' to use them."

