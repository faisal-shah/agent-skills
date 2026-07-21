# build123d Profile

The build123d profile installs a mode-scoped MCP server and workflow files for CAD modeling and drawing tasks.

Installed files:

| Agent | File |
|-------|------|
| Codex | `~/.codex/build123d.config.toml` |
| Codex | `~/.codex/profiles/build123d/instructions.md` |
| Codex | `~/.codex/profiles/build123d/skills/b123d-modeling/SKILL.md` |
| Codex | `~/.codex/profiles/build123d/skills/b123d-drawing/SKILL.md` |
| Codex | `~/.codex/profiles/build123d/viewer/live_viewer_pyvista.py` (POSIX) |
| Copilot | `~/.copilot/agents/build123d.agent.md` |
| Copilot | `~/.copilot/profiles/build123d/instructions.md` |
| Copilot | `~/.copilot/profiles/build123d/skills/b123d-modeling/SKILL.md` |
| Copilot | `~/.copilot/profiles/build123d/skills/b123d-drawing/SKILL.md` |
| Copilot | `~/.copilot/profiles/build123d/viewer/live_viewer_pyvista.py` (POSIX) |
| Claude Code | `~/.claude/profiles/build123d/.claude-plugin/plugin.json` |
| Claude Code | `~/.claude/profiles/build123d/.mcp.json` |
| Claude Code | `~/.claude/profiles/build123d/agents/build123d.md` |
| Claude Code | `~/.claude/profiles/build123d/skills/b123d-modeling/SKILL.md` |
| Claude Code | `~/.claude/profiles/build123d/skills/b123d-drawing/SKILL.md` |
| Claude Code | `~/.claude/profiles/build123d/viewer/live_viewer_pyvista.py` (POSIX) |

## Claude Code

Claude Code has no `--profile`. The equivalent is a **plugin directory**: one
folder holding the MCP server (`.mcp.json`), the profile instructions (a subagent
in `agents/`), and the two workflow skills. `model: opus` on the subagent stands
in for Codex's `model_reasoning_effort = "xhigh"`.

It is installed to `~/.claude/profiles/build123d` — deliberately **not**
`~/.claude/skills` or `~/.claude/plugins`, both of which load in every session. A
Codex or Copilot profile is inert until selected, and the Claude port keeps that
property by being loaded per launch:

```bash
claude --plugin-dir ~/.claude/profiles/build123d --agent build123d
```

Upstream ships the two workflow files without YAML frontmatter, since Codex and
Copilot reference them by absolute path. Claude Code selects skills by
`description`, so the installer derives frontmatter from each file's H1 and
opening paragraph — derived rather than hand-written, so it tracks upstream
wording. Verify a generated profile with `claude plugin validate <dir>`.

The workflow files are sourced from the installed `build123d-mcp` package during installation. The installer installs the server from the `build123d-mcp` main branch (which provides the live session viewer) as a persistent `uv` tool, and the generated config launches that installed executable directly:

```text
uv tool install --force --python 3.12 git+https://github.com/pzfreo/build123d-mcp@main
```

Launching the installed executable avoids the ~1.5 s per-launch git re-resolution of `uv tool run --from git+...`, which raced MCP-host startup timeouts and intermittently left the server unavailable on session resume. Re-run the installer to update to a newer `main`.

Launch examples:

```bash
codex --profile build123d
copilot --agent build123d
claude --plugin-dir ~/.claude/profiles/build123d --agent build123d
```

On native Windows the generated config launches the server with `--in-process`:
under the Codex and Copilot CLIs the worker subprocess never starts (the CLI's
stdio pipes break the `multiprocessing` spawn handshake), so the CAD session runs
in the server process instead. This trades the worker's crash containment and
per-operation timeouts for a server that works. POSIX hosts keep the isolated
worker and the live viewer.

Optional launch helpers:

| Helper | Command |
|--------|---------|
| `codex-build123d` | `codex --profile build123d` |
| `copilot-build123d` | `copilot --agent build123d` |
| `claude-build123d` | `claude --plugin-dir ~/.claude/profiles/build123d --agent build123d` |
| `build123d-viewer` | open the live 3D viewer (see below) |

Install them with `.\install.ps1 -InstallPowerShellAliases` on Windows or
`./install.sh --install-shell-aliases` on Linux, macOS, or WSL. They are not
installed unless that flag is provided.

## Live viewer (POSIX)

On POSIX hosts (Linux, macOS, WSL) the server is launched so each instance binds
its own live-viewer Unix socket at `/tmp/build123d-mcp.<pid>.sock`. Any number of
Codex and Copilot agents can run at once without contending for a socket. The
viewer streams the session's geometry to an interactive, rotatable pyvista window
that updates after every model change, while the agent keeps driving the tools.

To watch a session:

1. Ask the running agent for its viewer socket path (it reads the path from its
   own server process), or let the viewer auto-pick the newest socket.
2. Open the window:

   ```bash
   build123d-viewer                     # newest /tmp/build123d-mcp.*.sock
   build123d-viewer /tmp/build123d-mcp.12345.sock   # a specific session
   ```

`build123d-viewer` runs `viewer/live_viewer_pyvista.py` through `uv`, which pulls
pyvista and trimesh on demand. Override the socket location for a session with the
`BUILD123D_VIEWER_SOCKET` environment variable, or disable the socket entirely at
install time with `--no-viewer`. The viewer is not available on native Windows
(the server needs an `AF_UNIX` socket), where the socket flag is omitted.
