# technical-report

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
that teaches AI coding assistants how to generate professional DOCX technical
reports using `python-docx` — covering table formatting, alignment rules, image
embedding, page layout, and reusable helper patterns.

> **Part of [agent-skills](../../README.md).** Complements
> [elmer-fem](../elmer-fem/) and [circuit-sim](../circuit-sim/) by handling the
> report generation step after simulation results are available.

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | **yes** | Main skill file loaded by the agent framework |
| `README.md` | no | This file (repo documentation only) |
| `AGENTS.md` | no | AI context for developing the skill itself |
| `install.sh` | **yes** | Installs the skill into a skills directory (bash) |
| `install.ps1` | **yes** | Installs the skill into a skills directory (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./install.sh                               # installs to ~/.copilot/skills and ~/.codex/skills
./skills/technical-report/install.sh       # install to both Copilot and Codex
./skills/technical-report/install.sh --copilot
./skills/technical-report/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\install.ps1                               # installs all skills
.\skills\technical-report\install.ps1      # install to both Copilot and Codex
.\skills\technical-report\install.ps1 -Copilot
.\skills\technical-report\install.ps1 -Uninstall
```

## Prerequisites

- **Python 3.10+** with `python-docx` (`pip install python-docx`)
- **matplotlib** *(optional)* — for generating plots to embed in reports

## Quick Start

```python
# Minimal PEP 723 script header
# /// script
# requires-python = ">=3.10"
# dependencies = ["python-docx"]
# ///

from docx import Document
doc = Document()
doc.add_heading("My Report", level=1)
doc.add_paragraph("Hello, world!")
doc.save("report.docx")
```

## What the Skill Covers

1. **Alignment rules** — The #1 formatting mistake: justified bullets vs left-aligned lists
2. **Table formatting** — Blue headers, white text, borders, centered numerics
3. **Image embedding** — Centered images with sizing guidelines and overflow prevention
4. **Figure captions** — Italic, centered, proper spacing
5. **Page breaks** — When and where to insert them
6. **Title blocks** — Professional report title/subtitle/date patterns
7. **Rich text** — Inline bold phrases within paragraphs
8. **Matplotlib integration** — DPI, sizing, multi-panel plots, colorbar management
9. **Verification checklist** — Automated post-generation quality checks
10. **Complete script skeleton** — Copy-and-adapt template for new reports

## License

[MIT](../../LICENSE)
