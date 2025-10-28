#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

# --- Variables ---
FONT_DIR="$HOME/.local/share/fonts/nerd-fonts"
TMP_DIR="$(mktemp -d)"
FONTS=(
    "CascadiaMono.zip"
    "Meslo.zip"
    "NerdFontsSymbolsOnly.zip"
)
# Seznam všech konkrétních TTF souborů, které chceme mít
TTF_FILES=(
    "CaskaydiaMonoNerdFont-BoldItalic.ttf"
    "CaskaydiaMonoNerdFont-Bold.ttf"
    "CaskaydiaMonoNerdFont-ExtraLightItalic.ttf"
    "CaskaydiaMonoNerdFont-ExtraLight.ttf"
    "CaskaydiaMonoNerdFont-Italic.ttf"
    "CaskaydiaMonoNerdFont-LightItalic.ttf"
    "CaskaydiaMonoNerdFont-Light.ttf"
    "CaskaydiaMonoNerdFont-Regular.ttf"
    "MesloLGLDZNerdFont-BoldItalic.ttf"
    "MesloLGLDZNerdFont-Bold.ttf"
    "MesloLGLDZNerdFont-Italic.ttf"
    "MesloLGLDZNerdFont-Regular.ttf"
    "SymbolsNerdFont-Regular.ttf"
    "SymbolsNerdFontMono-Regular.ttf"
)
BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0"

mkdir -p "$FONT_DIR"

# --- Check if all TTF files exist ---
all_fonts_exist=true
for ttf_file in "${TTF_FILES[@]}"; do
    if [[ ! -f "$FONT_DIR/$ttf_file" ]]; then
        all_fonts_exist=false
        break
    fi
done

if $all_fonts_exist; then
    log_info "All Nerd Fonts are already installed in $FONT_DIR, skipping download."
else
    log_info "Installing missing Nerd Fonts to $FONT_DIR"

    # --- Download and extract each font ZIP ---
    for font_zip in "${FONTS[@]}"; do
        ZIP_PATH="$TMP_DIR/$font_zip"
        FONT_NAME="${font_zip%.zip}"

        log_info "Downloading $font_zip..."
        wget -q --show-progress -O "$ZIP_PATH" "$BASE_URL/$font_zip"

        log_info "Extracting $font_zip..."
        unzip -q "$ZIP_PATH" -d "$TMP_DIR/$FONT_NAME"

        # Copy only missing TTF files
        for ttf_file in "$TMP_DIR/$FONT_NAME"/*.ttf; do
            ttf_filename=$(basename "$ttf_file")
            if [[ -f "$FONT_DIR/$ttf_filename" ]]; then
                log_debug "TTF $ttf_filename already installed, skipping"
            else
                log_info "Installing $ttf_filename"
                cp "$ttf_file" "$FONT_DIR/"
            fi
        done
    done
fi

# --- Refresh font cache ---
log_info "Refreshing font cache..."
fc-cache -fv "$FONT_DIR" >/dev/null

# --- Cleanup ---
rm -rf "$TMP_DIR"

log_info "Nerd Fonts installation complete"

