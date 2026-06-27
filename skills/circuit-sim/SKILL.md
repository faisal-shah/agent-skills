---
name: circuit-sim
description: >
  Simulate a circuit, run a SPICE simulation, or analyze circuit behavior
  (AC/DC/transient). Use when asked to simulate, plot waveforms, sweep
  parameters, measure rise time, check frequency response, or parse
  simulation output from a .cir/.spice netlist.
---

# Circuit Simulation Skill

Drive ngspice from the command line to simulate analog/mixed-signal circuits.
This skill covers the full workflow: write a netlist, run batch simulation,
parse binary output, and plot results with matplotlib.

> **Schematic diagrams:** To convert a netlist into a circuit schematic, use
> the `netlist-to-schematic` skill instead.

## Prerequisites

- `ngspice` installed and on `PATH` (`ngspice --version` to verify)
- Windows automation: prefer console `ngspice_con.exe` when available; GUI
  `ngspice.exe` can create popups and empty logs in unattended runs
- Python 3.10+ with `numpy` and `matplotlib` (use `uv run` with inline metadata)

---

## 1. Netlist Syntax (SPICE3 Format)

```spice
Title Line (REQUIRED — first line is always the title, never a command)
* Comments start with asterisk

* === Component Syntax ===
* Resistor:    Rname node+ node- value
* Capacitor:   Cname node+ node- value [ic=voltage]
* Inductor:    Lname node+ node- value [ic=current]
* Diode:       Dname anode cathode modelname
* BJT:         Qname collector base emitter modelname
* MOSFET:      Mname drain gate source bulk modelname W=w L=l
* VCVS:        Ename out+ out- ctrl+ ctrl- gain
* Voltage src: Vname node+ node- [DC val] [AC mag [phase]] [transient_func]
* Current src: Iname node+ node- [DC val] [AC mag [phase]]

* === Subcircuit Definition ===
.subckt name port1 port2 ...
* ... components ...
.ends name

* === Parameters ===
.param Rval=1k Cval=100n

* === Models ===
.model NMOS1 NMOS (VTO=0.7 KP=110u)
.model D1N4148 D (IS=2.52e-9 RS=0.568)

* === Include External Files ===
.include "models/opamp.lib"

* === Analysis Commands (pick one or more) ===
.op                              * DC operating point
.dc Vin 0 5 0.1                  * DC sweep: source start stop step
.ac dec 100 1 1e6                * AC sweep: dec/oct/lin Npts fstart fstop
.tran 1u 10m                     * Transient: step stop [start [max_step]] [UIC]
.step param Rval 50 200 50       * Parameter sweep

* === Measurements ===
.meas tran rise_time TRIG v(out) VAL=0.1 RISE=1 TARG v(out) VAL=0.9 RISE=1
.meas ac f3dB WHEN vdb(out)=-3 FALL=1
.meas dc vout_max MAX v(out)

* === Control Block (batch mode) ===
.control
run
wrdata output.csv v(out) v(in)
write output.raw v(out)
quit
.endc

.end
```

### Key Rules
- **First line is ALWAYS the title** — not a dot-command, not a comment
- **Node `0` is ground** — every circuit must reference node 0
- **Node names are case-insensitive** in standard ngspice
- **Value suffixes:** `f`=1e-15, `p`=1e-12, `n`=1e-9, `u`=1e-6, `m`=1e-3,
  `k`=1e3, `meg`=1e6, `g`=1e9, `t`=1e12
- **SPICE treats `M` as milli** (1e-3), use `MEG` for mega (1e6)

---

## 2. Running ngspice in Batch Mode

**Preferred: `.control` block** — embed run + write commands directly in the netlist.
This is the most reliable pattern and works with `.meas` directives:

```spice
.control
run
write output.raw
quit
.endc
```

Run with: `ngspice -b circuit.cir`

Keep the trailing `quit`: in batch `.control` decks, omitting it can leave a
success-shaped run with a nonzero process exit. Smoke runners must propagate the
return code and inspect logs, not just parse output files.

