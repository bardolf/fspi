#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: CETIN office printer (SMB) -> CUPS queue 'cetin'"

# --- Config ---
# The server is reachable only over the CETIN VPN (scripts/vpn-cetin.sh adds the
# ad.cetin search domain). Driver is the generic PostScript PPD; the printer is
# a PostScript queue on the AD print server.
QUEUE=cetin
SERVER=printer.ad.cetin            # -> 172.29.132.18, SMB 139/445
SHARE=printer
PPD='drv:///sample.drv/generic.ppd'   # "Generic PostScript Printer"
CRED=/etc/cetin-printer.cred
DEFAULT_USER='mi077548@cetin.cz'   # verified working UPN (sAMAccountName works too)

# --- Packages: CUPS scheduler + the SMB backend (shipped by samba-client) ---
ensure_package cups
ensure_package samba-client        # provides /usr/lib/cups/backend/smb

if systemctl is-active --quiet cups; then
  log_debug "cups already running"
else
  log_info "Starting cups"
  run_sudo systemctl start cups
fi

# --- Credentials (password NOT in the repo; lives in this 0600 root file) ---
# We bake the credentials into the CUPS device URI so jobs print straight through
# instead of being held for an interactive "authenticate" prompt. CUPS has no
# separate credentials-file mechanism for the smb backend, so the secret ends up
# in /etc/cups/printers.conf (root-readable) — same trust level as $CRED.
if run_sudo test -f "$CRED"; then
  log_debug "Credentials file present: $CRED"
else
  log_info "Installing credentials template: $CRED"
  run_sudo install -m 600 -o root -g root "$STEP_DIR/files/cetin-printer.cred.example" "$CRED"
fi

cred_get() { run_sudo grep -E "^$1=" "$CRED" 2>/dev/null | head -1 | cut -d= -f2-; }
USERNAME=$(cred_get username); USERNAME=${USERNAME:-$DEFAULT_USER}
PASSWORD=$(cred_get password)

persist_cred() {
  printf '%s\n' \
    "# CETIN office printer SMB credentials (managed by optional/printer-cetin/setup.sh)." \
    "# Keep this file 0600, owned by root. Password = your CETIN AD password (Bitwarden)." \
    "username=$USERNAME" \
    "password=$PASSWORD" | run_sudo tee "$CRED" >/dev/null
  run_sudo chmod 600 "$CRED"
}

# Offer to fill a blank password interactively (and remember it for next time).
if [[ -z "$PASSWORD" && -t 0 ]]; then
  log_info "No password in $CRED yet."
  read -rsp "  Enter AD password for $USERNAME (blank to skip): " PASSWORD; echo
  [[ -n "$PASSWORD" ]] && persist_cred
fi

# --- Build the device URI ---
if [[ -n "$PASSWORD" ]]; then
  # Embed URL-encoded creds -> no per-job auth. UPN '@' becomes %40.
  enc() { VAL="$1" python3 -c 'import os,urllib.parse;print(urllib.parse.quote(os.environ["VAL"],safe=""))'; }
  URI="smb://$(enc "$USERNAME"):$(enc "$PASSWORD")@${SERVER}/${SHARE}"
  AUTH=none
else
  # No password -> fall back to per-job authentication (system-config-printer ->
  # right-click held job -> Authenticate, with $USERNAME + AD password).
  URI="smb://AD/${SERVER}/${SHARE}"
  AUTH='username,password'
  log_warn "No password set in $CRED -> print jobs will be HELD for authentication."
  log_warn "  Fill it (sudoedit $CRED) and re-run, or authenticate each job manually."
fi

# --- Create / refresh the queue (idempotent: lpadmin -p just resets attrs) ---
if lpstat -p "$QUEUE" >/dev/null 2>&1; then
  log_debug "Refreshing existing queue '$QUEUE' (auth=$AUTH)"
  run_sudo lpadmin -p "$QUEUE" -v "$URI" -o auth-info-required="$AUTH"
else
  log_info "Creating queue '$QUEUE' (auth=$AUTH)"
  run_sudo lpadmin -p "$QUEUE" -v "$URI" -m "$PPD" \
    -o auth-info-required="$AUTH" -o printer-is-shared=false -E
fi

# With baked creds, drop any jobs left held by a previous per-job-auth config.
if [[ "$AUTH" == none ]]; then
  cancel -a "$QUEUE" 2>/dev/null || true
fi

# --- Sanity hint: is the print server even reachable right now? ---
if getent hosts "$SERVER" >/dev/null 2>&1; then
  log_debug "$SERVER resolves"
else
  log_warn "$SERVER does not resolve — is the CETIN VPN up? (scripts/vpn-cetin.sh)"
fi

log_info "CETIN printer setup complete (queue: $QUEUE)"
if [[ "$AUTH" == none ]]; then
  log_info "  Print:   lp -d $QUEUE file.pdf      (no auth prompt; needs the CETIN VPN up)"
else
  log_info "  Finish:  sudoedit $CRED   (paste AD password from Bitwarden), then re-run"
fi
log_info "  Remove:  sudo lpadmin -x $QUEUE   (and: sudo rm -f $CRED)"
