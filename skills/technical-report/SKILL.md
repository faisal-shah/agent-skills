---
name: technical-report
description: >
  Generate professional DOCX technical reports with python-docx. Use when asked
  to create Word documents, format tables, embed figures, or build report
  generation scripts. Covers styling, alignment rules, page layout, and
  reusable helper patterns.
---

# Technical Report Generation Skill

Generate professional, script-reproducible DOCX technical reports using
`python-docx`. This skill captures formatting patterns, alignment rules, and
reusable helper functions learned from production report generation workflows.

> **Regenerable reports:** Always generate reports from a Python script — never
> by hand-editing a `.docx`. This makes reports reproducible when data changes.

## Prerequisites

- Python 3.10+ with `python-docx` (`pip install python-docx`)
- For PEP 723 scripts: `uv run` with inline dependency metadata

---

## 1. Critical Alignment Rule

**This is the #1 formatting mistake.** Get this wrong and every report looks
amateurish:

| Element | Alignment | Constant |
|---------|-----------|----------|
| Body paragraphs | **Justified** | `WD_ALIGN_PARAGRAPH.JUSTIFY` |
| Bullet points / list items | **Left** | `WD_ALIGN_PARAGRAPH.LEFT` |
| Figure captions | **Center, italic** | `WD_ALIGN_PARAGRAPH.CENTER` |
| Table header cells | **Center** | `WD_ALIGN_PARAGRAPH.CENTER` |
| Table numeric cells | **Center** | `WD_ALIGN_PARAGRAPH.CENTER` |
| Table text cells (first col) | **Left** | `WD_ALIGN_PARAGRAPH.LEFT` |
| Headings | **Left** (default) | — |

**⚠ NEVER justify bullet points or list items.** Justified text in short lines
creates ugly word spacing. Lists must ALWAYS use LEFT alignment:

```python
def bullet_left(doc, text):
    """Add a left-aligned bullet point. NEVER use JUSTIFY for lists."""
    p = doc.add_paragraph(style='List Bullet')
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.space_before = Pt(0)
    p.clear()
    r = p.add_run(text)
    r.font.size = Pt(10.5)
    return p
```

---

## 2. Standard Imports

```python
from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor, Emu
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn, nsdecls
from docx.oxml import parse_xml
```

---

## 3. Color Constants

```python
DARK_BLUE  = RGBColor(0x1F, 0x38, 0x64)   # title text
HDR_BLUE   = RGBColor(0x44, 0x72, 0xC4)   # table header background
WHITE      = RGBColor(0xFF, 0xFF, 0xFF)   # table header text
BLACK      = RGBColor(0x00, 0x00, 0x00)
```

---

## 4. Table Formatting Helpers

### Cell shading

```python
def set_cell_shading(cell, hex_color):
    """Set cell background color. hex_color without '#', e.g. '4472C4'."""
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>')
    cell._tc.get_or_add_tcPr().append(shading)
```

### Cell borders

```python
def set_cell_borders(cell, sz="4", color="000000"):
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    borders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'  <w:top    w:val="single" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'  <w:left   w:val="single" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'  <w:bottom w:val="single" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'  <w:right  w:val="single" w:sz="{sz}" w:space="0" w:color="{color}"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(borders)
```

### Header row styling

```python
def style_header_row(row):
    """Blue background, white bold centered text."""
    for cell in row.cells:
        set_cell_shading(cell, "4472C4")
        set_cell_borders(cell)
        for p in cell.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            for r in p.runs:
                r.font.color.rgb = WHITE
                r.font.bold = True
                r.font.size = Pt(9)
```

### Complete table builder

```python
def add_table(doc, headers, rows, col_widths=None, first_col_left=False):
    """Create a professionally-styled table with header and data rows."""
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    # Header
    for i, h in enumerate(headers):
        table.rows[0].cells[i].text = h
    style_header_row(table.rows[0])
    # Data rows
    for ri, row_data in enumerate(rows):
        for ci, val in enumerate(row_data):
            cell = table.rows[ri + 1].cells[ci]
            cell.text = str(val)
            align = (WD_ALIGN_PARAGRAPH.LEFT if (ci == 0 and first_col_left)
                     else WD_ALIGN_PARAGRAPH.CENTER)
            set_cell_borders(cell)
            for p in cell.paragraphs:
                p.alignment = align
                for r in p.runs:
                    r.font.size = Pt(9)
    # Column widths
    if col_widths:
        for row in table.rows:
            for ci, w in enumerate(col_widths):
                row.cells[ci].width = Inches(w)
    return table
```