**Simple alternative:** `ngspice -b -r output.raw circuit.cir` writes all signals
automatically — but **silently suppresses `.meas` results**. Use only without `.meas`.

`scripts/run_sim.py` handles this automatically — detects `.meas` and injects
a `.control` block when needed.

### Batch Automation Reliability

For unattended or generated studies, treat a run as valid only after checking:

- deterministic working directory (usually the netlist directory)
- project-relative or caller-specified output paths, not hardcoded scratch paths
- return code plus stdout/stderr
- rawfile exists and has nonzero points
- expected variables are present before indexing
- timeout for sweeps or generated cases
- high-signal log terms: `error`, `fatal`, `singular`, `timestep`,
  `convergence`, `timeout`, `aborted`, `no simulations run`, failed `.meas`
- manifest with ngspice executable/version, netlist, rawfile, log, metrics, and
  plot paths

Common batch failures:

| Symptom | Cause | Fix |
|---|---|---|
| `write output.raw` is reported as an unknown model/element | Control command parsed as circuit syntax | Put `run`/`write` inside `.control ... .endc` in a complete netlist, then run `ngspice -b circuit.cir` |
| Batch run says no simulations ran | No usable `.control`, `.print`, `.plot`, `.save`, or raw output path | Add `.control` with `run` + `write output.raw`, or use `-b -r output.raw` |
| Rawfile exists but arrays are empty | Run failed after opening the file | Inspect return code/log and rawfile header before parsing data |
| Output files exist but process return code is nonzero | `.control` did not terminate cleanly, often missing `quit` | Add `quit`; fail the automation until rc/logs are clean |

### Selective Output with .save

To reduce rawfile size, specify which signals to save:

```spice
.save v(out) v(in) i(Vpower)
```

### Initial Conditions and UIC

**This is a critical gotcha.** The `UIC` (Use Initial Conditions) flag on `.tran`
controls whether ngspice uses `ic=` values set on capacitors and inductors.

```spice
* Pre-charged capacitor and inductor with initial current
Cp node+ node- 12u ic=15000
Lp node+ node- 6u ic=0.5
.tran 1u 10m UIC
```

**Without `UIC`** (default): ngspice computes a DC operating point first —
capacitors open, inductors shorted — and **silently ignores** all `ic=` values.
This produces all-zero waveforms for stored-energy circuits.

**With `UIC`**: skips DC OP, initializes directly from `ic=` values. Essential for
pre-charged capacitors, oscillator startup, or any energy-storage circuit.

**`ic=` vs `.ic`**: `ic=` on components requires `UIC`; `.ic V(node)=val` is a
post-DC-OP constraint (different mechanism, does NOT require `UIC`).

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| All-zero waveforms despite `ic=` on caps | `.tran` missing `UIC` | Add `UIC` to `.tran` line |
| Capacitor starts at 0V not expected voltage | DC OP overrides `ic=` | Add `UIC` to `.tran` line |

---

## 3. Parsing Binary Rawfiles (Python)

The rawfile is the **primary data exchange format**. Use `scripts/parse_rawfile.py`:

```python
from parse_rawfile import parse_rawfile, parse_rawfile_all

data = parse_rawfile("output.raw")
# Returns dict: variable_name → numpy array (complex for AC, real-as-complex for DC/tran)

# For multi-run rawfiles (.step param sweeps, multiple analyses):
runs = parse_rawfile_all("output.raw")  # list of dicts, one per run
```

AC data is complex; DC/transient is real (stored as complex with zero imaginary).
Use `np.real()` for time/DC values, `np.abs()`/`np.angle()` for AC.

```python
data = parse_rawfile("output.raw")
time = np.real(data["time"])        # Transient
vout_ac = data["v(out)"]           # AC: complex → use np.abs(), np.angle()
mag_dB = 20 * np.log10(np.abs(vout_ac))
```

Always inspect variables once before writing analysis code:

