#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 19c: Howdy face unlock for swaylock"

# Howdy 3.x is not in Fedora, and the COPR every guide points at
# (principis/howdy-beta) is stale: its python3-elevate is still built against
# Python 3.13, so howdy-gtk will not install on a python3.14 Fedora, and
# python3dist(dlib) has no provider there at all. march7thdev/howdy-surface is
# the maintained fork and builds the whole chain — howdy, python3-dlib,
# python3-pyv4l2, python3-keyboard — for fedora-44. Despite the name, the plain
# `howdy` package in it is the generic build; the Surface-specific IR bits live
# in a separate `howdy-surface` package that is deliberately not installed.
#
# Only swaylock gets wired up. sudo would be a dead line because
# 00a_sudoers.sh gives this user NOPASSWD, and this box has no
# /etc/pam.d/polkit-1 and no polkit agent.
#
# The camera is a plain RGB webcam with no IR emitter, so treat this as
# convenience, not security. See howdy-face-unlock.md.

COPR_REPO="march7thdev/howdy-surface"
HOWDY_CONFIG="/etc/howdy/config.ini"
PAM_FILE="/etc/pam.d/swaylock"
PAM_SRC="$SCRIPT_DIR/files/pam/swaylock"

# --- COPR repository ---
if dnf repolist --enabled 2>/dev/null | grep -q "march7thdev:howdy-surface"; then
  log_debug "Howdy COPR repository already enabled"
else
  log_info "Enabling Howdy COPR repository ($COPR_REPO)"
  run_sudo dnf -y copr enable "$COPR_REPO"
fi

# Pulls in python3-dlib and, through python3-opencv, VTK — about 500 MiB.
ensure_package "howdy"

# --- Keep the COPR's own dependency repo off ---
# howdy-surface declares an external runtime dependency on
# march7thdev/Evernight-Vista-Kernel, and `dnf copr enable` silently turns that
# on alongside it — with gpgcheck=0. What it actually carries is
# kernel-evernight* (harmless: they do not collide with Fedora's `kernel`) and
# libwacom-surface, which Provides libwacom without Obsoleting it. Nothing in
# the Howdy transaction comes from it, so leaving it enabled buys an unsigned
# third-party repo for nothing.
#
# config-manager writes to /etc/dnf/repos.override.d/ rather than the .repo
# file, so this survives a later `dnf copr enable` regenerating that file.
COPRDEP_REPO="coprdep:https_download_copr_fedorainfracloud_org_results_march7thdev_Evernight_Vista_Kernel_fedora_releasever_basearch"
coprdep_state=$(dnf repolist --all 2>/dev/null | awk -v id="$COPRDEP_REPO" '$1 == id { print $NF }')
if [[ -z "$coprdep_state" ]]; then
  log_debug "Evernight kernel coprdep repository not present"
elif [[ "$coprdep_state" == "disabled" ]]; then
  log_debug "Evernight kernel coprdep repository already disabled"
else
  log_info "Disabling the COPR's unsigned Evernight kernel dependency repository"
  run_sudo dnf config-manager setopt "${COPRDEP_REPO}.enabled=0"
fi


