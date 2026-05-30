# Ngspice skill feedback from prior Copilot sessions

Generated: 2026-05-29

Scope: ten recent Linux and Windows Copilot sessions involving non-trivial
ngspice circuit simulation. Each session was reviewed by a separate GPT-5.5
investigator, then consolidated here for deciding future updates to
`skills/circuit-sim/SKILL.md`.

## Executive summary

The current `circuit-sim` skill already captures several lessons from prior
work: title-line requirements, `.control` vs `-b -r`, `UIC`, binary rawfile
parsing, `.step` handling, current-probe key mismatch, multi-winding `K`
syntax, differential monitor sources, stiff pulsed-power solver options, and
analysis-netlist instrumentation.

The recurring remaining gaps are:

1. **Batch automation needs a more explicit reliability contract.** Sessions
   repeatedly needed console ngspice on Windows, timeouts, return-code checks,
   rawfile existence checks, log scanning, project-relative output paths, and
   a manifest of generated artifacts.
2. **Current and CSV extraction remain the largest data-interface friction.**
   `wrdata` can repeat time columns, device currents are not always named or
   exported as expected, internal subcircuit currents may be absent or zero,
   and failed runs can leave empty rawfiles.
3. **Topology and polarity validation matter as much as syntax.** Several
   ngspice decks ran successfully while modeling the wrong physical connection,
   wrong transformer polarity, wrong diode conduction direction, or wrong
   switched-vs-permanently-connected load assumption.
4. **Transient post-processing needs reusable validation patterns.** Common
   needs were sign-aware peak detection, energy integration, reversal ratio,
   `f0`/`Z0` sanity checks, waveform overlays, stale-artifact prevention, and
   comparison against analytical or independent-solver references.
5. **Generated large-system netlists need stronger guidance.** Exporters need
   safe names, scientific notation, deterministic working directories, `.save`
   discipline, K-coupling generation checks, per-section-vs-equivalent
   parameter labels, and clear model-scope comments.
6. **Stiff switched circuits need modeling guidance, not just solver options.**
   Gear/BDF settings helped, but convergence was also improved by finite
   `RON`/`ROFF`, hysteresis, leakage paths, delayed/non-overlap switching,
   smoothed behavioral sources, and replacing ideal CC/CV clamps with labeled
   Thevenin/current-limit approximations when appropriate.

## Sessions reviewed

| # | Source | Session | Topic |
|---:|---|---|---|
| 1 | Windows | `bebd3662-bbbe-4e38-be2a-b9b4b009d79e` | Triaxial cable recharge simulation |
| 2 | Linux | `dbf5d815-844c-4cf9-86d4-e631cda91b6f` | Transformer validation suite |
| 3 | Linux | `d7462394-7b41-4a02-979a-659e1a13486b` | Air-core transformer GUI with live ngspice |
| 4 | Linux | `77731906-3b99-469f-b232-305997646bb0` | Dedicated transformer ngspice verification |
| 5 | Linux | `db558530-0887-4b73-8609-d18d5edca0c9` | 200 kV-class pulsed-load simulation |
| 6 | Linux | `5042bcae-08d9-44a1-b652-2d1b937ae40c` | Primary capacitor test model |
| 7 | Linux | `a17933ef-3a37-4de9-8da6-90d884490358` | FEM-to-SPICE waveform pipeline |
| 8 | Linux | `39cedae2-0c3a-4cfd-a87b-cf5426bacf2a` | Complete pulsed-power SPICE simulation |
| 9 | Linux | `bd881ca1-2f0a-4bd1-bb4c-be0ada8aaa5d` | Diode clipping and waveform validation |
| 10 | Linux | `beea1ba6-3b5b-4718-996d-c91a71de50ef` | Saturable-inductor/magnetic-switch debugging |

## Recommended skill updates

### P0 - Add a batch automation reliability checklist

The skill should state a repeatable contract for unattended ngspice runs:

- Prefer `.control` blocks with `run`, `write` or `wrdata`, and `quit` when
  `.meas` or CSV export is needed.
- Prefer `ngspice -b -r output.raw circuit.cir` for simple no-`.meas` rawfile
  generation.
- On Windows automation, prefer console `ngspice_con.exe` over GUI
  `ngspice.exe`; GUI builds can create popups and empty logs.
- Run from a deterministic working directory, usually the netlist directory.
- Use project-relative or caller-specified output directories, not hardcoded
  scratch paths.
- Check return code, stdout/stderr, rawfile existence, rawfile nonzero point
  count, and expected variables before post-processing.
