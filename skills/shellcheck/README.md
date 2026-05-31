# shellcheck

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for linting shell scripts with ShellCheck and PowerShell scripts with
PSScriptAnalyzer.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md   | yes | Scope rules, analyzer workflows, suppression guidelines |
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
- `PSScriptAnalyzer` — install with
  `Install-Module PSScriptAnalyzer -Scope CurrentUser`

ShellCheck does not lint PowerShell. PSScriptAnalyzer is the PowerShell
equivalent and is a separate module, not bundled with PowerShell.

## Quick Start

The skill activates automatically when the agent creates or edits deliverable
script files. It lints committed artifacts and skips ephemeral one-liners.

```bash
shellcheck -f gcc script.sh
```

```powershell
Invoke-ScriptAnalyzer -Path .\script.ps1
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-ScriptAnalyzer -Path .\script.ps1 -Fix
```

Use `-Fix` only for safe automatic fixes, then review the diff and re-run the
analyzer.

## What the Skill Covers

1. Scope rules for `.sh`, `.bash`, `.sh.template`, `.ps1`, `.psm1`, and `.psd1`
2. ShellCheck command flow and common fixes (SC2086, SC2155, SC2164, etc.)
3. Template file handling (`@@PLACEHOLDER@@` conventions)
4. PSScriptAnalyzer command flow, including recursive scans and safe `-Fix`
5. Severity triage and clean-results requirement
6. Suppression rules and best practices for both analyzers

## License

[MIT](../../LICENSE)
