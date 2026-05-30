# Elmer FEM skill feedback from prior Copilot sessions

Generated: 2026-05-29

Scope: ten recent Linux and Windows Copilot sessions involving Elmer FEM
simulation or FEM workflow preparation. Each session was reviewed by a separate
GPT-5.5 investigator, then consolidated here for deciding future updates to
`skills/elmer-fem/SKILL.md`.

## Executive summary

The current skill is strong for the general mesh-to-SIF-to-solver workflow and
for 2D harmonic circuit-coupled conductor impedance extraction. The repeated
gaps from real sessions are:

1. **Electrostatic capacitance extraction is under-covered.** Multiple sessions
   improvised capacitance extraction, energy parsing, and axisymmetric scaling.
   The most important recurring gotcha was that axisymmetric capacitance/energy
   outputs behaved as per-radian quantities and needed validation against a
   known coaxial case before multiplying by `2*pi`.
2. **The mesh handoff contract should be clearer.** The Elmer-relevant lesson
   is not how to operate Salome or SolidWorks; it is that Elmer only sees the
   converted mesh. The skill should state what must be present after
   `ElmerGrid`: named material bodies, named boundary groups, and verified
   `mesh/mesh.names` mappings.
3. **Electrostatic SIF templates should be made more production-safe.** Real
   runs failed until explicit linear solver settings were added. The current
   minimal electrostatic examples omit these settings.
4. **Multiconductor cable and capacitance-matrix workflows are now common.**
   The triaxial cable study needs a reusable pattern: one excitation per
   conductor, assemble the capacitance matrix, run magnetic R/L modes, and check
   matrix symmetry/row consistency.
5. **AC-loss/proximity work needs more validation guidance.** The skill covers
   circuit-coupled harmonic conductors, but sessions added lessons about Joule
   heating integration, convergence, proximity benchmarks, and avoiding false
   validation claims.
6. **Application integration has recurring operational friction.** Only the
   Elmer-facing parts belong in this skill: reproducible run directories,
   solver/startinfo files, artifact locations, VTU/scalar parsing, and
   `elmer-circuitbuilder` path/body-ID details.

## Recommended skill updates

### P0 - Add electrostatic capacitance extraction guidance

Add a section near the existing electrostatics/axisymmetric material covering:

- 1 V electrode excitation, grounded return, dielectric/air body, and
  `StatElecSolver`.
- `Calculate Electric Energy`, `Calculate Capacitance Matrix`, `Capacitance
  Bodies`, and `Capacitance Body` usage.
- Robust parsing of `capacitance.dat`, solver logs, or scalar outputs.
- Axisymmetric scalar validation:
  - benchmark against an analytical coaxial capacitor;
  - treat capacitance/energy normalization as solver/version dependent until
    verified;
  - in the reviewed sessions, Elmer's axisymmetric capacitance result was
    effectively per radian, requiring `2*pi` for full revolution.
- Narrow-gap mesh convergence: elements across gap, convergence table, and
  analytical comparison.

Evidence came from sessions 2-4, where the raw capacitance result was off by
`1/(2*pi)` until validated against a coaxial test.

### P0 - Strengthen electrostatic SIF templates

Update minimal and axisymmetric electrostatic examples to include explicit
linear solver settings, for example:

```sif
Solver 1
  Equation = Electrostatics
  Procedure = "StatElecSolve" "StatElecSolver"
  Variable = Potential
  Exec Solver = Always
  Linear System Solver = Direct
  Linear System Direct Method = umfpack
End
```

A greenfield GUI session hit:

```text
ERROR:: SolveLinearSystem: Give "Linear System Solver", e.g. "iterative" or "direct"
```

### P0 - Add an Elmer mesh-handoff contract

Do not add a Salome or SolidWorks recipe to the Elmer skill. Instead, add a
short Elmer-facing contract for any upstream mesher/CAD tool:

- The converted mesh must contain one body per material/domain that Elmer needs
  to solve.
- Boundary conditions must correspond to named mesh boundary groups, not just
  visual CAD edges.
- After `ElmerGrid`, inspect `mesh/mesh.names` and write SIF
  `Target Bodies`/`Target Boundaries` from those names or IDs.
