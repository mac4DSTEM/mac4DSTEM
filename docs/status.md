# Status

The one live status table. Updated in the same commit as the work it
describes; anything older than the current step moves to `docs/archive/`.
Numbers are quoted only from retained, dated runs. The per-increment log of
2026-09-02/03 is `docs/archive/v2/v2.5-log-2026-09-03.md`.

## Releases

| Version | State | Evidence |
|---|---|---|
| v1.0.0 | shipped 2026-08-06, signed and notarized | `CHANGELOG.md` |
| v2.0.0 | named 2026-09-02, never built, superseded by v2.5.0; a local tag exists on this machine and was never pushed, and none will be (C0 (4), `decisions.md` 2026-09-07) | `CHANGELOG.md` |
| v2.5.1 | released 2026-09-04, version/build 2.5.1 / 5 — macOS floor down to 14 and the sidecar-reader fix. Artefact built from `a9a0437`; app notarization `fb693c50`, DMG `f3d05e79`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `30282206…31af`, 6 157 051 bytes; the app inside the image declares `LSMinimumSystemVersion 14.0`, verified by mounting it. First release able to claim `run-tests.sh all` exit 0 (458/0/0, 44 harnesses). v2.5.0's artefact cannot launch below macOS 26, so this is the build that reaches older systems | `CHANGELOG.md` |
| v2.5.0 | released 2026-09-04, version/build 2.5 / 4 — the first shipped build of the SwiftUI rebuild. Gated on `unit` (457/0/0) + `package-test`, both exit 0; **`run-tests.sh all` was attempted and exited 1** on a pre-existing sidecar defect (`open-items.md`), and the notes say so. Artefact: built from `3c0a3eb`, app notarization `af7cc0f4`, DMG notarization `f4aa1d12`, both Accepted and stapled, `spctl` accepted; DMG SHA-256 `d55821a1…4c75`, 6 074 038 bytes. Build 3 (`df80e8e`) is superseded, kept as `mac4DSTEM-2.5-build3-superseded.dmg` | `CHANGELOG.md` |

## Where the UI stands

