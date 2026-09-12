# fspi — Fedora Sway Post-Install

Idempotent shell scripts that take a fresh Fedora Sway Spin install and bring
it up to the daily-driver state I actually use: repos, packages, dotfiles,
fonts, login-time tweaks, scripts, and a handful of optional add-ons.

Pure Bash — no compiled languages, no package managers beyond `dnf`/`flatpak`,
no build tools beyond shell. Every step is safe to re-run; check-then-act is
the rule throughout (`lib/utils.sh`).

## Quick start

```bash
./install.sh            # run all steps in order
DEBUG=1 ./install.sh    # same, with verbose "already done, skipping" lines
bash steps/02_packages.sh   # run a single step on its own
```

`install.sh` glob-sorts `steps/*.sh` and runs them sequentially; any step can
also be run directly. Re-running the whole thing is the supported way to
reconcile drift.

## Layout

```
fspi/
├── install.sh          Entry point — runs every steps/*.sh in order
├── diff-check.sh       Compare repo files against deployed system files
├── lib/
│   ├── logging.sh      log_info, log_warn, log_error, log_debug
│   └── utils.sh        ensure_package, ensure_symlink, ensure_file_copy, …
├── steps/              Numbered scripts (00–30) executed sequentially
├── config/             Dotfiles deployed to ~/.config/ by steps/20_config.sh
├── scripts/            User scripts deployed to ~/scripts/ by steps/30_scripts.sh
├── files/              Static files (desktop entries, icons, systemd units)
├── optional/           Opt-in components (e.g. Dropbox/rclone sync)
├── docs/archive/       Superseded hardware notes (kept for reference)
├── lc0-amd-setup.md    Leela Chess Zero with ROCm on AMD (by hand)
├── chess-relay-setup.md  Stockfish + Lc0 exposed over TCP for remote play
├── fingerprint-swaylock-setup.md   PAM setup for fingerprint unlock on swaylock
├── audio-mic-setup.md  Webcam mic + BT earbuds; the dead-HFP-mic traps
└── luks-tang-setup.md  Network-bound LUKS unlock (clevis + tang on the NAS)
```

Numbering convention for `steps/`: `00–09` base system, `10–19` tools built or
fetched out of band, `20–29` config deployment, `30+` scripts and finishing
touches.

## What each step group does

- **00–09** — sudoers, system upgrade, env vars, repos (RPM Fusion, Flathub,
  Vivaldi, git-secret, Terra), package install, SELinux off, flatpaks,
  aliases, sysrq, swap off, earlyoom, timezone, VS Code, fonts.
- **10–19** — LazyVim, gsettings, Docker, vpn-slice, wayfreeze, Satty, yazi,
  swaylock-effects (source build).
- **20–29** — config files into `~/.config/`, nvim settings, color schemes,
  desktop icons, zsh, calendar sync (vdirsyncer + khal + systemd timers).
- **30+** — user scripts into `~/scripts/`.

## Drift check

```bash
./diff-check.sh           # list configs/scripts that differ from the repo
./diff-check.sh -d        # also show unified diffs
DEBUG=1 ./diff-check.sh   # also list files that already match
```

Useful before committing local tweaks back upstream, or after running
`install.sh` to confirm the deployment matches the tree.

## Adding a step

Drop `steps/NN_name.sh` using the project skeleton (`set -euo pipefail`,
source `logging.sh` and `utils.sh`, log start/end, prefer the `ensure_*`
helpers). Conventions and code style are documented in `AGENTS.md`.

## Notes

- **Graphics**: AMD Radeon RX 6600 on the in-tree `amdgpu` driver — nothing to
  install or configure. The machine's previous NVIDIA GTX 950 setup is archived
  at `docs/archive/nvidia-setup.md` (historical only; no longer applied).
- **Lc0 na AMD GPU**: see `lc0-amd-setup.md` — the Leela Chess Zero engine
  with ROCm acceleration (`onnx-rocm` backend over Fedora's
  `onnxruntime-rocm`). Records the two non-obvious traps: lc0's OpenCL backend
  cannot run any modern network, and consumer RDNA2 cards need
  `HSA_OVERRIDE_GFX_VERSION=10.3.0` or the backend segfaults. Not run by
  `install.sh` (one-off, machine-specific).
