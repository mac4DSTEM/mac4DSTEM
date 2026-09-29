# Open items — the 2026-09-29 night consolidation's removed text (verbatim)

What this is: the text `docs/open-items.md` shed in the 2026-09-29 night consolidation (521 → 377 lines), copied
verbatim from the file as it stood at `c436c41` and grouped under the original headings. For each block a one-line note says why
it is here: **closed (evidence)**, **superseded by <entry>**, or **trimmed from <entry>** (the whole original entry is given, so
nothing trimmed is lost; the live file carries the same findings in fewer lines). Line numbers and paths inside the blocks are
as they were on that date, not re-verified, except where a note says a citation moved. The blocks contain nothing newer than
that text; the notes carry the 2026-09-29 night re-grep findings.


---

## Header (original lines 1–20)

> trimmed from the header: the enumeration of older archive files; the live header points to the archive folder and this file. (Shown in a fence so its heading does not nest.)

```markdown
# Open items

Live defects, debts, owed runs and open questions only — status is
`docs/status.md`, history is `docs/archive/`. Four lanes (owner, 2026-09-03):
**Science** items are taken one at a time in the order the status handoff
names, carry no release number, and a landed change to a scientific output
cuts a release; **Verification debt** closes when its run happens; **Known,
scoped** items and the owner's bug reports ship in the next patch;
**Code hygiene** rides with the session that touches its file. Each entry is
≤ 12 lines and dated: what is wrong, the pinning evidence, the trap, the
owner. No narrative. Closed items move to
[`docs/archive/closed-items-2026-09.md`](archive/closed-items-2026-09.md); the
file before the 2026-09-07 trim is verbatim in
[`docs/archive/open-items-2026-09-07.md`](archive/open-items-2026-09-07.md),
the 2026-09-02 pre-cull file beside it. Long narrative compressed out of this
file on 2026-09-23 is in
[`docs/archive/open-items-detail-2026-09-23.md`](archive/open-items-detail-2026-09-23.md);
earlier detail files are `archive/open-items-detail-2026-09-18.md` and
`archive/v3/open-items-detail-2026-09-16.md`. The merged UI-findings list is
[`docs/archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md) §3 — point there.
```


---

## Science & parity

> trimmed from "Origin validity mask landed 2026-09-17 …"

### Origin validity mask landed 2026-09-17 (disclosure + D4 count); overlay owed, still `validation:"none"`
`OriginMaps.originValidity: [Bool]?` carries the robust trim's per-position
`kept` mask (disclosure only, no fitted number moves; ADR 033). D4 count
landed (`PrepareSettings.positionsUsedValue`, unit-tested) but **unverified
on screen**. Step-3 trim-sweep PASSED on 4 cubes: excluded 0.6–15.7 %,
`maxGap` 1–5 — two cubes exclude alike but differ spatially. **Owed:** the
spatial validity overlay (origin fit over the scan grid, excluded positions
greyed via `DisplayedProduct.validityMask`) is a larger follow-on, not
built. Owner: unclaimed. Detail: `archive/open-items-detail-2026-09-18.md`.

> trimmed from "Parallax and ptychography are unrunnable …"; the owed drive is now also stated here by merging the Scope clean-up follow-up (see Code hygiene).

### Parallax and ptychography are unrunnable on the owner's Mac — release-notes item
8–11 GB of working set for a 268 MB cube is a 30–40× ratio; nobody has
checked whether that is the algorithm's true cost or an over-estimate that
refuses work the machine could do. That is a Gate D of its own (a number
governs whether a feature runs at all), not a tuning knob to raise.
Consequence: both features ship **undriven on real data** and must be
described that way in release notes. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

> trimmed from "Phase mapping runs on an uncalibrated cube and says nothing"

### Phase mapping runs on an uncalibrated cube and says nothing — owner's drive, 2026-09-24
`datasetA_stride3.h5` carries no calibration; Map Phases ran with Q unset (scale bars "20 px",
the px fallback at `ImagePanes.swift:298`) and returned 29 241 / 29 241 not indexed, every phase 0;
Find Matrix Zone Axis reported "at chance". Setting Q 0,1904 nm⁻¹ and re-running Map Phases (no
re-detection) gave T1 3680 / θ′ 833 / matrix 22 068 / not indexed 2660. Owner: "add this later" —
refuse, or say why, when Q is uncalibrated. The stale zone-axis list also survives a calibration change.

> trimmed from "Diffraction groups in a Debug build …"; the Scope clean-up follow-up (profile diffraction groups) is merged into it.

### Diffraction groups in a Debug build — fixed 2026-09-28 (three Gate Ds); one test gap
Covariance, embed and projection moved to Accelerate (`archive/v4/embedding-*-gateD-2026-09-28.md`); 1 000 patterns at
32 × 32 in Debug: 90.7 → 1.02 s. **Gap:** no shipped test reaches the two-pass path (cube cache > 512 MB).

> trimmed from "Phase mapping's matrix verdict is by exclusion …"; citation `PhaseVectorMatching.swift:769-773` re-grepped 2026-09-29: `minimumVectors` is `:73` (default) and `:882` (applied), the flag `:182`.

### Phase mapping's matrix verdict is by exclusion, and the cross-phase winner ignores completeness — MEASURED, unwired candidate parked
`PhaseVectorMatching.swift:769-773`'s `minimumVectors` is 2, so a position is
called matrix when almost nothing survives removal — never because the
matrix entry explains the pattern. The best entry per phase is chosen by
mean distance alone, so a sparse precise match outranks a dense one, across
phases too (Gate B 2026-09-15: 0.004 two-vector beats 0.012 ten-vector).
A count-aware candidate (`PhaseVectorSettings.completenessAwareCrossPhaseRanking`,
off by default) is byte-identical on the demo cube with the flag on or off —
no regression, not yet an improvement; Thronsen isn't a valid second
measurement (T1 reference already known wrong). Step 3 stride-3 sits outside
every threshold tried (98.26 % shipped defaults; 26.2–26.4 % at 1–10 %
thresholds). Gate D before any edit on either the exclusion rule or the
ranking. Owner: unclaimed.
Detail: `archive/v3/step3-2026-09-16.md`, `archive/v3/open-items-detail-2026-09-16.md`.

> trimmed from "T1 [0 -4 1] not-indexed pairs are detection noise …"

### T1 [0 -4 1] not-indexed pairs are detection noise, not origin or reference — measured 2026-09-17/21, lever choice owed
Resolved by direct measurement: the 252 not-indexed T1 positions each leave
one real {200} Friedel pair sitting 2.5–5.2° off antiparallel, so
`containsFriedelPair` returns false; a per-position origin recovers only 10 %
of them (per-peak centroid noise on weak spots, not a common-mode origin
error). What was actually missing (measured 2026-09-21) were the weak
{014}/{214} families under the 5 % intensity floor. py4DSTEM's own ACOM
labels 100 % of these positions Al — validates the matrix-removal design,
not a lever. Remaining levers, each its own Gate D: better centroiding,
loosen the pair-antiparallel tolerance (recovers ~half, raises Al-false-
positive cost), or accept detection-limited recall.
Owner: which lever, if any. Detail: `archive/open-items-detail-2026-09-18.md`.

> trimmed from "ACOM / zone-axis science residuals — four measured gaps". The third bullet (py4DSTEM's `power_radial` absent, no DEVIATION note) is **closed (evidence)**: `mac4DSTEM/Core/Crystal/OrientationPlan.swift:212-229` carries the DEVIATION note and the 2026-09-15 measurement; the live entry keeps one line and is retitled "three measured gaps".

### ACOM / zone-axis science residuals — four measured gaps, no fix attempted
- **Zone axis up to 12.8° beyond the bank's own sampling** (MEASURED
  2026-09-15): winner outscores the truth by 0.6–10 %, worst on ⟨122⟩. Next
  experiment: dump the winner's and the true axis's templates for one
  failing case.
- **26 of 200 templates fail to recover themselves at an off-grid rotation**
  (added 2026-09-14), by 1.7–9.3°; 0/200 fail on-grid. Two hypotheses
  already spent; Gate D owed before any change.
- **py4DSTEM's `power_radial` is absent, no DEVIATION note** (added
  2026-09-14): up-weights the outer rings the item above is about.
- **The rotation null's power drops at the highest noise**: 3/12 refused at
  sd 0.05 vs 0/60 shuffle null; the demo cube's own noise level (sd≈0.010)
  is certified only 2/60 — "measured −67.5°" recurs about once in thirty.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

> trimmed from "Origin-fit and Q-calibration open holes"

### Origin-fit and Q-calibration open holes
- **Origin gate has two unresolved holes** (2026-09-05): which statistic
  gates `originFitIsSane` (full-scan RMS can't see bias; the robust residual
  tried 2026-08-28 passes a 15 px-displaced fit); the trimmed fit is blind
  to spatially clustered contamination ≥ 50 % (a 40 px-off quarter gives
  100 % kept, 20.6 px error). Owner: a design pass, `docs/q-calibration-design.md`.
- **The coarse block seed lands on the wrong blob on noisy cubes**
  (Gate B refuter, `q-calibration-design.md` §9): 28/169, 29/195, 2/169 of
  three real cubes miss by >1 px against a Gaussian-argmax seed; the plane
  fit's trimming hides most of it. Owner: a design pass before the holes
  above, which it would move.
- **Reference-shell pick has no l-filter**: on 2H-WS₂ it selects (0002),
  invisible on a [0001]-zone specimen — predicted mis-scale 2.26×, silent,
  and correlation-score-based rescue doesn't work (score halves, reliability
  rises). Owner: its own design pass.

> trimmed from "Other named science/presentation residuals", which was split in two (science / presentation and trust) so each entry is ≤ 12 lines. Only wording change: the single-slice ptychography guard's citation `ResultExport.swift:1627` vs `:1478` no longer exists (the file is 1 597 lines; the guard is now at `:1506`). Heading and pointer line as they were:

### Other named science/presentation residuals
One line each; full wording `archive/v4/open-items-detail-2026-09-25.md` (earlier: `archive/open-items-detail-2026-09-23.md`).

> ...and the line whose citation moved:

- Single-slice ptychography export guard may miss its mode (`ResultExport.swift:1627` vs `:1478`) — Gate D.


---

## Data, IO & sessions

> trimmed from "An emptied manual Q field, confirmed, discards the file's calibration"

### An emptied manual Q field, confirmed, discards the file's calibration (2026-09-07)
Agent drive (`drive/shots-c3/b2-qr-unset-bug.png`): on a cube with Q pixel
scale green "From file", typing `0.2` into Prepare's Manual field entered
nothing (this locale wants `0,2`; the period was dropped silently), and
Return on the now-empty field flipped the row to "Not set" and the scale
bar from `0.5 Å⁻¹` to `5 px`. `0,25` typed afterward worked live. Two
things to establish before a fix (Gate D): why a period is rejected rather
than parsed, and whether an empty manual entry should clear the file value
or restore it. Owner: `/diagnose`.

> trimmed from "HDF5 runs under one lock …"

### HDF5 runs under one lock — what that still costs (fixed 2026-09-15 late night)
Costs: a caller blocks its thread for the length of one operation (a
sidecar write can be seconds); the two `dlopen`s stay two; no unit test can
crash-test this, the probe is diagnostic. The "refuse a second open" guard
stays as belt and braces. **Residual:** thread-safety is still asserted by
one 2026-08-19 `nm` inspection; `H5is_library_threadsafe` is still called
nowhere.

> trimmed from "resultexport-split and braggvector-emd-writer-split …"

### resultexport-split and braggvector-emd-writer-split — both prepared and parked, Gate B support owed
`Support/ResultExport.swift` and `Core/Data/BraggVectorEMDWriter.swift` are
the two largest wire-format-risk files. One zero-behaviour-risk extraction
landed on each (`+Rendering.swift` byte-identical diff; `BraggVectorEMDTypes.swift`
byte-identical diff, both harness-verified). **Parked:** the actual
HDF5-adjacent split — four candidate files on the ResultExport side
(`sessionPixelCalibration` must stay single-sourced), and the writer's
`H5Fcreate`/`H5Dwrite` logic itself, dataset-kind by dataset-kind, each new
file `nonisolated`-verified by a cold app build.
Owner: assign a session with Gate B support, or authorize continuing with a
refuter. Detail: `archive/open-items-detail-2026-09-18.md`.

> trimmed from "The sidecar reader has D003's missing attribute-length guard too"; re-grepped 2026-09-29: `H5Reader.swift` now guards (`elementCount(spaceID:) == 1`, `:897/:949/:965`), the writer-side `readStringAttribute` (`BraggVectorEMDWriter.swift:2453`) does not, so the entry stays live.

### The sidecar reader has D003's missing attribute-length guard too (2026-09-09)
`BraggVectorEMDWriter.swift`'s attribute reads share D003's defect in
`H5Reader.swift`: `H5Aread` assumes a scalar without checking file type or
extent (measured: 24 bytes into 8; 32 into 9). Same three-line fix
(`H5Aget_space` + `elementCount(spaceID:) == 1`). Owner: a patch session.

> trimmed from "Scan-fastest DM4 detector pair may be transposed"

### Scan-fastest DM4 detector pair may be transposed (2026-09-05)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps tags as `[Rx,
Ry, Qy, Qx]`, giving a pattern 480×448. A transposed pattern silently flips
strain axes and R–Q rotation. Owed: the owner reads width/height in GMS —
if 448 wide, flip `DM4Reader.scanFastestStrides` and pin an ncempy checksum.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

> trimmed from "Load/promote/replay trust residuals". Two edits: the `datasetLoadCancellation` field no longer exists (now `DatasetSession.loadCancellation`, cleared unconditionally in `DatasetSession.finishLoading()`, `Session/DatasetSession.swift:104` — defect still live); the sentence "`TiledDiskDetection.detectAll` still stages each tile into a fresh `MTLBuffer`" is **superseded by** "Tiled GPU memory: classical detection fixed 2026-09-29 (A1) …" (a pool per tile).

### Load/promote/replay trust residuals
- **Fabricated provenance on pre-2026-08-18 sidecars**: `AppState.swift:2854,2867`
  do `snapshot.loadSpecification ?? .fullExtent`, asserting full-extent for
  an unknown-era crop. Reproducer needs a synthesised sidecar. Unowned.
- **The open/promote unwind is sixfold, Cancel can vanish mid-load**:
  `finishDatasetLoading` unconditionally nils `datasetLoadCancellation` —
  with two loads in flight the first tail to finish disarms Cancel for the
  second. No fixture exercises this. Owner: whichever session next touches
  any of the six.
- **Promote/replay residuals**: (a) should promote carry scan position, or
  land at (0,0)? (b) fitted origin maps refuse the full-extent restore's
  shape check, expected but unexplained; (c) parallax/ptychography
  deliberately not in the replay record; (d) a user analysis mid-replay
  steals Cancel; (e) per-kind replay contracts live in three places held
  together by tests, not structure.
- **Recent failure leaves Reopen dead-ended**: `openRecent`'s failure path
  drops a dead entry but "Reopen" still dead-ends in "No recoverable
  dataset." (The separate multi-window recents clobber WAS fixed 2026-09-21,
  sharing one `RecentDatasets` owner.) Owner: unclaimed.
- **Resident/streaming residuals**: `releaseResident()`'s "freed" claim is a
  derived byte count, never measured — a leaked `MTLBuffer` is invisible to
  every test. `TiledDiskDetection.detectAll` still stages each tile into a
  fresh `MTLBuffer`. Resident cancellation is 2.5× coarser than streaming —
  academic until something requests `.resident`, which nothing does today.


---

## UI & on-screen

> trimmed from "The panel overlap — a transient blank/black window …"

### The panel overlap — a transient blank/black window, not diagnosed, parked 2026-09-22
Driven live on `datasetA_stride3.h5` (171×171, 29,241 positions): twice, a
screenshot during a calibration busy→idle toolbar transition showed the
whole app window blank (menu bar only, no chrome/panes) for ~1 s before
recovering on its own; a click issued during the blank state still reached
the app (one action ran twice from what looked like one click). Not a
`.zIndex`/`.offset` stacking bug (grepped, nothing found); the leading guess
— ADR 035's ideal-width budget recomputing on every toolbar change — was
independently *deleted* the same night (the floor is now a fixed derived
constant), but not re-tested on a real cube, so this stays open rather than
closed by that change. **2026-09-22 night:** the owner has not seen it
recur across the rebuild's drives (`413bcdc`). Not diagnosed, not fixed.
Owner: reopen with a screen recording if it returns; `WorkspaceView.swift`/
`ContentView.swift` are Frozen Shell regardless.

> trimmed from "View state has four owners …"

### View state has four owners, and three Frozen Shell residuals sit behind it — code hygiene
Confirmed still current (2026-09-23 grep): 26 `@SceneStorage`/`@AppStorage`
sites across `UI/`, including `WorkspaceInspector.swift:50`'s
`@AppStorage("ui2.inspectorTab")` — a relic of the deleted UI2, not renamed
because the file is Frozen Shell (ADR 035). Two other Frozen Shell residuals
sit behind the same wall: **`PhaseSettings.swift` → `ReconstructSettings.swift`**
(still unrenamed; its only call site, `WorkspaceInspector.swift:199`, is
frozen) and **the Info tab has no "Unvalidated" badge**
(`ProductInfoSections`, `WorkspaceInspector.swift:570`, confirmed still has
no per-room branching — a `validation:"none"` product reaches Info as one
more alphabetized Provenance row while Settings shows a styled orange
warning). `WorkspaceNavigation` (104 lines) is the declared truth but does
not yet own all 26 sites. Rides with the first Frozen Shell exception or
the next room conversion. Owner: unclaimed.

> trimmed from "Inspector kit gaps"

### Inspector kit gaps — confirmed still open 2026-09-23
`UI/InspectorRows.swift` has no adaptive `Menu` (Add Phase stays hand-rolled)
and no warning-note variant — `InspectorNote` is a plain secondary caption;
orange captions and unvalidated badges stay hand-rolled and must not change
shape. Long labels ("Measured kernel mode") wrap beside wide pickers —
wording is the owner's call. Scoped work, not bugs.

> trimmed from "Cosmetic parallax-completeness disagreement"; citations re-grepped 2026-09-29: `WorkspaceView.swift:304`, `AppState.swift:1187`, `parallaxStage4IsComplete` at `PhaseSettings.swift:271`.

### Cosmetic parallax-completeness disagreement, confirmed still present (2026-09-23)
Fixing `parallaxStage4IsComplete` made the checklist checkmark more correct
but exposed two independent, un-refactored "is parallax done" checks still
reading `parallaxSubpixel` alone: `WorkspaceView.swift:309` and
`AppState.swift:1236`. Cosmetic (the dispatcher's own gate is independent
and correct) but real; `WorkspaceView.swift`'s half is Frozen Shell, so
`AppState.swift`'s half was left matching rather than diverging further.
Owner: unclaimed.


---

## Release, CI & process

> trimmed from "GitHub CI's unit job is paused …"

### GitHub CI's unit job is paused until a macOS 27 runner exists (ADR 040, 2026-09-28)
**2026-09-23:** the macOS 27 deployment floor (v4.0.0) makes the `macos-26`
runner unable to build the app at all (target above its SDK) — CI needs a
macOS 27 runner image. **2026-09-28:** paused (`if: false` in `ci.yml`), to be restored on such an image. Before that: the runner's Xcode 26.6
type checker timed out on `ContentView`'s file-importer closure while the
owner's Xcode 27.0 compiled it fine; three `main` runs failed unread. Every
green gate in `status.md` is a LOCAL run on Xcode 27.

> trimmed from "The learned-detector parity fixture is a same-runtime claim …"

### The learned-detector parity fixture is a same-runtime claim; CI has no Neural Engine (2026-09-14)
`testLearnedPathMatchesPythonReference` failed on both runner jobs, passed
locally. Now skips (stated) where no Neural Engine is listed; the 98 % bars
were NOT loosened. A CPU-written second fixture would turn the skip back
into a check. Owner: whether CI should verify this.

> merged into "Acceptance-harness gaps …" (first bullet)

### A red real-data gate names the symptom, not the cause; only one harness reaches it (2026-09-08/09)
`compare.py`'s `fail()` raises `SystemExit` at the first mismatch, hiding
later ones — confirmed by the Gate D refuter, cheap fix (collect every
mismatch). Separately, `real-data-acceptance/run.sh` is the only harness
`all` reaches; `scientific` stayed green three days past a real regression
in 2026-09-05 (`ba6360d`), 43 commits before symptom. Uncosted options: add
the harness to `scientific`, or gate science-lane commits by hand.

> merged into "Acceptance-harness gaps …" (second bullet)

### The acceptance harness pins peak counts, never positions (2026-09-09)
`AcceptanceReport` has no coordinates — a change moving every peak while
preserving the count is invisible. On `ba6360d` one peak was substituted
~26 px away, count unchanged, harness silent. Likely two near-threshold
noise peaks trading places, not a defect — but the gate can't tell. Owner:
a checksum needs a tolerance, a design pass.

> trimmed from "A stale DerivedData test bundle fakes both a pass and a surviving mutation"

### A stale DerivedData test bundle fakes both a pass and a surviving mutation — process trap (2026-09-12)
Twice a newly added test method was not discovered by XCTest at all: N-1 of
N cases ran, suite reported success. Rule: reconcile the case count against
`func test` per file. **Related trap:** a test appended "at the end of the
file" can land in the wrong `XCTestCase` class and report "TEST SUCCEEDED"
having run zero cases. Rule: `grep -n "^final class\|XCTestCase"` before
inserting, and grep the run log for the test's own name, not just the exit code.

> trimmed from "The published v2.5.1 artefact is universal but its libraries are arm64-only"

### The published v2.5.1 artefact is universal but its libraries are arm64-only — status unclear, verify against the current release
`lipo -archs` on that build's executable is `x86_64 arm64` while all three
embedded libraries are `arm64` alone, and `Info.plist` invites every macOS
14 machine — every `.h5`/`.emd` open fails on Intel. Not re-checked against
the current v4.0.0 (arm64-only per `docs/decisions.md`, macOS 27 floor)
download that has since superseded it — likely moot if v2.5.1 is no longer
the linked artefact, but unverified. Owner: confirm the current download,
then decide whether v2.5.1 needs withdrawing or annotating.

> trimmed from "The three redistributed dylibs have no rebuild path"

### The three redistributed dylibs have no rebuild path (2026-09-09)
They came from Homebrew `hdf5 2.1.1` / `libaec 1.1.7` on one machine;
nothing in the repo rebuilds them. Owner: whether a release needs a rebuild
script.

> merged into "Acceptance-harness gaps …" (third bullet), from "Acceptance-gate test-infrastructure residuals (2026-09-02)"

### Acceptance-gate test-infrastructure residuals (2026-09-02)
`real-data-acceptance/run.sh`'s empty-glob SKIP exits 0, so a machine with
zero datasets passes the gate — whether it should consult `expected.json`
is open. The 15 s acceptance budget gates 4 pinned datasets only. `abs_tol`
on virtual-image fields exceeds one fixture's whole dynamic range. The
comparator's `rel_tol` on `diskProbeRadiusPixels` is inert below 50 px, and
`if not actual:` is unkillable by any mutation. The runner aborts at the
first red harness, so it can't say how many are red.


---

## Accessibility

> trimmed from the Accessibility section text

## Accessibility (does NOT block a release — owner decision, 2026-09-11)

Deferred to a far-future release, kept in full because it is a live defect
and not VoiceOver-only: any AX client resolving labels on the front window
trips it, blocking any automated driving rig, and it crashed the owner's own
session twice on 2026-09-08. **Two crash reports, evidence aged off
2026-09-15, suspect named:** `EXC_BAD_ACCESS` at a stack guard page —
overflow — in `AccessibilityNode.accessibilityLabel()` → `labelsToResolve` →
`resolvedRole(forPlatformElement:)` → AppKit, both times while an AX client
resolved labels on the front window; VoiceOver does exactly that. **In-body
controls report no accessibility label — same bug:** `Compute Mean / Max`,
`Fit Detector Ellipse`, both image-pane buttons, every `Advanced` disclosure
come back as bare `AXButton`/`AXDisclosureTriangle` with empty
title/description/value, while AppKit-backed toolbar items report
correctly. Treat as one Gate D, not two fixes.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.


---

## Code hygiene

> trimmed from "The audit's refactor list, rows 4–13"

### The audit's refactor list, rows 4–13 — most parked, one closed off-list
Rows 1–3, 10 landed (`e415929`); row 8 closed 2026-09-17; row 5 (Settings
extraction, then the full AppState seams plan) closed 2026-09-18 —
`AppState.swift` 5476 → 1474 lines at closeout, since grown again with the
seams' own follow-ons. **Still open:** row 4 (a shared harness `fail`
helper — Gate B on it, a shared bug can green 46 harnesses at once); rows
6–7 (the ResultExport/BraggVectorEMDWriter splits above, both parked); row
12 (the >1 000-line harness mains). **Row 9 is a do-not:** five different
`median` bodies in Core stay separate until a Gate D shows they should
agree (ADR 015). Owner: whoever picks a row.
Detail: `archive/open-items-detail-2026-09-18.md`.

> merged into "Parallax and ptychography are unrunnable …" (drive on the stronger Mac) and "Diffraction groups in a Debug build …" (profile it); the "Done" half is history, the verdicts are in `archive/v4/cleanup-audit-2026-09-25.md`.

### Scope clean-up — worked with the owner 2026-09-28; two follow-ups owed
Done: the dead `displayedProduct` branch, the pre-v1.0 `legacyDomain` guess (now a refusal) and the Settings
engine picker are gone; the other audit rows were kept on evidence (`archive/v4/cleanup-audit-2026-09-25.md`,
verdicts). Owed: **drive parallax and ptychography on the stronger Mac**, then keep or remove them; **profile
diffraction groups** (Release vs Debug, per phase) before deciding its fate.

> trimmed from "Minor tooling/hygiene residuals". The last sentence (`Aperture` declared in `App/AppState.swift`, harness copies) is **closed (evidence)**: `Aperture` is `package struct Aperture` in `mac4DSTEM/Core/Analysis/VirtualDetector.swift:24`, and `tools/*/main.swift` construct it with no `struct Aperture` of their own (grep 2026-09-29). The `.fixedSize()` count and the zoom-badge line moved: 20 call sites, badge at `ImagePanes.swift:639`.

### Minor tooling/hygiene residuals
`tools/free-space.sh`: the temp prefix is spelled by producer and reaper
separately, and the MCP root is hardcoded — a `tools/lib/` constants file
is deliberately NOT taken (every gate sources through `run-tests.sh` under
`set -euo pipefail`; a bad line there kills the whole harness). `.fixedSize()`
in `UI/`: 12 bare sites against the constraint-loop rule, one armed (the
zoom badge, `ImagePanes.swift:587`, inserts/removes a child repeatedly
mid-pinch) — not fixed deliberately, not urgent. `Aperture` is declared in
`App/AppState.swift` and scientific harnesses carry their own copies that
would still pass if the app's gained a field — belongs in `Core/`, owner:
the next `AppState` extraction.


## Misc data-layer items, low priority — trimmed by the orchestrator 2026-09-29 night (verbatim)

### Misc data-layer items, low priority
A real load cancel was driven 2026-09-29 night ("Load cancelled", back to the welcome, `d1-09c`). `#31`
`validationIssues` is O(n²) in a SwiftUI view body — confirmed still called
from `DiskDetection.swift`/`TiledDiskDetection.swift` inline, not cached.
`#32` `isSymmetry`'s bijection check has no fixture coverage. `#30` —
origin calibration over a NAS runs at ~3 MB/s (2026-08-06), uninvestigated
since. Ptychography pads both object axes unlike py4DSTEM (deliberate,
kept as a `DEVIATION` note — correcting it was outside the port's scope).
Residency `.automatic` cannot be re-measured without a second machine
(dropped by decision, v2 S3, not dormant — do NOT set
`ResidencyAdmission.measuredWorkingSetFraction`; the three checked-in
training cubes top out at 0.19 working-set ratio, no knee in that data).
`tools/bragg-spacing-probe/` and `tools/residency-sweep/` both need
gitignored multi-GB data and stay diagnostics only — a standing limit, not
a gap. C3 drive leftovers, still unprovoked: staleness (f), and "Fit
Detector Ellipse" on the demo ending in "residual is too large (0.247)".


## Entries rewritten from the 2026-09-29 night drives — originals as they stood at `4cef2d1` (verbatim)

### Full-cube Friedel origin calibration froze the app, then progress/ETA plateaued — fixed, screen check owed (2026-09-19)
Owner's Debug 171×171 run froze without memory/thermal pressure; Gate D
refuted an HDF5/FFT stall — `calibrateOrigin` now detaches only the tiled
CPU-FFT pass, and progress now emits completed rows with monotonic,
non-cancelled publication (was: only after a 60-row tile, giving a
plateaued ETA). Current-app demo drive (12×12) verified selected Friedel,
live Cancel, measured completion; unit and Friedel/py4DSTEM parity passed.
**The full-cube row-progress/ETA drive remains owed**, not a release gate.

### Sidecar/session UX residuals, mostly small
Recents-row location labels unverified on screen. A sidecar retarget made
before any save survives only until the next dataset change. Repeating
"Save Session Sidecar As…" can prefill a doubled `.h5.h5` suffix. Pre-S4
calibration-only sidecars remain unrecognisable (owner decision on the
open-panel filter). Manual Q/R pixel scale fields: **fixed in code, drive
owed** — owner enters a manual scale, the row turns green; owed: confirm
the field stays visible and editable afterward (a wrong R scale silently
rescales every real-space axis). `calibration.*` accessibility identifiers
are emitted twice while the export sheet is open (harmless today, would
defeat a future UI test addressing a readiness row). Owner: unclaimed.

### No workflow logic in the rooms — partially addressed, on-screen verification owed
Original finding (2026-09-21, Prepare and Bragg disks): steps, manual
fields and calibrations were unordered prose, not legible as steps with
state and one verb. `PrepareSettings.swift` (2026-09-23 check) now declares
`stepOrder` (`[.originProbe, .ellipse, .rotation, .qScale, .rScale]`) and a
`readinessSummary` line replacing the old prose paragraph — code evidence
the redesign happened, but not re-driven on screen against the original
critique. Owner: confirm on a real cube before closing.

### Two pre-rebuild UI process gaps, still open
- **UI tests cannot see layout; the unverified row drains only by owner
  time**: 33 UI-adjacent tests are all pure functions; the 2026-09-21 drive
  found eight structural defects 844 green tests did not. Every UI commit
  should ship captures at 1100/1470 pt, light and dark, under `archive/`
  so "Unverified on screen" means undecided, not unlooked-at. Light-mode
  captures are still owed even after the v4.0.0 rebuild (status.md: "Unseen:
  light mode on a real cube; busy run at the 915-pt minimum on a real cube").
- **UI docs written for agent continuity, not owner decisions**: `docs/archive/v4/window-design.md`
  is still 442 lines / 4 416 words (2026-09-23 measurement) against
  `status.md`, this file and `ROADMAP.md`. Next: brief + red-box screenshot
  + a 20-row element table; retire ADR 034's rejected half rather than
  amend it. Unclaimed.

### No automated visual baseline (2026-08-17), residual after the v4.0.0 drive
Every acceptance run is numeric-only; the owner driving the app is the only
evidence anything "looks right." Driving has caught defects with every
harness green five separate sessions. Since 2026-08-17: the v4.0.0 rebuild
was driven and accepted on a real cube ("fantastic so far"); still never
seen on screen — light appearance on a real cube, a real load cancel, the
bounded promote run. Retired checklist trap notes:
`archive/v2/visual-acceptance-checklist-2026-09-03.md`. Owner: one sitting.

### The 915-pt launch crash: fixed by the sidebar maximum; the inspector's maximum is unmeasured (2026-09-28)
Gate D, refuter NOT REFUTED: launch aborted in the constraint loop iff restored **window − sidebar ≤ 639 pt** (28 runs,
both axes). The shell allowed a 320-pt sidebar at the 915-pt floor where ≤ 275 fits. Fix (owner's pick, SwiftUI only):
`sidebarWidth.max` 320 → 270, so the saved 278 and 320 states launch; the floor stays at 915. The rejected alternative
was a 965-pt floor, which also passed. Open: the inspector's max of 460 has the same arithmetic (190 + 460 + 365 > 915).
Its width is not saved, so it cannot crash at launch, but a live drag at the floor is untested. The unit host now
clears saved geometry (`run-tests.sh`). Rule and earlier cases: `archive/closed-items-2026-09.md`.

### `PaneSplit` image-floor residual — status unclear, verify against current split code
(a) header overflow and (c) divider reset were closed and seen on screen
2026-09-07. (b) **The image floor lapses below 2× itself**: the fraction
saturates at 0.5 under ~360 pt of usable width; SwiftUI offers no detail-
column minimum short of the window's own floor, and announcing one from
inside the split is the constraint-loop shape. Not re-verified against the
v4.0.0 toolbar/inspector rebuild's own split code — status unclear. Owner:
with the owner's next drive.

### Owed on screen from earlier drives (2026-09-09)
Still unexercised: the four failure paths (ROI-sum, sidecar inventory
refresh, configurator single-pattern preview, "No preview available")
reaching the status strip, both Reset confirmations, and the disk-centre
label round trip (the rig couldn't synthesize a click on that Metal/Canvas
pane at all). That one needs the owner's hand.
