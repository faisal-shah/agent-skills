---
name: technical-report
description: >
  Generate professional, reproducible DOCX technical reports with python-docx;
  update existing Word reports safely; create short executive PDFs when DOCX is
  not required. Use for report packages, tables, figures, captions, previews,
  evidence tracking, and QA.
---

# Technical Report Skill

Use this skill when the deliverable is a polished technical report, not just a
document file. The agent's job is to produce a reproducible report package:
source evidence, generated figures, generator script, DOCX/PDF outputs, and QA
results that another agent can rerun.

## Decision Flow

1. **New technical DOCX?** Build a report package and generate the DOCX from
   `generate_report.py`. This is the default path.
2. **Existing DOCX edit?** Preserve the original, inspect structure first, then
   make scripted targeted edits. Read `references/edit_existing.md`.
3. **Executive PDF only?** Use a short `fpdf2` generator when Word fidelity is
   unnecessary or DOCX tooling is blocked. Read `references/pdf_fallback.md`.
4. **Figures required?** Generate figure files before DOCX assembly, run a
   visual/technical critique, then embed only reviewed assets. Read
   `references/figures.md` for complex plots, screenshots, equations, or page
   previews.
5. **Unusual DOCX formatting?** Keep the main skeleton as the source of truth;
   read `references/docx_helpers.md` for helper variants only when needed.

Do not hand-edit a generated `.docx`. If a report is durable or likely to be
revised, keep the script and inputs beside the output.

## Report Package Contract

For durable deliverables, create a package in the user's workspace, not in
`/tmp`. Use `/tmp` only for disposable experiments.

```text
reports/<report-slug>/
  generate_report.py
  data/
  source_docs/
  figs/
  page_previews/
  Report_Name.docx
  Report_Name_preview.pdf        # if export tools exist
  figure_review_log.txt
  report_manifest.json
```

Final responses should report the DOCX path, optional PDF/page previews,
generator script path, figure/table/caption counts, source documents used, and
known limitations. If working on Windows files through WSL, show the final path
in the user's Windows-facing location when useful.

## Agent Rules

- **Evidence first:** read/download the source documents and data before writing
  conclusions. Cite source file paths in the generator or manifest.
- **Regenerate, do not patch:** centralize assumptions, constants, source paths,
  figure metadata, expected counts, key phrases, and banned stale phrases at the
  top of the generator.
- **Update QA with content changes:** when figures, tables, or generated
  artifacts are added/removed, update named artifact lists, manifests, required
  phrase/banned-phrase checks, and expected-count assertions in the same change.
- **Fail loudly for missing assets:** raise on missing figures or source files
  unless the user explicitly asks for placeholders.
- **Alignment rule:** body paragraphs are justified; bullets and numbered lists
  are always left-aligned. Never justify list items.
- **Figures are separate artifacts:** generate them first, review them, then
  embed them. Every figure needs nearby explanatory text and a numbered caption.
- **Captions are generated, not hand-numbered:** use report-owned counters for
  figures/tables and verify numbering is unique, sequential, and gapless.
- **QA is mandatory:** reopen the DOCX, count structure, scan for stale text,
  verify assets, and export/render previews when tools are available.
- **Windows/Office friction:** prefer standalone `.py` files over inline
  PowerShell heredocs; handle Word-open `PermissionError` by saving an
  `_updated` file and saying so.

## Cross-Platform Defaults

The common path is intentionally portable across Linux, WSL, and Windows:

- Use Python scripts with `pathlib.Path`; avoid shell-specific path assembly in
  report generators.
- Run generators with `uv run reports/<report-slug>/generate_report.py` on
  Linux/WSL, or the equivalent standalone script invocation on Windows.
- Use `install.sh` on Linux/macOS/WSL and `install.ps1` on Windows; both install
  `SKILL.md` and `references/`.
- When working on `/mnt/c/...` paths from WSL, keep artifacts in the Windows
  project tree and report the Windows-facing output path when useful.
