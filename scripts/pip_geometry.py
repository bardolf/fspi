#!/usr/bin/env python3
"""Drží pozici a velikost PiP okna mezi spuštěními (viz pip_play.sh).

Spouští se jako `pip_geometry.py <pid mpv>` a běží, dokud okno nezmizí:
počká, až sway okno namapuje a udělá z něj floating, obnoví na něm naposledy
uloženou geometrii, a při zavření okna si tu aktuální uloží zpátky.

Přesouvání ani zvětšování okna sway žádnou událostí nehlásí, takže průběžně
sledovat nejde — ale událost "close" nese poslední rect, což je přesně to, co
potřebujeme uložit.
"""

import json
import os
import subprocess
import sys
import time

STATE_FILE = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "pip", "geometry")


def swaymsg_run(command):
    subprocess.run(["swaymsg", "-q", command], check=False)


def sway_tree():
    result = subprocess.run(["swaymsg", "-t", "get_tree"],
                            capture_output=True, text=True, check=False)
    try:
        return json.loads(result.stdout or "{}")
    except ValueError:
        return {}


def find_window(node, pid):
    if node.get("pid") == pid and (node.get("app_id") or "") == "mpv":
        return node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key) or ():
            found = find_window(child, pid)
            if found:
                return found
    return None


def wait_for_window(pid, timeout=25.0):
    """Okno musí být nejen namapované, ale i floating — teprve pak má smysl
    nastavovat velikost a pozici. Floating z něj dělá pravidlo ve sway configu,
    které běží až po namapování."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        window = find_window(sway_tree(), pid)
        if window and window.get("type") == "floating_con" \
                and window["rect"]["width"] > 0:
            return window
        time.sleep(0.15)
    return None


def load_geometry():
    try:
        with open(STATE_FILE) as handle:
            width, height, pos_x, pos_y = handle.read().split()
        return int(width), int(height), int(pos_x), int(pos_y)
    except (OSError, ValueError):
        return None


def save_geometry(rect):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as handle:
        handle.write("%d %d %d %d\n"
                     % (rect["width"], rect["height"], rect["x"], rect["y"]))
    os.replace(tmp, STATE_FILE)


def on_visible_output(geometry):
    """Uložená pozice může být na monitoru, který už není připojený — pak by
    okno skončilo mimo obraz a nešlo by ho chytit."""
    width, height, pos_x, pos_y = geometry
    result = subprocess.run(["swaymsg", "-t", "get_outputs"],
                            capture_output=True, text=True, check=False)
    try:
        outputs = json.loads(result.stdout or "[]")
    except ValueError:
        return False
    for output in outputs:
        if not output.get("active"):
            continue
        rect = output.get("rect") or {}
        if pos_x < rect["x"] + rect["width"] and pos_x + width > rect["x"] \
                and pos_y < rect["y"] + rect["height"] and pos_y + height > rect["y"]:
            return True
    return False


def apply_geometry(con_id, geometry):
    width, height, pos_x, pos_y = geometry
    # Nejdřív velikost: sway při resize okno vycentruje, takže by jinak
    # přepsal pozici, kterou právě nastavíme.
    swaymsg_run("[con_id=%d] resize set width %d px height %d px"
                % (con_id, width, height))
    # "absolute" proto, že rect ze sway je globální, ale "move position" bere
    # souřadnice relativně k workspace — bez toho by okno každým obnovením
    # odskočilo o velikost panelu.
    swaymsg_run("[con_id=%d] move absolute position %d %d"
                % (con_id, pos_x, pos_y))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: pip_geometry.py <pid of mpv>")
    pid = int(sys.argv[1])

    window = wait_for_window(pid)
    if window is None:
        return
    con_id = window["id"]

    geometry = load_geometry()
    if geometry and on_visible_output(geometry):
        apply_geometry(con_id, geometry)
    elif geometry:
        # Nechej okno tam, kam ho dalo pravidlo ve sway configu, a zapomeň to.
        try:
            os.remove(STATE_FILE)
        except OSError:
            pass

    monitor = subprocess.Popen(
        ["swaymsg", "-m", "-r", "-t", "subscribe", '["window"]'],
        stdout=subprocess.PIPE, text=True)
    try:
        for line in monitor.stdout:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            container = event.get("container") or {}
            if event.get("change") == "close" and container.get("id") == con_id:
                save_geometry(container["rect"])
                break
    finally:
        monitor.terminate()


if __name__ == "__main__":
    main()
