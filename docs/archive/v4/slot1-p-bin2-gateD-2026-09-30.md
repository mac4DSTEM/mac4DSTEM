# Slot 1 lane P — the bin-2 aperture default: Gate D record (2026-09-30 night)

Lane P's implementer (Sonnet 5.5) wrote the diagnosis and predictions before any run; the supervisor (Fable 5.1) reviewed the diagnosis; an independent Fable refuter's verdict is `slot1-p-bin2-refuter-2026-09-30.md` (HOLDS WITH CORRECTIONS; its must-fix test was added before landing). Logs named here lived in the session scratchpad and are not retained; the retained logs show the pass/fail pattern only — the assertion values and exit codes were read from the .xcresult bundles, deleted after reading (refuter finding 3).

## Diagnosis — item 1, the bin-2 aperture ring (Gate D; written BEFORE any code or reproduction run, 2026-09-30 22:05)

Observation (drive 3, shot 52 `docs/archive/v4/drives-2026-09-30-night-shots/d3-52-bin2-done.jpg`, read by eye from the jpg):
binned 64 x 64 pattern pane spans x 208..525 (317 px), y 206..522. Ring/dot centre at x 289, y 286 => fraction (0.256, 0.253)
=> about detector pixel (16.2, 16.2) of 64 (pixel-centre convention). Ring radius: dot 289 -> right edge 368 = 79 px
= 79 / (317/64) = 16.0 detector px. The pattern's disks centre sits at the pane centre (32,32). Origin & probe read "Not set"
in that shot, i.e. the file carried NO recorded origin on that view.

Candidates and the observation that would refute each:
- (i) default `Aperture(centerX: qx/2 ...)` built from the SOURCE descriptor while the view is binned. Would put the centre at the
  source middle (64,64 for a 128 px source), off the 64 px pane, with outer radius 32. REFUTED by the shot (centre ~16, radius 16)
  and by the code: `let descriptor = view.descriptor` (AppState+Open.swift ~378) shadows the source before line 416; radius 16 =
  64/4 is exactly the VIEW-derived default.
- (ii) the file's `qx0Mean/qy0Mean` (source pixels, line 495) not scaled by the bin in `CalibrationReReference.apply`. Would
  leave the centre at the source value (64,64), not (16,16); and needs a recorded mean, but the shot says "Origin: Not set".
  REFUTED by the shot; and by the code: `apply` runs `binnedCoordinate` on the aperture centre whenever `readDetectorCrop != nil`,
  which is non-nil for every bin > 1 (LoadSpecification.swift:317).
- (iii) a stale aperture from the previous (unbinned) load survives `activate`. Would leave (64,64) r=32 (the previous 128 px
  defaults) or a previously dragged value. REFUTED: line 416 assigns a fresh `Aperture` unconditionally before any await, the
  drive used a fresh `open -n` instance (no previous load), and the radius is the new view's.
- (iv) centre and radius follow different rules. SURVIVES: the radius is the view-frame default and is never touched again; the
  centre is the view-frame default (32,32) and is then handed to `CalibrationReReference.apply` as if it were a SOURCE-frame
  position. `apply` subtracts the crop offset (0) and rebins: binnedCoordinate(32, bin 2) = (32 + 0.5)/2 - 0.5 = 15.75. That is
  the ring at pixel 15.75, pane fraction (15.75 + 0.5)/64 = 0.254 — matches the measured 0.256 / 0.253 to the resolution of a jpg.
  It needs no sidecar and no drag: only "no file-recorded origin" + a detector bin (or a detector crop).

The same mechanism predicts two more symptoms, testable headless, that the shot cannot show:
  - a detector CROP (bin 1) without a file origin: view-middle default minus the crop offset. 64 px source, 32 px crop at offset
    16: default 16 -> 16 - 16 = 0.
  - a crop whose offset exceeds the default (16 px wide at offset 48): 8 - 48 = -40 is "outside", so `apply` APPENDS a `Beam origin`
    invalidation ("the direct beam is not inside this diffraction crop") for a file that never had an origin, and returns nil,
    which the caller turns into the geometric default and `.geometricDefault` (right end value, wrong reason, false refusal shown).
  The session-sidecar caller (Session/SessionCalibrationFramePolicy.swift:162) passes the same kind of view-frame default as a
  placeholder and discards the centre only when there is no session centre — but `outcome.invalidated` still carries the false
  refusal (same mechanism, same fix).

Does the fix move a shipped number? YES, on any binned or detector-cropped load whose file has no recorded origin: the aperture
centre (which `Calibration.referenceOrigin` uses as the origin of last resort, `.apertureCentre`: disk detection, ACOM, parallax,
phase mapping, export) and the virtual-detector image integrated with that aperture. Loads with a file origin (mean or maps) go
through the same `apply` but with a genuine source-frame centre: unchanged, pinned by a control test. Full extent: identity.
Refuter: the supervisor reads THIS section.

