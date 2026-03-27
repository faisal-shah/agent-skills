# mermaid

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for creating and validating Mermaid diagrams with the official Mermaid CLI.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md           | yes | Workflow guide and validation instructions |
| tools/validate.sh  | yes | Validates `.mmd` files with mmdc + ASCII preview |
| README.md          | no  | Human-facing usage notes (this file) |
| AGENTS.md          | no  | AI context for developing this skill |
| install.sh         | yes | Installs the skill (bash) |
| install.ps1        | yes | Installs the skill (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/mermaid/install.sh                         # both Copilot and Codex
./skills/mermaid/install.sh --copilot               # Copilot only
./skills/mermaid/install.sh --skills-dir .github/skills
./skills/mermaid/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\mermaid\install.ps1
.\skills\mermaid\install.ps1 -Copilot
.\skills\mermaid\install.ps1 -SkillsDir C:\my\skills
.\skills\mermaid\install.ps1 -Uninstall
```

## Prerequisites

- Node.js + npm (for `npx`)
- First run downloads a headless Chromium via Puppeteer

## Quick Start

Ask the agent: *"create a mermaid diagram of the authentication flow"*

The skill workflow:
1. Draft diagram in a standalone `diagram.mmd`
2. Validate with `./tools/validate.sh diagram.mmd`
3. Fix any errors
4. Copy the validated block into the target Markdown file

## What the Skill Covers

1. Mermaid CLI validation via `npx @mermaid-js/mermaid-cli`
2. ASCII preview via `beautiful-mermaid`
3. Standalone-file-first workflow to avoid embedding broken diagrams

## License

[MIT](../../LICENSE)