- Do not assume CAD, STEP, Salome, or Gmsh labels survived conversion unchanged.
- For electrostatics, make sure the dielectric/air/fluid/rock region being
  solved is actually meshed; voltage boundary edges alone do not create a
  solve domain.
- For axisymmetric models, confirm the mesh is a valid `r-z` cross-section and
  that the axis/coordinate mapping are consistent before debugging solver
  settings.

Salome-specific operations such as Boolean Common, Partition, face/edge
selection, and geometry-vs-mesh group creation should live in a separate
CAD/meshing guide if needed, not in `elmer-fem/SKILL.md`.

### P1 - Add multiconductor/triaxial cable templates

Add a worked pattern for multiconductor electrostatics and R/L:

- Create center, shield, armor, and exterior dielectric/air/rock bodies.
- Run one electrostatic excitation per conductor.
- Assemble capacitance matrix.
- Check symmetry and row sums/consistency.
- Calibrate/compare against datasheet or analytical coax/triaxial formulas.
- Run circuit-coupled harmonic magnetic cases for return modes.
- Preserve `solver.log`, `capacitance.dat`, `scalars.dat`, result JSON, and
  plots.

Specific gotchas from the triaxial session:

- `SaveScalars` with `Filename = "scalars.dat"` writes beside `case.sif` by
  default; parse `case_dir/scalars.dat*`, not `case_dir/mesh/scalars.dat*`.
- `ElmerComponent(... body_id ...)` uses the Elmer SIF `Body N` number, not the
  Gmsh physical ID or `Target Bodies` ID.
- Avoid stale dependency pins such as `elmer-circuitbuilder>=0.4,<0.5`; the
  successful script used a modern `elmer-circuitbuilder` release.

### P1 - Add axisymmetric AC-loss / Joule-heating guidance

The current skill focuses on scalar impedance extraction from circuit output.
Transformer AC-loss sessions also needed a Joule-heating path:

- Use conductive copper with circuit-coupled `Massive` conductors.
- Use `MagnetoDynamicsCalcFields` to compute Joule heating.
- Integrate over axisymmetric elements as `q_e * 2*pi*r_centroid*area`.
- Convert power to resistance using the correct current convention, e.g.
  `R_ac = 2*P_avg/I_peak^2` for peak current.
- Document that primary-only and secondary-only solves capture active-family
  skin/proximity, not simultaneous primary-secondary redistribution.

### P1 - Add AC-loss validation hierarchy

Add a validation hierarchy for AC conductor loss/proximity:

1. Isolated round wire vs exact Bessel skin-effect solution.
2. TEAM Problem 2 transverse-field cylinder for pure proximity behavior.
3. Two parallel round conductors for current-coupled proximity.
4. Full cable/transformer regression only after the canonical tests pass.

Also warn that `R_ac` usually converges more slowly with mesh refinement than
L/C extraction.

### P1 - Add convergence and large-run artifact hygiene

Add checklist items for expensive Elmer studies:

- **Convergence hygiene:** rerun the same Elmer case with deliberately varied
  mesh profiles, timesteps, nonlinear/linear tolerances, or domain sizes; compare
  the physical quantities of interest against a finer/reference case; report
  relative deltas, not just "solver converged" or "runtime was acceptable".
- **Scalar reduction hygiene:** after a large Elmer run, reduce heavy field
  outputs to durable scalar engineering quantities such as C, R, L, energy,
  Joule loss, peak field, and matrix symmetry/error metrics; save those scalars
  with enough metadata to reproduce the run.
- Preflight disk space before ultra/fine VTU-producing runs.
- Prune, compress, or avoid writing intermediate VTUs after scalar reduction
  when fields are no longer needed.
- Keep deterministic reduced artifacts: result JSON/CSV, scalar files, logs,
  plots, and a manifest.
- Avoid project-specific advice about particular convergence CLI names, report
  generators, or design JSON schemas in the Elmer skill.

### P1 - Add generated-artifact audit and rerun guidance

Add an "artifact audit" subsection:

- Inspect output folder layout, manifest, `mesh.msh`, `mesh/mesh.names`, SIFs,
  logs, scalar files, and VTUs.
- Use globs for VTUs; Elmer often writes suffixes such as `fields_t0001.vtu`.
- If GUI apps regenerate FEM, hand-edited mesh/SIF files may be overwritten or
  ignored.
