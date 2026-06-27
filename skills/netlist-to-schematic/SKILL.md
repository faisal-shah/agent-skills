---
name: netlist-to-schematic
description: >
  Draw, create, or visualize a circuit schematic diagram from a SPICE netlist
  (.cir/.spice file). Use when asked to produce a circuit diagram, schematic,
  or visual representation of an electrical circuit.
---

# Netlist-to-Schematic Skill

Convert a SPICE netlist (`.cir`) into a readable, publication-quality circuit
schematic using Circuitikz (LaTeX). This skill covers the entire workflow from
parsing the netlist through to the final PNG.

## Prerequisites

- `pdflatex` with the `circuitikz` package (MiKTeX on Windows, TeX Live on Linux)
- `pdftoppm` (Poppler) for PDF→PNG conversion
- Python 3.10+ and `uv` for running `scripts/compile_tex.py`

---

## 1. Workflow

1. **Choose the schematic mode** — exact transcription, engineering
   abstraction, presentation simplification, or physical-fixture overlay
2. **Parse** the netlist — identify components, nodes, topology, stages
3. **Build a coverage manifest** — component counts, critical nodes, polarity
   items, subcircuits, and any omitted/summarized elements
4. **Plan** the layout — determine signal flow, group stages, assign coordinates
5. **Write** the Circuitikz LaTeX source and save it beside the PNG target
6. **Compile** to PNG — `uv run scripts/compile_tex.py schematic.tex`
7. **View** the PNG — check for label overlaps, missing components, topology errors
8. **Fix** and recompile — one or more iterations until the schematic is correct

### Schematic mode gate

Before drawing, decide what the output is allowed to omit or simplify:

| Mode | Use when | Required note |
|---|---|---|
| Exact | User needs the simulated circuit faithfully transcribed | "Exact netlist transcription" |
| Engineering abstraction | Equivalent groups improve readability | List grouped/omitted elements |
| Presentation | Teaching or report slide needs clear energy flow | "Simplified for presentation" |
| Physical-fixture overlay | Probes, sensors, or fixtures are shown with the simulated circuit | Mark non-simulated items as annotations |

Default to **Exact** unless the user asks for a simplified or presentation view.
If using any abstraction, put a subtitle or note in the schematic that says what
was summarized.

### Coverage manifest for exact schematics

For exact or simulation-faithful schematics, keep a short manifest while
drawing:

```text
Source netlist: path/to/circuit.cir
Output source: schematic/circuit_schematic.tex
Output render: schematic/circuit_schematic.png
Components: R=..., C=..., L=..., D=..., S=..., V=..., K=...
Critical nodes: vin, pri, sec, out, load, 0
Ground handling: every node 0 rendered with ground symbol
Subcircuits: flattened / shown as blocks with detail sheet / omitted by request
Polarity checks: diodes, coupled-inductor dots, transformer winding order
Omissions or summaries: none / listed here
```

Do not stop at "the LaTeX compiled" for exact schematics. Count and trace the
netlist items before calling the drawing done.

### Programmatically generated schematics

When code emits both a netlist/model and a schematic, make the two artifacts
share the same source of truth whenever possible. If the drawing cannot be
derived directly from the emitted netlist, add assertions before rendering:

- repeated-block counts in source data == drawn instances;
- each drawn branch maps to a source element/group and endpoint node pair;
- representative rendered values match the source values;
- no layout helper silently drops data (`zip(..., strict=True)` or explicit
  length assertions for coordinates, labels, parsed elements, and fitted cells).

For intentional compression, mark the mode as presentation/abstraction and
write the expected source count plus rendered count in the visible note or
manifest.

---

## 2. Reading a Netlist for Schematic Purposes

A SPICE netlist defines components and their node connections. To convert it
into a schematic, extract this information:

| What to find | How to find it | Why it matters |
|---|---|---|
| Main signal path | Trace from source through components to load | Becomes the horizontal backbone |
| Stages / sections | Look for `* === Section ===` comments | Group into dashed stage boxes |
| Ground connections | Any connection to node `0` | Vertical drops to ground bus |
| Parallel branches | Multiple components sharing the same two nodes | Side-by-side vertical drops |
| Transformer | `K` coupling statement referencing two `L` elements | Draw as coupled inductors with core |
| Switches | `S` element with ctrl+/ctrl- nodes | Main path + control annotation |
| Parameters | `.param` lines | Use values as component labels |
| Sources | `V`/`I` elements with `PULSE`, `SIN`, etc. | Use square-wave symbol for PULSE |

