---
name: robust-doc
description: "Read this skill before making a technical document robust through adversarial analysis, source verification, and iterative refinement"
---

# Make a Technical Document Robust

Multi-pass methodology to systematically verify, challenge, and strengthen any technical document. Produces a separate audit report and tracks every claim through structured verification.

## When to Invoke

- User asks to "make this document robust", "verify this document", "audit this document", "adversarial review", or similar
- User provides a technical document and asks you to check it for errors, validate claims, or strengthen it

## Overview

The process has 6 phases executed iteratively. Each phase builds on the previous. You may need 2–4 full cycles before the document stabilizes.

```
┌─────────┐    ┌────────┐    ┌─────────────┐    ┌───────────────┐    ┌──────────┐    ┌─────────┐
│ 1.AUDIT │───►│2.VERIFY│───►│3.ADVERSARIAL│───►│4.CROSS-REFER. │───►│5.CORRECT │───►│6.ITERATE│
│ Extract  │    │ Search │    │  Challenge   │    │ Books/Papers  │    │ Fix+Cite │    │ Repeat? │
│ claims   │    │ evidence│   │  assumptions │    │ Standards     │    │ Annotate │    │         │
└─────────┘    └────────┘    └─────────────┘    └───────────────┘    └──────────┘    └─────────┘
```

## Phase 1: AUDIT — Extract Claims

Read the entire document. For every factual claim, calculation, recommendation, or design choice, create a tracking entry.

### What counts as a claim

- Numerical values (voltages, currents, frequencies, dimensions, costs)
- Component selections (part numbers, ratings, vendors)
- Physics/engineering assertions ("k=0.6 gives complete energy transfer")
- Design choices ("8 primaries is optimal")
- Safety assertions ("interlocks prevent X")
- Cost estimates and timelines

### Tracking setup

```sql
CREATE TABLE IF NOT EXISTS doc_claims (
  id TEXT PRIMARY KEY,           -- e.g., 'calc-resonant-freq', 'part-thyristor-rating'
  section TEXT,                  -- document section where claim appears
  claim TEXT NOT NULL,           -- the claim as stated
  category TEXT,                 -- 'calculation', 'component', 'physics', 'design', 'safety', 'cost'
  severity TEXT DEFAULT 'medium', -- 'critical', 'high', 'medium', 'low'
  status TEXT DEFAULT 'unverified', -- 'unverified', 'verified', 'disputed', 'corrected', 'flagged'
  evidence TEXT,                 -- sources found that support or contradict
  finding TEXT,                  -- what you found (error, confirmed, needs-context)
  updated_at TEXT DEFAULT (datetime('now'))
);
```

- **severity=critical**: Wrong value here causes system failure, safety hazard, or invalidates the design
- **severity=high**: Wrong value leads to significant performance/cost impact
- **severity=medium**: Affects quality/completeness but not fundamental correctness
- **severity=low**: Minor detail, stylistic, or nice-to-have

Populate this table with ALL claims before proceeding. Expect 30–100+ entries for a serious technical document.

## Phase 2: VERIFY — Search for Evidence

For each unverified claim (start with critical, then high):

1. **Web search** for the specific claim. Look for:
   - Manufacturer datasheets and application notes
   - Peer-reviewed papers (IEEE, AIP, etc.)
   - Textbook references (search for known authors in the field)
   - Industry standards (IEC, IEEE, NFPA, etc.)
   - Vendor catalogs with current pricing/availability

2. **Record evidence** in the `evidence` column:
   - If confirmed: cite the source (author, title, year, URL/DOI)
   - If contradicted: record what the source says instead
   - If no evidence found: flag as "unsubstantiated"

3. **Update status**:
   - `verified` — at least one authoritative source confirms
   - `disputed` — source contradicts the claim
   - `flagged` — cannot find evidence either way

### Common verification failures (from experience)

| Failure Pattern | Example | Why It Happens |
|---|---|---|
| **Theoretical minimum used as design value** | "5.4 µF primary bank" when practical is 12 µF | Optimizer mindset; forgetting margins |
| **Wrong component for the application** | Thyratron rated for 1 kA in a 3.4 kA circuit | Grabbed first search result |
| **Outdated pricing or availability** | "$500 per unit" for discontinued part | Old source, not cross-checked |
| **Misapplied physics** | k ≥ 0.90 when k=0.6 is the canonical solution | Incomplete literature review |
| **Frequency/timing mismatch** | Test system at 7.5 kHz when target is 24 kHz | Forgot to match the actual operating point |
| **Missing critical subsystem** | No anti-parallel diode → only 9% energy transfer | Didn't simulate the full circuit |

## Phase 3: ADVERSARIAL ANALYSIS — Challenge Everything

For each verified or unverified claim, apply these challenges:

### 3a. First-Principles Check
- Can you derive the number from basic equations?
- Does dimensional analysis work out?
- Plug in the values yourself and compute independently

