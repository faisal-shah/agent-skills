#!/usr/bin/env python3
"""Read and drive an Android emulator's screen by testID or visible text.

    avd-ui.py texts                 every visible text and content description
    avd-ui.py tap <id-or-text>      tap the centre of that element
    avd-ui.py type <id-or-text> <s> tap it, then type <s>
    avd-ui.py bounds <id-or-text>   print its bounds

React Native exposes `testID` as the node's resource-id. `uiautomator dump`
cannot read a screen that never goes idle (a spinner, playing media): it
fails with "could not get idle state" and leaves the previous dump in place.
This deletes the old dump first and exits 3 when there is no fresh one, so a
stale screen is never read as the current one; read an animating screen from
`adb exec-out screencap -p` instead. ADB is taken from $ADB, else PATH.
"""
import os
import re
import shutil
import subprocess
import sys

ADB = os.environ.get("ADB") or shutil.which("adb") or "adb"
DUMP = "/sdcard/avd-ui.xml"


def adb(*args: str) -> str:
    done = subprocess.run([ADB, *args], capture_output=True, text=True)
    return done.stdout + done.stderr


def screen() -> str:
    adb("shell", "rm", "-f", DUMP)
    out = adb("shell", "uiautomator", "dump", DUMP).strip()
    xml = adb("shell", "cat", DUMP)
    if "<hierarchy" not in xml:
        why = "the screen is animating; use screencap" if "idle state" in out else "is a device attached?"
        print(f"no fresh dump ({out or 'no output'}): {why}", file=sys.stderr)
        sys.exit(3)
    return xml


def find(xml: str, key: str):
    for node in re.findall(r"<node [^>]*>", xml):
        if f'resource-id="{key}"' in node or f'text="{key}"' in node or f'content-desc="{key}"' in node:
            x1, y1, x2, y2 = map(int, re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node).groups())
            return x1, y1, x2, y2
    return None


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in {"texts", "tap", "type", "bounds"}:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    xml = screen()
    if cmd == "texts":
        print("\n".join(t for t in re.findall(r'(?:text|content-desc)="([^"]+)"', xml)))
        return 0
    if len(sys.argv) < 3 or (cmd == "type" and len(sys.argv) < 4):
        print(__doc__, file=sys.stderr)
        return 2
    box = find(xml, sys.argv[2])
    if box is None:
        print(f"not on screen: {sys.argv[2]}", file=sys.stderr)
        return 1
    if cmd == "bounds":
        print(*box)
        return 0
    x, y = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    adb("shell", "input", "tap", str(x), str(y))
    if cmd == "type":
        adb("shell", "input", "text", sys.argv[3].replace(" ", "%s").replace("@", "\\@"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