### Polarity-sensitive parsing

Check these before placing symbols:

- **Diodes:** SPICE order is anode, cathode. Circuitikz draw direction is also
  anode to cathode; if the readable layout draws cathode to anode, use `invert`.
- **Coupled inductors:** In ngspice, the **first node of each `L` element is the
  dotted terminal** for `K` coupling. Put schematic dots on those terminals.
- **Transformers:** Keep coupling visually separate from electrical connection;
  core/coupling lines should not look like wires between windings.
- **Waveform sign:** When simulation results exist, use them to confirm diode
  and transformer polarity.

### Tracing the signal path

Start from the source (usually a `V` element connected to node 0). Follow
node names through components: the output node of one component is the input
node of the next. The chain of unique node names reveals the main path.

```
Example: Cpri→(cpri)→Rpri→(nsw)→Smain→(nlead)→Rlead→(p)→Lpri→(0)
Main path: cpri → nsw → nlead → p → 0 (ground return)
```

---

## 3. Layout Strategy

These rules prevent the most common quality problems (label overlap, cramped
spacing, unreadable topology):

### Signal flow
- **Main path runs left-to-right** along the top of the schematic.
- **Ground bus** is a horizontal line at the bottom. Connect vertical drops.
- **Branches to ground** are vertical (top to bottom).

### Coordinate spacing
- Use **3 units** between main component endpoints (e.g., `(0,6)` to `(3,6)`).
- Vertical main components need **3 units** of height (e.g., `(6,6)` to `(6,3)`).
- Parasitics and short interconnect elements can use **2–2.5 units**.
- Leave **2–3 units** horizontal gap between parallel vertical branches.
- Reserve extra margin at the right edge for timing notes and callouts.

### Size and scale

| Circuit size | Coordinate width | Suggested scale | Suggested `bipoles/length` |
|---|---:|---:|---:|
| 5–10 components | <20 units | 0.80–0.90 | 1.1–1.2cm |
| 10–20 components | 20–35 units | 0.65–0.80 | 1.2–1.3cm |
| 20+ components | 35+ units | 0.50–0.65 | 1.3–1.4cm |

If labels are still crowded, shorten schematic labels to names only and move
values to a parameter table.

### Grouping
- Use **dashed stage boxes** around functional blocks:
  ```latex
  \draw[dashed, rounded corners=4pt, gray]
        (x1,y1) rectangle (x2,y2)
        node[above left, font=\footnotesize\color{gray}] {Stage Name};
  ```
- Typical stages: Source, Switch, Transformer, Output, Load.

### Multi-stage layouts (N repeated stages)
- For exact schematics, draw each stage as a **horizontal row** at a computed
  y-level (top to bottom).
- Use `\foreach` + `\pgfmathsetmacro` to avoid writing N× the LaTeX:
  ```latex
  \foreach \n in {1,...,8} {
    \pgfmathsetmacro{\yb}{28.5 - (\n-1)*3.5}
    \pgfmathsetmacro{\yt}{\yb + 2.0}
    \draw (0.5, \yt) to[C] (0.5, \yb);
    \draw (0.5, \yb) -- ++(0,-0.3) node[ground]{};
  }
  ```
- **Critical:** Use `{\expr}` braces for arithmetic in TikZ coordinates:
  `(0.5, {\yt-0.3})` not `(0.5, \yt-0.3)`.
- Inter-stage series connections use U-shaped jogs through a bus column.
- Full annotations on stage 1 only; stages 2–N show minimal labels.
- For presentation schematics, it is acceptable to draw representative stages
  plus an ellipsis, but add a note such as "stages 3–6 omitted; simulated
  netlist contains 8 stages."

### Large schematics

- Render large circuits as named sections when one image is unreadable.
- Check each section is nonblank, uniquely named, and not overwritten.
- Use local wires for nearby connections. Use net labels mainly for global or
  distant nets; too many repeated local labels can make the circuit look
  disconnected.
- For complex subcircuits, create a system-level block schematic plus a separate
  detail schematic instead of forcing every internal element into one drawing.

### Ground symbols
- For **≤5 ground connections**: a shared ground bus is fine.
- For **many grounds** (e.g., 16+ in a multi-stage system): use individual
  `node[ground]{}` at each point. Do not route long wires to a shared bus —
  the spaghetti of wires makes the schematic unreadable.

