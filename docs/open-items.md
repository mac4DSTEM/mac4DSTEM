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

**Nothing.** #46 was fixed on 2026-08-06 (commit `87dce1c`), and
`tools/run-tests.sh all` is green at 30 harnesses. What remains before the tag
is a QC playthrough run *with* screenshots — see **Verification debt** — and
that is a run, not a defect.

**#46 — closed.** `calibrateQFromCrystal` now refuses when
`Calibration.originFitRefusal` is non-nil, so a Q pixel size can no longer
contradict a warning the app has already issued. The predicate
(`originFitIsQuantitative`) is the single owner of that judgement and is read by
the Prepare readiness row, the calibration action, and
`tools/training-dataset-campaign`, so the badge, the app's behaviour, and the
parity records cannot disagree. Covered by `mac4DSTEMTests/
QCalibrationOriginGateTests` and `tools/calibration-readiness-test`.

> **The defect class is not fully closed, and that was a deliberate scope
> decision.** Adversarial review of the fix (2026-08-06) established that the
> threshold it inherited — `residual <= probeRadius` — is looser than the
> estimator's actual failure onset (≈2 px, set by `minimumRadiusPixels`), and
> that `.fileMean`/`.sessionMean` imports reach the same wrong number by an
> ungated route. Both need `Core/` changes, so they are recorded in
> [`docs/post-v1-ideas.md`](post-v1-ideas.md) rather than here, which keeps this
> file's no-`Core/` contract intact. #29 remains the upstream question: whether
> the residual is a fitting bug or genuine descan is still unanswered, and it
> feeds ACOM and strain too.

## Release-owner actions

Developer ID signing, notarization, and a clean-account launch. Credentials
required; nothing in the repo blocks these.

**These do not block the tag** (decided 2026-08-06). Closing out v1.0 splits in
two, and only the first half needs anything from the repo:

1. **Repo close-out** — #46 fixed, `run-tests.sh all` green, a QC playthrough
   run *with* screenshots to create the visual baseline that has never existed,
   commit, **tag `v1.0.0`**, and reset the docs (see below). Needs no
   credentials and no Apple Developer account.
2. **Distribution close-out** — Developer ID signing, notarization, stapling,
   clean-account launch. Needs paid Apple Developer Program membership. Ships
   as a later release action against the same tag; it changes no source.

**Docs reset, at the tag:** `CHANGELOG.md` is the record of what v1.0 is; this
file drops everything closed and keeps only what is live; `docs/archive/v1.0/`
stays frozen; `docs/load-pipeline-plan.md` becomes the single live plan; and
`CLAUDE.md` loses the "two threads" framing in favour of pointing at the tag.
The point is that every later bisect has a real tag to bisect against instead
of "somewhere in `main`".

## Fixed on 2026-08-06, after the #46 work

Both were found by driving the real app, not by a test — worth remembering when
deciding how much a green suite is worth.

- **The Result colormap was unreachable from Results.** The 2026-08-06 polish
  pass moved the display controls into a collapsed disclosure (right) and hid
  the whole section in the Results workspace (wrong), while the Result picker
  was gated on a result existing. The control that recolours a result was in
  every workspace *except* the one built for looking at results. Now the
  section scopes its *contents* per workspace: Results drops the pattern
  controls, which have no CBED pane to act on, and keeps the Result colormap.
  RGBA products (ACOM IPF maps) correctly show no colormap control at all,
  since a colormap is meaningless on an RGB image. Pinned by
  `SidebarLayoutTests.testDisplaySectionScopesItsContentsRatherThanHidingItself`
  — which asserts the *decision*, because the rendering cannot be asserted:
  SwiftUI builds a `Picker`'s `NSPopUpButton` menu lazily for a real assistive
  client, so in-process every pop-up reports empty titles and zero items.
- **The Origin & probe row called a measured origin "Missing".** With a fit
  residual above the probe radius the row printed **"Missing"** directly above
  its own detail line reading *"Origin: Measured in app · Probe: 5.03 px · Fit
  RMS 11.66 px (exceeds probe radius…)"* — the #46 defect class exactly, a
  label contradicting the data beside it. `CalibrationReadinessStatus` gained a
  third case, `.unusable` ("Not quantitative"), whose `isReady` stays `false`,
  so every gate and the prerequisite checklist behave identically; only the
  word changed. `.missing` is still used when the origin or probe genuinely is
  absent, and `tools/calibration-readiness-test` pins both directions.

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
