#!/usr/bin/env bash
# optional: VMware Workstation Pro from the bundle in ~/Downloads + kernel modules (Windows VM: new-win11-vm.sh)
# installed: test -x /usr/bin/vmware
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: VMware Workstation Pro"

# Proč VMware a ne KVM/Wine, pasti a ladění: vmware-win11-setup.md v kořeni
# repa. Virtuálku s Windows 11 zakládá zvlášť new-win11-vm.sh — tady je jen
# hostitel. Znovu spustit po každé aktualizaci jádra: přeloží vmmon/vmnet.

# --- Překlad jaderných modulů ---
PACKAGES=(
  gcc
  make
  elfutils-libelf-devel
)

for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

# kernel-devel pro BĚŽÍCÍ jádro. Mimo ensure_package: `rpm -q --whatprovides`
# plné NVRA nezná, takže by dnf volal při každém běhu. Po aktualizaci jádra
# bez rebootu už tahle verze v repu být nemusí — pak napřed reboot.
KERNEL_DEVEL="kernel-devel-$(uname -r)"
if rpm -q "$KERNEL_DEVEL" &>/dev/null; then
  log_debug "Package already installed: $KERNEL_DEVEL"
else
  log_info "Installing package: $KERNEL_DEVEL"
  run_sudo dnf install -y "$KERNEL_DEVEL"
fi

# --- VMware Workstation ---
# Zdarma i komerčně, ale bundle je jen za přihlášením na portálu
# Broadcomu — stáhnout ručně, skript ho jen najde v ~/Downloads.
if check_command vmware; then
  log_debug "VMware Workstation already installed: $(vmware --version 2>/dev/null)"
else
  bundle=$(find "$HOME/Downloads" -maxdepth 1 -name 'VMware-Workstation-Full-*.x86_64.bundle' -printf '%T@ %p\n' |
    sort -nr | head -1 | cut -d' ' -f2-)
  if [[ -z "$bundle" ]]; then
    log_error "No VMware-Workstation-Full-*.x86_64.bundle in ~/Downloads"
    log_error "Get it (Broadcom login): https://support.broadcom.com/group/ecx/free-downloads"
    log_error "  → VMware Workstation Pro → … for Linux, then re-run this script"
    exit 1
  fi
  log_info "Installing $(basename "$bundle") (EULA accepted on the command line)"
  run_sudo sh "$bundle" --console --required --eulas-agreed
fi

# --- vmmon / vmnet pro běžící jádro ---
kernel=$(uname -r)
if modinfo -k "$kernel" vmmon &>/dev/null && modinfo -k "$kernel" vmnet &>/dev/null; then
  log_debug "vmmon/vmnet already built for $kernel"
else
  log_info "Building vmmon/vmnet for kernel $kernel"
  run_sudo vmware-modconfig --console --install-all
fi

for unit in vmware.service vmware-USBArbitrator.service; do
  if systemctl is-enabled --quiet "$unit" && systemctl is-active --quiet "$unit"; then
    log_debug "$unit already enabled and running"
  else
    log_info "Enabling and starting $unit"
    run_sudo systemctl enable --now "$unit"
  fi
done

# --- KVM nesmí držet virtualizaci ---
KVM_CONF_SRC="$STEP_DIR/files/kvm-virt-on-demand.conf"
KVM_CONF_DEST=/etc/modprobe.d/kvm-virt-on-demand.conf

if cmp -s "$KVM_CONF_SRC" "$KVM_CONF_DEST" 2>/dev/null; then
  log_debug "KVM on-demand virtualization already configured: $KVM_CONF_DEST"
else
  log_info "KVM: enable virtualization only while a KVM guest runs: $KVM_CONF_DEST"
  run_sudo install -m 644 -o root -g root "$KVM_CONF_SRC" "$KVM_CONF_DEST"
fi

# Option platí až při načtení modulu. Načtený kvm s Y přenačíst — jde jen
# když neběží žádná KVM virtuálka (libvirt, dockur, Android emulátor…).
KVM_PARAM=/sys/module/kvm/parameters/enable_virt_at_load
if [[ -r "$KVM_PARAM" && "$(cat "$KVM_PARAM")" == Y ]]; then
  vendor_mod=kvm_amd
  grep -qw vmx /proc/cpuinfo && vendor_mod=kvm_intel
  log_info "Reloading $vendor_mod + kvm to apply enable_virt_at_load=0"
  if run_sudo modprobe -r "$vendor_mod" kvm && run_sudo modprobe "$vendor_mod"; then
    log_debug "kvm enable_virt_at_load is now $(cat "$KVM_PARAM")"
  else
    log_warn "kvm is in use (a KVM guest running?) — stop it and re-run, or reboot"
  fi
else
  log_debug "kvm does not hold virtualization (enable_virt_at_load != Y or kvm not loaded)"
fi

log_info "Optional VMware setup complete"
log_info "  Windows 11 VM:  bash $STEP_DIR/new-win11-vm.sh [path/to/Win11.iso]"
log_info "  After a kernel update: re-run this script (rebuilds vmmon/vmnet)"
