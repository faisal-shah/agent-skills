#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyvista", "trimesh", "numpy"]
# ///
"""Interactive pyvista window for the build123d-mcp live session socket.

Connects to the Unix domain socket published by ``build123d-mcp --viewer-socket
PATH`` and shows the session geometry in a rotatable 3D window that updates as
the model changes while an agent (Codex or Copilot) drives the MCP tools.

Usage::

    build123d-viewer [socket_path]
    uv run live_viewer_pyvista.py [socket_path]

With no ``socket_path`` the newest ``/tmp/build123d-mcp.*.sock`` is used, which
is the right choice when a single agent is running. When several agents run at
once, ask the agent for its viewer socket path (each server binds its own
``/tmp/build123d-mcp.<pid>.sock``) and pass that path explicitly.

Adapted from the reference consumer in build123d-mcp (Apache-2.0); the wire
protocol is documented in that project's docs/live-viewer.md. A background
reader thread parses the length-prefixed frames into events and pushes them onto
a queue; the main thread owns all rendering, because VTK is not thread-safe.
"""

import argparse
import glob
import io
import json
import os
import queue
import socket
import struct
import sys
import threading
import time


def _has_listener(path: str) -> bool:
    """True if a server is currently accepting connections at ``path``.

    A stale socket file left behind by a killed server refuses the connection,
    so this filters those out when auto-selecting the newest socket.
    """
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.settimeout(0.5)
    try:
        probe.connect(path)
        return True
    except OSError:
        return False
    finally:
        probe.close()


def _newest_default_socket() -> str | None:
    """Return the most recently created *live* default viewer socket, if any.

    Prefers the newest socket with an active listener; stale socket files from
    killed servers are skipped so the viewer does not hang connecting to a dead
    path. Falls back to the newest socket overall when none currently has a
    listener (a server may still be starting up).
    """
    candidates = sorted(
        glob.glob("/tmp/build123d-mcp.*.sock"),
        key=lambda p: os.stat(p).st_mtime,
        reverse=True,
    )
    if not candidates:
        return None
    for path in candidates:
        if _has_listener(path):
            return path
    return candidates[0]