```python
from parse_rawfile import parse_rawfile_header

header = parse_rawfile_header("output.raw")
for var in header["variables"]:
    print(var["name"], var["type"])
```

### Current and CSV Extraction

Do not assume branch-current names. Depending on the element and output mode,
currents may appear as `i(lname)`, `i(vsense)`, or `i(@lname[i])`.

When saving inductor/device branch currents, the `.save` directive form and the
rawfile key differ:

| `.save` directive | rawfile key | Notes |
|---|---|---|
| `v(out)` | `v(out)` | Voltage probes: consistent |
| `@l_p1[i]` | `i(@l_p1[i])` | Branch currents get `i()` wrapper |

Always look up currents by the **rawfile key** (`i(...)` form), not the `.save`
form. This mismatch causes `KeyError` crashes in analysis scripts.

For arbitrary branch current, insert a zero-volt sense source:

```spice
Vsense n1 n2 DC 0
.save i(Vsense)
```

For resistor current, compute from node voltages when that is simpler and less
ambiguous:

```python
i_load = (v_pos - v_neg) / r_load
```

For capacitor current, post-process `I = C*dV/dt` when internal device current
is unavailable or suspect. Internal subcircuit passive currents may be omitted,
hierarchically named, or not the signal intended.

`wrdata` CSV output can be `time1 value1 time2 value2 ...` even with a single
scale. Parse by vector names or tolerate repeated scale columns, not by fixed
column positions. Treat `wrdata @device[i]` current export with caution; when
high confidence matters, prefer rawfile currents, a sense source, or
node-derived current.

CLI: `uv run scripts/parse_rawfile.py output.raw [--json | --csv]`

---

## 4. Analysis Patterns

### 4a. AC Analysis (Bode Plot)

```spice
Bandpass Filter
Vin in 0 AC 1
L1 in mid 1mH
C1 mid out 253nF
R1 out 0 100
.ac dec 100 10 1e6
.end
```

### 4b. Transient Analysis

```spice
RC Step Response
Vin in 0 PULSE(0 1 0 1n 1n 5m 10m)
R1 in out 1k
C1 out 0 1u
.tran 10u 20m
.end
```

### 4c. DC Sweep

```spice
Diode IV Curve
Vd anode 0 DC 0
D1 anode 0 DMOD
.model DMOD D (IS=1e-14)
.dc Vd 0 0.8 0.001
.end
```

### 4d. Parameter Sweep with .step

```spice
R Sweep
Vin in 0 AC 1
R1 in out {Rval}
C1 out 0 1n
.param Rval=1k
.step param Rval 500 2k 500
.ac dec 50 1 100MEG
.end
```

The rawfile contains multiple runs. Use `parse_rawfile_all()` to get a list of
dicts, one per run. `run_sim.py` handles this automatically with `result.all_runs`.

### 4e. Transient Post-Processing Checks

Do not trust plots alone for pulsed or bipolar waveforms. Reduce each run to
engineering scalars:

```python
time = np.real(data["time"])
vout = np.real(data["v(out)"])

idx_min = int(np.argmin(vout))
idx_max = int(np.argmax(vout))
v_neg_peak, t_neg_peak = vout[idx_min], time[idx_min]
v_pos_peak, t_pos_peak = vout[idx_max], time[idx_max]

idx_abs = int(np.argmax(np.abs(vout)))
v_abs_peak, t_abs_peak = vout[idx_abs], time[idx_abs]
```

For resistive-load energy:

```python
p_load = v_load * v_load / r_load
e_load = np.trapezoid(p_load, time)
```

For RLC ring-down cases, compare against sanity checks before reporting:

- natural frequency: `f0 = 1 / (2*pi*sqrt(L*C))`
- impedance: `Z0 = sqrt(L/C)`
- expected peak current: `Ipk ≈ V0 / Z0`
- reversal percentage and total stored/dissipated energy
- positive and negative peak times/magnitudes separately

