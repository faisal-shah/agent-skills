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
| `install.sh` | **yes** | Installs the skill into a skills directory (bash) |
| `install.ps1` | **yes** | Installs the skill into a skills directory (PowerShell) |

## Installation

**Linux / macOS / WSL:**

```bash
./install.sh                               # installs all skills to ~/.copilot/skills and ~/.codex/skills
./skills/elmer-fem/install.sh              # install to both Copilot and Codex
./skills/elmer-fem/install.sh --copilot
./skills/elmer-fem/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\install.ps1                               # installs all skills
.\skills\elmer-fem\install.ps1              # install to both Copilot and Codex
.\skills\elmer-fem\install.ps1 -Copilot
.\skills\elmer-fem\install.ps1 -Uninstall
```

## Prerequisites

- **ElmerSolver** and **ElmerGrid** (required)
- **Gmsh** or **Salome** for mesh generation (required)
- **elmer-circuitbuilder** Python package (`pip install elmer-circuitbuilder`) — required for circuit-coupled simulations
- **ParaView** for result inspection *(optional — GUI visualization tool, not invoked by the skill)*

<details><summary><strong>Install prerequisites</strong></summary>

**Windows:**
```powershell
# Elmer — download installer from https://www.elmerfem.org/blog/binaries/
winget install --id=GMSH.GMSH             # Gmsh
# ParaView (optional) — download from https://www.paraview.org/download/
```

**Linux / macOS / WSL:**
```bash
sudo apt install elmer gmsh               # Debian/Ubuntu
sudo apt install paraview                  # optional
# OR download from https://www.elmerfem.org/blog/binaries/ and https://gmsh.info/
```
</details>

## Quick Start

```bash
# Typical mesh conversion
ElmerGrid 14 2 mesh.msh -autoclean

# Run a case (case.sif is the default input)
ElmerSolver

# Visualize time-series output
paraview results/fields.pvd
```

## What the Skill Covers

1. **Workflow** - CAD/mesh to ElmerGrid to SIF to ElmerSolver to ParaView
2. **Mesh conversion** - Gmsh and Salome import patterns
3. **Skin-depth meshing** - graded mesh sizing for AC problems
4. **SIF anatomy** - core block structure and ID mapping
5. **Transient setup** - `Variable Time`, BDF stepping, output timing
6. **Axisymmetry** - `r-z` conventions and coordinate mapping
7. **Circuit-coupled conductors** - impedance extraction (R, L) for solid and litz wire, go/return polarity, Massive vs Stranded coil types
8. **Parametric sweeps** - frequency sweep pattern, multi-config studies, JSON results aggregation
9. **Output handling** - VTU export, field verification, PVD manifests
10. **Worked examples** - pulsed capacitor (axisym) and complete impedance extraction script template
11. **Validated results** - reference table across 7 wire configurations at 3 frequencies
12. **Debugging** - 15-row symptom→cause→fix checklist

## License

[MIT](../../LICENSE)
