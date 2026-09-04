# Open items

The only maintained status doc: unresolved items after the v2.5
consolidation (2026-09-03). The four sections are the four lanes
(2026-09-03, owner): **Science** items are taken one at a time, in the order
the status handoff names, carry no release number, and when one lands the
changelog names the number it changes — a landed change to a scientific
output cuts v2.6.0, everything else ships in the next v2.5.x patch;
**Verification debt** closes when its run happens; **Known, scoped** items and
the owner's bug reports are patch work; **Code hygiene** rides with the
session that touches its file, never its own. Each entry is a live defect, debt, owed run, or open question —
≤ 12 lines: what is wrong, the pinning evidence, the trap, the owner, any
live residual. No narrative. Closed and historical material is the verbatim
pre-cull file,
[`docs/archive/v2/open-items-2026-09-02.md`](archive/v2/open-items-2026-09-02.md),
plus [`docs/archive/closed-items-2026-08.md`](archive/closed-items-2026-08.md)
and [`docs/archive/closed-items-2026-09.md`](archive/closed-items-2026-09.md).
The finished AppKit UI rework and the v2.5 train are
[`docs/archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md).
**[`docs/archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md)** is the finished consolidation plan — its §3 is
the merged UI-findings list; point there, do not duplicate. Owner decisions
and standing directives now live in `docs/decisions.md`.

## Science — Gate D or Gate B owed

### Bullseye disk detection accepts noise, not disks
Map ▸ Bragg disks on `calibrationData_bullseyeProbe.h5` (100×84 scan,
250×250 detector, synthetic kernel r=6.8px, correlation power 1.00,
parabolic subpixel, funnel absolute 187/relative 72/spacing 68): accepted
circles sit across noise regions far from any disk. Evidence: owner
playthrough, 2026-09-01 second sitting, finding 1. Trap: this is distinct
from the (already-actioned) permissive acceptance thresholds and the
estimator repair — don't fold it into either. Owner: a dedicated Gate D
science session, not a UI slice.

### Origin-fit gate has three unresolved holes
(a) **Gate D 2026-09-03, refuted as filed:** the middle-threshold fallback
in `probeSize` is unreachable — r(thresh) is non-increasing, so max(dr)
always lies in the trusted band; py4DSTEM's "NaN" never happens either
(refuter, sonnet, stood it with a general proof and 2000 random trials).
The reachable silent path is the `dpMax > 0` guard (~line 37): an all-zero
or NaN-first pattern returns **1 px at the geometric centre** and
`Calibration.probeRadius` is a bare `Float?` with no provenance, so
readiness (`AppState` ~4675) cannot tell it from a measurement. Pinned by
`ProbeSizeTests.testAnAllZeroPatternReturnsTheUnflaggedOnePixelCentre`.
Fix owed (Gate B): an explicit not-measurable outcome and a radius
provenance like `originProvenance`. (b) Which
statistic gates `originFitIsSane` is open: full-scan RMS (current) can't
see bias; the robust/kept-set residual Gate B tried 2026-08-28 was
reverted — it passes a 15px-displaced fit at 9.94px. (c) The trimmed fit
is blind to spatially clustered failure and contamination ≥50% (a 40px-off
quarter of the scan gives 100% kept, 20.6px error; an exactly-bimodal
residual zeroes the MAD guard). Owner: (a) Gate D, same family as the
probe-radius fix; (b)/(c) a design pass — no statistic proposed yet
distinguishes displacement from contamination. `docs/q-calibration-design.md`.

### CIF import can silently accept a wrong crystal
Two mechanisms, same family: (a) a non-P1 declaration with a PARTIAL ops
list still imports the wrong cell (`verifyFamily` can pass it — Gate B
refuter escape E2, 2026-09-01, recorded not fixed; missing/identity-only
case is already guarded). (b) Imported ids are `imported_<file stem>`
(`Core/Crystal/CIFImport.swift:139`) — two different CIFs sharing a
filename replay by set membership with no content check (residual of the
2026-09-02 lattice-constant Gate D). Trap: (a) needs a 230-entry
IT-number→group-order table the importer deliberately lacks — cheap
mitigation, new scope. Owner: unclaimed, Gate B when picked up.

### ACOM orientation/export coverage gaps
Found in W4b Gate B, 2026-08-31; the shipping numbers are believed correct
but nothing gated would catch a regression. (a) Exported Euler angles are
labelled py4DSTEM/orix-compatible but differ by frame rotation `P` — median
38.55° misorientation if compared naively; math is right, label is wrong.
(b) The projection convention (`OrientationPlan.project`) is verified
correct three independent ways, but every gated ACOM harness builds its
own peaks through the same function it's testing, so two frame-mutation
bugs stay green — a real fixture (analytic, non-self-referential) doesn't
exist yet. (c) The exported orientation matrix can decouple from the
reported template index unnoticed. (d) Unpinned: an additive radial
offset, the reliability distinctness test, `intensityPower`. Owner: (a)
relabel-vs-convert decision then Gate B; (b)–(d) Gate B, unscheduled.

