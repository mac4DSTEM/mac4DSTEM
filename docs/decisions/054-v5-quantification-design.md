# 054 — v5.0 quantification and the Spectroscopy room's layout

Dates: 2026-10-05

Status: **accepted** (owner, 2026-10-05, the sheet V5-Q1…Q9 in `docs/archive/v5/owner-decisions-2026-10-05-v5.json`).
It follows the design session of ADR 053 (record: `docs/archive/v5/quant-design-2026-10-05/`).

The evidence and the independent second opinion are in `columns.md` and `second-opinion.md` of that folder. Every card
was answered as recommended.

## Decision

1. **Fit (V5-Q1).** Least squares is the named default, and Poisson maximum likelihood sits under Expert (ADR 053
   option 3). An LS-vs-ML comparison on the owner's pooled Al-Mg-Si spectra is pre-registered. The default switches to
   ML only if the gap on the Mg/Si net ratio exceeds about ½ of its counting σ. That bar is a property of these data
   (threshold rule).
2. **Background (V5-Q2).** The default is a fitted whole-spectrum empirical continuum with the Al K-edge step, like
   Velox's "Empirical". Polynomial windows sit under Expert and serve the eXSpy parity path. A physical (espm)
   continuum comes later and needs a sourced Super-X detector-efficiency curve.
   - Acceptance: the residual over 1.1–1.9 keV on a pooled matrix spectrum from the owner's files is flat within ±1.
3. **at% (V5-Q3).** at% ships, from a computed Brown-Powell k or a typed k with its source.
   - The badge `validation:"none"` shows on screen and in every export.
   - at% is computed on pooled regions only.
   - The k-free ratio is shown above it.
   - The detector efficiency is a named, sourced input.
   - No ζ option appears in the menu; ζ stays in Core for parity.
   - Bote-Salvat waits for a data-rights check. Schreiber-Wims is not planned.
4. **Energy axis (V5-Q4).** Offset, gain and width are refined on the pooled spectrum, and file vs refined is shown.
   Frame-by-frame drift tracking comes only if first-vs-last frames show drift.
5. **Comparing regions (V5-Q5).** Regions are normalised by per-pixel live time where the file has it, otherwise by the
   Al Kα internal reference. The result says which.
6. **Element identification (V5-Q6).** A proposer runs on open. Conflicts are named ("Al sum or Ar?", "Ga L from FIB?").
   One click accepts, and nothing is added silently. Each element is Quantify / Fit only / Off, and Cu defaults to
   Quantify (Q phase).
7. **The Al tail and Si internal fluorescence (V5-Q7).** The matrix pool is subtracted for enrichment, and the result is
   labelled "excess over matrix". The owner records one five-minute pure-Al spectrum on the same Super-X, which
   measures the Al Kα tail and the Si internal fluorescence once. The tail is then fitted as a component tied to Al Kα.
8. **The room's layout (V5-Q8).**
   - **Five sidebar steps:** Spectrum image · Elements & maps · Regions · Quantify · Export.
   - **Each step has its own inspector of ≤ 7 rows.** k and absorption are visible.
   - **One toolbar verb, Quantify,** which records a replay step (ADR 047). The pooled fit itself reruns live as
     settings change.
   - **Display toggles** (overlay, residual, axis) live on the canvas and the plot.
   - **Saving a method** is in the menu.
   - **Rows are costed in points in the mock** before anything is drawn.
9. **Thickness (V5-Q9).** Typed ± σ now. The EELS t/λ map from the owner's GMS run comes later; it needs a named
   mean-free-path model.
10. **Escape peaks.** Always fitted, with no control. Mg, Al and Si produce none, and the footer names the setting
    (second opinion C8; no card).

## Consequences

