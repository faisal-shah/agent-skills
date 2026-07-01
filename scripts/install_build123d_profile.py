#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "build123d-mcp @ git+https://github.com/pzfreo/build123d-mcp@main",
# ]
# ///
"""Install build123d-mcp profile files for Codex and Copilot."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from importlib.resources import files
from pathlib import Path


SERVER_NAME = "build123d-mcp"
# The live session viewer (--viewer-socket) is provided by the build123d-mcp
# main branch, so the server is installed from git main rather than a PyPI
# release. It is installed once as a persistent uv tool at install time and the
# generated config launches the installed executable directly: this avoids the
# ~1.5 s per-launch git re-resolution of `uv tool run --from git+...`, which
# raced MCP-host startup timeouts and intermittently left the server unavailable
# on session resume.
PACKAGE_SPEC = "git+https://github.com/pzfreo/build123d-mcp@main"
PROFILE_NAME = "build123d"
DEFAULT_VIEWER_SOCKET_DIR = "/tmp"
MODE_DESCRIPTION = (
    "Parametric CAD profile using build123d-mcp for iterative geometry, "
    "measurement, rendering, engineering drawings, and export."
)

#: Vendored live-viewer consumer, installed into each profile so a human can
#: watch the model over the viewer socket. See docs in profiles/build123d.
_VIEWER_CONSUMER = (
    Path(__file__).resolve().parent.parent
    / "profiles"
    / PROFILE_NAME
    / "viewer"
    / "live_viewer_pyvista.py"
)


def viewer_supported() -> bool:
    """True when the live-viewer socket can be used on this platform.

    The viewer needs an ``AF_UNIX`` socket; build123d-mcp rejects
    ``--viewer-socket`` on Windows, so the flag is only emitted on POSIX hosts.
    """
    return os.name == "posix"


def uv_tool_install(mcp_python: str) -> None:
    """Install/update build123d-mcp (git main) as a persistent uv tool.

    ``--force`` reinstalls so re-running the installer picks up a moved ``main``.
    Failures are fatal: the launch config points at the installed executable, so
    a missing install must surface rather than write a config that cannot start.
    """
    subprocess.run(
        ["uv", "tool", "install", "--force", "--python", mcp_python, PACKAGE_SPEC],
        check=True,
    )


def uv_tool_uninstall() -> str:
    """Remove the persistent build123d-mcp uv tool (best-effort)."""
    result = subprocess.run(
        ["uv", "tool", "uninstall", SERVER_NAME],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return f"Uninstalled uv tool {SERVER_NAME}"
    return f"uv tool {SERVER_NAME} not installed"


def resolve_installed_exe() -> str:
    """Return the absolute path to the installed build123d-mcp executable.

    Resolved after ``uv tool install`` so the config launches the exact installed
    build directly (fast, offline, deterministic). The uv tool bin directory is
    the canonical source; PATH and the platform default are fallbacks.
    """
    exe_name = f"{SERVER_NAME}.exe" if os.name == "nt" else SERVER_NAME

    try:
        bin_dir = subprocess.run(
            ["uv", "tool", "dir", "--bin"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        candidate = Path(bin_dir) / exe_name
        if candidate.exists():
            return str(candidate)
    except (OSError, subprocess.SubprocessError):
        pass

    on_path = shutil.which(SERVER_NAME)
    if on_path:
        return str(Path(on_path).resolve() if os.name != "nt" else Path(on_path))

    fallback = Path.home() / ".local" / "bin" / exe_name
    if fallback.exists():
        return str(fallback)

    raise RuntimeError(
        f"could not locate the installed {SERVER_NAME} executable after "
        "'uv tool install'; is the uv tool bin directory on PATH?"
    )


def _launch(exe: str, viewer: bool, viewer_dir: str) -> tuple[str, str]:
    """Return ``(command, args_literal)`` for launching the installed server.

    ``args_literal`` is a JSON array valid in both the Codex TOML config and the
    Copilot YAML front matter. With the live viewer enabled the installed
    executable is wrapped in ``sh -c`` so each instance binds its own per-process
    socket ``<dir>/build123d-mcp.<pid>.sock``; any number of concurrent
    Codex/Copilot agents therefore never contend for one socket. The running
    server carries the resolved path in its argv, so the agent can report it and
    the human opens the viewer on it. ``BUILD123D_VIEWER_SOCKET`` overrides the
    path. Without the viewer the executable is launched directly.
    """
    if viewer and viewer_supported():
        default_socket = (
            f"{(viewer_dir or DEFAULT_VIEWER_SOCKET_DIR).rstrip('/')}/{SERVER_NAME}.$$.sock"
        )
        launch_line = (
            f'exec "{exe}" --viewer-socket '
            '"${BUILD123D_VIEWER_SOCKET:-' + default_socket + '}"'
        )
        return "sh", json.dumps(["-c", launch_line])
    return exe, json.dumps([])


def _home_path(value: str | None, env_name: str, default_name: str) -> Path:
    if value:
        return Path(value).expanduser()
    env_value = os.environ.get(env_name)
    if env_value:
        return Path(env_value).expanduser()
    return Path.home() / default_name


def _toml_string(value: str) -> str:
    return '"' + value.replace("\\", "/").replace('"', '\\"') + '"'


def _read_package_skill(skill_dir: str) -> str:
    root = files("build123d_mcp") / "skills" / skill_dir / "SKILL.md"
    return root.read_text(encoding="utf-8")


def _write_text(path: Path, content: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return f"Unchanged {path}"
    path.write_text(content, encoding="utf-8", newline="\n")
    return f"Wrote {path}"


def _remove_path(path: Path) -> str:
    if path.is_dir():
        shutil.rmtree(path)
        return f"Removed {path}"
    if path.exists():
        path.unlink()
        return f"Removed {path}"
    return f"Nothing to remove: {path}"


def _remove_empty(path: Path) -> None:
    try:
        path.rmdir()
    except OSError:
        pass


def _viewer_instructions(viewer: bool) -> str:
    """A short section telling the agent how to report its live-viewer socket."""
    if not viewer:
        return ""
    return f"""