### Q-calibration scale defects on real crystals
(a) `KnownCrystalQCalibration.estimate` takes the per-pattern MINIMUM
radius as the reference ring, biased low by an order statistic (~1.9–2%
measured on `polycrystal_2D_WS2`). (b) The reference-shell pick has no
l-filter or visibility filter; on 2H-WS₂ it selects (0002), a reflection
a [0001]-zone specimen never shows — predicted mis-scale 2.26×, silent
(S13's Gate B cut the threshold that would have refused it). Measured
end to end: correlation score HALVES at the defective scale, and median
`reliability` is HIGHER at the wrong scale — no fix may lean on
reliability to choose between candidate scales. Owner: (a) Gate D first
(mode/trimmed-mean/profile-fit?) then Gate B; (b) its own W3-territory
design pass, owner's call on scheduling.

### ACOM bundle exports no origin provenance
The strain bundle snapshots `origin_reference` and the excluded fraction
at compute time; `ACOMRunSemantics` has no equivalent, so reading live
calibration at export time (what Gate B found wrong) is the only option
today. Fix is one snapshot field. Owner: whoever next touches
`ACOMRunSemantics`.

### Selected-area diffraction's mask-to-tile correspondence is unpinned
Gate B demonstrated (2026-08-27) that replacing the per-tile mask slice
(`Core/Analysis/VirtualDetector.swift:354`) with row 0's mask stays green
on every harness in the repo — excluded scan rows could be summed in:
wrong science, plausible numbers, nothing would catch it. Fix: a ground
truth case in `tools/virtual-detector-test` with ry≥4, a partial region,
`tiledDiffraction(maximumTileRows: 1)` vs whole-cube. Owner: whichever
session next touches virtual diffraction.

### #18 — training-dataset campaign can't reproduce the app's Si_SiGe strain
Mechanism resolved: the campaign's fitted mean origin is ~7px off centre
(non-quantitative fit), which poisons `estimateLatticeBasis`'s clustering
scale; the app's own gate rejects that fit and falls back to the true
detector centre. Latent app-side risk: a genuinely off-centre beam with
`meanOrigin` nil would fail the same way. Two candidate fixes, neither
made (science changes, own Gate B): floor `minRadius` at the probe
radius or scale it with fit quality; or have the campaign adopt the
app's origin gating. Full diff in the archive.

### ACOM omits py4DSTEM's `power_radial` weighting
`orientation_plan` applies `power_radial=1.0` to the template side
(`crystal_ACOM.py:32,810`); `OrientationPlan.buildPolar` doesn't, so outer
shells are under-weighted by ~r relative to py4DSTEM. Untested materiality
— apparatus exists (`tools/acom-groundtruth`) but the Python driver that
built prior test inputs wasn't retained. Also un-DEVIATION-noted (hard
rule violation): the app subtracts each ring's mean where py4DSTEM leaves
that line commented out. Owner: S16 successor / whoever next touches ACOM
weighting.

### UI review (Fable, 2026-09-04) — labels that can misstate a number
Independent review of `UI/`. Nothing found was a wrong computed value; every
finding is a LABEL on a correct one. **(a) and (c) fixed 2026-09-04**, the rest
open. (a) *Axis order and the letter q meant different things on one screen* —
FIXED: the file's own order is `[Ry, Rx, Qy, Qx]`, so the app's `rx`/`qx` ARE
the columns; UI now prints columns × rows everywhere with `Rx × Ry` /
`Qx × Qy` labels, and the one place showing py4DSTEM's opposite convention
(whose `qx` is the rows) says "py4DSTEM" on screen instead of two bare glyphs.
(c) *Byte sizes in two bases under one label* — FIXED: UI had three
formatters (two hand-rolled 1024-based ones disagreeing on precision, plus
`ByteCountFormatter(.file)` at 1000), so one cube read 4.00 GB in Info and
4.29 GB in the export sheet; one helper now, Finder's style. STILL OPEN:
(b) "Current scan position ▸ Pattern min/max" is not that position's pattern
in Mean/Max/ROI mode (`WorkspaceInspector`, `AppState.swift:1302`) — the only ROI-sum
flag is in the pane header, one tab away. (d) The A/B/A−B comparison draws
three panels at 0…1 with no colorbar, range or zero mark on a symmetric RdBu
difference (`ResultsWorkspace.swift:186`). (e) The cursor readout prints a raw Float,
seven-plus digits, beside a badge that may say Exploratory (`ImagePanes.swift:389`,
`DisplayedProduct.swift:161`). (f) Staleness has two verdicts: the sidebar's
green check ignores `diskDetectionSettingsAreStale` by design while the
inspector and pane both flag it, and Strain/ACOM rows stay green on stale
vectors. Minor: the scale bar can print a physical sampling labelled "px" when
`pixel.units` is nil (`ImagePanes.swift:713`); disks draw at an invented
`probeRadius ?? 3` with no kernel (`:152`). Owner: (b), (d), (e), (f) unclaimed.

