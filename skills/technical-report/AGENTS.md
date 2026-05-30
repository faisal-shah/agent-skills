# AGENTS.md - AI Context for technical-report skill

## What This Skill Is

An agent skill that teaches AI assistants to produce report packages, not just
Word files. The runtime entry point is `SKILL.md`; optional references deepen
advanced workflows without making every activation expensive.

## Key Files

- `SKILL.md` - Main skill content loaded by the agent.
- `references/docx_helpers.md` - Advanced DOCX helper variants.
- `references/figures.md` - Figure generation, critique, and preview workflow.
- `references/edit_existing.md` - Existing Word report surgery.
- `references/pdf_fallback.md` - Short executive PDF fallback.
- `install.sh` / `install.ps1` - Copy `SKILL.md` and `references/`.

## Design Principles

1. **Agent workflow before snippets** - Start with the decision path and artifact
   contract. Code exists to support that path.
2. **One canonical skeleton** - Keep the common generator self-contained in
   `SKILL.md`. References may add variants, but must not define a competing
   primary workflow.
3. **Report package, not temp file** - Durable reports keep generator, data,
   sources, figures, outputs, QA, and manifest together. `/tmp` is only scratch.
4. **Evidence first** - Agents must read source documents/data before writing
   conclusions and record sources in the generator or manifest.
5. **Regeneration discipline** - Assumptions, constants, source paths, figure
   specs, key phrases, banned stale phrases, and expected counts live near the
   top of the generator.
6. **Alignment rule is still critical** - Body text is justified; bullets and
   numbered lists are left-aligned. Never justify list items.
7. **Visual QA matters** - Figure critique, PDF export, and page previews catch
   failures that `python-docx` structural checks cannot.
8. **Existing-DOCX edits are bounded** - Preserve originals and layouts; use
   targeted scripted changes, not full rewrites, unless explicitly requested.

## Origin

This skill was distilled from repeated Linux and Windows report-generation
sessions involving simulation reports, design reviews, proposal comparisons,
PDF executive summaries, and existing-DOCX edits. Recurring failures were:

| Issue | Root cause | Skill response |
|-------|------------|----------------|
| Disposable `/tmp` generators | Report needed later revision | Durable package contract |
| Stale narrative after revisions | Manual patching | Centralized assumptions and banned phrases |
| Missing or weak figures | Visual QA was skipped | Figure pipeline and critic loop |
| DOCX looked valid but layout was wrong | No rendered preview | QA ladder with PDF/page previews |
| Existing report layout changed | New-report workflow used for edits | Separate existing-DOCX mode |
| Word-open save failures | DOCX open in Office | Safe `_updated.docx` fallback |
| PowerShell heredoc failures | Long inline scripts | Standalone `.py` with `uv run` |

## Testing Changes

```bash
# Verify YAML frontmatter
head -10 skills/technical-report/SKILL.md

# Install to scratch directory
rm -rf /tmp/skills-test
./skills/technical-report/install.sh --skills-dir /tmp/skills-test
test -f /tmp/skills-test/technical-report/SKILL.md
test -f /tmp/skills-test/technical-report/references/docx_helpers.md

# Shell script lint
shellcheck skills/technical-report/install.sh

# Windows PowerShell
.\skills\technical-report\install.ps1 -SkillsDir skills-test
Test-Path skills-test\technical-report\SKILL.md
Test-Path skills-test\technical-report\references\docx_helpers.md
```

## Style

- `SKILL.md`: concise operating procedure plus one complete common-path
  skeleton.
- References: focused, task-specific, and only loaded when needed.
- Prefer tables and checklists over long prose.
- Keep examples runnable or clearly marked as fragments.
