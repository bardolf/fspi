#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Starting Fedora Sway setup"

for step in "$SCRIPT_DIR"/steps/*.sh; do
    log_info "Running step: $(basename "$step")"
    bash "$step" || { log_error "Step failed: $step"; exit 1; }
done

log_info "Setup complete!"

# Upozornění na reboot až úplně na konci — varování ze stepů (03 SELinux,
# 00b nové jádro) jinak zapadnou stovky řádků vysoko ve scrollbacku.
# Odvozuje se ze stavu systému, ne z markeru, takže sedí i při re-runu.
reboot_reasons=()

if selinuxenabled 2>/dev/null \
    && grep -qx 'SELINUX=disabled' /etc/selinux/config 2>/dev/null; then
    reboot_reasons+=("SELinux is disabled in /etc/selinux/config, but the running kernel still has it loaded")
fi

newest_kernel=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -1 || true)
if [[ -n "$newest_kernel" && "$newest_kernel" != "$(uname -r)" ]]; then
    reboot_reasons+=("newer kernel installed: $newest_kernel (running $(uname -r))")
fi

if ((${#reboot_reasons[@]} > 0)); then
    log_warn "═══════════════════════════════════════════"
    log_warn "  REBOOT REQUIRED:"
    for reason in "${reboot_reasons[@]}"; do
        log_warn "    - $reason"
    done
    log_warn "  Run: systemctl reboot"
    log_warn "═══════════════════════════════════════════"
fi
