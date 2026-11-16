#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Install CETIN corporate CA certificates into the system trust store.
# Runs before 01_repos so TLS-inspecting corporate networks don't break dnf.
# Only the CETIN CAs belong in anchors/ (root + sub CA 23, and the old root
# "CA CETIN" valid till 2035 that makalu's README also imports into JDKs) —
# the bundled complete-with-defaults.crt is the full system bundle and is
# intentionally not shipped here. scripts/jdk-cetin-certs.sh copies whatever
# lands in anchors/ into the mise JDKs (step 19d + mise postinstall hook).

CERT_SRC="$SCRIPT_DIR/files/certs"
ANCHOR_DIR="/etc/pki/ca-trust/source/anchors"

changed=false
for cert in "$CERT_SRC"/*.crt; do
  [[ -f "$cert" ]] || continue
  dest="$ANCHOR_DIR/$(basename "$cert")"
  if sudo cmp -s "$cert" "$dest" 2>/dev/null; then
    log_debug "CA cert already up-to-date: $dest"
  else
    log_info "Installing CA cert: $(basename "$cert")"
    sudo install -m 0644 "$cert" "$dest"
    changed=true
  fi
done

if $changed; then
  log_info "Rebuilding system trust store (update-ca-trust)"
  sudo update-ca-trust
else
  log_debug "CETIN CA certs already trusted, skipping update-ca-trust"
fi
