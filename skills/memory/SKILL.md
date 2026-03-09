---
name: memory
description: "Bootstrap persistent memory files that survive compactions and session restarts, with flexible location and git strategies"
---

# Memory Skill

Bootstrap and manage persistent memory files that maintain context across Copilot CLI session compactions and restarts. Supports multiple setup strategies — in-place or new directory, with or without git tracking.

## Workflow Overview

```
┌───────────────────────────┐     ┌──────────────────────────────────┐
│  Session 1: Planning      │     │  Session 2+: Grinding            │
│                           │     │                                  │
│  User + agent develop     │     │  cd <project-dir>                │
│  a plan (plan mode)       │     │  AGENTS.md auto-loads            │
│         │                 │     │  Agent reads .memory/*           │
│         ▼                 │     │  Picks up next task              │
│  "memory init"            │     │  Works...                        │
│  → detects environment    │     │  Updates .memory/progress.md     │
│  → asks location + git    │     │  Commits (if git enabled)        │
│  → seeds memory files     │     │                                  │
└───────────────────────────┘     └──────────────────────────────────┘
```

## Setup Strategies

`memory init` supports flexible setup along two independent axes:

### Location Strategy

| Strategy | When to use | What happens |
|----------|------------|--------------|
| **In-place** | Already in the project directory (existing codebase, repo, etc.) | Creates `.memory/` and `AGENTS.md` in CWD |
| **New directory** | Starting fresh, want an isolated workspace | Creates a new subdirectory, then sets up inside it |

### Git Strategy

| Strategy | When to use | What happens |
|----------|------------|--------------|
| **None** | Don't need version history, or managing git separately | No git operations at all |
| **Existing** | CWD is already a git repo | Commits memory files into the existing repo |
| **New** | Want a fresh repo for this project | Runs `git init`, then commits |

### Strategy Detection

During `memory init`, **auto-detect and propose defaults** based on environment:

```
Is CWD a git repo?
├─ YES → default: in-place + existing git
│        (CWD already has project structure)
└─ NO
   ├─ Does CWD contain project files? (src/, package.json, Makefile, etc.)
   │  └─ YES → default: in-place + new git (or none)
   └─ NO → default: new directory + new git
```

**Always confirm** the proposed strategy with the user before proceeding. Present it as a short summary:

> "I'll set up memory **in the current directory** using the **existing git repo**. Sound good?"

or

> "I'll create `./my-project/` with a **new git repo**. Sound good?"

The user can override any axis.

## Directory Structure

```
<project-root>/
  AGENTS.md              ← auto-loaded by Copilot CLI, contains memory instructions
  .memory/
    config.yml           ← records chosen strategies so update/reset know what to do
    plan.md              ← frozen original plan (reference, don't edit)
    context.md           ← project overview, architecture, tech stack, key decisions
    progress.md          ← task list with statuses, current focus, next steps
    lessons.md           ← gotchas, patterns discovered, decisions with rationale
```

### .memory/config.yml

Created during `memory init`. Records the chosen strategies so that `memory update`, `memory reset`, and the AGENTS.md instructions all behave correctly.

```yaml
location: in-place    # or "new-directory"
git: existing         # or "new", "none"
created: 2025-03-09
```

## Commands

### `memory init` — bootstrap memory for a project

The primary command. Sets up persistent memory files from the current session's plan.

**Steps:**

1. **Locate the plan.** Look for plan.md in the session state folder. If no plan exists, tell the user to develop one first (using plan mode) before initializing memory.

2. **Detect environment and propose strategy:**
   - Check if CWD is inside a git repo (`git rev-parse --git-dir`).
   - Check if CWD contains project files.
   - Apply the detection logic above to propose default location + git strategy.
   - **Ask the user** to confirm or override. Present both axes clearly.