- Use timeouts for sweep cases so one failing deck cannot hang the study.
- Grep logs for high-signal failure terms: `error`, `fatal`, `singular`,
  `timestep`, `convergence`, `timeout`, and `aborted`.
- Record the ngspice executable path/version and generated artifact paths in
  a JSON/CSV manifest.

Add a pitfall entry:

| Symptom | Cause | Fix |
|---|---|---|
| `write output.raw` is reported as an unknown model/element or rawfile is not created | A control command was parsed as circuit syntax, often because `.control/.endc` is missing or a loose control script was run as a netlist | Put `run`/`write` inside `.control ... .endc` in a complete netlist with title and `.end`, then run `ngspice -b circuit.cir` |
| Batch run says no simulations ran | No usable `.control`, `.plot`, `.print`, `.fourier`, `.save`, or raw output path | Add `.control` with `run` and `write output.raw`, or run with `-b -r output.raw` |
| Rawfile exists but parser crashes or arrays are empty | ngspice failed after opening the file, or wrote zero points | Inspect return code/log and rawfile header before parsing data arrays |

### P0 - Strengthen current measurement and data extraction guidance

Add a dedicated section for current and CSV extraction:

- Always list variables once before indexing:

  ```python
  from parse_rawfile import parse_rawfile_header

  header = parse_rawfile_header("output.raw")
  for var in header["variables"]:
      print(var["name"], var["type"])
  ```

- Do not assume branch-current names. Depending on the element and output mode,
  currents may appear as `i(lname)`, `i(vsense)`, or `i(@lname[i])`.
- For arbitrary branch current, insert a zero-volt sense source:

  ```spice
  Vsense n1 n2 DC 0
  .save i(Vsense)
  ```

- For resistor current, compute from node voltages when that is simpler and
  less ambiguous:

  ```python
  i_load = (v_pos - v_neg) / r_load
  ```

- For capacitor current in post-processing, derive `I = C*dV/dt` when the
  internal device current is unavailable or suspect.
- Warn that internal subcircuit passive currents may not be emitted, may use
  hierarchical names, or may not be the signal the user intended.
- Document `wrdata` CSV shape: output can be `time1 value1 time2 value2 ...`
  even with single-scale settings. Parsers should tolerate repeated scale
  columns and map columns by vector names, not position alone.
- Treat `wrdata @device[i]` with caution. Prior sessions saw wrong or
  misleading magnitudes; use rawfile currents, a sense source, or node-derived
  current when high confidence is required.

### P0 - Add topology and polarity validation before trusting results

Multiple sessions had valid ngspice runs with invalid modeling assumptions.
Add a checklist before optimization/reporting:

- What is physically connected at `t=0`?
- Is the load permanently connected, diode-gated, actively switched, or absent?
- Is every switch backed by an actual modeled control source or device?
- Are initial conditions physical, and is `.tran ... UIC` present when using
  component `ic=`?
- Do all non-ground nodes have a DC path or intentional leakage/reference path?
- Does the simulated topology match the schematic/block diagram?
- Are idealizations such as switches, clamps, CC/CV sources, and simplified
  Thevenin equivalents clearly labeled?

Add a polarity checklist for transformers and rectifiers:

- In ngspice coupled inductors, the first node of each inductor is the dotted
  terminal for `K` sign reasoning.
- Validate polarity on a one-stage/minimal deck before scaling to many windings.
- For diode orientation, reason from `Dname anode cathode model`; for negative
  rail conduction, verify the expected half-cycle from data, not just symbol
  intuition.
- After any diode or transformer-terminal change, parse positive and negative
  peak magnitudes and times from the rawfile.
- Compare magnitude separately from sign when matching another solver, because
  sign flips are often convention errors rather than physics errors.

### P0 - Add transient validation and post-processing recipes

Common transient studies needed more than plots. Add compact recipes for:

- Sign-aware peak detection:

  ```python
  idx_min = int(np.argmin(vout))
  idx_max = int(np.argmax(vout))
  v_neg_peak, t_neg_peak = vout[idx_min], time[idx_min]
  v_pos_peak, t_pos_peak = vout[idx_max], time[idx_max]
  ```

- Absolute peak for bipolar waveforms:

  ```python
  idx_abs = int(np.argmax(np.abs(vout)))
  v_abs_peak = vout[idx_abs]
  ```

- Resistive-load energy:

  ```python
  p_load = v_load * v_load / r_load
  e_load = np.trapezoid(p_load, time)
  ```