Regenerate CSV/JSON/plots after every netlist change and print key metrics from
the plotting script so stale artifacts are obvious.

### 4f. Pulsed Capacitor / RLC Ring-Down

Use this pattern for precharged stored-energy circuits:

```spice
Pulsed RLC Ringdown
.param V0=15000 C0=0.5u L0=100u RLOAD_VAL=2
Vtrig trig 0 PULSE(0 1 50u 100n 100n 500u 1m)
C1 cap 0 {C0} ic={V0}
Sfire cap n1 trig 0 SWFIRE
L1 n1 n2 {L0}
Rload n2 0 {RLOAD_VAL}
.model SWFIRE SW(VT=0.5 VH=0.05 RON=10m ROFF=1G)
.tran 0.1u 500u UIC
.save v(cap) v(n2) i(L1)
.control
run
write output.raw
quit
.endc
.end
```

If branch current naming is ambiguous, add a zero-volt sense source in series
with the load or compute current from `V/R`.

---

## 5. Monte Carlo / Tolerance Analysis

ngspice has no built-in Monte Carlo. Use Python to randomize and loop:

```python
rng = np.random.default_rng(42)
for i in range(200):
    r = R_NOM * (1 + rng.uniform(-0.05, 0.05))    # ±5%
    c = C_NOM * (1 + rng.uniform(-0.10, 0.10))    # ±10%
    netlist = make_netlist(r, c)
    results.append(simulate(netlist))
```

---

## 6. Temperature Sweep

ngspice `.temp`/`.step temp` only affects semiconductor models, not passive RLC.
For passives, apply TC manually: `R(T) = R_nom × (1 + TC × (T - 25))`.

```spice
.step temp -40 150 10    * sweep semiconductor temperature
```

---

## 7. Measurements (.meas)

`.meas` extracts scalar metrics. `run_sim.py` parses them automatically.

```spice
.meas ac f_3dB WHEN vdb(out)=-3 FALL=1
.meas tran risetime TRIG v(out) VAL=0.1 RISE=1 TARG v(out) VAL=0.9 RISE=1
.meas tran overshoot MAX v(out)
```

Manual parsing from stdout: parse only declared measurement names, or filter
ngspice status/memory lines such as `doing analysis at temp` and
`total elapsed time`. Use both `MAX` and `MIN`, or post-process absolute peaks
in Python, for bipolar transient waveforms.

ngspice `.meas` is less portable than raw/CSV post-processing. If
`.meas FIND v(a,b)` or expressions such as `abs(i(...))` fail, define helper
vectors in `.control` (`let vd = v(a)-v(b)`), add a differential monitor or
zero-volt sense source, or compute the metric from saved raw/CSV data in Python.

---

## 8. Plotting Conventions

Always set the Agg backend **before** importing pyplot — headless environments
hang or error otherwise:

```python
import matplotlib
matplotlib.use("Agg")  # must come before pyplot import
import matplotlib.pyplot as plt
```

---

## 9. ngspice Quick Reference

Common elements beyond R/L/C that the AI may need:

| Element | Syntax | Notes |
|---------|--------|-------|
| Coupled inductors | `Kname L1 L2 coupling` | k=0 to 1; define both L elements first |
| V-controlled switch | `Sname n+ n- ctrl+ ctrl- model` | `.model name SW(VT=0 VH=0.1 RON=1 ROFF=1e6)` |
| I-controlled switch | `Wname n+ n- Vctrl model` | `.model name CSW(IT=0 IH=0.1 RON=1 ROFF=1e6)` |
| Behavioral source | `Bname n+ n- V={expr}` | or `I={expr}`; any math on node voltages |
| Ideal transformer | Two `L` + `K` statement | No standalone transformer element |
| VCVS | `Ename out+ out- ctrl+ ctrl- gain` | Ideal voltage amplifier |
| CCCS | `Fname out+ out- Vsense gain` | Current controlled by current through Vsense |
| Diode | `Dname anode cathode model` | `.model name D(IS=1e-14 BV=100)` |
| Transmission line | `Tname p1+ p1- p2+ p2- Z0=50 TD=1n` | Lossless |

