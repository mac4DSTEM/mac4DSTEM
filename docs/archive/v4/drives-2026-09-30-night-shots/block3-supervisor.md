# Supervisor block 3 — verdicts (Fable 5.1, read-only, 2026-09-30 night, tree on 9aa309e4)

Read: RULES.md, CLAUDE.md, the four briefs/reports, sup2/verdict.md, decisions/{evidence,verdicts}.md, every diff of the named
files against HEAD, the new test files, every log named below. No repo edit, no build, no app. Paths are repo-relative.
Full unit on this tree: `me/unit-b2.log` 1278 passed / 0 failed / 3 skipped, exit 0 (`me/unit-b2.sum`).

## 1. DEC (owner decisions 1 + 2) — FIX-FIRST (one small lineage defect in decision 1; decision 2 is COMMIT)

Per claim:
- **Set-aside node fires once per drag, not per tick — HOLDS.** `recordOriginSetAsideRun()` sits inside
  `if let displaced = calibrationSession.calibration.origin` and `origin = nil` follows in the same branch
  (App/AppState+Open.swift:1217-1223); the next tick finds no origin. Pinned by
  `testDraggingTheCentreTwiceRecordsOneManualNode` and `testARadiusOnlyDragRecordsNoLineageNode` (`dec/green3.log` 36/0).
- **D068 marks products stale after a centre drag — HOLDS.** The manual node is a `calibration_origin` node, and
  `calibrationUses(of: strain)` reads used = fit, active = manual, changed (test
  `testACentreDragRecordsAManualOriginNodeAndAStrainOnTheFitReadsStale`; red without the record, `dec/mutA.log` M1, 4 red).
  The verdict surface (`lineageCalibrationSignatures`, App/AppState+Lineage.swift:273-290) reads exactly that.
- **Restore records a new node; products on the first fit stay stale — HOLDS as designed, but the no-product path loses the
  fit's record. This is the FIX-FIRST.** Sequence: Measure Origin → drag the centre → Restore, with nothing computed in
  between — the DEC drive checklist's own sequence (`virtual_detector` consumes no origin node: `inputPolicy`,
  Core/Data/SessionLineage.swift:200-217). The fit node then has no child and no product, so R3
  (SessionLineage.swift:543-556) collapses the manual record INTO the fit node in place: same id, parameters overwritten to
  `{"method": "manual"}`. `recordOriginRestoredRun()` (App/AppState+Lineage.swift:73-82) then finds no non-manual origin node
  and records `{"method": "restored", origin_x_px, origin_y_px}`. Net: fit_function, method, probe_radius_px and fit_rms_px
  are gone from the lineage, the pane shows an origin "restored" by nothing, and a save afterwards persists that. Every DEC
  test avoids the path by recording a strain first (`recordFitAndAStrainOnIt`). Not a number move; a provenance loss on the
  first thing the drive will do.
  **Fix:** capture the displaced node's parameters at the set-aside and restore from them. App/AppState+Lineage.swift:61
  `recordOriginSetAsideRun()`: read `replay.lineage.activeNodes().first { $0.kind == "calibration_origin" }?.parameters`
  BEFORE `recordLineageRun`, and keep it beside the maps — widen the existing tuple
  `supersededFittedOrigin: (maps:, provenance:)` (App/AppState.swift:1324-1325) with `lineage: [String: String]?` (no new
  stored property; same owner). App/AppState+Open.swift:1194 `restoreFittedOrigin`: read the tuple before
  `clearSupersededFittedOrigin()` and pass it to `recordOriginRestoredRun(from:)`, which uses those parameters (with the mean
  overwritten as now) and falls back to `["method": "restored"]` only when none were captured (a fit loaded from sidecar maps
  with no node). Result on the no-product path: the restore collapses back into the same node with the fit's parameters — one
  node, as if nothing happened. Test (ApertureDragOriginTests): fit → drag → restore with NO strain; assert the active origin
  node's `method == "centreOfMass"` and `fit_function` present; mutation: skip the capture → red. Existing tests stay green.
- **Implementer's deviation (warn on `status.isReady ∧ canRestoreFittedOrigin`, not `.ready(.manual)`) — RIGHT.** After the
  drag with a measured probe the origin row's status is `.ready(.mixed)`, not `.manual` (the test asserts `isReady`, and the
  readiness report mixes probe and origin provenance); `.manual` alone would leave that row green. `canRestoreFittedOrigin` IS
  the parked fact, so a manual centre with nothing parked stays un-orange (pinned in
  `testTheOriginRowIsAWarningOnlyWhileAFittedOriginIsSetAside`; `dec/mutB.log` M5 / `mutC.log` M6 red).