## Predictions (dated 2026-09-30 22:05, BEFORE the reproduction run; never edited — amend with a new dated line)
Headless path: `AppState.openDemoFixture(calibrated: false, specification:)` (64 x 64 demo detector, no file origin) — the same
`activate` -> `CalibrationReReference.apply` path the drive took.
P1. detectorBin 2 (view 32 x 32): HEAD aperture centre = (7.75, 7.75) [= binnedCoordinate(16, 2)], outer 8. Expected (16, 16).
P2. detectorCrop 32 x 32 at offset (16,16), bin 1 (view 32 x 32): HEAD centre = (0, 0). Expected (16, 16).
P3. detectorCrop 16 x 16 at offset (48,48): HEAD `loadedView.invalidatedCalibration` holds one `.origin` entry. Expected none.
    Centre ends (8, 8) and originProvenance .geometricDefault on HEAD and fixed alike.
P4 (control, GREEN on HEAD and after): `calibrated: true` (file centre (32,32) mean + maps), bin 2: centre = (15.75, 15.75).
P5 (control, GREEN on HEAD and after): full extent, calibrated false: centre (32, 32), outer 16.

## Reproduction on HEAD (2026-09-30 22:05, log P/test-1.log; `xcodebuild test -only-testing:mac4DSTEMTests/BinnedApertureDefaultTests`, EXIT=65)
Predictions met exactly (assertion text from the .xcresult):
- P1 binned: centre "7.75" not "16.0" (RED, as predicted).
- P2 cropped: centre "0.0" not "16.0" (RED, as predicted).
- P3 far crop: one `Beam origin` refusal "The beam centre lands at (-40.0, -40.0) in the loaded detector, outside its 16 x 16 extent"
  on a file that recorded no origin (RED, as predicted; 8 - 48 = -40).
- P4 control (file centre rebinned to 15.75) PASSED; P5 control (full extent 32,32 r16) PASSED.
=> mechanism (iv) reproduced on HEAD; (i), (ii), (iii) stay refuted (the controls show the file-recorded path is right).

## Item 1 — fix and mutations (2026-09-30 ~22:25)
Fix (the ONE surviving mechanism (iv)): the view-frame default aperture is no longer passed to `CalibrationReReference.apply`; only
a file-recorded position (recorded mean, or the file maps' mean) is, and only that one falls back to the geometric default when it
lands outside the crop. `apply(apertureCenter:)` is now `DetectorPoint?` (nil = nothing to move, nothing refused).
Files: App/AppState+Open.swift (`fileApertureCenter`), Core/Data/CalibrationReReference.swift (optional param, doc),
Session/SessionCalibrationFramePolicy.swift (the placeholder removed; same mechanism, false `Beam origin` refusal).
Tests, class `BinnedApertureDefaultTests` (mac4DSTEMTests/PolishSlot1Tests.swift), 7 tests:
| test | mutation | result |
|---|---|---|
| testABinnedLoadWithoutAFileOriginKeepsTheViewsMiddleAsItsAperture | HEAD / M1 (pass the default to apply) / M3 | RED on HEAD (7.75 vs 16), RED M1, RED M3; GREEN fixed |
| testACroppedLoadWithoutAFileOriginKeepsTheViewsMiddleAsItsAperture | same | RED on HEAD (0.0 vs 16), RED M1, M3; GREEN |
| testACropFarFromTheMiddleDoesNotInventAnOriginRefusal | same | RED on HEAD ("beam centre lands at (-40.0, -40.0)"), RED M1, M3; GREEN |
| testAFileRecordedCentreIsStillRebinnedIntoTheView (control) | M2 (never pass the file's position) | GREEN on HEAD and fixed; RED under M2 |
| testAFullExtentLoadKeepsTheDefaultAperture (control) | — | GREEN throughout |
| testReReferenceWithNoAperturePositionRefusesNothing (pure) | M3 (apply substitutes a view middle for nil) | RED M3; GREEN fixed (does not compile on HEAD: non-optional param) |
| testASessionWithoutAnOriginIsNotRefusedAnOriginOnACrop | M4 (session placeholder restored) | RED M4, RED M3; GREEN fixed |
Runs: test-1.log HEAD red (EXIT=65, 3 of 5 red); test-2.log fixed + neighbours (BinnedApertureDefaultTests, CalibrationReReferenceTests,
SessionCalibrationFramePolicyTests, SidecarRestoreProvenanceTests, SessionCalibrationTranslationTests, PromotePositionTests) EXIT=0, 49 "passed" lines, 0 failed
(that run predates the 7th test, added after); test-3-M1.log EXIT=65; test-4-M2.log EXIT=65; test-5-M3.log EXIT=65; test-6-M4.log EXIT=65;
test-7-green.log EXIT=0 (7 of 7 passed, final fixed code). Mutants M1..M4 restored byte-for-byte (cmp against P/*.fixed).

## The frozen-file hunk NOT applied (the owner's call — a wording edit that corrects no false claim)

```diff
-                    InspectorValueRow(key, product.provenance[key] ?? "", mono: true)
+                    InspectorValueRow(ProvenanceKeyLabel.text(key), product.provenance[key] ?? "", mono: true)
+                        .help(key)
```
(`UI/WorkspaceInspector.swift:625`, the Info tab's Provenance section; the Lineage pane already shows the labels.)
