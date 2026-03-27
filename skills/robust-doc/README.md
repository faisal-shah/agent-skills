# robust-doc

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
for making technical documents robust through adversarial analysis, source
verification, and iterative refinement.

> **Part of [agent-skills](../../README.md).**

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| SKILL.md   | yes | 6-phase verification methodology with SQL tracking |
| README.md  | no  | Human-facing usage notes (this file) |
| AGENTS.md  | no  | AI context for developing this skill |
| install.sh | yes | Installs the skill (bash) |
| install.ps1| yes | Installs the skill (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./skills/robust-doc/install.sh                      # both Copilot and Codex
./skills/robust-doc/install.sh --copilot            # Copilot only
./skills/robust-doc/install.sh --skills-dir .github/skills
./skills/robust-doc/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\skills\robust-doc\install.ps1
.\skills\robust-doc\install.ps1 -Copilot
.\skills\robust-doc\install.ps1 -SkillsDir C:\my\skills
.\skills\robust-doc\install.ps1 -Uninstall
```

## Prerequisites

- Web search access (for evidence verification)
- SQL tool access (for claim tracking via `doc_claims` table)

## Quick Start

Ask the agent: *"make this document robust"* or *"audit this technical report"*

The skill triggers a multi-pass process:
1. **Audit** — extract every factual claim
2. **Verify** — search for evidence (datasheets, papers, standards)
3. **Adversarial** — challenge assumptions, check boundary conditions
4. **Cross-reference** — find authoritative sources
5. **Correct** — fix errors, add citations, flag uncertainties
6. **Iterate** — repeat until all critical claims are verified

## What the Skill Covers

1. Claim extraction and SQL-based tracking
2. Evidence search strategies (datasheets, IEEE, standards)
3. Adversarial analysis (first-principles, boundary conditions, failure modes)
4. Common verification failure patterns
5. Audit report generation

## License

[MIT](../../LICENSE)