### Transformer placement
- Draw primary and secondary windings **side by side vertically** with 2 units
  horizontal separation.
- Primary path enters from the left, secondary exits to the right.
- Add core lines and polarity dots (see §6).

---

## 4. Circuitikz Template

```latex
\documentclass[border=20pt]{standalone}
\usepackage[american]{circuitikz}
\ctikzset{bipoles/length=1.2cm}
\begin{document}
\begin{circuitikz}[scale=0.85, transform shape]

% Title
\node[font=\large\bfseries] at (8,8.5) {Circuit Title};

% === Stage 1: Source ===
\draw (0,6) to[V, l=$V_{in}$] (0,3)   % vertical source
      (0,6) to[R, l=$R_1$] (3,6)       % horizontal resistor
      to[short] (6,6);                  % wire to next stage

% === Ground bus ===
\draw (0,3) node[ground]{} -- (6,3) -- (12,3) node[ground]{};

\end{circuitikz}
\end{document}
```

**Key settings:**
- `border=20pt` — prevents clipping on large circuits (use 10pt for small ones)
- `bipoles/length=1.2cm` — keeps components readable in dense schematics
- `scale=0.85` — fits more on the page without sacrificing readability

**Color definitions** — avoid TikZ reserved words (`out`, `in`, `at`, `to`,
`above`, `below`, `left`, `right`) as color names — they conflict with TikZ
keys. Use prefixed names like `pri`, `sec`, `ogrn` (not `out`).

---

## 5. SPICE → Circuitikz Component Mapping

| SPICE | Circuitikz | Label pattern | Notes |
|-------|-----------|--------------|-------|
| `R` | `to[R, l=...]` | `l=$R_1$` | |
| `C` | `to[C, l=...]` | `l=$C_1$` | |
| `L` | `to[L, l=...]` | `l=$L_1$` | Use `cute inductor` for transformer windings |
| `D` | `to[D, l=...]` | `l=$D_1$` | Draw direction = anode→cathode; use `invert` if layout draws cathode→anode |
| `S` (switch) | `to[nos, l=...]` | `l=$S_1$` | Normally-open; add control annotation |
| `V` (DC) | `to[V, l=...]` | `l=$V_{in}$` | |
| `V` (PULSE) | `to[sqV, l=...]` | `l=$V_{trig}$` | Use symbol for main-path sources; use dashed annotation for controls |
| `I` | `to[I, l=...]` | `l=$I_1$` | Current source |
| `K` | Two `cute inductor` + core | See §6 | Coupled inductors = transformer |
| `B` | `to[american voltage source]` | `l=$B_1$` | Behavioral source |
| node `0` | `node[ground]{}` | | Every ground connection |

### Value formatting in labels

```latex
% Name only (clean, preferred for dense circuits)
l=$R_1$
% Name and value
l=$R_1{=}10\,\mathrm{m}\Omega$
% Value with SI prefix
l=$12\,\mu\mathrm{F}$
```

### Diode reversed relative to drawing direction

If the netlist diode is `D1 anode cathode model` but the clean layout draws from
cathode to anode, use `invert`:

```latex
% Netlist: D1 out sec Dmodel  (anode=out, cathode=sec)
% Layout draws left-to-right from sec to out, so invert the symbol.
\draw (sec) to[D, invert, l=$D_1$] (out);
```

Always verify the final symbol against intended conduction direction and, when
available, waveform polarity.

---

## 6. Complex Component Patterns

### Transformer (coupled inductors)

This is the most common source of errors. Use this exact pattern:

```latex
% Primary winding (left, top to bottom) — mirror flips bumps toward coupling gap
\draw (6,6) to[cute inductor, l=$L_p$, mirror] (6,3);
% Secondary winding (right, top to bottom) — default bumps face left toward gap
\draw (8,6) to[cute inductor, l_=$L_s$] (8,3);
% Core lines (two parallel vertical lines between windings)
\draw[thick] (6.8,3.2) -- (6.8,5.8);
\draw[thick] (7.2,3.2) -- (7.2,5.8);
% Polarity dots — OUTER FACE of each winding (away from coupling gap)
\node[circle, fill, inner sep=1.3pt] at (5.75,5.7) {};   % left of primary
\node[circle, fill, inner sep=1.3pt] at (8.25,5.7) {};   % right of secondary
% Coupling coefficient annotation
\node[font=\small, red!60!black] at (7,2.5) {$k = 0.95$};
```

