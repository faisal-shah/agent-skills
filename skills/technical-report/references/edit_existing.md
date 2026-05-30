# Editing Existing DOCX Reports

Use this workflow when the user asks to modify a current Word report while
preserving its formatting, figures, page layout, and surrounding content. This
is different from generating a new report from scratch.

## Workflow

1. Copy the input file to a backup before editing.
2. Inspect the document structure: paragraphs, headings, tables, sections,
   headers/footers, relationships, and media files.
3. Identify exact targets by stable text, heading, table index, bookmark, or
   relationship ID. Avoid broad search/replace.
4. Make scripted edits only to targeted objects.
5. Save as a new output file.
6. Reopen both original and edited files and compare expected preserved counts.

## Inspection Script

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["python-docx"]
# ///
from pathlib import Path
from docx import Document

path = Path("Original.docx")
doc = Document(path)

print(f"paragraphs={len(doc.paragraphs)} tables={len(doc.tables)} sections={len(doc.sections)}")
print("headings:")
for index, paragraph in enumerate(doc.paragraphs):
    style = paragraph.style.name if paragraph.style else ""
    if style.startswith("Heading"):
        print(index, style, paragraph.text)

print("media relationships:")
for rel_id, rel in doc.part.rels.items():
    if "image" in rel.reltype:
        print(rel_id, rel.target_ref)

for index, section in enumerate(doc.sections):
    print(
        index,
        round(section.page_width.inches, 2),
        round(section.page_height.inches, 2),
        round(section.left_margin.inches, 2),
        round(section.right_margin.inches, 2),
    )
```

## Preservation Rules

- Preserve section page width/height, orientation, margins, headers, footers,
  numbering, and existing media unless the user explicitly asks for a change.
- Do not recreate the whole document when the task is to replace one figure or
  paragraph.
- Do not reset styles globally unless the task is a full redesign.
- If replacing figures, verify the media count changed only as expected.
- If changing page orientation for one wide table, add a bounded landscape
  section and switch back to portrait.

## Targeted Text Replacement

```python
def replace_once(doc, old: str, new: str) -> None:
    matches = [p for p in doc.paragraphs if old in p.text]
    if len(matches) != 1:
        raise AssertionError(f"Expected exactly one match for {old!r}, found {len(matches)}")
    paragraph = matches[0]
    paragraph.text = paragraph.text.replace(old, new)
```

This simple replacement loses mixed run styling inside that paragraph. For
styled text, rebuild runs intentionally or use a lower-level XML approach.

## Targeted Figure Replacement

`python-docx` does not provide a high-level "replace image" API. Prefer one of:

1. remove and recreate a figure paragraph at a known location;
2. replace the image file inside the DOCX package only when dimensions and type
   are compatible;
3. rebuild the section from source if many figures change.

After replacement, reopen the DOCX and verify image counts, captions, nearby
text, and section sizes.

## QA for Existing Edits

Report both changed and preserved facts:

- original path and backup path;
- output path;
- changed targets;
- paragraph/table/image counts before and after;
- preserved section page sizes/margins;
- any skipped visual preview tools.

