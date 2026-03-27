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

### 6.7 Simple 2-conductor go/return pair

The simplest and most common circuit topology: one Go and one Return conductor.

```python
from elmer_circuitbuilder import (
    ElmerComponent, I, R, generate_elmer_circuits, number_of_circuits,
)

c = number_of_circuits(1)
c[1].ref_node = 1

comps = []
comps.append(I("I1", 1, 2, 1.0 + 0j))          # 1 A current source
comps.append(R("Rshunt", 1, 2, 1e6))            # numerical stability

# Go conductor:   node 2 → 3  (body_id=1, +z current)
comps.append(ElmerComponent("Go", 2, 3, 1, [1]))
# Return conductor: node 1 → 3  (body_id=2, REVERSED → −z current)
comps.append(ElmerComponent("Ret", 1, 3, 2, [2]))

c[1].components.append(comps)
generate_elmer_circuits(c, "circuit.definition")
```

This pattern scales: for N go conductors + M return conductors, add more
`ElmerComponent` entries with unique body IDs, keeping Go on nodes (2→3) and
Return on nodes (1→3).

### 6.8 Robust stranded coil patching

The simple `str.replace` in §6.3 can double-insert `Number of Turns` if run
twice. Use this idempotent patcher instead:

```python
def patch_circuit_for_stranded(path: Path, sigma_eff: float) -> None:
    """Convert all Massive components to Stranded with given σ_eff."""
    lines = path.read_text().splitlines()
    out = []
    for line in lines:
        if 'Coil Type = "Massive"' in line:
            out.append(line.replace('"Massive"', '"Stranded"'))
            out.append("  Number of Turns = Real 1")
        else:
            out.append(line)
    path.write_text("\n".join(out) + "\n")
```

Call this after `generate_elmer_circuits()` for litz/stranded conductor models.
Set `Electric Conductivity = sigma_eff` in the SIF material for each stranded
conductor (σ_eff = η × σ_Cu where η is the fill factor).

### 6.9 Parametric frequency sweep pattern

For impedance extraction at multiple frequencies, loop over frequencies and
create a separate run directory per case:

```python
FREQUENCIES = [10.0, 24_000.0, 36_000.0]  # Hz (10 Hz ≈ DC)
results = {}

for freq in FREQUENCIES:
    omega = 2 * math.pi * freq
    case_dir = base_dir / f"f{freq:.0f}"
    case_dir.mkdir(parents=True, exist_ok=True)

    create_mesh(case_dir, freq)           # mesh sized for this freq's δ
    write_circuit(case_dir)               # same circuit topology
    write_sif(case_dir, omega)            # Angular Frequency = omega
    run_elmer(case_dir)                   # ElmerGrid + ElmerSolver
    R, L = postprocess(case_dir, omega)   # parse scalars.dat → Z → R, L

    results[freq] = {"R_mohm": R * 1e3, "L_uH": L * 1e6}

# Save aggregated results
(base_dir / "results.json").write_text(json.dumps(results, indent=2))
```

Use `10 Hz` (not `0 Hz`) for the DC case — harmonic solvers divide by ω, so
exact zero causes division errors. At 10 Hz the result is indistinguishable
from true DC.

**Mesh reuse:** If the geometry is identical across frequencies, you can mesh
once for the highest frequency (smallest δ) and reuse it. The fine mesh is
conservative at lower frequencies.

### 6.10 Validated reference results

CFC-12-4 flat cable (4 × 12 AWG, alternating polarity, 13 ft):

| Quantity | Elmer FEM | Analytical / Reference | Error |
|---|---|---|---|
| R_dc (10 Hz) | 20.09 mΩ | 20.08 mΩ (ρL/A) | +0.05% |
| R_solid (24 kHz) | 31.20 mΩ | 30.71 mΩ (Reed) | +1.6% |
| L (24 kHz) | 1.19 µH | 1.15 µH (Reed) | +3.7% |
| Rac/Rdc (24 kHz) | 1.55 | ~1.53 (Reed) | — |
| R_litz η=0.55 (24 kHz, Stranded) | 37.66 mΩ | 36.52 mΩ (R_dc/η) | +3.1% |

Extended results across wire types (all at 13 ft / 3.963 m, 20 °C):

