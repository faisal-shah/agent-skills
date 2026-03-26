---
name: elmer-fem
description: >
  Set up, run, and debug Elmer FEM simulations from CAD or scripted geometry.
  Use when asked about ElmerSolver, ElmerGrid, SIF files, Gmsh or Salome
  meshing, steady-state or transient FEM setup, axisymmetric models,
  MagnetoDynamics (harmonic/transient), circuit-coupled conductors, or
  ParaView post-processing of Elmer results.
---

# Elmer FEM Skill

Use Elmer for open-source finite-element simulation workflows driven by a mesh,
a SIF input file, and post-processing in ParaView. This skill is intentionally
workflow-first: prefer adapting a nearby working example over inventing an
unfamiliar SIF from scratch.

> **Waveforms from circuits:** If the excitation comes from a resonant network,
> switcher, or other SPICE-described source, use `circuit-sim` to generate the
> time/value waveform, then feed those values into Elmer.

## Prerequisites

- `ElmerSolver` and `ElmerGrid` on `PATH`
- A meshing tool: **Salome** for GUI-heavy workflows or **Gmsh** for scripting
- **ParaView** *(optional)* — GUI tool for visual inspection of results; not invoked programmatically
- Python 3.10+ if automating geometry, mesh conversion, or PVD generation
- `elmer-circuitbuilder` *(pip)* — required for circuit-coupled conductor simulations

---

## 1. Standard Workflow

1. **Prepare geometry** in CAD, Salome, or Gmsh
2. **Mesh and label** every material region and every BC-relevant boundary
3. **Convert mesh** with `ElmerGrid`
4. **Write the SIF** (`case.sif`)
5. **Run ElmerSolver**
6. **Inspect logs and outputs**
7. **Open results in ParaView**

### Mesh conversion commands

| Source mesh | Command |
|---|---|
| Gmsh `.msh` | `ElmerGrid 14 2 mesh.msh -autoclean` |
| Salome `.unv` | `ElmerGrid 8 2 mesh.unv -autoclean` |

After conversion, inspect `mesh/mesh.names`. It is the most reliable mapping
between human-readable group names and the numeric IDs used by `Target Bodies`
and `Target Boundaries`.

---

## 2. Geometry and Meshing Rules

### General rules

- Every material region must be a separate final **surface** (2D) or **volume**
  (3D).
- Every boundary condition that matters in the SIF should have an explicit
  named boundary group.
- Confirm group names **after** all boolean operations and **before** writing
  the mesh.
- Start with a coarse mesh and correct BC/body mapping first; refine only after
  the model behaves sensibly.

### Meshing for skin depth

For AC electromagnetic problems, the mesh near conductor surfaces must resolve
the skin depth δ = 1/√(πfμσ). The **minimum element size should be ≤ δ/4**
(3–4 elements across the skin depth). Use a graded mesh:

```python
# Gmsh graded mesh near conductor boundaries
gmsh.model.mesh.field.add("Distance", 1)
gmsh.model.mesh.field.setNumbers(1, "CurvesList", conductor_boundary_curves)
gmsh.model.mesh.field.setNumber(1, "Sampling", 200)
gmsh.model.mesh.field.add("Threshold", 2)
gmsh.model.mesh.field.setNumber(2, "InField", 1)
gmsh.model.mesh.field.setNumber(2, "SizeMin", skin_depth / 4)
gmsh.model.mesh.field.setNumber(2, "SizeMax", domain_radius / 10)
gmsh.model.mesh.field.setNumber(2, "DistMin", 0.0)
gmsh.model.mesh.field.setNumber(2, "DistMax", 0.02)   # transition zone
gmsh.model.mesh.field.setAsBackgroundMesh(2)
gmsh.option.setNumber("Mesh.MeshSizeExtendFromBoundary", 0)
gmsh.option.setNumber("Mesh.MeshSizeFromPoints", 0)
gmsh.option.setNumber("Mesh.MeshSizeFromCurvature", 0)
```

If running a frequency sweep, size the mesh for the **highest** frequency (smallest δ).

### Salome vs Gmsh

| Tool | Best for | Tradeoff |
|---|---|---|
| Salome | Interactive CAD import, GUI grouping, manual local mesh control | Heavier, less scriptable |
| Gmsh | Scripted geometry, repeatable runs, Python automation | OCC booleans can be tricky |

### Gmsh OpenCASCADE boolean gotcha

