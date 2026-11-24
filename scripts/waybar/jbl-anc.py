#!/usr/bin/env python3
"""Noise control (ANC / Ambient Aware / TalkThru / Off) of JBL headphones from waybar.

Usage:
  jbl-anc.py watch                   waybar module: one JSON line per change, empty text
                                     (= hidden module) while no JBL headphones are connected
  jbl-anc.py status                  print the current mode
  jbl-anc.py anc|ambient|talkthru|off
  jbl-anc.py cycle                   next mode of JBL_ANC_CYCLE (default "anc,ambient,off")

JBL_ANC_DEVICE=<MAC> picks the headphones explicitly; by default it is the first connected
Bluetooth device whose name starts with "JBL".

Tour One M3 a další modely, které aplikace JBL Headphones řadí do rodiny "Protocol4", mají
ovládání na BLE GATT službě 65786365-6c70-6f69-6e74-2e636f6d0000 ("excelpoint.com"). Zvuk
jede přes BR/EDR, ovládání potřebuje vedle toho LE spojení — BlueZ ho otevře přes
org.bluez.Bearer.LE1.Connect (LE bond vznikl spolu s párováním pro zvuk). Sluchátka berou
jen jedno ovládací spojení: dokud ho drží tenhle modul, aplikace v telefonu se nepřipojí
(zvuk ani tlačítka na sluchátkách to neovlivní).

Rámec: 00 dd | cmd u16 LE | 01 00 | délka u16 LE | payload; TLV = tag u16 | len u16 | value.
  0x0001 GET (payload = seznam tagů)   -> odpověď 0x0001: status u16 + TLV
  0x0002 SET (payload = TLV)           -> ack 0x0002 + notifikace 0x0003 s novým stavem
  0x0003 notifikace sluchátek (i po stisku tlačítka ANC na sluchátkách)
Každá relace (odběr notifikací) začíná SET HostType 0x2f = 01 — bez něj GET vrací prázdné
hodnoty a SET se ignoruje. Tagy 0x18 ANC, 0x19 Ambient Aware, 0x1a TalkThru: bit 7 = zapnuto,
bity 0-6 = úroveň (ta se zachovává). Off = SET 0x18 s nulovým bitem 7; zapsaný do 0x19/0x1a
ho sluchátka ignorují. Popis protokolu: https://github.com/NeoHBz/JBLProtocol4
(notes/protocol.md, ověřeno na Tune 780NC); hodnoty výše ověřené na Tour One M3.
"""

import json
import os
import signal
import subprocess
import sys
import time

import dbus
import dbus.mainloop.glib
import gi
from gi.repository import GLib

try:  # PyGObject >= 3.52; GLib.unix_signal_add je deprecated
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLibUnix
    unix_signal_add = GLibUnix.signal_add
except (ImportError, ValueError):
    unix_signal_add = GLib.unix_signal_add

BLUEZ = "org.bluez"
OBJ_MANAGER = "org.freedesktop.DBus.ObjectManager"
PROPS = "org.freedesktop.DBus.Properties"
DEVICE = "org.bluez.Device1"
LE_BEARER = "org.bluez.Bearer.LE1"
GATT_SERVICE = "org.bluez.GattService1"
GATT_CHAR = "org.bluez.GattCharacteristic1"

SERVICE_UUID = "65786365-6c70-6f69-6e74-2e636f6d0000"
RX_UUID = "65786365-6c70-6f69-6e74-2e636f6d0001"  # notify (sluchátka -> PC)
TX_UUID = "65786365-6c70-6f69-6e74-2e636f6d0002"  # write (PC -> sluchátka)

CMD_GET, CMD_SET, CMD_NOTIFY = 0x0001, 0x0002, 0x0003
TAG_BATTERY, TAG_HOST_TYPE = 0x000D, 0x002F
TAG_ANC, TAG_AMBIENT, TAG_TALKTHRU = 0x0018, 0x0019, 0x001A
NOISE_TAGS = {"anc": TAG_ANC, "ambient": TAG_AMBIENT, "talkthru": TAG_TALKTHRU}
STATE_TAGS = (TAG_BATTERY, TAG_ANC, TAG_AMBIENT, TAG_TALKTHRU)

