# LUKS Unlock over the Network (clevis + tang on the NAS)

The encrypted root/home volume unlocks itself at boot from a **tang** server on
the NAS — no passphrase typed, as long as the machine is on the home LAN. The
manual passphrase stays as the fallback. Set up by hand; **this repo does not
deploy any of it** (LUKS UUIDs and keyslots are per-install).

## The layout

```
nvme0n1p3   crypto_LUKS   UUID=a02f8e8f-ab7e-4d0e-8483-5e31e3bdbd59
└─ luks-a02f8e8f-…        btrfs "fedora" → subvol=root (/) and /home
```

Everything except `/boot` and `/boot/efi` is inside that one LUKS2 container, so
the unlock happens in the initrd, before switch-root.

- **Keyslot 0** — the passphrase, typed by hand. Never remove it; it is the only
  way in when the NAS is down or the machine is off the LAN.
- **Keyslot 1 + token 0** — the clevis/tang binding:

```bash
sudo clevis luks list -d /dev/nvme0n1p3
# 1: tang '{"url":"http://192.168.1.11:7500"}'
```

The tang server runs on the NAS at `192.168.1.11:7500` and is **not** configured
from this repo. `/etc/crypttab` carries `x-initrd.attach`; packages are
`clevis`, `clevis-luks`, `clevis-dracut`, `clevis-systemd`.

## How the boot actually works

`clevis-luks-askpass.path` watches `/run/systemd/ask-password`. The moment
systemd-cryptsetup posts a password question, `clevis-luks-askpass -l` starts and
**loops forever** (`sleep 0.5` between passes) until either the device is
unlocked or the question file disappears. There is no retry limit and no
timeout on the clevis side — worth knowing, because it changes what a failure
means.

The initrd needs an IP before any of that can work, hence on the kernel cmdline:

```
rd.neednet=1 ip=dhcp
```

**These lines at the start of every boot are normal:**

```
clevis-luks-askpass[…]: Error communicating with server http://192.168.1.11:7500
```

Clevis starts ~0.1 s after the NIC driver loads and simply spins until the
network is actually up. Six to ten of them per boot is the healthy case.

## The trap: DHCP sits in the boot-critical path

On 2026-09-12 the disk asked for the passphrase even though the NAS was up and
reachable:

```
15:58:11.1  igb loaded, enp7s0 appears
15:58:11.2  clevis starts → "Error communicating with server" ×37
15:58:14.6  NIC Link is Up 1000 Mbps
15:58:14.7  dhcp4 (enp7s0): activation: beginning transaction
15:58:37.8  passphrase typed by hand → unlocked, clevis exits
15:58:45.7  dhcp4: new lease, address=192.168.1.10     ← 8 s too late
```

The lease took **31 seconds**; the seven preceding boots got one in 0.01–2.4 s.
Nothing local had changed (no dnf transaction since 2026-09-09, same initramfs
across all those boots) — the router at `192.168.1.1` just left the first few
DISCOVERs unanswered, the usual suspects being a switch-port STP forward delay
or a busy router.

Two things worth internalising from that:

- **Clevis did not fail and did not time out.** It lost a race against a human.
  Waiting ~8 s longer at the prompt would have unlocked the disk by itself. If
  the passphrase prompt ever shows up, giving it half a minute before typing
  costs nothing and tells you which of the two is broken.
- **Tang being reachable "now" proves nothing about boot time.** The only thing
  that had gone wrong was address assignment.

That first bullet *is* the mitigation. `ip=dhcp` stays.

### Do not replace it with a static IP (tried 2026-09-12, reverted the next day)

The obvious fix is to take DHCP out of the critical path altogether:

```
ip=192.168.1.10::192.168.1.1:255.255.255.0::enp7s0:none
```

It works, and it works well — the next boot unlocked **0.8 s after link-up**,
six "Error communicating" lines and no prompt. **It also silently kills DNS.**

`nm-initrd-generator` turns that cmdline into a connection profile in
`/run/NetworkManager/system-connections/enp7s0.nmconnection`:

```ini
[ipv4]
address1=192.168.1.10/24
gateway=192.168.1.1
method=manual        # ← and no dns= line at all
```

After switch-root the real-root NetworkManager **assumes** that profile
(`device (enp7s0): state change: … managed-type: 'assume'`) instead of
configuring the link itself, because there is **no persistent wired profile** in
`/etc/NetworkManager/system-connections/` — only the wifi one. The wired link has
always run on whatever the initrd left behind. Under `ip=dhcp` that is harmless:
the generated profile is a DHCP profile, so `192.168.1.11` and `8.8.8.8` arrive
with the lease. Under a static `ip=` the generated profile carries no name
servers at all, so:

- `resolvectl status` shows **zero DNS servers on link enp7s0**
- the wired default route still wins on metric (100 vs. wifi's 600), so traffic
  leaves over the cable while DNS depends entirely on wifi being up
- wired-only — the normal state on this box — means **no DNS whatsoever**

Nothing about either symptom points back at the bootloader, which is what makes
it worth the paragraph. If a static `ip=` is ever wanted again it needs
`nameserver=192.168.1.11 nameserver=8.8.8.8` on the cmdline as well. A
persistent `/etc` profile alone does **not** rescue it: the generated profile's
`autoconnect-priority=-100` only decides who wins a fresh autoconnect (a cable
replug), and NetworkManager never preempts a connection it has already assumed.

## Verifying without rebooting

End-to-end test of the binding (recovers the real passphrase from tang, so don't
print it — the byte count is enough to prove it worked):

```bash
sudo clevis luks pass -d /dev/nvme0n1p3 -s 1 | wc -c    # 54 here; exit 0 = tang OK
curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://192.168.1.11:7500/adv
```

After a boot, the two numbers that matter:

```bash
journalctl -b | grep -c "Error communicating with server"   # ~6–10 normal, dozens = network slow
journalctl -b | grep "Unlocked /dev/disk/by-uuid"      # clevis says so when it wins
```

## Re-creating it after a reinstall

```bash
sudo dnf install clevis clevis-luks clevis-dracut clevis-systemd
sudo clevis luks bind -d /dev/nvme0n1p3 tang '{"url":"http://192.168.1.11:7500"}'
sudo dracut -f --regenerate-all
sudo grubby --update-kernel=ALL --args="rd.neednet=1 ip=dhcp"
```

`clevis luks bind` asks for an existing passphrase (keyslot 0) and consumes the
next free keyslot. The tang half on the NAS — the service, its keys and the
firewall rule — is not part of this repo.