- V5-8 (joint scope) stays open. Everything above serves the plain spectrum image and pooling by phase or region.
- The owner owes:
  - the joint GMS run (HAADF ticked);
  - a pure-Al spectrum;
  - whether Velox stores per-pixel live time;
  - one Velox quantification of a pooled matrix spectrum (the cheapest check of the app's computed k, efficiency
    included);
  - the GMS help pages.
- Next for the sessions: the Spectroscopy room mock (from `ux-study.md` and item 8), then the room's and the eXSpy core
  port's pre-registrations (P0–P3: tables, FWHM, windows, CL, absorption, statistics).

## The mock's first review (owner, same evening)

On the first mock (`docs/archive/v5/spectroscopy-mock-2026-10-05/`):

- Element roles are set in a **periodic table** in the Elements & maps inspector, as in Velox's Periodic Table panel.
  Click toggles Quantify; right-click gives Quantify · Fit only · Off · Lines. Proposer suggestions show as marked cells.
  The map's thumbnail tiles show the role only as a symbol. (This replaces the owner's first answer, roles on the tiles.)
- **Velox is the reference for layout and interaction** (owner: "quite intuitive, we can orient ourselves by it"), except
  for two weaknesses. Auto ID never drops manual picks, and there is no "Apply to SI" step: the fit is live.
- Screen 1: map and results table side by side on top, the spectrum full width below. The explanatory text beside the
  map is cut.
- The draw tools sit in the map pane's header, and the toolbar stays as the app has it.
- Export has no second toolbar verb: an "Export…" button in the Export step, and File › Export.
- Regions stay in the sidebar.

The revised mock follows. The room is built only once the owner accepts it (ADR 035).

## Corrections from the WP3 pre-registration (session, Fable 5.1 review, 2026-10-05; owner overrules on sight)

- **Item 7, second half, is wrong.** The detector's Si internal-fluorescence peak cannot be tied to Al Kα: Al Kα
  (1.487 keV) lies below the Si K edge (1.839 keV). It is tied to the integrated counts above 1.84 keV. The Al Kα tail
  stays tied to Al Kα.
- **"Four-detector geometric average" (ADR 053 item 5) becomes "four-detector weighted transmission".** The summed
  stream's exact correction is 1/T̄ with T̄ = Σ Ω_d T_d / Σ Ω_d. The geometric mean is reported only as a comparison.
- **Item 2's Expert option is eXSpy's whole-range sixth-order polynomial** (the parity path), not Velox-style
  polynomial windows.
- **Least squares is unweighted** (hyperspy `ls`), and every result's footer says so.
- **Garwood intervals are used at every count.** The "~20 counts" switch was a threshold, and it is dropped.

Record: `docs/archive/v5/wp3-quantification-preregistration-2026-10-05.md` § Flags.

## Brown-Powell has no licence-clean source; computed k uses Bote-Salvat (session, 2026-10-05; owner overrules on sight)

- **What the research found** (Sonnet, `bp/report.md` in the session scratchpad):
  - No licence-clean, citable implementation of the Brown-Powell cross-section exists. NIST EPQ has none, xraylib has
    none, and the Velox manual names it without coefficients.
  - EPQ (public domain, 17 USC 105, commit 249dd3f8) carries Bote-Salvat 2008 (PRA 77, 042701), valid to 1 GeV, so
    Mg/Al/Si K at 200 kV is in range.
  - EPQ also carries Krause 1979 fluorescence yields and an SDD efficiency model.
- **Decision.** Computed k uses **Bote-Salvat + Krause 1979 + EPQ's efficiency model.**
  - It is labelled by name and badged unvalidated.
  - A DEVIATION note says it is not Velox's Brown-Powell default. Velox's manual says Bote-Salvat tends to underestimate
    light-element atomic fractions.
  - Typed k stays.
  - WP3's Q3, the Velox cross-check on one pooled matrix spectrum, measures the gap before any computed at% loses its
    badge.
- **Why this costs the owner's first question nothing.** Si enrichment at cell boundaries is a ratio of ratios, so k
  cancels.
