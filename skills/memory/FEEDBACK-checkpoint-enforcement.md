# Feedback: Agents Don't Follow Memory Update Instructions

## Observed Problem

In real-world usage, agents consistently skip memory updates despite clear
instructions in AGENTS.md and SKILL.md telling them to update frequently. The
agent reads the memory files at session start, locks onto the primary task
(writing code, fixing bugs, etc.), and powers through the entire task list
without ever calling `edit` on progress.md or lessons.md.

The result: progress.md still says "Not started" after the agent has completed
80%+ of the work. If compaction or session death occurs, the next agent starts
from scratch — the exact failure mode the skill was designed to prevent.

This isn't a documentation problem. The instructions are clear and repeated in
multiple places. It's a **behavioral problem with LLM agents**: they optimize
for the primary objective and treat meta-instructions (update memory, commit
code) as low-priority side effects that get dropped under context pressure.

## Root Causes

### 1. Advisory instructions don't create behavioral gates

The current AGENTS.md says:

> Update `.memory/` files **frequently** — not just at session end.

This is advice, not structure. The agent has no mechanism that *forces* it to
stop coding and update memory. There's no gate, no prerequisite check, no
dependency between "finish task N" and "update memory before starting task N+1."

Compare: if you tell a human developer "commit frequently," many won't. But if
CI rejects pushes without atomic commits per feature, they will. Agents need the
same structural enforcement.

### 2. plan.md bloat consumes the context budget

The skill copies the full plan verbatim into `.memory/plan.md` and the agent
reads it at session start. In practice, plans can be 400–500+ lines with
detailed reference tables (pin maps, API specs, hardware descriptions). This
single file can consume 20–30% of the context window, leaving less room for the
agent to "remember" meta-tasks like memory updates.

The agent's attention prioritizes the rich, detailed plan content over the
shorter, more abstract memory-update instructions.

### 3. Large task lists encourage batch execution

When progress.md lists 15–20 tasks with clear dependencies, the agent treats
them as a single continuous job. It enters a "flow state" of writing code and
never hits a natural stopping point where it would think about housekeeping.

### 4. Memory update instructions are spatially distant from the task list

The "update frequently" instructions live in AGENTS.md. The actual tasks the
agent is executing live in progress.md (and the detailed specs in plan.md).
These are different files read at different times. By the time the agent is
deep in task execution, the AGENTS.md instructions have scrolled out of its
effective attention window.

## Recommendations

### A. Embed checkpoint steps directly in progress.md

Instead of relying on AGENTS.md to say "update frequently," have `memory init`
inject explicit checkpoint lines into the task list itself:

```markdown
## Tasks
- [ ] setup-skeleton — Create Makefile, cfg/ dirs, .gitignore
- [ ] cfg-files — halconf.h, mcuconf.h, chconf.h, deviceconf.h
- [ ] ⚠️ CHECKPOINT — Update .memory/progress.md + git commit
- [ ] main-shell — main.c with ChibiOS shell, LED heartbeat
- [ ] test-core — Clock tree, UID, flash size, internal sensors
- [ ] test-led — LED on/off/blink via PAL
- [ ] ⚠️ CHECKPOINT — Update .memory/progress.md + git commit
...
```

The checkpoint appears *in the task list the agent is already following*. It's
not a separate instruction in a separate file — it's the next item to execute.

**Implementation:** During `memory init`, when extracting tasks into
progress.md, insert a checkpoint task every 2–4 tasks. The frequency can be
configurable or heuristic-based (e.g., every 3 tasks, or after major phase
boundaries if the plan has phases).

### B. Add a mandatory preamble to progress.md

Put the update rule *inside* the file the agent is actively reading, not just
in AGENTS.md:

```markdown
# Progress

> **RULE: After completing each task below, update this file to mark it done
> and commit before starting the next task. This is mandatory, not optional.**

## Current Focus
...
```

This keeps the instruction in the agent's attention while it's scanning the
task list for what to do next.

### C. Cap plan.md size and extract reference material

Add guidance (or enforcement) in `memory init` to keep plan.md under a size
budget (~100–150 lines). If the source plan exceeds this:

- Extract detailed reference material (pin tables, API specs, hardware maps)
  into a separate `.memory/reference.md` or leave it in the session plan.
- Keep only the task list, key decisions, and architectural overview in plan.md.

This reduces context consumption and leaves more budget for the agent to
maintain awareness of meta-instructions.

Alternatively, the AGENTS.md loader could instruct the agent to read plan.md
*only when needed for reference*, not on every session start. Currently the
plan is labeled "read-only reference" but it's still a 27KB file that gets
loaded into context.

### D. Restructure AGENTS.md to lead with the update rule

The current AGENTS.md template puts "On Session Start" first, then "Updating
Memory" second. By the time the agent reaches the update section, it's already
thinking about tasks. Consider restructuring:

```markdown
## ⚠️ Critical Rule

After completing EACH task, you MUST update .memory/progress.md and commit
BEFORE starting the next task. No exceptions.

## On Session Start / After Compaction
...
```

Leading with the constraint makes it more likely to be internalized before the
agent enters task-execution mode.

### E. Consider a phase-based structure

Instead of a flat task list, structure progress.md into phases with explicit
gates:

```markdown
## Phase 1: Skeleton
- [ ] setup-skeleton
- [ ] cfg-files
- [ ] main-shell

**→ GATE: Update memory + commit. Do not proceed to Phase 2 until done.**

## Phase 2: Test Modules
- [ ] test-core
- [ ] test-led
...

**→ GATE: Update memory + commit. Do not proceed to Phase 3 until done.**
```

Phases create natural stopping points. The gate language ("do not proceed")
is stronger than "update frequently."

### F. Track checkpoint compliance in lessons.md (post-hoc)

Add a section to the `memory update` command: when the agent runs
`memory update`, have it note *how many tasks were completed since the last
update*. If the answer is more than 3–4, that's a signal the update frequency
is too low. This creates a self-monitoring feedback loop:

```markdown
## Update Log
| Date | Tasks completed since last update | Notes |
|------|-----------------------------------|-------|
| 2025-03-09 | 12 | ⚠️ Too many — increase checkpoint frequency |
```

## Summary

The memory skill's design is sound — the file structure, update workflow, and
compaction warnings are all well-thought-out. The gap is in **enforcement**.
The skill relies on advisory instructions that agents deprioritize under
context pressure. The fix is structural: put checkpoints in the task list
itself, cap plan sizes to preserve context budget, and use gate language that
makes memory updates a prerequisite rather than a suggestion.
