# elmer-fem

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
that teaches AI coding assistants how to use **Elmer FEM** for general
finite-element workflows: mesh conversion, SIF authoring, steady-state and
transient setup, axisymmetric models, and ParaView post-processing.

> **Part of [agent-skills](../../README.md).** If the excitation waveform comes
> from a SPICE circuit, see [circuit-sim](../circuit-sim/).

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | **yes** | Main skill file loaded by the agent framework |
| `README.md` | no | This file (repo documentation only) |
| `AGENTS.md` | no | AI context for developing the skill itself |
| `install.sh` | **yes** | Installs the skill into a skills directory |

## Installation

```bash
# From the monorepo root
./install.sh                               # installs all skills to ~/.copilot/skills and ~/.codex/skills

# Or just this skill
./skills/elmer-fem/install.sh              # install to both Copilot and Codex
./skills/elmer-fem/install.sh --copilot
./skills/elmer-fem/install.sh --codex
./skills/elmer-fem/install.sh --skills-dir .github/skills

# Uninstall from both default user dirs
./skills/elmer-fem/install.sh --uninstall
```

## Prerequisites

- **ElmerSolver** and **ElmerGrid**
- A mesh generator such as **Gmsh** or **Salome**
- **ParaView** for result inspection

## Quick Start

```bash
# Typical mesh conversion
ElmerGrid 14 2 mesh.msh -autoclean

# Run a case
ELMER_SOLVER_INPUT_FILE=case.sif ElmerSolver | tee solver.log

# Visualize time-series output
paraview results/fields.pvd
```

## What the Skill Covers

1. **Workflow** - CAD/mesh to ElmerGrid to SIF to ElmerSolver to ParaView
2. **Mesh conversion** - Gmsh and Salome import patterns
3. **SIF anatomy** - core block structure and ID mapping
4. **Transient setup** - `Variable Time`, BDF stepping, output timing
5. **Axisymmetry** - `r-z` conventions and coordinate mapping
6. **Output handling** - VTU export, field verification, PVD manifests
7. **General gotchas** - body/boundary IDs, missing fields, boolean retagging
8. **Worked example** - pulsed axisymmetric capacitor as a reusable pattern

## License

[MIT](../../LICENSE)
