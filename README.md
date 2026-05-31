# agent-skills

A collection of [agent skills](https://docs.github.com/copilot/concepts/agents/about-agent-skills)
that teach AI coding assistants domain-specific workflows — circuit simulation,
Elmer FEM setup, schematic drawing, and persistent memory across sessions.

## Skills

| Skill | Description | Prerequisites |
|-------|-------------|---------------|
| [circuit-sim](skills/circuit-sim/) | Drive ngspice for AC/DC/transient simulation, parse rawfiles, plot waveforms | ngspice, Python 3.10+, numpy, matplotlib |
| [commit](skills/commit/) | Consistent Conventional Commits-style git commit messages | Git |
| [elmer-fem](skills/elmer-fem/) | Set up, run, and debug Elmer FEM workflows: mesh conversion, SIF authoring, circuit-coupled conductor impedance extraction (R, L), parametric frequency sweeps, Massive/Stranded coil types, and ParaView post-processing. Includes a complete script template and validated reference results. | ElmerSolver, ElmerGrid, Gmsh or Salome, elmer-circuitbuilder; ParaView *(optional)* |
| [mermaid](skills/mermaid/) | Create and validate Mermaid diagrams with the official Mermaid CLI | Node.js + npm |
| [memory](skills/memory/) | Bootstrap persistent memory files that survive compactions and session restarts | None |
| [netlist-to-schematic](skills/netlist-to-schematic/) | Convert SPICE netlists into publication-quality Circuitikz schematic diagrams | pdflatex, pdftoppm, Python 3.10+ |
| [playwright-cli](skills/playwright-cli/) | Browser automation: navigation, form filling, screenshots, scraping, session management | playwright-cli, Chromium |
| [robust-doc](skills/robust-doc/) | Adversarial verification and strengthening of technical documents | Web search access |
| [shellcheck](skills/shellcheck/) | Lint shell scripts with ShellCheck and PowerShell scripts with PSScriptAnalyzer | shellcheck-py, PSScriptAnalyzer |
| [technical-report](skills/technical-report/) | Generate professional DOCX technical reports with python-docx: table formatting, alignment rules, image embedding, page layout, and matplotlib integration | Python 3.10+, python-docx; matplotlib *(optional)* |
| [uv](skills/uv/) | Use `uv` instead of pip/python/venv for scripts, dependencies, and builds | [uv](https://docs.astral.sh/uv/) |

## Installation

Install all skills at once, or pick individual ones. Installers default to both
user-level agent skill directories if no path is provided: `~/.copilot/skills`
and `~/.codex/skills`.

**Linux / macOS / WSL:**

```bash
./install.sh                                        # all skills → both Copilot and Codex
./install.sh --copilot                              # all skills → Copilot only
./install.sh --codex                                # all skills → Codex only
./skills/circuit-sim/install.sh --copilot           # individual skill
./install.sh --skills-dir .github/skills            # custom path
./install.sh --uninstall                            # remove from both default dirs
```

**Windows (PowerShell):**

```powershell
.\install.ps1                                       # all skills → both Copilot and Codex
.\install.ps1 -Copilot                              # all skills → Copilot only
.\install.ps1 -Codex                                # all skills → Codex only
.\skills\circuit-sim\install.ps1 -Copilot           # individual skill
.\install.ps1 -SkillsDir C:\my\skills               # custom path
.\install.ps1 -Uninstall                            # remove from both default dirs
```

Supported skill directories:

| Agent | Path |
|-------|------|
| GitHub Copilot CLI (user) | `~/.copilot/skills` |
| GitHub Copilot (project) | `.github/skills` |
| OpenAI Codex | `~/.codex/skills` |

The installer also copies **user-level instruction files** when installing to default directories:

| Agent | Instructions file | Source |
|-------|-------------------|--------|
| GitHub Copilot | `~/.copilot/copilot-instructions.md` | `copilot-instructions.md` |
| OpenAI Codex | `~/.codex/instructions.md` | `codex-instructions.md` |

## Prerequisites

All skills need **Python 3.10+** and [**uv**](https://docs.astral.sh/uv/) (recommended script runner).
Skill-specific tools:

| Tool | Skill | Windows | Linux / macOS / WSL |
|------|-------|---------|---------------------|
| ngspice | circuit-sim | `winget install --id=ngspice.ngspice` or [SourceForge](https://ngspice.sourceforge.io/) | `sudo apt install ngspice` / `brew install ngspice` |
| ElmerSolver + ElmerGrid | elmer-fem | [Elmer Windows installer](https://www.elmerfem.org/blog/binaries/) | `sudo apt install elmer` / [elmerfem.org](https://www.elmerfem.org/blog/binaries/) |
| Gmsh | elmer-fem | `winget install --id=GMSH.GMSH` | `sudo apt install gmsh` / `brew install gmsh` |
| elmer-circuitbuilder *(pip)* | elmer-fem | `pip install elmer-circuitbuilder` | `pip install elmer-circuitbuilder` |
| ParaView *(optional — GUI only)* | elmer-fem | [paraview.org](https://www.paraview.org/download/) | `sudo apt install paraview` / [paraview.org](https://www.paraview.org/download/) |
| pdflatex (TeX) | netlist-to-schematic | `winget install --id=MiKTeX.MiKTeX` | `sudo apt install texlive-latex-extra texlive-pictures` |
| pdftoppm (Poppler) | netlist-to-schematic | `winget install --id=oschwartz10612.Poppler` | `sudo apt install poppler-utils` |
| Node.js + npm | mermaid | [nodejs.org](https://nodejs.org/) / `winget install --id=OpenJS.NodeJS` | `sudo apt install nodejs npm` / `brew install node` |
| shellcheck | shellcheck | `pip install shellcheck-py` | `pip install shellcheck-py` / `sudo apt install shellcheck` |
| PSScriptAnalyzer | shellcheck | `Install-Module PSScriptAnalyzer -Scope CurrentUser` | `Install-Module PSScriptAnalyzer -Scope CurrentUser` |
| playwright-cli | playwright-cli | Bundled with Copilot CLI Playwright MCP server | Same |

> **Note:** ParaView is a GUI visualization tool for inspecting Elmer results — it is not
> invoked programmatically by the skill and is not required to run simulations.

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
├── codex-instructions.md   ← user-level Codex agent instructions (~/.codex/instructions.md)
├── .gitattributes          ← line-ending rules (LF for .sh, CRLF for .ps1)
├── install.sh              ← install all skills (bash)
├── install.ps1             ← install all skills (PowerShell)
├── LICENSE                 ← MIT
└── skills/
    ├── circuit-sim/        ← ngspice simulation skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   ├── install.ps1
    │   ├── scripts/
    │   │   ├── run_sim.py
    │   │   └── parse_rawfile.py
    │   └── examples/
    ├── commit/             ← git commit message skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── install.ps1
    ├── elmer-fem/          ← general Elmer FEM workflow skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── install.ps1
    ├── mermaid/            ← Mermaid diagram validation skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   ├── install.ps1
    │   └── tools/
    │       └── validate.sh
    ├── memory/             ← persistent memory skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── install.ps1
    ├── netlist-to-schematic/ ← Circuitikz schematic skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   ├── install.ps1
    │   └── scripts/
    │       └── compile_tex.py
    ├── playwright-cli/     ← browser automation skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   ├── install.ps1
    │   └── references/
    │       ├── request-mocking.md
    │       ├── running-code.md
    │       ├── session-management.md
    │       ├── storage-state.md
    │       ├── test-generation.md
    │       ├── tracing.md
    │       └── video-recording.md
    ├── robust-doc/         ← document verification skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── install.ps1
    ├── shellcheck/         ← script linting skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── install.ps1
    ├── technical-report/   ← DOCX report generation skill
    │   ├── SKILL.md
    │   ├── AGENTS.md
    │   ├── README.md
    │   ├── install.sh
    │   └── install.ps1
    └── uv/                 ← Python uv tool skill
        ├── SKILL.md
        ├── AGENTS.md
        ├── README.md
        ├── install.sh
        ├── install.ps1
        └── references/
            ├── build.md
            └── scripts.md
```

## License

MIT
