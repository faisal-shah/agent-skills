# Figure and Preview Workflow

Most report rework comes from visual quality failures. Treat figures as
deliverables with their own generation and review loop.

## Figure Contract

Each figure should have:

- a source data file or source document path;
- a generated file in `figs/`;
- a caption stored near the figure metadata in `generate_report.py`;
- nearby body text explaining the engineering point;
- a review note in `figure_review_log.txt`.

Before final QA, clean or manifest-check generated figure directories so every
embedded figure is from the current build and no orphaned old figure is reused.

## Matplotlib Defaults

```python
import matplotlib.pyplot as plt

plt.rcParams.update({
    "figure.dpi": 120,
    "savefig.dpi": 220,
    "font.size": 9,
    "axes.titlesize": 10,
    "axes.labelsize": 9,
    "legend.fontsize": 8,
})

fig.savefig(
    FIG_DIR / "result.png",
    dpi=220,
    bbox_inches="tight",
    pad_inches=0.08,
    facecolor="white",
)
```

Use `facecolor="white"` unless transparency is specifically tested in the
target DOCX/PDF workflow. Transparent PNGs can render poorly in Word.

## Legends and Colorbars

- Never let a legend cover data; move it outside the axes or below the plot.
- Use a dedicated colorbar axis for multipanel plots.
- For grouped bars, use color families plus shade levels and label directly
  when possible.

```python
fig, axes = plt.subplots(2, 1, figsize=(7.0, 7.5), constrained_layout=True)
# ...
fig.legend(handles, labels, loc="lower center", ncol=3, frameon=False)
fig.savefig(FIG_DIR / "multipanel.png", bbox_inches="tight", facecolor="white")
```

## Screenshot Annotation

Screenshots alone are usually weak evidence. Add callouts, arrows, crop boxes,
or numbered labels before embedding. Validate screenshots are not blank:

```python
from pathlib import Path
from PIL import Image, ImageStat


def assert_not_blank(path: Path) -> None:
    image = Image.open(path).convert("L")
    extrema = ImageStat.Stat(image).extrema[0]
    if extrema[1] - extrema[0] < 5:
        raise AssertionError(f"Screenshot appears blank: {path}")
```

Add `pillow` to PEP 723 metadata if using this check.

## Adversarial Figure Review

For important figures, run a critic pass before embedding:

```text
Review this figure as an adversarial technical reviewer. Check whitespace,
legibility at Word embed size, clipped labels, label collisions, legend/data
overlap, colorbar overlap, engineering conventions, whether the figure proves
the intended point, and whether the caption/text overclaim. Return only
actionable defects.
```

Log review results as:

```text
Figure 4 - defect: legend overlaps curve at 36 kHz.
Figure 4 - fix: moved legend below plot, increased bottom margin.
Figure 4 - status: accepted after rerender.
```

## Semantic Figure Checks

Visual polish is not enough. Verify the figure says the same thing as the data,
caption, and body text:

- axes, units, scale type, and legend labels match the source data;
- model, reference, measured, inferred, and unavailable values are distinguishable;
- captions describe every panel actually shown and do not mention missing panels;
- very different magnitudes or units use separate panels, normalization, or a
  clearly labeled secondary axis instead of one misleading linear axis;
- zero/NA bars or blank regions are explicitly labeled when they carry meaning.

## PDF Export and Page Previews

Use the strongest available preview path:

```bash
libreoffice --headless --convert-to pdf --outdir reports/<slug> reports/<slug>/Report_Name.docx
pdftoppm -png -r 150 reports/<slug>/Report_Name.pdf reports/<slug>/page_previews/page
```

If those tools are unavailable, keep the structural QA and note that visual page
previews were skipped. Do not imply a visual inspection happened unless preview
pages or screenshots were actually reviewed.

## Visual QA Checklist

- Title page and executive summary fit cleanly.
- Every figure appears near the relevant text.
- Captions are directly below figures and numbered sequentially.
- Axis labels, tick labels, legends, and callouts are readable at embed size.
- Axes, units, panel captions, and model/reference labels match the plotted data.
- Tables do not overflow page margins.
- No stale screenshots, blank images, clipped labels, or cropped legends.
- Conclusions are supported by the visible figure or cited source.
