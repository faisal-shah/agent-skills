# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Compile a Circuitikz .tex schematic to PNG.

Usage:
    uv run scripts/compile_tex.py schematic.tex              # → schematic.png
    uv run scripts/compile_tex.py schematic.tex -o out.png   # custom output
    uv run scripts/compile_tex.py schematic.tex --dpi 600    # higher resolution
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path


def compile_tex(tex_path: str | Path, png_path: str | Path | None = None, dpi: int = 300) -> Path:
    """Compile a .tex file to PNG via pdflatex + pdftoppm."""
    tex_path = Path(tex_path).resolve()
    if not tex_path.exists():
        raise FileNotFoundError(tex_path)

    if png_path is None:
        png_path = tex_path.with_suffix(".png")
    else:
        png_path = Path(png_path).resolve()

    with tempfile.TemporaryDirectory() as tmpdir:
        result = subprocess.run(
            ["pdflatex", "-interaction=nonstopmode", f"-output-directory={tmpdir}", str(tex_path)],
            capture_output=True, text=True,
        )
        pdf = Path(tmpdir) / tex_path.with_suffix(".pdf").name
        if not pdf.exists():
            # Extract the first LaTeX error for a useful message
            for line in result.stdout.splitlines():
                if line.startswith("!"):
                    print(f"LaTeX error: {line}", file=sys.stderr)
            raise RuntimeError(f"pdflatex failed (exit {result.returncode})")

        stem = str(png_path.with_suffix(""))
        subprocess.run(
            ["pdftoppm", "-png", "-r", str(dpi), "-singlefile", str(pdf), stem],
            check=True, capture_output=True,
        )

    return png_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Compile Circuitikz .tex → PNG")
    parser.add_argument("tex", help="Input .tex file")
    parser.add_argument("-o", "--output", help="Output .png path (default: same stem as input)")
    parser.add_argument("--dpi", type=int, default=300, help="Resolution (default: 300)")
    args = parser.parse_args()

    out = compile_tex(args.tex, args.output, args.dpi)
    print(f"Saved: {out}")


if __name__ == "__main__":
    main()