# mode: (Nerd Font glyph, bar label, name)
MODES = {
    "anc": ("\U000F0A45", "ANC", "Noise cancelling"),   # md-ear_hearing_off
    "ambient": ("\U000F07C5", "AMB", "Ambient Aware"),  # md-ear_hearing
    "talkthru": ("\U000F05CB", "TT", "TalkThru"),       # md-account_voice
    "off": ("\U000F02CB", "OFF", "Off"),                # md-headphones
}
HEADPHONES = MODES["off"][0]
DEFAULT_CYCLE = "anc,ambient,off"


def log(msg):
    print(f"jbl-anc: {msg}", file=sys.stderr, flush=True)


# --- Protocol ---------------------------------------------------------------

def u16(n):
    return n.to_bytes(2, "little")


def frame(cmd, payload=b""):
    return b"\x00\xdd" + u16(cmd) + b"\x01\x00" + u16(len(payload)) + payload


def get_frame(tags):
    return frame(CMD_GET, b"".join(u16(t) for t in tags))


def set_frame(tag, value):
    return frame(CMD_SET, u16(tag) + u16(1) + bytes([value]))


HANDSHAKE = set_frame(TAG_HOST_TYPE, 0x01)


def parse_frames(data):
    """Yield (cmd, {tag: value}) for every frame; TLVs only for GET replies and notifications."""
    while len(data) >= 8 and data[1] == 0xDD:
        cmd = int.from_bytes(data[2:4], "little")
        size = int.from_bytes(data[6:8], "little")
        payload, data = data[8:8 + size], data[8 + size:]
        tags = {}
        if cmd in (CMD_GET, CMD_NOTIFY):
            i = 2  # status u16
            while i + 4 <= len(payload):
                tag = int.from_bytes(payload[i:i + 2], "little")
                n = int.from_bytes(payload[i + 2:i + 4], "little")
                tags[tag] = payload[i + 4:i + 4 + n]
                i += 4 + n
        yield cmd, tags


class State:
    """Last raw values of the noise tags (bit 7 = on, bits 0-6 = level) and the battery."""

    def __init__(self):
        self.raw = {}

    def update(self, tags):
        changed = False
        for tag in STATE_TAGS:
            value = tags.get(tag)
            if value and self.raw.get(tag) != value[0]:  # prázdná hodnota = relace bez handshaku
                self.raw[tag] = value[0]
                changed = True
        # Režimy se vylučují; kdyby notifikace nesla jen zapnutý tag, ostatní zhasnout.
        on = [t for t in NOISE_TAGS.values() if tags.get(t) and tags[t][0] & 0x80]
        for tag in NOISE_TAGS.values():
            if on and tag not in on and self.raw.get(tag, 0) & 0x80:
                self.raw[tag] &= 0x7F
                changed = True
        return changed

    @property
    def mode(self):
        if not all(t in self.raw for t in NOISE_TAGS.values()):
            return None
        for name, tag in NOISE_TAGS.items():
            if self.raw[tag] & 0x80:
                return name
        return "off"

    @property
    def battery(self):
        return self.raw[TAG_BATTERY] & 0x7F if TAG_BATTERY in self.raw else None

    def frame_for(self, mode):
        if mode == "off":
            return set_frame(TAG_ANC, self.raw[TAG_ANC] & 0x7F)
        tag = NOISE_TAGS[mode]
        return set_frame(tag, 0x80 | (self.raw[tag] & 0x7F))


# --- BlueZ ------------------------------------------------------------------

def managed_objects(bus):
    return dbus.Interface(bus.get_object(BLUEZ, "/"), OBJ_MANAGER).GetManagedObjects()


def find_device(objs):
    want = os.environ.get("JBL_ANC_DEVICE", "").upper()
    for path, ifaces in objs.items():
        dev = ifaces.get(DEVICE)
        if not dev or not dev.get("Connected"):
            continue
        if want and str(dev.get("Address", "")).upper() == want:
            return str(path)
        if not want and str(dev.get("Name", "")).startswith("JBL"):
            return str(path)
    return None