## Live viewer

A human can watch this session in an interactive 3D window. Each server instance
binds its own socket at `{DEFAULT_VIEWER_SOCKET_DIR}/{SERVER_NAME}.<pid>.sock`.
When asked where the viewer socket is, read the resolved path from your running
server's argv and report it:

```bash
pgrep -af -- --viewer-socket
```

The user then opens the window with `build123d-viewer <path>`. The socket streams
the live scene after each mutating tool; it does not replace `render_view` checks.
"""


def _profile_instructions(skill_root: Path, viewer: bool) -> str:
    modeling = (skill_root / "b123d-modeling" / "SKILL.md").as_posix()
    drawing = (skill_root / "b123d-drawing" / "SKILL.md").as_posix()
    return f"""# build123d CAD Profile

You are running in the build123d CAD profile. Use the `{SERVER_NAME}` MCP server for build123d work instead of writing blind, one-shot CAD scripts.

## Startup

- For a new model, call `reset`, then `execute` with `from build123d import *`.
- Read `build123d://quickref` before using unfamiliar build123d APIs.
- For fasteners, bearings, threads, or catalogue parts, read `build123d://bd_warehouse` and probe valid sizes before scripting.

## Workflow

- Build geometry incrementally.
- After each meaningful geometry change, run `measure` before rendering.
- Use `save_snapshot` before risky operations and `restore_snapshot` when an experiment fails.
- Use `render_view` only after deterministic checks make sense, or when the user asks to inspect the shape.
- Use `export` for STEP, STL, DXF, or SVG output. Do not directly edit exported CAD artifacts as source.

## Profile-Local Workflow Files

Before creating, modifying, or reverse-engineering a 3D part or assembly, read:

`{modeling}`

Before creating or fixing an engineering drawing from build123d geometry, read:

`{drawing}`

These files are installed for this profile. Do not copy them into the current working directory unless explicitly asked.

## File Placement

- Use the system temp directory for scratch files, previews, and intermediate rendered images.
- Write final user-requested CAD, drawing, and script artifacts to the current working directory or to the path the user specifies.
- Do not create MCP configuration files, agent instruction files, or editor configuration files in the current working directory unless explicitly asked.

## Heavy Builds

For expensive operations such as threads, gears, large arrays, or many fillets:

1. Probe APIs and feature behavior through MCP.
2. Build the long-running geometry in a normal Python script when needed.
3. Import the resulting STEP or STL with `import_cad_file`.
4. Verify with `measure`, `shape_compare`, `clearance`, and `render_view`.

## Finish

- Run final numeric checks against the requested dimensions and features.
- Export the requested deliverables.
- Save a clean regeneration script when the user wants repeatable CAD source or when the model is likely to be revised.
{_viewer_instructions(viewer)}"""


def _codex_config(codex_home: Path, exe: str, viewer: bool, viewer_dir: str) -> str:
    instructions = codex_home / "profiles" / PROFILE_NAME / "instructions.md"
    command, args_literal = _launch(exe, viewer, viewer_dir)
    return f"""model_reasoning_effort = "xhigh"
model_instructions_file = {_toml_string(instructions.as_posix())}

[mcp_servers.{SERVER_NAME}]
command = {json.dumps(command)}
args = {args_literal}
startup_timeout_sec = 60
tool_timeout_sec = 180
"""


def _copilot_agent(copilot_home: Path, exe: str, viewer: bool, viewer_dir: str) -> str:
    skill_root = copilot_home / "profiles" / PROFILE_NAME / "skills"
    modeling = (skill_root / "b123d-modeling" / "SKILL.md").as_posix()
    drawing = (skill_root / "b123d-drawing" / "SKILL.md").as_posix()
    command, args_literal = _launch(exe, viewer, viewer_dir)
    return f"""---
name: build123d
description: {MODE_DESCRIPTION}
tools: ["*"]
mcp-servers:
  {SERVER_NAME}:
    type: "local"
    command: {json.dumps(command)}
    args: {args_literal}
    tools: ["*"]
---

# build123d CAD Profile

Use the `{SERVER_NAME}` MCP server for build123d work instead of writing blind, one-shot CAD scripts.