After `fuse`, `cut`, or `fragment`, entity tags often change. Do **not** assume
the original tags survive. If using the Gmsh Python API, track the outputs of
the final boolean operation and build physical groups from those final entities.

The most robust pattern is:

```python
result, result_map = gmsh.model.occ.fragment(primary, others)
gmsh.model.occ.synchronize()
```

Then derive region membership from `result_map` or from final geometry checks
(bounding boxes, areas, volumes). Do not hard-code pre-boolean tags.

---

## 3. SIF Anatomy

Every Elmer case has the same core shape:

```text
Header
Simulation
Constants
Solver(s)
Equation(s)
Material(s)
Body / Body Force / Initial Condition
Boundary Condition(s)
```

Minimal skeleton:

```sif
Header
  CHECK KEYWORDS Warn
  Mesh DB "." "mesh"
End

Simulation
  Max Output Level = 4
  Coordinate System = Cartesian 2D
  Simulation Type = Steady State
  Steady State Max Iterations = 1
  Output Intervals = 1
End

Constants
  Permittivity Of Vacuum = 8.854187817e-12
End

Solver 1
  Equation = Electrostatics
  Procedure = "StatElecSolve" "StatElecSolver"
  Variable = Potential
  Exec Solver = Always
End

Equation 1
  Active Solvers(1) = 1
End

Material 1
  Relative Permittivity = 2.5
End

Body 1
  Target Bodies(1) = 1
  Equation = 1
  Material = 1
End

Boundary Condition 1
  Target Boundaries(1) = 1
  Potential = 1000.0
End
```

### Core rule

Do not guess body and boundary IDs. Read them from `mesh/mesh.names` after
`ElmerGrid` conversion.

---

## 4. Steady-State vs Transient Pattern

| Case type | Key simulation setting | Main solver timing | Output timing | BC style |
|---|---|---|---|---|
| Steady-state | `Simulation Type = Steady State` | `Exec Solver = Always` (or implicit default) | Usually `After Simulation` | Constant values |
| Transient | `Simulation Type = Transient` | `Exec Solver = Always` | `After Timestep` | Constant or time-varying |

### Transient essentials

For transient runs, add:

```sif
Simulation
  Simulation Type = Transient
  Timestepping Method = BDF
  BDF Order = 1
  Timestep Sizes = 1.0e-7
  Timestep Intervals = 200
  Output Intervals = 10
End
```

Use `BDF Order = 1` as the conservative default. Move to order 2 only after the
model is behaving and the timestep is already validated.

### Time-varying boundary conditions

The most robust starting point is a tabulated `Variable Time` boundary:

```sif
Boundary Condition 3
  Target Boundaries(1) = 3
  Potential = Variable Time
    Real
      0.0      0.0
      1.0e-7   1.0e3
      2.0e-7   0.0
      3.0e-7  -5.0e2
    End
End
```

Generate the table in Python if needed. For first-pass transient work, this is
usually safer than trying to be clever with custom expressions.

### Modeling judgement

If the excitation changes over microseconds or milliseconds while the geometry
is only millimeters or centimeters, a **quasi-static** transient model is often
the right first solve. Only move to a more wave-like/full-EM treatment when
propagation or radiation effects are actually important.

---

## 5. Axisymmetric Models

Use axisymmetry only when both geometry and excitation are rotationally
symmetric.

For a standard 2D `r-z` mesh:

- radial direction = **x**
- axial direction = **y**

Typical setup:

```sif
Simulation
  Coordinate System = Axi Symmetric
  Coordinate Mapping(3) = 1 2 3
End
```

If an axisymmetric result looks rotated, inverted, or otherwise nonsensical,
check the axis placement and coordinate mapping before touching solver settings.

---

## 6. 2D Harmonic MagnetoDynamics — Circuit-Coupled Conductors

This is the correct way to extract R and L from a 2D cross-section of
conductors carrying prescribed current at a given frequency. **Do NOT use
Body Force current density** for this (see §6.5 for why).

### 6.1 Overview

The workflow uses three coupled solvers:
1. **CircuitsAndDynamicsHarmonic** — enforces Kirchhoff's laws (total current
   constraints)
2. **MagnetoDynamics2DHarmonic** — solves for the vector potential Az
3. **MagnetoDynamicsCalcFields** — post-processes J, B, Joule heating

Plus the `elmer-circuitbuilder` Python package to generate the circuit
definition file.

### 6.2 Circuit definition with `elmer-circuitbuilder`