- Prefer rerunning from `design_snapshot.json` or equivalent source-of-truth
  configuration.
- For hand mesh edits: edit `mesh.msh`, rerun `ElmerGrid`, then rerun
  `ElmerSolver` with the intended SIF/startinfo.

### P2 - Add mesh-name and VTU parsing snippets

The skill already says to inspect `mesh.names`, but sessions hit parser
mistakes. Add snippets for:

- Elmer's common name format: `$ Name = ID`, not `ID = Name`.
- Building a `name -> id` map robustly.
- Verifying actual VTU arrays before assuming exported fields exist.
- If electrostatic VTU only contains `potential`, compute electric field from
  potential gradients or update the SIF to export the desired field.

### P2 - Add application integration boundary notes

Keep this short and Elmer-facing:

- Validate the Elmer workflow directly before GUI integration.
- Run Elmer/Gmsh workflows in reproducible, inspectable case directories.
- Prefer process-level isolation when embedding solver workflows in applications.
- Use persistent, inspectable run directories instead of opaque temp-only
  folders.

Detailed PyQt, Qt-threading, and GUI test guidance belongs in an application
integration guide, not in the Elmer skill.

### P2 - Expand Windows notes

Windows-specific additions:

- Always create `ELMERSOLVER_STARTINFO` in case directories.
- Locate `ElmerSolver.exe` and `ElmerGrid.exe` explicitly when PATH inheritance
  is unreliable.
- Resolve target directories before changing `cwd`; for
  `elmer-circuitbuilder`, after `chdir(case_dir)`, pass a local filename rather
  than an already case-prefixed path.

Do not add ngspice console behavior, Word/DOCX file locks, or Python-version
selection to the Elmer skill; those are useful session notes but not Elmer FEM
guidance.

## Scope adjustments before updating the skill

The following findings should remain in this feedback document but should not
be promoted into `skills/elmer-fem/SKILL.md` except as very short boundary
notes:

- **Detailed Salome 9.15 GUI workflow:** out of scope for Elmer. Keep only the
  mesh handoff contract and `ElmerGrid` conversion/`mesh.names` verification.
- **SolidWorks modeling tactics:** out of scope. Keep only the requirement that
  the mesh contain distinct material bodies and BC boundary groups.
- **ngspice automation and DOCX/report file locks:** unrelated to Elmer.
- **PyQt-specific thread failures:** mostly application/Gmsh integration
  material. The Elmer skill can say to use inspectable case directories and
  process isolation, but should not become a GUI integration guide.
- **Project-specific convergence CLIs, design JSON names, and report plotting
  assumptions:** keep only the general Elmer lesson: run mesh/timestep/tolerance
  sweeps, compare engineering scalars to a reference case, preserve metadata,
  and reduce large VTU-heavy runs into durable scalar outputs.
- **General Python dependency management:** only mention dependencies directly
  required by Elmer workflows, such as `elmer-circuitbuilder` for circuit
  coupling.

## Session-by-session findings

### 1. Windows: triaxial Prysmian cable study

- Session: `bebd3662-bbbe-4e38-be2a-b9b4b009d79e`
- Path: `/mnt/c/Users/hb60584/.copilot/session-state/bebd3662-bbbe-4e38-be2a-b9b4b009d79e`
- CWD: `D:\workdata\cheetah\surface-power-cable\prysmian-cable-characteristics`

**Summary:** Built a reproducible PN20500522 triaxial cable study using Elmer
electrostatics, Elmer harmonic magnetic R/L, ngspice transients, plots, and a
DOCX report. Final summary JSON reported electrostatic, magnetic, and SPICE
statuses OK.

**Friction:**

- `elmer-circuitbuilder>=0.4,<0.5` was unsatisfiable; final script used a
  modern `elmer-circuitbuilder` release.
- `SaveScalars` was initially parsed under `mesh/`, but output was in the case
  root.
- Circuit components needed SIF `Body N` IDs, not mesh/physical IDs.
- On Windows, `ngspice.exe` caused GUI/abort behavior; `ngspice_con.exe` was
  required for automation.
- Open report files caused DOCX write `PermissionError`.

**Best practices:**

