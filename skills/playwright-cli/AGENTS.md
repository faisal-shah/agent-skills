# AGENTS.md — AI Context for playwright-cli skill

## What This Skill Is

A comprehensive command reference for `playwright-cli`, the CLI interface to
Playwright browser automation. The agent uses this to drive browsers from the
terminal — navigating pages, filling forms, taking screenshots, scraping data,
and managing browser sessions.

## Key Files

- `SKILL.md` — Full command reference (core, navigation, keyboard, mouse, tabs,
  storage, network, DevTools, sessions, configuration)
- `references/request-mocking.md` — Network interception and mocking patterns
- `references/running-code.md` — Executing arbitrary Playwright code via `run-code`
- `references/session-management.md` — Multi-session browser management
- `references/storage-state.md` — Cookie, localStorage, sessionStorage management
- `references/test-generation.md` — Generating Playwright test code from interactions
- `references/tracing.md` — Trace capture for debugging
- `references/video-recording.md` — WebM video recording of sessions

## Design Principles

1. **Command reference, not tutorial.** SKILL.md is a lookup table of commands,
   not a narrative guide. The agent should find what it needs in seconds.
2. **Examples over descriptions.** Every command has a runnable example.
3. **References for deep topics.** Complex workflows (mocking, sessions, storage)
   are in separate reference files to keep SKILL.md scannable.
4. **Cross-platform.** `playwright-cli` works on Linux, macOS, WSL, and Windows.
   WSL-specific notes for `file://` paths are included.

## Testing Changes

```bash
# Verify the skill installs cleanly
./skills/playwright-cli/install.sh --skills-dir /tmp/skills-test
ls /tmp/skills-test/playwright-cli/
# Should contain: SKILL.md, references/
rm -rf /tmp/skills-test
```

## Style

- SKILL.md: command blocks grouped by category, minimal prose.
- References: one topic per file, code-first with brief explanations.
