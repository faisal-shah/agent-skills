#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "build123d-mcp",
# ]
# ///
"""Install build123d-mcp profile files for Codex and Copilot."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from importlib.resources import files
from pathlib import Path


SERVER_NAME = "build123d-mcp"
PACKAGE_SPEC = "build123d-mcp@latest"
PROFILE_NAME = "build123d"
MODE_DESCRIPTION = (
    "Parametric CAD profile using build123d-mcp for iterative geometry, "
    "measurement, rendering, engineering drawings, and export."
)


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


def _profile_instructions(skill_root: Path) -> str:
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
"""


def _codex_config(codex_home: Path, mcp_python: str) -> str:
    instructions = codex_home / "profiles" / PROFILE_NAME / "instructions.md"
    return f"""model_reasoning_effort = "xhigh"
model_instructions_file = {_toml_string(instructions.as_posix())}

[mcp_servers.{SERVER_NAME}]
command = "uv"
args = ["tool", "run", "--python", "{mcp_python}", "{PACKAGE_SPEC}"]
startup_timeout_sec = 60
tool_timeout_sec = 180
"""


def _copilot_agent(copilot_home: Path, mcp_python: str) -> str:
    skill_root = copilot_home / "profiles" / PROFILE_NAME / "skills"
    modeling = (skill_root / "b123d-modeling" / "SKILL.md").as_posix()
    drawing = (skill_root / "b123d-drawing" / "SKILL.md").as_posix()
    return f"""---
name: build123d
description: {MODE_DESCRIPTION}
tools: ["*"]
mcp-servers:
  {SERVER_NAME}:
    type: "local"
    command: "uv"
    args: ["tool", "run", "--python", "{mcp_python}", "{PACKAGE_SPEC}"]
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
"""


def _install_skill_files(target_root: Path) -> list[str]:
    messages: list[str] = []
    skills = {
        "b123d-modeling": _read_package_skill("b123d-modeling"),
        "b123d-drawing": _read_package_skill("b123d-drawing"),
    }
    for skill_dir, content in skills.items():
        messages.append(_write_text(target_root / skill_dir / "SKILL.md", content))
    return messages


def install_codex(codex_home: Path, mcp_python: str) -> list[str]:
    messages: list[str] = []
    profile_root = codex_home / "profiles" / PROFILE_NAME
    skill_root = profile_root / "skills"
    messages.extend(_install_skill_files(skill_root))
    messages.append(_write_text(profile_root / "instructions.md", _profile_instructions(skill_root)))
    messages.append(_write_text(codex_home / f"{PROFILE_NAME}.config.toml", _codex_config(codex_home, mcp_python)))
    return messages


def install_copilot(copilot_home: Path, mcp_python: str) -> list[str]:
    messages: list[str] = []
    profile_root = copilot_home / "profiles" / PROFILE_NAME
    skill_root = profile_root / "skills"
    messages.extend(_install_skill_files(skill_root))
    messages.append(_write_text(profile_root / "instructions.md", _profile_instructions(skill_root)))
    messages.append(_write_text(copilot_home / "agents" / f"{PROFILE_NAME}.agent.md", _copilot_agent(copilot_home, mcp_python)))
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
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    codex_home = _home_path(args.codex_home, "CODEX_HOME", ".codex")
    copilot_home = _home_path(args.copilot_home, "COPILOT_HOME", ".copilot")

    messages: list[str] = []
    if args.target in ("all", "codex"):
        if args.uninstall:
            messages.extend(uninstall_codex(codex_home))
        else:
            messages.extend(install_codex(codex_home, args.mcp_python))

    if args.target in ("all", "copilot"):
        if args.uninstall:
            messages.extend(uninstall_copilot(copilot_home))
        else:
            messages.extend(install_copilot(copilot_home, args.mcp_python))

    for message in messages:
        print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

