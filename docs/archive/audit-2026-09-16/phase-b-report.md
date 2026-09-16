# Phase B report — Hygiene slice (audit rows 1, 2, 3, 10)

Worktree: `$S/wt-b`, branch `audit/hygiene`, base `a960665`, commit `70901f6`.
Patch: `$S/phase-b.patch`. Logs: `$S/wt-b-logs/`.

## Row 1 — dedupe

`readinessAction`/`manualScaleRows` in `ExportSheet.swift` and `PrepareSettings.swift`
were byte-identical (after normalising two wrapped-comment words). Both now
call `UI/CalibrationReadinessRow.swift` (`action`/`manualScale`, `@ViewBuilder`
statics on an `enum`), passing `appState`, `kind`, `status`, and the one
string that differed between hosts (`qScaleUnavailableReason`). Each host
keeps its own `Form`/`Section` container unchanged. SwiftUI only, no AppKit,
no numeric `.frame` outside `LayoutPolicy`. No behaviour change.

## Row 2 — dead symbols

| Symbol | Evidence (whole-repo grep: bare word, `#selector(`, `\.name`, quoted string) | Deleted |
|---|---|---|
| `AppState.acomBackendSummary` | Only the declaration line (`AppState.swift:493`); no caller anywhere in `mac4DSTEM`, `mac4DSTEMTests`, `tools` | y |
| `Colormaps.shortDisplayName` | Only the declaration line (`Colormaps.swift:26`); no caller | y |
| `ResultExport.exportBraggPeaksCSV` | Only the declaration line (`ResultExport.swift:647`); no caller | y |
| `ResultExport.exportBraggVectorsEMD` | Only the declaration line (`ResultExport.swift:678`); no caller | y |
| `ZoomPan.isZoomedIn` | Only the declaration line (`ZoomPan.swift:38`); no caller | y |
| `AppState.availableComputedProducts` | Declaration (`AppState.swift:5006/5012`) **plus** `ResultPresentationTests.swift:85`, a real assertion (`XCTAssertTrue(state.availableComputedProducts.isEmpty)`) pinning actual behaviour, not a dead reference | n |
| `ProductWorkflow.recommendedNextArea` | Declaration (`ProductWorkflow.swift:691`) **plus** 3 call sites in `ProductWorkflowTests.swift:322,326,330` | n |

Raw grep evidence: `$S/wt-b-logs/task2-grep.log`.

`ProductWorkflow.swift` is unmodified because its one candidate symbol is
live, not dead — confirmed by the test call sites above.