def find_chars(objs, dev):
    service = next((p for p, i in objs.items()
                    if p.startswith(dev + "/") and GATT_SERVICE in i
                    and str(i[GATT_SERVICE]["UUID"]).lower() == SERVICE_UUID), None)
    if service is None:
        return None, None
    chars = {str(i[GATT_CHAR]["UUID"]).lower(): str(p) for p, i in objs.items()
             if p.startswith(service + "/") and GATT_CHAR in i}
    return chars.get(RX_UUID), chars.get(TX_UUID)


class Link:
    """Notification subscription and writes on the control characteristics of one device."""

    def __init__(self, bus, rx, tx, on_frame):
        self.rx_path = rx
        self.on_frame = on_frame
        self.rx = dbus.Interface(bus.get_object(BLUEZ, rx), GATT_CHAR)
        self.tx = dbus.Interface(bus.get_object(BLUEZ, tx), GATT_CHAR)
        self.match = bus.add_signal_receiver(self._changed, "PropertiesChanged", PROPS, BLUEZ, rx)
        try:
            self.rx.StartNotify()
        except dbus.DBusException:
            self.match.remove()
            raise

    def _changed(self, iface, changed, _invalidated):
        if iface == GATT_CHAR and "Value" in changed:
            for cmd, tags in parse_frames(bytes(changed["Value"])):
                self.on_frame(cmd, tags)

    def write(self, data):
        self.tx.WriteValue(dbus.Array([dbus.Byte(b) for b in data], signature="y"),
                           {"type": dbus.String("request")})

    def close(self):
        self.match.remove()
        try:
            self.rx.StopNotify()
        except dbus.DBusException:
            pass


def cycle_modes():
    modes = [m.strip() for m in os.environ.get("JBL_ANC_CYCLE", DEFAULT_CYCLE).split(",")]
    return [m for m in modes if m in MODES] or DEFAULT_CYCLE.split(",")


# --- waybar module ----------------------------------------------------------

