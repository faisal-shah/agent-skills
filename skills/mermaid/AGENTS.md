# AGENTS.md — AI Context for mermaid skill

## What This Skill Is

A validation-first workflow for Mermaid diagrams. The agent drafts diagrams
in standalone `.mmd` files when useful, validates `.mmd` or final Markdown
with the official Mermaid CLI (via `tools/validate.sh`), fixes errors, and
visually inspects important rendered diagrams.

## Key Files

- `SKILL.md` — Workflow steps, prerequisites, and validation tool usage
- `tools/validate.sh` — Shell script that renders `.mmd` or Markdown Mermaid
  blocks with `mmdc` and handles local Chrome/Chromium Puppeteer config

## Design Principles

1. **Validate before embedding.** Never paste an untested Mermaid block into Markdown.
2. **Standalone for iteration, Markdown for final QA.** Draft in `.mmd` when
   convenient, then validate the final Markdown file when the diagram lives in docs.
3. **Visual pass for important diagrams.** Syntax success is not layout or semantic QA.
4. **Cross-platform.** Uses `npx` and a Puppeteer config for detected Chrome/Chromium.

## Testing Changes

```bash
# Create a test diagram and validate it
echo 'graph TD; A-->B; B-->C;' > /tmp/test.mmd
./skills/mermaid/tools/validate.sh /tmp/test.mmd /tmp/test.svg
rm /tmp/test.mmd /tmp/test.svg
```

## Style

- SKILL.md should stay concise — the workflow is simple.
- `validate.sh` should remain a single self-contained script (no dependencies
  beyond npx).
