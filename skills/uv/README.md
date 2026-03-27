# uv

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for using `uv` as the primary Python package and script runner — replacing pip,
python, and venv.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md              | yes | Quick reference, proxy/TLS, inline metadata, build backend |
| references/scripts.md | yes | Full guide to running scripts with uv |
| references/build.md   | yes | `uv_build` backend setup and project structure |
| README.md             | no  | Human-facing usage notes (this file) |
| AGENTS.md             | no  | AI context for developing this skill |
| install.sh            | yes | Installs the skill (bash) |
| install.ps1           | yes | Installs the skill (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/uv/install.sh                              # both Copilot and Codex
./skills/uv/install.sh --copilot                    # Copilot only
./skills/uv/install.sh --skills-dir .github/skills
./skills/uv/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\uv\install.ps1
.\skills\uv\install.ps1 -Copilot
.\skills\uv\install.ps1 -SkillsDir C:\my\skills
.\skills\uv\install.ps1 -Uninstall
```

## Prerequisites

- [uv](https://docs.astral.sh/uv/) — install via `curl -LsSf https://astral.sh/uv/install.sh | sh`
  or `pip install uv`

## Quick Start

```bash
uv run script.py                   # Run a script (auto-installs deps)
uv run --with requests script.py   # Run with ad-hoc dependency
uv add requests                    # Add dependency to project
uv init --script foo.py            # Create script with inline metadata
```

## What the Skill Covers

1. Running scripts with `uv run`
2. Ad-hoc and inline script dependencies (PEP 723)
3. Corporate proxy and TLS configuration
4. `uv_build` build backend for pure Python packages
5. Dependency locking and reproducibility
6. Executable scripts with shebang

## License

[MIT](../../LICENSE)
