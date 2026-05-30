# DOCX Helper Reference

Use this reference only after the main `SKILL.md` skeleton is not enough. Keep
new reports based on the canonical generator; copy helper variants from here
sparingly.

## Alignment Defaults

| Element | Alignment |
|---|---|
| Body paragraphs | `WD_ALIGN_PARAGRAPH.JUSTIFY` |
| Bullets and numbered lists | `WD_ALIGN_PARAGRAPH.LEFT` |
| Figure/table captions | `WD_ALIGN_PARAGRAPH.CENTER`, italic |
| Header cells | `WD_ALIGN_PARAGRAPH.CENTER` |
| Numeric table cells | `WD_ALIGN_PARAGRAPH.CENTER` |
| First text column | `WD_ALIGN_PARAGRAPH.LEFT` |

Never justify list items. If a helper creates list paragraphs, set `LEFT`
inside that helper instead of relying on document defaults.

## Rich Text With Bold Phrases

```python
def add_rich_text(paragraph, text: str, bold_phrases: list[str]) -> None:
    remaining = text
    while remaining:
        earliest_pos = len(remaining)
        earliest_phrase = None
        for phrase in bold_phrases:
            position = remaining.find(phrase)
            if position != -1 and position < earliest_pos:
                earliest_pos = position
                earliest_phrase = phrase
        if earliest_phrase is None:
            run = paragraph.add_run(remaining)
            run.font.size = Pt(10.5)
            break
        if earliest_pos:
            run = paragraph.add_run(remaining[:earliest_pos])
            run.font.size = Pt(10.5)
        run = paragraph.add_run(earliest_phrase)
        run.font.size = Pt(10.5)
        run.font.bold = True
        remaining = remaining[earliest_pos + len(earliest_phrase):]
```

Use this for brief emphasis, not for whole paragraphs. If many phrases need
semantic styling, store them in a data structure at the top of the generator.

## Landscape Section Helper

Use landscape only for wide tables or schematics. Return to portrait afterward
and verify section sizes in QA.

```python
from docx.enum.section import WD_ORIENT
from docx.shared import Inches


def add_landscape_section(doc):
    section = doc.add_section()
    section.orientation = WD_ORIENT.LANDSCAPE
    section.page_width = Inches(11)
    section.page_height = Inches(8.5)
    section.top_margin = Inches(0.6)
    section.bottom_margin = Inches(0.6)
    section.left_margin = Inches(0.6)
    section.right_margin = Inches(0.6)
    return section
```

## Safe XML Values

When writing direct Word XML, escape text values and keep XML snippets small.
Most formatting should use `python-docx` APIs; direct XML is for features the
API does not expose.

```python
from html import escape


def safe_xml_text(value: object) -> str:
    return escape(str(value), quote=True)
```

For color fills and borders, pass only validated hex strings such as
`"4472C4"`. Do not put user text into XML attributes without escaping.

## Width Planning

Letter portrait with 0.75 inch margins has about 7.0 inches of printable width.
Use these starting points:

| Content | Width |
|---|---:|
| Full-width chart | 6.25 to 6.75 in |
| Dense schematic | 6.0 to 6.5 in |
| Detail image | 4.5 to 5.75 in |
| Two-column figure | 3.1 to 3.3 in each |

If a figure is tall, reducing width may still be necessary to avoid pushing the
caption to the next page.

## Tables With Footnotes

For dense technical tables, keep the table compact and put definitions in a
paragraph below it instead of widening columns.

```python
add_table(
    doc,
    "Table 3. Test conditions.",
    ["Case", "Voltage", "Frequency", "Notes"],
    rows,
    first_col_left=True,
    col_widths=[1.0, 1.2, 1.2, 3.2],
)
add_body(doc, "Notes: RMS values are line-to-line unless otherwise stated.")
```

## Equation Images

`python-docx` has limited native equation support. For important equations,
render high-DPI equation images with transparent or white backgrounds, place
them under `figs/`, caption them if they are standalone, and include the source
LaTeX string in the manifest or generator.