## Verification debt

### S17 sidebar intermittent — archived, its test is gone
`SidebarLayoutTests` and the `ContentView` column publisher the whole
observation log measured were deleted with the AppKit window (`d5786e2`), so
the log cannot be extended and the fault cannot recur in the same place. The
full record — 2 of 5, then 0 of 14, then 3 of 4, and the 810.5 pt against
786 pt it always failed at — is in [`archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md). What survives it is the rule in
the constraint-loop entry below. Kept live only as the name S17, which other
entries still cite.

### Sidebar drag crash — mechanism found and removed 2026-09-03, owner's drive owed
Exception (owner, Xcode console): `NSGenericException: The window has been
marked as needing another Update Constraints in Window pass, but it has
already had more … passes than there are views in the window`, after a
sidebar drag; the sidebar at ~60pt with its content laid out at full width.
Reproduced on the demo fixture with real mouse events: column 92pt, content
305pt wide at x = −213. Mechanism, measured in-process: SwiftUI's
`NavigationSplitView` owned the sidebar's split item and rewrote its
minimum to 140 on every update, while the declared 250 constrained only the
content; a drag shrank the column under content that could not shrink and
the loop guard threw. Refuted on the way: the hard frame belt (crash
reproduced without it), the policy "never applying" (it applied and was
overwritten). Fix: the columns are AppKit's (`ColumnSplitController`, an
`NSSplitViewController` with sidebar/inspector items; hosted content with
`sizingOptions = []` so it never sizes the column). Live drive 2026-09-03:
drag past the minimum collapses, Show Tools reopens at the old width, a
560pt sidebar squeezes the inspector first, no exception.
**2026-09-04: the fix described above no longer exists.** `d5786e2` deleted the
AppKit shell, `ColumnSplitController` with it; the columns are a SwiftUI
`NavigationSplitView` now. So the drive this entry asks for cannot be performed
as written — dragging today exercises different code. What is worth carrying
forward is the MECHANISM, not the fix: a split rewriting a hosted child's
minimum under content that cannot shrink, which is the constraint-loop rule
below. Kept live rather than archived only because the owner has still never
driven a column divider on the rebuilt window.

### A unit-level column-width gate is not possible — falsified 2026-09-04
`d5786e2` deleted both width-range gates, so nothing gates a column's width and
this repo keeps finding truncation defects there. **Refuted before it was
built.** A probe hosted `PrepareSettings` (250 pt), `WorkspaceSidebar` (190 pt)
and `WorkspaceInspector` (280 pt) in an `NSHostingView` and measured
`fittingSize.width` and the worst descendant-`NSView` overflow; then a
150-character section label — impossible in 250 pt — was injected and it re-ran.
**Both runs byte-identical**: `fittingWidth=1103.0 worstOverflow=0.0`. SwiftUI
draws `Text` into layers and makes no `NSView` per label, so only real controls
appear; the deleted gate had the same hole (`controls(_:)` collected
`NSControl`s). `fittingSize` is no substitute — 1103 pt for a form that fits,
0 pt for the sidebar `List`. Anything that catches a long label must rasterise
or drive the app. Owner: re-open only with a measurement that survives the
injected-label mutation.

### No automated visual baseline
Every acceptance run is numeric-only (`--no-screenshots`); the owner
driving the app is the only evidence anything "looks right" — say who
drove it and when. Standing: driving has caught defects with every harness
green (colormap control missing, readiness row self-contradicting, three
more in the clean-account run); the 2026-09-03 UI hardening and UI
native shell reset are also not owner-approved. The retired checklist's trap notes are in
`docs/archive/v2/visual-acceptance-checklist-2026-09-03.md`. Never seen on
screen: everything from 7c slice 1 on (Results sidebar and inspector, the
inspector following the focused pane), the clean-account run, the bounded
promote run, a real load cancel.

### `tools/run-tests.sh all` has not been re-run on the newest tree
Last run: 2026-09-03, `e2284f1` — 43 harnesses green, exit 1 only at
`package-test`'s literal version assertion, since fixed and green on that
same tree (`status.md`). Nothing aggregate has run since; `unit` and the
reader harnesses have each run green individually on 2026-09-04's trees.
The run itself is ~12 minutes and needs nothing the machine lacks except
disk: the preflight demands 8 GB on both `$ROOT` and `$TMPDIR`, and getting
there means deleting outside the two roots `free-space.sh` guards — which is
the owner's call, not an agent's. Do not quote an aggregate you did not run.

### The app has never been driven on the macOS version it claims to support
`LSMinimumSystemVersion` is 14.0; every manual session has been on macOS
26/27. CI now builds and unit-tests on macOS 26. Nothing from 14–25 has
been exercised at all — only a real older machine answers this.

### Residency `.automatic` cannot be re-measured without a second machine
Dropped by decision (v2 S3, 2026-08-19), not dormant — do not set
`ResidencyAdmission.measuredWorkingSetFraction`. The three checked-in
training cubes top out at working-set ratio 0.19 on this machine; no knee
exists in that data. A second-machine sweep is the only thing that could
reopen it, and if two machines disagree the rule needs a second term.

### Two diagnostic harnesses gate nothing
`tools/bragg-spacing-probe/` and `tools/residency-sweep/` both need
gitignored multi-GB data and stay diagnostics only — not a gap to close,
a standing limit to remember before citing them as coverage.

### #30 — origin calibration over a NAS runs at ~3 MB/s
Investigation owed.

## Known, scoped, not blocking

**UI findings** — the merged, trust-ordered list (provenance
inference, ACOM confidence gating, calibration-state vocabularies, unit
labels, Phase linearity, inspector layout) lives in
[`docs/archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md) §3. Do not duplicate it here and do
not patch findings 1/4/5/7 on the current facade — they wait on the
architecture seams.

