# AGENTS.md — AI Context for memory skill

## What This Skill Is

An agent skill that teaches AI assistants how to create and maintain durable
project memory across session restarts, compaction, and handoffs. The primary
artifact is `SKILL.md`, which gets loaded when the skill triggers.

## Key Files

- `SKILL.md` — Main skill content. Covers `memory init`, `memory update`,
  `memory status`, `memory reconcile`, and `memory reset`.
- `README.md` — Human-facing install and compatibility notes.
- `FEEDBACK-checkpoint-enforcement.md` — Background on why the skill uses
  phase gates and structural checkpointing.

## Design Principles

1. **Durable state beats transcript state.** The skill should survive
   restart/compaction without depending on chat history.
2. **Structural checkpointing.** Advisory reminders are weak; gates must live
   inside `progress.md` itself.
3. **Short loader, rich memory files.** Keep the `AGENTS.md` memory block
   tiny and idempotent; keep actual project state in `.memory/*`.
4. **Compressed plans.** `plan.md` is a compact frozen reference, not a full
   transcript dump. Large reference material belongs in `reference.md`.
5. **Cross-agent compatibility.** The workflow should make sense for both
   GitHub Copilot CLI and OpenAI Codex CLI, including Codex's session-start
   instruction loading behavior.

## Testing Changes

Manual testing in a scratch repo:

```bash
# 1) Ask the agent to run: memory init
# Verify:
# - .memory/config.yml, plan.md, context.md, progress.md, lessons.md exist
# - progress.md includes Resume Here + phase gates
# - AGENTS.md contains exactly one marked memory block
#
# 2) Ask the agent to complete one synthetic task, then run: memory update
# Verify:
# - completed task is marked done
# - Resume Here advances to the next task
# - lessons.md checkpoint log gets a new row
#
# 3) Simulate drift (edit a repo file without updating .memory/), then run:
#    memory status
# Verify: drift is reported read-only
#
# 4) Then run: memory reconcile
# Verify: progress.md and lessons.md are repaired to match repo reality
```

## Style

- SKILL.md should stay imperative, concrete, and example-driven.
- Prefer short tables and compact templates over repeated prose.
- Keep the loader block tiny and the full SKILL.md under roughly 350 lines.
