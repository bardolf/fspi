#!/usr/bin/env bash
# optional: fingerprint unlock for swaylock (password first, empty Enter = finger); fingers enrolled by hand
# installed: grep -q pam_fprintd /etc/pam.d/swaylock
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Fingerprint unlock for swaylock"

# Postup a hlavně proč takhle (heslo první, prst na prázdný Enter, authselect
# with-fingerprint vypnutý): fingerprint-swaylock-setup.md v kořeni repa.
# Otisky se ukládají ručně (fprintd-enroll) — senzoru se musí dotknout prst.
# Ověřeno: Goodix 27c6:6594 (ThinkPad), Synaptics 06cb:00f9 (P14s Gen 6 AMD).

ensure_package fprintd
ensure_package fprintd-pam

# --- Čtečka: bez ní nemá smysl PAM měnit ---
if fprintd-list "$USER" 2>/dev/null | grep -q '^found [1-9]'; then
  log_debug "fprintd sees a fingerprint reader"
else
  log_error "fprintd found no fingerprint reader on this machine (lsusb, libfprint support?)"
  exit 1
fi

# --- PAM pro swaylock (swaylock-effects používá stejnou PAM službu) ---
PAM_SRC="$STEP_DIR/files/swaylock.pam"
PAM_DEST=/etc/pam.d/swaylock
if cmp -s "$PAM_SRC" "$PAM_DEST"; then
  log_debug "PAM config already up-to-date: $PAM_DEST"
else
  log_info "Installing $PAM_DEST (password first, fingerprint on empty Enter)"
  run_sudo install -m 644 -o root -g root "$PAM_SRC" "$PAM_DEST"
fi

# --- authselect with-fingerprint dává prst před heslo všude → vypnout ---
if authselect current 2>/dev/null | grep -qx -- '- with-fingerprint'; then
  log_info "Disabling authselect feature with-fingerprint (it blocks password entry on the sensor)"
  run_sudo authselect disable-feature with-fingerprint
else
  log_debug "authselect with-fingerprint already disabled"
fi

# --- Otisky ---
enrolled=$(fprintd-list "$USER" 2>/dev/null | grep -c ' - #' || true)
if ((enrolled > 0)); then
  log_info "Fingerprints enrolled for $USER: $enrolled"
else
  log_warn "No fingerprints enrolled yet. Run (touch the sensor repeatedly):"
  log_warn "  fprintd-enroll -f right-index-finger"
  log_warn "  fprintd-verify"
fi

log_info "Optional fingerprint setup complete"
log_info "  Test:  lock (Mod+L), press Enter with an empty password, touch the sensor"