- **`savedEllipseIsFitAnyway` compares SAVED pre-translation values with the ACTIVE node within rel 1e-6 — HOLDS.**
  App/AppState+Open.swift:985-996: `saved` is the sidecar's `PixelCalibration` before `translate`; `activeNodes()` is read after
  `replay.adopt` (:946) so a rewound pin counts (`testARewoundPathsActiveNodeDecidesNotTheLastNodeInTheFile`, red on
  `nodes.last`, `mutD.log` M11); `theta_deg` is converted to radians before comparing; 1 % on a and 0.01 rad on theta →
  `.sessionSidecar` (red at a 5 % tolerance, M10). Schema-6 / no-lineage sidecar unchanged
  (`testASidecarWithNoLineageStillReopensAsFromSession`). Note text drops the count when `lastEllipseFit` is nil (M12 red).
- **No wire change — HOLDS.** No writer/reader diff in DEC; the node kind, the `source` key and the lineage attribute all exist
  since ADR 047.
- **Button moved, not duplicated — HOLDS.** UI/PrepareSettings.swift removes the disclosure's button (old :231-241);
  UI/CalibrationReadinessRow.swift:85-96 adds it under the origin row. The row is shared, so **the Export sheet's origin row now
  also carries "Restore Fitted Origin"** (UI/ExportSheet.swift:227) — sensible (the sheet is where an export with a manual
  centre is noticed) but unverified on screen; the drive decides. Detail wording "the file's recorded mean, if any, was
  discarded" is more accurate than the advisor's; keep. InspectorWidthBudgetTests 7/7 in the wide run.

Logs, and two things to state honestly in the commit: `dec/red1.log` 8 new tests red before the fix (exit 65);
`dec/green3.log` 36/0 exit 0; mutations are BATCHED (`mutB` = M2+M5+M8, `mutC` = M4+M6+M9, `mutD` = M3+M7+M10+M11+M12; only M1 and
M7 ran alone) — each mutation still maps to a distinct named red test in its batch (listed in `dec/mut?.log`), so coverage is
inferable, not shown one-by-one. `dec/wide.log` is EMPTY (0 bytes); the "121 passed / 0 failed" the report quotes is in
`dec/wide.results.json` (xcresult JSON; I counted 121 Passed across 8 suites) — cite that file, not the log.

## 2. S15 label-only — COMMIT

- **No number moves — HOLDS.** Core/Data/H5Reader.swift:819-826 sets only `qrRotationNote`; `qrRotationRad = scalar("QR_rotation")`
  is untouched; the single negation at App/AppState+Open.swift:472-473 is unchanged; Core/Data/Calibration.swift:354-356
  appends text to the row detail only. `testAnUnmarkedExportKeepsTodaysNumberAndCarriesTheNote` pins −23° after Open through
  the real writer + reader (`s15/v2-green.log` 30/0 exit 0; `v2-mut3-reader-converts.log` red; `v2-red-stub.log` 2 red first).
- **Cannot attach to a py4DSTEM file — HOLDS.** Requires root `authoring_program == "mac4DSTEM"` AND no marker
  (Core/Data/RQRotationConvention.swift:35-38); emdfile stamps "emdfile" (sup2 §2(a)); pure test pins "emdfile"/nil → false
  (`v2-mut1`/`v2-mut2` red). Sup2's caveat stands: py4DSTEM `save(mode='a')` into an app-authored file keeps the root attrs (rare).
- **Provenance carry/clear — HOLDS.** One memberwise init, `rotationImportNote` defaulting nil (Calibration.swift:84-90).
  Constructions: Session/CalibrationSession.swift:19,132 (new session / reset → cleared, right); Session/SessionCalibrationFramePolicy.swift:163
  (a scratch provenance for the translation, not the live one). Copies: App/AppState+Open.swift:540 takes `reReferenced.provenance`
  whole (Core/Data/CalibrationReReference.swift:137 passes the struct through) → the note survives crop/bin, right, the value is
  still the file's. Retirement: display is gated on `rotation == .importedFile`; measure (CalibrationSession.swift:57), type
  (App/AppState+DPC.swift:93) and a sidecar rotation (AppState+Open.swift:1064) all move `rotation` off `.importedFile`, so the
  note hides (`testAnUnmarkedExportShowsItsNoteOnTheRotationRow`, `me/s15w-mutCal.log` + `s15w-mutOpen.log` 3/1 each, exit 65).
  The string stays in the struct after retirement — harmless (nothing compares provenance across it).
