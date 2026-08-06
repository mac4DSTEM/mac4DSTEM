# Open items

Everything still live after **v1.0.0** (tagged 2026-08-06).

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

## Decisions owed before phase 2 starts

- **[`docs/v2-planning-draft.md`](v2-planning-draft.md)** — proposals awaiting a
  planning session: version policy, the two-track testing split, the
  two-dataset default, and the per-stage `AppState` rule. Draft, not decided.
- **`docs/load-pipeline-plan.md` §7 — is a cropped/binned cube a *view* of the
  original, or a new dataset?** The plan recommends *view* and is written for
  it, but it is unconfirmed. **L3 cannot start cleanly without the answer**: it
  determines session-restore and export behaviour, and reversing it later is
  expensive.

## Release-owner actions

Developer ID signing, notarization, and a clean-account launch. Credentials
required; **nothing in the repo blocks these**, and they change no source — they
ship as a later release action against the `v1.0.0` tag.

## Verification debt

- **No visual QC baseline — and v1.0.0 shipped without one.** Every playthrough
  run to date used `--no-screenshots`, so the acceptance evidence for the tag is
  numeric only: the numbers the app reports through its own controls, never what
  it draws. Running it with screenshots was considered at the tag on 2026-08-06
  and **deliberately skipped**; this is a recorded decision, not an oversight,
  and `CHANGELOG.md` says so in the release entry too. A baseline needs Screen
  Recording granted to the ad-hoc-signed test runner — see #45 for why the
  shell's own grant does not cover it, and for the two-permission trap.
  Until it exists, any claim that a UI change "looks right" rests on someone
  having looked. Two defects fixed on the day of the tag — the unreachable
  Result colormap and the readiness row calling a measured origin "Missing" —
  were both found by hand, on screen, by a person driving the app, while the
  full 30-harness suite was green.
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
4. **Open the app.** On the day of the tag, with all 30 harnesses green, ten
   minutes of driving the real app produced two defects the suite could not see:
   a colormap control missing from the only workspace that needed it, and a
   readiness row contradicting its own detail line. Neither is exotic; both are
   invisible to a test that never looks at the screen.
5. **A test written for your own fix proves nothing until it fails without it.**
   Standard practice here for science changes, and it paid off in the UI layer
   too: the first colormap test failed against the fix *and* against the old
   code, and only became useful once it was made to report what it could
   actually see. Which was nothing — SwiftUI builds a `Picker`'s menu lazily for
   a real assistive client, so in-process every pop-up is blank. The test now
   asserts the *decision* instead of the rendering, and says why at the call
   site so the dead end is not rediscovered.
