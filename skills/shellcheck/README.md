# shellcheck

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for linting shell scripts with shellcheck, fixing warnings, and validating correctness.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md   | yes | Scope rules, warning fix table, suppression guidelines |
| README.md  | no  | Human-facing usage notes (this file) |
| AGENTS.md  | no  | AI context for developing this skill |
| install.sh | yes | Installs the skill (bash) |
| install.ps1| yes | Installs the skill (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/shellcheck/install.sh                      # both Copilot and Codex
./skills/shellcheck/install.sh --copilot            # Copilot only
./skills/shellcheck/install.sh --skills-dir .github/skills
./skills/shellcheck/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\shellcheck\install.ps1
.\skills\shellcheck\install.ps1 -Copilot
.\skills\shellcheck\install.ps1 -SkillsDir C:\my\skills
.\skills\shellcheck\install.ps1 -Uninstall
```

## Prerequisites

- `shellcheck` — install via `pip install shellcheck-py` (no sudo needed)
  or `sudo apt install shellcheck`

## Quick Start

The skill activates automatically when the agent creates or edits `.sh` files.
It lints deliverable scripts (committed artifacts) and skips ephemeral one-liners.

```bash
shellcheck -f gcc script.sh
```

## What the Skill Covers

1. Scope rules: what to lint vs skip
2. Common warning fixes (SC2086, SC2155, SC2164, etc.)
3. Template file handling (`@@PLACEHOLDER@@` conventions)
4. Severity triage (error → warning → info/style)
5. Suppression rules and best practices
6. Useful shellcheck flags (`-x`, `-s bash`, `-f diff`)

## License

[MIT](../../LICENSE)
