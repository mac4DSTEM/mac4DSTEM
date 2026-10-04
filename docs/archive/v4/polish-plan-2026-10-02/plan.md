# Slot 4⅞ — the polish plan before v4.1.0 (explored 2026-10-02; to run in the next session)

Six read-only Sonnet mappers checked every rough edge left after the pre-release review against HEAD `3bc115ae` (`map.json`: file:line,
mechanism, fix, effort, Gate D, test hint, UI cost per item). The owner's calls are on one sheet
([`../owner-decisions-2026-10-02-polish.json`](../owner-decisions-2026-10-02-polish.json), cards Q1–Q4, Q6, Q7, with an independent second opinion; Q5 became a plain fix).
Owner directive (2026-10-02): sheet first, lanes in parallel, Sonnet 5.5 implementers. The repo's rules hold: tests broken first,
an independent (Fable) refuter per lane, each lane gated alone on an isolated copy of HEAD + the lane, commit by explicit paths.

## Lanes (disjoint write-sets; run in parallel)

### N — number entry (Gate D)
Sonnet implementer; Fable refuter on the DIAGNOSIS (reproduce on screen first: Use Parallax Fit → switch rooms → Defocus and provenance rounded). Test-first in NumberEntryCommitRuleTests. Then delete the two compensating patches. Gate: unit + core + build.

