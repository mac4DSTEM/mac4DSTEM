# Lane F-C — independent refuter (Gate D: diagnosis reviewed, then the diff). 2026-10-01. Read-only.

Scope: rows 8, 25, 27 of docs/archive/v4/review-2026-09-30-findings.md; the diff of App/AppState+ResultPresentation.swift,
App/AppState+DiskDetection.swift, Session/LearnedDetection.swift and the three FCRow*Tests. Logs read: $SP/FC/test-1..5, mut-8/25/27,
core, inv; $SP/gate-FC/unit.log (1360 passed / 0 failed, GATE_EXIT=0; all three FC tests present and passed).
Caveat on evidence: the -quiet xcodebuild logs hold only "Test case … failed/passed" lines; the assertion TEXT (the stated red reason)
lived in the xcresults, deleted per RULES.md. The stated reasons are therefore verified below by tracing the test logic against HEAD,
not by the log. Each trace is deterministic (no timing), so I accept them.

## Row 8 — HOLDS WITH CORRECTIONS (the row's defect is fixed; the "other entry paths" question finds a pre-existing residual to register)
Reproduction: real. On HEAD the VD site merged `currentResultPersistenceMetadata.provenance` (ResultExport.swift:1627-1645 returns the
DISPLAYED product's provenance when `resultPresentation.product != nil`); the test puts a strain product on screen, sets the mode to
.virtualDetector (equivalent to `changeMode`, AppState.swift:1156-1165, which keeps the product) and runs → `source_product=strain_exx`
present → red for the stated reason (test-1.log: FCRow8 failed). Mutation M8 (re-merge) → mut-8.log: exactly that test failed. Green:
test-3a/4a, unit.log.
Fix: `publishProduct(kind:…, domain: .scan, sampling: own, extraProvenance: [quantitative_status, virtual_shape])`
(AppState+ResultPresentation.swift:304-314). publishProduct (AppState.swift:377-402) reads `currentScalarPersistenceMetadata` (mode-keyed)
and adds display_domain, quantitative_status, lineage_step. `resultPresentation.publish` = replaceProduct + one resultVersion bump
(Session/ResultPresentation.swift:99-107); HEAD did bumpResultVersion + replaceProduct = also one bump. No other behaviour moves:
same kind/name/units/sampling/status; provenance gains `analysis_mode` + `lineage_step` (as every other site) and loses nothing
(HEAD's no-product legacy chain was the same mode-keyed metadata, ResultExport.swift:1646-1662).
Other sites: `grep currentResultPersistenceMetadata` — remaining readers are export/save (ResultExport.swift:255/286/689/691/726,
AppState.swift:670), none publishes a product from it. "Only this site" confirmed.
Residual (pre-existing at HEAD, NOT a regression, beyond the row's claim): the provenance is now keyed by the CURRENT MODE, and three
entry paths run the VD site under another mode:
  - replay executor: `executeReplayStep(.virtualDetector)` sets shape + aperture and runs; it never sets `navigation.analysisMode`
    (AppState+Replay.swift:194-199; no `analysisMode` write anywhere in that file). A promote run replaying a virtual_detector step
    while the session is in .disks publishes the virtual image with `source_product=bragg_vector_map, coordinate_space=reciprocal`
    (ResultExport.swift:1510-1521); in .dpc/iDPC with a physical calibration it gets `quantitative=true` + the idpc keys.
    The same holds for every other replayed step (runDPC/strain publish through publishProduct too) — a general replay defect.
  - lineage rewind: same pattern (AppState+Lineage.swift:398-401), no mode write.
  - `runOpeningAnalysis` (OpeningAnalysis.swift:49-54): `needsVirtualImage` is TRUE only when `mode != .virtualDetector`
    (OpeningAnalysis.swift:24) — the opening virtual image in Prepare is BY DESIGN published under another mode's keys.
  The report's claim "applyDetectorPreset sets the mode first so it is fine" is right for that path only.
Corrections:
  C8-1 (small, in write-set, optional for this row): pin the two keys that are always true of this site in `extraProvenance`:
       `"analysis_mode": AnalysisMode.virtualDetector.rawValue` (and, if wanted, `"source_product": "virtual_<shape>"`). It cannot
       remove stray keys (coordinate_space, idpc keys), so it is a partial mitigation; say so in the comment. The FCRow8 test still passes.
  C8-2 (register, do not fix here — ADR 050: a new registration is a new item): "replay/rewind/opening-pass publish under the current
       mode's persistence metadata (publishProduct keys provenance by navigation.analysisMode; the executor never switches mode)".
       Fixture: record a VD step, change mode to .disks, replay → assert no `coordinate_space`/`bragg_vector_map`.

## Row 25 — HOLDS (deviation accepted; one test-strength correction, one note for the commit message)
Reproduction: real and forced, not timing-based. The seam `AppState.virtualDetectorBeforeLanding` (line 79, awaited at 288) holds the quiet
run for aperture A (outer 5) after its pixels exist; the commit run for B (outer 9) lands; A is released and on HEAD lands second →
image A overwrites B (different pixels for outer 5 vs 9 on the demo cube) and `record(kind:)` REPLACES the single virtual_detector step
with outer 5.0 (SessionReplayRecord.swift:85-97: one step per kind, replaced in place — so the row's "records aperture A" is exact:
the recipe's only VD step becomes A). test-1.log: FCRow25 failed; mut-25 (guard disabled): failed; green test-3b, unit.log.
Fix (AppState+ResultPresentation.swift:294-302): `if quiet, ap != aperture || shapeMode != resultPresentation.virtualShape { return .cancelled }`.
Race-free: after the two awaits (tiledImage, seam) everything to the landing is synchronous on the main actor (AppState is @MainActor;
publishProduct/recordReplayStep are sync), so compare-and-land is atomic against any other main-actor mutation of `aperture`/`virtualShape`.
"Two quiet runs sharing the same aperture": cannot be concurrent — scheduleLiveVirtualDetector allows one quiet run in flight (vdInFlight,
lines 81-90); the only concurrent pair is quiet + commit. Same aperture → both land the same image and the step is rewritten with identical
parameters (new date only) — identical to HEAD's quiet-run recording, which the report correctly calls harmless. Drag A→B while A is in
flight: A lands stale → .cancelled → the pending B runs (line 88). Drag A→B→A: A lands (correct), a redundant re-run follows. No image is
ever lost; no number beyond the row moves (quiet runs record on HEAD too; the guard only drops stale landings).
Deviation (equality guard vs request counter): accepted. The counter's owner is Session/ResultPresentation.swift (outside the write-set);
the guard is smaller and the outcome is the row's: the landed image and the recorded step describe the live aperture. Not covered (and not in
the row): a COMMIT run landing after a NEWER quiet drag still overwrites — the mirror race; the guard is quiet-only. Note it, do not widen.
Seam / AppState growth: `static var` closure, nil in production, in an extension file — not instance state, not counted by inventory
(AppState.swift + ResultExport.swift). It IS the first stored static in App/ (every other `static var` in App/Session/Core is computed);
precedent for a documented test seam exists in Core (LearnedDiskDetector.swift:70). Acceptable under "no AppState growth beyond a call";
the commit should name it. Test hygiene: tearDown resets it to nil (test line 18-20); if the test throws before `gate.released = true` the
held task spins on `Task.yield()` for the rest of the process (no deadlock — it yields — but a burning main-actor task). Minor.
Corrections:
  C25-1 (test strength): the test is blind to the mutation "quiet runs never land" (`if quiet { return .cancelled }`) — live-drag preview
       dead, test green. Add: assert `await quietA.value == .cancelled`, then run `runVirtualDetector(quiet: true)` at the LIVE aperture and
       assert `.published` with the step still `outer == "9.0"`. Break it with that mutation once.
  C25-2 (test hygiene, optional): release the gate in a `defer` (or in tearDown via a captured reference) so a failed XCTUnwrap cannot leave
       the spinning task behind.

## Row 27 — HOLDS
Reproduction: real and deterministic. Row's claim restated correctly: the run used `learnedThreshold` captured on the main actor before the
detach, the step recorded `learnedDetection.replayParameters(for:)` → live `threshold`. Test: 4×4 demo crop, learned class, threshold 0.5,
run; spin until `isBusy` (set in beginCancellableOperation, DiskDetection.swift:265, same main-actor turn as the capture at 272 — no await
between 265 and the detach); set 0.9 with no await before `await run.value`, so the run's record (which must return to the main actor)
cannot precede the write → recorded "0.9" on HEAD → red (test-1.log FCRow27 failed; mut-27 live-read: failed; green test-3c, unit.log).
Fix: capture moved from inside the do-block (HEAD :287) to :272 — between the two positions there is no suspension point (lines 272-287:
declarations and comments only), so the value the run uses is unchanged; passed as `threshold: learnedThreshold` (:364).
`replayParameters(for:threshold:)` (LearnedDetection.swift:268-274): nil → live. Callers (grep): AppState.swift:965 `settingsReplaySignature`
= the CURRENT settings' signature compared against the recorded step — live is the correct value there, so the nil default is right and
leaves no path recording a live value; the only recording site is :364. Tests DetectorTrainingFlowTests/LearnedDetectionSessionTests call
it without the argument — unchanged. Replay/rewind: ReplayPlan.swift:740 parses `learned_threshold` and the executor sets it before the
run, so captured == set; recording is suppressed when replaying anyway (AppState.swift:341).
Numbers moved: none shipped; the recipe's `learned_threshold` now equals the value the detector wrote into `detectionProvenance`
(LearnedDiskDetector.swift:598) — the two were inconsistent on HEAD only during an in-flight edit.
Residual (same mechanism, other keys, beyond the row — register if reachable, do not fix here): `learned_model_sha256`/`learned_model_*`
are still read live at record time (LearnedDetection.swift:275-280); `assetSHA256` is written at :137 (model set) and :211 (prepareForRun).
A model swap/adoption during Detect All would record the new model's hash for a run made with the old one. Whether the UI blocks adoption
while `isBusy` was not checked (LearnedDetection.swift has no isBusy guard).

## Overall: HOLDS WITH CORRECTIONS. Nothing refuted. All three reproductions are real and deterministic; each test goes red on its
## stated mutation (mut-8/25/27 logs: exactly the one test fails); no shipped number moves.
Must-fix before commit: none blocking.
Should-fix (small, in write-set): C25-1 (second assertion + its mutation), C8-1 (pin analysis_mode at the VD site).
Register as new items (not this lane): C8-2 (replay/rewind/opening-pass publish under the current mode's metadata — general, pre-existing);
row-27 sibling (model identity keys read live at record time); row-25 mirror (commit landing after a newer drag).
Commit message: name the static test seam and why it lives on AppState (owner file outside the write-set; nil in production).