- Treat PDF export and page previews as capability-based: use LibreOffice,
  Word automation, or PDF renderers when present; otherwise keep structural DOCX
  QA and state which visual checks were skipped.
- Avoid inline PowerShell heredocs and long one-liners on Windows. Write a
  standalone `.py` file and run it.

## Canonical Generator Skeleton

Create `generate_report.py` inside the report package and adapt this skeleton.
It is intentionally self-contained for the common path; add `matplotlib` or
other dependencies only when the script generates figures.

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["python-docx"]
# ///
"""Generate Report_Name.docx from local evidence, data, and figures."""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Sequence

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import parse_xml
from docx.oxml.ns import nsdecls
from docx.shared import Inches, Pt, RGBColor


PACKAGE = Path(__file__).resolve().parent
DATA_DIR = PACKAGE / "data"
SOURCE_DIR = PACKAGE / "source_docs"
FIG_DIR = PACKAGE / "figs"
PREVIEW_DIR = PACKAGE / "page_previews"

REPORT_TITLE = "Report Name"
REPORT_SUBTITLE = "Technical report subtitle"
OUTPUT_DOCX = PACKAGE / "Report_Name.docx"
MANIFEST = PACKAGE / "report_manifest.json"

SOURCE_DOCS = [
    SOURCE_DIR / "source_document.pdf",
]
EXPECTED_TABLES = 1
KEY_PHRASES = ["Report Name"]
BANNED_PHRASES = ["old estimate", "placeholder", "[IMAGE NOT FOUND"]

DARK_BLUE = RGBColor(0x1F, 0x38, 0x64)
HEADER_BLUE = "4472C4"
WHITE = RGBColor(0xFF, 0xFF, 0xFF)


@dataclass(frozen=True)
class FigureSpec:
    path: Path
    caption: str
    width_in: float = 6.25


@dataclass
class CaptionCounter:
    figures: int = 0
    tables: int = 0


FIGURES = [
    FigureSpec(FIG_DIR / "figure_1.png", "Figure caption."),
]
CAPTIONS = CaptionCounter()


def require_files(paths: Iterable[Path]) -> None:
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing required files:\n" + "\n".join(missing))


def set_cell_shading(cell, hex_color: str) -> None:
    shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>')
    cell._tc.get_or_add_tcPr().append(shading)


def set_cell_borders(cell, size: str = "4", color: str = "000000") -> None:
    borders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:top w:val="single" w:sz="{size}" w:space="0" w:color="{color}"/>'
        f'<w:left w:val="single" w:sz="{size}" w:space="0" w:color="{color}"/>'
        f'<w:bottom w:val="single" w:sz="{size}" w:space="0" w:color="{color}"/>'
        f'<w:right w:val="single" w:sz="{size}" w:space="0" w:color="{color}"/>'
        "</w:tcBorders>"
    )
    cell._tc.get_or_add_tcPr().append(borders)


def configure_doc(doc: Document) -> None:
    section = doc.sections[0]
    section.orientation = WD_ORIENT.PORTRAIT
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(0.75)
    section.bottom_margin = Inches(0.75)
    section.left_margin = Inches(0.75)
    section.right_margin = Inches(0.75)

    styles = doc.styles
    styles["Normal"].font.name = "Aptos"
    styles["Normal"].font.size = Pt(10.5)
    for name in ("Heading 1", "Heading 2", "Heading 3"):
        styles[name].font.name = "Aptos"
        styles[name].font.color.rgb = DARK_BLUE


def add_title_block(doc: Document, title: str, subtitle: str) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(4)
    r = p.add_run(title)
    r.font.size = Pt(22)
    r.font.bold = True
    r.font.color.rgb = DARK_BLUE

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(4)
    r = p.add_run(subtitle)
    r.font.size = Pt(13)
    r.italic = True

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(18)
    r = p.add_run(datetime.now().strftime("%B %d, %Y"))
    r.font.size = Pt(10.5)


