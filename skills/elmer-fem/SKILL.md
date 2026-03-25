---
name: elmer-fem
description: >
  Set up, run, and debug Elmer FEM simulations from CAD or scripted geometry.
  Use when asked about ElmerSolver, ElmerGrid, SIF files, Gmsh or Salome
  meshing, steady-state or transient FEM setup, axisymmetric models, or
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
- `ParaView` for result inspection
- Python 3.10+ if automating geometry, mesh conversion, or PVD generation

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

## 6. Output and Visualization

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

## 7. Worked Example: Pulsed Axisymmetric Capacitor

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

Check:

```bash
sed -n '1,40p' mesh/mesh.names
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
ELMER_SOLVER_INPUT_FILE=case.sif ElmerSolver | tee solver.log
```

Then open `results/fields.pvd` in ParaView.

---

## 8. Debugging Checklist

| Symptom | Likely cause | What to do |
|---|---|---|
| BC seems applied to the wrong edge | Boundary IDs do not match the mesh | Inspect `mesh/mesh.names` and fix `Target Boundaries` |
| Solver starts but result is nonsense in axisymmetry | Wrong `r-z` interpretation or mapping | Re-check axis on `x=0` and `Coordinate Mapping(3)` |
| Output field is missing | Computed quantity was not exported | Add it explicitly to `ResultOutputSolver` or derive it in ParaView |
| Too many or too few VTUs written | Assumption about output cadence is wrong | Trust the solver log and actual files, not expectations |
| ParaView Apply is very slow | Loading many VTUs directly | Open a `.pvd` collection instead |
| Gmsh groups are wrong after booleans | OCC retagged entities | Build groups from the final boolean result, not old tags |
| Convergence is bad from the start | Model too complex too early | Reduce to a coarse steady-state or single-step version, then add complexity |

---

## 9. Practical Defaults

- Start from the **nearest working example** you can find
- Keep the first run **small and coarse**
- Validate **mesh names and BC mapping** before tuning solver tolerances
- Capture solver stdout to a log file
- Verify actual output arrays before telling the user what fields exist
- Prefer `.pvd` for time series visualization