- Create `ELMERSOLVER_STARTINFO` on Windows.
- Run separate electrostatic excitations and assemble a capacitance matrix.
- Preserve solver logs, scalar files, result JSON, and plots.
- Use visual critique of figures as a quality gate for engineering reports.

### 2. Linux: diode Cj / rod-through-plate capacitance

- Session: `81707f1d-ebe1-47b8-9468-264fe3528717`
- Path: `/home/dev/.copilot/session-state/81707f1d-ebe1-47b8-9468-264fe3528717`
- CWD: `/home/dev/temp/secondary-diode-sim`

**Summary:** Used Elmer FEM to validate a rod-through-plate capacitance model.
The FEM mechanics were useful, but the initial electrical interpretation of
the geometry was later corrected.

**Friction:**

- Axisymmetric capacitance output was effectively per-radian and required
  `2*pi` after coaxial validation.
- Geometry assumptions dominated: rods through plates were fiberglass, not
  copper return conductors.
- Capacitance extraction was improvised from `capacitance.dat`, energy logs,
  and scalars.
- Minor scripting friction: missing `scipy`, duplicate dependencies, and Elmer
  executable scoping.

**Best practices:**

- Validate against an analytical canonical case before trusting a custom FEM
  model.
- Inspect `mesh.names` and physical groups after conversion.
- Treat conductor/insulator classification as part of simulation setup.

### 3. Linux: Cj0 measurement / axisymmetric capacitance

- Session: `ee6cb9dc-4a1f-4673-950e-44685df6f481`
- Path: `/home/dev/.copilot/session-state/ee6cb9dc-4a1f-4673-950e-44685df6f481`
- CWD: `/home/dev/temp/secondary-diode-sim`

**Summary:** Similar diode capacitance investigation. Raw FEM result was about
2.032 pF; coax validation showed a `1/(2*pi)` ratio, leading to corrected
values around 12.765 pF per rod and 51.1 pF per plate for that model.

**Friction:**

- Axisymmetric normalization was not obvious.
- First runs missed `scipy`; `ELMER_GRID` scope failed.
- Material/body mapping risk showed up when fiberglass cases produced
  suspicious results.

**Best practices:**

- Capture `solver.log` and grep for capacitance/energy.
- Use STEP/CAD spatial extraction before simplifying to axisymmetry.
- Validate material mapping whenever dielectric changes violate intuition.

### 4. Linux: secondary diode assembly simulation

- Session: `90ab4b0a-887f-4bce-adee-f72509dbaddc`
- Path: `/home/dev/.copilot/session-state/90ab4b0a-887f-4bce-adee-f72509dbaddc`
- CWD: `/home/dev/temp/secondary-diode-sim`

**Summary:** Modeled a secondary diode assembly and used Elmer electrostatics
to validate parasitic capacitance assumptions.

**Friction:**

- Same axisymmetric per-radian scalar issue.
- FEM initially validated the wrong geometry because structural rods were
  assumed conductive.
- Script robustness issues around dependencies and executable path handling.

**Best practices:**

- Keep analytical estimates beside FEM results so order-of-magnitude mistakes
  are obvious.
- Use Elmer as validation, not as a substitute for geometry understanding.

### 5. Linux: transformer software update review

- Session: `dbf5d815-844c-4cf9-86d4-e631cda91b6f`
- Path: `/home/dev/.copilot/session-state/dbf5d815-844c-4cf9-86d4-e631cda91b6f`
- CWD: `/home/dev/repos/work/WARP/PcApps/Sandbox/cheetah/tools/dual-resonant-xfrmr-design`

**Summary:** Built digital validation workflow for transformer FEM
methodology: design JSON to geometry, Elmer/Gmsh setup, post-processing,
matrix/loss reduction, and SPICE export.

**Friction:**

- Convergence CLI initially generated plans instead of running profiles by
  default.
- AC loss was the least mesh-converged quantity; even `finest` differed from
  `ultra` by roughly 3.3-3.7 percent in `R_ac`.
- Large `ultra` run filled disk and produced truncated VTUs/XML/PMIX errors.
- Runtime estimates were inaccurate and were removed as quality gates.
- Report/plot generation initially assumed a fixed number of profiles.

**Best practices:**

- Treat Elmer, Gmsh, and ngspice as independent witnesses, not validation
  targets.
- Split validation into fast analytical tests, optional live FEM studies, and
  curated proof artifacts.
