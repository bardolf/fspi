# NVIDIA Setup (Maxwell GTX 950, Fedora Sway)

Proprietary NVIDIA driver setup for an older Maxwell card on Fedora Sway,
including the bits that make Sway (wlroots) actually start on NVIDIA. Tested
and working. Not automated by `install.sh` — this hardware is specific to one
machine, so the steps live here and are run by hand.

## Hardware

- NVIDIA GeForce GTX 950 (`GM206`, **Maxwell** architecture, `10de:1402`)
- Verify with: `lspci -nnk | grep -iA3 -E "vga|3d|display"`

## The critical gotcha: driver branch

NVIDIA dropped **Maxwell / Pascal / Volta** support starting with driver branch
**590/595**. The `580xx` branch is the **last** one that supports the GTX 950.

RPM Fusion's default `akmod-nvidia` now tracks 595+, which **builds fine but
cannot drive a Maxwell card** — you get a black screen after the LUKS prompt.
You must explicitly install the legacy `580xx` packages instead.

| Symptom | Cause |
| --- | --- |
| Black screen after LUKS password | 595+ driver loaded, no Maxwell support |
| 1024×768 on a 4K monitor + "no NVIDIA drivers" | `nomodeset` workaround → `simpledrm` fallback framebuffer, nvidia module never loads |
| Sway won't start from the display manager | wlroots refuses NVIDIA without `--unsupported-gpu` |

## Step 1: Remove the too-new driver

If a fresh install pulled in `akmod-nvidia` (595+), remove it first:

```bash
sudo dnf remove 'xorg-x11-drv-nvidia*' 'akmod-nvidia' 'kmod-nvidia*' \
  'nvidia-settings' 'nvidia-modprobe'
```

`nvidia-gpu-firmware` may stay — it is harmless and shared.

## Step 2: Install the 580xx legacy branch

Requires RPM Fusion nonfree (enabled by `steps/01_repos.sh`).

```bash
sudo dnf install akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda
```

Wait ~1–2 min for the akmod to build the kernel module in the background, then
verify it built for the running kernel:

```bash
modinfo nvidia | grep ^version    # expect 580.xx
```

If it returns nothing, force the build:

```bash
sudo akmods --force --kernels "$(uname -r)"
```

## Step 3: Fix the kernel command line

The card needs KMS, so `nomodeset` must be gone and `nvidia-drm.modeset=1` must
be set. Update the **existing** boot entries:

```bash
sudo grubby --update-kernel=ALL \
  --remove-args="nomodeset vga=791" \
  --args="nvidia-drm.modeset=1"
```

`grubby` only touches entries that already exist. To make it stick for **future
kernels**, also fix the two source-of-truth files (otherwise the next kernel
update regenerates a broken entry):

```bash
# /etc/kernel/cmdline  — source for new BLS entries
# /etc/default/grub    — GRUB_CMDLINE_LINUX
# In both: drop `vga=791`, drop `nomodeset`, add `nvidia-drm.modeset=1`.
# Keep the nouveau blacklist — it is correct.
```

Both should end up containing:

```
... rd.driver.blacklist=nouveau,nova_core modprobe.blacklist=nouveau,nova_core nvidia-drm.modeset=1
```

Regenerate the initramfs and verify the args propagated:

```bash
sudo dracut --force --regenerate-all
sudo grubby --info=ALL | grep args   # no nomodeset/vga=791, has nvidia-drm.modeset=1
```

## Step 4: Let Sway start on NVIDIA (`--unsupported-gpu`)

wlroots refuses to run on the proprietary NVIDIA driver unless Sway is launched
with `--unsupported-gpu`. Fedora's `start-sway` wrapper (from
`sway-config-fedora`) reads `SWAY_EXTRA_ARGS` from `/etc/sway/environment`, and
that file already ships the line commented out — just uncomment it:

```bash
sudo sed -i '/^#SWAY_EXTRA_ARGS=.*--unsupported-gpu/s/^#//' /etc/sway/environment
grep unsupported-gpu /etc/sway/environment    # line no longer starts with #
```

This is the clean seam: no edits to the packaged `sway.desktop` or `start-sway`
script (which updates would overwrite), and it applies to every user via the
display manager (SDDM). Per-user override goes in
`~/.config/sway/environment` instead.

## Step 5: Reboot

```bash
reboot
```

After the LUKS prompt the SDDM greeter and Sway should come up at native 4K.

## New kernels — nothing to do

Once the above is in place, kernel updates are **fully automatic**:

- **Driver:** `akmod-nvidia-580xx` + `akmods.service` rebuild the module during
  the `dnf` transaction for the new kernel.
- **Boot args:** the new BLS entry inherits the command line from
  `/etc/kernel/cmdline`, which now carries `nvidia-drm.modeset=1` and the
  nouveau blacklist.
- **Sway flag:** `SWAY_EXTRA_ARGS` lives in `/etc/sway/environment`, untouched
  by kernel or package updates.

## Troubleshooting

### Black screen on a brand-new kernel

The akmod build occasionally lags the kernel install. From a TTY
(`Ctrl+Alt+F3`):

```bash
modinfo nvidia | grep ^version            # is there a module for the new kernel?
sudo akmods --force && sudo dracut --force
```

Or boot the previous kernel from GRUB and give akmods a minute to finish.

### Verify the driver is live

```bash
cat /sys/module/nvidia_drm/parameters/modeset   # expect Y
nvidia-smi                                       # lists the GPU
journalctl -b -k | grep -iE "NVRM|nvidia"
```

### Sway still won't start from SDDM

Confirm the flag is actually being passed and inspect the session log:

```bash
grep -n unsupported /etc/sway/environment
sway --unsupported-gpu        # does it start manually from a TTY?
journalctl -b -t sway | tail -40
```

## References

- Tom's Hardware — 580 is the last branch for Maxwell/Pascal/Volta:
  https://www.tomshardware.com/pc-components/gpu-drivers/nvidia-to-axe-maxwell-pascal-and-volta-gpus-with-end-of-driver-support-580-series-drivers-will-be-the-last-to-support-gtx-900-and-1000-cards
- RPM Fusion NVIDIA howto: https://rpmfusion.org/Howto/NVIDIA
- ArchWiki — Sway on NVIDIA (`--unsupported-gpu`): https://wiki.archlinux.org/title/Sway#Nvidia
