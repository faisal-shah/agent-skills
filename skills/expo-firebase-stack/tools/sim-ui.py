#!/usr/bin/env python3
"""Read and drive a booted iOS simulator's screen by testID or label (idb).

    sim-ui.py ids [filter]          every element: testID, label, frame (points)
    sim-ui.py tap <id-or-label>     tap the centre of the first match
                                    (testID prefix first, then label contains)
    sim-ui.py tapxy <x> <y>         tap a point, in POINTS (screenshot px / scale)
    sim-ui.py text <string>         type into the focused field
    sim-ui.py swipe x1 y1 x2 y2     swipe, in points
    sim-ui.py shot <name>           screenshot to $SIM_SHOTS/<name>.png (default .)

The simulator is $SIM_UDID, else the one booted simulator (two booted: set
SIM_UDID). React Native exposes `testID` as the element's AXUniqueId.

Needs idb with a companion connected to that simulator
(`idb_companion --udid <UDID>`, then `idb connect localhost <grpc_port>`).
`text` with nothing focused is delivered as hardware keys, and React Native's
dev build reads `d` and `i` as Dev Menu and inspector shortcuts: tap the field
first and check the caret.
"""
import json
import os
import subprocess
import sys
import time


def udid() -> str:
    if os.environ.get("SIM_UDID"):
        return os.environ["SIM_UDID"]
    out = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted", "-j"],
        capture_output=True, text=True, timeout=30, check=True,
    ).stdout
    booted = [d["udid"] for ds in json.loads(out)["devices"].values() for d in ds if d.get("state") == "Booted"]
    if len(booted) != 1:
        sys.exit(f"{len(booted)} simulators booted; set SIM_UDID")
    return booted[0]


def idb(*args: str, timeout: int = 30) -> str:
    return subprocess.run(
        ["idb", *args[:2], "--udid", UDID, *args[2:]],
        capture_output=True, text=True, timeout=timeout, check=True,
    ).stdout


def tree() -> list:
    out = idb("ui", "describe-all")
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        # idb prints a status line instead of JSON while its companion is still
        # starting, or when it has lost the simulator.
        sys.exit(f"idb answered without a tree (companion starting or not connected): {out.strip()[:200]}")


def find(key: str):
    elements = tree()
    for e in elements:
        if key and (e.get("AXUniqueId") or "").startswith(key):
            return e
    for e in elements:
        if key.lower() in (e.get("AXLabel") or "").lower():
            return e
    return None


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd, *args = sys.argv[1:]
    if cmd == "ids":
        flt = args[0].lower() if args else ""
        for e in tree():
            ident, label, f = e.get("AXUniqueId") or "", e.get("AXLabel") or "", e["frame"]
            if (ident or label) and (flt in ident.lower() or flt in label.lower()):
                off = " [disabled]" if e.get("enabled") is False else ""
                print(f"{ident[:34]:34s} | {label[:56]:56s} | "
                      f"{f['x']:.0f},{f['y']:.0f} {f['width']:.0f}x{f['height']:.0f}{off}")
    elif cmd == "tap" and args:
        e = find(args[0])
        if not e:
            sys.exit(f"not on screen: {args[0]}")
        f = e["frame"]
        x, y = f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
        idb("ui", "tap", str(round(x)), str(round(y)))
        print(f"tapped {e.get('AXUniqueId') or e.get('AXLabel')!r} at {x:.0f},{y:.0f}")
    elif cmd == "tapxy" and len(args) == 2:
        idb("ui", "tap", *args)
    elif cmd == "text" and args:
        idb("ui", "text", args[0], timeout=60)
    elif cmd == "swipe" and len(args) == 4:
        idb("ui", "swipe", *args, "--duration", "0.4")
    elif cmd == "shot" and args:
        time.sleep(float(args[1]) if len(args) > 1 else 0)
        path = os.path.join(os.environ.get("SIM_SHOTS", "."), args[0] + ".png")
        subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", path],
                       check=True, timeout=60, capture_output=True)
        print(path)
    else:
        sys.exit(__doc__)


UDID = udid() if __name__ == "__main__" and len(sys.argv) > 1 else ""

if __name__ == "__main__":
    main()
