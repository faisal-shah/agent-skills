# Executive PDF Fallback

Use this path when the user asks for a short executive PDF, Word fidelity is not
required, or DOCX/Office tooling is blocked. Keep the report package discipline:
script, source files, figures, output PDF, and manifest.

Prefer `fpdf2` for simple table-driven PDFs. Avoid WeasyPrint unless the
environment already has its native dependencies and it is known to work.

## Minimal fpdf2 Script

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["fpdf2"]
# ///
from __future__ import annotations

import json
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

from fpdf import FPDF

PACKAGE = Path(__file__).resolve().parent
OUT = PACKAGE / "Executive_Report.pdf"
MANIFEST = PACKAGE / "report_manifest.json"


def clean_text(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    return normalized.encode("latin-1", "ignore").decode("latin-1")


class PDF(FPDF):
    def header(self):
        self.set_font("Helvetica", "B", 10)
        self.cell(0, 8, clean_text("Executive Technical Summary"), ln=True)
        self.ln(2)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "", 8)
        self.cell(0, 10, f"Page {self.page_no()}", align="C")


pdf = PDF()
pdf.set_auto_page_break(auto=True, margin=15)
pdf.add_page()
pdf.set_font("Helvetica", "B", 16)
pdf.multi_cell(0, 8, clean_text("Report Title"))
pdf.ln(2)

pdf.set_font("Helvetica", "", 10)
pdf.multi_cell(0, 5, clean_text("State the conclusion first, then evidence and limitations."))

pdf.set_font("Helvetica", "B", 11)
pdf.cell(60, 7, "Item", border=1)
pdf.cell(120, 7, "Finding", border=1, ln=True)
pdf.set_font("Helvetica", "", 9)
for item, finding in [("Scope", "Short executive summary")]:
    pdf.cell(60, 7, clean_text(item), border=1)
    pdf.cell(120, 7, clean_text(finding), border=1, ln=True)

pdf.output(OUT)
MANIFEST.write_text(
    json.dumps(
        {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "generator": str(Path(__file__).resolve()),
            "output_pdf": str(OUT),
        },
        indent=2,
    ),
    encoding="utf-8",
)
print(f"Saved {OUT} ({OUT.stat().st_size / 1024:.1f} KB)")
```

## Unicode Options

`Helvetica` only supports Latin-1. For engineering reports with symbols,
subscripts, Greek letters, or non-English text:

1. Register a Unicode TTF if available.
2. Otherwise normalize text with `clean_text()` and spell out units/symbols.
3. Add a note if normalization changes symbols that matter technically.

## PDF Quality Checklist

- Keep executive PDFs short and conclusion-first.
- Use tables for comparisons and decisions.
- Do not cram dense technical appendices into PDF-only reports unless requested.
- Keep the source evidence and generator in the package.
- If DOCX is still required later, switch back to the main DOCX workflow.

