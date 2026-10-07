# 058 — The Velox sheet's recommendations are built (display kernel, no-k picks as Fit only, cursor candidates, counts/px, windows, range readout, honest rows) and the shell gets Liquid Glass (mock A)

**Date:** 2026-10-07 · **Status:** accepted (owner: "go ahead… go with the recommendations… where is the liquid glass?") · **Amends:** 035 (shell materials only), 054 §6 (Auto ID roles), 057 §10

## Context
The morning drive of the spec-2 room on the owner's SI 1339 (`docs/archive/v5/room-drive-4-2026-10-07.md`) and the Velox 3.15
manual carved from his installer gave the 14-row sheet `docs/archive/v5/velox-parity-sheet-2026-10-07.md` (options, effort, gate,
a recommendation and an independent second opinion per row). The owner took the recommendations as a whole and asked for the
glass shell; mock A (`docs/archive/v5/shell-mocks-2026-10-07/`) was the recommended picture.

## Decisions
1. **Maps get a display kernel** (row 1a): none · 3 × 3 · 5 × 5 · σ 1 px · σ 2 px, a count-conserving box/Gaussian applied to the
   signed net map before the display clamp (`MapSmoothing` in Core, mean-preserving at the border). Display only: the raw map,
   the pooled spectra, the fit and the counts CSV are untouched; every tile and PNG name carries the kernel. Better than Velox's
   pre-filter, which feeds its quantification silently.
2. **A pick without a computed k is Fit only** (row 2c, replaces the 054 §6 deviation): with Computed k-factors, an Auto ID pick
   whose group is an L or M line lands as Fit only (Velox's deconvolution-only), so at% is computed for the K-line elements at
   once; the Found row shows each pick's net / L_D (row 2a). No renormalised at% (row 2b, Gate D, not taken).
3. **The cursor names candidates** (row 3a): tabulated α lines within ± 1 FWHM, the listed elements' sum and escape positions,
   a right-click menu that picks; **counts / px** as a Show-menu unit (row 4b); **Windows** as a Show-menu layer drawing the
   net maps' line and background windows (row 10a); **⌥-drag** reads the counts and fraction in an energy range (row 13a).
4. **Honest rows** (rows 8a, 9a): Absorption's box follows a typed thickness (no "Off" beside a tick); Info lists dispersion,
   offset and stage tilt when the file has them, nothing when not; live time waits for the reader change (its semantics are unverified). The 4D verb "Preprocess Raw Data…" is not shown in a
   spectrum-only window (row 8c, a frozen-shell file, by this acceptance).
5. **Liquid Glass on the shell** (mock A): the sidebar and the inspector as `glassEffect` panes inset from their columns over a thin
   window material (a window material alone read flat on screen), the toolbar the system's; widths
   and structure unchanged (sidebar 230, inspector 320); the centre column and the maps stay flat (HIG Materials: glass is the
   navigation layer). "Drive before more surface" is set aside for this landing by the owner's go; the open rows stay owed.
6. **Not taken now** (each its own Gate D lane later): frames trim (5a), per-pixel at% (6b), line profile (7a), segment exclusion
   (12a), apply-method (14a), EMSA export (11a, when asked).

## Consequences
Built by five Sonnet lanes on disjoint files from the seam 09473889, merged and gated as one landing, driven on SI 1339 by the
session; the sheet's rows are marked landed in place. Science registration still owed: the proposer on real Al pools (V5-8).
