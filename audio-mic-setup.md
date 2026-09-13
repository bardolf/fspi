# Audio Setup: Webcam Mic + Bluetooth Earbuds (Fedora, PipeWire)

Working audio layout on the desktop: **output = soundcore Liberty 5 earbuds over
A2DP/AAC, microphone = the USB webcam.** The earbuds' own microphone is dead at
the hardware/transport level and must not be used. Diagnosed
2026-09-09 on PipeWire 1.6.8 + WirePlumber 0.5.14; the Steam-killing half
re-diagnosed 2026-09-13, see below.

## Hardware

- Microsoft LifeCam HD-5000 webcam (`045e:076d`) — capture-only USB audio card,
  single mono mic. **This is the only working microphone on the machine.**
- soundcore Liberty 5 earbuds (`7C:E9:13:58:59:84`) — A2DP playback only.
- Broadcom BCM20702A0 Bluetooth 4.0 adapter (`0a5c:21e8`).

## The two failure modes

### 1. The earbuds' microphone returns digital silence

Recording from `bluez_input.<addr>` yields **peak 0 across every sample** — not a
quiet mic, a dead path. Reproduced in *both* HFP codecs:

```bash
pactl set-card-profile bluez_card.7C_E9_13_58_59_84 headset-head-unit       # mSBC
pactl set-card-profile bluez_card.7C_E9_13_58_59_84 headset-head-unit-cvsd  # CVSD
```

Both silent, so this is **not** the WirePlumber profile autoswitch — the SCO
transport itself is broken. The BCM20702A0 is a known SCO-over-USB problem
child. Cause not chased further; the webcam mic is the answer.

The trap: applications still *see* that microphone. WirePlumber's
`bluetooth.autoswitch-to-headset-profile` (default on) keeps a
`bluez_input.<addr>` loopback filter node present even in A2DP profile, so
"soundcore Liberty 5" shows up as a selectable mic in Teams/Chromium. Pick it
and the level meter never moves and nobody hears you. **Never select the earbuds
as a microphone.**

Distinguishing test — digital silence vs. a live mic:

```bash
timeout -s INT 4 pw-record --target <node> --rate 16000 --channels 1 --format s16 /tmp/t.wav
# peak 0 / zero non-zero samples  -> broken path
# any noise floor                 -> mic is live
```

### 2. Do not switch the Liberty 5 into a headset profile

Switching to `headset-head-unit*` makes BlueZ **tear down the AVDTP endpoint**.
The A2DP profiles then disappear from `pactl list cards` altogether, playback is
stuck at `s16le 1ch 8000Hz`, and switching back fails:

```
$ pactl set-card-profile bluez_card.7C_E9_13_58_59_84 a2dp-sink-sbc
Failure: No such entity
```

Recovery is a full Bluetooth reconnect:

```bash
bluetoothctl disconnect 7C:E9:13:58:59:84
bluetoothctl connect 7C:E9:13:58:59:84     # comes back on a2dp-sink (AAC)
```

## The empty-profile flake that kills Steam

Intermittently, and so far only at boot, the LifeCam card comes up with an
**empty ACP profile list**. `pactl list cards` prints it with no
`Active Profile:` line at all, and pipewire-pulse logs:

```
mod.protocol-pulse: card 50 port 0 profiles inconsistent (0 < 1)
```

`pw-dump` shows the same thing from the other side: `EnumProfile` is `[]` while
the active `Profile` still reports `off`. There is no source node either, so the
machine has no working microphone at all.

The second casualty is Steam. pipewire-pulse resolves `pa_card_info.active_profile`
by looking the active profile up in the profile list; with that list empty the
pointer comes out NULL. Steam's bundled `libaudio.so` dereferences it in its
`pa_context_get_card_info_list` callback and segfaults during startup, so Steam
dies before it can launch anything:

```
#0 libaudio.so                              <- Steam's callback, NULL deref
#1 context_get_card_info_callback  libpulse.so.0
#2 run_action                      libpulsecommon-17.0.so
```

