# AGENTS.md — AI Context for netlist-to-schematic skill

## What This Skill Is

An agent skill that teaches AI assistants how to convert SPICE netlists into
Circuitikz schematic diagrams. The primary artifact is `SKILL.md` which gets
loaded into the AI's context when the skill triggers.

## Key Files

- `SKILL.md` — Main skill content. Loaded by the agent framework. Keep it
  under 400 lines — every line consumes context tokens on every invocation.
- `scripts/compile_tex.py` — Compiles Circuitikz `.tex` schematics to PNG
  via pdflatex + pdftoppm. PEP 723 inline metadata (no external deps).

## Design Principles

1. **Reduce agent bumbling** — The skill exists because LLMs consistently
   struggle with Circuitikz layout. Every section targets a specific observed
   failure mode from multi-model experiments.

2. **Worked examples over rules** — §8 (the forward converter example) is the
   most valuable section. Models that see a concrete worked example produce
   dramatically better schematics than those given only abstract rules.

3. **Label placement is #1** — Label overlap on vertical components is the
   single most common quality issue across all models. §7 provides systematic
   rules, not just a warning.

4. **The compile→view→iterate loop** — The skill explicitly tells agents to
   view their output and fix issues. Without this, many models produce a
   schematic and stop without checking quality.

## Related Skills

- [circuit-sim](../circuit-sim/) — drive ngspice for circuit simulation.

## Testing Changes

Compile the worked example from §8 to verify Circuitikz patterns still work:

```bash
# Extract the worked example from SKILL.md into a .tex file, then:
uv run scripts/compile_tex.py example.tex
# View the output PNG and verify: transformer has core lines + dots,
# labels don't overlap, stage boxes are positioned correctly.
```

## Style

- SKILL.md: terse, high-signal, no filler. Tables over prose. Code examples
  must be minimal but complete and **tested** (every snippet should compile).
- Scripts: PEP 723 inline metadata, type hints.
