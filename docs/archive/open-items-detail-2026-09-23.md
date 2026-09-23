# Open-items detail — 2026-09-23 triage

Full original wording for live items whose entry in
[`docs/open-items.md`](../open-items.md) was compressed during the
2026-09-23 docs cleanup (903 → well under half by word count). Nothing
here is closed — these are still-open items; this file exists only so the
compression in the live file lost no wording. See `open-items.md` for the
current, shorter entry and its section.

---

## Precipitate segmentation defects — full original wording

### Contiguous invalid regions fabricate precipitates — blocks wiring

`PrecipitateSegmentation.segment()`'s non-finite guard imputes the finite median. That
survives scattered NaN and **not** a large contiguous invalid region — the shape
`Core/Analysis/StrainMapping.swift:81` actually writes. **Do not wire this engine to a
product until this is resolved.** Gate D of its own; the obvious remedy (threshold
statistics over the finite subset) silently breaks the caller-validity contract at
`PrecipitateSegmentation.swift:104-107` unless it excludes non-finite rather than invalid
pixels. Owner: whether to fix or to refuse above a bound.

### Non-finite pixels ON a feature erase it silently

Same engine, same guard, different placement — and `StrainMap.component()`
writes NaN where indexing failed, which is *on* the second phase. Marking a
needle's own pixels invalid deletes it from the result with no signal: 1 needle
marked → 5 objects, 6 marked (126 px, 0.77 % of the scan) → **0 objects**.
Worse at partial coverage: 7 invalid pixels (0.04 %) leave a reassuring count
of 6 while one needle reads **21.6 px instead of 8.2** — wrong by 2.6x. No
imputation strategy recovers this; the information is gone from the input. The
honest fix is to report the imputed count, not to hide it. Owner: report or
refuse.

### The robust-sigma constant and the fill statistic are unpinned

Pre-existing, inherited with the port, found by Gate B. `1.4826 * mad`
(`PrecipitateSegmentation.swift:305`) can be changed to `3.0 * mad` — a +102 %
error in the constant that gives `Settings.thresholdSigmas` its documented
meaning — with every test green, moving mask footprints **-22 %**,
`meanIntensity` **-36 %** and one object's orientation by **23°**. Separately
`medianOf(finite)` can become the arithmetic mean with every test green. Both
are one-token mutants. Fix: one fixture asserting `robustThreshold` lands near
`median + 3 x sigma_known` on known Gaussian noise, and one assertion that
distinguishes median from mean. Not blocking — the engine is unwired.

### Dark-contrast ridges register through their flanks

Found by the 2026-09-14 audit (an independent reader; script not retained).
`ridgeMeasure` (`PrecipitateSegmentation.swift`) keeps only the negative
Hessian eigenvalue and its comment says a dark ridge "never registers". A
dark stripe's smoothed cross-section has two negative-curvature shoulders,
which DO register and close into one ring-shaped object: a −200 dark 40 × 30
stripe on a bright field, `.needles`, gave one object with the right centroid
and `lengthPx` 53.96, `widthPx` 45.0 — the flank spacing, not the stripe.
Every needle fixture in `PrecipitateTests` is bright. Owner: decide whether
dark contrast is in scope; if it is, the measure needs the sign made explicit
and a dark fixture. Not blocking — unwired.

### A negative peak collapses an object to 1 × 1, and NaN next to a maximum passes

Same audit, both unreproduced through the public surface. `PrecipitateSegmentation`
takes `half = 0.5 × peak` for the length/width extent; with `peak < 0` no
member clears it and the object ships as `lengthPx = widthPx = 1`, silently.
`.needles` drops it on the length floor; `.particles` has none. Reaching it
needs a component whose maximum is negative, which the threshold seems to
prevent unless `thresholdSigmas ≤ 0`, which nothing validates. And
`PrecipitateReflections.find` checks `isFinite` on the candidate only; a NaN
neighbour compares false, so a pixel beside a dead detector pixel can be a
local maximum. No fixture holds a NaN in the max pattern. Not blocking.

---

## Other named science/presentation residuals — full original wording

### The Al-Mg-Si cube's peak set is not clean enough — added 2026-09-12

**Science.** On `060_STEM SI_…bin_4`, only **39 %** of detected vectors are
explained by the best-fitting Al orientation at one-pixel tolerance, on a
specimen whose matrix is aluminium. Measured by `tools/phase-map-probe` with a
synthetic 2.5 px kernel and default spacing on a 4×-binned 64 px detector, so
this is a statement about the DETECTION, not the matcher. The app's own path —
a measured probe kernel, a fitted origin map, the ellipse — is what the probe
skips. Evidence: `docs/archive/v3/phase-mapping-2026-09-12.md` §"Step 4".
Not blocking: the matcher refuses (99.0 % "not indexed") rather than inventing.

