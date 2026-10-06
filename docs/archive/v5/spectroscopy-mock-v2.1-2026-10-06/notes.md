# Spectroscopy room mock v2 (2026-10-06)

Files: `mock.html` (source, `body.wide a`), `mock-b.html` (`wide b`), `mock-narrow.html`; `wide-a.png`, `wide-b.png`
(1470 × 923), `narrow.png` (915 × 923), 2× via `render.swift`. Maps and spectra are seeded placeholders.

## What changed from v1

- **Maps grid owns the content** (Velox): ColorMix spans three rows on the left; HAADF, Mg, Al, Si and the two
  proposed tiles (O, Cu, dimmed, dashed, "Accept") fill two columns beside it. Tile sizes at 1470: (a) ColorMix
  509 × 382, tiles 163 × 122; (b) ColorMix 581 × 436, tiles 187 × 140 — the grid is 51 % / 57 % of the content height.
  Mode switch int / net / wt% / at% and the rectangle / polygon tools sit in the grid header.
- **Region is a live tool** (owner's rule): one rectangle with eight handles on the ColorMix; dragging it re-pools the
  spectrum as it moves (caption "Region · 572 px · live"). No Regions list anywhere. Inspector "Region" holds
  four rows: Source (Drawn rectangle · Whole map · β″ phase pool · object pool), Pixels · counts, Compare with
  (the grey overlay on the spectrum), and **Pin** — keeps a copy of the current region as a comparison overlay and a
  results column; unpinning drops it. Draw tools stay in the map header.
- **Periodic table in the inspector**, states by fill only: mapped = accent, proposed = accent outline, fit-only =
  hollow (Fe shown), not detectable = dim; help on hover (Cu shown); no legend row.
  (a) 364-pt inspector, 18-pt cells, full 18 columns (20-pt cells would need 400 pt).
  (b) 248 pt, 21-pt cells: main group (8 columns, H–Rn) above the transition block (Sc–Hg); period 7 and the
  f-block fold into "La–Lu · Ac–Lr".
- **Sidebar**: rooms only; "EDX" under Spectroscopy, selected. Dataset facts move to the Info tab.
- Inspector order: Elements · Region · Fit · Map display · Export · Expert (collapsed ×3). Beam energy reads
  "200 kV · from the file". Spectrum strip and results table are v1's.
- Narrow: grid stacks (ColorMix full width, tiles 2 × 3), then spectrum ("Show" menu), then results; scrolls.

## Decisions still open for the owner

| # | Problem | Options | Recommendation |
|---|---|---|---|
| D1 | Inspector width for this room (ADR 035 freeze) | a) 364 pt, full table, 18-pt cells · b) 248 pt, split table, 21-pt cells | **b** — no frozen-shell change, cells larger; the split reads once seen |
| D2 | Proposed elements in the grid | a) dimmed tiles with Accept (mock) · b) no tile until accepted | **a** — the map is the evidence |
| D3 | Fresh open | a) HAADF + proposals only · b) proposals auto-mapped, unquantified | **b** |
| D4 | Pin semantics | a) overlay + results column (mock) · b) overlay only | **a** |

## Limits

Not verified against a Velox screenshot: tile proportions, default colours. Hover tooltip overprints the row above
(real app: system help). Spectrum marker labels still crowd below ~400 pt width. No app code was touched.