Key points:
- **`mirror` depends on position, not role.** `mirror` goes on whichever winding
  needs bumps facing **toward** the coupling gap. For primary-left/secondary-right:
  `mirror` goes on the **primary**. If secondary is left, mirror goes on secondary.
- **Dots follow the netlist.** In ngspice, the first node of each coupled `L`
  element is the dotted terminal.
- **Polarity dots go on the OUTER face** — away from the coupling gap, not
  between windings. This follows EE convention and prevents dots from merging
  visually with core lines.
- Core lines are 0.4 units apart, centered between the windings.
- Use `l_=` (underscore suffix) on the secondary to place label on the right side.
- For **air-core** transformers, use dashed core lines instead of solid.

### Switch with control annotation

```latex
% Switch on main path
\draw (3,6) to[nos, l=$S_{main}$] (6,6);
% Control signal annotation (dashed line to trigger source)
\draw[dashed, ->, gray] (4.5,5.2) -- (4.5,4)
      node[below, font=\footnotesize] {$V_{trig}$};
```

Use a full `sqV` source for a PULSE source in the main circuit path. For switch
controls, triggers, gate drives, timing notes, probes, Rogowski coils, and other
non-main-path context, prefer dashed arrows or callout nodes so annotations are
not mistaken for circuit topology.

### Vertical series branch

Use this for branches such as switch + resistor to ground:

```latex
\draw (10,6) to[nos] (10,4.5);
\node[right, font=\small] at (10,5.25) {$S_1$};
\draw (10,4.5) to[R] (10,3);
\node[right, font=\small] at (10,3.75) {$R_1$};
\draw (10,3) node[ground]{};
```

### RLC loop or ring-down test circuit

Not every netlist is a left-to-right source-load chain. For capacitor discharge
or ring-down tests, draw the energy-storage loop explicitly and place
measurement annotations outside the loop:

```latex
\draw (0,4) to[C, l=$C_{test}$] (0,0)
      node[ground]{};
\draw (0,4) to[nos, l=$S_1$] (3,4)
      to[L, l=$L_{loop}$] (6,4)
      to[R, l=$R_{loop}$] (6,0)
      -- (0,0);
\draw[dashed, ->, gray] (3,5.0) -- (3,4.3)
      node[above, font=\footnotesize] {trigger};
```

### Repeated series stack

For diode, IGBT, MOV, resistor, or capacitor stacks:

```latex
\foreach \n in {1,...,5} {
  \pgfmathsetmacro{\x}{(\n-1)*2.0}
  \draw ({\x},4) to[D, l=$D_{\n}$] ({\x+1.5},4);
}
\node[above, font=\footnotesize] at (5,4.7) {5 of 15 devices shown};
```

For exact schematics, draw every device. For presentation schematics, one
representative cell plus `\times N` is acceptable if the schematic says what was
compressed.

### Parallel branches to ground

When multiple components connect from the same node to ground (e.g.,
R ∥ C ∥ R):

```latex
% Three parallel paths from "rock" node to ground, spaced 3 units apart
\draw (10,6) -- (16,6);                          % horizontal bus
\draw (10,6) to[R, l=$R_1$] (10,3);              % first branch
\draw (13,6) to[C, l=$C_1$] (13,3);              % second branch
\draw (16,6) to[R, l=$R_2$] (16,3);              % third branch
\draw (10,3) -- (16,3) node[ground]{};            % ground bus
```

For dense load networks, alternate label sides or use explicit side nodes for
each vertical component. If a parallel group represents a large subcircuit, draw
it as a block in the system schematic and provide a separate detail sheet.

---

## 7. Label Placement Rules

Label overlap is the **#1 quality problem** in generated schematics. Follow
these rules systematically:

| Component orientation | Label method | Example |
|---|---|---|
| Horizontal | `l=` (above) or `l_=` (below) | `to[R, l=$R_1$]` |
| Vertical | `\node[left]` or `\node[right]` at midpoint | See below |

Avoid `l=` on vertical components in dense schematics — the label often
overlaps the component body. Prefer explicit node placement:

```latex
% WRONG — label overlaps vertical capacitor
\draw (6,6) to[C, l=$C_1$] (6,3);

% RIGHT — label placed to the left, clear of the body
\draw (6,6) to[C] (6,3);
\node[left, font=\small] at (6,4.5) {$C_1$};
```

**Exception:** `l_=` (underscore suffix) places the label on the opposite side
and sometimes works for vertical components. Test by compiling and inspecting
the PNG. For final dense/report figures, explicit `\node[left/right]` labels
are more predictable.

**Dense circuits:** Use short labels (name only, no value) on the schematic
and add a parameter table as a separate node:

```latex
\node[anchor=north west, font=\footnotesize, align=left] at (0,1) {%
  $R_1 = 10\,\mathrm{m}\Omega$ \\
  $C_1 = 12\,\mu\mathrm{F}$ \\
  $L_p = 4.28\,\mu\mathrm{H}$};
```

---

## 8. Worked Example

A forward converter with switch, transformer, diode rectifier, LC filter, and
load. Demonstrates: left-to-right flow, transformer with core/dots, vertical
components, stage boxes, ground bus, and node labels.

```latex
\documentclass[border=20pt]{standalone}
\usepackage[american]{circuitikz}
\ctikzset{bipoles/length=1.2cm}
\begin{document}
\begin{circuitikz}[scale=0.85, transform shape]

% Title
\node[font=\large\bfseries] at (8,8.5) {Forward Converter};

% === Source stage ===
\draw (0,6) to[V, l=$V_{in}$] (0,3)      % DC source (vertical)
      (0,6) to[nos, l=$S_1$] (3,6)        % Switch
      to[R, l=$R_{sw}$] (6,6);            % Switch resistance

% === Transformer ===
\draw (6,6) to[cute inductor, l=$L_p$, mirror] (6,3);
\draw (8,6) to[cute inductor, l_=$L_s$] (8,3);
\draw[thick] (6.8,3.2) -- (6.8,5.8);     % Core line 1
\draw[thick] (7.2,3.2) -- (7.2,5.8);     % Core line 2
\node[circle, fill, inner sep=1.3pt] at (5.75,5.7) {};   % Dot primary
\node[circle, fill, inner sep=1.3pt] at (8.25,5.7) {};   % Dot secondary
\node[font=\small, red!60!black] at (7,2.5) {$k = 0.95$};

% === Output: diode → filter → load ===
\draw (8,6) to[D, l=$D_1$] (11,6)
      to[L, l=$L_{out}$] (14,6)
      -- (16,6)
      to[R, l=$R_{load}$] (16,3);         % Load (vertical)
\draw (14,6) to[C, l_=$C_{out}$] (14,3);  % Filter cap (vertical)

% === Ground bus ===
\draw (0,3) node[ground]{} -- (6,3) -- (8,3) -- (14,3) -- (16,3)
      node[ground]{};

% === Node labels ===
\node[above, font=\footnotesize\color{blue!60!black}] at (6,6.1) {pri};
\node[above, font=\footnotesize\color{blue!60!black}] at (8,6.1) {sec};
\node[above, font=\footnotesize\color{blue!60!black}] at (14,6.1) {out};

% === Stage boxes ===
\draw[dashed, rounded corners=4pt, gray]
      (-0.8,2.4) rectangle (3.6,7)
      node[above left, font=\footnotesize\color{gray}] {Source};
\draw[dashed, rounded corners=4pt, gray]
      (5.2,2.0) rectangle (8.8,7)
      node[above left, font=\footnotesize\color{gray}] {Transformer};
\draw[dashed, rounded corners=4pt, gray]
      (9.5,2.4) rectangle (16.8,7)
      node[above left, font=\footnotesize\color{gray}] {Output};

\end{circuitikz}
\end{document}
```

This example demonstrates every technique from §3–§7:
- Left-to-right signal flow along the top
- Ground bus along the bottom
- Transformer with core lines, polarity dots, and coupling annotation
- Stage grouping boxes
- Blue node labels for key connection points
- `l_=` used for secondary winding and vertical capacitor labels

---

## 9. Compile → View → Iterate

**Expect 3–5 iterations** for complex schematics. Each compile-view-fix cycle
takes ~30 seconds. This is normal — treat it as the standard workflow.

### Typical iteration pattern

- **V1–V2:** Topology and layout — may need reorientation, fix compilation bugs
- **V3–V4:** Polish — fix polarity dots, labels, annotation positions
- **V5:** Final quality — ready for review

### Compile