### The β″ zone axis for ⟨110⟩Al data is not chosen — added 2026-09-12

**Known, scoped.** β″ is coherent along its b-axis with a ⟨100⟩Al direction, so
with the beam on ⟨110⟩Al — which is where this cube sits, measured — no variant
is viewed down its needle axis and a [010]β″ library cannot match. Which β″
zone axes a ⟨110⟩Al beam DOES present is a crystallographic question nobody has
answered here; until it is, the UI lets the user type one and the method
refuses when it is wrong, which is the correct behaviour but not the answer.

### The ellipse "Fit anyway" mark: what it does not yet do — added 2026-09-15

**Known, scoped.** The flag the owner asked for landed 2026-09-15 behind an explicit "Fit
Anyway" button. **The mark does not survive a session round trip.** `PixelCalibration`
carries a/b/θ and nothing else, so a restored fit-anyway ellipse reads "From session". The
sidecar wire format is the owner's (plan §8); a field there is a format decision, not a fix.

### A challenged matrix verdict is drawn like one by exclusion — added 2026-09-15

**Presentation, live; the science is closed.** A position the matrix takes back through `classify`
step 5 gets the same neutral grey as one where removal left too little to
index, and `PhaseMap.phaseCounts` cannot separate the two. The evidence line
does distinguish them; nothing else does. The demo cube's matrix fraction moves
51 % → 74 % because of it, which is correct but unexplained on screen. Owner:
presentation only, so no Gate D.

### "Computed this session" reports what EXISTS, not what was computed (2026-09-11)

This is what the owner actually reported. The two rows are bare predicates —
`product("Origin calibration", done: ...calibration.hasFittedOrigin)` and
`done: ...hasRotation` (`WorkspaceInspector.swift:563-565`) — so a session
restored from a sidecar shows both green having computed nothing. The owner's
session WAS restored (the sidecar reproduces his 9.72 px and 3.74 px exactly),
so his green ticks were restored, not computed, and the tick went grey because
the origin was cleared, not because a computation was undone. The label is the
defect. Owner: presentation only, neither Gate D trigger applies.

### CIF import can silently accept a wrong crystal (2026-09-01)

(a) A non-P1 declaration with a PARTIAL ops list still imports the wrong
cell (`verifyFamily` can pass it — Gate B refuter escape E2, 2026-09-01,
recorded not fixed; the missing/identity-only case is guarded). Trap: needs
a 230-entry IT-number→group-order table the importer deliberately lacks —
cheap mitigation, new scope. (b) closed 2026-09-05: the ACOM recipe step
records `material_fingerprint` (`CrystalModel.contentFingerprint`, FNV-1a
over cell, symmetry and basis) for imported models and `resolveMaterial`
refuses by name when the session's same-named import differs; pre-key
records still resolve by membership (`ReplayPlanTests`, `CIFImportTests`).
Owner: (a) unclaimed, Gate B when picked up.

---

## `PaneSplit` and the constraint-loop crash — full original wording

### The constraint-loop crash: nothing in a split may change its own minimum (2026-09-04)

**The rule, demonstrated 2026-09-04: nothing inside a split's hosted content
may repeatedly change its own minimum size.** Two sites, both in the status
bar, both fixed. Full diagnosis and the refuted `HSplitView` conjunction: commits `e608dbd`, `27de9bb`; the
S17 record is archived. Residuals: n=1 each way against a fault once called intermittent; the
inspector's Performance rows still tick per second. Owner: unclaimed.
**2026-09-22 night:** one crash of this class (`_crashOnException` in `updateConstraintsForSubtree`, a scratch build, 3 s after launch) after the Gate D fix made the strip's glance/run slots compressible without a constant minimum; NOT reproduced (12 resizes, 6 launches). The slots now carry a constant min/ideal/max (`LayoutPolicy.compressibleSlotMinimum`), the rule's shape. A different pre-session abort (20:26, owner's build) is undiagnosed.

### `PaneSplit` residuals from the refuter (2026-09-04)

(a) header overflow and (c) the divider resetting to centre are closed and
were seen on screen 2026-09-07 (`shots-c3/a3b-narrow.png`, `a4b-divider-back.png`).
(b) **The image floor lapses below 2× itself**: the fraction saturates at 0.5 under ~360 pt of usable
width, and UI declares no detail-column minimum where the retired AppKit UI
had `SplitViewPolicy.detailMinimum` = 360. SwiftUI offers no detail-column
minimum short of the window's own floor, and announcing one from inside the
split is the constraint-loop shape; recorded, not made. Owner: with the
owner's drive (C3).