---

## 5. Paragraph Helpers

### Justified body text

```python
def para_justified(doc, text, bold_phrases=None):
    """Add a justified paragraph. Optionally bold specific phrases."""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.space_before = Pt(0)
    if bold_phrases:
        add_rich_text(p, text, bold_phrases)
    else:
        run = p.add_run(text)
        run.font.size = Pt(10.5)
    return p
```

### Rich text (inline bold phrases)

```python
def add_rich_text(p, text, bold_phrases):
    """Render text with specific phrases in bold."""
    remaining = text
    while remaining:
        earliest_pos = len(remaining)
        earliest_phrase = None
        for bp in bold_phrases:
            idx = remaining.find(bp)
            if idx != -1 and idx < earliest_pos:
                earliest_pos = idx
                earliest_phrase = bp
        if earliest_phrase is None:
            r = p.add_run(remaining)
            r.font.size = Pt(10.5)
            break
        if earliest_pos > 0:
            r = p.add_run(remaining[:earliest_pos])
            r.font.size = Pt(10.5)
        r = p.add_run(earliest_phrase)
        r.font.size = Pt(10.5)
        r.font.bold = True
        remaining = remaining[earliest_pos + len(earliest_phrase):]
```

---

## 6. Images and Figures

### Centered image with caption

```python
def add_image(doc, path, width_inches):
    """Add a centered image. Gracefully handles missing files."""
    import os
    if not os.path.isfile(path):
        p = doc.add_paragraph(f"[IMAGE NOT FOUND: {path}]")
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        return
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    run.add_picture(path, width=Inches(width_inches))


def add_caption(doc, text):
    """Add an italic, centered figure caption."""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(12)
    run = p.add_run(text)
    run.italic = True
    run.font.size = Pt(9)
    return p
```

### Image sizing guidelines

| Content type | Recommended width | Notes |
|---|---|---|
| Full-width chart (bar, line) | 6.0–6.5" | Fills page with margins |
| Configuration diagram | 5.0–5.5" | Slightly smaller to avoid overflow |
| Detail diagram (cross-section) | 4.5–5.5" | Depends on aspect ratio |
| Multi-panel plot | 5.5–6.0" | Watch for label clipping |

**⚠ Page overflow:** Standard letter paper is 8.5" wide with 1" margins =
6.5" printable. Images wider than 6.5" will overflow. Always check the aspect
ratio — a tall image at 6.5" wide may push off the bottom of the page.

---

## 7. Page Breaks

Insert page breaks before major sections, especially those with figures:

```python
from docx.oxml.ns import qn

def page_break(doc):
    """Insert a page break."""
    p = doc.add_paragraph()
    run = p.add_run()
    run._r.append(parse_xml(f'<w:br {nsdecls("w")} w:type="page"/>'))
    return p
```

Or simply:

```python
doc.add_page_break()
```

**When to insert page breaks:**
- Before each Results section (figures should start at top of page)
- Before Appendix tables
- Before any section containing a full-width figure
- NOT between paragraphs within the same section

---

## 8. Title Block Pattern

```python
def add_title_block(doc, title, subtitle, date_line):
    """Professional report title block."""
    # Title
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(4)
    run = p.add_run(title)
    run.font.size = Pt(22)
    run.font.bold = True
    run.font.color.rgb = DARK_BLUE

    # Subtitle
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(4)
    run = p.add_run(subtitle)
    run.font.size = Pt(13)
    run.italic = True

    # Date line
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(24)
    run = p.add_run(date_line)
    run.font.size = Pt(11)
```

---

## 9. Complete Script Skeleton

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["python-docx"]
# ///
"""Generate <Report Title>.docx"""

import os
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import nsdecls
from docx.oxml import parse_xml

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "Report_Title.docx")

# ... paste helpers from §4–§8 above ...

def main():
    doc = Document()

    # ── Title ──
    add_title_block(doc, "Report Title", "Subtitle here", "Method  •  Date")

    # ── Section 1 ──
    doc.add_heading("1. Introduction", level=1)
    para_justified(doc, "Body text goes here...")

    # ── Section with bullets ──
    doc.add_heading("2. Configuration", level=1)
    para_justified(doc, "The following configurations were evaluated:")
    bullet_left(doc, "Configuration A — description")
    bullet_left(doc, "Configuration B — description")

    # ── Section with figure ──
    doc.add_page_break()
    doc.add_heading("3. Results", level=1)
    add_image(doc, os.path.join(BASE, "plots", "figure1.png"), 6.5)
    add_caption(doc, "Figure 1. Description of the figure.")

    # ── Table ──
    doc.add_heading("4. Data", level=1)
    add_table(doc,
        headers=["Config", "Value A", "Value B"],
        rows=[["Config 1", "1.23", "4.56"],
              ["Config 2", "7.89", "0.12"]],
        first_col_left=True)

    doc.save(OUT)
    size_kb = os.path.getsize(OUT) / 1024
    print(f"Saved {OUT} ({size_kb:.0f} KB)")

