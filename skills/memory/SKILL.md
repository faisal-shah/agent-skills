---
name: memory
description: "Create and maintain persistent project memory that survives session restarts, compaction, and handoffs. Use when asked to initialize memory, save progress, resume after compaction, reconcile stale state, or reset memory in GitHub Copilot CLI or OpenAI Codex CLI."
---

# Memory Skill

Use this skill when the user wants durable project memory outside the chat transcript.

## Core Rules

- Durable state lives in `.memory/`, not in chat history.
- A task is not done until `.memory/progress.md` reflects reality.
- Put checkpoint gates inside the task board itself.
- Keep `AGENTS.md` tiny; keep real state in `.memory/*`.
- Do not rely on a last-second save before compaction or handoff.

## Platform Notes

- Use the same `.memory/` layout for GitHub Copilot CLI and OpenAI Codex CLI.
- Keep the repo-root `AGENTS.md` memory block short and idempotent.
- OpenAI Codex may not reload a newly written `AGENTS.md` until the next session. After `memory init`, `memory reconcile`, or any loader-block change, immediately read `.memory/context.md`, `.memory/progress.md`, and `.memory/lessons.md` yourself and continue from them.
- Do not auto-read `.memory/plan.md` on every restart. Use it only when you need original intent or reference material.

## Directory Layout

```
<project-root>/
  AGENTS.md              ← short loader block for compatible agents
  .memory/
    config.yml           ← strategy + checkpoint metadata
    plan.md              ← compressed frozen plan
    reference.md         ← optional detailed specs or large tables
    context.md           ← project overview, architecture, stack, decisions
    progress.md          ← resume point, phased tasks, checkpoint gates
    lessons.md           ← gotchas, patterns, decisions, checkpoint log
```

### `.memory/config.yml`

```yaml
memory_version: 2
location: in-place    # or "new-directory"
git: existing         # or "new", "none"
created: 2026-03-25
last_checkpoint: 2026-03-25T18:40:00Z
```

## Commands

### `memory init` — bootstrap durable memory

**Goal:** seed a compact, durable project state that a fresh agent can use in minutes.

**Steps:**

1. **Gather source plan material** in this order:
   - a file/path the user explicitly gave you
   - the task list or plan from the current chat
   - repo docs such as `README`, `TODO`, issue text, or design notes
   - any session plan file the current tool exposes
   If you still have no plan, ask the user for a short task list first.

2. **Detect environment and propose defaults:**
   - Is CWD already a git repo? Default to `in-place + existing git`.
   - Is CWD clearly a project directory but not yet a repo? Default to
     `in-place + new git` or `in-place + none`.
   - Is CWD just a scratch folder? Default to `new directory + new git`.
   Always confirm the proposed location and git strategy before proceeding.

3. **Choose target root:**
   - **In-place:** work in CWD.
   - **New directory:** derive a short kebab-case name from the plan topic,
     propose `./<name>/`, create it, then work there.

4. **Set up git if requested:**
   - `existing`: verify the repo and warn if there are uncommitted changes.
   - `new`: run `git init` in the target root.
   - `none`: skip git work.

5. **Create `.memory/` and seed files:**
   - Write `.memory/config.yml`.
   - Write `.memory/plan.md` as a **compressed frozen plan**.
     Keep it under roughly 120 lines. Preserve goals, architecture, phases,
     and major constraints. Move large tables, API details, pin maps, or
     long reference notes into `.memory/reference.md`.
   - Write `.memory/context.md` from the plan:
     overview, architecture, tech stack, invariants, and key decisions.
   - Write `.memory/progress.md` as a **phase board**, not a journal:
     - Add `## Resume Here` with exactly one next task and one next action.
     - Split work into 2–6 phases when possible.
     - Give tasks stable IDs such as `P1-T1`, `P2-T3`.
     - Add a **gate task** after every phase, or every 2–4 tasks if phases
       are unclear.
     - Gate text should be explicit: `GATE-P1 — update .memory/* before
       Phase 2`.
   - Write `.memory/lessons.md` with gotchas, patterns, decisions, and a
     checkpoint log.

