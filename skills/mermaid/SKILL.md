---
name: mermaid
description: "Create and validate Mermaid diagrams with the official Mermaid CLI. Use for Mermaid fenced Markdown diagrams, .mmd files, rendered SVG/PNG/PDF artifacts, and visual QA of important diagrams."
---

# Mermaid Skill

Use this skill to create or edit Mermaid diagrams and validate them with the
official Mermaid CLI (`mmdc`). GitHub renders fenced `mermaid` blocks natively,
but validating locally catches syntax/rendering failures before docs are updated.

## Prerequisites

- Node.js + npm for `npx`.
- A browser usable by Puppeteer. `tools/validate.sh` auto-detects common
  Chrome/Chromium executables and passes them to `mmdc` with a Puppeteer config.
  If detection fails, set `PUPPETEER_EXECUTABLE_PATH` or
  `MERMAID_PUPPETEER_CONFIG`.

## Tool

```bash
./tools/validate.sh diagram.mmd [output.svg|output.png|output.pdf]
./tools/validate.sh README.md [validated.md]
```

- `.mmd` input renders one diagram.
- `.md` input lets `mmdc` extract Mermaid fences, render artifacts, and rewrite
  Markdown references.
- If output is omitted, the tool renders to a temporary file and removes it.
- Non-zero exit means syntax, rendering, or browser setup failed.

## Workflow

1. For a new diagram, draft in a standalone `.mmd` file for fast iteration.
2. Run `./tools/validate.sh diagram.mmd rendered.svg` and fix errors.
3. If the final deliverable is Markdown, copy the Mermaid block into the target
   `.md` and run `./tools/validate.sh target.md /tmp/target.validated.md`.
4. For important/public diagrams, inspect the rendered SVG/PNG for clipping,
   wrapped labels, ambiguous endpoints, and semantic mismatch; syntax success is
   not visual QA. Do not rely on self-inspection alone: pass the rendered PNG to
   independent sub-agent critics (prefer the agent's native sub-agent mechanism;
   run several in parallel), address every concern, and re-render until the
   diagram is judged legible.
5. Keep rendered assets only when the deliverable needs images/PDFs/previews;
   otherwise prefer source Mermaid in Markdown for GitHub docs.

## Browser troubleshooting

If validation fails because Chrome/Chromium cannot be found:

- install Chrome/Chromium; or
- set `PUPPETEER_EXECUTABLE_PATH=/path/to/chrome`; or
- create a Puppeteer config JSON and set `MERMAID_PUPPETEER_CONFIG`, e.g.
  `{ "executablePath": "/usr/bin/chromium" }`; or
- install Puppeteer's browser cache with
  `npx -y puppeteer browsers install chrome-headless-shell`.
