# AGENTS.md — AI Context for elmer-fem skill

## What This Skill Is

An agent skill that teaches AI assistants how to set up, run, and debug Elmer
FEM workflows. The primary artifact is `SKILL.md`, which gets loaded into the
AI's context when the skill triggers.

## Key Files

- `SKILL.md` — Main skill content. Keep it concise and workflow-oriented; it is
  the runtime artifact.
- `install.sh` — Copies `SKILL.md` into the target skills directory.

## Design Principles

1. **Workflow first, module second** — The skill should make agents competent at
   the general Elmer pipeline before it tries to be a catalog of every solver.

2. **Reusable gotchas over narrow lore** — Keep the focus on lessons that apply
   across many Elmer jobs: ID mapping, mesh conversion, transient execution
   order, axisymmetry, VTU/PVD output, and ParaView behavior.

3. **Worked example anchors the skill** — Include one concrete end-to-end
   example, but keep it generic enough that agents can transfer the pattern to
   other geometries and physics.

4. **Do not overstate uncertain behavior** — If a behavior is version-specific
   or not fully validated, phrase it cautiously and tell the agent to verify the
   actual output rather than assuming.

## Related Skills

- [circuit-sim](../circuit-sim/) — useful when the Elmer model needs a waveform
  generated from a SPICE circuit.
- [netlist-to-schematic](../netlist-to-schematic/) — useful for circuit
  visualization, not FEM geometry.

## Testing Changes

```bash
# Install only this skill
./skills/elmer-fem/install.sh /tmp/skills-test
test -f /tmp/skills-test/elmer-fem/SKILL.md

# Install the full monorepo
./install.sh /tmp/all-skills-test
test -f /tmp/all-skills-test/elmer-fem/SKILL.md
```

Manual review:

- Verify `SKILL.md` has valid YAML frontmatter (`name`, `description`)
- Verify the skill stays concise and high-signal
- Verify the worked example is concrete but not tied to one narrow project

## Style

- `SKILL.md`: terse, command-oriented, tables over filler prose
- Prefer stable command names and file names
- Separate confirmed guidance from advice that requires verification