def add_body(doc: Document, text: str) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.space_after = Pt(6)
    r = p.add_run(text)
    r.font.size = Pt(10.5)


def add_bullet(doc: Document, text: str) -> None:
    p = doc.add_paragraph(style="List Bullet")
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.space_before = Pt(0)
    r = p.add_run(text)
    r.font.size = Pt(10.5)


def add_caption(doc: Document, text: str) -> None:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(10)
    r = p.add_run(text)
    r.italic = True
    r.font.size = Pt(9)


def next_figure_caption(text: str) -> str:
    CAPTIONS.figures += 1
    return f"Figure {CAPTIONS.figures}. {text}"


def next_table_caption(text: str) -> str:
    CAPTIONS.tables += 1
    return f"Table {CAPTIONS.tables}. {text}"


def add_figure(doc: Document, spec: FigureSpec) -> None:
    if not spec.path.exists():
        raise FileNotFoundError(f"Missing figure: {spec.path}")
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run().add_picture(str(spec.path), width=Inches(spec.width_in))
    add_caption(doc, next_figure_caption(spec.caption))


def add_table(
    doc: Document,
    caption: str,
    headers: Sequence[str],
    rows: Sequence[Sequence[object]],
    *,
    first_col_left: bool = False,
    col_widths: Sequence[float] | None = None,
) -> None:
    if any(len(row) != len(headers) for row in rows):
        raise ValueError("Every table row must match the header count.")

    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False

    for index, header in enumerate(headers):
        cell = table.rows[0].cells[index]
        cell.text = header
        set_cell_shading(cell, HEADER_BLUE)
        set_cell_borders(cell)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        for paragraph in cell.paragraphs:
            paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
            for run in paragraph.runs:
                run.font.bold = True
                run.font.color.rgb = WHITE
                run.font.size = Pt(9)

    for row_index, row_data in enumerate(rows, start=1):
        for col_index, value in enumerate(row_data):
            cell = table.rows[row_index].cells[col_index]
            cell.text = str(value)
            set_cell_borders(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            align = (
                WD_ALIGN_PARAGRAPH.LEFT
                if first_col_left and col_index == 0
                else WD_ALIGN_PARAGRAPH.CENTER
            )
            for paragraph in cell.paragraphs:
                paragraph.alignment = align
                for run in paragraph.runs:
                    run.font.size = Pt(9)

    if col_widths:
        for row in table.rows:
            for col_index, width in enumerate(col_widths):
                row.cells[col_index].width = Inches(width)

    add_caption(doc, next_table_caption(caption))


def save_with_word_open_fallback(doc: Document, path: Path) -> Path:
    try:
        doc.save(path)
        return path
    except PermissionError:
        fallback = path.with_name(f"{path.stem}_updated{path.suffix}")
        doc.save(fallback)
        print(f"Original file appears open; saved fallback: {fallback}")
        return fallback


def count_docx_images(doc: Document) -> int:
    return sum(1 for rel in doc.part.rels.values() if "image" in rel.reltype)


def document_text(doc: Document) -> str:
    parts = [paragraph.text for paragraph in doc.paragraphs]
    for table in doc.tables:
        for row in table.rows:
            parts.extend(cell.text for cell in row.cells)
    return "\n".join(parts)


def caption_numbers(captions: Sequence[str], kind: str) -> list[int]:
    pattern = re.compile(rf"^{kind} (\d+)\.")
    return [
        int(match.group(1))
        for caption in captions
        if (match := pattern.match(caption))
    ]


def verify_docx(path: Path) -> dict[str, object]:
    doc = Document(path)
    text = document_text(doc)
    images = count_docx_images(doc)
    tables = len(doc.tables)
    captions = [
        paragraph.text
        for paragraph in doc.paragraphs
        if paragraph.text.startswith(("Figure ", "Table "))
    ]
    headings = [
        paragraph.text
        for paragraph in doc.paragraphs
        if paragraph.style and paragraph.style.name.startswith("Heading")
    ]

    failures = []
    expected_images = len(FIGURES)
    if images < expected_images:
        failures.append(f"expected at least {expected_images} images, found {images}")
    if tables < EXPECTED_TABLES:
        failures.append(f"expected at least {EXPECTED_TABLES} tables, found {tables}")
    for phrase in KEY_PHRASES:
        if phrase not in text:
            failures.append(f"missing key phrase: {phrase}")
    for phrase in BANNED_PHRASES:
        if phrase.lower() in text.lower():
            failures.append(f"banned/stale phrase present: {phrase}")
    for kind in ("Figure", "Table"):
        numbers = caption_numbers(captions, kind)
        expected = list(range(1, len(numbers) + 1))
        if numbers != expected:
            failures.append(f"{kind} captions not sequential/gapless: {numbers}")
    for section in doc.sections:
        width = round(section.page_width.inches, 2)
        height = round(section.page_height.inches, 2)
        if (width, height) not in {(8.5, 11.0), (11.0, 8.5)}:
            failures.append(f"unexpected section size: {width} x {height}")

    qa = {
        "docx": str(path),
        "size_kb": round(path.stat().st_size / 1024, 1),
        "images": images,
        "tables": tables,
        "captions": len(captions),
        "headings": len(headings),
        "sections": len(doc.sections),
        "failures": failures,
    }
    if failures:
        raise AssertionError("DOCX QA failed:\n" + "\n".join(failures))
    return qa


def write_manifest(output_path: Path, qa: dict[str, object]) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator": str(Path(__file__).resolve()),
        "output_docx": str(output_path),
        "source_docs": [str(path) for path in SOURCE_DOCS],
        "figures": [asdict(spec) | {"path": str(spec.path)} for spec in FIGURES],
        "qa": qa,
    }
    MANIFEST.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def build_report() -> Path:
    CAPTIONS.figures = 0
    CAPTIONS.tables = 0
    require_files(SOURCE_DOCS)
    require_files(spec.path for spec in FIGURES)

    doc = Document()
    configure_doc(doc)
    add_title_block(doc, REPORT_TITLE, REPORT_SUBTITLE)

    doc.add_heading("1. Executive Summary", level=1)
    add_body(
        doc,
        "State the engineering conclusion first, then summarize the evidence, "
        "scope, assumptions, and limitations.",
    )
    add_bullet(doc, "Bullets are left-aligned and concise.")
    add_bullet(doc, "Measured, calculated, inferred, assumed, and unknown values are distinguished.")

    doc.add_heading("2. Evidence and Method", level=1)
    add_body(doc, "List the source documents, data files, and calculations used.")
    add_table(
        doc,
        "Source evidence used for the report.",
        ["Source", "Use", "Status"],
        [[path.name, "Input evidence", "Available"] for path in SOURCE_DOCS],
        first_col_left=True,
        col_widths=[2.4, 3.0, 1.2],
    )

    doc.add_page_break()
    doc.add_heading("3. Results", level=1)
    for spec in FIGURES:
        add_figure(doc, spec)
        add_body(doc, "Explain what this figure proves and any limitations.")

    saved_path = save_with_word_open_fallback(doc, OUTPUT_DOCX)
    qa = verify_docx(saved_path)
    write_manifest(saved_path, qa)
    print(json.dumps(qa, indent=2))
    print(f"Saved: {saved_path}")
    print(f"Manifest: {MANIFEST}")
    return saved_path