- **Campaign hunk "relabel only" — REFUTED as a description, endorsed as a change.** tools/training-dataset-campaign/main.swift
  makes three changes: import now converts py4DSTEM → app (:272-274, was raw), export now writes py4DSTEM's sign plus the marker
  (:202-205, was the app's unmarked), and the report metric `rotation_degrees` KEEPS ITS KEY but flips to py4DSTEM's convention
  with `rotation_degrees_app_internal` beside it (:514-515). Nothing in the repo reads `rotation_degrees` from campaign output
  (grep: only the tool and docs), so no gate moves and the solver's number is unchanged; but an old campaign JSON compared with a
  new one shows a sign flip under the same key. The archive doc (`docs/archive/v4/s15-rq-legacy-exports-2026-09-30.md:29-30`)
  should say that in one line. Typechecks (`s15/v2-tc.log` exit 0). Diagnostic tool, not the app.
- Si-SiGe_calibrated.h5 (the one References file of this kind) opens with today's number and the note; unverified on screen.

## 3. S18 — COMMIT (three residuals for the owner; one docs gap for the orchestrator)

- **(f) "schema ≥ 6 with no load-spec attribute = whole file" — HOLDS.** Writer history: the attribute
  `mac4dstem_load_specification` arrived at 4e01c242 (2026-08-18 16:51, L6) written only for a reduced view
  (`!specification.isFullExtent`, identical at Core/Data/BraggVectorEMDWriter.swift:1841 today); the schema stamp stayed "5" and
  was written only when results existed (`if !resultNodeNames.isEmpty` at 4e01c242:1355). Schema 6 = 0af2e667 (2026-08-24).
  So schema ≥ 6 + no attribute is the writer's own statement; schema "5" or NO stamp + no attribute → `.unrecorded`
  (Core/Data/BraggVectorEMDTypes.swift:190-196), both covered by tests (`SidecarViewRecordTests`, m5/m6/m13 red).
  **"Schema 5 = no statement" HOLDS literally, but history says every schema-5 sidecar from a RELEASED build was whole-file:**
  reduced views arrived at a06c624e (2026-08-18 15:58, L5, opt-in) 53 minutes before the attribute; v1.0.0 (2026-08-06) had none;
  the next release (v2.5.0, 09-04) is schema 6. S18's calibration handling matches that (adopted onto a whole-file load, refused into
  a reduced view — the only behaviour change: a schema-5 sidecar opened on a crop/bin was re-referenced from a full-extent claim,
  now refused by name, `SidecarRestoreProvenanceTests.testALegacySidecarIsNotMovedIntoAReducedView`, m7/m7b/m8/m9 red). **Residual
  1:** stored disks are refused for EVERY schema-5 sidecar even at whole file (Session/SessionCalibrationFramePolicy.swift:196-208,
  `restoreSessionPeaks`) — stricter than the history warrants: a v1.0.0 sidecar's disks were detected on the whole file and no
  longer restore. Say so in open-items; relaxing it is one line (BraggVectorEMDTypes.swift:193, with the log line kept) and m5's
  expectation — owner's call, not a blocker.
  **Real data (h5py, attrs only, read-only):** References/ holds three sidecars — training_dataset/calibrationData_bullseyeProbe
  (schema 7), training_dataset/sim_Au_data_all_binned (6), thronsen-datasetA/datasetA_stride3 (6); all min-reader 5, none carries
  `mac4dstem_load_specification` → all read `.recorded(.fullExtent)`, behaviour unchanged. **No schema-5 sidecar under References/.**
- **(a) token logic — HOLDS.** `unwindLoadIfNeeded` (App/AppState+Open.swift:815-826): stop when the OWN token or the current one
  is cancelled; reset only when `datasetSession.loadCancellation === owner`; `finishDatasetLoading(owner:)` already refuses a
  non-owner (Session/DatasetSession.swift:115-116). `activate` captures its owner at entry (:340); every production caller
  brackets with `beginDatasetLoading` (AppState+DatasetSession.swift:118, AppState+Open.swift:144,194, Promote:41,137). A nil
  owner reduces to the old `loadWasCancelled` stop without the reset, which cannot arise with a token. LoadTailTests (5) drive
  two loads through the seam; m1/m2 red. **Residual 2 (pre-existing, stated in the test header):** an uncancelled, superseded
  tail still continues over the newer load; unreachable by a click today (open/promote refuse a second load).
