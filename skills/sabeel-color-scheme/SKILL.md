---
name: sabeel-color-scheme
description: Apply the Sabeel Institute brand palette (Option 1) accurately and appropriately — the five colours, their roles and proportions, the accessibility-driven text and gold cuts, and the single-light-theme rule. Use when designing or building any Sabeel Institute surface (the kanban app, the time tracker, web pages, printed statements, illustrations, charts).
---

# Sabeel Institute colour scheme

The brand palette is **"Option 1"** (designer, 2026-07-21). It supersedes the
older colour-usage-guide JPG. The same five colours are used across every Sabeel
surface, so this skill is the one place to get them right.

**Read the whole thing before picking a colour.** The palette is small and the
mistakes are specific: using taupe for body text, using gold where it can't be
read, saturating raspberry into a background, or inventing a dark theme.

## The five brand colours

| Colour | Hex | Share | Role |
|---|---|---|---|
| **Warm Ivory** | `#F6EBDD` | ~35% | Foundation — page and card backgrounds, forms |
| **Soft Sage** | `#A8B89A` | ~30% | Calm & community — alternate sections, footers, decor, success |
| **Dark Raspberry** | `#83114F` | ~20% | Brand identity — headings, buttons, links, CTAs. A **plum**, not a red |
| **Antique Gold** | `#C6A15B` | ~10% | Elegance — dividers, borders, small accents, hover |
| **Mushroom Taupe** | `#A58D7A` | ~5% | Support — captions, borders, shadows |

The proportions matter as much as the hexes. The base is ivory and sage, light
and airy. Raspberry is the identity, spent **with purpose** — a button, a
heading, a link — never a full-bleed background wash. Gold is a garnish:
dividers, a focus ring, a selected state. If a layout is more than a fifth
raspberry or shows large fields of gold, it is off-brand even with the right
hexes.

## Accessibility: three cuts you must know

The palette is a *brand* palette; two of its colours fail WCAG contrast in the
uses people reach for first. Legibility wins, and these are the sanctioned
substitutes.

1. **Never set body text in Mushroom Taupe.** `#A58D7A` on ivory is ~2.7:1, well
   under the 4.5:1 minimum. Use:
   - **Primary text `#3A2F28`** — deep warm brown, ~11:1. Same family, reads.
   - **Secondary text `#6A5748`** — darkened taupe, ~5.8:1.
   - Keep true taupe `#A58D7A` for **captions, borders, dividers, shadows** —
     where softness is the point and contrast is not load-bearing.

2. **Gold cannot be read as text or a signal at brand strength.** `#C6A15B` on
   ivory is ~2.1:1. Deepen it for any job where it must be *read*:
   - **Gold as text** (a label, a badge caption): `#795E2A` (~5.2:1).
   - **Gold as a status/warning signal**: `#977535` (~3.6:1, fine for a UI dot
     or icon at ≥3:1).
   - Leave gold true (`#C6A15B`) only where it is **decoration** — a divider, a
     hairline border, a hover tint.

3. **Raspberry is comfortable.** `#83114F` on ivory is ~8.3:1, and ivory
   (`#F9F2E9`) on a raspberry fill is ~8.8:1. Headings, links and primary buttons
   are fine exactly as specified. Text on a raspberry surface should be **warm
   ivory, never pure white** (`#F9F2E9`).

## Single light theme — there is NO dark mode

The Sabeel apps ship **one light appearance** (decided 2026-07-21). Do not add a
dark theme, a `prefers-color-scheme` branch, or a "derived dark" palette to a
Sabeel surface unless the team explicitly reverses this. A dormant dark theme
was deliberately removed rather than disabled, precisely so it does not creep
back. On native apps, `userInterfaceStyle` is pinned to `"light"`.

If you are building a *standalone* web page (a landing page, a preview) that is
not one of the apps, you may still honour the viewer's OS theme for the page
chrome — but the brand specimens themselves render in these fixed light values.

## Applying it in an app: semantic tokens, one file

Both Sabeel apps put **every** colour behind role-named semantic tokens and
forbid raw hex literals in screens (ESLint-enforced), with a single palette file
as the only exception. Follow the same discipline — it is what made the Option 1
refresh a one-file change. Names describe **role, not appearance**
(`text.muted`, never `text.grey`).

