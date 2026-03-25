# memory

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for creating and maintaining **durable project memory** that survives session
restarts, compaction, and handoffs in **GitHub Copilot CLI** and **OpenAI
Codex CLI**.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | **yes** | Main skill file loaded by compatible agents |
| `README.md` | no | Human-facing usage notes |
| `AGENTS.md` | no | AI context for developing this skill |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/memory/install.sh                               # user-level: ~/.copilot/skills + ~/.codex/skills
./skills/memory/install.sh --copilot
./skills/memory/install.sh --codex
./skills/memory/install.sh --skills-dir .github/skills   # Copilot repo-local skill
./skills/memory/install.sh --skills-dir .agents/skills   # Codex repo-local skill
./skills/memory/install.sh /path/to/skills               # custom path
./skills/memory/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\memory\install.ps1                                # user-level: ~/.copilot/skills + ~/.codex/skills
.\skills\memory\install.ps1 -Copilot
.\skills\memory\install.ps1 -Codex
.\skills\memory\install.ps1 -SkillsDir .github\skills     # Copilot repo-local skill
.\skills\memory\install.ps1 -SkillsDir .agents\skills     # Codex repo-local skill
.\skills\memory\install.ps1 -Uninstall
```

## Prerequisites

None. The memory skill is instruction-only.

## Quick Start

Natural-language prompts that should trigger this skill:

```text
memory init
memory update
memory status
memory reconcile
memory reset
```

## What Changed in This Version

- **Phase boards + gate tasks:** `progress.md` is structured so checkpoints
  are part of the task list, not a side note.
- **`Resume Here` section:** a fresh agent gets one next task and one next
  action instead of re-parsing a long plan.
- **Compressed `plan.md`:** large specs move to `reference.md` so durable
  memory stays small.
- **Stale-state repair:** `memory reconcile` repairs `.memory/*` when repo
  reality and memory drift apart.
- **Short loader block:** repo-root `AGENTS.md` stays small and idempotent,
  which is friendlier to both Copilot and Codex.

## How It Works

The skill creates durable files in the project root:

```text
<project-root>/
├── AGENTS.md         ← short loader block for compatible agents
└── .memory/
    ├── config.yml    ← strategy + checkpoint metadata
    ├── plan.md       ← compressed frozen plan
    ├── reference.md  ← optional large reference material
    ├── context.md    ← overview, architecture, stack, invariants
    ├── progress.md   ← resume point, phased tasks, checkpoint gates
    └── lessons.md    ← gotchas, patterns, decisions, checkpoint log
```

## Agent Compatibility Notes

- **GitHub Copilot CLI:** project-local skills live in `.github/skills/`;
  personal skills live in `~/.copilot/skills/`.
- **OpenAI Codex CLI:** project-local skills live in `.agents/skills/`; the
  repo-level `AGENTS.md` loader block reinforces the workflow on restart.
- **Codex session behavior:** newly written `AGENTS.md` content may not be
  picked up until a new session starts, so the skill explicitly tells the
  agent to read `.memory/context.md`, `.memory/progress.md`, and
  `.memory/lessons.md` again in the current session.

## Recommended Usage Pattern

1. Run `memory init` once you have a real plan.
2. Work one small task at a time.
3. Run `memory update` after each completed task or gate.
4. If repo state and `.memory/*` drift apart, run `memory reconcile` before
   doing more implementation work.
5. Use `memory status` for a read-only restart summary.

## License

[MIT](../../LICENSE)
