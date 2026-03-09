# agent-skills

A collection of [agent skills](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
that teach AI coding assistants domain-specific workflows — circuit simulation,
schematic drawing, and persistent memory across sessions.

## Skills

| Skill | Description | Prerequisites |
|-------|-------------|---------------|
| [circuit-sim](skills/circuit-sim/) | Drive ngspice for AC/DC/transient simulation, parse rawfiles, plot waveforms | ngspice, Python 3.10+, numpy, matplotlib |
| [netlist-to-schematic](skills/netlist-to-schematic/) | Convert SPICE netlists into publication-quality Circuitikz schematic diagrams | pdflatex, pdftoppm, Python 3.10+ |
| [memory](skills/memory/) | Bootstrap persistent memory files that survive compactions and session restarts | None |

## Installation

Install all skills at once, or pick individual ones. All scripts default to
`~/.copilot/skills` if no path is provided.

```bash
# All skills (defaults to ~/.copilot/skills)
./install.sh

# Individual skill
./skills/circuit-sim/install.sh
./skills/netlist-to-schematic/install.sh
./skills/memory/install.sh

# Custom path
./install.sh /path/to/skills

# Uninstall
./install.sh --uninstall
```

The **memory** skill also includes a PowerShell installer for native Windows:

```powershell
.\skills\memory\install.ps1                         # defaults to ~/.copilot/skills
.\skills\memory\install.ps1 -SkillsDir C:\my\skills
.\skills\memory\install.ps1 -Uninstall
```

Supported skill directories:

| Agent | Path |
|-------|------|
| GitHub Copilot CLI (user) | `~/.copilot/skills` |
| GitHub Copilot (project) | `.github/skills` |
| OpenAI Codex | `~/.codex/skills` |

## Compatible Agents

- GitHub Copilot (CLI, VS Code, JetBrains)
- Claude Code / Claude.ai
- OpenAI Codex
- Any agent supporting the SKILL.md convention

## Repository Layout

```
agent-skills/
├── README.md               ← this file
├── AGENTS.md               ← AI context for developing skills
├── copilot-instructions.md ← user-level Copilot agent instructions (~/.copilot/copilot-instructions.md)
├── install.sh              ← install all skills at once
├── LICENSE                 ← MIT
└── skills/
    ├── circuit-sim/        ← ngspice simulation skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   ├── scripts/
    │   │   ├── run_sim.py
    │   │   └── parse_rawfile.py
    │   └── examples/
    ├── netlist-to-schematic/ ← Circuitikz schematic skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── scripts/
    │       └── compile_tex.py
    └── memory/             ← persistent memory skill
        ├── SKILL.md
        ├── AGENTS.md
        ├── README.md
        └── install.sh
```

## License

MIT
