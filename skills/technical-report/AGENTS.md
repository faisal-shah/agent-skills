# AGENTS.md — AI Context for technical-report skill

## What This Skill Is

An agent skill that teaches AI assistants how to generate professional DOCX
technical reports using `python-docx`. The primary artifact is `SKILL.md`,
which gets loaded into the AI's context when the skill triggers.

## Key Files

- `SKILL.md` — Main skill content. Runtime artifact loaded by the agent.
- `install.sh` / `install.ps1` — Copies `SKILL.md` into the target directory.

## Design Principles

1. **Alignment rule is #1** — The single most impactful lesson: NEVER justify
   bullet points. This must be prominently documented and reinforced. Every
   report generation session that forgot this rule required rework.

2. **Helper functions are the API** — The skill defines a small set of reusable
   functions (add_table, bullet_left, para_justified, add_image, add_caption).
   These are the building blocks. New reports should compose these, not invent
   new patterns.

3. **Script-generated reports only** — Reports must always be generated from a
   Python script, never by hand-editing a .docx. This ensures reproducibility
   when underlying data changes.

4. **Verification is mandatory** — Every generated report must pass the
   checklist in §10 (image count, caption count, alignment audit, file size).

5. **Matplotlib patterns are report-adjacent** — Plot generation is tightly
   coupled to report quality. DPI, sizing, colorbar placement, and legend
   positioning directly affect how plots look when embedded in DOCX.

## Origin

This skill was distilled from a 26-hour Elmer FEM wire study session that
spent ~30% of its time on DOCX formatting iterations. The most frequent issues:

| Issue | Occurrences | Root cause |
|-------|-------------|------------|
| Justified bullet points | 3+ | Default alignment applied to lists |
| Figure overflow | 2 | Image width exceeded printable area |
| Colorbar overlap | 2 | No dedicated gridspec axis for colorbar |
| Legend overlap | 2 | Default legend placement over data |
| Report regeneration | 4 | Data changed, script needed re-running |

## Related Skills

- [elmer-fem](../elmer-fem/) — generates simulation data that feeds into reports
- [circuit-sim](../circuit-sim/) — generates circuit simulation results

## Testing Changes

```bash
# Verify YAML frontmatter
head -10 skills/technical-report/SKILL.md

# Install to scratch directory
./skills/technical-report/install.sh skills-test
test -f skills-test/technical-report/SKILL.md

# Windows PowerShell
.\skills\technical-report\install.ps1 -SkillsDir skills-test
Test-Path skills-test\technical-report\SKILL.md
```

## Style

- `SKILL.md`: code-heavy, tables over prose, copy-paste-ready helpers
- Focus on patterns that prevent the most common mistakes
- Every helper function should be self-contained and independently usable