class Watcher:
    """Keeps the LE control link up while the headphones are connected and prints their state."""

    def __init__(self, bus, loop):
        self.bus = bus
        self.loop = loop
        self.dev = None
        self.name = ""
        self.link = None
        self.state = State()
        self.status = None  # None | "connecting" | "unavailable" | "unsupported"
        self.error = ""
        self.connecting = False
        self.opened_le = False
        self.awaiting_init = False
        self.retry_at = 0.0
        self.backoff = 0
        self.last_line = None
        self.pending = None
        cycle = " → ".join(MODES[m][1] for m in cycle_modes())
        self.hint = f"Click: {cycle}\nRight click: TalkThru · middle click: Off"
        bus.add_signal_receiver(self._props_changed, "PropertiesChanged", PROPS, BLUEZ,
                                path_keyword="path")
        bus.add_signal_receiver(lambda *_: self.schedule(), "InterfacesAdded", OBJ_MANAGER, BLUEZ)
        bus.add_signal_receiver(self._ifaces_removed, "InterfacesRemoved", OBJ_MANAGER, BLUEZ)
        GLib.timeout_add_seconds(15, self._tick)
        GLib.timeout_add_seconds(60, self._refresh)
        self.schedule()

    def schedule(self):
        if self.pending is None:
            self.pending = GLib.idle_add(self._reconcile)

    def _tick(self):
        self.schedule()
        return True

    def _props_changed(self, iface, changed, _invalidated, path=None):
        if iface == DEVICE and ("Connected" in changed or "ServicesResolved" in changed):
            self.schedule()
        elif iface == LE_BEARER and "Connected" in changed and path == self.dev:
            if not changed["Connected"]:
                self.drop()
            self.schedule()

    def _ifaces_removed(self, path, _ifaces):
        if self.link and (self.link.rx_path == path or self.link.rx_path.startswith(path + "/")):
            self.drop()
        self.schedule()

    def _reconcile(self):
        self.pending = None
        try:
            objs = managed_objects(self.bus)
        except dbus.DBusException as e:  # bluetoothd neběží / restartuje se
            log(f"BlueZ: {e.get_dbus_message()}")
            objs = {}
        dev = find_device(objs)
        if dev != self.dev:
            self.drop()
            self.dev, self.status, self.error = dev, None, ""
            self.backoff, self.retry_at, self.opened_le = 0, 0.0, False
            self.name = str(objs[dev][DEVICE].get("Alias", "JBL")) if dev else ""
        if dev and not self.link and self.status != "unsupported":
            self._connect_control(objs)
        self.emit()
        return False

    def _connect_control(self, objs):
        ifaces = objs[self.dev]
        rx, tx = find_chars(objs, self.dev)
        if rx and tx:
            try:
                self.link = Link(self.bus, rx, tx, self._frame)
                self.awaiting_init = True
                self.link.write(HANDSHAKE)
            except dbus.DBusException as e:
                self.drop()
                self._failed(e.get_dbus_message())
                return
            self.status, self.backoff = None, 0
            GLib.timeout_add(2000, self._init_timeout)
            return
        if LE_BEARER not in ifaces:
            self._unsupported("BlueZ has no org.bluez.Bearer.LE1")
            return
        if ifaces[LE_BEARER].get("Connected"):
            if ifaces[DEVICE].get("ServicesResolved"):
                self._unsupported("no JBL control service (not a Protocol4 model?)")
            else:
                self.status = "connecting"  # čeká se na ServicesResolved
            return
        if self.connecting or time.monotonic() < self.retry_at:
            return
        self.connecting = True
        self.status = "connecting"
        dev = self.dev
        dbus.Interface(self.bus.get_object(BLUEZ, dev), LE_BEARER).Connect(
            reply_handler=lambda: self._le_done(dev),
            error_handler=lambda e: self._le_done(dev, e),
            timeout=60)

    def _le_done(self, dev, error=None):
        self.connecting = False
        if dev != self.dev:
            return
        if error is None:
            self.opened_le = True
        elif error.get_dbus_name() != "org.bluez.Error.AlreadyConnected":
            self._failed(error.get_dbus_message())
        self.schedule()

    def _failed(self, msg):
        delay = (10, 30, 60)[min(self.backoff, 2)]
        self.backoff += 1
        self.status, self.error = "unavailable", msg
        self.retry_at = time.monotonic() + delay
        GLib.timeout_add_seconds(delay, self._tick_once)
        log(f"{self.name}: control channel: {msg}; retry in {delay} s")

    def _tick_once(self):
        self.schedule()
        return False

    def _unsupported(self, msg):
        self.status, self.error = "unsupported", msg
        log(f"{self.name}: {msg}")
        if self.opened_le:  # LE spojení jsme otevřeli my a k ničemu není — pustit
            dbus.Interface(self.bus.get_object(BLUEZ, self.dev), LE_BEARER).Disconnect(
                reply_handler=lambda: None, error_handler=lambda e: None)

    def _frame(self, _cmd, tags):
        if self.awaiting_init and TAG_HOST_TYPE in tags:
            self._query()
        if self.state.update(tags):
            self.emit()

    def _init_timeout(self):
        if self.awaiting_init:
            self._query()
        return False

    def _query(self):
        self.awaiting_init = False
        self._write(get_frame(STATE_TAGS))

    def _refresh(self):
        # Pravidelně obnoví stav (baterie); bez stavu zkusí relaci založit znovu.
        if self.link:
            if self.state.mode is None:
                self.awaiting_init = True
                self._write(HANDSHAKE)
            else:
                self._write(get_frame(STATE_TAGS))
        return True

    def _write(self, data):
        try:
            self.link.write(data)
        except (dbus.DBusException, AttributeError) as e:
            log(f"{self.name}: write failed: {e}")
            self.drop()
            self.schedule()

    def drop(self):
        if self.link:
            self.link.close()
            self.link = None
        self.state = State()

    def render(self):
        if not self.dev or self.status == "unsupported":
            return {"text": "", "tooltip": "", "class": "hidden"}
        name = GLib.markup_escape_text(self.name)
        mode = self.state.mode
        if self.link and mode:
            glyph, label, title = MODES[mode]
            tip = [f"{name}: {title}"]
            if self.state.battery is not None:
                tip.append(f"Battery {self.state.battery}%")
            tip += ["", self.hint]
            return {"text": f"{glyph} {label}", "tooltip": "\n".join(tip), "class": mode}
        # První nezdar bývá jen tím, že sluchátka po zapnutí ještě neinzerují LE.
        if self.status == "unavailable" and self.backoff >= 2:
            return {"text": f"{HEADPHONES} ?", "class": "unavailable",
                    "tooltip": f"{name}: control channel unavailable\n"
                               f"{GLib.markup_escape_text(self.error)}\n\n"
                               "Only one controller at a time — is the JBL app on the phone connected?"}
        return {"text": f"{HEADPHONES} …", "class": "connecting",
                "tooltip": f"{name}: connecting the control channel (BLE)…"}

    def emit(self):
        line = json.dumps(self.render(), ensure_ascii=False)
        if line == self.last_line:
            return
        self.last_line = line
        try:
            print(line, flush=True)
        except BrokenPipeError:  # waybar skončil
            self.loop.quit()


