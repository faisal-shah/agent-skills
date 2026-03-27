# AGENTS.md — AI Context for mermaid skill

## What This Skill Is

A validation-first workflow for Mermaid diagrams. The agent drafts diagrams
in standalone `.mmd` files, validates them with the official Mermaid CLI
(via `tools/validate.sh`), fixes errors, then pastes the validated block
into the target Markdown file.

## Key Files

- `SKILL.md` — Workflow steps, prerequisites, and validation tool usage
- `tools/validate.sh` — Shell script that renders a `.mmd` file with `mmdc`
  and prints an ASCII preview via `beautiful-mermaid`

## Design Principles

1. **Validate before embedding.** Never paste an untested Mermaid block into Markdown.
2. **Standalone files first.** `mmdc` only validates plain `.mmd` files, not fenced
   blocks inside Markdown. Draft in a temp `.mmd`, validate, then copy.
3. **ASCII preview for feedback.** The validate script shows an ASCII rendering so the
   agent can spot structural issues without a GUI.
4. **Cross-platform.** Uses `npx` — works anywhere Node.js is installed (Linux, macOS, WSL, Windows).

## Testing Changes

```bash
# Create a test diagram and validate it
echo 'graph TD; A-->B; B-->C;' > /tmp/test.mmd
./skills/mermaid/tools/validate.sh /tmp/test.mmd
rm /tmp/test.mmd
```

## Style

- SKILL.md should stay under 30 lines — the workflow is simple.
- `validate.sh` should remain a single self-contained script (no dependencies
  beyond npx).
