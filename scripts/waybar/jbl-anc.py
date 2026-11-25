#!/usr/bin/python3
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
ho sluchátka ignorují. Bez provozu sluchátka relaci po pár minutách potichu zahodí (LE spojení
i odběr zůstanou, jen přestanou odpovídat) — proto heartbeat SET 0x0002 (prázdná hodnota) každé
~3 s jako aplikace JBL; obnoví ji až nový odběr (zápis CCCD). Zápisy jdou jako write-without-
response, takže se souběžné zápisy (kliknutí + heartbeat) v BlueZ nesrazí na "In Progress".
Popis protokolu: https://github.com/NeoHBz/JBLProtocol4
(notes/protocol.md, ověřeno na Tune 780NC); hodnoty výše ověřené na Tour One M3.
"""

import fcntl
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
BREDR_BEARER = "org.bluez.Bearer.BREDR1"
GATT_SERVICE = "org.bluez.GattService1"
GATT_CHAR = "org.bluez.GattCharacteristic1"

SERVICE_UUID = "65786365-6c70-6f69-6e74-2e636f6d0000"
RX_UUID = "65786365-6c70-6f69-6e74-2e636f6d0001"  # notify (sluchátka -> PC)
TX_UUID = "65786365-6c70-6f69-6e74-2e636f6d0002"  # write (PC -> sluchátka)

CMD_GET, CMD_SET, CMD_NOTIFY = 0x0001, 0x0002, 0x0003
TAG_HEARTBEAT, TAG_BATTERY, TAG_HOST_TYPE = 0x0002, 0x000D, 0x002F
HEARTBEAT_S = 3   # interval heartbeatu (aplikace JBL ~3 s)
SILENCE_S = 10    # bez odpovědi tak dlouho = mrtvá relace, založit odběr znovu
STATELESS_S = 45  # tak dlouho bez stavu = v liště "?" místo "…"
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


class CliError(Exception):
    pass


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
HEARTBEAT = frame(CMD_SET, u16(TAG_HEARTBEAT) + u16(0))


def parse_frames(data):
    """Yield (cmd, {tag: value}) for every frame; TLVs only for GET replies and notifications."""
    while len(data) >= 8 and data[0] in (0x00, 0x01) and data[1] == 0xDD:
        cmd = int.from_bytes(data[2:4], "little")
        size = int.from_bytes(data[6:8], "little")
        if 8 + size > len(data):  # useknutý rámec
            return
        payload, data = data[8:8 + size], data[8 + size:]
        tags = {}
        if cmd in (CMD_GET, CMD_NOTIFY):
            i = 2  # status u16
            while i + 4 <= len(payload):
                tag = int.from_bytes(payload[i:i + 2], "little")
                n = int.from_bytes(payload[i + 2:i + 4], "little")
                if i + 4 + n > len(payload):
                    break
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
        # Stačí ANC: modely bez Ambient/TalkThru ty tagy vynechají nebo vrátí prázdné.
        if TAG_ANC not in self.raw:
            return None
        for name, tag in NOISE_TAGS.items():
            if self.raw.get(tag, 0) & 0x80:
                return name
        return "off"

    @property
    def battery(self):
        return self.raw[TAG_BATTERY] & 0x7F if TAG_BATTERY in self.raw else None

    def frame_for(self, mode):
        tag = TAG_ANC if mode == "off" else NOISE_TAGS[mode]
        if tag not in self.raw:
            raise CliError(f"these headphones don't report {MODES[mode][2]}")
        if mode == "off":
            return set_frame(TAG_ANC, self.raw[TAG_ANC] & 0x7F)
        return set_frame(tag, 0x80 | (self.raw[tag] & 0x7F))


# --- BlueZ ------------------------------------------------------------------

def managed_objects(bus):
    # get_object na nevlastněné jméno by BlueZ D-Bus-aktivoval (na stroji bez adaptéru
    # při každém volání znovu, i s čekáním na timeout).
    if not bus.name_has_owner(BLUEZ):
        return {}
    return dbus.Interface(bus.get_object(BLUEZ, "/"), OBJ_MANAGER).GetManagedObjects()


def control_ready(objs, dev):
    # GATT objekty BlueZ cachuje (Cache=always) a nechává na D-Bus i po odpojení LE —
    # jejich existence nic neznamená, rozhoduje Bearer.LE1.Connected + ServicesResolved.
    ifaces = objs.get(dev, {})
    return bool(ifaces.get(LE_BEARER, {}).get("Connected")
                and ifaces.get(DEVICE, {}).get("ServicesResolved"))


def has_gatt(objs, dev):
    return any(p.startswith(dev + "/") and GATT_SERVICE in i for p, i in objs.items())


def find_device(objs):
    want = os.environ.get("JBL_ANC_DEVICE", "").upper()
    for path, ifaces in objs.items():
        dev = ifaces.get(DEVICE)
        # Device1.Connected platí i pro samotné LE, které drží tenhle modul — rozhoduje
        # zvukové (BR/EDR) spojení, jinak by modul po odchodu zvuku k telefonu držel
        # ovládání dál a blokoval tam aplikaci JBL.
        bredr = ifaces.get(BREDR_BEARER)
        if not dev or not (bredr.get("Connected") if bredr else dev.get("Connected")):
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
                           {"type": dbus.String("command")})

    def close(self):
        self.match.remove()
        try:
            self.rx.StopNotify()
        except dbus.DBusException:
            pass


def cycle_modes():
    modes = []
    for m in os.environ.get("JBL_ANC_CYCLE", DEFAULT_CYCLE).split(","):
        m = m.strip().lower()
        if m in MODES and m not in modes:
            modes.append(m)
    return modes or DEFAULT_CYCLE.split(",")


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
        self.init_timer = None
        self.last_rx = 0.0
        self.silent = 0   # kolikrát po sobě relace oněměla
        self.stateless_since = 0.0  # od kdy není znám stav (0 = je znám)
        self.retry_at = 0.0
        self.retry_timer = None
        self.backoff = 0
        self.last_line = None
        self.pending = None
        cycle = " → ".join(MODES[m][1] for m in cycle_modes())
        self.hint = f"Click: {cycle}\nRight click: TalkThru · middle click: Off"
        bus.add_signal_receiver(self._props_changed, "PropertiesChanged", PROPS, BLUEZ,
                                path_keyword="path")
        bus.add_signal_receiver(self._ifaces_added, "InterfacesAdded", OBJ_MANAGER, BLUEZ)
        bus.add_signal_receiver(self._ifaces_removed, "InterfacesRemoved", OBJ_MANAGER, BLUEZ)
        GLib.timeout_add_seconds(15, self._tick)
        GLib.timeout_add_seconds(HEARTBEAT_S, self._heartbeat)
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
        elif iface == BREDR_BEARER and "Connected" in changed:
            self.schedule()
        elif iface == LE_BEARER and "Connected" in changed and path == self.dev:
            if not changed["Connected"]:
                self.drop()
            self.schedule()

    def _ifaces_added(self, path, ifaces):
        # Služby dorazily později (Service Changed, pozdní Bearer.LE1) — zkusit to znovu.
        if (self.status == "unsupported" and self.dev and str(path).startswith(self.dev)
                and {LE_BEARER, GATT_SERVICE, GATT_CHAR} & set(map(str, ifaces))):
            self.status, self.error = None, ""
        self.schedule()

    def _ifaces_removed(self, path, ifaces):
        # Z cesty zařízení mizí i Battery1, MediaControl1…; link shodit jen s GATT/Device1.
        if (self.link and (self.link.rx_path == path or self.link.rx_path.startswith(path + "/"))
                and {DEVICE, GATT_SERVICE, GATT_CHAR} & set(map(str, ifaces))):
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
            self._release_le()
            self._cancel_retry()
            self.dev, self.status, self.error = dev, None, ""
            self.backoff, self.retry_at, self.silent = 0, 0.0, 0
            self.stateless_since = time.monotonic()
            self.name = str(objs[dev][DEVICE].get("Alias", "JBL")) if dev else ""
        if dev and not self.link and self.status != "unsupported":
            self._connect_control(objs)
        self.emit()
        return False

    def _connect_control(self, objs):
        ifaces = objs[self.dev]
        if LE_BEARER not in ifaces:
            self._unsupported("BlueZ has no org.bluez.Bearer.LE1")
            return
        if time.monotonic() < self.retry_at:
            return
        rx, tx = find_chars(objs, self.dev)
        if control_ready(objs, self.dev) and rx and tx:
            try:
                self.link = Link(self.bus, rx, tx, self._frame)
                self.awaiting_init = True
                self.last_rx = time.monotonic()
                self.link.write(HANDSHAKE)
            except dbus.DBusException as e:
                self.drop()
                self._failed(e.get_dbus_message())
                return
            self.status, self.backoff = None, 0
            self.init_timer = GLib.timeout_add(2000, self._init_timeout)
            return
        if ifaces[LE_BEARER].get("Connected"):
            if control_ready(objs, self.dev) and has_gatt(objs, self.dev):
                self._unsupported("no JBL control service (not a Protocol4 model?)")
            else:
                self.status = "connecting"  # čeká se na ServicesResolved / export GATT
            return
        if self.connecting:
            return
        self.status = "connecting"
        dev = self.dev
        try:
            dbus.Interface(self.bus.get_object(BLUEZ, dev), LE_BEARER).Connect(
                reply_handler=lambda: self._le_done(dev),
                error_handler=lambda e: self._le_done(dev, e),
                timeout=60)
        except dbus.DBusException as e:
            self._failed(e.get_dbus_message())
            return
        self.connecting = True

    def _le_done(self, dev, error=None):
        self.connecting = False
        if dev != self.dev:
            # Mezitím se zařízení změnilo/odpojilo; LE, které se právě otevřelo, nenechat viset.
            if error is None:
                self._le_disconnect(dev)
            self.schedule()
            return
        if error is None:
            self.opened_le = True
        elif error.get_dbus_name() == "org.bluez.Error.InProgress":
            # LE právě otevírá někdo jiný (CLI po kliknutí) — počkat, ne se točit dokola.
            self.retry_at = time.monotonic() + 2
            self._cancel_retry()
            self.retry_timer = GLib.timeout_add_seconds(2, self._retry)
            return
        elif error.get_dbus_name() != "org.bluez.Error.AlreadyConnected":
            self._failed(error.get_dbus_message())
        self.schedule()

    def _failed(self, msg):
        delay = (10, 30, 60)[min(self.backoff, 2)]
        self.backoff += 1
        self.status, self.error = "unavailable", msg
        self.retry_at = time.monotonic() + delay
        self._cancel_retry()
        self.retry_timer = GLib.timeout_add_seconds(delay, self._retry)
        log(f"{self.name}: control channel: {msg}; retry in {delay} s")

    def _retry(self):
        self.retry_timer = None
        self.retry_at = 0.0  # timer může vypršet o chlup dřív
        self.schedule()
        return False

    def _cancel_retry(self):
        if self.retry_timer is not None:
            GLib.source_remove(self.retry_timer)
            self.retry_timer = None

    def _unsupported(self, msg):
        self.status, self.error = "unsupported", msg
        log(f"{self.name}: {msg}")
        self._release_le()  # k ničemu není

    def _le_disconnect(self, dev, wait=False):
        try:
            bearer = dbus.Interface(self.bus.get_object(BLUEZ, dev), LE_BEARER)
            if wait:
                bearer.Disconnect(timeout=5)
            else:
                bearer.Disconnect(reply_handler=lambda: None, error_handler=lambda e: None)
        except dbus.DBusException:
            pass

    def _release_le(self, wait=False):
        """Close the LE link if this module opened it (it locks the phone app out)."""
        if self.opened_le and self.dev:
            self._le_disconnect(self.dev, wait)
        self.opened_le = False

    def _frame(self, _cmd, tags):
        self.last_rx = time.monotonic()
        self.silent = 0
        if self.awaiting_init and TAG_HOST_TYPE in tags:
            self._query()
        changed = self.state.update(tags)
        if self.state.mode:
            self.stateless_since = 0.0
            self.error = ""
        if changed:
            self.emit()

    def _init_timeout(self):
        self.init_timer = None
        if self.awaiting_init:
            self._query()
        return False

    def _query(self):
        self.awaiting_init = False
        self._write(get_frame(STATE_TAGS))

    def _heartbeat(self):
        if self.link:
            # Na heartbeat sluchátka odpovídají ackem, ticho = relace je mrtvá. Odběr znovu,
            # při opakovaném tichu (ovládání drží jiný klient?) s narůstajícím odstupem.
            if time.monotonic() - self.last_rx > SILENCE_S * min(1 + self.silent, 6):
                self.silent += 1
                self.error = "headphones stopped answering"
                log(f"{self.name}: no reply, re-subscribing (#{self.silent})")
                self.drop()
                self.schedule()
            else:
                self._write(HEARTBEAT)
        return True

    def _refresh(self):
        # Pravidelně obnoví stav (baterie); bez stavu zkusí relaci založit znovu.
        if self.link:
            if self.state.mode is None:
                self.awaiting_init = True
                self._write(HANDSHAKE)
                if self.link and self.init_timer is None:  # echo HostType nemusí přijít
                    self.init_timer = GLib.timeout_add(2000, self._init_timeout)
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
        if self.init_timer is not None:
            GLib.source_remove(self.init_timer)
            self.init_timer = None
        self.awaiting_init = False
        self.state = State()
        if not self.stateless_since:
            self.stateless_since = time.monotonic()

    def render(self):
        if not self.dev or self.status == "unsupported":
            return {"text": ""}  # prázdný text = waybar modul skryje
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
        stale = bool(self.stateless_since) and time.monotonic() - self.stateless_since > STATELESS_S
        if (self.status == "unavailable" and self.backoff >= 2) or self.silent >= 2 or stale:
            return {"text": f"{HEADPHONES} ?", "class": "unavailable",
                    "tooltip": f"{name}: control channel unavailable\n"
                               f"{GLib.markup_escape_text(self.error or 'no state from the headphones')}\n\n"
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
    if watcher.connecting and watcher.dev:  # Connect ještě běží — BlueZ by ho dokončil po nás
        watcher.opened_le = True
    watcher._release_le(wait=True)


# --- one-shot commands ------------------------------------------------------

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
    """-> (device path, rx, tx, whether this call opened the LE link)."""
    objs = managed_objects(bus)
    dev = find_device(objs)
    if not dev:
        raise CliError("no JBL headphones connected")
    if LE_BEARER not in objs[dev]:
        raise CliError("BlueZ has no org.bluez.Bearer.LE1")
    opened = False
    if not objs[dev][LE_BEARER].get("Connected"):
        # Waybar modul neběží nebo LE zrovna obnovuje — otevřít ho tady.
        try:
            dbus.Interface(bus.get_object(BLUEZ, dev), LE_BEARER).Connect(timeout=60)
            opened = True
        except dbus.DBusException as e:
            if e.get_dbus_name() not in ("org.bluez.Error.AlreadyConnected",
                                         "org.bluez.Error.InProgress"):
                raise CliError(f"cannot open the control channel: {e.get_dbus_message()}") from e
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        objs = managed_objects(bus)
        rx, tx = find_chars(objs, dev)
        if rx and tx and control_ready(objs, dev):
            return dev, rx, tx, opened
        time.sleep(0.2)
    if opened:
        disconnect_le(bus, dev)
    if not control_ready(objs, dev):
        raise CliError("the control channel (BLE) did not come up")
    raise CliError("headphones have no JBL control service (not a Protocol4 model?)")


def disconnect_le(bus, dev):
    try:
        dbus.Interface(bus.get_object(BLUEZ, dev), LE_BEARER).Disconnect()
    except dbus.DBusException:
        pass


def command(action):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    dev, rx, tx, opened = open_control(bus)
    state = State()
    host_type_echo = []

    def on_frame(_cmd, tags):
        if TAG_HOST_TYPE in tags:
            host_type_echo.append(True)
        state.update(tags)

    link = None
    try:
        link = Link(bus, rx, tx, on_frame)
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
        if link:
            link.close()
        if opened:  # LE jsme otevřeli my — nenechat ho viset (blokuje aplikaci v telefonu)
            disconnect_le(bus, dev)


def fail(msg, notify=True):
    log(msg)
    if notify and not sys.stderr.isatty():  # spuštěno z waybaru — chybu ukázat notifikací
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
        # Kliknutí po sobě (dvojklik) serializovat, jinak oba procesy přečtou stejný
        # stav a cyklus postoupí jen o krok.
        lock_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "jbl-anc.lock")
        try:
            with open(lock_path, "w") as lock:
                queued = time.monotonic()
                fcntl.flock(lock, fcntl.LOCK_EX)
                # Kliknutí, které čekalo dlouho (sluchátka neodpovídají), už neplatí —
                # jinak by se fronta po zotavení provedla jako kroky cyklu navíc.
                if action != "status" and time.monotonic() - queued > 3:
                    sys.exit(1)
                command(action)
        except CliError as e:
            fail(str(e), notify=action != "status")
        except dbus.DBusException as e:
            fail(e.get_dbus_message() or e.get_dbus_name(), notify=action != "status")
    else:
        print(__doc__.split("\n\n", 2)[1], file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