### UI polish list from the same review
Not trust defects; the Mac-ness gap. Ranked by the reviewer: layout is not
remembered (pane divider resets on every trip to Results, log height is
per-window `@State`; `@SceneStorage` for both); the Info tab carries seven
ACTIONS against its own descriptive contract (Reopen, Ignore…, Change…, Remove
per result, Apply Saved Controls, Release cube); two per-body costs (the output
log re-diffs every line and scrolls on each append; the validity row reduces
the whole mask on every AppState change); no `.navigationDocument(url)`, so the
window has no proxy icon or drag-out; the primary action answers to both ⌘↩ and
⌘R and arrow-scrubbing needs a focus the user cannot see they must give.
Un-Mac-like: `TabView` renders a bordered Preferences box in a 280 pt inspector
(Xcode uses a segmented strip); "Ignore…" opens no dialog; values written into
their own labels with a comma ("Gamma, 1.00", "Radius, 12 px") — no system
control does that; Unicode glyphs where SF Symbols exist; "Reconstruction
Ready" as a disabled prominent button; landing-page copy in the empty window.
Stale copy: "shown in the tools panel" (no such panel in UI), "Open a 4DSTEM
.h5 file" (the importer takes dm4/mib/emd/raw), and one action called "Save to
Session", "Save to Results" and "Save Current Result to Session Sidecar" in
three places. Two contract leaks: `NSPasteboard` in `ContentView` and an
`NSString` bridge in `PrepareSettings` (the latter deliberate — it keeps a
tested helper byte-identical). Owner: a UI polish session, after the owner's
next drive.