if __name__ == "__main__":
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    PREVIEW_DIR.mkdir(exist_ok=True)
    build_report()
```

Run with:

```bash
uv run reports/<report-slug>/generate_report.py
```

If dependency resolution happens on Windows/corporate networks, use the `uv`
skill's TLS guidance (`--native-tls` and PyPI insecure-host flags).

## Figure Pipeline

1. Put raw data and source screenshots under `data/` or `source_docs/`.
2. Generate final figures into `figs/` before DOCX assembly.
3. Review at the size it will appear in Word: labels readable, no clipped axes,
   no legend/data overlap, no colorbar overlap, no blank screenshots, no
   transparent background surprises.
4. Review semantics: axes, units, scales, model/reference labels, and captions
   must match the plotted data. Use separate panels, normalization, or a
   secondary axis for very different magnitudes/units; captions must describe
   every panel actually shown.
5. Record defects and fixes in `figure_review_log.txt`.
6. Only then embed figures and rerun DOCX QA.

Use this critic prompt for important figures:

```text
Review this figure as an adversarial technical reviewer. Check whitespace,
legibility, label collisions, domain conventions, whether it communicates the
intended engineering point, and whether captions/text overclaim. Return only
actionable defects.
```

See `references/figures.md` for matplotlib settings, screenshot annotation,
equation images, PDF previews, and visual QA ladders.

## Existing DOCX Edit Mode

Use this path only when the user asks to preserve or modify an existing Word
file. Keep the original intact:

1. Copy `Original.docx` to `Original_backup.docx`.
2. Inspect paragraphs, tables, sections, headers/footers, relationships, and
   `word/media` before editing.
3. Replace only targeted text, figures, tables, or sections.
4. Preserve page sizes, margins, orientation, headers, footers, numbering, and
   existing media unless the user asks otherwise.
5. Save as a new file and run structural QA against both expected changes and
   preserved counts.

Read `references/edit_existing.md` before editing an existing report.

## QA Ladder

Run the strongest available checks without blocking on unavailable GUI tools:

1. **Package checks:** required source docs, data, figures, generator, and
   manifest exist; stale/orphan generated files are absent or explicitly
   explained.
2. **DOCX structural checks:** reopen with `python-docx`; count images, tables,
   captions, headings, sections; verify key phrases, banned stale phrases, and
   unique/gapless Figure/Table numbering.
3. **Layout checks:** verify section page sizes and orientation; ensure figures
   are not wider than the printable page.
4. **PDF export:** if LibreOffice or Word automation is available, export a PDF
   preview.
5. **Page previews:** if PDF rendering tools are available, render preview pages
   and inspect figures/tables visually.

Structural DOCX checks prove packaging, not visual correctness. For important
reports, inspect rendered PDF/page previews or screenshots before claiming the
report is visually reviewed.

If export/render tools are unavailable, say which checks were skipped and keep
the structural QA results in `report_manifest.json`.

## Common Failure Patterns

| Symptom | Likely cause | Response |
|---|---|---|
| Ugly wide spaces in bullets | List items were justified | Set all list paragraphs to `WD_ALIGN_PARAGRAPH.LEFT`. |
| Missing images but DOCX exists | Asset path wrong or placeholder fallback | Raise on missing assets and verify image relationships. |
| Old figure appears in final report | Output dir reused without clean rebuild | Clean generated dirs or manifest-check expected vs unexpected artifacts. |
| Figure unreadable in Word | Plot reviewed only at full image size | Review at embed width; increase DPI/font sizes or simplify. |
| Page size changed unexpectedly | Existing document edit reset sections | Verify every section width, height, margins, and orientation. |
| `PermissionError` on save | DOCX open in Word | Save `_updated.docx` and report the fallback path. |
| PowerShell heredoc/tool-call failure | Long inline script on Windows | Write a standalone `.py` file and run it with `uv run`. |
| Unicode errors in PDF | Built-in PDF font lacks glyphs | Normalize text or register a Unicode TTF; see PDF reference. |
| Stale conclusions remain | Manual patching instead of regeneration | Centralize assumptions and banned phrases, then regenerate. |
| Code block appears flattened | One DOCX run contained embedded `\n` | Insert explicit Word line breaks or separate paragraphs; see DOCX helpers. |