**V-controlled switch polarity tip**: the switch closes when `V(ctrl+) - V(ctrl-) > VT`.
For negative output voltages, swap control nodes so the difference is positive.

Full syntax reference: https://ngspice.sourceforge.io/docs/ngspice-html-manual/manual.xhtml

### Coupled Inductors (Transformers)

ngspice has no standalone transformer element. Model with two inductors + a K
coupling statement. Turns ratio ≈ √(L2/L1).

```spice
* Iron-core power transformer: 1:10 turns ratio, k=0.95
Lpri  pri_top  pri_bot  1m
Lsec  sec_top  sec_bot  100m
KTR   Lpri Lsec 0.95
```

Both inductors support `ic=` for initial current (requires `UIC` on `.tran`).
Define both `L` elements **before** the `K` statement.

For multi-winding transformers, use a single `K` statement with all inductors
and the upper-triangle coupling matrix: `K_all L1 L2 L3 k12 k13 k23`.

Polarity matters: the first node of each inductor is the dotted terminal for
`K` sign reasoning. Validate polarity on a one-stage/minimal deck before
scaling to many windings. When comparing against another solver, compare sign,
magnitude, timing, and energy separately so a dot-convention error does not hide
a magnitude problem.

### Differential Monitor Source

For differential voltage measurements, add a non-loading VCVS:

```spice
E_mon  vdiff  0  node_p  node_n  1    * V(vdiff) = V(node_p) - V(node_n)
```

Simplifies `.meas` and plotting — use `V(vdiff)` instead of computing the
difference everywhere.

### V-Controlled Switch Patterns

```spice
* Basic switch: closes when V(ctrl) - V(0) > VT
Smain  out  load  ctrl  0  SWMOD
.model SWMOD SW(VT=0.5 VH=0.1 RON=5m ROFF=1MEG)

* Threshold switch: closes when voltage exceeds threshold
* For negative voltages, swap ctrl+/ctrl- so difference is positive:
Sbrk  node  gnd  0  node  BRKMOD
.model BRKMOD SW(VT=100 VH=5 RON=1 ROFF=1G)
```

### Netlist Structure for Complex Circuits

Use `.param` and section comments for readability:

```spice
Title — Circuit Name
.param Vsrc=12 Lp=1m Ls=100m Cload=10u

* === Source ===
Vsrc  src  0  DC {Vsrc}
Lpri  src  xfmr_p  {Lp}

* === Load ===
Lsec  xfmr_s  out  {Ls}
KTR   Lpri Lsec 0.95
Cload out  0  {Cload}

.control
run
write output.raw
quit
.endc
.end
```

### Generated Netlist Hygiene

For programmatic exporters or large generated systems:

- keep one canonical generation path; do not hand-maintain a second "same"
  deck or compare against stale orphan outputs
- validate exporter CLI boundaries before generation: reject zero/negative
  lengths, invalid time constants, impossible section counts, and oversized
  expansions with clear errors rather than tracebacks
- use safe deterministic SPICE names; avoid punctuation that complicates
  rawfile lookup
- emit values in scientific notation to avoid suffix ambiguity (`M` is milli)
- keep design netlists separate from instrumented analysis copies
- insert instrumentation before the final `.end`; when replacing directives,
  consume continuation lines beginning with `+`
- use `.save` aggressively to reduce rawfile size
- define all `L` elements before `K` statements; clamp `|k| < 1` and count
  expected couplings
- label per-section values separately from series/parallel equivalent values
- add model-scope comments when a simplified equivalent is intentional, such as
  fixed-frequency `R_ac` represented by a constant transient resistor
- clean output directories or manifest-check expected vs unexpected generated
  decks before validation
- smoke-test every generated deployment form: baked and parametric netlists,
  each simulator dialect, realistic cascaded subcircuits, and at least two
  parameter values to prove knobs are live
