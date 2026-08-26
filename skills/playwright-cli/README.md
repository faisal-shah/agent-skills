# playwright-cli

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for browser automation using the `playwright-cli` command-line interface.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md                          | yes | Full command reference for playwright-cli |
| scripts/doctor.ps1 / doctor.sh    | yes | Detect stale Node, missing CLI, unsafe TLS, and mixed Windows/WSL installs |
| scripts/repair-windows-playwright-cli.ps1 | Windows | Idempotent no-popup compatibility repair |
| scripts/smoke-test.ps1 / smoke-test.sh | yes | Network-free browser lifecycle checks |
| references/platform-setup.md      | yes | Windows, Linux, and WSL setup and troubleshooting |
| references/element-attributes.md  | yes | Inspecting DOM attributes missing from snapshots |
| references/playwright-tests.md    | yes | Running and debugging Playwright tests through the CLI |
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
./skills/playwright-cli/install.sh --claude         # Claude Code only
./skills/playwright-cli/install.sh --skills-dir .github/skills
./skills/playwright-cli/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\playwright-cli\install.ps1
.\skills\playwright-cli\install.ps1 -Copilot
.\skills\playwright-cli\install.ps1 -Claude
.\skills\playwright-cli\install.ps1 -SkillsDir C:\my\skills
.\skills\playwright-cli\install.ps1 -Uninstall
```

## Prerequisites

- Node.js 20 or newer
- `playwright-cli` (`npm install --global @playwright/cli@latest`)
- A supported browser (Chromium installed by default on first run)

On Windows, the PowerShell skill installer also repairs upstream CLI process
launches that can open transient Windows Terminal tabs and suppresses a known
Node.js 24 update-notifier assertion. The repair is version-aware, idempotent,
and must be rerun after a global npm upgrade. Linux and WSL installations are
not modified.

Run the platform doctor before first use or after changing Node/npm:

```powershell
.\skills\playwright-cli\scripts\doctor.ps1
```

```bash
./skills/playwright-cli/scripts/doctor.sh
```

## Quick Start

Ask the agent: *"open example.com and take a screenshot"*

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli screenshot --filename=example.png
playwright-cli close
```

## What the Skill Covers

1. Safe snapshot-first browser workflows and evidence capture
2. Core navigation, form, keyboard, mouse, tab, and file commands
3. Screenshots, PDFs, traces, videos, and annotated user review
4. Network inspection, offline simulation, and request mocking
5. Isolated, persistent, attached, and concurrent browser sessions
6. Cookie, localStorage, sessionStorage, and authentication-state handling
7. Playwright test planning, generation, debugging, and healing
8. Windows, native Linux, and WSL setup with shell-correct examples
9. Windows no-popup process repair and lifecycle smoke testing

## License

[MIT](../../LICENSE)