- RLC sanity checks: natural frequency, impedance, expected peak current,
  reversal percentage, and conservation of stored energy.
- Waveform witness overlays: compare related nodes such as source capacitor,
  diode output, and load node to confirm diode/switch action.
- Stale artifact prevention: regenerate plots/CSV/JSON after netlist changes
  and print key metrics from the plotting script so stale figures are obvious.

### P1 - Add generated-netlist/exporter hygiene

For programmatic SPICE exporters, add guidance to:

- Use safe deterministic SPICE names and avoid characters that complicate
  rawfile lookup.
- Emit numeric values in scientific notation to avoid suffix ambiguity.
- Keep design netlists separate from instrumented analysis copies.
- Insert instrumentation before the final `.end`; when replacing directives,
  consume continuation lines beginning with `+`.
- Use `.save` aggressively for large generated systems to reduce rawfile size.
- Emit explicit differential monitor sources for frequently plotted signals:

  ```spice
  E_mon vdiff 0 node_p node_n 1
  ```

- Use deterministic case directories for sweeps and write a manifest containing
  original netlist, instrumented netlist, rawfile, log, metrics JSON/CSV, and
  plots.
- For generated coupled-inductor models, define all `L` elements before any
  `K` statements, clamp `|k| < 1`, count expected coupling statements, and
  validate against a reduced model.
- Label per-section values separately from series/parallel equivalent values.
  Several transformer errors came from mixing these conventions.
- Add model-scope comments directly in exported netlists, for example when a
  fixed-frequency `R_ac` is represented as an ordinary constant resistor in a
  transient simulation.

### P1 - Add solver-comparison and CI parity guidance

ngspice was often used as an independent witness against a Python/ODE/FEM
pipeline. Add a small pattern:

- Make live ngspice tests optional:

  ```python
  import shutil
  import pytest

  pytestmark = pytest.mark.skipif(
      shutil.which("ngspice") is None,
      reason="ngspice not installed",
  )
  ```

- Run with timeout and include stdout/stderr on failure.
- Assert the rawfile or CSV exists and contains nonzero data.
- Compare scalar metrics and waveform overlays, not only solver success.
- Interpolate adaptive ngspice timesteps before RMS/error comparison with a
  fixed-step solver.
- Compare sign, magnitude, timing, and energy separately so a polarity
  convention mismatch does not hide a magnitude error.
- For `.meas` parsing, parse declared measurement names or filter ngspice
  status/memory lines. Prior code accidentally captured lines such as
  `doing analysis at temp` and memory statistics as measurements.
- Use both `MAX` and `MIN`, or post-process absolute peak in Python, for
  bipolar transient waveforms.

### P1 - Expand stiff switched-transient modeling advice

The current convergence table is useful; add modeling advice that prevents the
hard cases:

- Use finite switch `RON`/`ROFF` and hysteresis (`VT`, `VH`) instead of ideal
  discontinuities.
- Add leakage/reference resistors for floating nodes.
- Delay initial switching or use non-overlap PWL controls when possible.
- Smooth behavioral-source transitions; save internal state nodes for debug.
- Avoid ideal behavioral CC/CV clamps in stiff switched ladders when a finite
  Thevenin/current-limit equivalent is adequate. If simplified, label the model
  and validate the engineering effect.
- Add damping resistance where it represents real loss or a numerical proxy
  that has been justified.
- For failed aggressive cases, inspect whether the circuit topology or
  behavioral discontinuity is the root cause before only relaxing tolerances.

### P2 - Add reusable examples

These examples should be generic and compact, not project-specific:

1. **Pulsed capacitor/RLC ring-down**
   - Precharged capacitor with `ic=`.
   - `.tran ... UIC`.
   - Triggered switch.
   - Voltage reversal and energy balance.
   - Current from resistor voltage or a sense source.

2. **Diode-gated permanently connected load**
   - Demonstrates that a diode can naturally gate current without an explicit
     load switch.
   - Includes polarity checks and overlay of capacitor, diode, and load nodes.

3. **Multi-winding transformer smoke test**
   - One-stage polarity check.
   - Programmatic `K` generation for a small matrix.
   - Rawfile header listing for current-name discovery.

4. **Advanced saturable-inductor/magnetic-switch pattern**
   - Present as an advanced behavioral-source example only.
   - Include internal flux-state saving, threshold verification, smoothing, and
     convergence cautions.
   - Avoid project-specific magnetic-core design claims.

## Opportunities for helper script improvements