# --- Point Howdy at the webcam ---
# Howdy ships device_path = none and then guesses, which on a box with two
# video nodes per camera picks the wrong one as often as not.
#
# The by-path link is preferred over by-id on purpose: the by-id name for this
# webcam contains a literal "®", and this string ends up in an INI file parsed
# by a C++ reader inside the PAM module. by-path is plain ASCII. The cost is
# that moving the camera to another USB port changes the path — re-run this
# step if that happens.
resolve_camera_path() {
  local node link
  for node in /dev/video*; do
    [[ -e "$node" ]] || continue
    # Every camera exposes a metadata node next to the capture node; only the
    # capture one reports ":capture:" in ID_V4L_CAPABILITIES.
    udevadm info -q property -n "$node" 2>/dev/null |
      grep -q '^ID_V4L_CAPABILITIES=.*:capture:' || continue
    for link in $(udevadm info -q property -n "$node" 2>/dev/null |
      sed -n 's/^DEVLINKS=//p' | tr ' ' '\n'); do
      # Skip the "usbv2-" spelling of the same link; either works, one is enough.
      case "$link" in
      /dev/v4l/by-path/*-usb-*) printf '%s\n' "$link" && return 0 ;;
      esac
    done
  done
  return 1
}

howdy_get() {
  # shellcheck disable=SC2016  # $1/$2/$3 here are awk fields, not shell args
  run_sudo awk -v k="$1" '$1 == k && $2 == "=" { print $3; exit }' "$HOWDY_CONFIG"
}

howdy_set() {
  local key="$1" value="$2"
  if [[ "$(howdy_get "$key")" == "$value" ]]; then
    log_debug "howdy config: $key already set to $value"
  else
    log_info "howdy config: setting $key = $value"
    run_sudo howdy set "$key" "$value"
  fi
}

# Howdy defaults to abort_if_lid_closed = true, and pam_howdy.so implements that
# by globbing /proc/acpi/button/lid/*/state. A desktop has no lid, so the glob
# matches nothing, returns GLOB_NOMATCH, and the module treats that as a fatal
# error — it bails out before it ever runs the recognition:
#
#   pam_howdy: Failed to read files from glob: 3
#   pam_howdy: Underlying error: No such file or directory (2)
#   pam_howdy: Failure, timeout reached
#
# The giveaway is that `compare.py` succeeds on its own while PAM still fails:
# the lid check lives in the C++ module, not in the Python half.
if [[ -d /proc/acpi/button/lid ]]; then
  log_debug "Lid button present, leaving abort_if_lid_closed alone"
else
  howdy_set abort_if_lid_closed false
fi

if camera_path=$(resolve_camera_path); then
  howdy_set device_path "$camera_path"
else
  log_warn "No capture-capable video device found — leaving device_path alone."
  log_warn "Plug the webcam in and re-run this step, or set it by hand:"
  log_warn "  sudo howdy set device_path /dev/v4l/by-path/<your-camera>"
fi

# --- PAM: replace /etc/pam.d/swaylock ---
# The whole file is deployed rather than a marker block, because the ORDER of
# the auth stack is the entire point and the stock file's single
# "auth include login" line has to move to the bottom of it. See the comments
# in files/pam/swaylock and the authselect section of
# fingerprint-swaylock-setup.md.

# One-time backup of whatever was there before we ever touch it.
if run_sudo test -f "${PAM_FILE}.fspi-backup"; then
  log_debug "PAM backup already exists: ${PAM_FILE}.fspi-backup"
else
  log_info "Backing up $PAM_FILE -> ${PAM_FILE}.fspi-backup"
  run_sudo cp -a "$PAM_FILE" "${PAM_FILE}.fspi-backup"
fi

# Refuse to deploy a stack that has lost its password line: with pam_unix gone
# and the camera unable to see you, there would be no way back in.
if ! grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_unix\.so' "$PAM_SRC"; then
  log_error "$PAM_SRC has no pam_unix.so auth line — refusing to deploy it"
  exit 1
fi

if run_sudo cmp -s "$PAM_SRC" "$PAM_FILE"; then
  log_debug "swaylock PAM stack already up-to-date"
else
  log_info "Deploying swaylock PAM stack: $PAM_SRC -> $PAM_FILE"
  run_sudo install -m 0644 -o root -g root "$PAM_SRC" "$PAM_FILE"
fi

# --- First-run hint: the face model has to be enrolled by hand ---
if run_sudo howdy -U "$USER" list --plain &>/dev/null; then
  log_debug "Face model already enrolled for $USER"
else
  log_warn "No face model enrolled yet — Howdy will just time out until there is one."
  log_warn "Sit in front of the webcam in the light you normally use, then run this"
  log_warn "FOUR times, shifting your head slightly between runs:"
  log_warn "  sudo howdy -U $USER -y add"
  log_warn "One model is not enough on this camera — measured 0.43 best distance"
  log_warn "against a 0.35 threshold, i.e. never a match. Four gets it to 0.25."
  log_warn "See howdy-face-unlock.md; verify with: sudo howdy -U $USER test"
fi

log_info "Step 19c complete"