- **P1** — `mac4DSTEM/UI/InspectorRows.swift:749 (shown), :755 (blur commits), :760 (.onDisappear(perform: commit)), :782-789 (commit), :796-802 (resolve; the only guard is`  
  The field's text is always the FORMATTED value (`shown`, :749). commit() runs on blur (:755), on Return, and on .onDisappear (:760) even if nothing was typed. It feeds the shown text to resolve(), which parses it and calls onCommit whenever the parse differs from the stored value (:800). So whenever the format shows fewer digits than the stored value has, merely focusing and leaving the field, or leaving the room or  
  *Fix:* Fix once, in resolve(): before parsing, return .keep when the trimmed typed text equals the shown text of the current value (`if let current, typed == entry.format(current) { return .keep }`). An unedited field then never commits, wherever its format rounds. A typed text that differs from the shown text still parses and commits as today. Then delete the two compensating patches as dead weight: AppState.isUnchangedMan  
  *Test:* In DecimalEntryFormatTests.NumberEntryCommitRuleTests: with a fractionLength(0...1) entry and current 123.456, `resolve(typed: "123,5" /* the shown text */, current: 123.456)` must be .keep (it is .set(123.5) today, red before the fix). `typed: "123.6"` must s  
  *Cost:* n/a (0 rows, 0 pt) · *effort* S (about 5 lines in resolve + 3 tests; patch removal is anot · Gate D: yes

### V — export voltage (Core, Gate B)
Sonnet implementer; Fable refuter. Writer + both doors + one shared eV→kV normaliser; round trip test (export → reopen reads the voltage). Gate: unit + core + build + scientific (preprocessing-export-test, scientific-bundle-test).

- **P10a** — `Core/Data/BraggVectorEMDWriter.swift:237 (writeCalibratedDataCube signature) and :1616-1623 (file-root attributes; no voltage written anywhere in the file); Sup`  
  The voltage is held outside PixelCalibration (calibrationSession.acceleratingVoltage; PixelCalibration has no voltage field, FourDDataSource.swift:68-72). Both doors hand the writer only a PixelCalibration, so the writer has nothing to stamp. The grep for 'voltage' in BraggVectorEMDWriter.swift returns nothing. On reopen, activate() reads the root attribute 'accelerating_voltage' (AppState+Open.swift:491). It is abse  
  *Fix:* 1) Add `acceleratingVoltageKV: Double? = nil` to writeCalibratedDataCube (a defaulted parameter, so the ~12 tools/tests callers still compile). In writeCalibratedDataCubeFile, after 'authoring_user' (:1623), if it is finite and > 0, call the existing writeScalarAttribute("accelerating_voltage", value: kv, type: h5.nativeDouble, on: fileID) (same helper as version_major at :1617). The value is in kV, which the reader  
  *Test:* Round trip in PreprocessSheetModelTests style (next to the raw/open bit-identity test, :200-210): write with acceleratingVoltageKV 300 -> H5Reader.readDoubleAttribute("accelerating_voltage", onObjectPath: "/") == 300; nil, 0, NaN -> attribute absent (reader re  
  *Cost:* n/a (0 rows, 0 pt) · *effort* S-M (Core writer + two call sites + a shared normaliser + 3  · Gate D: no

- **P10c** — `mac4DSTEM/UI/PreprocessSheet.swift:277-297 (write() and beginWrite() never call PendingEdits.commitAll); :161-163 (hot-pixel Threshold is a NumberEntryField); A`  
  Found while tracing P10; not in open-items. Every other work-starting action goes through PendingEdits.run so a typed-but-uncommitted field is committed first. The Preprocess sheet's Write button does not: write() goes straight to beginWrite() -> writePreprocessed, which reads pending.preprocess. Type a new Threshold (say 20) and click Write with the mouse: the field still has focus, so the edit is only registered in  
  *Fix:* Add `PendingEdits.commitAll()` as the first line of PreprocessSheet.write() (before the readiness check, so the alert path is covered too). Nothing else changes.  
  *Test:* Reproduce first: open Preprocess, enable Filter hot pixels, type 20 in Threshold, click Write, then read the written file's hot-pixel provenance (or the 'N hot pixels replaced' count against threshold 8 vs 20). Unit: register a PendingEdits closure that sets p  
  *Cost:* n/a (0 rows, 0 pt) · *effort* XS (1 line + 1 test) · Gate D: yes

### S — session safety and wording
Sonnet implementer; Fable refuter. P3a per card Q2; P5a per card Q4; P3b: removal must not clear an unsaved displayed product (trace removeSavedSessionResult's tail). Gate: unit + core + build.

- **P3a** — `App/mac4DSTEMApp.swift:198-200 (menu item); App/AppState+Open.swift:252-259 (reopenIgnoringSessionSidecar) and :1006-1011 (one-shot skip in loadSessionSnapshot)`  
  The command calls reopenIgnoringSessionSidecar(), which sets ignoreSessionForDatasetID and calls openRecent -> openFile -> openFileAsync. That path replaces the window's dataset: it re-runs activate, so every in-memory product goes (disk detection / braggVectors, displayed result, strain/ACOM/phase maps, unsaved calibration edits, the unsaved replay recipe). The only difference from a plain reopen is that loadSession  
  *Fix:* Always confirm; do not build an unsaved-work predicate (a wrong 'nothing to lose' answer would lose data silently, and the command is rare). (1) Split the entry: AppState.reopenIgnoringSessionSidecar() keeps its name and callers (so the frozen inspector button needs no edit) but only sets sessionSidecar.confirmsIgnore = true, with no reopen. (2) Add a new func confirmReopenIgnoringSessionSidecar() holding the current  
  *Test:* AppStateTests-style: with a dataset held and a recents entry, call reopenIgnoringSessionSidecar() and assert ignoreSessionForDatasetID == nil, sessionSidecar.confirmsIgnore == true and no load began (datasetSession.isLoading == false). Then call confirmReopenI  
  *Cost:* 0 rows, a modal dialog only · *effort* S, about 30 lines in 3 files, no Core change · Gate D: no

- **P3b** — `Support/ResultExport.swift:1015-1022 (tail of removeSavedSessionResult); related: :794-834 selectSavedSessionResult, App/AppState.swift:372-385 publishRestoredP`  
  After the file rebuild, removeSavedSessionResult rereads the inventory and then ALWAYS replaces the displayed product. Either it calls selectSavedSessionResult(<the file's current result>), or, when none is left, it runs resultPresentation.replaceProduct(nil) plus bumpResultVersion() (:1020-1021). Nothing asks whether the removed item was the one on screen. resultPresentation.product is the single slot that Results a  
  *Fix:* Capture let wasShown = resultPresentation.product?.origin == .restoredFromSidecar && sessionInventory.currentResultID == saved.id BEFORE the await. After the rebuild, run the existing if/else (:1016-1022) only when wasShown. Otherwise leave the product and resultVersion alone. Put the predicate in a small static on SessionGates (or ResultPresentation) so it is testable without AppState: removalDisplacesDisplay(displa  
  *Test:* Extend ReviewOwnerCardsTests / SessionGatesTests, which already remove against a real sidecar: write a sidecar with one result, publishProduct a computed virtual_detector image, call removeSavedSessionResult, and assert resultPresentation.product?.origin == .c  
  *Cost:* 0 · *effort* S, about 10 lines plus 2 tests · Gate D: no

- **P5a** — `UI/WorkspaceSidebar.swift:296-309 (call site; detail = gates.sidecarRewriteRefusal() ?? 'Session: … · loaded: …'), :311-326 (warning(): detail .lineLimit(3) at `  
  Two defects in one helper. (1) Truncation: the detail is Text(detail).font(.caption).lineLimit(3). In the mismatch case the detail is the full rewrite refusal ('The session sidecar holds “X”, computed on another view… (saved: … · loaded: …). Saving now would relabel it… Reopen the dataset — a plain open restores the saved view — and save there, or remove “X” in Results first.'), about 350 characters. At sidebar width  
  *Fix:* In WorkspaceSidebar.swift only (not frozen). warning() takes two strings, shown and help. For the three branches, show one short line that carries the remedy first. Mismatch with a refusal: 'Saving is off here. Reopen the dataset, or remove the saved result in Results.' Mismatch without a refusal: keep 'Session: … · loaded: …'. Unreadable: 'mac4DSTEM has not been given access. Choose Allow Access… below.' (see P5c).  
  *Test:* Pure test on a new SessionSidebarWording.warningLine(refusal:, views:) (or the equivalent): given a long refusal it returns a string under 120 characters that contains 'Reopen' and 'remove'. Plus an inventory grep that 'The Info tab carries the full explanatio  
  *Cost:* 0 rows (stays at 3 caption lines) · *effort* S, about 15 lines; put the short strings in SessionSidebarWo · Gate D: no

- **P5c** — `App/AppState+Open.swift:1059-1062 (loadSessionSnapshot catch); App/AppState.swift:1348-1363 (recordedLoadSpecification .unreadable); Session/SessionSidecarLocat`  
  On every open, the sidecar is read twice and the unreadable warning gets two writers. First, recordedLoadSpecification (called at AppState+Open.swift:357) classifies the error with SessionSidecarReadFailure.classify (errno = 1 means .notPermitted) and calls sessionSidecar.noteUnreadable with the classified text ('… has not been granted access …'). It also sets the gate with that same message. Then activate runs loadS  
  *Fix:* (1) Add one pure static on SessionSidecarReadFailure, e.g. reason(sidecar:error:) -> String. It classifies and returns the explanation for .notPermitted; for .unreadable it returns 'Could not restore X: <errorDetail>'. Both writers (AppState.swift:1348 path and AppState+Open.swift:1059) call it, and the raw detail also goes to activityLog.record for diagnosis. (2) Reword the .notPermitted explanation: '… has not been  
  *Test:* Pure tests in SessionSidecarLocatorTests: reason(sidecar:error:) for a SimpleError containing 'errno = 1,' contains 'not been granted access' and 'Allow Access' and does NOT contain 'HDF5' or 'errno'; for errno = 13 it keeps the raw detail. Break it by returni  
  *Cost:* 0 · *effort* S, about 20 lines plus 2 tests · Gate D: no

### R — rooms and views
Sonnet implementer; Fable refuter. P4a: the opening pass must not run the current room's analysis (DPC) — only the virtual image; P4b: Diffraction groups re-shows its own map (lane J's rule); P4c per card Q3. Gate: unit + core + build.

- **P4a** — `mac4DSTEM/App/OpeningAnalysis.swift:46-47 (runOpeningAnalysis calls runCurrentAnalysis); App/AppState+ResultPresentation.swift:18-23 (runCurrentAnalysis: .dpc -`  
  Every open path ends in runOpeningAnalysis(), which runs runCurrentAnalysis(), a switch on navigation.analysisMode. But activate() always lands the window in Prepare (Open.swift:710) and keeps the remembered mode (and recovery restores one, :740). Prepare has no task of its own (WorkspaceArea.prepare.analysisModes == []), so the opening pass runs the task of a room the user is not in. Per mode on open: .virtualDetect  
  *Fix:* Make the opening pass Prepare's pass: in runOpeningAnalysis replace 'await runCurrentAnalysis()' + the needsVirtualImage branch with an unconditional 'await runVirtualDetector()' (it does not depend on the mode; the mode is kept so the remembered task survives, nothing of it runs). Delete OpeningAnalysis.needsVirtualImage and its test (net negative); keep restoresPatternReadout. Reword the activate comment at Open.sw  
  *Test:* In PolishCPanesTests next to testACubeOpenedUnderAStaleTaskShowsItsVirtualImage: state.navigation.analysisMode = .dpc; await state.openDemoFixture(); assert product.kind hasPrefix 'virtual', state.comField == nil, no 'dpc_' kind. Same for .disks. Mutation: res  
  *Cost:* 0 rows, 0 pt (no UI structure; the DPC pass at open, seconds to minutes on a large cube, goes away) · *effort* S (about 15 lines changed, one test deleted, two added) · Gate D: no

- **P4b** — `mac4DSTEM/App/AppState+ResultPresentation.swift:192-198 (the .diffractionGroups branch of presentProductForEnteredMode; stale reason in comment 193-194 and doc `  
  The grouping result is held in diffractionGroups.result (Session/DiffractionGroupsProduct.swift, survives navigation, cleared on activate) together with lastRunSettings. The group map (DiffractionEmbedding.groupMap(result)), its name (groupMapDisplayName(groups: result.groupCount)) and its provenance (binned_size, seed from lastRunSettings; components/groups/explained variance from result) are all derivable from thos  
  *Fix:* 1) Extract the publishProduct call (DiffractionGroups.swift:83-97 minus recordLineageRun and statusText) into 'func publishDiffractionGroupsProduct()' reading diffractionGroups.result and lastRunSettings (guard both non-nil), set resultPresentation.resultColormap = .viridis there; runDiffractionGroups calls it right after recordLineageRun (lineage_step is read from replay.producedStep, which persists, so a republish  
  *Test:* PolishFTests/PolishJTests pattern: state.diffractionGroups.publish(tinyResult, ranWith: s); state.resultPresentation.publish(strainProduct()); state.changeMode(.diffractionGroups); assert kind == 'diffraction_groups', displayName == groupMapDisplayName(groups:  
  *Cost:* 0 rows, 0 pt · *effort* S (about 25 lines, one extraction, 3 tests) · Gate D: no

- **P4c** — `mac4DSTEM/UI/ImagePanes.swift:896-904 (the inset overlay, topTrailing, padding 8), :424 (scanNavigatorWidth = 118), :1076-1116 (scanNavigator view, 'SCAN' label`  
  The inset is a ZStack sibling drawn over the image area at the pane's top-right with a fixed 118 pt width (118 x 118*ry/rx pt, plus 8 pt padding) and a solid black background with a white border. It appears for every product that is not scan-domain (ProductDomain: detector = Bragg vector map, disagreement map; reconstruction = parallax, single-slice ptychography), because their pixels cannot be clicked to choose a sc  
  *Fix:* Recommended option A below: move the SCAN navigator out of the real-space image into the diffraction pane (the pattern it drives), top-trailing, same view and gesture; it sits on the CBED corner, which is dark/empty outside the disk and its rings (22-pprev left pane), and the Bragg/reconstruction maps are left clean. Implementation: render scanNavigator(_:) in DiffractionPane's image ZStack under the same condition (  
  *Test:* View-only: no unit test of layout. Pin the rule with a pure predicate if moved (e.g. ScanNavigatorPlacement.isShown(domain:hasImage:allowsScanSelection:) used by both panes) and assert detector/reconstruction domains show it, scan domain does not, and the real  
  *Cost:* A: 0 rows, 0 pt in the result pane (about -126 pt covered there, +126 pt covered in the CBED corner); B: -42 pt; C: +20  · *effort* S-M (about 30 lines moved; needs an on-screen drive of Bragg · Gate D: no

### M — memory figure, menus, overlays
Sonnet implementer; Fable refuter. P5b: phys_footprint (what Activity Monitor calls Memory), one source for strip and glance; P5d: Preprocess with no window opens a window then the sheet; P7b legend chip outside the zoomed content; P7c: park the inner handle at 1.5 handle-widths (no card; second opinion). Gate: unit + core + build.

- **P5b** — `mac4DSTEM/Session/SystemMonitor.swift:15-24 (residentMemoryMB reads MACH_TASK_BASIC_INFO resident_size); mac4DSTEM/UI/WorkspaceView.swift:748-753 (systemGlance `  
  The strip's figure is resident_size, the pages of the process currently in RAM. That includes clean file-backed pages of the mmap'd cube (readingOptions alwaysMapped, docs/archive/v4/parity-28gb-2026-09-30.md:36), which the kernel can drop at any time and which belong to the page cache, not the app. The RC/K3 drive measured it: 23.1 GB for a 15.8 GiB resident cube, and 18.9 GB after Release, when the real phys_footpr  
  *Fix:* Add SystemMonitor.footprintMB() that reads task_vm_info.phys_footprint (copy the 8 lines from DetectorTrainer.footprintMB) and make the strip read it. To avoid touching the frozen WorkspaceView.swift, keep the call site as it is and change the body of residentMemoryMB() to phys_footprint, then rename it (appMemoryMB) when the frozen shell is next open. Do not fall back to resident_size. Fix the stale comment at Layou  
  *Test:* The reader is a Mach call and cannot be pinned exactly. Test that SystemMonitor's reading tracks phys_footprint: allocate and touch 200 MB anonymous (memset), assert it rises by at least 150 MB, then mmap a 300 MB temp file with MAP_PRIVATE, touch every page r  
  *Cost:* 0 rows / 0 pt (the digits change, the slot does not). Number moves: streaming a big cube reads GBs lower, a resident cub · *effort* S (about 15 lines, one file, plus a test) · Gate D: no

- **P5d** — `mac4DSTEM/App/mac4DSTEMApp.swift:100 (@FocusedValue(\.appState)), :119 (Open Dataset… .disabled(appState == nil ...)), :138-140 (Preprocess Raw Data… .disabled(`  
  The commands read the FocusedValue appState, which only a focused DatasetWindow publishes. With no dataset window open (the last window closed, the app stays alive), or with Settings or the Precipitate Objects window as key window, appState is nil, so both 'Preprocess Raw Data…' and 'Open Dataset…' (cmd-O) are disabled. The polish re-drive saw it (docs/archive/v4/polish-redrive-2026-10-02/report.md:15 and :48). Open  
  *Fix:* Enable both items unless a window with a nil state exists, and with a nil appState open a window first, then run the action in it. 1) A tiny @Observable relay in App/ (the tableSelection shape: owned as @State by mac4DSTEMApp and injected into DatasetCommands and DatasetWindow) holding a pendingAction enum {openDataset, preprocess} with a take()-once accessor. 2) In DatasetCommands: when appState == nil, set relay.pe  
  *Test:* Pure relay test: take() returns the pending action once and then nil; setting it twice keeps the latest. Extract the enablement predicate (menuEnabled(appState: AppState?, isBusy:, isLoading:)) as a static function and assert that a nil state is enabled and th  
  *Cost:* 0 / 0 (a menu item's enablement, no layout). This fix also covers 'Settings window is key'. · *effort* M (about 35 lines in mac4DSTEMApp.swift, one new tiny file,  · Gate D: no

- **P7b** — `mac4DSTEM/UI/ImagePanes.swift:304-315 (PatternFitOverlay placed inside the ZStack that is .scaleEffect(zp.drawZoom).offset(zp.effectiveOffset).clipped(), lines `  
  The legend chip ('✚ fitted origin · ◌ fitted ellipse') is part of PatternFitOverlay, whose frame is the fitted pattern box. That overlay sits inside the zoomed layer, so it is scaled and offset with the image and then clipped to the pane. Zoomed in, the box's top-left corner (where the chip sits) is scaled away outside the clip, so the chip disappears (slot-1 drive D1; at zoom 4 the chip would also be 4x larger). Unl  
  *Fix:* Split the chip out of PatternFitOverlay: make a small PatternFitLegend(text:) view and a static func PatternFitOverlay.legendText(strain:template:originPoint:ellipse:) shared by the overlay's accessibilityValue and the chip. Remove `legend` from the overlay's ZStack. In ImagePanes.content(in:), after .clipped()/.zoomPan, or as a sibling beside PaneFooter in the outer ZStack, place PatternFitLegend at .topLeading with  
  *Test:* legendText becomes a static pure function: test the four branches (strain with residual, strain without, template, origin plus ellipse) and the empty string, which hides the chip. Placement is not unit-testable; drive: zoom the CBED pane with the fit overlay o  
  *Cost:* 0 rows. The chip is the same ~18 pt capsule, now fixed to the pane corner instead of the image corner. It may sit over t · *effort* S-M (about 25 lines, two files, drive at zoom 1 and 4) · Gate D: no

- **P7c** — `mac4DSTEM/UI/PaneOverlays.swift:482-496 (ApertureHandleRules.innerHandleOffset), :655-703 (annulus(): parked handle at center.x + parked, centerHandle drawn las`  
  By design, not by accident. At inner radius 0 the cyan inner handle used to sit exactly under the white centre handle and stole its drag (drive 2A, 2026-09-30). The fix PARKS it one handle diameter (12 pt) to the right of the centre. With 12 pt handles that is exactly touching, so the cyan dot reads as stuck to the ⊕, a visual residual rather than a functional defect (shot 76-crop-loaded.jpg: cyan dot touching the ⊕  
  *Fix:* Smallest change: park at 1.5 diameters, i.e. pass minimum: Float(1.5 * Self.handleDiameter / radiusScale) at the call site (line ~694). A 6 pt gap makes the centre ⊕ and the cyan handle visibly two controls and keeps the drag targets clear. Optionally dim the handle (.opacity(aperture.inner > 0 ? 1 : 0.55)) so the parked state matches the 0.35 inner circle. The pure rule and its tests stay as they are (the minimum is  
  *Test:* The rule is pinned by ApertureHandleRulesTests; it is red on a mutation of max(inner, minimum). The geometry change is only visible on screen: drive the demo cube with an annulus at inner 0 and compare the gap to 76-crop-loaded.jpg.  
  *Cost:* 0 rows / 0 pt of layout; +6 pt of gap between two 12 pt handles. · *effort* XS (1-2 lines, one file) · Gate D: no

### D — DM4 vanished volume
Sonnet implementer; Fable refuter (Gate B, Core reader). Per card Q1. Test: a reader on a temp file whose volume check is injected to fail → throws volumeGone, no read. Gate: unit + core + build + scientific (dm4-robustness-test, vendor-reader-test).

- **P2** — `mac4DSTEM/Core/Data/DM4Reader.swift:93-96 (Data(contentsOf:options:)), :130-134 (readingOptions: MNT_LOCAL -> .alwaysMapped, else .mappedIfSafe), :422-441 (deco`  
  Confirmed by reading, not reproduced here (no volume was unplugged). ONLY the DM4/DM3 reader maps a file, on any MNT_LOCAL volume including an external SSD: DM4Reader holds `private let data: Data` (:57) from init until the dataset is released. Every other reader goes through calls that return errors: HDF5 uses H5Fopen with the default property list (no mmap driver; H5Dread status < 0 becomes H5Error.readFailed, H5Re  
  *Fix:* Recommended: (c) now plus a small reader-side guard. Guard: in DM4Reader capture the volume identity at init (statfs f_fsid of the path, or stat st_dev) and run a `try requireVolumeAlive()` at the top of readPattern, readScanRow, readScanTile (not per decode; one statfs is ~microseconds against a multi-ms tile), throwing a new `DM4Error.volumeGone(name)` with errorDescription like '<file> is no longer reachable: its  
  *Test:* Unit (DSTEMCore, next to DM4ReadingOptionsTests): build a tiny synthetic DM4 in NSTemporaryDirectory, open DM4Reader, unlink the file (or point the stored identity at a path whose statfs fails) and assert readPattern/readScanTile throw DM4Error.volumeGone inst  
  *Cost:* 0 rows / 0 pt (error alert text only; no new control). Option 3 would add one status-line sentence, still 0 rows. · *effort* Guard + error case + test: S (about 30 lines and one test, 1 · Gate D: no

### F — frozen shell (only after the owner's answers Q6, Q7)
Sonnet implementer; Fable refuter; the owner's answer is the accepted picture. P6d-1/2 are wording corrections (allowed regardless). Gate: unit + core + build; drive.

- **P6b** — `mac4DSTEM/UI/LayoutPolicy.swift:175 (processAreaIdealFraction = 0.3), :259-295 (ProcessAreaLayout.heights has no minimum), :168-169 (statusStripHeight 34, botto`  
  CURRENT STATE. The bottom area is not a fixed ~1.5 rows (drive report D2 'fixed ... no divider drag' is wrong on both counts). Its height is `usable * processFraction` where usable = column height - 34 (WorkspaceView.swift:41). The whole 34-pt infobar IS the divider: a DragGesture over its full width with a row-resize cursor (WorkspaceView.swift:596-610, 'ResizePointer(axis: .row)'), and it has no visible grabber. `p  
  *Fix:* Proposed picture: a floor and a snap, no new control. Add `LayoutPolicy.processAreaMinimumHeight` = 140 pt (26 header + 3 list rows at ~26 + the 31-pt provenance row = ~135). In ProcessAreaLayout.heights, for 0 < process < floor use floor. In ProcessAreaLayout.fraction(afterDrag:), a drag that ends below floor/2 closes the area (0) and one between floor/2 and floor holds at the floor. Clamp `lastProcessFraction` to a  
  *Test:* Pure-function tests on ProcessAreaLayout: heights(fraction: 0.05, available: 836) returns process == the floor; fraction(afterDrag:) with a drag ending below floor/2 returns 0; toggled(from: 0, last: tiny) restores at least floor/available. Break each by delet  
  *Cost:* Default state 0 pt. Floor 140 pt (about 5.4 list rows of 26 pt including header and disclosure, or ~3 graph rows when th · *effort* Half a day: pure function change in LayoutPolicy.swift plus  · Gate D: no

- **P6c** — `mac4DSTEM/UI/WorkspaceView.swift:290-300 (primaryActionTitle .image), :334-341 (hint), :361-376 (enabled); mac4DSTEM/App/AppState.swift:1200-1228 (hasPrimaryWor`  
  In the Imaging room with the Virtual Det mode (the only non-groups mode), the toolbar offers a prominent 'Compute Image' (title from WorkspaceView.swift:300, Cmd-Return). The image is already current whenever the user can change what it depends on. Dragging the aperture calls updateAperture, which sets the aperture and calls scheduleLiveVirtualDetector (a coalesced quiet run that publishes the product and records the  
  *Fix:* Option B (recommended): in primaryActionTitle return nil for .image when analysisMode == .virtualDetector (only Group Patterns remains for .image), mirror it in AppState.hasPrimaryWorkspaceTask (`.image` returns analysisMode == .diffractionGroups) so Cmd-R disables with it, and have runPrimaryWorkspaceTask's .image branch keep only the groups call. Option A: a word-only change, title 'Recompute Image' once a virtual-  
  *Test:* Pure test on the predicate: with area .image and mode .virtualDetector, hasPrimaryWorkspaceTask is false and canRunPrimaryWorkspaceTask is false; with .diffractionGroups true. Break it by restoring `return true`. Also pin that applyDetectorPreset still publish  
  *Cost:* 0 rows, 0 pt for option 1 (it frees ~110 pt of toolbar width, not height). · *effort* B: 20 min plus tests (3 sites, 1 frozen). A: 10 min. · Gate D: no

- **P6d-1** — `mac4DSTEM/UI/WorkspaceInspector.swift:966-974 (PromoteRunCaption); Session/AppPreferences.swift:142, :158; mac4DSTEM/App/AppState.swift:141-148; UI/SettingsWind`  
  The caption under 'Reopen at Full Extent' says 'Then replays this session's N recorded analyses in order (...), keeping this Mac awake while it runs (lid open). A step that fails halts the run.' The keep-awake assertion is taken only when `preferences.keepAwake` is true (AppState.swift:142-143), and the preference DEFAULTS to false (AppPreferences.swift:142: `defaults.object(forKey:) as? Bool ?? false`, reset at :158  
  *Fix:* Wording correction, allowed in the frozen file: remove the clause, giving 'Then replays this session's N recorded analyses in order (titles). A step that fails halts the run.' Alternative (not preferred, adds a read of preferences in the view): keep the clause only when appState.preferences.keepAwake is true and otherwise say 'The Mac may sleep; Settings > General can keep it awake.'  
  *Test:* No test pins the string today (grep found no hit). Extract the sentence into a static func taking (count, titles, keepAwake) and assert it contains no 'awake' when keepAwake is false; break it by hard-coding the clause.  
  *Cost:* 0 rows; the caption becomes about half a line shorter (a saving of at most one 12-pt wrapped line). · *effort* 5 minutes plus a test. · Gate D: no

- **P6d-2** — `mac4DSTEM/UI/WorkspaceView.swift:334-341 (primaryActionHint), :365 area; mac4DSTEM/App/AppState.swift:1246`  
  One pass over the user-visible strings of the five frozen files found one false sentence (P6d-1) and two weaker ones. (i) The Imaging hint 'Runs the selected imaging task with the current settings.' (WorkspaceView.swift, .image case) describes a run while the image is live; it is the tooltip of P6c's button and goes with whichever option the owner picks there. (ii) The `.results` hint 'Adds the visible result to the  
  *Fix:* Delete the dead `.results` hint arm (or change its text to match 'Save to Session'); fold the Imaging hint into P6c's chosen option. No other change.  
  *Test:* None needed for the dead arm; the Imaging hint is covered by P6c's tests if any test reads primaryActionHint (none found).  
  *Cost:* 0 rows, 0 pt. · *effort* 5 minutes, with P6c. · Gate D: no

### Docs only
Close P6a (already landed ceac82b1) and P10b-steppers (sheet gone) in open-items; P10b-scroll is re-checked in the final drive.

- **P6a** — `mac4DSTEM/UI/WorkspaceInspector.swift:625-629 (Info > Provenance); mac4DSTEM/UI/BottomWorkspace.swift:194-218 (ProvenanceKeyLabel); mac4DSTEMTests/PolishSlot1Te`  
  REFUTED, already landed. Info > Provenance now reads `InspectorValueRow(ProvenanceKeyLabel.text(key), product.provenance[key] ?? "", mono: true).help(key)` (WorkspaceInspector.swift:626-628). It landed in ceac82b1 ("P1 — Info > Provenance shows labels in the frozen inspector, the raw key in .help (card P1 a, the owner's exception)"). There is no snake_case patch left to quote. analysis_mode reads 'Analysis mode', cou  
  *Fix:* Delete the 'Left: Info > Provenance shows raw snake_case keys ...' sentence from docs/open-items.md:173-174 (docs only, net negative lines). Optional, owner's call: change WorkspaceInspector.swift:627 to pass `ProvenanceValueText.display(product.provenance[key] ?? "")` so the Info tab and the Lineage disclosure print the same value, with the exact string still available. Do not add anything for truncation.  
  *Test:* The label mapping is already pinned (PolishSlot1Tests:187-194). For option 2, add an assertion that ProvenanceValueText.display("10.056641535141353") == "10.057", and one that a short or non-numeric value is returned unchanged. Break it by dropping the digits  
  *Cost:* 0 rows, 0 pt (same single line per entry). Item 1 of the closed set; the doc fix touches no frozen file. · *effort* Docs fix 2 min. Optional value-format hunk 5 min plus one te · Gate D: no

- **P10b-steppers** — `docs/open-items.md:233 ('Polish from the drive: 1-px crop steppers'); mac4DSTEM/UI/ExportSheet.swift:8-10; git commit de05c943`  
  REFUTED as a live defect. The 1-px steppers were on the OLD ExportSheet (slot2-drive-2026-10-01.md rows 21-24 and defect 3). Commit de05c943 (X3, the same day) deleted them and LayoutPolicy.exportSheet. Crop is now dragged on the preview panes (ReductionSections.swift:57-110). The only Stepper left in the sheet is Scan stride (PreprocessSheet.swift:146), whose range is 1...strideLimit. Both polish items in the open-i  
  *Fix:* Edit docs/open-items.md:233: drop 'Polish from the drive: 1-px crop steppers' (and the status-history mention if any). Docs only, net-negative lines.  
  *Test:* none (docs); the inventory grep for the item's words must still pass  
  *Cost:* n/a · *effort* XS (docs) · Gate D: no

- **P10b-scroll** — `mac4DSTEM/UI/PreprocessSheet.swift:57-79 (VStack: title, source row, ReductionPreviewPanes, Form, footer); ReductionSections.swift:268-272 (pane frame minHeight`  
  UNVERIFIED on the new layout. The 'short scroll area' (~450 pt, 3 scrolls) was measured on the old ExportSheet. In the X3 sheet the Form is the only scrolling region, and the previews take the space above it. Arithmetic, not observation: fixed chrome is about title 58 + source row 38 + previews 16+16+(180...320) + footer ~60-70 (more with a refusal, failure or progress block). At the sheet's 500 pt floor the Form vie  
  *Fix:* Do nothing in code until it is seen. Re-drive Preprocess at the sheet's minimum size (the drive row: a short display) and shoot the Form viewport. Only if it is cramped: (A) lower the previews' share on a short sheet (a presentation-only edit to PreprocessSheet or ReductionSections), or (B) move the previews into the same ScrollView as the Form so the footer stays pinned. Raising configuratorSheet.min.height means ed  
  *Test:* none: a layout claim; verify by driving the scratch build at the 720x500 floor and attach the shot under docs/archive/. Any code change here is placement/presentation, so Gate D does not apply.  
  *Cost:* Option 1: 0. Option 2: no extra rows, previews lose up to ~140 pt of height on short sheets. Option 3: 0 rows added, the · *effort* XS to re-drive and decide; S if A or B · Gate D: no

## After the lanes
1. **Drive** (the owner's SSD mounted): graphene and bullseye — ADF 3r–6r on a narrow beam, scale bars; sim_Au or the demo cube — a mirrored ACOM pixel
   ("Mirrored Yes"); Phase mapping on a run — the β″ legend; lane J's room switches; every lane above on screen; the Preprocess form at the sheet's
   minimum size (P10b-scroll); a window-only README hero screenshot from a real dataset (Crystal Maps › Strain on Si-SiGe or graphene).
   The owner: the two Replace clicks (the dataset as a save / Export Bundle destination → refused, file unchanged).
2. **One complete `tools/run-tests.sh all`** on the release commit, then status, open-items, CHANGELOG (the polish lines), the Board.
3. Slot 5 as written in `docs/status.md` (notary password → archive → notarize → DMG → push, tag, release; website version lines).

## Record — the polish session (2026-10-04)

Owner's answers: Q1 a (latching, from the session prompt), Q2 a (the paste left it blank; the session took the recommendation —
overrule on sight), Q3 a, Q4 d, Q6 a (Lineage stays off by default), Q7 a. Mid-session the owner cut cost: no second refuter pass,
R3 deferred to open-items, a narrow drive. Each lane: a Sonnet implementer (tests red first, predictions before runs), an independent
Fable refuter in its own HEAD + patch copy, a fix round, then a gate alone on an isolated copy of HEAD + the lane's hunks.

| Lane | Items | Commit | Unit gate (passed / failed / skipped) | Refuter |
|---|---|---|---|---|
| M | P5b, P5d, P7b, P7c | `d415970d` | 1580 / 0 / 2 = 1582 | holds with corrections |
| S | P3b (Gate D), P5c | `068b39b6` | 1591 / 0 / 2 = 1593 | holds |
| V | P10a (Gate B) | `76f01764` | 1578 / 0 / 2 = 1580, scientific 0 FAIL | holds |
| R | P4a, P4b, Go to <room> | `3ec593ac` | 1607 / 0 / 2 = 1609 | holds with corrections |
| N | P1, P10c (Gate D, `lane-N-drive/`) | `7faae9f6` | 1598 / 0 / 2 = 1600 | holds with corrections |
| D | P2 = Q1 a (Gate B, `lane-D-probe/`) | `4400487a` | 1603 / 0 / 2 = 1605, scientific 0 FAIL | holds with corrections |
| R2 | P4c = Q3 a | `b714c125` | 1639 / 0 / 2 = 1641 | holds |
| S2 | P3a = Q2 a, P5a + P7a = Q4 d | `3d2297d1` | 1655 / 0 / 2 = 1657 | holds |
| F | P6b = Q6 a, P6c + P6d-2 = Q7 a, P6d-1 | `a1a8d234` | 1669 / 0 / 2 = 1671 | holds with corrections |

Docs-only closes: P6a (landed `ceac82b1`), P10b-steppers (the sheet is gone). New, registered not fixed: the two room-switch defects
lane N's drive saw (R3, deferred by the owner); the lanes' residuals in `open-items.md`. `run-tests.sh all` on `a1a8d234`: unit
1669 / 0 / 2 = 1671 reconciled, 54 sections, zero FAIL, `GATE_EXIT=0`.

## The prompt for the polish session

```text
Slot 4⅞ — polish mac4DSTEM before v4.1.0 (owner, 2026-10-02). Read CLAUDE.md, docs/status.md and docs/archive/v4/polish-plan-2026-10-02/plan.md first.

Where we are: v4.1.0 / build 8 is cut and the release gate is green on 388634ef (run-tests.sh all: 1571/0/2 = 1573, 54 sections), the
pre-release review's 35 confirmed findings are fixed and driven. I want a polished app before release. The plan maps 26 remaining rough
edges to file:line with mechanism, fix and test (plan.md + map.json); my answers to cards Q1–Q4, Q6, Q7 are in
docs/archive/v4/owner-decisions-2026-10-02-polish.json ("answered") — or below if I paste them here: <ANSWERS>.

1. In parallel, Sonnet 5.5 implementers, one per lane, disjoint write-sets, all in the one working tree on main:
   N number entry (Gate D: reproduce on screen first) · V export voltage (Core, Gate B) · S session safety + wording (Q2, Q4) ·
   R rooms and views (Q3) · M memory figure, menus, overlays (P7c: park the inner handle 1.5 widths out) · D DM4 vanished volume (Q1, Gate B; the guard latches) · F frozen shell (Q6, Q7 — my
   answer is the accepted picture; P6d wording fixes regardless). Each lane: verify the mapper's file:line before editing, tests broken
   first (mutation → red → green), predictions in its report before runs, then an independent Fable refuter, then a fix round.
2. Gate each lane alone on an isolated copy of HEAD + its hunks (the per-lane patch + gatepatch pattern in the 0ed09fb0 scratchpad
   — hunks.py, gatepatch.sh, heavy.sh with 3 slots), commit by explicit paths with the gate numbers, status/open-items in the same commit.
3. Docs-only closes: P6a (already landed ceac82b1), P10b-steppers (that sheet is gone).
4. Then a drive of a scratch build with my SSD mounted (graphene, bullseye, sim_Au or the demo cube): every lane on screen, ADF 3r–6r on a
   narrow beam, a mirrored ACOM pixel, the β″ legend on a run, lane J's room switches, the Preprocess form at minimum size, and a
   window-only README hero screenshot from real data. Work on copies of datasets for any save/export refusal test; the two Replace clicks
   are mine. Review every shot.
5. One complete tools/run-tests.sh all on the release commit; CHANGELOG v4.1.0 gets the polish lines; status, open-items, the review
   record and the Board updated. Then stop: Slot 5 (notary password, archive, notarize, DMG, push, tag, release) is mine.
Work fast and in parallel; document as you go (RESUME.md first lines = these rules); ask me only through one sheet.
```