**Live export path for Bragg peaks/vectors** (replacing the two deleted
functions): the session sidecar —
`ResultExport.saveCurrentResultToSessionSidecar()` / `saveSessionSidecarAs()`
(`ResultExport.swift:677,1055`), wired to File-menu commands in
`mac4DSTEMApp.swift:114,127` and to buttons in `ResultsWorkspace.swift:99` /
`WorkspaceView.swift:775` — call `BraggVectorEMDWriter.mergeResultMap` /
`mergeRGBAResultMap` to write detected Bragg vectors and result maps into
`<source>.mac4dstem.h5`. `ResultExport.exportScientificBundle()`
(`ResultExport.swift:385`, button in `ResultsWorkspace.swift:90`) calls
`BraggVectorEMDWriter.writeScientificBundle` for the coherent-fields export.
Both are py4DSTEM-readable EMD, satisfying README.md:70 ("Export — EMD Bragg
vectors, datacubes and products, readable in py4DSTEM"). The two deleted
functions (`exportBraggPeaksCSV`, a standalone CSV save panel;
`exportBraggVectorsEMD`, a standalone HDF5 save panel) were an unreachable,
superseded duplicate of this path — not the README's claim.

## Row 3 — stale comments

| File | Before | After |
|---|---|---|
| `tools/run-tests.sh:210-211` | cites `FormPolicy`/`WindowPolicy` (`FormControls.swift`) — none exist | cites `LayoutPolicy.swift` |
| `mac4DSTEMTests/StrainProductTests.swift` header | `App/StrainProduct.swift` | `Session/StrainProduct.swift` (the type's actual location) |
| `mac4DSTEM/Shaders/ACOMMatching.metal:4` | no `MUST match` comment | `// MUST match ACOMMetalParams in OrientationMatcher.swift (all 4-byte fields).` — matches the file-basename style of the 5 sibling shader comments (`VirtualAperture.metal`, `DPStatistics.metal`, `OriginMeasure.metal`, `VirtualDiffraction.metal`, `VirtualMask.metal`); confirmed true: `ACOMMetalParams` (`OrientationMatcher.swift:389-394`) has 4 fields, all `UInt32` |

Comment-only; no Shaders code changed.

## Row 10-lite — new tests, broken before trusted

Both new files include a header explaining tolerance/scope
(`MTLTextureFloatTests.swift`, `MetalEngineDispatchTests.swift`).
`MetalEngineDispatchTests` uses `accuracy: 1e-4` on a synthetic 2×2×2×2 cube
of small integers (<100): GPU and CPU sums are bit-identical in principle,
so the tolerance only absorbs a different GPU accumulation order, not a
wrong-pixel or wrong-count mistake (which would be off by whole units).

| Test | Mutation (worktree only) | Exit red | Exit green | Logs |
|---|---|---|---|---|
| `MTLTextureFloatTests.testFloatTextureRoundTripsExactValues` | `makeFloatTexture`: `bytesPerRow: width * stride` → `(width - 1) * stride` | 65 (only this test failed) | 0 | `mut1-red.log`/`.exit`, `mut1-green.log`/`.exit` |
| `MTLTextureFloatTests.testRGBATextureRoundTripsExactBytes` | `makeRGBATexture`: `bytesPerRow: width * 4` → `(width - 1) * 4` | 65 (only this test failed) | 0 | `mut2-red.log`/`.exit`, `mut2-green.log`/`.exit` |
| `MTLTextureFloatTests.testLUTTextureRoundTripsExactBytes` | `makeLUTTexture`: write region `MTLRegionMake1D(0, count)` → `(0, count - 1)` (last entry left unwritten) | 65 (only this test failed) | 0 | `mut3-red.log`/`.exit`, `mut3-green.log`/`.exit` |
| `MetalEngineDispatchTests.testVirtualDiffractionSumsOnlySelectedScanPositions` | `MetalEngine.virtualDiffraction`: `arrayFromBuffer(out, count: n)` → `count: n - 1` | 65 (only this test failed) | 0 | `mut4-red.log`/`.exit`, `mut4-green.log`/`.exit` |
| `MetalEngineDispatchTests.testDPStatisticsMatchesCPUMaxAndMean` | `MetalEngine.dpStatistics`: return tuple `(outMax, outMean)` → `(outMean, outMax)` (swapped) | 65 (only this test failed) | 0 | `mut5-red.log`/`.exit`, `mut5-green.log`/`.exit` |

Each cycle: mutate the source under test in the worktree → build+test the
one class (exit 65, and the log shows only the target test failed, siblings
in the same suite still passed) → `git checkout -- <file>` → `cmp <file>
<(git show HEAD:<file>)` printed no diff (clean revert) → re-run the same
class (exit 0). All mutations targeted `Core/Compute/MTLTexture+Float.swift`
and `Core/Compute/MetalEngine.swift` (not excluded directories) and were
never committed — confirmed by the final `git diff --stat` matching the
pre-mutation state exactly before staging.

## Build and full suite

- `build2.log` / `build2.exit`: app target build, exit 0.
- `test2.log` / `test2.exit`: `-only-testing` for `MTLTextureFloatTests`,
  `MetalEngineDispatchTests`, `StrainProductTests`, `ProductWorkflowTests`,
  `ExportProvenanceTests`, `ZoomPanClampTests`, `MetalLayerScaleTests` — all
  7 suites ran, 60 tests passed, 0 failed, exit 0.
  (Note: the earlier `test1.log` from the prior run omitted
  `StrainProductTests` from the `-only-testing` list; `test2.log` is the
  complete run task 5 asks for and is the one the commit cites.)

| File | Delta |
|---|---|
| `mac4DSTEM/App/AppState.swift` | 5461 → 5455 lines (-6) |
| `mac4DSTEM/App/Colormaps.swift` | -8 |
| `mac4DSTEM/Shaders/ACOMMatching.metal` | +1 (comment only) |
| `mac4DSTEM/Support/ResultExport.swift` | 1939 → 1856 lines (-83) |
| `mac4DSTEM/UI/ExportSheet.swift` | -111 net text lines (66-line `readinessAction` + 18-line `manualScaleRows` removed, replaced by an 8-line call) |
| `mac4DSTEM/UI/PrepareSettings.swift` | -99 net text lines (same dedupe, other host) |
| `mac4DSTEM/UI/ZoomPan.swift` | -2 |
| `mac4DSTEMTests/StrainProductTests.swift` | comment fix only (+1/-1) |
| `tools/run-tests.sh` | comment fix only (+2/-2) |
| `mac4DSTEM/UI/CalibrationReadinessRow.swift` | new, 122 lines |
| `mac4DSTEMTests/MTLTextureFloatTests.swift` | new, 93 lines |
| `mac4DSTEMTests/MetalEngineDispatchTests.swift` | new, 110 lines |

`AppState.swift` and `Support/ResultExport.swift` both shrank; neither grew.

## Gate D

Does not apply. Two triggers are "a change can move a scientific number" and
"the cause of a defect is not yet established" — neither applies: this slice
is dead-symbol deletion (verified zero-reach by grep, not by guessing),
an identical-body UI dedupe (byte-identical before and after, SwiftUI-only),
two corrected stale comments and one added comment (no code semantics
changed), and new test coverage (additive, each one proven to fail on a
real mutation before being trusted). No `Core/Analysis`, `Core/Crystal`,
`Session/`, threshold, or fixture file was touched, and `Shaders/` got only
the one comment line in `ACOMMatching.metal`.

## Not done / deferred

- Rows 4-9 and 11 of the ranked list (`tools/lib/harness.swift` dedupe, the
  `AppState` extraction continuation, `ResultExport`/`BraggVectorEMDWriter`
  splits, the Core helper consolidations, the `median` non-consolidation,
  and the `.agents/skills` mirror sync) are out of this slice's scope
  (rows 1, 2, 3, 10 only) and were not attempted.
- Everything in the assigned scope (rows 1, 2, 3, 10) is complete.

## Cleanup

`$S/wt-b-dd` deleted after this report was written (final step, per brief).
Disk before cleanup: ~4.2 GB free (above the 3 GB floor throughout).
