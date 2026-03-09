# memory

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
that teaches AI coding assistants how to bootstrap **persistent memory files**
that survive context compactions and session restarts.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | **yes** | Main skill file — loaded by the agent framework |
| `README.md` | no | This file (repo documentation only) |
| `AGENTS.md` | no | AI context for developing the skill itself |

## Installation

```bash
# From the monorepo root
./install.sh ~/.copilot/skills              # installs all skills

# Or just this skill
./skills/memory/install.sh ~/.copilot/skills

# Uninstall
./skills/memory/install.sh --uninstall ~/.copilot/skills
```

## Prerequisites

None — the memory skill is framework-agnostic and has no external dependencies.

## Quick Start

Once installed, use natural language commands with your AI assistant:

```
memory init       — set up persistent memory for a project
memory update     — checkpoint current state after a milestone
memory status     — read-only overview of memory state
memory reset      — recover from bad state (preserves plan)
```

## What the Skill Covers

1. **`memory init`** — Bootstrap memory for a project with environment detection,
   location strategy (in-place vs new directory), and git strategy (none, existing, new)
2. **`memory update`** — Checkpoint progress, lessons learned, and context changes
3. **`memory status`** — Read-only overview of current memory state
4. **`memory reset`** — Recover from bad state while preserving the original plan

## How It Works

The skill creates a `.memory/` directory with structured files:

```
<project-root>/
├── AGENTS.md         ← auto-loaded by Copilot CLI (memory loader block appended)
└── .memory/
    ├── config.yml    ← chosen strategies
    ├── plan.md       ← frozen original plan (reference only)
    ├── context.md    ← project overview, architecture, tech stack
    ├── progress.md   ← task list, current focus, next steps
    └── lessons.md    ← gotchas, patterns, decisions
```

On session restart, the agent reads `.memory/` files (via the AGENTS.md loader
block) and picks up where it left off.

## License

[MIT](../../LICENSE)
