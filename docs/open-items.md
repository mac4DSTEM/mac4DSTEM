# Open items

Everything still live at the close of the v1.0 development phase, 2026-08-06.

> **Active feature work is planned separately** in
> [`docs/load-pipeline-plan.md`](load-pipeline-plan.md) — load progress, a
> resident in-memory cube, crop/bin on open. It is kept out of this file on
> purpose: every item here is UI/workflow-only and touches no `Core/`, which is
> what makes this list safe to hand out as implementation prompts. Two items
> below are claimed by that plan and are noted where they appear (**#36** —
> now fixed by stage L1 — and **#37**).

Closed items are not here — the full v1.0 record is
[`docs/archive/v1.0/ui-workflow-backlog.md`](archive/v1.0/ui-workflow-backlog.md),
kept as history. Cited numbers are prefixed `#` and refer to that file.

## Blocking the v1.0 tag

**#46 — Q calibration is stamped "Measured in app" from an unusable origin.**
On `downsample_Si_SiGe_exp` the origin fit residual is **11.66 px against a
5.03 px probe radius**, which the app already flags *"exceeds probe radius;
recalibrate before quantitative use"*. `calibrateQFromCrystal` runs anyway and
labels the result `.measuredInApp`. The Q pixel size comes out **2.56× too
large** (0.0548359 against ≈0.02140 Å⁻¹/px) and that label — not the warning —
is what travels into export, reopen and the QC log.

- Likely fix: gate on the origin readiness the checklist already computes, or
  carry a degraded provenance. Small; does not touch the estimator.
- **Do not** replace the estimator with nearest-neighbour spacing. That was
  tried on 2026-08-06, passed a purpose-built suite, and was refuted: it breaks
  `tools/strain-test` (single-peak patterns), and it collapses on superimposed
  lattices with Q errors up to +176%. The full refutation is in #46.
- Upstream and larger: **#29** established on 2026-08-05 that the same residual
  is why Bragg-vector maps sometimes look smeared, and that `Plane` may not
  follow the descan on a 200×50 scan. A measured probe kernel via
  **Use Current CBED / ROI** gave RMS 1.46 px. Whether the residual is a fitting
  bug or genuine descan is still unanswered, and it feeds ACOM and strain too.

## Release-owner actions

Developer ID signing, notarization, and a clean-account launch. Credentials
required; nothing in the repo blocks these.

## Verification debt

- **No visual QC baseline.** The 2026-08-06 acceptance runs used
  `--no-screenshots` and prove the numbers only. A visual baseline needs Screen
  Recording granted to the ad-hoc-signed test runner — see #45 for why the
  shell's own grant does not cover it, and for the two-permission trap.
- **`tools/bragg-spacing-probe/` gates nothing** and cannot: it needs a
  gitignored multi-gigabyte datacube. It stays a diagnostic.
- **The QC harness can read a stale peak count.** On `polycrystal_2D_WS2`,
  step 4 logged 16,384 peaks while the app's own status later read 213,441.

## Known, scoped, not blocking

- **#17a — aspect-aware pane arrangement.** Built, then reverted on sight
  2026-08-05. Needs a design decision, not an implementation.
- ~~**#36 — no progress indication while a datacube loads.**~~ **Fixed
  2026-08-06** by `load-pipeline-plan.md` stage L1, and **confirmed on the real
  app** on a 3.96 GB cube (patterns and MB both counting, bar advancing).
- **#37 — cancelling the virtual detector takes a long time.** *Re-measure
  after L2 (resident cube) — residency changes this problem entirely.*
- **#38 — the image panes' scroll monitor consumes every scroll in the window.**
- **#43 — the acceptance gate breaks if a session is saved for a training
  dataset.**
- **#31 — `validationIssues` is O(n²) and runs in a SwiftUI view body.**
- **#32 — `isSymmetry`'s bijection check has no fixture coverage**, and its
  stated counterexample does not exercise it.
- **#30 — origin calibration over a NAS runs at ~3 MB/s.** Investigation.
- **#11 — no WS₂ crystal model.** Scope question; `polycrystal_2D_WS2` cannot
  reach ACOM without one.
- **#18 — the campaign cannot reproduce the app's strain result on Si_SiGe.**
  Test-harness gap.
- **#15, #19, #20** — open measurement questions, low priority.

## Code hygiene

- **22 `.fixedSize(horizontal: false, vertical: true)` sites remain in `UI/`**,
  including 4 in `TaskPrerequisiteChecklist` — the construct that caused #16.
  Safe today and covered by `SplitViewHeightTests`, but unaudited.
- **A saved sidebar divider can restore below the declared minimum.** Observed
  144pt against `ContentView`'s declared `min: 250`. Every string wraps harder
  there than the layout was designed for. Test harnesses pin the width
  explicitly (`pinSidebarWidth`); the app does not.

## Working methods that earned their keep

Kept because they changed outcomes, not because they are tidy:

1. **Cost a UI change before designing it.** `SidebarDensityMeasurementTests`
   turned "it feels crowded" into 63pt of workspace rows and a 332pt shape
   change, and made the choice between options a measurement rather than taste.
2. **Adversarially review anything touching the science, and review the
   *diagnosis*, not just the code.** Twice now — 2026-08-05 and 2026-08-06 — a
   fix passed every test written for it, including one verified to fail without
   it, and was still wrong. Both times the refuting evidence was already in a
   log nobody had re-read.
3. **Never widen a gate that fails silently.** The QC harness's miss paths call
   `recordError` and continue; a control hidden behind a disclosure turns a
   failure into a finding nobody reads. Both are documented at the call sites.