- write a manifest containing original netlist, instrumented netlist, rawfile,
  log, metrics JSON/CSV, and plots

### Subcircuit Usage

Define reusable blocks with `.subckt` and instantiate with `X`:

```spice
* Define a voltage regulator subcircuit
.subckt LDO in out gnd
R1   in  mid  10
C1   mid gnd  1u
Breg out gnd  V={min(V(mid,gnd), 3.3)}
.ends LDO

* Instantiate it
X1  vin  vout  0  LDO
X2  vin  vout2 0  LDO
```

Pin order in `Xname` must match `.subckt` port order exactly. Internal node
names are local to each instance (no collisions between X1 and X2).

### Behavioral Sources (B Element)

Model nonlinear or computed quantities with arbitrary expressions:

```spice
* Voltage limiter (clamp to ±5V)
Blim out 0 V={max(-5, min(5, V(in)))}

* Absolute value rectifier
Babs out 0 V={abs(V(in))}

* Power computation (V × I)
Bpwr pwr 0 V={V(load)*I(Vsense)}
```

Expressions can reference any node voltage `V(node)` or branch current
`I(Vsource)`. Supports standard math functions: `abs`, `sqrt`, `exp`,
`log`, `sin`, `cos`, `min`, `max`, `atan2`, `pow`, ternary `(cond ? a : b)`.

For advanced saturable-inductor or magnetic-switch models, save internal state
nodes (flux, effective inductance, threshold flag), smooth hard transitions,
include damping/leakage, and validate threshold timing on a minimal circuit
before embedding the model in a large switched network.

### Transient Source Functions

These are used with `V` or `I` sources. Getting parameter order wrong causes **silent** errors.

```
PULSE(V1 V2 Td Tr Tf PW PER)
  V1=initial, V2=pulsed, Td=delay, Tr=rise, Tf=fall, PW=width, PER=period

SIN(Voff Vamp Freq Td Theta Phase)
  Damped sine: V = Voff + Vamp × sin(2π·Freq·t + Phase) × exp(-Theta·t)

EXP(V1 V2 Td1 Tau1 Td2 Tau2)
  Exponential rise from V1 to V2, then fall

PWL(t1 v1 t2 v2 ...)
  Piecewise linear — arbitrary waveform defined point by point
```

Example: 5V pulse with 10ns rise/fall, 10µs width, 100µs period:
```spice
Vpulse in 0 PULSE(0 5 0 10n 10n 10u 100u)
```

---

## 10. Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| `Error: no circuit loaded` | First line is a dot-command | Add title as first line |
| `Node 0 not found` | No ground reference | Connect something to node `0` |
| `Timestep too small` | Convergence failure in transient | Add `.options reltol=0.003` or use `UIC` |
| `Singular matrix` | Floating node or topology error | Every node needs a DC path to ground |
| `M` means milli not mega | SPICE convention | Use `MEG` for 1e6 |
| Rawfile parse garbage | Text mode vs binary | Always use `-r` flag for binary |
| AC gain > 0 dB for passives | Phase/complex issue | Check `np.abs()` not `.real` |
| `.meas` results missing | `-b -r` suppresses `.meas` | Use `run_sim.py` (auto-handled) or `.control` block with `run` + `write` |
| `ic=` ignored, all zeros | `.tran` without `UIC` | Add `UIC` to `.tran` line (`run_sim.py` warns automatically) |
| `PULSE` DC value warning | Informational only — V1 ≠ DC OP | Ignore; simulation proceeds correctly. Common on trigger sources |
| `KeyError` on current data | `.save @L[i]` → rawfile key is `i(@L[i])` | Look up by rawfile key with `i()` wrapper (see §3) |
| Plausible but wrong waveform | Topology/polarity mismatch, not syntax | Check switch/load assumptions, diode direction, and transformer dots |
| Empty or zero-point rawfile | Failed run left an output stub | Check return code/log/header before parsing arrays |
| Switch model does not behave as expected | LTspice-style `VON`/`VOFF` used with ngspice `SW` | Use ngspice `VT`/`VH` plus `RON`/`ROFF` |

