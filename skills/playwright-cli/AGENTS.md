# AGENTS.md — AI Context for playwright-cli skill

## What This Skill Is

A comprehensive command reference for `playwright-cli`, the CLI interface to
Playwright browser automation. The agent uses this to drive browsers from the
terminal — navigating pages, filling forms, taking screenshots, scraping data,
and managing browser sessions.

## Key Files

- `SKILL.md` — Full command reference (core, navigation, keyboard, mouse, tabs,
  storage, network, DevTools, sessions, safety, and configuration)
- `scripts/repair-windows-playwright-cli.ps1` — fail-closed compatibility
  repair for hidden Playwright daemon and cleanup processes on Windows
- `scripts/doctor.ps1` / `doctor.sh` — native runtime and PATH validation
- `scripts/smoke-test.ps1` / `smoke-test.sh` — network-free lifecycle checks
- `references/platform-setup.md` — native Windows, Linux, and WSL setup
- `references/request-mocking.md` — Network interception and mocking patterns
- `references/running-code.md` — Executing arbitrary Playwright code via `run-code`
- `references/session-management.md` — Multi-session browser management
- `references/storage-state.md` — Cookie, localStorage, sessionStorage management
- `references/test-generation.md` — Generating Playwright test code from interactions
- `references/tracing.md` — Trace capture for debugging
- `references/video-recording.md` — WebM video recording of sessions
- `references/element-attributes.md` — DOM attribute inspection
- `references/playwright-tests.md` — Playwright test runner attach/debug flow

## Design Principles

1. **Command reference, not tutorial.** SKILL.md is a lookup table of commands,
   not a narrative guide. The agent should find what it needs in seconds.
2. **Examples over descriptions.** Every command has a runnable example.
3. **References for deep topics.** Complex workflows (mocking, sessions, storage)
   are in separate reference files to keep SKILL.md scannable.
4. **Cross-platform.** `playwright-cli` works on Linux, macOS, WSL, and Windows.
   Keep shell syntax explicit and do not imply that WSL inherits Windows SSO.
5. **Safe by construction.** Fresh snapshots precede actions, consequential
   clicks require authorization, uncertain submissions are never replayed, and
   authentication artifacts never enter source control.
6. **No transient terminals.** The Windows installer keeps the upstream CLI's
   detached background architecture while hiding daemon/browser processes,
   invoking `taskkill.exe` without a shell, and disabling the crashing update
   notifier only on Node.js 24+.

## Testing Changes

```bash
# POSIX/WSL: verify an isolated skill install and lint shell code.
tmpdir="$(mktemp -d)"
./skills/playwright-cli/install.sh --skills-dir "$tmpdir"
test -f "$tmpdir/playwright-cli/SKILL.md"
test -f "$tmpdir/playwright-cli/scripts/repair-windows-playwright-cli.ps1"
shellcheck skills/playwright-cli/install.sh skills/playwright-cli/scripts/*.sh
rm -rf "$tmpdir"

# Windows: validate and smoke-test the repair.
Invoke-ScriptAnalyzer -Path .\skills\playwright-cli\install.ps1
Invoke-ScriptAnalyzer -Path .\skills\playwright-cli\scripts\doctor.ps1
Invoke-ScriptAnalyzer -Path .\skills\playwright-cli\scripts\repair-windows-playwright-cli.ps1
.\skills\playwright-cli\scripts\repair-windows-playwright-cli.ps1 -Check
```

## Style

- SKILL.md: command blocks grouped by category, minimal prose.
- References: one topic per file, code-first with brief explanations.
