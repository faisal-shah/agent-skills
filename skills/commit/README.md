# commit

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for producing consistent git commit messages using Conventional Commits style.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md   | yes | Commit message format rules and workflow |
| README.md  | no  | Human-facing usage notes (this file) |
| AGENTS.md  | no  | AI context for developing this skill |
| install.sh | yes | Installs the skill (bash) |
| install.ps1| yes | Installs the skill (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/commit/install.sh                          # both Copilot and Codex
./skills/commit/install.sh --copilot                # Copilot only
./skills/commit/install.sh --skills-dir .github/skills
./skills/commit/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\commit\install.ps1
.\skills\commit\install.ps1 -Copilot
.\skills\commit\install.ps1 -SkillsDir C:\my\skills
.\skills\commit\install.ps1 -Uninstall
```

## Prerequisites

- Git

## Quick Start

Ask the agent: *"commit"* or *"commit the auth changes"*

The skill produces messages like:
```
feat(auth): add JWT token refresh endpoint
fix(parser): handle empty input without panic
docs: update installation guide for Windows
```

## What the Skill Covers

1. Conventional Commits format (`type(scope): summary`)
2. Allowed type prefixes (`feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `perf`)
3. When to include a body vs subject-only
4. File-scoping: committing only specified files
5. Ambiguity handling: asking the user when files are unclear

## License

[MIT](../../LICENSE)