def watch():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    loop = GLib.MainLoop()
    watcher = Watcher(bus, loop)
    for sig in (signal.SIGTERM, signal.SIGINT):
        unix_signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()
    watcher.drop()


# --- one-shot commands ------------------------------------------------------

class CliError(Exception):
    pass


def wait_for(predicate, timeout):
    ctx = GLib.MainContext.default()
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() >= deadline:
            return False
        if not ctx.iteration(False):
            time.sleep(0.01)
    return True


def open_control(bus):
    objs = managed_objects(bus)
    dev = find_device(objs)
    if not dev:
        raise CliError("no JBL headphones connected")
    rx, tx = find_chars(objs, dev)
    if rx and tx:
        return rx, tx
    # Waybar modul neběží (jinak by LE spojení už drželo) — otevřít ho tady.
    try:
        dbus.Interface(bus.get_object(BLUEZ, dev), LE_BEARER).Connect(timeout=60)
    except dbus.DBusException as e:
        if e.get_dbus_name() != "org.bluez.Error.AlreadyConnected":
            raise CliError(f"cannot open the control channel: {e.get_dbus_message()}") from e
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        objs = managed_objects(bus)
        rx, tx = find_chars(objs, dev)
        if rx and tx:
            return rx, tx
        if objs.get(dev, {}).get(DEVICE, {}).get("ServicesResolved"):
            break
        time.sleep(0.2)
    raise CliError("headphones have no JBL control service (not a Protocol4 model?)")


def command(action):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    rx, tx = open_control(bus)
    state = State()
    host_type_echo = []

    def on_frame(_cmd, tags):
        if TAG_HOST_TYPE in tags:
            host_type_echo.append(True)
        state.update(tags)

    link = Link(bus, rx, tx, on_frame)
    try:
        link.write(HANDSHAKE)
        wait_for(lambda: host_type_echo, 1.5)
        link.write(get_frame(STATE_TAGS))
        if not wait_for(lambda: state.mode is not None, 3):
            raise CliError("headphones did not report their noise-control state")
        current = state.mode
        if action == "status":
            print(current)
            return
        if action == "cycle":
            modes = cycle_modes()
            target = modes[(modes.index(current) + 1) % len(modes)] if current in modes else modes[0]
        else:
            target = action
        if target != current:
            link.write(state.frame_for(target))
            if not wait_for(lambda: state.mode == target, 3):
                raise CliError(f"headphones did not switch to {MODES[target][2]}")
        print(target)
    finally:
        link.close()


def fail(msg):
    log(msg)
    if not sys.stderr.isatty():  # spuštěno z waybaru — chybu ukázat notifikací
        try:
            subprocess.run(["notify-send", "-a", "JBL", "JBL noise control", msg], check=False)
        except OSError:
            pass
    sys.exit(1)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "watch":
        watch()
    elif action in ("status", "cycle", *MODES):
        try:
            command(action)
        except CliError as e:
            fail(str(e))
        except dbus.DBusException as e:
            fail(e.get_dbus_message() or e.get_dbus_name())
    else:
        print(__doc__.split("\n\n", 2)[1], file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