### Convergence Helpers

Escalation order: `method=gear` → `maxord=2` → `reltol=0.003` → relax
`abstol`/`vntol` → `itl4=100` → `gmin`/`cshunt`.

Fix model discontinuities before only relaxing tolerances:

- use finite switch `RON`/`ROFF` and hysteresis (`VT`, `VH`)
- add leakage/reference resistors for floating nodes
- delay initial switching or use non-overlap PWL controls
- smooth behavioral-source transitions and save internal state nodes for debug
- replace ideal CC/CV clamps with labeled finite Thevenin/current-limit
  equivalents when adequate
- add damping only when it represents real loss or a justified numerical proxy

| Option | Default | When to change |
|--------|---------|----------------|
| `method=gear` | trapezoidal | Stiff circuits: switching, high-Q, large L/C ratios |
| `maxord` | 6 | Set to `2` for stiff switching — BDF-2 is more stable than higher orders through abrupt transients |
| `reltol` | 0.001 | Relax to 0.003 if "timestep too small" |
| `itl1` / `itl4` | 100 / 10 | Increase to 300/100 for synchronized multi-stage switching |
| `abstol` / `vntol` | 1e-12 / 1e-6 | Relax for large-signal circuits (kV/kA range): 1e-9 / 1e-3 |

**Proven config for stiff pulsed-power (8-stage, kV/kA):**

```spice
.options method=gear maxord=2 reltol=3e-3 abstol=1e-9 vntol=1e-3 itl1=300 itl4=100
```

---

## 11. Helper Scripts

- `scripts/run_sim.py` — Full simulation runner with auto-handling of `.meas`,
  `.step` param sweeps, and UIC warnings. Bode/transient plots, CSV export.
- `scripts/parse_rawfile.py` — Binary rawfile parser (single + multi-run).

Usage:

```bash
uv run scripts/run_sim.py circuit.cir --plot bode.png
uv run scripts/parse_rawfile.py output.raw [--json | --csv]
```

### Netlist Instrumentation Pattern

For custom analysis suites, instrument the design netlist programmatically:
replace `.options` with analysis-specific solver settings, replace `.save` with
the needed signal list, and inject `.control`/`run`/`write`/`.endc` before
`.end`. Write the instrumented copy to a separate file — never overwrite the
design netlist. This keeps different analysis modes (time-domain, AC sweep,
parameter scan) independent.

### Solver-Parity / CI Pattern

When ngspice is an independent witness for a Python/ODE/FEM pipeline:

```python
import shutil
import pytest

pytestmark = pytest.mark.skipif(
    shutil.which("ngspice") is None,
    reason="ngspice not installed",
)
```

- run with a timeout and include stdout/stderr on failure
- assert the rawfile/CSV exists and contains nonzero data
- instantiate generated subcircuits the way users will: realistic cascades,
  parameter overrides, and no over-grounded harness that masks floating nodes
- compare scalar metrics and waveform overlays, not just solver success
- interpolate adaptive ngspice timesteps before RMS/error comparisons
- compare sign, magnitude, timing, and energy separately

### Topology Validation Checklist

Before trusting results, confirm:

- what is physically connected at `t=0`
- whether the load is permanently connected, diode-gated, actively switched, or
  absent
- every switch has an actual modeled control source or device
- initial conditions are physical and `.tran ... UIC` is present when using
  component `ic=`
- all non-ground nodes have a DC path or intentional leakage/reference path
- the simulated topology matches the schematic/block diagram
- idealizations such as switches, clamps, CC/CV sources, and Thevenin
  equivalents are clearly labeled

For diode orientation, use `Dname anode cathode model` and verify the expected
half-cycle from parsed peak data. Negative-rail circuits are easy to reverse by
symbol intuition alone.
