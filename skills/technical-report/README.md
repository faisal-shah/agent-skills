# technical-report

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for producing reproducible technical report packages: DOCX reports generated
with `python-docx`, safe scripted edits to existing Word reports, and short
executive PDFs when DOCX is not required.

> **Part of [agent-skills](../../README.md).** Complements
> [elmer-fem](../elmer-fem/) and [circuit-sim](../circuit-sim/) by packaging
> simulation, design, and analysis results into report deliverables.

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | **yes** | Agent operating procedure, canonical generator skeleton, QA ladder |
| `references/docx_helpers.md` | no | Optional helper variants for advanced DOCX formatting |
| `references/figures.md` | no | Figure generation, critique, screenshots, and preview workflow |
| `references/edit_existing.md` | no | Safe workflow for editing existing DOCX files |
| `references/pdf_fallback.md` | no | `fpdf2` executive PDF fallback patterns |
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
./skills/technical-report/install.sh --claude # Claude Code only
./skills/technical-report/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\install.ps1                              # installs all skills
.\skills\technical-report\install.ps1      # install to both Copilot and Codex
.\skills\technical-report\install.ps1 -Copilot
.\skills\technical-report\install.ps1 -Claude
.\skills\technical-report\install.ps1 -Uninstall
```

## Prerequisites

- **Python 3.10+** with `python-docx`
- **uv** for PEP 723 report generators
- **matplotlib / pillow / fpdf2** only when the selected workflow needs plots,
  screenshot checks, or PDF-only output

## What the Skill Covers

1. Decision flow for new DOCX, existing-DOCX edit, or executive PDF.
2. Durable report package layout with generator, evidence, figures, outputs,
   previews, review log, and manifest.
3. One canonical PEP 723 generator skeleton with QA built in.
4. Figure generation and adversarial visual-review workflow.
5. Existing Word report edit workflow that preserves layout and media.
6. Structural DOCX validation, optional PDF export, and page previews.
7. Windows/Office failure handling for open files, PowerShell quoting, and
   Unicode/PDF issues.

## License

[MIT](../../LICENSE)