Install: `pip install elmer-circuitbuilder`

```python
from elmer_circuitbuilder import (
    ElmerComponent, I, R, generate_elmer_circuits, number_of_circuits,
)

c = number_of_circuits(1)
c[1].ref_node = 1

comps = []
comps.append(I("I1", 1, 2, 1.0 + 0j))          # 1 A current source
comps.append(R("Rshunt", 1, 2, 1e6))            # numerical stability

# Go conductors: node 2 → 3 (positive i_component = +z current)
comps.append(ElmerComponent("Go1", 2, 3, 1, [1]))
comps.append(ElmerComponent("Go3", 2, 3, 3, [3]))

# Return conductors: node 1 → 3 (REVERSED pins → −z current)
comps.append(ElmerComponent("Ret2", 1, 3, 2, [2]))
comps.append(ElmerComponent("Ret4", 1, 3, 4, [4]))

c[1].components.append(comps)
generate_elmer_circuits(c, "circuit.definition")
```

**CRITICAL — Go/Return polarity:** To get opposing current directions in 2D,
the Return components must have their pin nodes **reversed** relative to the Go
components. If Go uses nodes (2→3), Return uses (1→3) or (3→2). This makes the
circuit force negative current through the return wires, giving −z current in
the FEM. Without this, all conductors carry +z current and there is no field
cancellation — inductance will be ~8× too high.

### 6.3 Coil types: Massive vs Stranded

| Setting | `Coil Type = "Massive"` | `Coil Type = "Stranded"` |
|---------|------------------------|--------------------------|
| J distribution | Non-uniform (skin + proximity) | **Forced uniform** |
| Eddy currents | Computed | Suppressed |
| Use for | Solid wire | Litz wire / idealized |
| σ to set | σ_Cu | η × σ_Cu (fill factor) |

For litz wire modeling, use `Coil Type = "Stranded"` with σ_eff = η × σ_Cu.
The Stranded type forces uniform J (mimicking ideal transposition); the reduced
σ accounts for the fill factor (less copper in same OD). This correctly gives:
- R_ac = R_dc,litz = R_dc,solid / η (frequency-independent)
- L from geometry (similar to solid since same OD)

**⚠ Do NOT use `Coil Type = "Massive"` with reduced σ for litz.** This gives
a double penalty: higher R_dc (from lower σ) PLUS residual skin effect (solver
still computes eddy currents). Result: R_litz > R_solid — physically wrong.

To change coil type, post-process the circuit definition file:

```python
txt = Path("circuit.definition").read_text()
txt = txt.replace('Coil Type = "Massive"', 'Coil Type = "Stranded"')
txt = txt.replace(
    'Coil Type = "Stranded"',
    'Coil Type = "Stranded"\n  Number of Turns = Real 1',
)
Path("circuit.definition").write_text(txt)
```

**⚠ `Number of Turns` must be `Real`, not `Integer`.** Elmer rejects
`Integer` with: `Keyword [number of turns] is given wrong type: [integer],
should be of type: [real]`.

### 6.4 SIF template for 2D harmonic magnetics

