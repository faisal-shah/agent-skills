# AGENTS.md — AI Context for robust-doc skill

## What This Skill Is

A 6-phase methodology for systematically verifying, challenging, and strengthening
technical documents. The agent extracts every factual claim, searches for evidence,
applies adversarial analysis, cross-references authoritative sources, corrects errors,
and iterates until the document stabilizes. Produces a separate audit report.

## Key Files

- `SKILL.md` — Complete methodology with SQL tracking schema, verification
  patterns, common failure modes, and audit report template

## Design Principles

1. **Track every claim.** SQL table is the ground truth — no claim goes unchecked.
2. **Severity-driven.** Critical claims first, then high, then medium/low.
3. **Evidence-based.** Every verification cites authoritative sources (datasheets,
   papers, standards).
4. **Adversarial.** Not just "does this look right?" but "what happens if this is
   wrong by 10×?"
5. **Iterate.** One pass finds obvious errors. Second finds subtle ones. Third
   finds inconsistencies created by fixes.
6. **Separate audit report.** The document itself gets corrected; the audit trail
   goes in a separate report.

## Origin

Developed from a real 26-hour audit of a pulsed-power engineering document where
the first pass found 15+ substantive errors including undersized components,
misapplied physics, and outdated pricing. The methodology crystallized from
that iterative correction process.

## Testing Changes

Manual test: give the agent a short technical document with a known error (wrong
component rating, misquoted formula) and verify the methodology catches it.

## Style

- Keep the SQL schema and phase descriptions precise — agents execute these
  literally.
- Common failure patterns table is high-value; keep it updated with real examples.