- **(b) promote position — HOLDS.** `LoadSpecification` has scanCrop / detectorCrop / detectorBin only (Core/Data/LoadSpecification.swift:73-86,
  no scan bin), so carried = view + scanCrop offset (App/AppState+Promote.swift:108-111) and a bin-only view is unchanged;
  `activate` bounds-checks against the VIEW descriptor (`self.descriptor = view.descriptor` at :361 precedes :383). The test
  compares the pattern's pixels before and after promote (PromotePositionTests; m3/m4 red).
- **(d) maps refusal — HOLDS.** `appOriginMaps` is nil only for a shape/count mismatch (Core/Data/Calibration.swift:952-955), so the
  reason names the right cause; it lands as a `.origin` invalidation on the view (AppState+Open.swift:1042-1045), shown by the
  existing WorkspaceInspector list (:833, Frozen Shell untouched); the mean still stands in (`.sessionMean`, m10/m10b/m11 red).
  m12 pins that a crop session's maps are refused whole by the frame policy (unchanged behaviour).
- **Two post-unit edits — harmless, and mostly not post-unit.** Diffed against the S18 mutation backups:
  Session/SessionCalibrationFramePolicy.swift is byte-identical to `s18/bak/mut-m12.orig` (23:54) — nothing changed after the
  mutation runs; compiled 00:05:39 (`dd/.../DSTEMSession-t.build/.../SessionCalibrationFramePolicy.o`), before unit-b2.
  Core/Data/BraggVectorEMDTypes.swift differs from `mut-m6.orig` (23:49) in three `///` lines only (:179-181, the
  `loadSpecification` doc comment), mtime 00:02:05; unit-b2 started after `me/s15w-mutCal.log` (00:07:21, heavy-lock serialised)
  and exited 0, so the current content is what it built.
- **Residual 3:** `replay.adopt(..., recordedOn: ReplayParameterFrame.of(snapshot.loadSpecification))` (AppState+Open.swift:946)
  still reads the raw attribute (nil → detector identity) for an unrecorded sidecar — consistent with whole-file-only adoption,
  pre-existing; note only. `restoreSessionPeaks` widened to internal for the test (:706) — fine.
- Logs: `s18/red1.log` 8/14 (14 new tests red, exit 65); `green1.log` 22/0; `unit1.log` 1277/0; m1–m13 (15 runs, each ONE mutation,
  exit 65, every `*.restore` = restored-cmp-ok). Mutation discipline here is the model the DEC run should have followed.
- **Docs gap (orchestrator):** `s18/report.md` is three lines — no per-item diagnosis, no (e) list ("replay contracts in three
  places" is "listed only" but the list is nowhere), no drive checklist. The test-file headers carry the BEFORE/AFTER for
  (a), (b), (d), (f); write the archive/open-items entry from them and record (e) as still open. `s18/sidecar_edit.py`
  (legacy / dropspec modes on scratch copies) is the drive fixture.

## 4. S22 — COMMIT

Labels only. The diff of the four files adds 10 lines, every one `.accessibilityLabel(...)`: UI/DiffractionGroupsSettings.swift:41,54;
UI/ImagePanes.swift:195 ("Show claimed disks"); UI/MapSettings.swift:517,574,592,607,618,632 (all `DiskDetectionParameterID.*.title`);
UI/PhaseMappingSettings.swift:553. No other edit. The report's second ImagePanes line (:186, "Fit overlay") already exists at HEAD
(16 labels at HEAD, 17 in the tree) — nothing missing. Not built by S22 (swiftc -parse only); the tree's unit-b2 exit 0 covers
compilation. Re-probe on the drive as the report asks.

## Summary
| Item | Verdict | Blocking fix |
|---|---|---|
| DEC | FIX-FIRST (decision 1 only) | capture the fit node's parameters at set-aside; restore from them (AppState+Lineage.swift:61,73; AppState.swift:1324; one test) |
| S15 | COMMIT | one line in the archive doc: the campaign metric keeps its key with a flipped sign |
| S18 | COMMIT | none; write the missing report/open-items entry; owner decides the v1.0.0-disks over-refusal |
| S22 | COMMIT | none |