```sif
Check Keywords "Warn"
Header
  Mesh DB "." "mesh"
End
Include "circuit.definition"
Simulation
  Max Output Level = 5
  Coordinate System = "Cartesian"
  Simulation Type = Steady
  Angular Frequency = Real 150796.447372   ! 2π × 24000
  Output Intervals(1) = 1
  Steady State Max Iterations = 1
  Use Mesh Names = True    ! match Body Name to physical group names
End
Constants
  Permittivity of Vacuum = 8.8542e-12
  Permeability of Vacuum = 1.256637e-6
End

! --- Bodies: one per conductor + air ---
Body 1
  Name = Conductor1
  Equation = 1
  Material = 1
  Body Force = 1    ! MUST reference the circuit-generated body force
End
! ... repeat for each conductor ...
Body 5
  Name = Air
  Equation = 1
  Material = 2
End

Material 1
  Name = "Copper"
  Electric Conductivity = 5.96e7
  Relative Permittivity = 1.0
  Relative Permeability = 1.0
End
Material 2
  Name = "Air"
  Electric Conductivity = 0.0
  Relative Permittivity = 1.0
  Relative Permeability = 1.0
End

Equation 1
  Active Solvers(5) = 1 2 3 4 5
End

! Solver 1: Circuit coupling (MUST be first, before MgDyn)
Solver 1
  Equation = Circuits
  Variable = X
  No Matrix = Logical True
  Procedure = "CircuitsAndDynamics" "CircuitsAndDynamicsHarmonic"
End

! Solver 2: Magnetodynamics
Solver 2
  Equation = MgDyn2D
  Variable = Az[Az re:1 Az im:1]
  Procedure = "MagnetoDynamics2D" "MagnetoDynamics2DHarmonic"
  Linear System Solver = Direct
  Linear System Direct Method = umfpack
  Export Lagrange Multiplier = True    ! required for circuit coupling
End

! Solver 3: Post-process fields (MUST have Linear System settings!)
Solver 3
  Equation = CalcFields
  Procedure = "MagnetoDynamics" "MagnetoDynamicsCalcFields"
  Linear System Solver = Iterative
  Linear System Iterative Method = CG
  Linear System Max Iterations = 5000
  Linear System Convergence Tolerance = 1.0e-8
  Linear System Preconditioning = ILU0
  Calculate Current Density = Logical True
  Calculate Joule Heating = Logical True
End

! Solver 4: VTU output
Solver 4
  Equation = "ResultOutput"
  Procedure = "ResultOutputSolve" "ResultOutputSolver"
  Exec Solver = After Simulation
  Output File Name = "results"
  Save Geometry Ids = Logical True
  Vtu Format = Logical True
End

! Solver 5: Circuit quantities output
Solver 5
  Equation = Circuits Output
  Procedure = "CircuitsAndDynamics" "CircuitsOutput"
End

! Solver 6: Scalar extraction for impedance
Solver 6
  Exec Solver = After Simulation
  Procedure = "SaveData" "SaveScalars"
  Filename = "scalars.dat"
End

Boundary Condition 1
  Name = FarField
  Az re = Real 0.0
  Az im = Real 0.0
End
```

**Key gotchas in this SIF:**
- **`Use Mesh Names = True`** in Simulation — matches `Body N / Name = X` to
  physical group names from Gmsh. Without it, bodies map by numeric ID only.
- **`Export Lagrange Multiplier = True`** in MgDyn solver — required for the
  circuit coupling to actually constrain current.
- **CalcFields MUST have `Linear System Solver` settings** — without them,
  Elmer errors out silently or crashes. Even though CalcFields is a
  post-processing step, it still solves a system.
- **All conductor bodies need `Body Force = 1`** — this references the
  circuit-generated body force (I1_Source). Without it, the circuit has no
  coupling to the FEM bodies.

### 6.5 Why NOT to use Body Force current density

The `Body Force { Current Density = ... }` approach imposes a fixed, uniform
source current density J_source. In a harmonic solve, eddy currents (∝ jωσA)
develop on top of J_source and can partially or fully cancel the source. At
high frequencies, **net current through each conductor ≈ 0** instead of the
intended value.

Symptoms of this bug:
- R ≈ R_dc at all frequencies (no skin effect visible)
- L is much smaller than expected (often 5–10× too low)
- The current is correct at low frequency but wrong at high frequency

**Always use circuit-coupled conductors** (§6.2–6.4) for impedance extraction.

### 6.6 Impedance extraction from scalars

After solving, read `scalars.dat` + `scalars.dat.names`:

```python
import re, numpy as np

data = np.loadtxt("scalars.dat")
vals = data[-1] if data.ndim == 2 else data

col_map = {}
for line in open("scalars.dat.names"):
    m = re.match(r"\s*(\d+):\s*res:\s*(.*)", line)
    if m:
        col_map[m.group(2).strip().lower()] = int(m.group(1)) - 1

V = complex(vals[col_map["v_i1 re"]], vals[col_map["v_i1 im"]])
I = complex(vals[col_map["i_i1 re"]], vals[col_map["i_i1 im"]])
Z = V / I                          # Ω per metre (2D = per unit length)
R_per_m = Z.real                    # resistance
L_per_m = Z.imag / omega           # inductance
```

**Parsing gotcha:** When matching column names, do NOT use `"re" in name` —
this falsely matches the `"res:"` prefix in every line. Use exact key matching.

### 6.7 Validated reference results

CFC-12-4 flat cable (4 × 12 AWG, alternating polarity, 13 ft):