6. **Create or update repo-root `AGENTS.md`:**
   - If no `AGENTS.md` exists, create one.
   - If it exists, replace the existing memory block if marker comments are
     present; otherwise append a single memory block.
   - Use these markers so repeated `memory init` is idempotent:
     `<!-- memory-skill:start -->` and `<!-- memory-skill:end -->`.
   - Keep the block short. It should point agents to `.memory/context.md`,
     `.memory/progress.md`, and `.memory/lessons.md`, and it should restate
     the checkpoint rule.

7. **Current-session safety step:** after writing or updating `AGENTS.md`,
   immediately read `.memory/context.md`, `.memory/progress.md`, and
   `.memory/lessons.md` yourself. Do not assume the current session will
   reload new instructions automatically.

8. **Initial commit (optional but recommended if git is enabled):** commit the seeded memory files, especially when creating a new repo or handing work off to another session.

9. **Tell the user:** report the chosen root, strategy, and next task. If a
   new directory was created, tell them the exact `cd` path to use later.

### `memory update` — checkpoint after work

Run this automatically after each completed task, each gate, each resolved
blocker, each major decision, and before any risky refactor or manual
compaction command.

**Steps:**

1. Read `.memory/config.yml`, `.memory/progress.md`, and `.memory/lessons.md`.
2. Inspect repo reality since the last checkpoint:
   - if git is enabled, use `git status --short` and optionally
     `git diff --stat`
   - otherwise inspect the files you just changed and the work you finished
3. If `.memory/` is already stale, repair it first instead of layering a
   new checkpoint onto wrong state.
4. Update `.memory/progress.md`:
   - mark completed tasks with dates
   - advance `## Resume Here` to the next unfinished task
   - update `Next action` with the next concrete command or file to touch
   - mark the relevant gate complete when the phase checkpoint is done
   - if more than 2 regular tasks were completed since the last checkpoint,
     add a warning note that checkpoint cadence slipped
5. Update `.memory/lessons.md` with new gotchas, patterns, and decisions.
   Append a row to the checkpoint log with the date and the number of tasks
   completed since the previous checkpoint.
6. Update `.memory/context.md` only if architecture, tooling, or invariants
   changed.
7. Update `last_checkpoint` in `.memory/config.yml`.
8. **If git is enabled, commit when it matters:**
   - phase boundary or gate completed
   - user asked to save or commit
   - before risky edits, reset, or handoff
   - end of session after meaningful progress
   A commit is recommended, but the hard requirement is that `.memory/*`
   must be updated before moving on.

**Keep it lean:** `progress.md` should stay scannable. Collapse old done
tasks into one-line summaries if the file grows beyond roughly 80 lines.

### `memory status` — read-only snapshot

Read `.memory/config.yml`, `.memory/context.md`, `.memory/progress.md`, and
`.memory/lessons.md`, then summarize:

- current focus and next task
- active blockers
- important decisions/gotchas
- whether `.memory/` appears stale relative to repo reality

Do **not** modify files in `memory status`.

### `memory reconcile` — repair stale memory

Use this when the repo state and `.memory/*` disagree: after compaction, restart, partial crashes, manual file edits, or missed checkpoints.

**Steps:**

1. Read all `.memory/` files.
2. Inspect actual repo state:
   - changed files
   - tests run or still pending
   - completed work not reflected in `progress.md`
   - tasks marked in progress even though the code is already done
3. Rewrite `.memory/progress.md` to match reality.
   Update `Resume Here`, completed task markers, gates, and notes.
4. Add a reconciliation note to `.memory/lessons.md` with what drift was
   found and how it was repaired.
5. Update `.memory/context.md` if the real architecture changed.
6. Update `.memory/config.yml:last_checkpoint`.
7. If git is enabled, commit when the user asked for a save or when a clean
   handoff matters.

### `memory reset` — recover from a bad memory state

Use this only when `.memory/` is unusable and reconciliation is not the
right fix.

- If git is enabled, tag or otherwise preserve the current state before
  resetting.
- Keep `.memory/plan.md` and `.memory/reference.md`.
- Rebuild `.memory/progress.md`, `.memory/lessons.md`, and any stale loader
  block from the preserved plan plus current repo state.
