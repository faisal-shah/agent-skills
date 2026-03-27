# AGENTS.md — AI Context for agent-skills

## What This Repo Is

A monorepo containing multiple agent skills — self-contained teaching modules
that AI coding assistants load to gain domain-specific capabilities. Each skill
lives under `skills/<name>/` with its own SKILL.md, scripts, and documentation.

## Repository Structure

```
skills/
├── circuit-sim/            ← ngspice simulation (AC/DC/transient, rawfile parsing, plotting)
├── elmer-fem/              ← general Elmer FEM workflow (mesh → SIF → solve → visualize)
├── netlist-to-schematic/   ← SPICE netlist → Circuitikz schematic diagrams
├── technical-report/       ← DOCX report generation (python-docx, tables, figures, formatting)
└── memory/                 ← persistent memory across sessions and compactions
```

Each skill directory has its own `AGENTS.md` with skill-specific context.
Read the relevant skill's `AGENTS.md` before modifying that skill.

## Design Principles

1. **Each skill is self-contained.** A skill's `install.sh` copies only its own
   `SKILL.md` and `scripts/` — no cross-skill dependencies at runtime.

2. **SKILL.md is the artifact.** Everything else (README, AGENTS.md, examples,
   install.sh) exists to support developing and distributing the SKILL.md.
   Keep SKILL.md concise — every line is loaded into the agent's context on
   every invocation.

3. **Worked examples over abstract rules.** LLMs perform dramatically better
   when given concrete examples. Every SKILL.md should contain at least one
   end-to-end worked example.

4. **Scripts use PEP 723 inline metadata.** No pyproject.toml or
   requirements.txt — each script declares its own dependencies and runs
   with `uv run`.

## Adding a New Skill

1. Create `skills/<name>/` with at minimum:
   - `SKILL.md` — the skill content (with YAML frontmatter: `name`, `description`)
   - `install.sh` — copies SKILL.md (and scripts/ if any) to a target directory
   - `AGENTS.md` — AI context for developing this skill
   - `README.md` — human documentation

2. Add the skill to the table in the top-level `README.md`.

3. Update the top-level `install.sh` to include the new skill.

## Cross-Skill References

- **circuit-sim** and **netlist-to-schematic** are complementary:
  circuit-sim runs simulations, netlist-to-schematic draws the schematic.
- **elmer-fem** complements **circuit-sim** when a circuit-generated waveform
  needs to be applied as a boundary condition in a field simulation.
- **memory** is orthogonal — it manages session persistence, not circuit
  engineering.

## Testing Changes

Each skill's `AGENTS.md` describes how to test that skill. In general:

```bash
# circuit-sim: run example netlists
uv run skills/circuit-sim/scripts/run_sim.py skills/circuit-sim/examples/rc_lowpass.cir --plot test.png

# elmer-fem: install into a scratch skills directory
./skills/elmer-fem/install.sh skills-test

# netlist-to-schematic: compile a worked example
uv run skills/netlist-to-schematic/scripts/compile_tex.py example.tex

# memory: manual test — run `memory init` in a scratch directory
```

## Style

- SKILL.md: terse, high-signal, no filler. Tables over prose.
- Scripts: PEP 723 inline metadata, type hints, minimal dependencies.
- READMEs: installation-focused, with quick-start examples.