if __name__ == "__main__":
    main()
```

---

## 10. Verification Checklist

After generating a report, verify:

| Check | How | Why |
|---|---|---|
| Image count | Count `add_image` calls vs expected | Missing images fail silently |
| Captions | Every image has a caption below it | Easy to forget |
| Alignment | Grep for `JUSTIFY` — must NOT appear near `List Bullet` | #1 formatting bug |
| Page breaks | Count `add_page_break` calls | Figures should start fresh pages |
| Table count | Count `add_table` calls | Data tables can be accidentally dropped |
| File size | `os.path.getsize` > threshold (e.g., 400 KB with images) | Catches missing images |

Automated verification pattern:

```python
from docx import Document

def verify_report(path):
    doc = Document(path)
    images = sum(1 for rel in doc.part.rels.values()
                 if "image" in rel.reltype)
    tables = len(doc.tables)
    size_kb = os.path.getsize(path) / 1024

    checks = [
        ("Images", images, ">=", 1),
        ("Tables", tables, ">=", 1),
        ("File size (KB)", size_kb, ">", 100),
    ]
    for name, val, op, threshold in checks:
        ok = val >= threshold if op == ">=" else val > threshold
        status = "✓" if ok else "✗"
        print(f"  {status} {name}: {val}")
```

---

## 11. Matplotlib Integration Tips

When generating plots for embedding in DOCX reports:

### DPI and sizing

```python
fig.savefig("plot.png", dpi=200, bbox_inches='tight', pad_inches=0.1)
```

- **200 DPI** is the sweet spot — crisp on screen and print, reasonable file size
- `bbox_inches='tight'` prevents label clipping
- Match the figure aspect ratio to the DOCX embed width

### Multi-panel / multi-frequency bar charts

When showing multiple groups with sub-categories (e.g., DC / 24 kHz / 36 kHz):

```python
# Use 3 shade levels per color family: lightest → darkest
shades = {
    'Group A': ['#c6dbef', '#6baed6', '#2171b5'],  # blue
    'Group B': ['#fdd0a2', '#fd8d3c', '#d94801'],  # orange
    'Group C': ['#c7e9c0', '#74c476', '#238b45'],  # green
}
# Index 0 = DC (lightest), 1 = mid freq, 2 = high freq (darkest)
```

### Vertical stacking with shared colorbar

For multi-panel images that need a shared colorbar (e.g., field plots):

```python
import matplotlib.gridspec as gridspec

fig = plt.figure(figsize=(8, 12))
gs = gridspec.GridSpec(3, 1, height_ratios=[1, 1, 0.05], hspace=0.3)
ax1 = fig.add_subplot(gs[0])
ax2 = fig.add_subplot(gs[1])
cbar_ax = fig.add_subplot(gs[2])
# ... plot on ax1, ax2 ...
fig.colorbar(im, cax=cbar_ax, orientation='horizontal')
```

**⚠ Never overlay a legend on plot data.** Use `bbox_to_anchor` to place it
outside, or `ncol=` with small `fontsize=` to keep it compact.

---

## 12. Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Justified bullets | Ugly word spacing in short lines | Use `WD_ALIGN_PARAGRAPH.LEFT` for all list items |
| Missing `parse_xml` import | `NameError` at runtime | Import from `docx.oxml` |
| Image path wrong | Silent placeholder text | Use `os.path.isfile` check with clear error |
| Table too wide | Columns overflow page | Set explicit `col_widths` in `Inches()` |
| Figure pushed to next page | Awkward whitespace | Add page break before the figure's section |
| `nsdecls` missing | XML namespace error | Import from `docx.oxml.ns` |
| Overwriting open file | `PermissionError` | Close the DOCX in Word before running script |
| Colorbar overlaps data | Unreadable plot | Use `gridspec` with dedicated `cbar_ax` |
| Legend overlaps bars | Unreadable plot | Use `ncol=`, `fontsize=6.5`, `framealpha=0.9` |