The v2.5 consolidation train and the presentation pass over the AppKit
window are finished and archived, with the window itself:
[`docs/archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md).
What that train left behind is the shape the app has now — `DSTEMCore` and
`DSTEMSession` packages, `DisplayedProduct`, `CalibrationSession`,
`ProductWorkflow.readiness`, `ACOMSession`, five workspace sidebars.

| Step | State | What it left behind |
|---|---|---|
| C4 slice 2: one enable logic | done 2026-09-07 night by a Sonnet agent, wiring only, no Gate D; two tests broken first (`scratchpad/pw-fail.log`, `sg-fail.log` exit 65 → `test-productworkflow-after.log`, `test-gates-nav-demo.log` exit 0), `xcodebuild build` exit 0 (`build1.log`); unit 495/0/1 (gate table); **unverified on screen** | `ProductWorkflow.mayRun(_:readiness:isBusy:)` is what every run button binds to (Compute Strain Map, Reconstruct Object, Prepare Parallax Preview, the toolbar action); `SessionGates.mayWriteSidecar` gates the five sidecar save/remove controls; `View.disabledWhileRunning(appState)` on the four settings panels disables every parameter while a run is in flight; "Update Image" is "Compute Image" and the dead "Reconstruction Ready" button is gone. 56 survey rows classified in the agent's report; the parallax stage buttons keep their in-memory sequencing checks, which `ProductWorkflow` does not model. `AppState` untouched |
| C4 slice 1: the four C3 presentation observations | done 2026-09-07 night by a Sonnet agent, presentation only, no Gate D; two new tests broken first (`scratchpad/statusbar-before.log` exit 65 → `-after.log` exit 0; `activitylog-before.log` → `-after.log`); unit 493/0/1 (gate table); **unverified on screen** | `LayoutPolicy.progressPercentWidth` (36 pt, measured against "100 %") reserves the status bar's percentage; the status message is one line, tail-truncated; the output log scrolls to its newest line on appear through `ActivityLog.scrollTarget(forCount:)`; `MapSettings.parameterSliderRow` shows title and value as two texts, which also fixes the two sigma sliders that shared it. `AppState` untouched. Not testable in the unit target, said plainly: the one-line truncation and the slider layout |
| C5, first extraction: the fit-verification overlays out of `AppState` | done 2026-09-07, unit + `core` green, six tests broken first (five mutations, all caught); **owner-verified on screen 2026-09-07 23:33** (light appearance, `sim_Au`: the fitted-origin cross on the central disk) (`scratchpad/drive/shots/`): on the demo fixture the red fitted-origin cross draws on the central disk in Prepare, the toggle removes it and brings it back, and it draws on the Mean pattern too; the yellow ring and dot that stay with the toggle off are the aperture control, not the overlay; no fit ellipse was drawn because the demo carries none; strain and ACOM overlays not reached (nothing computed) | `Session/FitOverlayPresentation.swift`: the origin/ellipse/strain-lattice/ACOM-template overlays as a value over a snapshot; `AppState.fitOverlays` builds the snapshot, `ImagePanes` reads the value. `AppState` 5 593 → 5 500 lines. The reopen boundary is pinned: a calibration restored through `SessionCalibrationTranslation` draws the same origin and ellipse as the live one. Not exercised: the ACOM template path beyond its gating (no `OrientationPlan` fixture in the unit target). The rule itself: `inventory` fails when `AppState.swift` + `ResultExport.swift` exceed their count at HEAD (HEAD^ on a clean tree) — broken first by a 100-line append (`inventory-c5-broken.log`) |
| Bullseye: flat measured-kernel mode + the file's probe as a kernel source | done 2026-09-05, Gate D diagnosed, Gate B passed with findings applied, **agent-verified on screen 2026-09-07** (`shots-c3/a9-strain.png`: Measured kernel mode "Flat", "Use File's Probe"; detection on the demo 9/9 per pattern, 1 296 peaks) | `ProbeKernel.flat` = py4DSTEM `get_probe_kernel_flat` (normalise, Fourier-shift the centre to the corner; DEVIATION: a non-finite pixel counts as zero), `ProbeKernelMode` on every kernel and in both provenances, `.fileProbe` with `probePath`; `FourDDataSource.probeCandidates`/`readProbe` read the legacy (Qx, Qy, N) and the modern (2, Qx, Qy) `Probe` layouts, slice 0 either way. Parity on the bullseye file: 878/878 and 164/164 peaks with py4DSTEM's flat route at two thresholds, both sides pinned to (125, 125) (`scratchpad/parity/compare-0.05.log`, `-0.1.log`); the kernel at the app's own probe centre matches to 3e-6 (refuter's `refute-bullseye/flat/compare-pristine2.log`). Refuter's findings applied: two mutations survived every shipped check — an unwrapped frequency index (passed the integer-centre fixture and the parity) and a dropped conjugation (correlation became convolution; every radially symmetric check blind) — now caught by the fractional-centre/conjugate-transform fixture (`flat_kernel_fractional_centre`, 4.5e-8 / 6.7e-7) and an asymmetric unit test; the modern Probe layout was refused, now read (`p3` fixture); the UI defaulted to the trench, now flat; the stated mechanism corrected (the trench fails at the ESTIMATOR'S radii, not on bullseye probes as such). Mutations retained: five (mut2), four (mut3), two unit-suite (`unit-mutation-M1-20260905.txt`), all caught. Unit 485/0/1 (486 cases, MCP, `unit-mcp-flatkernel2`). `AppState` gained `generateFileProbeKernel`; nothing moved out. Not exercised by any check: the AppState glue itself (an x/y swap there would be invisible) |
| Detection threshold: the one-peak warning names the knob; the default is measured, not moved | done 2026-09-05, controls agent-verified 2026-09-07; **owner-verified 2026-09-07 23:38** that a high Min relative (0,5 %) on `sim_Au` yields a warning in the preview ("the selected reference-peak rank is absent in this pattern; the relative filter cannot be evaluated", 37 candidates → 0 accepted); the full-scan summary's own wording is not in that screenshot | `DiskDetectionScanSummary` carries the run's `parameters`; the median ≤ 1 warning names Min relative intensity (value, reference peak, both remedies) instead of "spacing or thresholds". One test, failing first on the old text (MCP log 18:22, passing 18:24). `AppState` touched at one call-site argument only — no responsibility moved out, said plainly. The `relativeToPeak` 0 → 1 default question is REFUTED by measurement on six training cubes (`det-experiment-20260905.log`, closure in `closed-items-2026-09.md`): WS₂ 1 → 45 peaks/position where ~13 are disks, sim_Au 3 918 and MgO 12 357 positions at the 70 cap — the reference collapses wherever the second peak is weak. Default unchanged; item closed. New observation: twisted bilayer graphene finds one peak at either reference (`open-items.md`). Unit 479/0/1 (480 cases, MCP route, `unit-mcp-detection-20260905.json`) |
| Origin measurement: the CoM window iterates and never cuts the beam's edge | done 2026-09-05, Gate D pre-registered (prediction met to 0.001 px), Gate B passed with findings applied | `measureOrigin` recentres its window on its own estimate (≤ 4 passes) in max(r·rscale, r + 1.5 px); DEVIATION from py4DSTEM's single pass noted in the kernel. WS₂ at the shipped rscale: 63.986 → 63.7375 against an independent 63.738. The refuter's numpy twin over ten training cubes: new values within 0.02 px of a wide-window reference on every clean cube, the old ones 0.25–0.8 px off; the shift depends on the beam's place in the block grid, not disk size (`q-calibration-design.md` §9, which corrects the "~0.3 px, small beams only" claim). `origin_measurement_truth` at 0.02 px (six mutations, the bounding-box clip survived 0.05 px); two-spec P4 equivariance tightened 0.65 → 0.001 px. Every origin-derived number can move, up to ~0.8 px mean on the training set — a v2.6.0 change |
| Q-calibration (a): the same-shell cluster mean replaces the per-pattern minimum | done 2026-09-05, Gate D pre-registered, Gate B passed with the mechanism corrected | `KnownCrystalQCalibration.estimate` averages the innermost shell's equivalents (band = derived separation capped at 8 %), both shells; `sameShellPeaksPerPosition` reports k. WS₂: cluster 18.902 px vs 18.901 from the independent 11-20 shell; the minimum was one spoke of a 0.26 px origin-fit offset (new open item). sim_Au: the reference shell is item (b)'s problem and Friedel pairs differ 2.4 %, so no truth claim there. `q-calibration-gate-test` 79 checks, 14 mutations; the scratch experiment harness and the refuter's dumps are in the scratchpad |
| Science lane: probe refusal, ACOM origin snapshot, selected-area fixture, CIF fingerprint | done 2026-09-05, Gate B passed with findings applied | `probeSize` → nil, `OriginCalibrationError.probeNotMeasurable`, finite-only at every step, `np.median` parity; `ACOMRunSemantics.originProvenance`; `selected_area_diffraction_partial_rows` with `2^scan` values and a 1 × 2 region (ten mutations, refuter's row-reversal included); `CrystalModel.contentFingerprint` recorded as `material_fingerprint`, `resolveMaterial` refuses a different CIF under a shared id. Refuter report and every mutation log in the scratchpad; closures in `closed-items-2026-09.md` |
| UI-review label findings (b)(d)(e)(f), minors, `PaneSplit` (a)(c) | done 2026-09-05, **agent-verified on screen 2026-09-07** except (f) staleness, which no drive has yet made stale (`shots-c3/a1-launch.png`, `a3b-narrow.png`, `a4b-divider-back.png`: "Virtual detector · Annulus · Relative" label, colorbar with range and units, cursor readout `1.159e+04`, scale bar `5 px` only while Q is Not set, headers overflow into ••• and the divider survives a Results round trip) | Pattern statistics named for what is on screen (`PatternSourceLabel`); comparison panels carry a `Colorbar` (range, units, zero mark, masked swatch); cursor readout at four significant digits; ONE staleness verdict (`TaskProductState`, `ProductWorkflow.productState`) on the sidebar, the inspector and the strain/ACOM maps; scale bar never prints a unitless sampling as px (`ScaleBar.footerSampling`); no kernel → cross markers, not a 3 px circle (`PeakOverlayGeometry.radius` is optional). Both pane headers are `ViewThatFits` with an overflow menu; the divider fraction is `@SceneStorage`. Six unit tests, each broken first |
| DM4 Gatan STEM-SI import | fixed 2026-09-05, reviewed and reworked the same day; owner's GMS observation and re-drive owed | Empty positional labels resolve by physical sibling index (ncempy's rule, confirmed against ncempy on the real file); calibration domains distinguish detector-fastest from scan-fastest storage. `Si-SiGe.dm4` discovers as scan 77 × 17, detector 448 × 480, uint16, 2 nm / 0.06208537 1/nm — the roles are proven by the units and the survey rectangle; **the detector pair's x/y order is not** (`open-items.md`, Gate D). Review rework: full-cube read 19 s → 0.94 s (blocked transpose), undecidable units open the file without pixel sizes instead of refusing it, detector-fastest DM4 reports `.scanOnly` pushdown again, py4DSTEM's TitanX roll recorded as unported. Probe log `scratchpad/dm4-probe-20260905.log`. **Evening:** the `realslices` refusal its own harness check demanded (`read_v0_12.py:373-388`) was never in the reader — a legacy strain stack opened as a cube with a 4-px detector; the rule now names both v0.12 slice collections and `datacube-discovery-test` is green again |
| UI rebuilt in SwiftUI, and the old one retired | done 2026-09-04 | `UI/` IS the SwiftUI rebuild: the AppKit-hosted window's 32 files are deleted, the `UI2/` folder and the `UI2` type prefix are both gone, and no flag selects a UI. Contract in `architecture.md` "The UI contract", three of its rules pinned by an `inventory` grep (`HSplitView`/`VSplitView`/`NSSplitView`/`NSSplitViewController`/`import AppKit`, mutation-tested both ways). Shape, drive calls and the retirement in `decisions.md` (2026-09-04). The launch crash is fixed (`PaneSplit`) and gated; its mechanism was refuted here and then DEMONSTRATED later the same day by the status-bar revert (`open-items.md`, the constraint-loop entry), which made the two probes named at the time moot (`open-items.md`). Cost of the retirement: 27 tests deleted, every one pinning the AppKit column shell; six repointed. Five renames were not bare strips (`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`, `PatternFitOverlay`) — reasons in `architecture.md`. The status bar's elapsed/throughput/ETA was added and REVERTED the same day: its per-second `.fixedSize()` text crashed the app on a real dataset and, in doing so, demonstrated the constraint-loop mechanism that had been refuted-but-unestablished (`open-items.md`) |
| Status bar: elapsed / throughput / ETA, rebuilt in a reserved slot | done 2026-09-04, **agent-verified 2026-09-07 with one finding** (`shots-c3/a5-running.png`: the slot holds `0 s` and the progress bar; the `%` label wraps onto a second line — `open-items.md`; the demo run is sub-second, so throughput/ETA were never on screen) | `LayoutPolicy.operationMetricsWidth` (190 pt, constant) is the slot; the text truncates inside it and never resizes it. `OperationMetricsFormat.line` composes the line for both surfaces. `StatusBarMetricsTests` (4 tests, each broken first) measures the widest line the formatter can produce — an hour elapsed, an hour of ETA, 999.9 units/s — against that constant in the same font. The sibling `status.footer.facts` lost its `.fixedSize()`: it was breaking the same rule already, on every progress update, before the metrics line existed (predicted, not observed). Only a real dataset exercises the one-second tick |
| The output log moved off `AppState` | done 2026-09-04, **agent-verified 2026-09-07** (`shots-c3/a6-log.png`: the run's lines are there; the panel opens scrolled to its top — `open-items.md`) | `ActivityLog` (`App/ActivityLog.swift`) owns the strip's buffer: the filter, the no-repeat rule, the 300-line cap and the stamp, on an injected clock. `AppState` 495 → 494 stored properties. `@Observable` on it is load-bearing — with the annotation removed, five of its six tests still pass and the strip silently stops updating, which is why `ActivityLogTests` asserts the chain with `withObservationTracking` (the repo's first). Toggling the log from the status bar is the five-second check |
| Saved-session sidecar contents moved to the LEFT sidebar | done 2026-09-04, **rows agent-verified 2026-09-07** (`shots-c3/b3b-sidebar.png`, `b3d-reopened.png`: filename row, Calibration, Change…, Ignore… in the Session section, back after reopen); **Remove owner-verified 2026-09-07 23:33**: right-click on "DPC magnitude" shows "Remove DPC magnitude" (beside the system's Ask Siri item) | `Section("Saved session sidecar")` is gone from `WorkspaceInspector`; the sidecar filename, Calibration, BraggVectors, the saved-result rows, Apply Saved Controls and Change…/Ignore… render in `WorkspaceSidebar`'s `Section("Session")`. Info keeps only the unreadable / does-not-fit sections — the explanation half of the split. Builds clean with no warnings and no test names the moved identifiers, which is also the limit of what any gate can say: this is placement, and only the owner's eyes close it. One judgement call to overrule or keep — Remove is now the result row's context menu, not a second visible row per result (`open-items.md`) |
| 5 The owner's full drive | owner | — |

## Last gates (retained logs)

| Gate | Result |
|---|---|
| `run-tests.sh unit` | **exit 0 — 2026-09-07 night, the C4 slice-2 tree** (`scratchpad/unit-c4s2-20260907.log`): **495 passed / 0 failed / 1 skipped, 496 cases** (496 `func test` in source). Earlier the same night: 493/0/1 on the slice-1 tree (`unit-c4s1-20260907.log`); 491/0/1 on the C5 tree (`unit-c5-20260907.log`), 485/0/1 on the C2 tree (`unit-20260907.log`). The script's own `xcodebuild test` line run directly because the 8 GB preflight refuses at ~4 GB free. |
| `run-tests.sh scientific` | **43 harnesses, exit 0 — three runs on 2026-09-07 (C2)**: the tree before the harness rewrite (`scratchpad/scientific-before-20260907.log`), after every runner was pointed at `sources.manifest` (`scientific-after-…`), and after the `mktemp` tagging (`scientific-final-…`); each 43/43, `GATE_EXIT=0` on its own line. `PYTHON` resolved by `tools/lib/python.sh`. The six diagnostics that are not in the gate were type-checked against their new groups (`typecheck-*.err`, all empty). Previous: 43/exit 0 on 2026-09-05 (`scientific-bullseye3-20260905.log`). |
| `run-tests.sh core` (both packages) | **exit 0 — 2026-09-07 late evening, the C5 tree** with `Session/FitOverlayPresentation.swift` (`scratchpad/core-c5-20260907.log`). Previous: `b91f5bb`, 2026-09-03 |
| `run-tests.sh inventory` | **exit 0 — 2026-09-07 night, after the owner deleted the stray `tools/disk-detector/__pycache__`** (`scratchpad/inventory-owner-20260907.log`): every runner classified or explained, `AGENTS.md` in sync, `AppState` + `ResultExport` 7 531 against 7 624 at HEAD (the rule fired on a 100-line probe, `inventory-c5-broken.log`). Counts: gated 45, diagnostic 9, owner-only 0, support 2; live markdown 4 677 (4 620 at C1's end, the append-only decision entries; 5 701 at the morning baseline); cold-start set 884 (888). Previous: exit 1 on the same cache directory through C1, C2 and C5 the same day. |
| `tools/package-test/run.sh` | **exit 0 — 2026-09-04.** Clean-builds a hardened Release and audits the artefact: nested signatures, sandbox/read-write/bookmark entitlements, no `get-task-allow`, no Homebrew dylib paths, embedded HDF5 2.1.1 opening a checked-in fixture, and identity/version `2.5 (4)` with the deployment floor — both DERIVED from the project. The floor assertion and its success message were both literal `26.0` and both wrong after the floor moved; the message said "macOS 26 floor" while passing against 14.0 |
| `run-tests.sh all` | **exit 0 — 2026-09-04, post-release tree** (458 passed / 0 failed / 0 skipped, 44 harnesses, `real-data-acceptance` and `package-test` included). The release-tree attempt exited 1 at `real-data-acceptance`; that sidecar instance was diagnosed and closed as a stopgap then, and the wider discovery class was subsequently closed on 2026-09-05. Two recorded traps hit again: the background task's exit code was 0 while the gate's own `GATE_EXIT` line said 1, and the unit count read one short because an xcodebuild timestamp interleaved mid-test-name — reconciled against the source file's method count, never assumed |

## The v2.5.0 / v2.5.1 release night

Both shipped 2026-09-04; the plan, its two self-corrections and the artefact
provenance are
[`docs/archive/v2/release-2026-09-04.md`](archive/v2/release-2026-09-04.md).
The live facts are the Releases table above and `CHANGELOG.md`.

## Handoff (rewritten 2026-09-07: consolidation first)

**Consolidation first (owner, 2026-09-07).** `docs/consolidation-plan.md` is
the next target's source until it is archived: `/pickup` takes the first gate
of its §6 whose exit criterion fails — **next for an agent: C4 (b), staleness
(item 1's C4 paragraph); C6's four steps are yours.** C0 closed and **C1 (docs truth) and C2
(hygiene) were executed 2026-09-07**, C1 and C2 uncommitted together on
`main` (commit when asked). **Next: C3 is the owner's drive** (item 1 below)
and C4 waits on it. **C5 executed the same evening** (the rule in
`inventory` and `CLAUDE.md`; the overlays extracted); its standing part is one
extraction per month in the plan's §4 order — next the `OperationCenter`
forwarders. **C6's Python side was executed the same night on a worktree of
`ml/disk-detector`** (uncommitted; patch and worktree path, the gate logs,
the numbers and your four steps with their commands are in
`archive/v3/learned-detector-2026-09-06.md`, "C6 — the table"). Headline:
at the shipped 0.9 the exported asset scores fixture 0.939 / 0.896 against
the classical 0.900 / 0.866 on the same visible truth, and **validation
0.679 / 0.939** (0.963 was at 0.3); WS₂ counts-scaled makes the net propose
~24 spots per position, unjudged. Owed: your labels, the evaluation with
`--asset --labels`, the 256-px retrain (needs one agent session first: `S` is
128 everywhere — evidence file, step 3), the verdict. After that C7 only if
the verdict says so; otherwise C5's next extraction. **C1 closed by the owner the same night:** the stray cache directory deleted (`inventory` exit 0) and the branch commit `219ae54` on `ml/disk-detector` carrying the C1 strike and C6's Python side (unpushed). `References/py4DSTEM-dev` had lost its working tree (220 files
deleted, `.git` intact); `git checkout -- .` there restored the lock. No
feature work until C4 and C6 exit. The owner pushes; agents commit when
asked and never push.

v2.5.1 is published and verified from its own download link. Both repos are
pushed; the site says macOS 14+ and serves the build that can honour it. Push
state is not recorded here — it went stale twice in two commits; ask git.

**Read this first: item 1 is the owner's and `/pickup` cannot take it.** An
agent should say so and start at item 2.

1. **Your drive. (OWNER ONLY.)** Nothing beyond Prepare, Imaging and Strain &
   ACOM has been looked at since the AppKit retirement, and five sessions
   running have found defects by driving that every gate was green through.
   Bugs enter via `/diagnose`. Worth going at first: Phase's stages, the load
   configurator's crop drags, the Results comparison row, the colorbar popover,
   and every divider — the pane split is hand-built and **no gate can see a
   column's width** (falsified, `open-items.md`). **C3 was delegated to an
   agent drive on 2026-09-07 (`decisions.md`; report `scratchpad/drive/c3-report.md`,
   40 screenshots), and the owner closed it at 23:33–23:38 with four
   screenshots on `sim_Au`:** light appearance reads correctly, Remove is in
   the Session row's context menu, a cropped session reopens on its crop
   (scan 90×51 at (3, 15); the whole-file calibration correctly refused for
   that view), and a high Min relative yields a warning. Findings from the
   drive are in `open-items.md`. **C3 is closed.**
   **C4 started 2026-09-07 night, slice 1 (presentation only, no Gate D):
   the C3 observations — the status bar's `%` wrap and its text wrapping at
   narrow widths, the log opening at its top, the "Correlation power," label —
   landed and gated (the table row). Slice 2 in flight the same night: one
   enable logic (`ProductWorkflow.readiness` for every run button, parameters
   disabled while their run is in flight, "Update Image" and "Reconstruction
   Ready" gone) landed too (its row). **Next slices, in the plan's order:**
   (b) staleness generalised — the map is `scratchpad/c4-staleness-map.md`
   (Haiku, 2026-09-07): one verdict engine already exists
   (`ProductWorkflow.productState`, `.staleDiskSettings` for the three
   disk-dependent modes, three UI surfaces reading it, one test); every task
   already records its parameters in a replay step and every product carries
   a provenance dictionary, so the signature to compare is "the replay step
   this product was made from" against "the step the current parameters would
   record" — build that comparison beside `productState`, not in `AppState`
   (its seven publish sites must not grow: pay each added line there with a
   deletion); (c) the one
   exposure rule (Advanced sections, contrast/gamma and the four actions to
   Settings, sidecar actions to a Dataset menu, the Imaging pane-tap side
   effect, the four silent failures to the status strip, Remove and the two
   Resets confirming). Then your drive of every panel is C4's exit.**
2. **Two owner observations, both on `Si-SiGe.dm4` and Prepare**
   (`open-items.md`): open the file in GMS and read the pattern's width and
   height (the detector-pair Gate D item), and drive the manual Q/R fields
   after their rows turn green, in Prepare and in the export sheet.
3. **Drive the UI-review fixes and the pane headers** (`open-items.md`):
   the four label findings, the two minors, the compressible headers and the
   remembered divider all landed 2026-09-05 with tests and no screen time.
4. **The science lane, one item at a time — nothing here until C4 and C6
   exit.** What landed 2026-09-05 through Gate B is in
   `closed-items-2026-09.md` and `q-calibration-design.md` §8–9. Still open:
   the probe-size under-read on ring-shaped probes and the owner's drive of
   the bullseye maps; ACOM coverage (a) is an owner decision, relabel or
   convert; Q-calibration (b) and the origin-fit holes (b)/(c) as design
   passes. A landed number change cuts v2.6.0.

**macOS 14–25 is compile-verified, never executed** (every machine here is
26; a VM needs ~40 GB); the first report from an older system is the test.

**The rule bought the hard way** (`open-items.md`, the constraint-loop entry):
nothing inside a split column may repeatedly change its own minimum size.
`.fixedSize()` on text whose string changes is the easiest way to do it by
accident, and it only shows on a dataset big enough for an operation to tick.
All 12 bare `.fixedSize()` sites in `UI/` are audited and contained.

**Two traps (hit again 2026-09-07):** read the gate's own `GATE_EXIT` line,
never a wrapper's; reconcile the unit count against `func test` in source.

**Driving:** `open -n <Debug app> --args --demo-fixture`; per-window `screencapture -x -o -l <id>`.

## Owed to the owner

- Nothing on screen: C3 closed 2026-09-07. C6's four steps and the commit/push of what lands next.
- The §10g decisions and plan §8 (sidecar wire format).
