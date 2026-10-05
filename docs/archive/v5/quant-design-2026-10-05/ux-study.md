# Spectroscopy room — how the vendors lay out EDX, and a proposed anatomy (lane C, Sonnet 5.5, 2026-10-05)

This is the agent's handback, condensed by the session. **It is a draft.** The room is built only against a mock the
owner accepts (ADR 035, ADR 053).

**Sources.**

- **V** = Velox 3.15 User Manual (carved text, line numbers).
- **A** = Oxford AZtec post-processing guide (Northwestern).
- **Q** = Bruker QUANTAX/ESPRIT manual.

These stay in the session scratchpad (copyright). Web sources are named inline. Gatan and HyperSpy window anatomy is
thin; no user complaints were sourced.

## How each tool works

| | Velox | AZtecTEM | ESPRIT | GMS | HyperSpy |
|---|---|---|---|---|---|
| **Anatomy** | Processing window: image display plus side panels (Periodic Table, EDS Quantification, SI Quantification, Image Browser, Experiment Log) (V:1190, 1840, 1989) | Navigator modes, palette toolbar, image / spectrum / maps / elements fields, data tree (A:130–140) | Workspaces (Spectra, Objects, Line scan, Mapping…), a Project clipboard (Q:859–890, 1464) | Elemental Quantification palette plus right-click on the spectrum (Elite T :307–310) | Navigator + signal pair; the pointer or ROI on the navigator drives the plot (web) |
| **Element ID** | Auto ID toggle (manual picks lost when toggled, V:1863–1870); states included / auto / "deconvolution only"; right-click for lines and the quant family | Candidate list on double-click; include / exclude / clear tiles (A:205–245) | Auto ID or a Finder; fixed colour per element (Q:4378, 1763) | UNVERIFIED | `add_elements`; a mini periodic table in hyperspyui |
| **Maps** | Tile per element plus a ColorMix overlay; one mode switch int / net / wt% / at% (V:1210–1231) | Tile grid with weight / colour / include; AutoLayer; TruMap, QuantMap; binning, smoothing (A:385–496) | Thumbnail bar with a checkbox into the mix; filters, normalise, deconvolution, palette mode (Q:4371–4425) | quantitative maps from SI | — |
| **Region spectrum** | Rectangle / polygon on the ColorMix gives an integrated spectrum; regions overlay on one axis (V:8127–8176, 975–993) | Point, rectangle, ellipse, freehand; compare by overlay, normalised to a peak (A:152–262) | Point, line, rectangle, ellipse, polygon; **+/– sets line width** (Q:4426–4540) | — | ROI on the navigator |
| **Fit display** | Spectrum / Background / Modelled / **Residual** (V:889–958) | Fitted and theoretical spectrum overlays | online deconvolution | — | `plot_residual` |
| **Noise** | **Counts bar:** recorded vs "optimal", with a recommended pre-filter kernel; the filters do not change the data (V:2195–2265) | binning, smoothing | filters | — | — |
| **Line profile** | Arrow with width; recommends the Spectrum Profile for statistics (V:6255–6267) | line scans | Line scan tab | — | — |
| **Save/export** | `.emd`, PNG/SVG, CSV / EMSA, Experiment Log (V:803–886, 1294) | tables, Quant Settings | Project, methods | — | `.hspy` |

ePSIC's 4D-STEM + EDX manual is an acquisition recipe only. It warns that the two streams can differ in scan shape
(e.g. [256, 255] for a flyback column). That is a linkage hazard the room must name, not silently trim.

TESCAN TENSOR markets 4D-STEM + EDX phase segmentation. No page shows a linked-cursor or pooled-spectrum UI
(UNVERIFIED that none exists).

## Table stakes: what a user looks for in the first five minutes

Each item is seen in at least two tools.

1. The sum spectrum shown at once, beside the image.
2. A periodic-table picker with Auto ID and manual include/exclude.
3. Line markers, with a K/L/M choice.
4. A map per element.
5. A mixed overlay with per-map toggle and colour.
6. A region spectrum from a drawn shape.
7. A line profile with a width.
8. Overlap handling.
9. A wt%/at% table with σ, and a map mode switch.
10. Fit and residual display.
11. Display-only smoothing that does not touch the data.
12. Export: PNG/SVG, CSV/EMSA.
13. Zoom and pan: wheel, drag, Home.
14. Multi-spectrum comparison, normalised to a peak.
15. Phase/cluster analysis of the maps.

## Weak points to avoid

- Velox drops manual element picks when Auto ID is toggled. Its quantification parameters need an explicit "Apply to
  SI".
- AZtec spreads one task over eight fields and mode switches.
- ESPRIT splits one analysis across workspaces through a clipboard.
- GMS hides functions in right-click menus.
- Every tool communicates noise by advice, except Velox's counts bar.

## What only a 4D-STEM + EDX room can do

1. **A linked cursor:** one scan pixel shows its diffraction pattern and its spectrum.
2. **Pooling over diffraction-defined regions:** a phase, grain or precipitate object becomes a reproducible region.
3. **The reverse:** an element-map region shows its mean diffraction pattern.
4. **A per-phase pooled spectrum and composition table.**
5. **A scan-shape registration guard.**

## Proposed anatomy (inside the frozen shell)

**Sidebar.** The steps are Spectrum image · Elements · Maps · Regions · Quantify · Export. Regions are listed with a
colour symbol, pixels and counts; each is drawn or comes from a phase or object.

**Content, spectrum image alone.**

- **Top:** the map canvas (the mix or the STEM reference), with a thumbnail strip of element toggles. The draw tools in
  the toolbar are point, rectangle, ellipse, polygon and line.
- **Bottom (largest):** the spectrum of the selected region, the whole map by default. Line markers, other regions
  overlaid and normalisable, the fit with a thin residual strip, and wheel/drag/Home.
- **Line profile:** a small plot that appears only when a line is drawn.

**Content, linked to a 4D scan.** Scan-space canvas with the cursor · diffraction at the cursor or region · spectrum at
the cursor or pooled. A "pool by" row (cursor / drawn / phase / object), and a notice when the two scan shapes differ.

**Inspector.** Five groups, 22 rows in all, 16 visible by default.

| Group | Rows | Contents |
|---|---|---|
| **Display** | 5, open | map mode, axis, display smoothing, overlay, residual |
| **Elements** | 4, open | Auto ID (keeps manual picks), periodic-table sheet, lines, overlap-only |
| **Fit** | 6, collapsed (expert) | background, order, windows, energy calibration, cross-section model, absorption |
| **Region** | 4, open when selected | name, source, pixels/counts, line width |
| **Quantification** | 3, collapsed | wt/at, normalise, σ |

Cut first if fewer rows are wanted: overlay, cross-section model, name.

**The toolbar verb** changes by step: Fit spectra · Pool spectra · Export.

**Defaults.** The whole map selected, Auto ID on, net counts, smoothing and residual off, Fit collapsed. That means:
open a file → see a spectrum, elements and maps → draw a region → see its spectrum, with no setup.