These are optional implementation ideas for `skills/circuit-sim/scripts/`:

- Add a `--list-vars` or more prominent summary mode in `run_sim.py` that
  prints rawfile variables and current-like vectors before plotting.
- Add a `get_signal(data, name)` helper that lowercases names and tries common
  aliases such as `@l1[i]`, `i(@l1[i])`, and `i(l1)` before failing with a
  sorted list of available keys.
- Add a `validate_rawfile(path, expected=None)` helper that checks header,
  nonzero point count, and expected signals.
- Add a `wrdata` CSV parser helper that tolerates repeated scale columns.
- Add output-directory and save-list options to `run_sim.py` so callers do not
  need to create ad hoc instrumented copies for common workflows.

## Scope adjustments before updating the skill

The following lessons are useful context but should not be promoted into the
ngspice skill except as narrow, generic notes:

- Cheetah, RePED, Tetra, Halliburton, transformer, cable, capacitor, or drill
  hardware values and design conclusions.
- FEM/Elmer/Gmsh extraction workflows, mesh details, capacitance-matrix setup,
  or VTU/report artifacts. Only the generic FEM-to-SPICE handoff concept
  belongs here.
- PyQt GUI layout, threading, 3D visualization, and widget implementation
  details, except the general note to run ngspice off the UI thread with
  timeout and surfaced errors.
- DOCX/PPTX/report-generation, figure numbering, and presentation layout.
- Circuitikz, KiCad, or schematic rendering details; those belong in
  `netlist-to-schematic`.
- LTspice `.asc` generation strategy. A short portability note is useful, but
  detailed LTspice export belongs elsewhere.
- Product-specific safety procedures, acceptance criteria, materials, part
  numbers, packaging, cooling, or lab qualification steps.

## Per-session notes

### 1. Triaxial cable recharge simulation

Key lessons: Windows automation should use `ngspice_con.exe`; ideal CC/CV
behavioral sources can make switched ladders fragile; `wrdata` may duplicate
time columns; console executable, timeouts, log scans, and result manifests are
important for batch studies.

### 2. Transformer validation suite

Key lessons: live ngspice parity should skip cleanly when unavailable; generated
comparison netlists should add `.control`/`wrdata` without overwriting design
netlists; fixed-frequency FEM-derived `R_ac` must be labeled as a constant
transient resistor.

### 3. Air-core transformer GUI with live ngspice

Key lessons: stdout `.meas` parsing needs filtering or an allowlist; generated
netlists should use scientific notation and reference/leak paths; hierarchical
subcircuit branch-current names surprise analysis code; `.save` is needed for
large generated networks.

### 4. Dedicated transformer ngspice verification

Key lessons: `-b -r` is robust for simple no-`.meas` raw output; transformer
polarity can cause large false mismatches; rawfile headers should be inspected
before guessing current variables; adaptive ngspice output needs interpolation
for solver comparisons.

### 5. Pulsed-load simulation

Key lessons: topology assumptions must be checked before simulation. A switched
load model produced plausible but wrong results because the physical load was
permanently connected. Sign-aware negative peak and energy calculations were
essential.

### 6. Primary capacitor test model

Key lessons: `wrdata @device[i]` branch currents can be misleading; computing
current from node voltages fixed energy accounting. Plots must be regenerated
after netlist/export changes, and headless plots are better handled with
matplotlib than ngspice hardcopy.

### 7. FEM-to-SPICE waveform pipeline

Key lessons: keep design and instrumented analysis netlists separate; preserve
`UIC`; classify benign warnings such as trigger-source PULSE DC warnings;
consume continuation lines when replacing directives; record raw/log/metrics
artifacts.

### 8. Complete pulsed-power SPICE simulation

Key lessons: `SW` uses `VT`/`VH`, not LTspice-style `VON`/`VOFF`; no-output
batch runs need `.control` or `-r`; dot convention and diode orientation must
be validated from waveform peaks; sense sources and monitor sources simplify
analysis.

### 9. Diode clipping and waveform validation

Key lessons: waveform theory and documentation must be checked against raw
simulation data; negative-rail diode orientation is easy to reverse; zero-volt
sense sources avoid missing current variables; simplified presentation circuits
must state which parasitics were removed.

### 10. Saturable-inductor/magnetic-switch debugging

Key lessons: behavioral magnetic-switch models need saved internal state,
threshold validation, smoothing, and damping; failed runs can leave zero-point
rawfiles; parameter sweeps should use generated templates or `.step`/control
loops instead of brittle regex edits to `.param` lines.