The app-level light token set (derived from the five brand colours):

```
bg.canvas       #F6EBDD   app background
bg.surface      #FBF6F0   cards, sheets, rows (a touch brighter, so they lift)
bg.raised       #FFFFFF   menus, a dragged card
bg.inset        #E7DDD0   inputs, recessed areas
bg.accentSoft   #E6CCC9   tint behind a selected/active item
bg.dangerSoft   #F8E4E1   tint behind destructive confirmation

text.primary    #3A2F28   body text
text.secondary  #6A5748   secondary text
text.muted      #A58D7A   captions, placeholders (NOT body)
text.inverse    #F9F2E9   text on a raspberry fill
text.accent     #83114F   links, brand text
text.danger     #A32218

border.subtle   #DFD1C1
border.strong   #C9B7A7

accent.base     #83114F   primary buttons, brand
accent.hover    #660D3E
accent.onAccent #F9F2E9

feedback.danger   #A32218   (~6.4:1 on ivory)
feedback.success  #4E7A43   sage darkened to read (~4.3:1)
feedback.warning  #977535   gold deepened to read (~3.6:1)

priority.none   #A58D7A
priority.low    #4E7A43
priority.medium #B8860B
priority.high   #C2611F
priority.urgent #A32218
```

**Priority and feedback are a FUNCTIONAL scale, not brand colour.** Red/amber/
green must read as urgency; do not replace them with brand hues. They are tuned
to sit beside the palette (and now that raspberry is a plum, the reds no longer
risk reading as it) and to stay mutually distinguishable.

If a surface needs gold or sage as a *deliberate decorative accent* (some do more
than the kanban app), add explicit tokens rather than hardcoding — e.g.
`accent.gold #C6A15B`, `accent.goldText #795E2A`, `accent.sage #A8B89A`.

## Fixed swatch sets (labels, categories)

When users pick a colour (board labels, tags), offer a **fixed set**, never a
free picker — a free picker guarantees someone chooses something that vanishes on
ivory. A set that works: the brand raspberry `#83114F`, gold `#C6A15B`, a
darkened sage `#4E7A43`, taupe `#A58D7A`, plus clay `#A32218`, burnt orange
`#C2611F`, slate `#3E6B8A`, violet `#6B4C8A`. Keep any additions mutually
distinct (aim for ΔE > ~15) and legible on the ivory surfaces.

## The logo

Arabic calligraphy reading *Sabeel* with gold accent strokes. One asset, on the
warm-ivory canvas, no plate and no tint — a flat `tintColor` throws the gold
away. (Because the apps are light-only, no ivory-on-dark reverse mark is used.)

## Quick do / don't

- **Do** carry the base with ivory and sage; spend raspberry sparingly on the
  things that matter; garnish with gold.
- **Do** use `#3A2F28`/`#6A5748` for text and keep taupe for captions/borders.
- **Do** deepen gold (`#795E2A` text, `#977535` signal) whenever it must be read.
- **Don't** set body text in Mushroom Taupe or read-critical text in gold.
- **Don't** wash a large area in raspberry, or scatter big fields of gold.
- **Don't** add a dark theme.
- **Don't** hardcode a hex in a screen — route it through a semantic token.

## Contrast cheat-sheet (on Warm Ivory `#F6EBDD`)

| Foreground | Ratio | Verdict |
|---|---|---|
| text.primary `#3A2F28` | 11.0 | body ✓ |
| text.secondary `#6A5748` | 5.8 | body ✓ |
| accent `#83114F` | 8.3 | body ✓ |
| gold-as-text `#795E2A` | 5.2 | body ✓ |
| success `#4E7A43` | 4.3 | large/UI ✓, borderline for small body |
| danger `#A32218` | 6.4 | body ✓ |
| warning `#977535` | 3.6 | UI/large ✓, not body |
| Mushroom Taupe `#A58D7A` | 2.7 | captions/decoration only |
| Antique Gold `#C6A15B` | 2.1 | decoration only |

And ivory `#F9F2E9` on a raspberry `#83114F` fill: 8.8 ✓.