| Quantity | Elmer FEM | Analytical / Reference | Error |
|---|---|---|---|
| R_dc (10 Hz) | 20.09 mΩ | 20.08 mΩ (ρL/A) | +0.05% |
| R_solid (24 kHz) | 31.20 mΩ | 30.71 mΩ (Reed) | +1.6% |
| L (24 kHz) | 1.19 µH | 1.15 µH (Reed) | +3.7% |
| Rac/Rdc (24 kHz) | 1.55 | ~1.53 (Reed) | — |
| R_litz η=0.55 (24 kHz, Stranded) | 37.66 mΩ | 36.52 mΩ (R_dc/η) | +3.1% |

---

## 7. Output and Visualization

### Result output solver

Always add explicit result output:

```sif
Solver 2
  Equation = ResultOutput
  Procedure = "ResultOutputSolve" "ResultOutputSolver"
  Exec Solver = After Timestep
  Output File Name = "fields"
  Output Format = vtu
  Vtu Format = True
  Binary Output = True
  Scalar Field 1 = Potential
End
```

### Important rule

Do **not** assume that a quantity computed internally is automatically exported
to VTU. Verify the actual arrays written. If a derived vector field is missing,
either add it explicitly in the output solver or derive it in ParaView.

### VTU file naming

Elmer often writes results as `results_t0001.vtu` (with timestep suffix), even
for steady-state harmonic solves. Do not assume `results.vtu` — use glob:

```python
vtu_files = sorted(Path("mesh").glob("results*.vtu"))
```

### ParaView workflow

1. Open the `.pvd` file if available
2. Click **Apply**
3. Color by the actual field name present in the file
4. Use the animation controls / time slider for transient results

### PVD is better than loading grouped VTUs directly

Large timestep sets are much more pleasant in ParaView when opened through a
`.pvd` collection file. If Elmer did not generate one, create it yourself.

Minimal generator:

```python
from pathlib import Path

results = Path("results")
vtu_files = sorted(results.glob("fields_t*.vtu"))
dt = 1.0e-7

lines = [
    '<?xml version="1.0"?>',
    '<VTKFile type="Collection" version="0.1">',
    '  <Collection>',
]
for i, vf in enumerate(vtu_files, 1):
    lines.append(f'    <DataSet timestep="{i * dt:.7e}" file="{vf.name}"/>')
lines += ['  </Collection>', '</VTKFile>']

(results / "fields.pvd").write_text("\n".join(lines))
```

---

## 8. Worked Example: Pulsed Axisymmetric Capacitor

Use this as a compact end-to-end pattern for many dielectric/electrode problems.

### Geometry

- 2D axisymmetric `r-z` cross-section
- Inner conductor
- Outer grounded conductor
- Dielectric or fluid region between them

### Mesh

Name the final groups clearly:

- bodies: `Dielectric`, `InnerConductor`, `OuterConductor`
- boundaries: `Axis`, `InnerBC`, `OuterBC`, `FarField`

Convert with:

```bash
ElmerGrid 14 2 mesh.msh -autoclean
```

Check (inspect the first ~40 lines):

```
head -40 mesh/mesh.names          # Linux/macOS
Get-Content mesh/mesh.names -Head 40   # Windows PowerShell
```

### SIF pattern

```sif
Header
  CHECK KEYWORDS Warn
  Mesh DB "." "mesh"
End

Simulation
  Max Output Level = 4
  Coordinate System = Axi Symmetric
  Coordinate Mapping(3) = 1 2 3
  Simulation Type = Transient
  Timestepping Method = BDF
  BDF Order = 1
  Timestep Sizes = 1.0e-7
  Timestep Intervals = 200
  Output Intervals = 10
End

Constants
  Permittivity Of Vacuum = 8.854187817e-12
End

Solver 1
  Equation = Electrostatics
  Procedure = "StatElecSolve" "StatElecSolver"
  Variable = Potential
  Exec Solver = Always
  Calculate Electric Field = True
End

Solver 2
  Equation = ResultOutput
  Procedure = "ResultOutputSolve" "ResultOutputSolver"
  Exec Solver = After Timestep
  Output File Name = "fields"
  Output Format = vtu
  Vtu Format = True
  Binary Output = True
  Scalar Field 1 = Potential
End

Equation 1
  Active Solvers(2) = 1 2
End

Material 1
  Relative Permittivity = 3.0
End

Material 2
  Relative Permittivity = 1.0
  Electric Conductivity = 5.96e7
End

Body 1
  Target Bodies(1) = 1
  Equation = 1
  Material = 1
End

Body 2
  Target Bodies(1) = 2
  Equation = 1
  Material = 2
End

Body 3
  Target Bodies(1) = 3
  Equation = 1
  Material = 2
End

Boundary Condition 1
  Target Boundaries(1) = 2
  Potential = Variable Time
    Real
      0.0      0.0
      1.0e-7   1000.0
      2.0e-7   0.0
      3.0e-7  -500.0
    End
End

Boundary Condition 2
  Target Boundaries(1) = 3
  Potential = 0.0
End
```