3. **Set up the target directory:**

   **If new directory:**
   - Derive a short kebab-case name from the plan's topic/title.
   - Propose `./<derived-name>/` (relative to CWD). Use forward slashes — works on both Linux and Windows.
   - Create the directory: `mkdir -p <project-dir>`
   - All subsequent operations happen inside `<project-dir>`.

   **If in-place:**
   - All operations happen in CWD. No directory creation needed.

4. **Set up git (if applicable):**

   **If git strategy is "new":** `git init`
   **If git strategy is "existing":** verify repo is clean or warn about uncommitted changes.
   **If git strategy is "none":** skip.

5. **Create `.memory/` and seed files:**
   ```
   mkdir -p .memory
   ```
   - Write `.memory/config.yml` with the chosen strategies and date.
   - Copy the full plan verbatim to `.memory/plan.md` (frozen reference).
   - Extract project context (overview, architecture, tech stack, goals) into `.memory/context.md`.
   - Extract the task list into `.memory/progress.md`, formatted as a trackable checklist with status markers.
   - Create `.memory/lessons.md` with empty template sections.

6. **Create AGENTS.md** with the memory loader block (see template below). If AGENTS.md already exists, **append** the memory section rather than overwriting — the file may contain other project-specific instructions.

7. **Initial commit (if git enabled):**
   ```
   git add -A
   git commit -m "Initialize project memory"
   ```

8. **Tell the user:** print the full path and next steps. If a new directory was created, suggest `cd <project-dir>` for the next session.

### `memory update` (or "save progress") — checkpoint current state

The agent does this automatically after milestones, but the user can force it at any time. Also useful before manually running `/compact`.

