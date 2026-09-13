# Howdy face unlock for swaylock (Fedora 44)

**Status: working end to end as of 2026-09-13.** Howdy 3.0.1 and python3-dlib
20.0 are installed, four face models are enrolled, and swaylock unlocks on a
face — confirmed by `pam_howdy: Login approved` in the journal, not by
inference.

Unlock the swaylock screen locker with your face instead of a password, using
the Microsoft LifeCam HD-5000.

## What this is not

The LifeCam is a **plain RGB webcam with no IR emitter**. That has two
consequences worth being clear-eyed about:

- A photo, or your face on a phone screen, can pass it. Howdy upstream says the
  same about RGB cameras. This is a convenience feature, not a security one.
- It cannot see in the dark. In a dark room it will simply time out and you
  will type your password as before.

That is why it is wired into **swaylock only**, and specifically not into the
sddm login: the lock screen protects an already-unlocked session on a desktop
at home, while the login screen is the one barrier that exists after a cold
boot.

Two other PAM services that would normally be candidates are pointless here:

- **sudo** — `00a_sudoers.sh` installs `milan ALL=(ALL) NOPASSWD: ALL`, so sudo
  never asks for anything and `pam_howdy.so` there would be a dead line.
- **polkit** — this box has no `/etc/pam.d/polkit-1` and no polkit agent running.

## Where the packages come from

Howdy 3.x is not in Fedora. Every guide points at `principis/howdy-beta`, and
on Fedora 44 that repo is a dead end:

```
nothing provides python3dist(dlib) needed by howdy-3.0.0-7
package howdy-gtk requires python3dist(elevate), but
  nothing provides python(abi) = 3.13 needed by python3-elevate-0.1.3-3.fc41
```

Its `python3-elevate` is still built against Python 3.13 while Fedora 44 ships
3.14.7, and nothing anywhere provides `python3dist(dlib)` — not Fedora, not
RPM Fusion, not Terra.