def _recv_exactly(sock: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("server closed the connection")
        buf += chunk
    return bytes(buf)


def read_frame(sock: socket.socket) -> tuple[dict, bytes]:
    """Read one length-prefixed frame: returns (header dict, binary payload)."""
    (json_len,) = struct.unpack(">I", _recv_exactly(sock, 4))
    header = json.loads(_recv_exactly(sock, json_len).decode("utf-8"))
    (bin_len,) = struct.unpack(">I", _recv_exactly(sock, 4))
    payload = _recv_exactly(sock, bin_len) if bin_len else b""
    return header, payload


class FrameReader(threading.Thread):
    """Daemon thread: connect, parse frames into event dicts, push onto a queue.

    Display-free (no pyvista/VTK), so the reader never touches the render window.
    An UPSERT's glb payload rides on the event under the ``glb`` key. Pushes
    ``{"type": "_EOF"}`` when the connection closes, ``{"type": "_ERROR"}`` if it
    cannot connect.
    """

    def __init__(self, sock_path: str, out: queue.Queue):
        super().__init__(daemon=True)
        self._sock_path = sock_path
        self._out = out

    def _connect(self) -> socket.socket:
        # Wait for the server to appear rather than failing fast, so the viewer
        # can be opened before the server is started. Close the window (or
        # Ctrl-C) to quit while waiting.
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        announced = False
        while True:
            try:
                sock.connect(self._sock_path)
                return sock
            except (FileNotFoundError, ConnectionRefusedError):
                if not announced:
                    print(
                        f"waiting for the server socket at {self._sock_path} ...",
                        flush=True,
                    )
                    announced = True
                time.sleep(0.2)

    def run(self) -> None:
        try:
            sock = self._connect()
        except OSError as exc:
            self._out.put({"type": "_ERROR", "error": str(exc)})
            return
        with sock:
            while True:
                try:
                    header, payload = read_frame(sock)
                except (ConnectionError, OSError):
                    break
                event = dict(header)
                if payload:
                    event["glb"] = payload
                self._out.put(event)
        self._out.put({"type": "_EOF"})


def glb_to_mesh(glb: bytes):
    """Decode binary glb into a pyvista mesh. Call on the main thread only.

    trimesh.load of a glb returns a Scene (a multi-geometry container), so it is
    concatenated to a single mesh before wrapping into pyvista.
    """
    import pyvista as pv
    import trimesh

    loaded = trimesh.load(io.BytesIO(glb), file_type="glb")
    geom = loaded.to_geometry() if isinstance(loaded, trimesh.Scene) else loaded
    return pv.wrap(geom)


_COLORS = ["tan", "steelblue", "lightgreen", "lightcoral", "plum", "khaki"]


class PyvistaScene:
    """Apply scene events to a pyvista Plotter. Main-thread only (VTK actors)."""

    def __init__(self, plotter):
        self._plotter = plotter
        self._color_for: dict[str, str] = {}
        self._framed = False  # fit the camera once, then leave it to the user

    def clear(self) -> None:
        self._plotter.clear_actors()
        self._color_for.clear()
        self._framed = False

    def apply(self, event: dict) -> str:
        etype = event.get("type")
        if etype == "UPSERT":
            name = event["name"]
            color = self._color_for.setdefault(name, _COLORS[len(self._color_for) % len(_COLORS)])
            mesh = glb_to_mesh(event["glb"])
            # add_mesh(name=...) replaces the same-named actor in place.
            self._plotter.add_mesh(mesh, name=name, color=color, show_edges=True)
            if not self._framed:
                self._plotter.view_isometric()
                self._plotter.reset_camera()
                self._framed = True
        elif etype == "REMOVE":
            self._plotter.remove_actor(event.get("name"))
            self._color_for.pop(event.get("name"), None)
        elif etype == "RESET":
            self.clear()
        return etype or "?"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "socket_path",
        nargs="?",
        help="path to the viewer UDS (default: newest /tmp/build123d-mcp.*.sock)",
    )
    args = parser.parse_args()

    socket_path = args.socket_path or _newest_default_socket()
    if not socket_path:
        print(
            "no viewer socket given and none found under /tmp/build123d-mcp.*.sock.\n"
            "Start a build123d agent first, then ask it for its viewer socket path.",
            file=sys.stderr,
        )
        return 1

    import pyvista as pv

    events: queue.Queue = queue.Queue()
    FrameReader(socket_path, events).start()

    plotter = pv.Plotter(window_size=(900, 700))
    plotter.set_background("white")
    plotter.add_text("build123d live viewer", font_size=10)
    scene = PyvistaScene(plotter)
    plotter.show(interactive_update=True, auto_close=False)
    print(f"viewer ready for {socket_path}; close the window to quit.")

    while True:
        rendered = False
        try:  # drain everything pending, then render once (coalesce bursts)
            while True:
                event = events.get_nowait()
                etype = event.get("type")
                if etype == "_ERROR":  # could not connect (e.g. permission denied)
                    print(f"reader error: {event.get('error')}", file=sys.stderr)
                    plotter.close()
                    return 1
                if etype == "_EOF":
                    # Server went away (e.g. it was stopped). Drop the now-stale
                    # geometry, keep the window open, and wait for it to return;
                    # on reconnect the server re-sends HELLO + a full-scene dump.
                    print("server disconnected; waiting for it to return ...")
                    scene.clear()
                    rendered = True
                    FrameReader(socket_path, events).start()
                    break
                scene.apply(event)
                rendered = True
        except queue.Empty:
            pass

        if rendered:
            plotter.render()
        try:  # pump the interactor so the window stays responsive
            plotter.update(stime=50)
        except Exception:  # noqa: BLE001 - the window was closed
            break
        if getattr(plotter, "render_window", True) is None:
            break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