- **Vzdálené šachové enginy**: see `chess-relay-setup.md` — Stockfish (3456,
  CPU) and Lc0 (3457, GPU) exposed over TCP via systemd socket activation, so a
  weak laptop can drive them through the NAS. Firewalled to the NAS address
  only. Deployed by `optional/chess-relay/setup.sh`; the NAS half lives in the
  `fspi-server` repo.
- **Fingerprint unlock for swaylock**: see `fingerprint-swaylock-setup.md`
  for the standalone `/etc/pam.d/swaylock` setup (password first, fingerprint
  on empty Enter — does not require `authselect with-fingerprint`).
- **Lock screen with effects**: `steps/18_swaylock_effects.sh` source-builds
  the `jirutka/swaylock-effects` fork (blur, screenshot, clock, fade-in) into
  `~/.local/bin/swaylock-effects`, kept distinct from the stock Fedora
  `swaylock` package so `sway-config-fedora`'s hard `Requires: swaylock` stays
  satisfied. The effects-specific config lives at
  `~/.config/swaylock/effects.conf` (separate filename so it can't break
  stock swaylock if the build is ever absent). All lock paths — `Mod+L`,
  rofi shutdown menu, swayidle (auto-lock, before-sleep, `loginctl
  lock-session`) — go through `swaylock-effects -C ~/.config/swaylock/effects.conf`
  via a user-side `~/.config/sway/config.d/90-swayidle.conf` override.
  PAM service name stays `swaylock`, so the fingerprint setup above applies
  unchanged.
- **Optional components** under `optional/` are not run by `install.sh`; each
  carries its own `setup.sh` to opt in. `optional/samba/` adds CIFS mounts for
  the `192.168.1.11` NAS to `/etc/fstab` (only run it on machines that need
  them); passwords are not in the repo — they go in `/etc/cifs-credentials/*.cred`
  and live in Bitwarden (search "NAS 192.168.1.11"). `optional/printer-cetin/`
  adds the CETIN office printer as a CUPS SMB queue (`cetin`); needs the CETIN
  VPN up, and the AD password goes in `/etc/cetin-printer.cred` (not in the repo).
- **RustDesk**: `steps/19b_rustdesk.sh` installs the upstream RPM but keeps the
  machine outgoing-only — it disables `rustdesk.service` from boot and sets
  RustDesk's own `stop-service` flag, so just opening the GUI does not register
  this machine on the public rendezvous server. Opening the client on both sides
  is **not** enough to be controlled: with no `rustdesk --server` process
  RustDesk sends both screen and input through the RemoteDesktop portal, which
  `xdg-desktop-portal-wlr` does not implement (ScreenCast and Screenshot only),
  so an inbound session dies before the first frame. Let someone in for a single
  session with `~/scripts/rustdesk-inbound.sh on` (and `off` afterwards); the
  unit is never re-enabled at boot.
- **Audio — webcam mic, not the earbuds' mic**: see `audio-mic-setup.md`. Output
  goes to the soundcore Liberty 5 over A2DP/AAC, but their microphone returns
  **digital silence** (peak 0) in both HFP codecs, so the LifeCam webcam's mic is
  the machine's only working one. Two traps recorded there: apps still offer the
  earbuds as a mic (WirePlumber keeps a loopback node present in A2DP), and
  switching them to a headset profile tears down the A2DP endpoint until a
  `bluetoothctl` reconnect. The webcam mic itself only exists thanks to
  `config/wireplumber/51-webcam-no-split.conf`, whose rule must match on
  `device.name` — a `device.form_factor` match silently never fires.
- **Disk unlocks itself from the NAS**: see `luks-tang-setup.md`. The LUKS2
  volume is bound with clevis to a tang server at `192.168.1.11:7500`, so the
  passphrase prompt normally never appears; keyslot 0 stays as the manual
  fallback. The initrd therefore needs networking, and it uses a **static**
  address (`ip=192.168.1.10::192.168.1.1:255.255.255.0::enp7s0:none`) — `ip=dhcp`
  once took 31 s to get a lease and the passphrase got typed 8 s before it
  arrived. Note that `clevis-luks-askpass` never times out: a prompt means the
  network is late, not that clevis gave up, so waiting at it is worth a try.
  Set up by hand; not deployed by `install.sh`.
- No tests, no CI — validation is "run it on a Fedora Sway box."