| Configuration | R_dc (mΩ) | R @24k (mΩ) | R @36k (mΩ) | Rac/Rdc @24k | L_dc (µH) |
|---|---|---|---|---|---|
| CFC-10-4 +-+- (4×10AWG) | 12.65 | 24.29 | 29.14 | 1.92 | 1.307 |
| CFC-12-4 +-+- (4×12AWG) | 20.12 | 31.27 | 37.67 | 1.55 | 1.312 |
| CFC-14-4 +-+- (4×14AWG) | 32.03 | 41.51 | 48.59 | 1.30 | 1.318 |
| CFC-16-4 +-+- (4×16AWG) | 51.02 | 58.84 | 65.11 | 1.15 | 1.320 |
| Litz 660×36 pair (η=0.54) | 16.42 | 16.42 | 16.42 | 1.00 | 1.937 |
| Litz 429×36 pair (η=0.54) | 25.32 | 25.32 | 25.32 | 1.00 | 2.031 |
| 8 AWG hookup wire pair | 15.90 | 38.59 | 46.35 | 2.43 | 2.625 |

Key observations for sanity-checking new models:
- Litz Rac/Rdc should be **exactly 1.00** at all frequencies (Stranded coil type)
- Thinner gauges have lower Rac/Rdc (less skin effect)
- Wider conductor spacing → higher L (hookup's thick insulation → highest L)

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

## 9. Platform-Specific Notes

### ELMERSOLVER_STARTINFO

ElmerSolver on Windows requires an `ELMERSOLVER_STARTINFO` file in the working
directory. On Linux, ElmerSolver usually reads `case.sif` by default, but
creating this file is harmless and ensures consistent behavior cross-platform:

```python
Path("ELMERSOLVER_STARTINFO").write_text("case.sif\n1\n")
```

Without this file on Windows, ElmerSolver fails silently or with a cryptic error.

### Locating Elmer executables

When launching ElmerSolver from a Python script run via `uv run`, the uv
Python environment may not inherit the system PATH reliably. Use `shutil.which`
with a platform-aware fallback:

```python
import platform, shutil
from pathlib import Path

def find_elmer_bin() -> tuple[str, str]:
    """Return (ElmerSolver, ElmerGrid) paths."""
    solver = shutil.which("ElmerSolver")
    grid = shutil.which("ElmerGrid")
    if solver and grid:
        return solver, grid
    # Fallback: well-known install locations
    if platform.system() == "Windows":
        elmer_bin = Path(r"C:\Program Files\Elmer 26.1-Release\bin")
        return str(elmer_bin / "ElmerSolver.exe"), str(elmer_bin / "ElmerGrid.exe")
    # Linux/macOS: try /usr/bin or /usr/local/bin
    return "ElmerSolver", "ElmerGrid"

ELMER_SOLVER, ELMER_GRID = find_elmer_bin()
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
| ElmerSolver can't find SIF | Missing ELMERSOLVER_STARTINFO (esp. Windows) | Create file containing `case.sif\n1\n` (safe on all platforms) |
| Litz R > solid R in FEM | Used Massive coil type with reduced σ | Use Stranded coil type instead (§6.3) |
| Component current ≈ 0 in solver log | `Body Force = 1` missing on conductor bodies | Add `Body Force = 1` to every conductor body in SIF |
| Solver crashes with "singular matrix" | Isolated conductor with no circuit coupling | Ensure every conductor body has a matching `ElmerComponent` |

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

---

## 12. Complete Script Template: 2D Impedance Extraction

This is the canonical structure for a Python script that meshes a 2D conductor
cross-section, runs Elmer at multiple frequencies, and extracts R + L. Every
simulation script in this skill family follows this pattern — adapt the geometry
section and keep everything else.

```python
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "gmsh",
#   "numpy",
#   "meshio",
#   "matplotlib",
#   "elmer-circuitbuilder",
# ]
# ///
"""
<Title> FEM Study
=================
<Description of what conductors are being modeled.>

Usage:
  cd /path/to/working/dir
  uv run this_script.py
"""
from __future__ import annotations

import json, math, os, platform, re as _re, shutil, subprocess, sys, textwrap, time
from pathlib import Path
import numpy as np

# ── Constants ──────────────────────────────────────────────────────────
PI = math.pi
MU0 = 4e-7 * PI
SIGMA_CU = 5.96e7              # S/m, Cu @ 20 °C
LEAD_M = 3.963                 # reference lead length (m)
DOMAIN_R = 0.10                # air domain radius (m)
FREQUENCIES = [10.0, 24_000.0, 36_000.0]

def find_elmer_bin() -> tuple[str, str]:
    """Return (ElmerSolver, ElmerGrid) paths, cross-platform."""
    solver = shutil.which("ElmerSolver")
    grid = shutil.which("ElmerGrid")
    if solver and grid:
        return solver, grid
    if platform.system() == "Windows":
        elmer_bin = Path(r"C:\Program Files\Elmer 26.1-Release\bin")
        return str(elmer_bin / "ElmerSolver.exe"), str(elmer_bin / "ElmerGrid.exe")
    return "ElmerSolver", "ElmerGrid"

ELMER_SOLVER, ELMER_GRID = find_elmer_bin()

BASE_DIR = Path(__file__).parent / "sim_output"


def create_mesh(case_dir: Path, freq: float) -> None:
    """Build Gmsh geometry + mesh, write mesh.msh."""
    import gmsh
    gmsh.initialize()
    gmsh.model.add("model")
    # ... geometry creation (addDisk, fragment, addPhysicalGroup) ...
    # ... skin-depth-aware mesh sizing (Distance + Threshold fields) ...
    gmsh.model.mesh.generate(2)
    gmsh.write(str(case_dir / "mesh.msh"))
    gmsh.finalize()


def write_circuit(case_dir: Path) -> None:
    """Generate circuit.definition with elmer-circuitbuilder."""
    from elmer_circuitbuilder import (
        ElmerComponent, I, R, generate_elmer_circuits, number_of_circuits,
    )
    c = number_of_circuits(1)
    c[1].ref_node = 1
    comps = []
    comps.append(I("I1", 1, 2, 1.0 + 0j))
    comps.append(R("Rshunt", 1, 2, 1e6))
    comps.append(ElmerComponent("Go", 2, 3, 1, [1]))
    comps.append(ElmerComponent("Ret", 1, 3, 2, [2]))
    c[1].components.append(comps)
    os.chdir(case_dir)
    generate_elmer_circuits(c, str(case_dir / "circuit.definition"))


def write_sif(case_dir: Path, omega: float) -> None:
    """Write case.sif with the given angular frequency."""
    sif = textwrap.dedent(f"""\
    Check Keywords "Warn"
    Header
      Mesh DB "." "mesh"
    End
    Include "circuit.definition"
    Simulation
      Max Output Level = 5
      Coordinate System = "Cartesian"
      Simulation Type = Steady
      Angular Frequency = Real {omega}
      ...
    End
    ...
    """)
    (case_dir / "case.sif").write_text(sif)
    (case_dir / "ELMERSOLVER_STARTINFO").write_text("case.sif\n1\n")


def run_elmer(case_dir: Path) -> None:
    """ElmerGrid mesh conversion + ElmerSolver."""
    subprocess.run(
        [ELMER_GRID, "14", "2", "mesh.msh", "-autoclean"],
        cwd=case_dir, check=True,
    )
    subprocess.run(
        [ELMER_SOLVER], cwd=case_dir, check=True,
    )


def postprocess(case_dir: Path, omega: float) -> tuple[float, float]:
    """Parse scalars.dat → impedance → (R_per_m, L_per_m)."""
    data = np.loadtxt(case_dir / "scalars.dat")
    vals = data[-1] if data.ndim == 2 else data
    col_map = {}
    for line in open(case_dir / "scalars.dat.names"):
        m = _re.match(r"\s*(\d+):\s*res:\s*(.*)", line)
        if m:
            col_map[m.group(2).strip().lower()] = int(m.group(1)) - 1
    V = complex(vals[col_map["v_i1 re"]], vals[col_map["v_i1 im"]])
    I = complex(vals[col_map["i_i1 re"]], vals[col_map["i_i1 im"]])
    Z = V / I
    return Z.real, Z.imag / omega if omega > 1 else Z.imag


def main():
    results = {}
    for freq in FREQUENCIES:
        omega = 2 * PI * freq
        case_dir = BASE_DIR / f"f{freq:.0f}"
        case_dir.mkdir(parents=True, exist_ok=True)
        create_mesh(case_dir, freq)
        write_circuit(case_dir)
        write_sif(case_dir, omega)
        run_elmer(case_dir)
        R_m, L_m = postprocess(case_dir, omega)
        results[str(freq)] = {
            "R_total_mohm": round(R_m * LEAD_M * 1e3, 2),
            "L_uH": round(L_m * LEAD_M * 1e6, 3),
        }
        print(f"  {freq:>8.0f} Hz  R={results[str(freq)]['R_total_mohm']:.2f} mΩ"
              f"  L={results[str(freq)]['L_uH']:.3f} µH")
    (BASE_DIR / "results.json").write_text(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
```

Adapt the `create_mesh()` function for your geometry. Everything else is
reusable boilerplate. For multi-configuration sweeps, wrap `main()` in an
outer loop over a list of config dataclasses.