- Feed FEM AC loss into SPICE as fixed resistors only when the frequency
  assumption is compatible.

### 6. Windows: showerhead electrode CAD prep

- Session: `52a2c3c6-b226-4ae9-ad88-f78c710d1616`
- Path: `/mnt/c/Users/hb60584/.copilot/session-state/52a2c3c6-b226-4ae9-ad88-f78c710d1616`
- CWD: `D:\temp\showerhead-electrode`

**Summary:** Created simplified SolidWorks geometry for later Salome/Elmer
electrostatic/dynamic preparation.

**Friction:**

- STEP handoff was not used as the early acceptance test.
- Exact-touch multi-body CAD collapsed material interfaces on export/import.
- Artificial clearances became topology workarounds and risked changing
  electrostatics.
- Small offsets still snapped together in SolidWorks.
- Geometry mismatch was caught by user/visual review, not an FEM-readiness
  checklist.

**Best practices:**

- Define downstream import/partition requirements before modeling.
- Prefer separate same-origin components/assembly STEP for per-material
  regions.
- Use stable analysis-oriented names such as `center_electrode`,
  `nylon_insulator`, and `outer_ground_electrode`.
- For 2D axisymmetric FEM, clean region profiles matter more than decorative
  3D detail.

### 7. Windows: STEP geometry for FEM analysis

- Session: `b247dbf5-11cd-405e-aec8-8a252cbb3af7`
- Path: `/mnt/c/Users/hb60584/.copilot/session-state/b247dbf5-11cd-405e-aec8-8a252cbb3af7`
- CWD: `C:\Users\hb60584`

**Summary:** Advisory session for beginner-safe STEP to 2D axisymmetric
electrostatic workflow using SolidWorks, Salome 9.15, and Elmer/FEMM.

**Friction:**

- Early Salome instructions were wrong for the installed version; user reported
  no Boolean Section and then edge-only output.
- Workflow overused edge extraction/rebuilding.
- Salome selection model was unclear: parent compound vs sub-shapes, edge vs
  face vs wire vs group.

**Best practices:**

- Verify Salome version behavior before giving GUI paths.
- For Salome 9.15, prefer finite rectangle face plus Boolean Common and
  Partition to produce 2D faces directly.
- Exterior dielectric/rock/fluid domain is mandatory; Elmer solves only in
  meshed regions.
- Ideal electrodes can often be voltage boundary edges rather than meshed
  conductor interiors.

### 8. Linux: transformer discrepancy / AC-loss validation

- Session: `47704df0-93ae-4b57-96f7-2174ddbd89f9`
- Path: `/home/dev/.copilot/session-state/47704df0-93ae-4b57-96f7-2174ddbd89f9`
- CWD: `/home/dev/repos/work/WARP/PcApps/Sandbox/cheetah/tools/dual-resonant-xfrmr-design`

**Summary:** Moved from coupling discrepancy debugging into FEM-based AC-loss
and proximity validation.

**Friction:**

- Existing magnetic FEM used zero conductivity plus body-force current density,
  valid for inductance but not AC loss/proximity.
- Dowell-style proximity estimate overpredicted representative round-wire FEM.
- `elmer-circuitbuilder` path handling broke relative output directories by
  nesting `out/.../out/...`.
- Initial isolated-turn FEM validation was at risk of being mistaken for
  proximity validation.

**Best practices:**

- Separate inductance FEM from AC-loss FEM.
- Extract AC resistance from Joule heating rather than misleading DC-like
  scalar outputs.
- Validate in layers: skin effect, proximity benchmark, then full cable or
  transformer.
- Live tests should exercise the same top-level workflow used by the
  application.

### 9. Linux: greenfield air-core transformer design suite

- Session: `d7462394-7b41-4a02-979a-659e1a13486b`
- Path: `/home/dev/.copilot/session-state/d7462394-7b41-4a02-979a-659e1a13486b`
- CWD: `/home/dev/temp/oneshot-dual-resonant-transformer`

**Summary:** Built a PyQt5 air-core transformer suite with analytical
modeling, ngspice simulation, Elmer FEM verification, GUI inspection, and 3D
visualization. Elmer scope was constrained to axisymmetric electrostatic
stress/capacitance verification.

