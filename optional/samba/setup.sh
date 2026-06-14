#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Mount CIFS/Samba shares from //192.168.1.11 via /etc/fstab"

# cifs-utils provides the mount.cifs helper the kernel needs.
ensure_package cifs-utils

# --- Mount points ---
# x-systemd.automount needs the target directories to exist up front.
# Keep this list in sync with files/fstab-cifs.block.
MOUNT_POINTS=(/media/nas /media/disks/disk1 /media/disks/disk2 /media/disks/disk3)
for mp in "${MOUNT_POINTS[@]}"; do
  if [[ -d "$mp" ]]; then
    log_debug "Mount point already exists: $mp"
  else
    log_info "Creating mount point: $mp"
    run_sudo mkdir -p "$mp"
  fi
done

# --- Credential files (passwords NOT in the repo, they live in Bitwarden) ---
# Deploy the templates only when the target is absent so we never clobber a
# filled-in password on a re-run.
CRED_DIR=/etc/cifs-credentials
run_sudo install -d -m 700 -o root -g root "$CRED_DIR"

ensure_cred() {
  local src="$1" dest="$2"
  if run_sudo test -f "$dest"; then
    log_debug "Credentials file already present: $dest"
  else
    log_info "Installing credentials template: $dest"
    run_sudo install -m 600 -o root -g root "$src" "$dest"
  fi
  # Warn (don't fail) while the password is still blank.
  if ! run_sudo grep -Eq '^password=.+' "$dest"; then
    log_warn "Password not set in $dest"
    log_warn "  Paste it from Bitwarden (search \"NAS 192.168.1.11\"), keep file 0600 root-only."
  fi
}

ensure_cred "$STEP_DIR/files/nas.cred.example" "$CRED_DIR/nas.cred"

# --- /etc/fstab managed block ---
# We own a marker-delimited block in /etc/fstab and rewrite only that block,
# leaving the rest of the file untouched. Idempotent: re-running with an
# unchanged block file is a no-op.
FSTAB=/etc/fstab
MARKER_BEGIN="# >>> fspi samba cifs mounts >>>"
MARKER_END="# <<< fspi samba cifs mounts <<<"
BLOCK_SRC="$STEP_DIR/files/fstab-cifs.block"

# One-time backup before we ever touch fstab.
if run_sudo test -f "${FSTAB}.fspi-backup"; then
  log_debug "fstab backup already exists: ${FSTAB}.fspi-backup"
else
  log_info "Backing up $FSTAB -> ${FSTAB}.fspi-backup"
  run_sudo cp -a "$FSTAB" "${FSTAB}.fspi-backup"
fi

# Strip any existing managed block; $() drops trailing blank lines for us.
base=$(awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}
' "$FSTAB")
block=$(cat "$BLOCK_SRC")
desired=$(printf '%s\n\n%s\n%s\n%s\n' "$base" "$MARKER_BEGIN" "$block" "$MARKER_END")

if [[ "$desired" == "$(cat "$FSTAB")" ]]; then
  log_debug "fstab CIFS block already up-to-date"
else
  log_info "Writing managed CIFS block into $FSTAB"
  printf '%s\n' "$desired" | run_sudo tee "$FSTAB" >/dev/null
  run_sudo chmod 644 "$FSTAB"
  run_sudo chown root:root "$FSTAB"
fi

# --- Activate the automount units now ---
# daemon-reload (and every boot) only *generates* the .automount units from
# fstab; they stay inactive until started, so without this a fresh `ls` on a
# mount point would silently do nothing until the next reboot. Starting an
# already-active automount unit is a harmless no-op, so this is idempotent.
run_sudo systemctl daemon-reload
automount_units=()
for mp in "${MOUNT_POINTS[@]}"; do
  automount_units+=("$(systemd-escape -p --suffix=automount "$mp")")
done
log_info "Activating automount units: ${automount_units[*]}"
run_sudo systemctl start "${automount_units[@]}"

log_info "Optional Samba/CIFS mount setup complete"
log_info "  Fill password:   sudoedit $CRED_DIR/nas.cred  (from Bitwarden)"
log_info "  Test a share:    ls /media/nas   (automount mounts it on first access)"
log_info "  Inspect:         findmnt /media/nas ; systemctl list-units 'media-*.automount'"
