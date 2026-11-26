#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

# Založí virtuálku s Windows 11 pro VMware Workstation (napřed setup.sh) a
# připraví bezobslužnou instalaci: unattend.iso s autounattend.xml +
# vm-setup.ps1 (VMware Tools, Autodesk Fusion). Windows ISO se stahuje ručně
# od Microsoftu. Existující virtuálku nikdy nepřepisuje.
#
#   bash optional/vmware/new-win11-vm.sh [path/to/Win11.iso]
#
# Proměnné: VM_DIR (~/vmware/win11), SHARED_DIR (~/vmware/shared),
# VM_MEM_MB (12288), VM_CPUS (8), DISK_SIZE (128GB, roste podle potřeby).

VM_DIR="${VM_DIR:-$HOME/vmware/win11}"
SHARED_DIR="${SHARED_DIR:-$HOME/vmware/shared}"
VM_MEM_MB="${VM_MEM_MB:-12288}"
VM_CPUS="${VM_CPUS:-8}"
DISK_SIZE="${DISK_SIZE:-128GB}"

log_info "Windows 11 VM for VMware Workstation: $VM_DIR"

ensure_command vmware-vdiskmanager
ensure_package xorriso

if [[ -e "$VM_DIR/win11.vmx" ]]; then
  log_info "VM already exists, not touching it: $VM_DIR/win11.vmx"
  exit 0
fi

iso="${1:-}"
if [[ -z "$iso" ]]; then
  iso=$(find "$HOME/Downloads" -maxdepth 1 -iname 'win*11*.iso' -printf '%T@ %p\n' |
    sort -nr | head -1 | cut -d' ' -f2-)
fi
if [[ -z "$iso" || ! -f "$iso" ]]; then
  log_error "No Windows 11 ISO given and none (Win*11*.iso) in ~/Downloads"
  log_error "Get it: https://www.microsoft.com/software-download/windows11"
  log_error "  → Windows 11 (multi-edition ISO for x64 devices), English"
  exit 1
fi
iso=$(realpath "$iso")
log_info "Windows ISO: $iso"

mkdir -p "$VM_DIR" "$SHARED_DIR"

# --- btrfs: bez copy-on-write ---
# Obraz disku i .vmem (paměť hosta, viz vmware-win11-setup.md) se přepisují
# na místě; s CoW + zstd kompresí se soubor rozdrobí a každý zápis jde přes
# kompresi. +C na prázdném adresáři zdědí každý nový soubor; na existující
# data už nepůsobí, proto před vytvořením disku.
if [[ "$(stat -f -c %T "$VM_DIR")" == btrfs ]]; then
  if lsattr -d "$VM_DIR" | cut -d' ' -f1 | grep -q C; then
    log_debug "NOCOW already set on $VM_DIR"
  elif [[ -n "$(ls -A "$VM_DIR")" ]]; then
    log_warn "$VM_DIR is not empty, NOCOW would not reach existing files — leaving it"
  else
    log_info "btrfs: disabling copy-on-write for $VM_DIR"
    chattr +C "$VM_DIR"
  fi
fi

# --- unattend.iso ---
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed "s/@USER@/$USER/g" "$STEP_DIR/files/autounattend.xml" >"$work/autounattend.xml"
cp "$STEP_DIR/files/vm-setup.ps1" "$work/"
log_info "Building $VM_DIR/unattend.iso"
xorriso -as mkisofs -quiet -J -R -V UNATTEND -o "$VM_DIR/unattend.iso" "$work"

# --- Disk ---
if [[ -f "$VM_DIR/win11.vmdk" ]]; then
  log_debug "Disk already exists: $VM_DIR/win11.vmdk"
else
  log_info "Creating $DISK_SIZE growable disk: $VM_DIR/win11.vmdk"
  vmware-vdiskmanager -c -s "$DISK_SIZE" -a lsilogic -t 0 "$VM_DIR/win11.vmdk"
fi

# --- .vmx ---
sed -e "s|@WINDOWS_ISO@|$iso|" \
  -e "s|@SHARED_DIR@|$SHARED_DIR|" \
  -e "s|@MEMSIZE@|$VM_MEM_MB|" \
  -e "s|@VCPUS@|$VM_CPUS|g" \
  "$STEP_DIR/files/win11.vmx" >"$VM_DIR/win11.vmx"
log_info "Created $VM_DIR/win11.vmx ($VM_CPUS vCPU, $VM_MEM_MB MB RAM, 3D on)"

log_info "Next: vmware $VM_DIR/win11.vmx → Power on, click into the VM and press a key"
log_info "  at 'Press any key to boot from CD or DVD…' (~5 s). The rest runs on its own:"
log_info "  Windows (~20 min), then VMware Tools + Fusion and a reboot (~15 min)."
# Bez zpětných lomítek: log_info je vypisuje přes echo -e.
log_info "  Guest log: C:/Windows/Temp/vm-setup.log; $SHARED_DIR = vmware-host/Shared Folders/shared"
