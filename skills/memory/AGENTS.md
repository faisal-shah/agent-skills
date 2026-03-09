# AGENTS.md — AI Context for memory skill

## What This Skill Is

An agent skill that teaches AI assistants how to create and maintain persistent
memory files across sessions and compactions. The primary artifact is `SKILL.md`
which gets loaded into the AI's context when the skill triggers.

## Key Files

- `SKILL.md` — Main skill content. Loaded by the agent framework. Covers four
  commands: `memory init`, `memory update`, `memory status`, `memory reset`.

## Design Principles

1. **Survive compaction** — Copilot CLI compacts at ~95% context with no warning.
   The memory skill ensures the agent can resume from `.memory/` files without
   any context from the previous session.

2. **Frequent updates, not just at session end** — The skill instructs agents to
   checkpoint after each task, blocker resolution, or key decision. This
   minimizes lost work when compaction or disconnection occurs.

3. **Lean files** — `progress.md` should stay under ~80 lines. It gets loaded
   every session, so bloat costs tokens. Completed tasks become one-line
   `[x]` entries; collapse old done items when the file grows.

4. **Describe what and why, not how** — Memory files should not duplicate code.
   They capture decisions, gotchas, and architecture — things an agent can't
   infer from the codebase alone.

5. **User confirms strategy** — The skill proposes sensible defaults for
   location and git strategy, but always asks the user before proceeding.

## Testing Changes

Manual testing:

```bash
# In a scratch directory, ask the agent to run: memory init
# Verify:
# - .memory/ directory created with 5 files
# - AGENTS.md created/updated with memory loader block
# - config.yml reflects chosen strategies
#
# Then: memory update
# Verify: progress.md and lessons.md updated
#
# Then: memory status
# Verify: read-only, no file modifications
```

## Style

- SKILL.md: imperative, step-by-step instructions. The agent follows these
  literally, so be precise about file formats and field names.
- Keep the SKILL.md under 350 lines.
