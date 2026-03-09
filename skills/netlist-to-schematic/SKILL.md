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

- `pdflatex` with the `circuitikz` package installed
- `pdftoppm` (from poppler-utils) for PDF→PNG conversion
- Python 3.10+ and `uv` for running `scripts/compile_tex.py`

---

## 1. Workflow

1. **Parse** the netlist — identify components, nodes, topology, stages
2. **Plan** the layout — determine signal flow, group stages, assign coordinates
3. **Write** the Circuitikz LaTeX source
4. **Compile** to PNG — `uv run scripts/compile_tex.py schematic.tex`
5. **View** the PNG — check for label overlaps, missing components, topology errors
6. **Fix** and recompile — one or more iterations until the schematic is correct

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
- Minimum **3 units** between component endpoints (e.g., `(0,6)` to `(3,6)`).
- Vertical components need **3 units** of height (e.g., `(6,6)` to `(6,3)`).
- Leave **2 units** horizontal gap between parallel vertical branches.

### Grouping
- Use **dashed stage boxes** around functional blocks:
  ```latex
  \draw[dashed, rounded corners=4pt, gray]
        (x1,y1) rectangle (x2,y2)
        node[above left, font=\footnotesize\color{gray}] {Stage Name};
  ```
- Typical stages: Source, Switch, Transformer, Output, Load.

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

---

## 5. SPICE → Circuitikz Component Mapping

| SPICE | Circuitikz | Label pattern | Notes |
|-------|-----------|--------------|-------|
| `R` | `to[R, l=...]` | `l=$R_1$` | |
| `C` | `to[C, l=...]` | `l=$C_1$` | |
| `L` | `to[L, l=...]` | `l=$L_1$` | Use `cute inductor` for transformer windings |
| `D` | `to[D, l=...]` | `l=$D_1$` | Draw direction = anode→cathode |
| `S` (switch) | `to[nos, l=...]` | `l=$S_1$` | Normally-open; add control annotation |
| `V` (DC) | `to[V, l=...]` | `l=$V_{in}$` | |
| `V` (PULSE) | `to[sqV, l=...]` | `l=$V_{trig}$` | Square-wave source symbol |
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

---

## 6. Complex Component Patterns

### Transformer (coupled inductors)

This is the most common source of errors. Use this exact pattern:

```latex
% Primary winding (top to bottom)
\draw (6,6) to[cute inductor, l=$L_p$] (6,3);
% Secondary winding (mirrored, 2 units right)
\draw (8,6) to[cute inductor, l_=$L_s$, mirror] (8,3);
% Core lines (two parallel vertical lines between windings)
\draw[thick] (6.8,3.2) -- (6.8,5.8);
\draw[thick] (7.2,3.2) -- (7.2,5.8);
% Polarity dots (top-left of primary, top-right of secondary)
\node[circle, fill, inner sep=1.3pt] at (5.75,5.7) {};
\node[circle, fill, inner sep=1.3pt] at (8.25,5.7) {};
% Coupling coefficient annotation
\node[font=\small, red!60!black] at (7,2.5) {$k = 0.95$};
```

Key points:
- Primary uses `cute inductor`, secondary adds `mirror` to flip the winding.
- Core lines are 0.4 units apart, centered between the windings.
- Polarity dots go at the **top** of each winding (same-side = additive coupling).
- Use `l_=` (with underscore) on the secondary to place label on the right side.

### Switch with control annotation

```latex
% Switch on main path
\draw (3,6) to[nos, l=$S_{main}$] (6,6);
% Control signal annotation (dashed line to trigger source)
\draw[dashed, ->, gray] (4.5,5.2) -- (4.5,4)
      node[below, font=\footnotesize] {$V_{trig}$};
```

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

---

## 7. Label Placement Rules

Label overlap is the **#1 quality problem** in generated schematics. Follow
these rules systematically:

| Component orientation | Label method | Example |
|---|---|---|
| Horizontal | `l=` (above) or `l_=` (below) | `to[R, l=$R_1$]` |
| Vertical | `\node[left]` or `\node[right]` at midpoint | See below |

**Never use `l=` on vertical components** — the label overlaps the component
body. Instead, use explicit node placement:

```latex
% WRONG — label overlaps vertical capacitor
\draw (6,6) to[C, l=$C_1$] (6,3);

% RIGHT — label placed to the left, clear of the body
\draw (6,6) to[C] (6,3);
\node[left, font=\small] at (6,4.5) {$C_1$};
```

**Exception:** `l_=` (underscore suffix) places the label on the opposite side
and often works for vertical components. Test by compiling.

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
\draw (6,6) to[cute inductor, l=$L_p$] (6,3);
\draw (8,6) to[cute inductor, l_=$L_s$, mirror] (8,3);
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

### Compile

```bash
uv run scripts/compile_tex.py schematic.tex     # → schematic.png (300 dpi)
uv run scripts/compile_tex.py schematic.tex --dpi 600   # higher resolution
```

The script runs `pdflatex` → `pdftoppm` and reports LaTeX errors if
compilation fails.

### Review checklist

After viewing the PNG, verify:

- All netlist components are present (count them)
- Topology is correct (trace each netlist line → schematic connection)
- No label overlaps (especially vertical components)
- Signal flow reads left-to-right
- All ground connections have `node[ground]{}`
- Transformer has core lines and polarity dots
- Stage boxes don't clip component labels

### Common fixes

| Symptom | Fix |
|---------|-----|
| Labels overlap | Switch vertical labels to `\node[left/right]` |
| Components cramped | Increase coordinate spacing by 1–2 units |
| Circuit clipped at edge | Increase `border` in `\documentclass` |
| Components too small | Set `\ctikzset{bipoles/length=1.4cm}` |
| Wires crossing confusingly | Rearrange stage order or add `to[crossing]` |

---

## 10. Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| Label overlaps component body | `l=` on vertical component | Use `\node[left]` at midpoint |
| Transformer looks like two separate inductors | Missing core lines and dots | Use §6 transformer pattern |
| Circuit runs off the page | `border=10pt` too small | Use `border=20pt` or larger |
| Components too small to read | Many components + small scale | Add `\ctikzset{bipoles/length=1.2cm}` |
| Missing ground symbols | Forgot `node[ground]{}` | Every node-0 needs a ground symbol |
| Topology doesn't match netlist | Misread node names | Trace each netlist line to its schematic wire |
| Diode direction wrong | Drew cathode→anode | Draw direction follows current: anode→cathode |
| Switch has no control indication | Only drew the switch body | Add dashed annotation arrow (§6) |
| `pdflatex` fails silently | Unescaped special characters | Escape `_`, `%`, `&` in text nodes |
| Empty/white PNG output | LaTeX compiled but circuit outside bounding box | Check coordinates are consistent |