`march7thdev/howdy-surface` is the maintained fork ("Since Principis seems to
be inactive, I try to maintain the package here") and builds the whole chain
for `fedora-44-x86_64`: `howdy`, `python3-dlib` 20.0, `python3-pyv4l2`,
`python3-keyboard`. Despite the name, the plain `howdy` package there is the
generic build — the Surface-specific IR bits are a separate `howdy-surface`
package that is deliberately not installed.

It is a big install: **68 packages, ~507 MiB**, most of it `python3-opencv`
dragging in VTK.

One classic Fedora trap does not apply here: SELinux normally blocks Howdy at
the login screen, but `steps/03_se_linux_disabled.sh` already disabled it.

### The dependency repo `dnf copr enable` turns on with it

Worth knowing, because it is easy to miss in the wall of text dnf prints:
howdy-surface declares an **external runtime dependency** on
`march7thdev/Evernight-Vista-Kernel`, and enabling the COPR silently enables
that one too — with `gpgcheck=0`.

Inspected before deciding what to do about it:

- The kernels there are named `kernel-evernight*`, not `kernel`, so they never
  compete with Fedora's kernel in a plain `dnf upgrade`.
- `libwacom-surface` **Provides** `libwacom` and `libwacom.so.9` but does not
  **Obsolete** them, so it will not swap itself in on its own either.
- `dnf upgrade --assumeno` pulls nothing from it, and nothing in the Howdy
  transaction came from it.

So the practical risk is low — but it is still an unsigned third-party
repository left permanently enabled in exchange for nothing, so
`steps/19c_howdy.sh` turns it back off:

```bash
sudo dnf config-manager setopt "coprdep:...Evernight_Vista_Kernel....enabled=0"
```

`config-manager` writes that to `/etc/dnf/repos.override.d/99-config_manager.repo`
rather than into the COPR's own `.repo` file, which is what makes it stick: a
later `dnf copr enable` regenerates the `.repo` file, and the override still
wins. Verified by re-running the step.

## The camera path

Howdy ships `device_path = none` and then guesses. The webcam exposes two
video nodes and only one of them is the capture device:

```bash
udevadm info -q property -n /dev/video0 | grep ID_V4L_CAPABILITIES
# ID_V4L_CAPABILITIES=:capture:      <- this one
udevadm info -q property -n /dev/video1 | grep ID_V4L_CAPABILITIES
# ID_V4L_CAPABILITIES=:              <- metadata node
```

The step resolves the capture node from udev and writes its **by-path** link,
not the by-id one. The by-id name is
`usb-Microsoft_Microsoft®_LifeCam_HD-5000-video-index0` — it contains a literal
`®`, and this string is parsed by a C++ INI reader inside the PAM module. The
by-path link is plain ASCII. The trade-off is that moving the camera to another
USB port changes the path; re-run the step if that happens.

## The PAM stack, and why the order is the whole story

`steps/19c_howdy.sh` replaces `/etc/pam.d/swaylock` wholesale with
`files/pam/swaylock`:

```
auth  sufficient  pam_unix.so nullok
auth  sufficient  pam_howdy.so
auth  required    pam_deny.so
```

This is the same shape `fingerprint-swaylock-setup.md` arrived at for the
ThinkPad's fingerprint reader, and it is deployed as a whole file rather than a
marker-delimited block precisely because the order is the point: the stock
file's single `auth include login` line has to be replaced, not preceded.

Password first, biometrics second. Read that doc's authselect section for the
long version; the short version is that a biometric module placed **first**
blocks the entire stack until its own timeout expires, so typing a password and
pressing Enter would make you wait several seconds staring at the camera before
the password is even looked at. With `pam_unix` first:

- **Password path** — type it, press Enter, unlocked instantly. `pam_howdy` is
  never reached and the camera never wakes up.
- **Face path** — press Enter on an empty prompt. `pam_unix` fails (the account
  has a real password, so `nullok` does not let an empty one through — verified
  with `passwd -S milan`, which reports `P`), and `pam_howdy` takes over.

Password fallback therefore cannot break. A missing `pam_howdy.so`, a dark
room, an unplugged webcam — all of them just fail line 2. The step also refuses
to deploy a file whose `pam_unix` line has gone missing, and keeps a one-time
`/etc/pam.d/swaylock.fspi-backup` of whatever was there first.

If this box ever gets a fingerprint reader too, the two coexist by adding the
fprintd line between them:

```
auth  sufficient  pam_unix.so nullok
auth  sufficient  pam_fprintd.so ignore-empty-password
auth  sufficient  pam_howdy.so
auth  required    pam_deny.so
```

`/etc/pam.d/swaylock` is owned by the `swaylock` RPM, so a package update may
drop a `.rpmnew` next to it or restore the stock file. `./diff-check.sh`
reports the drift once Howdy is installed; re-run the step to put it back.

## Enrolling a face — record four, not one

The model has to be recorded by hand; the step only warns when there is none.
**Record several models.** Howdy matches against the *closest* of all enrolled
encodings, and one model is measurably not enough on this camera:

| enrolled models | best distance | median | verdict at `certainty = 3.5` (threshold 0.35) |
| --------------- | ------------- | ------ | --------------------------------------------- |
| 1               | 0.426         | 0.503  | never matches — `compare.py` exits 11          |
| 4               | 0.252         | ~0.28  | matches in ~1.3 s                              |

Four models, varying the head angle slightly between them, took the distance
from "always times out" to "comfortably under the threshold" without touching
`certainty`. Loosening the threshold instead would have been the wrong trade:
0.35 is already strict compared to dlib's conventional 0.6, and that strictness
is the only thing standing in for the liveness detection an IR camera would
give us.

```bash
sudo howdy -U milan -y add        # repeat 4x, shift your head between runs
sudo howdy -U milan list          # what is enrolled
sudo howdy -U milan test          # live preview with the distance (opens a window)
```

`-y` matters when running this from anything without a controlling terminal:
without it, `add` prompts for a label with `input()` and dies on `EOFError`.
With `-y` the label defaults to `Model #N` and the rest of the capture is
automatic — it reads up to 60 frames and stops at the first detected face.

Only one person may be in frame; `add` refuses when it detects more than one
face because it cannot tell which one is you.

## Verifying

```bash
sudo howdy -U milan list                     # at least one model
grep ^auth /etc/pam.d/swaylock                # pam_unix, then pam_howdy, then pam_deny
grep '^device_path' /etc/howdy/config.ini     # the by-path capture node
./diff-check.sh                               # PAM stack matches the repo
```

Then lock the screen and try it. swaylock only starts a PAM transaction when
you submit input, so the flow is **press Enter on an empty prompt, then look at
the camera** — not "walk up and it opens".

The authoritative check is the journal, not whether the screen happened to
open:

```bash
journalctl -b | grep pam_howdy
```

A good run looks like this — note that the first attempt timed out because the
`timeout = 4` window starts the moment you press Enter, and four seconds is not
much if you press Enter and *then* sit up straight:

```
swaylock: pam_unix(swaylock:auth): authentication failure   <- the empty Enter, by design
pam_howdy: Failure, timeout reached                         <- first try, too slow
pam_howdy: Login approved                                   <- second try
```

If that four-second window keeps catching you out, `sudo howdy set timeout 6`
widens it. The cost is symmetric: when Howdy *cannot* see you — dark room,
webcam unplugged — the prompt sits there that much longer before you can fall
back to typing the password.

## Turning it off

Fastest, keeps everything installed:

```bash
sudo howdy disable true        # [core] disabled = true; the CLI still works
```

Putting the stock PAM stack back instead:

```bash
sudo cp -a /etc/pam.d/swaylock.fspi-backup /etc/pam.d/swaylock
```

Full removal:

```bash
sudo cp -a /etc/pam.d/swaylock.fspi-backup /etc/pam.d/swaylock
sudo dnf remove howdy python3-dlib python3-pyv4l2 python3-keyboard
sudo dnf copr disable march7thdev/howdy-surface
# and the override that kept the Evernight dependency repo off:
sudo rm -f /etc/dnf/repos.override.d/99-config_manager.repo
```

## Troubleshooting

- **`Warning: could not start ir_bridge`.** Expected, and harmless. This fork
  unconditionally tries to spawn `/usr/local/bin/ir_bridge`, a Surface IR
  helper shipped by the `howdy-surface` package we do not install. `Popen`
  raises immediately, so it costs a printed line and not the `time.sleep(1.0)`
  that follows it on hardware where the bridge exists. If it ever shows up
  inside the swaylock prompt itself, that is cosmetic, not a failure.
- **Always times out.** Check the camera is the one Howdy uses:
  `sudo howdy -U milan test`. If the preview is black or garbled, try
  `sudo howdy set force_mjpeg true` — the LifeCam offers both YUYV and MJPG and
  the raw YUYV path is the documented source of decode trouble.
- **Recognises too easily / not at all.** Before touching `certainty` in
  `/etc/howdy/config.ini` (3.5 by default, lower is stricter), enrol more
  models — see the table above. Measure rather than guess: the loop in
  `compare.py` can be replicated in a few lines to print the per-frame
  darkness, face count and match distance, which says immediately whether the
  problem is the camera, the detector or the threshold.
- **A red herring worth not chasing twice.** `compare.py` scales every frame to
  `max_height` (320) before encoding and `add.py` does not scale at all, so
  models are recorded at 480px and compared at 320px. That looks like it would
  inflate the distance, and it does not: measured on the same frames, native
  and downscaled encodings differ by less than 0.005 (min 0.421 both ways).
  dlib crops the face to a fixed 150x150 chip internally, so the frame scale
  barely matters.
- **`compare.py` succeeds but swaylock still falls through to the password.**
  Check `journalctl -b | grep pam_howdy` for:

  ```
  pam_howdy: Failed to read files from glob: 3
  pam_howdy: Underlying error: No such file or directory (2)
  pam_howdy: Failure, timeout reached
  ```

  That is the lid check. Howdy defaults to `abort_if_lid_closed = true`, and
  `pam_howdy.so` implements it by globbing `/proc/acpi/button/lid/*/state`. A
  desktop has no lid, the glob returns `GLOB_NOMATCH` (3), and the module
  treats that as fatal and gives up before running recognition at all. Fixed by
  `steps/19c_howdy.sh`, which sets `abort_if_lid_closed = false` whenever
  `/proc/acpi/button/lid` does not exist.

  Worth internalising the diagnostic shape: the lid check lives in the **C++
  module**, the recognition in the **Python half**. So "the CLI works but PAM
  does not" points at the module, not at the camera or the models.
- **Nothing happens at the lock screen.** See the note above about pressing
  Enter first. Failing that, `journalctl -b | grep pam_howdy`.
- **The webcam's audio half is a separate mess.** See `audio-mic-setup.md`;
  the two are independent, but the same device is involved.
