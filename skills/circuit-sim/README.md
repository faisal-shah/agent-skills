# circuit-sim

An [agent skill](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
that teaches AI coding assistants how to drive **ngspice** for analog circuit
simulation — from netlist authoring through binary rawfile parsing to
publication-quality plots.

> **Part of [agent-skills](../../README.md).** For schematic diagrams, see
> [netlist-to-schematic](../netlist-to-schematic/).

## What's Included

| File | Required | Purpose |
|------|----------|---------|
| `SKILL.md` | **yes** | Main skill file — loaded by the agent framework |
| `scripts/parse_rawfile.py` | **yes** | Binary rawfile parser (CLI + library) |
| `scripts/run_sim.py` | **yes** | End-to-end sim runner with .meas/.step/UIC handling |
| `README.md` | no | This file (repo documentation only) |
| `AGENTS.md` | no | AI context for developing the skill itself |
| `install.sh` | **yes** | Installs the skill into a skills directory (bash) |
| `install.ps1` | **yes** | Installs the skill into a skills directory (PowerShell) |
| `examples/` | no | Reference netlists for testing changes to the skill |

## Installation

**Linux / macOS / WSL:**

```bash
./install.sh                               # installs all skills to ~/.copilot/skills and ~/.codex/skills
./skills/circuit-sim/install.sh            # install to both Copilot and Codex
./skills/circuit-sim/install.sh --copilot
./skills/circuit-sim/install.sh --uninstall
```

**Windows (PowerShell):**

```powershell
.\install.ps1                               # installs all skills
.\skills\circuit-sim\install.ps1            # install to both Copilot and Codex
.\skills\circuit-sim\install.ps1 -Copilot
.\skills\circuit-sim\install.ps1 -Uninstall
```

## Prerequisites

- **ngspice** installed and on PATH ([ngspice.sourceforge.io](https://ngspice.sourceforge.io/))
- **Python 3.10+** with `numpy` and `matplotlib`
- **uv** recommended for running scripts (`uv run scripts/run_sim.py`)

## Quick Start

```bash
# Run a simulation and generate a Bode plot
uv run scripts/run_sim.py my_filter.cir --plot bode.png

# Parse a rawfile
uv run scripts/parse_rawfile.py output.raw
uv run scripts/parse_rawfile.py output.raw --csv > data.csv
uv run scripts/parse_rawfile.py output.raw --json > data.json
```

## What the Skill Covers

1. **Netlist syntax** — SPICE3 format, components, subcircuits, models, parameters
2. **Initial conditions & UIC** — `ic=` on components, `.tran UIC`, when and why
3. **Analysis types** — `.ac`, `.dc`, `.tran`, `.op`, `.step`, `.meas`
4. **Binary rawfile parsing** — struct-level unpacking of ngspice's native format
5. **Monte Carlo analysis** — Python-driven tolerance sweeps
6. **Temperature sweeps** — Manual TC application for passives
7. **Measurement extraction** — `.meas` directives + stdout parsing
8. **Plotting** — Bode plots, transient waveforms
9. **Quick reference** — Common elements, source functions
10. **Common pitfalls** — Convergence, node naming, value suffixes, UIC gotchas

## License

[MIT](../../LICENSE)
