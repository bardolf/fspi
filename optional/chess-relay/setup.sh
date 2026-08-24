#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Expose Stockfish and Lc0 as UCI engines over TCP"

# Relay pro šachové GUI běžící jinde v síti (typicky na NASu). Každé TCP
# spojení dostane vlastní instanci enginu se stdin/stdout na socketu, takže
# klient mluví přímo UCI protokolem — žádná mezivrstva.
#
#   Stockfish  port 3456  (CPU)
#   Lc0        port 3457  (GPU, viz lc0-amd-setup.md)
#
# Přístup je omezený firewallem na jedinou adresu, viz ALLOWED_SOURCE níže.

ALLOWED_SOURCE="${CHESS_RELAY_SOURCE:-192.168.1.11}"
LC0_BIN=/home/milan/opt/lc0/build/rocm/lc0

# --- Stockfish z balíčku ---
ensure_package stockfish

# --- Lc0 se staví ručně, jen zkontrolovat ---
if [[ -x "$LC0_BIN" ]]; then
  log_debug "Lc0 binary present: $LC0_BIN"
else
  log_warn "Lc0 binary not found at $LC0_BIN"
  log_warn "  Build it first — see lc0-amd-setup.md in the project root."
  log_warn "  The lc0 socket will be installed but every connection will fail."
fi

# --- Relay skripty do /usr/local/bin ---
install_root_file() {
  local src="$1" dest="$2" mode="$3"
  if run_sudo cmp -s "$src" "$dest"; then
    log_debug "Already up-to-date: $dest"
  else
    log_info "Installing $dest"
    run_sudo install -m "$mode" -o root -g root "$src" "$dest"
  fi
}

install_root_file "$STEP_DIR/files/stockfish-relay" /usr/local/bin/stockfish-relay 755
install_root_file "$STEP_DIR/files/lc0-relay"       /usr/local/bin/lc0-relay       755

# --- Systemd units ---
UNITS=(stockfish.socket stockfish@.service lc0.socket lc0@.service)
units_changed=0
for unit in "${UNITS[@]}"; do
  if run_sudo cmp -s "$STEP_DIR/files/$unit" "/etc/systemd/system/$unit"; then
    log_debug "Unit already up-to-date: $unit"
  else
    log_info "Installing unit: $unit"
    run_sudo install -m 644 -o root -g root "$STEP_DIR/files/$unit" "/etc/systemd/system/$unit"
    units_changed=1
  fi
done

if [[ "$units_changed" -eq 1 ]]; then
  log_info "Reloading systemd"
  run_sudo systemctl daemon-reload
else
  log_debug "No unit changed, skipping daemon-reload"
fi

# --- Firewall: pustit dovnitř jen povolený zdroj ---
# Porty se nechávají zavřené pro zbytek sítě — otevírá je rich rule vázaná na
# konkrétní IP, ne plošné --add-port.
for port in 3456 3457; do
  rule="rule family=\"ipv4\" source address=\"$ALLOWED_SOURCE\" port port=\"$port\" protocol=\"tcp\" accept"
  if run_sudo firewall-cmd --permanent --query-rich-rule="$rule" >/dev/null 2>&1; then
    log_debug "Firewall rule already present for port $port"
  else
    log_info "Opening port $port for $ALLOWED_SOURCE"
    run_sudo firewall-cmd --permanent --add-rich-rule="$rule" >/dev/null
    run_sudo firewall-cmd --reload >/dev/null
  fi
done

# --- Aktivace socketů ---
# Socket se aktivuje na spojení, takže enginy nic nežerou, dokud se nikdo
# nepřipojí. Enable --now na už běžícím socketu je no-op.
for sock in stockfish.socket lc0.socket; do
  if [[ "$(systemctl is-enabled "$sock" 2>/dev/null)" == "enabled" ]] \
     && [[ "$(systemctl is-active "$sock" 2>/dev/null)" == "active" ]]; then
    log_debug "Socket already enabled and listening: $sock"
  else
    log_info "Enabling socket: $sock"
    run_sudo systemctl enable --now "$sock"
  fi
done

log_info "Chess relay setup complete"
log_info "  Listening:  ss -tlnp | grep -E '3456|3457'"
log_info "  Test local: printf 'uci\\nquit\\n' | nc 127.0.0.1 3456"
log_info "  Logs:       journalctl -u 'stockfish@*' -u 'lc0@*' -n 50"
log_info "  Allowed from: $ALLOWED_SOURCE (override with CHESS_RELAY_SOURCE=...)"
