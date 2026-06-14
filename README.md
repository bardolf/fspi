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
└── fingerprint-swaylock-setup.md   PAM setup for fingerprint unlock on swaylock
```

Numbering convention for `steps/`: `00–09` base system, `10–19` tools built or
fetched out of band, `20–29` config deployment, `30+` scripts and finishing
touches.

## What each step group does

- **00–09** — sudoers, system upgrade, env vars, repos (RPM Fusion, Flathub,
  Vivaldi, git-secret, Terra), package install, SELinux off, flatpaks,
  aliases, sysrq, swap off, timezone, VS Code, fonts.
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

- **NVIDIA (Maxwell GTX 950)**: see `nvidia-setup.md` for the full by-hand
  setup — the legacy `580xx` driver branch (595+ dropped Maxwell support),
  the `nomodeset`/`nvidia-drm.modeset=1` kernel-cmdline fix, and enabling
  Sway's `--unsupported-gpu` via `/etc/sway/environment`. Not run by
  `install.sh` (machine-specific hardware).
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
  and live in Bitwarden (search "NAS 192.168.1.11").
- No tests, no CI — validation is "run it on a Fedora Sway box."
