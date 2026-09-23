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

## Science & parity

### App R–Q rotation is −py4DSTEM's on the same file; QR_rotation crosses the boundary unconverted — Gate D, reopened 2026-09-23
The app reads a file's scan/detector axes as (Ry, Rx, Qy, Qx)
(`DatasetDescriptor.swift:15,38-41`), py4DSTEM as (Rx, Ry, Qx, Qy): both pairs
swapped, so the app's θ = −py4DSTEM's θ, transpose identical. Measured
(independent refuter, `archive/v3/rq-frame-class-2026-09-23.md` §Independent
refutation): real `Particle_1_Stack_1…bin8.h5` → py4DSTEM +80.0° T, app
−80.1° T; three planted non-square fields flip sign likewise. Origins and
peaks are axis-swapped at the py4DSTEM import/export boundary, but
`QR_rotation` is not (`AppState+Open.swift:474`; `ResultExport.swift:1304` →
`BraggVectorEMDWriter.swift:1690-1697`); no `DEVIATION` note on the sign.
**Trap:** `bfa5525`'s "fix" transposed the harness's own reference array,
relabeling py4DSTEM into the app's frame — leg (b) then PASSed by
construction; restored to informational (`a0e9a4a`).
Owner: decide the displayed convention; then Gate D on the sign conversion
(a scientific number), a file-faithful leg (b), and check `ellipseTheta` at
the same boundary.

### Origin validity mask landed 2026-09-17 (disclosure + D4 count); overlay owed, still `validation:"none"`
`OriginMaps.originValidity: [Bool]?` carries the robust trim's per-position
`kept` mask (disclosure only, no fitted number moves; ADR 033). D4 count
landed (`PrepareSettings.positionsUsedValue`, unit-tested) but **unverified
on screen**. Step-3 trim-sweep PASSED on 4 cubes: excluded 0.6–15.7 %,
`maxGap` 1–5 — two cubes exclude alike but differ spatially. **Owed:** the
spatial validity overlay (origin fit over the scan grid, excluded positions
greyed via `DisplayedProduct.validityMask`) is a larger follow-on, not
built. Owner: unclaimed. Detail: `archive/open-items-detail-2026-09-18.md`.

