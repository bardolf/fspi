#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# IntelliJ IDEA Ultimate z oficiálního tar.gz od JetBrains. Layout:
#
#   ~/opt/idea/idea/     rozbalený release — na bin/idea míří files/desktop/idea.desktop,
#                        na bin/idea.sh difftool/mergetool v config/git/gitconfig
#   ~/.local/bin/idea -> ~/opt/idea/idea/bin/idea   (spouštění z terminálu)
#
# Step instaluje jen tehdy, když IDEA chybí. Aktualizace dělá IDE samo
# (Help → Check for Updates; adresář patří uživateli, takže patchuje na místě),
# aby install.sh při každé nové verzi netahal 1.6 GB a nepral se s updaterem.
# Licence: přihlášení k JetBrains Account při prvním spuštění, ručně.

IDEA_API="https://data.services.jetbrains.com/products/releases?code=IIU&latest=true&type=release"
IDEA_BASE="$HOME/opt/idea"
IDEA_HOME="$IDEA_BASE/idea"

log_info "Step 19e: IntelliJ IDEA Ultimate"

ensure_package jq

installed_version() {
  jq -r '"\(.version) (\(.buildNumber))"' "$IDEA_HOME/product-info.json" 2>/dev/null || echo "unknown version"
}

if [[ -x "$IDEA_HOME/bin/idea" ]]; then
  log_debug "IntelliJ IDEA $(installed_version) already installed, skipping download"
else
  # Něco tam je, ale ne funkční IDEA — nemazat naslepo
  if [[ -e "$IDEA_HOME" || -L "$IDEA_HOME" ]]; then
    log_error "$IDEA_HOME exists but has no bin/idea; move it aside and re-run"
    exit 1
  fi

  # Stahuje se do ~/opt/idea, ne do /tmp (tmpfs = RAM, archiv má 1.6 GB a rozbalený ~4 GB)
  mkdir -p "$IDEA_BASE"
  tmp=$(mktemp -d "$IDEA_BASE/.install.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT

  if ! curl -fsSL "$IDEA_API" -o "$tmp/release.json"; then
    log_error "Could not reach the JetBrains release API ($IDEA_API)"
    exit 1
  fi

  version=$(jq -r '.IIU[0].version // empty' "$tmp/release.json")
  url=$(jq -r '.IIU[0].downloads.linux.link // empty' "$tmp/release.json")
  sha_url=$(jq -r '.IIU[0].downloads.linux.checksumLink // empty' "$tmp/release.json")
  size=$(jq -r '.IIU[0].downloads.linux.size // 0' "$tmp/release.json")

  if [[ -z "$version" || -z "$url" || -z "$sha_url" ]]; then
    log_error "No Linux download found in the JetBrains release API response"
    exit 1
  fi

  log_info "Downloading IntelliJ IDEA $version ($(numfmt --to=iec "$size"))"
  curl -fSL --progress-bar "$url" -o "$tmp/idea.tar.gz"

  expected=$(curl -fsSL "$sha_url" | cut -d' ' -f1)
  actual=$(sha256sum "$tmp/idea.tar.gz" | cut -d' ' -f1)
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    log_error "SHA-256 mismatch for $(basename "$url") (expected '$expected', got '$actual')"
    exit 1
  fi
  log_debug "SHA-256 OK: $actual"

  log_info "Unpacking to $IDEA_HOME"
  mkdir -p "$tmp/unpacked"
  tar -xzf "$tmp/idea.tar.gz" -C "$tmp/unpacked"

  # idea-2026.3.tar.gz -> idea-IU-263.7307.200/
  unpacked=$(find "$tmp/unpacked" -mindepth 1 -maxdepth 1 -type d -name 'idea-*' | head -1)
  if [[ -z "$unpacked" || ! -x "$unpacked/bin/idea" ]]; then
    log_error "Unexpected archive layout: no idea-*/bin/idea inside $(basename "$url")"
    exit 1
  fi
  mv "$unpacked" "$IDEA_HOME"
  log_info "IntelliJ IDEA $(installed_version) installed to $IDEA_HOME"
fi

ensure_symlink "$IDEA_HOME/bin/idea" "$HOME/.local/bin/idea"

# Dřívější alias z 05_aliases spouštěl flatpak a zastínil by ~/.local/bin/idea
if grep -q "^alias idea='flatpak run " "$HOME/.aliases" 2>/dev/null; then
  log_info "Removing stale flatpak 'idea' alias from ~/.aliases"
  sed -i "/^alias idea='flatpak run /d" "$HOME/.aliases"
fi

log_info "Step 19e done"
