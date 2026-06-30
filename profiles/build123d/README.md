# build123d Profile

The build123d profile installs a mode-scoped MCP server and workflow files for CAD modeling and drawing tasks.

Installed files:

| Agent | File |
|-------|------|
| Codex | `~/.codex/build123d.config.toml` |
| Codex | `~/.codex/profiles/build123d/instructions.md` |
| Codex | `~/.codex/profiles/build123d/skills/b123d-modeling/SKILL.md` |
| Codex | `~/.codex/profiles/build123d/skills/b123d-drawing/SKILL.md` |
| Copilot | `~/.copilot/agents/build123d.agent.md` |
| Copilot | `~/.copilot/profiles/build123d/instructions.md` |
| Copilot | `~/.copilot/profiles/build123d/skills/b123d-modeling/SKILL.md` |
| Copilot | `~/.copilot/profiles/build123d/skills/b123d-drawing/SKILL.md` |

The workflow files are sourced from the installed `build123d-mcp` package during installation. The MCP server is launched with:

```text
uv tool run --python 3.12 build123d-mcp@latest
```

Launch examples:

```bash
codex --profile build123d
copilot --agent build123d
```

Optional launch helpers:

| Helper | Command |
|--------|---------|
| `codex-build123d` | `codex --profile build123d` |
| `copilot-build123d` | `copilot --agent build123d` |

Install them with `.\install.ps1 -InstallPowerShellAliases` on Windows or
`./install.sh --install-shell-aliases` on Linux, macOS, or WSL. They are not
installed unless that flag is provided.