For a new model, call `reset`, then `execute` with `from build123d import *`. Build incrementally, run `measure` after meaningful geometry changes, use snapshots before risky operations, render only after deterministic checks make sense, and export final deliverables with `export`.

Before creating, modifying, or reverse-engineering a 3D part or assembly, read:

`{modeling}`

Before creating or fixing an engineering drawing from build123d geometry, read:

`{drawing}`

Use the system temp directory for scratch files, previews, and intermediate rendered images. Write final user-requested CAD, drawing, and script artifacts to the current working directory or to the path the user specifies.

Do not create MCP configuration files, agent instruction files, or editor configuration files in the current working directory unless explicitly asked.
{_viewer_instructions(viewer)}"""


def _install_skill_files(target_root: Path) -> list[str]:
    messages: list[str] = []
    skills = {
        "b123d-modeling": _read_package_skill("b123d-modeling"),
        "b123d-drawing": _read_package_skill("b123d-drawing"),
    }
    for skill_dir, content in skills.items():
        messages.append(_write_text(target_root / skill_dir / "SKILL.md", content))
    return messages


def _install_viewer_files(profile_root: Path) -> list[str]:
    """Install the vendored live-viewer consumer into the profile."""
    content = _VIEWER_CONSUMER.read_text(encoding="utf-8")
    return [_write_text(profile_root / "viewer" / "live_viewer_pyvista.py", content)]


def install_codex(codex_home: Path, exe: str, viewer: bool, viewer_dir: str) -> list[str]:
    messages: list[str] = []
    profile_root = codex_home / "profiles" / PROFILE_NAME
    skill_root = profile_root / "skills"
    messages.extend(_install_skill_files(skill_root))
    messages.append(_write_text(profile_root / "instructions.md", _profile_instructions(skill_root, viewer)))
    messages.append(_write_text(codex_home / f"{PROFILE_NAME}.config.toml", _codex_config(codex_home, exe, viewer, viewer_dir)))
    if viewer:
        messages.extend(_install_viewer_files(profile_root))
    return messages


def install_copilot(copilot_home: Path, exe: str, viewer: bool, viewer_dir: str) -> list[str]:
    messages: list[str] = []
    profile_root = copilot_home / "profiles" / PROFILE_NAME
    skill_root = profile_root / "skills"
    messages.extend(_install_skill_files(skill_root))
    messages.append(_write_text(profile_root / "instructions.md", _profile_instructions(skill_root, viewer)))
    messages.append(_write_text(copilot_home / "agents" / f"{PROFILE_NAME}.agent.md", _copilot_agent(copilot_home, exe, viewer, viewer_dir)))
    if viewer:
        messages.extend(_install_viewer_files(profile_root))
    return messages


def uninstall_codex(codex_home: Path) -> list[str]:
    profile_root = codex_home / "profiles" / PROFILE_NAME
    messages = [
        _remove_path(codex_home / f"{PROFILE_NAME}.config.toml"),
        _remove_path(profile_root),
    ]
    _remove_empty(codex_home / "profiles")
    return messages


def uninstall_copilot(copilot_home: Path) -> list[str]:
    profile_root = copilot_home / "profiles" / PROFILE_NAME
    messages = [
        _remove_path(copilot_home / "agents" / f"{PROFILE_NAME}.agent.md"),
        _remove_path(profile_root),
    ]
    _remove_empty(copilot_home / "agents")
    _remove_empty(copilot_home / "profiles")
    return messages


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("all", "codex", "copilot"), default="all")
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--codex-home")
    parser.add_argument("--copilot-home")
    parser.add_argument("--mcp-python", default="3.12")
    parser.add_argument(
        "--no-viewer",
        action="store_true",
        help="Do not enable the build123d live-viewer socket in the generated config.",
    )
    parser.add_argument(
        "--viewer-socket-dir",
        default=DEFAULT_VIEWER_SOCKET_DIR,
        help="Directory for per-instance live-viewer sockets (POSIX only). Default: %(default)s",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    codex_home = _home_path(args.codex_home, "CODEX_HOME", ".codex")
    copilot_home = _home_path(args.copilot_home, "COPILOT_HOME", ".copilot")
    viewer = (not args.no_viewer) and viewer_supported()

    messages: list[str] = []

    if args.uninstall:
        if args.target in ("all", "codex"):
            messages.extend(uninstall_codex(codex_home))
        if args.target in ("all", "copilot"):
            messages.extend(uninstall_copilot(copilot_home))
        messages.append(uv_tool_uninstall())
        for message in messages:
            print(message)
        return 0

    # Install/update the persistent tool once, then launch the installed
    # executable directly so startup is fast, offline, and deterministic.
    uv_tool_install(args.mcp_python)
    exe = resolve_installed_exe()
    messages.append(f"Installed uv tool {SERVER_NAME} -> {exe}")

    if args.target in ("all", "codex"):
        messages.extend(install_codex(codex_home, exe, viewer, args.viewer_socket_dir))
    if args.target in ("all", "copilot"):
        messages.extend(install_copilot(copilot_home, exe, viewer, args.viewer_socket_dir))

    for message in messages:
        print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

