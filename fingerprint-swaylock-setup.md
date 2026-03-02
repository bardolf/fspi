# Fingerprint Setup for Swaylock (ThinkPad + Goodix Sensor, Fedora)

Fingerprint unlock for swaylock on Fedora (Sway edition) using stock swaylock
with a custom PAM configuration. Tested and working.

## Hardware

- Lenovo ThinkPad with Goodix MOC Fingerprint Sensor (`27c6:6594`)
- Verify with: `lsusb | grep -i goodix`

## Prerequisites

Fedora ships `fprintd` and `fprintd-pam` preinstalled. Verify:

```bash
rpm -qa | grep fprintd
# expect: fprintd, fprintd-pam
```

## Step 1: Enroll fingerprints

```bash
fprintd-enroll
# Follow prompts, touch sensor multiple times

# Verify:
fprintd-verify

# Enroll a specific finger:
fprintd-enroll -f right-index-finger

# List enrolled fingerprints:
fprintd-list $USER
```

## Step 2: Configure PAM for swaylock

Replace `/etc/pam.d/swaylock` with a standalone config (do NOT include
`login` or `system-auth`):

```bash
sudo tee /etc/pam.d/swaylock > /dev/null << 'EOF'
# PAM configuration for swaylock
# Password first, fingerprint on empty Enter
auth  sufficient  pam_unix.so nullok
auth  sufficient  pam_fprintd.so ignore-empty-password
auth  required    pam_deny.so
EOF

sudo chown root:root /etc/pam.d/swaylock
sudo chmod 644 /etc/pam.d/swaylock
```

## Step 3: Make sure authselect with-fingerprint is disabled

The `with-fingerprint` authselect feature must NOT be enabled (see the
"Why not authselect" section below for why):

```bash
authselect current
# should NOT list with-fingerprint in enabled features

# If it is enabled, disable it:
sudo authselect disable-feature with-fingerprint
```

## Step 4: Test

```bash
swaylock
```

- **Password unlock:** Type your password, press Enter. Unlocks immediately.
- **Fingerprint unlock:** Press Enter (empty password), then touch the sensor.
  Unlocks after fingerprint match.

Password fallback always works, so you cannot get locked out.

## How it works

The PAM auth stack is evaluated top to bottom:

```
auth  sufficient  pam_unix.so nullok                   # 1. try password
auth  sufficient  pam_fprintd.so ignore-empty-password  # 2. try fingerprint
auth  required    pam_deny.so                           # 3. deny if both fail
```

1. `pam_unix.so nullok` -- checks the typed password. If you typed a correct
   password and pressed Enter, this succeeds (`sufficient` = stop here, grant
   access). If the password is wrong or empty, it fails and PAM moves to the
   next line.

2. `pam_fprintd.so ignore-empty-password` -- activates the fingerprint reader.
   The `ignore-empty-password` flag is key: when you pressed Enter with an
   empty input, `pam_unix.so` failed, and now `pam_fprintd.so` takes over and
   waits for a finger touch. If the fingerprint matches, access is granted.

3. `pam_deny.so` -- if both modules above failed, deny access.

The order matters: password first means typing a password and pressing Enter
works instantly without ever touching the sensor.

## Troubleshooting

### Re-enroll fingerprints

```bash
fprintd-delete $USER
fprintd-enroll
```

### Check fprintd status

```bash
fprintd-list $USER
systemctl status fprintd.service
journalctl -u fprintd --since "10 min ago"
```

### Fingerprint not detected after suspend/resume

fprintd may lose the USB device after suspend. A udev rule can help:

```bash
# /etc/udev/rules.d/01-fingerprint.rules
ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", \
  ATTRS{idVendor}=="27c6", ATTRS{idProduct}=="6594", \
  ATTR{power/persist}="1"
```

---

## Why not authselect `with-fingerprint`?

Fedora's `authselect` has a `with-fingerprint` feature that modifies
`/etc/pam.d/system-auth` to add `pam_fprintd.so`. It seems like the obvious
solution but it has a critical usability problem.

### What authselect does

Enabling the feature:

```bash
sudo authselect enable-feature with-fingerprint
```

Changes `/etc/pam.d/system-auth` to:

```
auth  sufficient  pam_fprintd.so      ← fingerprint FIRST
auth  sufficient  pam_unix.so nullok  ← password SECOND
auth  required    pam_deny.so
```

Since the default `/etc/pam.d/swaylock` is just `auth include login` which
chains into `system-auth`, this propagates to swaylock.

### The problem

With `pam_fprintd.so` listed FIRST (without `ignore-empty-password`):

1. You start typing your password in swaylock.
2. You press Enter to submit it.
3. `pam_fprintd.so` is the first module in the stack. It intercepts the
   authentication attempt and starts listening for a fingerprint.
4. It **blocks** -- waiting for you to touch the sensor.
5. Your typed password just sits there. `pam_unix.so` never gets a chance to
   check it until `pam_fprintd.so` finishes.
6. You are forced to touch the sensor (even with the wrong finger) just to
   make `pam_fprintd.so` fail/give up, so control finally passes to
   `pam_unix.so` which then checks your password.

**Result:** To unlock with a password, you must type the password, press Enter,
AND touch the sensor. This defeats the purpose of having a password fallback.

### Why the custom config fixes this

The custom `/etc/pam.d/swaylock` reverses the order and adds
`ignore-empty-password`:

```
auth  sufficient  pam_unix.so nullok                    ← password FIRST
auth  sufficient  pam_fprintd.so ignore-empty-password  ← fingerprint SECOND
```

- Password path: `pam_unix.so` runs first, checks the password, succeeds.
  `pam_fprintd.so` is never reached. No sensor touch needed.
- Fingerprint path: empty Enter makes `pam_unix.so` fail, then
  `pam_fprintd.so` activates with `ignore-empty-password` so it knows to
  wait for a finger instead of rejecting the empty input.

### Disabling authselect with-fingerprint

```bash
# Check current state:
authselect current

# Disable if with-fingerprint is listed:
sudo authselect disable-feature with-fingerprint

# Verify system-auth is back to password-only:
grep pam_fprintd /etc/pam.d/system-auth
# should return nothing
```

This only affects `system-auth`. The custom `/etc/pam.d/swaylock` is
independent and unaffected by authselect.

## References

- Alpine Wiki (concept reference): https://wiki.alpinelinux.org/wiki/Fingerprint_Authentication_with_swaylock
- ArchWiki fprint: https://wiki.archlinux.org/title/Fprint
- fprint supported devices: https://fprint.freedesktop.org/supported-devices.html
