# playwright-cli

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for browser automation using the `playwright-cli` command-line interface.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md                          | yes | Full command reference for playwright-cli |
| references/request-mocking.md     | yes | Network interception and mock patterns |
| references/running-code.md        | yes | Executing arbitrary Playwright code |
| references/session-management.md  | yes | Multi-browser session management |
| references/storage-state.md       | yes | Cookie/localStorage/sessionStorage management |
| references/test-generation.md     | yes | Auto-generating Playwright test code |
| references/tracing.md             | yes | Capturing execution traces |
| references/video-recording.md     | yes | Recording browser sessions as video |
| README.md                         | no  | Human-facing usage notes (this file) |
| AGENTS.md                         | no  | AI context for developing this skill |
| install.sh                        | yes | Installs the skill (bash) |
| install.ps1                       | yes | Installs the skill (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/playwright-cli/install.sh                  # both Copilot and Codex
./skills/playwright-cli/install.sh --copilot        # Copilot only
./skills/playwright-cli/install.sh --skills-dir .github/skills
./skills/playwright-cli/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\playwright-cli\install.ps1
.\skills\playwright-cli\install.ps1 -Copilot
.\skills\playwright-cli\install.ps1 -SkillsDir C:\my\skills
.\skills\playwright-cli\install.ps1 -Uninstall
```

## Prerequisites

- `playwright-cli` (installed via the Copilot CLI Playwright MCP server or standalone)
- A supported browser (Chromium installed by default on first run)

## Quick Start

Ask the agent: *"open example.com and take a screenshot"*

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli screenshot --filename=example.png
playwright-cli close
```

## What the Skill Covers

1. Core commands: open, navigate, click, fill, type, select, upload
2. Screenshots and PDF generation
3. Keyboard and mouse control
4. Tab management
5. Cookie, localStorage, and sessionStorage management
6. Network request mocking and interception
7. DevTools: console, network logs, tracing, video recording
8. Multi-session browser management
9. Local file access (`file://` URLs)
10. Test code generation from interactions

## License

[MIT](../../LICENSE)