### 3b. Boundary Conditions
- What happens at the extremes of the operating range?
- What if a component is at ±20% of nominal?
- What if the environment is worse than assumed (temperature, humidity, aging)?

### 3c. Practical vs. Theoretical
- Is this a theoretical optimum or a practical design value?
- What margins/derating are standard practice? (typically 25–50% for HV, 2× for safety)
- Would a practicing engineer accept this number?

### 3d. Alternative Approaches
- Is there a fundamentally different way to achieve the same goal?
- What would a competitor or skeptical reviewer propose instead?
- Are there simpler/cheaper/more reliable alternatives?

### 3e. Failure Mode Analysis
- What single-point failures exist?
- What happens if this claim is wrong by 2×? By 10×?
- What's the consequence of the worst-case scenario?

### 3f. Internal Consistency
- Do numbers in one section agree with numbers in another?
- If Section 3 says 14 kV and Section 7 says 16 kV, which is correct?
- Do the schematics match the calculations?

Update the tracking table with findings from adversarial analysis.

## Phase 4: CROSS-REFERENCE — Find Authoritative Sources

Search for and consult:

1. **Textbooks** — Find the 2–3 definitive references in the field. Search for well-known authors, look at bibliographies of papers you've already found.

2. **Papers** — Search IEEE Xplore, arXiv, Google Scholar. Look for:
   - The original derivation of key equations
   - Experimental validation of the principles used
   - Similar systems that have been built and tested

3. **Standards** — Find applicable safety and design standards:
   - IEC/IEEE for electrical systems
   - NFPA for safety/fire protection
   - Industry-specific standards

4. **Vendor application notes** — Manufacturers often publish design guides that reveal practical considerations not in textbooks.

For each source found, record:
- What it confirms or contradicts
- Any additional considerations it raises
- Any corrections to make

## Phase 5: CORRECT & STRENGTHEN

### 5a. Fix errors
For each `disputed` claim:
- Correct the value/statement in the document
- Add a citation to the authoritative source
- Note what was wrong and why

### 5b. Add evidence
For each `verified` claim that lacks citation:
- Add inline citation or footnote
- Prefer: author, title, year, and either DOI/URL or page number

### 5c. Flag uncertainties
For each `flagged` claim:
- Add a note indicating the uncertainty
- Describe what additional work is needed to resolve it
- Suggest how to verify (test, simulation, expert consultation)

### 5d. Strengthen weak areas
- Add missing analysis (e.g., if safety margins aren't calculated, calculate them)
- Add missing failure modes
- Add missing alternatives that were considered and why they were rejected

## Phase 6: ITERATE — Repeat Until Stable

After completing one pass:

```sql
-- Check status summary
SELECT status, severity, COUNT(*) as n 
FROM doc_claims 
GROUP BY status, severity 
ORDER BY 
  CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 ELSE 4 END,
  status;
```

**Continue iterating if:**
- Any `critical` or `high` claims are still `unverified` or `disputed`
- New claims were discovered during adversarial analysis
- Cross-referencing revealed new issues

**Stop when:**
- All `critical` and `high` claims are `verified` or `corrected`
- No new issues found in the last pass
- Remaining `flagged` items are clearly documented with resolution paths

## Output: Audit Report

After all iterations, generate an audit report document (separate from the target document). Structure:

```markdown
# Document Audit Report
## Target: [document name]
## Date: [date]
## Passes completed: [N]

## Executive Summary
[2-3 sentences: how many claims checked, how many errors found and fixed, 
 confidence level in the final document]

## Critical Findings (Fixed)
[List of critical errors that were found and corrected, with before/after]

## Verification Summary
| Category | Verified | Corrected | Flagged | Total |
|----------|----------|-----------|---------|-------|

## Remaining Uncertainties
[Claims that could not be fully verified, with recommended resolution]

## Sources Consulted
[List of all references used during verification]

## Detailed Claim Log
[Full table dump from doc_claims, sorted by severity then status]
```

## Key Principles

1. **Never trust a single source.** Cross-reference everything with at least 2 independent sources for critical claims.

2. **Theoretical ≠ practical.** Always ask: "is this a textbook minimum or a build-it-tomorrow value?"

3. **Simulate when possible.** If the document contains circuit/physics calculations, write a quick simulation to verify independently.

4. **The document author is human.** Assume good faith but verify everything. Common failure: grabbing the first Google result without checking if the part/value actually fits the application.

5. **Search broadly, then deeply.** Start with web searches to identify the right domain. Then go deep into the specific textbooks, papers, and standards.

6. **Track everything.** The SQL table is your ground truth. Every claim gets a row. No claim goes unchecked.

7. **Iterate.** One pass is never enough. The first pass finds obvious errors. The second finds subtle ones. The third finds internal inconsistencies created by fixes.