```bash
uv run scripts/compile_tex.py schematic.tex     # → schematic.png (300 dpi)
uv run scripts/compile_tex.py schematic.tex --dpi 600   # higher resolution
```

The script runs `pdflatex` → `pdftoppm` and reports LaTeX errors if
compilation fails.

### Review checklist

After viewing the PNG, verify:

- The schematic mode is stated if anything was abstracted or simplified
- Required LaTeX/Circuitikz packages were available; the render did not fall
  back, omit symbols, or leave warnings that affect the image
- The `.tex` source is saved beside the rendered `.png`
- All netlist components are present (count them)
- Topology is correct (trace each netlist line → schematic connection)
- Repeated/generated sections have the expected rendered count and node pairs
- Polarity is correct for diodes, coupled inductors, transformers, and switches
- No label overlaps (especially vertical components)
- Signal flow reads left-to-right
- All ground connections have `node[ground]{}`
- Transformer has core lines and polarity dots
- Taps and connected junctions have visible dots where ambiguity is possible
- Probe/sense/measurement terminations are unambiguous and not mistaken for
  floating or simulated topology
- Long or multiline labels are short, wrapped, or moved to a table/callout; view
  the rendered image because multiline `.tex` labels can garble in dense figures
- Stage boxes don't clip component labels
- Timing callouts, probes, sensors, and tables do not overlap the circuit
- Large section renders are nonblank, uniquely named, and readable

### Common fixes

| Symptom | Fix |
|---------|-----|
| Labels overlap | Switch vertical labels to `\node[left/right]` |
| Components cramped | Increase coordinate spacing by 1–2 units |
| Circuit clipped at edge | Increase `border` in `\documentclass` |
| Components too small | Set `\ctikzset{bipoles/length=1.4cm}` |
| Wires crossing confusingly | Rearrange stage order or add `to[crossing]` |

---

## 10. Artifact Hygiene

- Save the Circuitikz source next to the rendered image:
  `schematic/name.tex` and `schematic/name.png`.
- Do not leave the only source in `/tmp` when the PNG is a deliverable.
- For exact schematics, keep the coverage manifest in the report, notebook, or
  final response.
- If the schematic is simplified, include a visible note listing what was
  summarized or moved to a detail sheet.
- For report figures, ensure titles, captions, and parameter tables remain
  readable at the final inserted size.

---

## 11. Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| Label overlaps component body | `l=` on vertical component | Use `\node[left]` at midpoint |
| Transformer looks like two separate inductors | Missing core lines and dots | Use §6 transformer pattern |
| Transformer looks shorted | Coupling/core lines too wire-like | Use dashed/non-wire core lines, visible gap, and dots on outer faces |
| Circuit runs off the page | `border=10pt` too small | Use `border=20pt` or larger |
| Components too small to read | Many components + small scale | Add `\ctikzset{bipoles/length=1.2cm}` |
| Missing ground symbols | Forgot `node[ground]{}` | Every node-0 needs a ground symbol |
| Topology doesn't match netlist | Misread node names | Trace each netlist line to its schematic wire |
| Diode direction wrong | Drew cathode→anode | Use anode→cathode draw direction or add `invert` |
| Coupled-inductor dots wrong | Ignored SPICE terminal order | First node of each ngspice `L` is dotted |
| Switch has no control indication | Only drew the switch body | Add dashed annotation arrow (§6) |
| Instrumentation looks like topology | Probe/sensor drawn as circuit element | Use dashed callouts and label as measurement context |
| `pdflatex` fails silently | Unescaped special characters | Escape `_`, `%`, `&` in text nodes |
| Empty/white PNG output | LaTeX compiled but circuit outside bounding box | Check coordinates are consistent |
| Section render overwritten | Reused same output filename | Use unique section names and verify all files |
| `pgfkeys Error: key '/tikz/out' requires a value` | Color name collides with TikZ key | Rename color (e.g., `out`→`ogrn`); avoid `in`, `at`, `to` etc. |
| Transformer bumps face wrong direction | `mirror` on wrong winding | `mirror` goes on winding whose bumps must face the coupling gap |
| Polarity dots between windings | Dots placed on gap side | Dots go on **outer face** (away from coupling gap) |
| Generated schematic has too few repeated cells | Fixed layout list or plain `zip()` truncated data | Use shared source data plus `zip(..., strict=True)` or explicit count assertions |