**When to update (automatically, don't wait to be asked):**

- After completing a task or subtask
- After hitting and resolving a significant blocker
- After making a key decision that changes approach
- At minimum once per session, but prefer multiple small updates over one big dump

**The goal:** if the session dies unexpectedly right now, a fresh agent should be able to read `.memory/` and pick up within minutes, not hours. There is **no pre-compaction hook** in Copilot CLI — auto-compaction at ~95% context gives no warning — so frequent updates are the only reliable safeguard.

**Steps:**

1. Read `.memory/config.yml` to determine git strategy.
2. Read all `.memory/` files to understand prior state.
3. Review what was accomplished since the last update.
4. Update `.memory/progress.md`:
   - Mark completed tasks as done (with date).
   - Update current focus to reflect what's actively being worked on.
   - Add brief notes on partially-completed work (what's done, what remains).
   - Reorder/reprioritize next steps if needed.
5. Update `.memory/lessons.md` if any new gotchas or decisions arose.
6. Update `.memory/context.md` only if architecture or tech stack changed.
7. **If git is enabled**, commit:
   ```
   git add .memory/
   git commit -m "Update memory: <brief summary>"
   ```

**Keeping progress.md lean:** The file must stay scannable — it's loaded into context every session. Don't write a journal; write a status board. Completed tasks get a one-line `[x]` entry, not a paragraph. If the file exceeds ~80 lines, collapse older completed items into a single "N tasks completed" summary line.

### `memory status` — read-only overview

Read and summarize all memory files without modifying anything. Use this when restarting after a crash or process death to see where things stand before the agent starts working.

### `memory reset` — recover from a bad state

When the agent has gone off the rails. Resets progress and lessons while keeping context and the original plan.

**If git is enabled:**
```
git tag memory-archive-$(date +%Y%m%d-%H%M%S)
```

Reinitializes `.memory/progress.md` from the frozen plan and clears `.memory/lessons.md`. Context and config are preserved.

**If git is not enabled:** warn the user that the current state will be lost (no tag to fall back to), and ask for confirmation before proceeding.

## Memory File Formats

### .memory/context.md

```markdown
# Project Context

## Overview
[What this project is, why it exists, who it's for]

## Architecture
[Key components, how they fit together, data flow]

## Tech Stack
[Languages, frameworks, tools, versions that matter]

## Key Decisions
[Important architectural/design decisions and WHY they were made]
```

### .memory/progress.md

```markdown
# Progress

## Current Focus
[What we're actively working on RIGHT NOW — most important section after compaction]

## Tasks
- [x] Task 1 description (done YYYY-MM-DD)
- [x] Task 2 description (done YYYY-MM-DD)
- [ ] **>>> Task 3 description** ← in progress
- [ ] Task 4 description
- [ ] Task 5 description

## Blocked
[Anything stuck and why]

## Notes
[Any context about priorities, ordering, or scope changes vs. the original plan]
```

### .memory/lessons.md

```markdown
# Lessons Learned

## Gotchas
[Things that tripped us up — non-obvious behaviors, environment quirks, footguns]

## Patterns
[Conventions in this codebase, recurring structures, naming schemes]

## Decisions
| Decision | Rationale | Date |
|----------|-----------|------|
| [what we decided] | [why] | [when] |
```

### .memory/plan.md

Verbatim copy of the original plan. **Never edit this file.** It's the reference for what was originally intended. Compare against `progress.md` to see drift.

## AGENTS.md Template

When creating AGENTS.md (or appending to an existing one), use this block:

```markdown
# Project Memory

This project uses persistent memory files to maintain context across sessions and compactions.

## On Session Start / After Compaction

**Before doing any work**, read these files in order:

1. `.memory/context.md` — What this project is and how it's built
2. `.memory/progress.md` — Where we are and what to do next
3. `.memory/lessons.md` — What we've learned (don't repeat mistakes)

Then pick up the next incomplete task from progress.md and continue working.

## Updating Memory

Update `.memory/` files **frequently** — not just at session end. Update after:

- Completing a task or subtask
- Resolving a significant blocker
- Making a key decision that changes approach
- When the user says "update memory" or "save progress"

**The goal:** if this session dies right now, a fresh agent reads `.memory/` and picks up in minutes.

Steps:
1. Read `.memory/config.yml` to check if git is enabled
2. Update `.memory/progress.md` — mark tasks done, update current focus, note partial progress on in-flight work
3. Add new entries to `.memory/lessons.md` — any gotchas hit or decisions made
4. Update `.memory/context.md` only if architecture changed
5. If git is enabled: `git add .memory/ && git commit -m "Update memory: <summary>"`

**Keep it lean.** progress.md is loaded every session — write a status board, not a journal. Completed tasks get one-line `[x]` entries. Collapse old done items when the file exceeds ~80 lines.

## ⚠ Compaction Warning

There is **no pre-compaction hook** in Copilot CLI. Auto-compaction triggers at ~95% context usage with no warning and no callback. This means:

- You CANNOT rely on saving state "just before" compaction — it may happen at any time.
- The frequent-update strategy above is the **only** reliable mitigation.
- Treat every memory update as if it might be the last thing you do before losing context.
- If the user manually runs `/compact`, they should say "save progress" first — but auto-compaction gives no such opportunity.

## Reference

The original project plan is preserved in `.memory/plan.md` (read-only reference).
```

## Guidelines

- **Keep files concise.** Each file should be scannable in seconds. If progress.md exceeds ~80 lines, archive completed tasks to a dated section or trim them.
- **progress.md changes most often.** Update after every milestone, not just at session end. Keep entries terse — status board, not journal.
- **Don't duplicate code.** Memory files describe *what* and *why*, not *how*. Never paste code blocks into memory files.
- **Prune aggressively.** Old completed items, resolved gotchas, and superseded decisions should be trimmed.
- **Commit memory updates (when git is enabled).** Git history IS your archive. Don't hoard old content — commit, then prune.
- **Always confirm the setup strategy.** Propose sensible defaults based on environment detection, but never proceed without user confirmation.
- **Append, don't overwrite AGENTS.md.** If the file already exists, add the memory section to it rather than replacing existing content.