### Parallax and ptychography are unrunnable on the owner's Mac — release-notes item
8–11 GB of working set for a 268 MB cube is a 30–40× ratio; nobody has
checked whether that is the algorithm's true cost or an over-estimate that
refuses work the machine could do. That is a Gate D of its own (a number
governs whether a feature runs at all), not a tuning knob to raise.
Consequence: both features ship **undriven on real data** and must be
described that way in release notes. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### Phase mapping has no object-level pass bar — draft pre-registration, owner decision owed 2026-09-23
Per-position error cannot see objects: at 0.96–1.75 % the published Thronsen maps have 20–173×
the truth's θ′ face-on objects (`docs/cloud/2026-09-23/T2-direction-check.md`). Cleaned counts
cannot certify a classifier (random flips clean up to the truth's counts); raw speckle can. The
app's T1 raw speckle is 23 objects at the 0.1 % floor, 5 at 0.15 % (published 1–13).
**Trap:** the truth's cuts (782 / 10 / 4 px) are that dataset's, never an app default. The shipped
guard (ADR 038) still needs a second truth dataset before "validated" (closed-items 2026-09).
Owner: the five decisions in `docs/cloud/2026-09-23/T4-object-preregistration-DRAFT.md`.

### Precipitate objects residuals — found driving the app, 2026-09-23/24 night
- a phase takes one zone axis and the same crystal cannot be added twice (silently); β″ at
  [010] + [001] needs a second CIF file name. Fix: a unique slot id (today `id == model.id`);
- a table row does not highlight its object; the Result legend prints "76.2 %" with a ".";
- zone-axis ties list in a run-dependent order (unchanged code, pre-e4 vs post-e4k0);
- unverified on screen: the table's final column widths, the density on its own line.

### The owner's real Al-Mg-Si cube: matrix almost never wins — driven 2026-09-24, cause not established
`Al_Mg_Si_060…bin_4` (⟨110⟩Al, 0.0457 Å⁻¹/px), scaled to the detector: matrix 0.7 % at the 0.15 %
floor, 2.2 % at 0.5 %; β″ speckle. Al is found (43 % of vectors) but ~4 of 6 peaks per pattern
are unexplained by one global orientation; a different Al CIF cannot help (0.003 vs 0.046 Å⁻¹).
**Trap:** do not tune the floor or β″ first. Gate D next session: (1) ACOM on Al — does the
orientation vary? (2) template overlay — disks or kernel maxima? `archive/v4/almgsi-drive-2026-09-23.md`.

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

### Parallax default bin schedule runs the finest bin once; py4DSTEM's runs it twice — Gate D diagnosed 2026-09-17, fix owed
`ParallaxAligner.defaultBinSchedule` returns `[4,2,1]`; py4DSTEM's default
(`num_iter_at_min_bin=2`) appends one repeat → `[4,2,1,1]`, so every gate on
`isComplete` computes one refinement pass short. Diagnosed (refuting
observation confirmed: no `numIterAtMinBin` knob exists). Not yet run: the
head-to-head experiment (py4DSTEM `reset=True` vs the port, max-abs diffs).
**Trap:** `tools/parallax-alignment-test/reference.py:354-357` hard-codes the
schedule without the repeat, so the green test can't catch this.
Science, Gate D before any change. Owner: unclaimed.
Detail: `archive/open-items-detail-2026-09-18.md`.

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

### Precipitate segmentation defects — the image `segment` path, unwired; the class-map path is wired (ADR 038)
`PrecipitateSegmentation.segment` only (owner: whether/how to fix, not urgent while unwired): a
large contiguous NaN region survives imputation; NaN on a feature erases it silently; two
one-token mutants (robust sigma, fill statistic) leave every test green; dark ridges register
via their flanks. Shared `measure`: a negative peak collapses an object to 1×1 (no fixture).
Full wording: `archive/open-items-detail-2026-09-23.md`.

### Other named science/presentation residuals
Full original wording for the first four: `archive/open-items-detail-2026-09-23.md`.
- **Al-Mg-Si cube's peak set not clean** (2026-09-12): only 39 % of detected
  vectors explained by the best Al orientation — a detection statement, not
  a matcher failure (matcher refuses 99.0 % rather than inventing).
- **β″ zone axis for ⟨110⟩Al not chosen** (known, scoped): no ⟨110⟩Al variant
  is viewed down its needle axis; which axes it DOES present is unanswered.
- **The ellipse "Fit anyway" mark doesn't survive a session round trip**:
  `PixelCalibration` carries a/b/θ only — a sidecar wire-format decision.
- **A challenged matrix verdict is drawn like one by exclusion**: same grey
  for "matrix took it back" vs "too little to index." Presentation, no Gate D.
- **The hexagonal IPF colour key may be labelled wrong way round** (2026-09-11):
  the colour function and both label strings are established; which triangle
  corner each sits under is not. Owner: settle against the convention, pin
  with a unit test, before calling it presentation-only.
- **Single-slice ptychography's export guard may miss its mode**
  (`ResultExport.swift:1627` vs `:1478`): not established that the publish
  path uses the distinct case. Gate D — a scale bar is a scientific number.
- **The Quantitative badge consults no origin gate**: only ACOM is wired
  (`ACOMWorkflow.swift:145-150`); Strain snapshots the origin and nothing
  reads it; DPC snapshots nothing. A 2026-09-11 fix was Gate-B rejected and
  reverted (changed no behaviour). Ships as a stated limitation. Gate D+B owed.
- **A radius-only aperture drag destroys the fitted origin** (2026-09-11):
  `ApertureOverlay.emit` rounds the centre and hands the whole `Aperture` to
  `updateAperture`, which trips the centre-change branch on rounding alone
  (`AppState.swift:3112`). Cheap, Gate D (a number can move).
- **"Computed this session" reports what EXISTS, not what was computed**
  (2026-09-11): a restored sidecar shows both readiness rows green having
  computed nothing (bare predicates, `WorkspaceInspector.swift:563-565`).
  Presentation only.
- **Moving the detector destroys the origin fit with no durable warning**
  (2026-09-11): the aperture centre IS the calibration; only a transient
  status line notices. Owner: confirmation, banner, or refuse.
- **Bullseye disk detection accepts noise** — two of three fixes landed
  2026-09-05 (flat mode + Use File's Probe, parity 878/878 and 164/164);
  open: an outer-edge probe size for structured probes. Owner: drive Map ▸
  Bragg disks, Flat + Use File's Probe, Min relative intensity ~0.05.
- **The one-peak warning is below the fold; Strain unlocks without it**
  (driven 2026-09-09, `archive/v3/drive-2026-09-09.md` finding 16): Strain
  gates on Bragg vectors existing, not on being usable. Presentation +
  readiness question, no Gate D (mechanism established by reading, no number
  moves).
- **Twisted bilayer graphene finds only the beam at defaults**: one accepted
  peak at `relativeToPeak` 0 AND 1 — the relative threshold isn't what
  removes the disks; not diagnosed which stage swallows the ring. Gate D
  owed with a per-pattern funnel.
- **Learned detector above 256 px: probe/pattern anchor mismatch** (Gate B):
  the probe channel crops clamped-centred while pattern windows use
  `windowOrigins` — the opposite of every training input. No Python
  reference above 256 px; nothing shipped is above 250 px. Owed: one
  synthetic >256-px case scored both ways before the windowed path is
  quoted as measured.
- **#18 — the training campaign can't reproduce the app's Si_SiGe strain**
  (2026-09-02): resolved mechanism (campaign's origin fit is ~7 px off,
  poisoning clustering scale; the app's own gate rejects that fit). Two
  candidate fixes exist, neither made (own Gate B). Detail:
  `archive/open-items-detail-2026-09-18.md`.
- **CIF import can silently accept a wrong crystal** (2026-09-01): a non-P1
  declaration with a partial ops list can still import the wrong cell
  (Gate B escape E2, recorded not fixed) — needs a 230-entry IT-number→
  group-order table the importer lacks. Owner: unclaimed, Gate B when picked up.
- **ACOM orientation/export coverage gaps** (2026-08-31): exported Euler
  angles differ from py4DSTEM/orix by frame rotation `P` (median 38.55°
  naive misorientation, math right, label wrong); every gated ACOM harness
  builds its own peaks through the function it tests, so two frame-mutation
  bugs stay green. Owner: relabel-vs-convert decision, then Gate B.
- **DPC's banner contradicts its badge — corrected 2026-09-04**: the badge
  and banner agree; the real defect is `PhaseSettings`' always-shown
  qualitative banner over quantities `quantitativeStatus` calls quantitative.
  No version field exists to migrate existing sidecars/PNGs on a fix. Owner:
  the trust-fixes session, a judgement call.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

## Data, IO & sessions

### Full-cube Friedel origin calibration froze the app, then progress/ETA plateaued — fixed, screen check owed (2026-09-19)
Owner's Debug 171×171 run froze without memory/thermal pressure; Gate D
refuted an HDF5/FFT stall — `calibrateOrigin` now detaches only the tiled
CPU-FFT pass, and progress now emits completed rows with monotonic,
non-cancelled publication (was: only after a 60-row tile, giving a
plateaued ETA). Current-app demo drive (12×12) verified selected Friedel,
live Cancel, measured completion; unit and Friedel/py4DSTEM parity passed.
**The full-cube row-progress/ETA drive remains owed**, not a release gate.

### An emptied manual Q field, confirmed, discards the file's calibration (2026-09-07)
Agent drive (`drive/shots-c3/b2-qr-unset-bug.png`): on a cube with Q pixel
scale green "From file", typing `0.2` into Prepare's Manual field entered
nothing (this locale wants `0,2`; the period was dropped silently), and
Return on the now-empty field flipped the row to "Not set" and the scale
bar from `0.5 Å⁻¹` to `5 px`. `0,25` typed afterward worked live. Two
things to establish before a fix (Gate D): why a period is rejected rather
than parsed, and whether an empty manual entry should clear the file value
or restore it. Owner: `/diagnose`.

### HDF5 runs under one lock — what that still costs (fixed 2026-09-15 late night)
Costs: a caller blocks its thread for the length of one operation (a
sidecar write can be seconds); the two `dlopen`s stay two; no unit test can
crash-test this, the probe is diagnostic. The "refuse a second open" guard
stays as belt and braces. **Residual:** thread-safety is still asserted by
one 2026-08-19 `nm` inspection; `H5is_library_threadsafe` is still called
nowhere.

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

### DM4Reader silently reads whole files into RAM off non-local volumes (2026-09-02)
`.mappedIfSafe` declines to map on any volume failing
`MNT_LOCAL && !MNT_REMOVABLE` (every external disk, disk image, smbfs —
confirmed) and falls back to a full anonymous-memory read held for the whole
session. The original 8 GB-machine death that motivated this is still NOT
explained as this mechanism's cause — real defect, not yet tied to that
incident. Owner: a later session, Gate B. Detail: `archive/v3/open-items-detail-2026-09-16.md`.

### The sidecar reader has D003's missing attribute-length guard too (2026-09-09)
`BraggVectorEMDWriter.swift`'s attribute reads share D003's defect in
`H5Reader.swift`: `H5Aread` assumes a scalar without checking file type or
extent (measured: 24 bytes into 8; 32 into 9). Same three-line fix
(`H5Aget_space` + `elementCount(spaceID:) == 1`). Owner: a patch session.

### Scan-fastest DM4 detector pair may be transposed (2026-09-05)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps tags as `[Rx,
Ry, Qy, Qx]`, giving a pattern 480×448. A transposed pattern silently flips
strain axes and R–Q rotation. Owed: the owner reads width/height in GMS —
if 448 wide, flip `DM4Reader.scanFastestStrides` and pin an ncempy checksum.
Detail: `archive/v3/open-items-detail-2026-09-16.md`.

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

### Misc data-layer items, low priority
Load-cancel (a real load cancelled on screen) never driven. `#31`
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

## UI & on-screen

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

### Inspector kit gaps — confirmed still open 2026-09-23
`UI/InspectorRows.swift` has no adaptive `Menu` (Add Phase stays hand-rolled)
and no warning-note variant — `InspectorNote` is a plain secondary caption;
orange captions and unvalidated badges stay hand-rolled and must not change
shape. Long labels ("Measured kernel mode") wrap beside wide pickers —
wording is the owner's call. Scoped work, not bugs.

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

### Cosmetic parallax-completeness disagreement, confirmed still present (2026-09-23)
Fixing `parallaxStage4IsComplete` made the checklist checkmark more correct
but exposed two independent, un-refactored "is parallax done" checks still
reading `parallaxSubpixel` alone: `WorkspaceView.swift:309` and
`AppState.swift:1236`. Cosmetic (the dispatcher's own gate is independent
and correct) but real; `WorkspaceView.swift`'s half is Frozen Shell, so
`AppState.swift`'s half was left matching rather than diverging further.
Owner: unclaimed.

### No automated visual baseline (2026-08-17), residual after the v4.0.0 drive
Every acceptance run is numeric-only; the owner driving the app is the only
evidence anything "looks right." Driving has caught defects with every
harness green five separate sessions. Since 2026-08-17: the v4.0.0 rebuild
was driven and accepted on a real cube ("fantastic so far"); still never
seen on screen — light appearance on a real cube, a real load cancel, the
bounded promote run. Retired checklist trap notes:
`archive/v2/visual-acceptance-checklist-2026-09-03.md`. Owner: one sitting.

### The constraint-loop crash rule, and one unreproduced crash of its class (2026-09-04, 2026-09-22)
**The rule, demonstrated 2026-09-04: nothing inside a split's hosted content
may repeatedly change its own minimum size.** Two sites, both in the status
bar, both fixed (`e608dbd`, `27de9bb`). Residuals: n=1 each way against a
fault once called intermittent; the inspector's Performance rows still tick
per second. **2026-09-22 night:** one crash of this class
(`_crashOnException` in `updateConstraintsForSubtree`, a scratch build, 3 s
after launch) after a Gate D fix made the strip's glance/run slots
compressible without a constant minimum; NOT reproduced (12 resizes, 6
launches) after the slots were given a constant min/ideal/max
(`LayoutPolicy.compressibleSlotMinimum`). A different pre-session abort
(20:26, owner's build) is undiagnosed. Owner: unclaimed.

### `PaneSplit` image-floor residual — status unclear, verify against current split code
(a) header overflow and (c) divider reset were closed and seen on screen
2026-09-07. (b) **The image floor lapses below 2× itself**: the fraction
saturates at 0.5 under ~360 pt of usable width; SwiftUI offers no detail-
column minimum short of the window's own floor, and announcing one from
inside the split is the constraint-loop shape. Not re-verified against the
v4.0.0 toolbar/inspector rebuild's own split code — status unclear. Owner:
with the owner's next drive.

## Release, CI & process

### GitHub CI's unit job has been red since the v3.0.0 cut — worse after v4.0.0 (2026-09-14, updated 2026-09-23)
**2026-09-23:** the macOS 27 deployment floor (v4.0.0) makes the `macos-26`
runner unable to build the app at all (target above its SDK) — CI needs a
macOS 27 runner image, owner's call. Before that: the runner's Xcode 26.6
type checker timed out on `ContentView`'s file-importer closure while the
owner's Xcode 27.0 compiled it fine; three `main` runs failed unread. Every
green gate in `status.md` is a LOCAL run on Xcode 27.

### 119 unverified defect claims from the 2026-09-09 repository review, triage order owed
259 records, deduplicated to 156 clusters (`archive/2026-09-09-review/register.md`).
Three fixed, 16 repeat, 8 may repeat the 2026-08-31 review, 8 already
tracked here, **119 new, none verified** — claims with a file and a line,
not defects. Do not fix from the register: each one that can move a
scientific number is its own Gate D. Owner: triage order.

### The learned-detector parity fixture is a same-runtime claim; CI has no Neural Engine (2026-09-14)
`testLearnedPathMatchesPythonReference` failed on both runner jobs, passed
locally. Now skips (stated) where no Neural Engine is listed; the 98 % bars
were NOT loosened. A CPU-written second fixture would turn the skip back
into a check. Owner: whether CI should verify this.

### A red real-data gate names the symptom, not the cause; only one harness reaches it (2026-09-08/09)
`compare.py`'s `fail()` raises `SystemExit` at the first mismatch, hiding
later ones — confirmed by the Gate D refuter, cheap fix (collect every
mismatch). Separately, `real-data-acceptance/run.sh` is the only harness
`all` reaches; `scientific` stayed green three days past a real regression
in 2026-09-05 (`ba6360d`), 43 commits before symptom. Uncosted options: add
the harness to `scientific`, or gate science-lane commits by hand.

### The acceptance harness pins peak counts, never positions (2026-09-09)
`AcceptanceReport` has no coordinates — a change moving every peak while
preserving the count is invisible. On `ba6360d` one peak was substituted
~26 px away, count unchanged, harness silent. Likely two near-threshold
noise peaks trading places, not a defect — but the gate can't tell. Owner:
a checksum needs a tolerance, a design pass.

### A stale DerivedData test bundle fakes both a pass and a surviving mutation — process trap (2026-09-12)
Twice a newly added test method was not discovered by XCTest at all: N-1 of
N cases ran, suite reported success. Rule: reconcile the case count against
`func test` per file. **Related trap:** a test appended "at the end of the
file" can land in the wrong `XCTestCase` class and report "TEST SUCCEEDED"
having run zero cases. Rule: `grep -n "^final class\|XCTestCase"` before
inserting, and grep the run log for the test's own name, not just the exit code.

### The published v2.5.1 artefact is universal but its libraries are arm64-only — status unclear, verify against the current release
`lipo -archs` on that build's executable is `x86_64 arm64` while all three
embedded libraries are `arm64` alone, and `Info.plist` invites every macOS
14 machine — every `.h5`/`.emd` open fails on Intel. Not re-checked against
the current v4.0.0 (arm64-only per `docs/decisions.md`, macOS 27 floor)
download that has since superseded it — likely moot if v2.5.1 is no longer
the linked artefact, but unverified. Owner: confirm the current download,
then decide whether v2.5.1 needs withdrawing or annotating.

### Owed on screen from earlier drives (2026-09-09)
Still unexercised: the four failure paths (ROI-sum, sidecar inventory
refresh, configurator single-pattern preview, "No preview available")
reaching the status strip, both Reset confirmations, and the disk-centre
label round trip (the rig couldn't synthesize a click on that Metal/Canvas
pane at all). That one needs the owner's hand.

### The three redistributed dylibs have no rebuild path (2026-09-09)
They came from Homebrew `hdf5 2.1.1` / `libaec 1.1.7` on one machine;
nothing in the repo rebuilds them. Owner: whether a release needs a rebuild
script.

### Acceptance-gate test-infrastructure residuals (2026-09-02)
`real-data-acceptance/run.sh`'s empty-glob SKIP exits 0, so a machine with
zero datasets passes the gate — whether it should consult `expected.json`
is open. The 15 s acceptance budget gates 4 pinned datasets only. `abs_tol`
on virtual-image fields exceeds one fixture's whole dynamic range. The
comparator's `rel_tol` on `diskProbeRadiusPixels` is inert below 50 px, and
`if not actual:` is unkillable by any mutation. The runner aborts at the
first red harness, so it can't say how many are red.

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

## Code hygiene

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