- Warn before destructive reset when no git history exists.

## File Formats

### `.memory/context.md`

```markdown
# Project Context

## Overview
[what this project is and why it exists]

## Architecture
[major components, boundaries, and data flow]

## Tech Stack
[languages, frameworks, tools, versions that matter]

## Invariants
[rules that must remain true]

## Key Decisions
| Decision | Rationale | Date |
|----------|-----------|------|
```

### `.memory/progress.md`

```markdown
# Progress

> **RULE: After each completed task or gate, update this file before moving
> on. Durable state lives here, not in chat history.**

## Resume Here
- Next task: P1-T2
- Next action: implement config loading in `src/config.py`
- Last checkpoint: 2026-03-25 18:40 UTC

## Phase 1 — Skeleton
- [x] P1-T1 create CLI parser skeleton (done 2026-03-25)
- [ ] P1-T2 add config loading
- [ ] GATE-P1 — update `.memory/*` before Phase 2

## Phase 2 — Validation
- [ ] P2-T1 add smoke tests
- [ ] P2-T2 document CLI flags
- [ ] GATE-P2 — update `.memory/*` before Phase 3

## Blocked
- None.

## Notes
- Keep tasks small enough that a missed checkpoint loses little work.
```

### `.memory/lessons.md`

```markdown
# Lessons Learned

## Gotchas
- [non-obvious behavior or footgun]

## Patterns
- [recurring codebase convention]

## Decisions
| Decision | Rationale | Date |
|----------|-----------|------|

## Checkpoint Log
| Date | Tasks Since Last Checkpoint | Notes |
|------|-----------------------------|-------|
```

### `.memory/plan.md`

Compressed frozen plan. Never turn this into a running journal. Keep it
short enough to consult on demand. Large reference material belongs in
`.memory/reference.md`.

## `AGENTS.md` Block Template

Use this exact block, bounded by markers, when creating or updating the
loader instructions:

```markdown
<!-- memory-skill:start -->
# Project Memory

Before doing work, read `.memory/context.md`, `.memory/progress.md`, and
`.memory/lessons.md`. Read `.memory/plan.md` or `.memory/reference.md` only
when you need original intent or detailed reference material.

A task is not done until `.memory/progress.md` matches reality. After each
completed task or gate, update `.memory/progress.md` and `.memory/lessons.md`.
Update `.memory/context.md` only when architecture or invariants change.

If `.memory/` disagrees with the repo state, reconcile memory before coding.
<!-- memory-skill:end -->
```

## Worked Example

**User asks:** “Set up durable memory for this existing CLI project so a new session can resume cleanly later.”

**Good behavior:**

1. Detect existing repo → propose `in-place + existing git`.
2. Build a compressed `.memory/plan.md` from the current chat and repo docs.
3. Create phased `progress.md` with gates:

```markdown
## Resume Here
- Next task: P1-T1
- Next action: create `src/cli.py` parser skeleton
- Last checkpoint: 2026-03-25 19:00 UTC

## Phase 1 — Skeleton
- [ ] P1-T1 create parser skeleton
- [ ] P1-T2 add config loading
- [ ] GATE-P1 — update `.memory/*` before Phase 2
```

4. Append or replace the marked memory block in `AGENTS.md`.
5. Immediately read `.memory/context.md`, `.memory/progress.md`, and
   `.memory/lessons.md` again in the current session.

**Later, after finishing `P1-T1`:** run `memory update`, mark `P1-T1` done,
move `Resume Here` to `P1-T2`, record the checkpoint, and continue.

**If the next session finds changed code but stale memory:** run `memory reconcile` first, repair the task board, then continue from the new `Resume Here` section.

## Guidelines

- Prefer 2–6 phases over a flat 20-item list.
- Prefer explicit gate tasks over vague “update frequently” reminders.
- Prefer stable task IDs and one concrete next action.
- Replace old memory loader blocks in place; do not append duplicates.
- Describe what changed and why, not code listings.
- Prune aggressively; git history is the archive when git is enabled.
- If the user wants every checkpoint committed, obey that stricter rule.