**Friction:**

- Gmsh/OpenCASCADE fragmentation invalidated simple entity-finding
  assumptions.
- `mesh.names` parser expected `ID = Name`, but Elmer wrote `$ Name = ID`.
- Electrostatic SIF failed without explicit linear solver settings.
- VTU initially contained only `potential`, not electric field.
- `gmsh.initialize()` failed in a Qt worker thread because signal handling
  requires the main thread.

**Best practices:**

- Use Elmer as a verification pass with clear claim boundaries.
- Inspect actual `mesh.names` and VTU arrays before downstream assumptions.
- Run solver workflows under GUI tests; direct solver tests did not expose Qt
  thread issues.
- Use subprocesses for Gmsh/Elmer integration in GUI apps.

### 10. Linux: dual-resonant audit findings

- Session: `db5b16b6-f292-4304-9fd3-14ff1055ffdf`
- Path: `/home/dev/.copilot/session-state/db5b16b6-f292-4304-9fd3-14ff1055ffdf`
- CWD: `/home/dev/repos/work/WARP/PcApps/Sandbox/cheetah/tools/dual-resonant-xfrmr-design`

**Summary:** Verified audit fixes and explained how to view, modify, and rerun
generated FEM artifacts.

**Friction:**

- User had to ask how to view/modify/rerun mesh artifacts; workflow was not
  obvious.
- Exact VTU/SIF paths required source inspection.
- Primary/secondary pitch mismatch had previously failed at runtime; GUI
  preflight was added.

**Best practices:**

- Rerun from `design_snapshot.json` or equivalent.
- Manual mesh edits require rerunning `ElmerGrid` before `ElmerSolver`.
- Validate physical IDs by syncing from `mesh/mesh.names`.
- Use artifact manifests and actual globbed VTU paths.

## Cross-session themes

### Modeling truth beats solver mechanics

The largest errors came from wrong geometry or wrong material/electrical role,
not from Elmer itself: fiberglass rods mistaken as conductors, exact-touch CAD
interfaces disappearing, or axisymmetric simplifications applied to geometry
with non-axisymmetric details.

### Verify scalar normalization with canonical cases

The axisymmetric capacitance issue appeared repeatedly. The skill should not
simply assert a universal rule without qualification; it should require a
canonical validation case and then document the observed `2*pi` correction as a
known Elmer axisymmetric electrostatics gotcha.

### Make outputs inspectable and rerunnable

Successful sessions kept `mesh.msh`, converted `mesh/`, `mesh.names`, SIFs,
logs, scalar files, JSON summaries, plots, and manifests. This made debugging
possible when VTU paths, scalar locations, or body IDs were misunderstood.

### Do not conflate validation scopes

Several sessions needed careful wording: skin-effect validation is not
proximity validation; Elmer/Gmsh/ngspice are independent numerical references,
not the app's own correctness proof; primary-only AC-loss solves do not prove
simultaneous primary-secondary redistribution.

### Prefer workflows that match production code

When validating an app, tests should call the same workflow functions/scripts
that production uses. Parallel toy SIFs can validate Elmer concepts but do not
prove the application path.

## Candidate insertion points in `SKILL.md`

- After section 2: add a mesh-handoff contract for any upstream mesher/CAD
  tool, centered on Elmer bodies, boundary groups, `ElmerGrid`, and
  `mesh.names`.
- In section 3: make electrostatic skeleton production-safe with explicit
  linear solver settings.
- In section 5: add axisymmetric scalar-output caution and validation recipe.
- After section 5 or before current section 6: add electrostatic capacitance
  extraction and capacitance-matrix workflows.
- In section 6: add SIF Body number vs physical ID note for
  `ElmerComponent`, SaveScalars path note, and AC-loss/Joule integration
  guidance.
- In section 7: add VTU field verification/fallback and artifact audit/rerun
  guidance.
- In section 9: expand Windows guidance for `ELMERSOLVER_STARTINFO`, explicit
  Elmer executable discovery, and `elmer-circuitbuilder` cwd/path behavior.
- In section 10: add symptoms for per-radian capacitance, missing/incorrect
  mesh bodies or boundary groups, missing linear solver settings, missing VTU
  fields, wrong scalar-file path assumptions, and SIF Body vs physical ID
  confusion.
