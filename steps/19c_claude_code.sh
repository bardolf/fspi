#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Claude Code přes oficiální nativní instalátor (claude.ai/install.sh). Stáhne
# binárku do ~/.local/share/claude/versions/<verze> a ~/.local/bin/claude na ni
# ukazuje (~/.local/bin je na PATH přes zshrc). Dál se aktualizuje sám, takže
# step jen doinstaluje, když chybí — re-run nic nepřepisuje ani neupgraduje.
#
# Instalátor se nesmí pouštět přes sudo (sám to odmítne), všechno jde do $HOME.
# Stahuje se nejdřív do souboru, ne `curl | bash`, ať se při přerušeném
# stahování nespustí půlka skriptu.

CLAUDE_BIN="$HOME/.local/bin/claude"
INSTALLER_URL="https://claude.ai/install.sh"

log_info "Step 19c: Installing Claude Code (native installer)"

# -x jde přes symlink na cíl, takže rozbitý odkaz (smazaná verze) se reinstaluje.
if [[ -x "$CLAUDE_BIN" ]]; then
  log_debug "Claude Code already installed at $CLAUDE_BIN, skipping"
else
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  log_info "Downloading $INSTALLER_URL"
  curl -fsSL "$INSTALLER_URL" -o "$tmp/install.sh"
  bash "$tmp/install.sh"

  if [[ ! -x "$CLAUDE_BIN" ]]; then
    log_error "Installer finished but $CLAUDE_BIN is missing"
    exit 1
  fi
  log_info "Claude Code installed: $("$CLAUDE_BIN" --version)"
fi

# --- Status line ---
# Skript nasazuje step 30 do ~/scripts; tady se jen zapojí do settings.json.
# Soubor nekopírujeme celý — Claude si do něj sám zapisuje (model, theme,
# effort přes /config), takže se mění jen klíč statusLine a zbytek zůstane.
# Odkaz na ~/scripts dřív, než tam skript je, nevadí: řeší se až při běhu.
SETTINGS="$HOME/.claude/settings.json"
# shellcheck disable=SC2088 # tildu rozvine až shell, kterým Claude příkaz pouští
STATUS_CMD="~/scripts/claude-status-line-command.sh"

ensure_command jq
mkdir -p "$(dirname "$SETTINGS")"
[[ -s "$SETTINGS" ]] || echo '{}' >"$SETTINGS"

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  # Rozbitý JSON nepřepisovat — byl by to tichý konec všech ostatních nastavení.
  log_warn "$SETTINGS is not valid JSON, status line not configured"
elif [[ "$(jq -r '.statusLine.command // empty' "$SETTINGS")" == "$STATUS_CMD" ]]; then
  log_debug "Claude status line already configured, skipping"
else
  log_info "Configuring Claude status line → $STATUS_CMD"
  tmp_settings="$(mktemp "$SETTINGS.XXXXXX")"
  jq --arg cmd "$STATUS_CMD" '.statusLine = {type: "command", command: $cmd}' \
    "$SETTINGS" >"$tmp_settings"
  chmod --reference="$SETTINGS" "$tmp_settings"
  mv "$tmp_settings" "$SETTINGS"
fi

log_info "Step 19c done (login on first run: claude)"