### Presentation-contract residuals still open on screen
Rules 2 and 5 were wrong as written and are amended in `architecture.md`; the
finding and its evidence are archived ([`archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md)). Two of the three "still
open" items closed with the rebuild: there is no workspace hero header any
more (`WorkspaceView` says so in as many words), and the pane-centring
complaint is now `PaneSplit`'s business. What is left, unverified: **~40
permanent caption `Text`s across the sidebars**, and **nothing has been seen
in light appearance**. Owner: the owner's drive.

### The columns' material was diagnosed, and never checked in light
Gate D 2026-09-03 (archived, [`archive/v2/ui-rework-2026-09-03.md`](archive/v2/ui-rework-2026-09-03.md)): the hosted lists were painting over
AppKit's column material; `.scrollContentBackground(.hidden)` removed that,
and the columns still render flat because the OS's column material is
within-window. The conclusion — the columns look like Xcode 26's, flat on the
window ground — was reached in dark appearance only. Owner: the owner's drive.

### Concurrent HDF5 use crashes the process
`EXC_BAD_ACCESS` in `libhdf5.dylib`\`H5SL_search`, reproduced under lldb
within a few dozen iterations; the bundled build is `Threadsafety: OFF`.
Live latent crash: `loadSession` runs on `Task.detached` while an
`H5Reader` actor may be working, plus an uncancelled
`preloadResidentCube`. Unowned.

### Fabricated provenance on pre-2026-08-18 sidecars
`AppState.swift:2331` does `snapshot.loadSpecification ?? .fullExtent` —
a sidecar saved from a cropped view before that attribute existed is now
asserted full-extent rather than unknown. Both prior reproducers were
overwritten by later driving sessions; demonstrating it again needs a
synthesised sidecar, not a training-set one. Unowned, belongs with the
trust fixes.

### Cross-frame recipe export refuses rather than composing
The other half of this entry is CLOSED and archived: `applySessionCalibration`
no longer adopts a saved calibration verbatim — it asks
`SessionCalibrationFramePolicy.decide` (`AppState.swift:2887`), added
2026-09-01, pinned by `SessionCalibrationFramePolicyTests` and
`SessionCalibrationTranslationTests`. What survives is not a wrong number but a
feature gap, so it moves out of the Science lane: `ResultExport.exportableRecipe`
REFUSES, with a reason in the export status line, when the recorded frame is not
the live view — a three-frame composition (recorded → source → exported) needs a
transform `ReplayFrameTransform` does not have. Recorded as an S10 decision, not
a defect. Owner: unclaimed.

### DM4Reader silently reads the whole file into RAM off non-local volumes
`.mappedIfSafe` (`Core/Data/DM4Reader.swift:64`) declines to map on any
volume failing `MNT_LOCAL && !MNT_REMOVABLE` (confirmed by S9b: every
external disk, every disk image even on internal SSD, all smbfs) and
silently falls back to a full anonymous-memory read — held for the whole
session. `H5Reader`/`VendorRawReaders` are immune (hyperslab/seek reads).
No fix landed; `.alwaysMapped` trades this for a SIGBUS risk if the
volume disappears mid-read. Needs a CI fixture (disk image on internal
disk reproduces `MNT_REMOVABLE` with no external hardware). **The
original 2026-08-18 8GB-machine death that motivated this is still NOT
explained** — the mechanism is real and worth fixing but not established
as that incident's cause. Owner: a later session, Gate B.

### The open/promote unwind is sixfold, and Cancel can vanish mid-load
Corrected 2026-09-04. **Six begin/finish brackets, not three**: `openFileAsync`,
`commitPendingLoad`, `promoteToFullExtent`, plus `selectDataset`,
`openManualPath` and `openDemoFixture` with no cancel handling at all.
**The old hazard 1 is refuted** — there is no suspension point between the last
cancellation check and `finishDatasetLoading` on any path (`AppState` is
main-actor isolated, `project.pbxproj:488`, and the calls there are not async).
**Hazard 2 is worse than recorded**: `finishDatasetLoading`
(`AppState.swift:2789`) unconditionally nils `datasetLoadCancellation` and
clears `isLoadingDataset`, both of which `canCancelDatasetLoad` (`:1162`)
depends on — so with two loads in flight the FIRST tail to finish disarms
Cancel for the second, and the running load becomes uncancellable. Unification
alone is not the fix. No fixture exercises these branches; that is the
precondition. Owner: whichever session next touches any of the six.

### Promote/replay residuals
(a) Owner design question, queued TB1: should promote carry the scan
position across, or land at (0,0) as today? (b) Fitted origin maps are
crop-sized and dropped by the full-extent restore's shape check, so a
promoted recipe recorded against "calibrated origins" refuses — expected
behaviour, not a bug. (c) Parallax/ptychography are deliberately NOT in
the replay record (not bit-reproducible); folding them in is its own
post-v2 session. (d) A user-initiated analysis mid-replay steals the
Cancel control from the replayed step (S18-class polish). (e) Per-kind
replay contracts live in three places (record/parse/apply) held together
by tests, not structure — co-locate per-kind when the next kind is added.

### Recents/window-state edge cases, both low priority
Each window's `AppState` holds its own `RecentDatasets` snapshot over one
`UserDefaults` key, so a second window's save can clobber the first's
entry (single-window use, the shipped reality, is unaffected). Separately,
`openRecent`'s failure path removes a dead entry from the list but leaves
"Reopen" dead-ending in "No recoverable dataset." Both unclaimed.

### Legacy `.icns` tops out at 256px — probably moot
Written against a macOS 14 floor this app no longer declares: the deployment
target is 26.0 in every build configuration and in `Package.swift` (corrected
across the docs 2026-09-04). On macOS 26+ Get Info, Quick Look and large Finder
icon view render from the `.icon` source correctly and the Dock was never
affected, so the defect can only appear below the supported floor. Close it
unless a reason to ship a legacy PNG set appears.

### S1's crop restore is repaired in code and unverified on screen
Retitled 2026-09-04: **its three code claims are all false now.**
`recordedLoadSpecification` reads through `sessionSidecar.location(forSourcePath:)`,
which takes the security-scoped grant first (`SessionSidecarLocator.swift:144`),
and the `try?` is gone — a refused read and "no crop recorded" stay different
facts. What is open is the drive: F1.3h passed on a FULL-EXTENT sidecar, which
never enters the repaired branch, so a cropped save → quit → reopen has never
been driven. `SessionSidecarLocatorTests.swift:269` cannot close it either — it
adopts an in-memory grant and never opens HDF5. Failure mode if still wrong:
right numbers, wrong region. Owner: the owner's drive.

### Resident/streaming residuals
`releaseResident()`'s "freed" claim is asserted by a derived byte count,
never a measured one — a leaked `MTLBuffer` is invisible to every test.
`TiledDiskDetection.detectAll` still stages each tile into a fresh
`MTLBuffer` (out of S18's bounded staging-copy elimination). Resident
cancellation is 2.5× coarser than streaming (one indivisible dispatch) —
academic until something under `mac4DSTEM/` requests `.resident`, which
nothing does today.

### Sidecar/session UX residuals
Recents-row location labels unverified on screen (F1.1c). A sidecar
retarget made before any save survives only until the next dataset
change. Repeating "Save Session Sidecar As…" can prefill a doubled
`.h5.h5` suffix. Pre-S4 calibration-only sidecars remain unrecognisable
(extension/open-panel-filter half is an owner decision, queued TB1). The
configurator's beam proxy has no "load anyway" override (owner question,
queued TB1; unifying it with `CalibrationReReference`'s gate is a
deliberate non-unification, `App/SessionGates.swift`).

### DPC's banner contradicts its badge — entry corrected 2026-09-04
Three claims here were wrong. **Mechanism:** the fall-through is `.relative`
(`AppState.swift:761`), not `.quantitative` — only named families are
quantitative (`:756`). Still true: it pattern-matches strings and consults no
calibration readiness, while `idpcPhysicalCalibration` consults three gates.
**Carrier:** not XMP (no "xmp" in any Swift file) — the PNG `Description` JSON
chunk and the status burned into the caption's pixels (`ResultExport.swift`).
**Headline:** iDPC's badge and banner AGREE; the contradiction is
`PhaseSettings`' always-shown qualitative banner over `dpc_magnitude` /
`dpc_angle`, which `quantitativeStatus` calls quantitative.
Before any fix: status is frozen at publish and at persist and preferred over
re-derivation on restore, so a change corrects neither existing sidecars nor
exported PNGs, and there is no version field to migrate on. Owner: the
trust-fixes session; which way it goes is a judgement call, and the owner's.

### Misc unclaimed, low priority
Load-cancel: F1.1d (cancel a real load on screen) never driven; resident
buffer/cropped-view teardown unpinned. #17a: the wider pane-arrangement
question (design decision, reverted on sight once). Detector-bounds
convention sweep: whether other tests use an index convention for
continuous positions besides the one already fixed, nobody has checked.
HDF5 multi-dataset axis order is assumed (`[ry,rx,qy,qx]`), not checked —
weak lead, a scan↔detector swap is obvious on screen, only Ry↔Rx/Qy↔Qx
transpositions would be silent, and the app does name the dataset it
picked. `MAC4DSTEM_ACOM_SCALE_OVERRIDE`: the sidecar keeps the estimate
scale, not the override scale the map was matched at (design call); a
cubic-dataset override run would compare apples-to-oranges in the parity
comparator (can't arise for WS₂). Virtual-detector mask boundary
(`r² < rOut²` vs `<=`) is unpinned against analytic truth. #31
`validationIssues` is O(n²) in a SwiftUI view body. #32 `isSymmetry`'s
bijection check has no fixture coverage. (Three UI clauses deleted 2026-09-04,
each verified obsolete: the launch-screen cards are gone with the welcome
rebuild; "the 171 pt pane-width floor" — `171` appears nowhere in the tree, the
floor is `LayoutPolicy.imagePaneMinimum` = 180; and "a saved sidebar divider can
restore below its 250 pt minimum" — there is no `autosaveName` anywhere in the
app, and the sidebar is a `NavigationSplitView` with a 190 pt minimum.)

### The constraint-loop crash: nothing in a split may change its own minimum
`NSGenericException` from `_postWindowNeedsUpdateConstraints`, through
`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`. **The
rule, demonstrated 2026-09-04: nothing inside a split's hosted content may
repeatedly change its own minimum size.** SwiftUI's split machinery loops on
it, and `NavigationSplitView` and `.inspector` are splits too. `.fixedSize()`
on text whose string changes is the easiest way to do it by accident, and it
only fires on a dataset big enough for an operation to tick — which is why
every demo-fixture launch was clean and a real one died. Two sites, both in
the status bar, both fixed: the metrics line and `status.footer.facts`.
`PaneSplit` is right and should not be "fixed" — it propagates no minimum at
all — but it was never the whole story. Full diagnosis, the refuted
`HSplitView` conjunction that preceded it, and the two probes it made moot:
commits `e608dbd` and `27de9bb`. Residuals: positive and negative are each
n=1 against a fault this repo calls intermittent (S17); the inspector's
Performance rows still tick per second, inside a scroll view rather than a
size-setting inset. The 12 bare `.fixedSize()` sites left in `UI/` are now
audited — see the entry below. Owner: unclaimed.
### `PaneSplit` residuals from the refuter
(a) **Header overflow at a narrow window.** `HSplitView` refused to shrink a
child below its minimum; `.frame(width:)` proposes a width and lets the child
overdraw. A pane header is ~420 pt of `.fixedSize()` controls, and at the
app's 1080 pt floor with both side columns wide each pane gets ~260–300 pt.
Mitigated only — the pane now `.clipped()`s so it cannot overprint its
neighbour; the header still needs to become compressible. Predicted, not seen
on screen. (b) **The image floor lapses below 2× itself**: the divider
fraction saturates at 0.5 under ~360 pt of usable width, and UI declares no
detail-column minimum at all where the retired AppKit UI had `SplitViewPolicy.detailMinimum`
= 360. Adding one is exactly the change most likely to re-arm the crash while
the mechanism is unestablished, so it is recorded rather than made.
(c) The divider position resets to centre whenever the workspace branch is
rebuilt (`HSplitView` did too). Owner: with (a) above.

### Status-bar elapsed / throughput / ETA — rebuilt, NOT yet driven
Owner, 2026-09-04: those three numbers belong beside the progress bar, not
only in the inspector's Performance tab. Built, reverted the same day for the
crash above, rebuilt 2026-09-04 in a reserved slot:
`LayoutPolicy.operationMetricsWidth`, a constant frame the text truncates
inside, no `.fixedSize()`, held for the whole operation so an appearing rate
or ETA moves nothing. `OperationMetricsFormat.line` composes it for both
surfaces. `StatusBarMetricsTests` pins what it says and measures the widest
line the formatter can produce (an hour elapsed, an hour of ETA, 999.9
units/s) against the constant in the same font; all four tests were broken
first. **What is left is the drive**: this is unverified on screen, and only a
real dataset exercises it — the demo cube finishes faster than the one-second
tick. Owner: the owner's drive.

### Manual Q and R pixel scale cannot be corrected once entered
Owner, 2026-09-04, on `downsample_Si_SiGe_exp.h5`: enter a manual Q or R pixel
size, the readiness row turns green — and the entry field disappears with it,
so a typo is permanent for the session. Mechanism: the readiness rows render
their action controls only `if !item.status.isReady`
(`PrepareSettings.swift:251`; the `UI/CalibrationReadinessView.swift` this
entry used to cite was deleted in `d5786e2`). The code names `.rScale` as
"the one calibration with no measurement path in the app"
(`PrepareSettings.swift:318`), so whether `.qScale` is equally trapped is
worth checking rather than assuming. A wrong R scale silently
rescales every real-space axis, scale bar and export, so this is a trust
defect, not an inconvenience. Fix: keep the manual rows on screen when the
value's provenance is manual (or always, for the two kinds with no measured
path). Owner: unclaimed; small, but it touches calibration presentation and
wants the owner watching.

### `calibration.*` identifiers exist twice while the export sheet is open
`ExportSheet` re-renders the readiness rows, so `calibration.readiness`,
`calibration.item.*`, `calibration.rScale.filenameConflict` and
`calibration.action.originProbe` are each emitted by both it and
`PrepareSettings` while the sheet is up. Harmless today — nothing queries them
at runtime — but it would defeat any future UI test that addresses a readiness
row by identifier. The old app had the same collision. Owner: unclaimed.

## Code hygiene

### `tools/free-space.sh` still spells shared path knowledge three times
Fixed 2026-09-04, the misreporting half: it prints the two volumes the preflight
gates (`$ROOT`, `$TMPDIR`) instead of `/`, answers "will the gate run?" against
the 8 GB floor, and surveys the regenerable roots outside its two — Xcode's
`DerivedData`, the per-project `ModuleCache.noindex`, `CodingAssistant`,
`.build`. Measured that day: 680 KB clearable against 743 MB it could not see.
Report-only; `guard_path()` untouched, and `build/release` (notarized, stapled
images) prints as PROTECTED. Residual: the temp prefix is spelled by producer
and reaper separately, the MCP root is hardcoded, and ~35 harnesses use
untagged `mktemp -d`. The proposed `tools/lib/` constants file is deliberately
NOT taken — every gate sources through `run-tests.sh` under `set -euo
pipefail`, so a bad line there kills the whole harness. Owner: whoever next
touches `run-tests.sh`.

### Acceptance-gate test-infrastructure residuals
`real-data-acceptance/run.sh` hand-spells 18 source paths instead of
sourcing `tools/lib/sources.manifest` (the reason a "byte-identical
inputs" audit once missed a shader file). Its empty-glob SKIP exits 0, so
a machine with zero datasets passes the gate — whether it should consult
`expected.json` instead is open. The 15s acceptance budget only gates the
4 pinned datasets now, not the 4 unpinned ones — pin-or-refuse vs. the
current advisory `UNPINNED` line is an open call. `abs_tol=1e-3` on
virtual-image fields exceeds `polycrystal_2D_WS2`'s whole dynamic range
(5.3e-4) — not tightened, since that risks reddening legitimate runs, but
the fixture now carries a WS₂-magnitude case so the boundary is testable.
Comparator residuals: `rel_tol` on `diskProbeRadiusPixels` is inert below
50px; `if not actual:` is unkillable by any mutation. A `run-tests.sh all`
`report count` discriminator (does the historical mismatch predate or
postdate the cube-count growth?) was never run; the owner holds the log.
Separately: the runner aborts at the first failing harness, so it can't
report how many are actually red — whether to continue-and-summarise
instead is open.

### `.fixedSize()` in `UI/`, audited 2026-09-04 — one armed site, contained
12 bare call sites against the constraint-loop rule above (an unanchored grep
says 16; four of those are comments *about* `.fixedSize()` — use
`grep -rn '^\s*\.fixedSize()'`). **One is armed**: `ImagePanes.swift:452`, the
zoom badge. `liveZoom` is written on every magnify event, the digit count moves
(×9.9 → ×10.0 → ×100.0), the value is unclamped mid-pinch, and the badge itself
appears and disappears across ×1.0 — a `.fixedSize()` child inserted and removed
repeatedly in one gesture. Of the rest, eight are literals and three change once
per published product (`badge(text:)`, `:413/:418/:437`) — not armed, but the
ones to re-check if a product ever republishes on a tick.
**Not fixed, deliberately:** a reserved slot closes the string-width channel and
NOT the appears/disappears one, so it would ship a green test claiming a closed
mechanism. **Not urgent:** `PaneSplit` gives each pane `.frame(width:)`, which
terminates its minimum, and none of the 12 is in the one `.safeAreaInset` in
`UI/` where both crashing sites lived. Owner: with the pane header's
compressibility (`PaneSplit` residual (a)) — same header.
(The `fixedSize(horizontal:vertical:)` set this entry once called "31 sites
covered by `SplitViewHeightTests`" is 5 sites, that test does not exist, and
vertical-only `fixedSize` cannot move a width.)

### Runner source lists still hand-spelled in places
`SessionReplayRecord.swift` is patched into seven runners by hand rather
than through the manifest, after predicted breakage recurred once
already. `Aperture` is declared in `App/AppState.swift`; scientific
harnesses carry their own copies that would still compile and pass if the
app's gained a field — belongs in `Core/`. The app build is the only real
gate for actor isolation (`tools/load-spec-test` compiles nonisolated;
the manifest's isolation flags buy visibility, not enforcement).

## Working methods that earned their keep

### Count a gate's tests by name, and reconcile against the expected delta
`run-tests.sh unit` passes `-quiet`, so xcodebuild prints no summary and the
count has to be grepped out of the log. The parallel runners interleave and a
`Test case '…' passed` line gets CHOPPED mid-name — twice on 2026-09-04, in
different places. `grep -c` on the whole line undercounts. Counting
`Class.method` undercounts too when the chop lands in the class name (it did:
`dedOriginSubtractsTheCropOffset…`). **Count the method alone —
`grep -oE "[a-zA-Z0-9_]+\(\)' passed" log | sort -u | wc -l` — and then
reconcile it against what you expected to change (prior total, minus deleted,
plus added).** When the two disagree, `comm` the two runs' rosters: both times
the "missing" test was a chopped duplicate of one that ran. Never conclude a
test vanished from a count alone. Same family as the `| tail` trap: the gate
was green, the number was wrong.



Kept because they changed outcomes, not because they are tidy:

1. **Cost a UI change before designing it.** Measure the shape change
   (pt/rows) before choosing between options — makes it a measurement,
   not taste.
2. **Adversarially review anything touching the science, and review the
   diagnosis, not just the code.** Three times a fix has passed every
   test written for it — including one verified to fail without it — and
   still been wrong. The refuting evidence was already in a log nobody
   had re-read.
3. **Never widen a gate that fails silently.** A miss path that calls
   `recordError` and continues, or a control hidden behind a disclosure,
   turns a failure into a finding nobody reads.
4. **Open the app.** Ten minutes of driving on a day with every harness
   green has twice found defects the suite could not see. The owner's
   driving sessions replace the retired checklist because nothing else
   catches that class.
5. **A green suite can be green about the wrong thing.** Check what
   calling convention a suite actually exercises (absolute vs. relative
   paths, `$0`-relative sourcing after a `cd`) and whether that's the one
   anyone uses. Search harness runners by basename, never by path prefix
   — the same path gets spelled multiple ways across `tools/*/run.sh`.
   A backgrounded pipeline's `${pipestatus[1]}` reports the last
   command's exit code, not the gate's — put the exit code where you
   will actually read it.
6. **A test written for your own fix proves nothing until it fails
   without it.** In-process SwiftUI `Picker` menus render blank to
   automation (built lazily for a real assistive client) — a rendering
   assertion can pass while testing nothing; assert the decision instead,
   and say why at the call site.
7. **Do not drive the app while `run-tests.sh unit` is running.** Both
   suites inject private `AppStorage` into the same defaults domain; a
   live instance can spuriously redden a layout/sidebar test.
8. **Break every new test before trusting it.** Confirm each new
   assertion actually goes red on the mutation it claims to catch —
   three green-but-worthless suites were caught only this way.