### Run

```bash
ElmerSolver                        # uses case.sif by default
```

To use a non-default SIF name or capture logs:

```bash
# Linux/macOS
ELMER_SOLVER_INPUT_FILE=case.sif ElmerSolver 2>&1 | tee solver.log

# Windows PowerShell
$env:ELMER_SOLVER_INPUT_FILE="case.sif"; ElmerSolver 2>&1 | Tee-Object solver.log
```

Then open `results/fields.pvd` in ParaView.

---

## 9. Windows-Specific Issues

### ELMERSOLVER_STARTINFO

ElmerSolver on Windows requires an `ELMERSOLVER_STARTINFO` file in the working
directory:

```python
Path("ELMERSOLVER_STARTINFO").write_text("case.sif\n1\n")
```

Without this file, ElmerSolver fails silently or with a cryptic error.

### Absolute paths when running under `uv run`

When launching ElmerSolver from a Python script run via `uv run`, the uv
Python environment does NOT inherit the system PATH reliably. Use absolute
paths:

```python
ELMER_BIN = Path(r"C:\Program Files\Elmer 26.1-Release\bin")
ELMER_SOLVER = str(ELMER_BIN / "ElmerSolver.exe")
ELMER_GRID   = str(ELMER_BIN / "ElmerGrid.exe")
```

### `elmer-circuitbuilder` `rm` warning

The `elmer-circuitbuilder` package internally calls `rm` (Unix command) to
clean up temp files. On Windows this produces a harmless warning:
`'rm' is not recognized...`. It can be ignored — the circuit definition file
is still generated correctly.

---

## 10. Debugging Checklist

| Symptom | Likely cause | What to do |
|---|---|---|
| BC seems applied to the wrong edge | Boundary IDs do not match the mesh | Inspect `mesh/mesh.names` and fix `Target Boundaries` |
| Solver starts but result is nonsense in axisymmetry | Wrong `r-z` interpretation or mapping | Re-check axis on `x=0` and `Coordinate Mapping(3)` |
| Output field is missing | Computed quantity was not exported | Add it explicitly to `ResultOutputSolver` or derive it in ParaView |
| Too many or too few VTUs written | Assumption about output cadence is wrong | Trust the solver log and actual files, not expectations |
| ParaView Apply is very slow | Loading many VTUs directly | Open a `.pvd` collection instead |
| Gmsh groups are wrong after booleans | OCC retagged entities | Build groups from the final boolean result, not old tags |
| Convergence is bad from the start | Model too complex too early | Reduce to a coarse steady-state or single-step version, then add complexity |
| R ≈ R_dc at all frequencies, L too small | Using Body Force instead of circuit coupling | Switch to CircuitsAndDynamicsHarmonic (§6) |
| All conductors carry same-direction current | Go/Return pin nodes not reversed in circuit | Swap pin1/pin2 for Return components (§6.2) |
| L is 5–10× too high | No opposing return current | Check circuit topology — return conductors need reversed pins |
| `Number of Turns` type error | Used `Integer` instead of `Real` | Must be `Number of Turns = Real 1` |
| CalcFields solver crashes | Missing Linear System Solver settings | Add `Linear System Solver = Iterative` + method + tolerance |
| ElmerSolver can't find SIF | Missing ELMERSOLVER_STARTINFO (Windows) | Create file containing `case.sif\n1\n` |
| Litz R > solid R in FEM | Used Massive coil type with reduced σ | Use Stranded coil type instead (§6.3) |

---

## 11. Practical Defaults

- Start from the **nearest working example** you can find
- Keep the first run **small and coarse**
- Validate **mesh names and BC mapping** before tuning solver tolerances
- Capture solver stdout to a log file
- Verify actual output arrays before telling the user what fields exist
- Prefer `.pvd` for time series visualization
- For impedance extraction: use **circuit-coupled conductors**, not Body Force
- For litz wire: use **Stranded** coil type with η × σ_Cu, never Massive with
  reduced σ