The bug is Steam's — a profile-less card is legal in the PulseAudio API — but
Steam bootstraps its own client into `~/.local/share/Steam` and self-updates
outside dnf, so pinning or reverting it is not an option.

**The cure is `systemctl --user restart wireplumber`.** The ACP probe then
enumerates `off / pro-audio / input:mono-fallback` normally and the mic comes
back as a source.

### It is a cold-boot flake, not a misconfiguration

Not reproducible on demand: twelve consecutive WirePlumber restarts probed the
card correctly every time. Across boots it is rare — of the nine boots between
2026-09-09 and 2026-09-13, only the last one was affected. The probe opens the
PCM (`pa_alsa_open_by_device_string` on `hw:2`) and drops every profile it
cannot open, so something about the cold USB device makes that open fail. The
exact trigger is not pinned down; these were ruled out along the way:

- **The sddm greeter's audio stack.** Its user session only ever *listens* on
  `pipewire.socket`; `pipewire.service` is never started for uid 979, so nothing
  there ever holds the card.
- **A busy PCM.** Holding `hw:2` open with `arecord` across a WirePlumber
  restart makes the card **disappear entirely** and reappear when released —
  a different symptom from the empty profile list.
- **USB autosuspend** (the device sits at `power/control = auto`, 2 s delay, and
  is usually found `suspended`) stays plausible as a trigger, but every restart
  test resumed it without trouble.

To capture the failing probe if it recurs:

```bash
systemctl --user set-environment WIREPLUMBER_DEBUG=D,acp:5,alsa:5
systemctl --user restart wireplumber
journalctl --user -t wireplumber -b | grep -B2 -A6 "probe card hw:2"
# a healthy probe says: "Profile input:mono-fallback supported."
```

### The guard

`scripts/audio-card-profile-guard.sh`, run at login by
`audio-card-profile-guard.service` (deployed by `steps/31_audio_guard.sh`),
checks every ALSA card for a missing `Active Profile:` line and restarts
WirePlumber once if it finds one. It keys off that state rather than off the
webcam, because any card in it kills Steam. It refuses to restart while streams
are running — clients connected across a WirePlumber restart do not all
reattach — and says so instead.

### `api.alsa.split-enable` was a red herring

An earlier round of this blamed WirePlumber's `api.alsa.split-enable` and
deployed `config/wireplumber/51-webcam-no-split.conf` to turn it off for the
webcam. **That rule was inert**, and it has been removed. Two independent
checks, both on WirePlumber 0.5.14:

- With the rule gone the card still enumerates all three profiles and still
  lands on `input:mono-fallback`.
- `/usr/share/wireplumber/scripts/monitors/alsa.lua` sets `api.alsa.use-acp = true`
  unconditionally (line 32), and the split properties are only ever read on the
  node-creation path behind `if dev_props["api.alsa.use-acp"] ~= "true"`
  (line 193). With ACP on — always — nothing is ever split, so disabling
  splitting changes nothing. It never touched profile enumeration.

What actually cured the card the day the rule was written was the WirePlumber
restart that came with deploying it.

## Restoring the defaults after a fresh install

The default source/sink selection lives in WirePlumber runtime state
(`~/.local/state/wireplumber/default-nodes`), which this repo does **not**
deploy. After a reinstall or a wiped state directory, set it by hand:

```bash
pactl set-default-source alsa_input.usb-Microsoft_Microsoft___LifeCam_HD-5000-02.mono-fallback
pactl set-default-sink bluez_output.7C_E9_13_58_59_84.1
```

## Verifying

```bash
# every card must have an "Active Profile:" line under its name; a card without
# one is the empty-profile flake, and Steam will segfault on it
pactl list cards | grep -E 'Name: alsa_card|Active Profile'
pactl list short sources | grep -i lifecam  # the mic must appear as a source
pactl info | grep -E 'Default (Sink|Source)'
wpctl status                                # Sources: LifeCam marked *
```

Applications that were connected across a `systemctl --user restart wireplumber`
do not always reattach — Teams (flatpak `com.github.IsmaelMartinez.teams_for_linux`)
loses its streams silently and needs restarting, then the mic re-picked in its
own settings.
