# AGENTS.md — AI Context for commit skill

## What This Skill Is

A concise git commit message guide following Conventional Commits style.
The agent reads this before every `git commit` to produce consistent,
well-formatted commit messages with proper type/scope/summary.

## Key Files

- `SKILL.md` — Commit message format rules, steps, and edge cases

## Design Principles

1. **Convention over configuration.** One format, no options to debate.
2. **Imperative mood.** "Add feature" not "Added feature".
3. **No footers.** No `Signed-off-by`, no `BREAKING CHANGE:` — keep it simple.
4. **Ask when unclear.** If the agent can't tell which files to include, it asks.
5. **Stage-then-commit.** The skill handles staging, not just message formatting.

## Testing Changes

Manual test: make a change, invoke the commit skill, verify the message
format matches `<type>(<scope>): <summary>` with ≤72 char subject.

## Style

- Keep SKILL.md under 50 lines — this is loaded on every commit.
- Rules, not prose. Tables and bullet lists over paragraphs.
