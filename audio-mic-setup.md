# Audio Setup: Webcam Mic + Bluetooth Earbuds (Fedora, PipeWire)

Working audio layout on the desktop: **output = soundcore Liberty 5 earbuds over
A2DP/AAC, microphone = the USB webcam.** The earbuds' own microphone is dead at
the hardware/transport level and must not be used. Diagnosed and fixed
2026-09-09 on PipeWire 1.6.8 + WirePlumber 0.5.14.

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

## The webcam mic needs split disabled

The LifeCam only appears as a PipeWire source because of
`config/wireplumber/51-webcam-no-split.conf` (deployed by `steps/20_config.sh`).
With PipeWire's ALSA `split-enable` left on, this capture-only card ends up with
an **empty profile list** and no source node at all — and, separately, Steam
segfaults on the resulting NULL active-profile pointer (both confirmed gone once
the rule actually matched).

That rule must match on **`device.name`, not `device.form_factor`** — the ALSA
monitor never sets `form_factor` on a card, so a form_factor match silently
never fires and the card keeps `split-enable = true`. That exact bug sat in the
file unnoticed and is what left the machine with no usable microphone. The
config file's header comment carries the full reasoning; read it before touching
the rule.

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
pactl list cards | grep -A2 -i lifecam      # must show an "Active Profile:" line
pactl list short sources | grep -i HD5000   # the mic must appear as a source
pactl info | grep -E 'Default (Sink|Source)'
wpctl status                                # Sources: LifeCam marked *
```

Applications that were connected across a `systemctl --user restart wireplumber`
do not always reattach — Teams (flatpak `com.github.IsmaelMartinez.teams_for_linux`)
loses its streams silently and needs restarting, then the mic re-picked in its
own settings.
