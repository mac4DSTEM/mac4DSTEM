# Open items

Live defects, debts, owed runs and open questions only — status is
`docs/status.md`, history is `docs/archive/`. Four lanes (owner, 2026-09-03):
**Science** items are taken one at a time in the order the status handoff
names, carry no release number, and a landed change to a scientific output
cuts v2.6.0; **Verification debt** closes when its run happens; **Known,
scoped** items and the owner's bug reports ship in the next v2.5.x patch;
**Code hygiene** rides with the session that touches its file. Each entry is
≤ 12 lines and dated: what is wrong, the pinning evidence, the trap, the
owner. No narrative. Closed items move to
[`docs/archive/closed-items-2026-09.md`](archive/closed-items-2026-09.md); the
file before the 2026-09-07 trim is verbatim in
[`docs/archive/open-items-2026-09-07.md`](archive/open-items-2026-09-07.md),
the 2026-09-02 pre-cull file beside it. The merged UI-findings list is
[`docs/archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md) §3 — point there.

## Code hygiene — added 2026-09-08 by the delegated drive

### Info's "Loaded view" keeps a caption whose button moved to Settings
Found by review of the C4(c) diff, 2026-09-08, not yet seen on screen.
`UI/WorkspaceInspector.swift` `loadedViewSection` (Info tab) still renders the
"Reloads the whole cube — N GB as float32…" cost sentence and a
`PromoteRunCaption`, but the "Reopen at Full Extent" button those describe now
lives in `DatasetActionSections` (Settings tab), where it has no cost caption.
`PromoteRunCaption` is therefore instantiated from two places whenever the
view is not at full extent. Presentation only; no scientific number. Trap: the
fix is to move the caption to the button, not to re-add the button to Info —
C4(c) deliberately emptied Info of actions. Owner: next session touching
`WorkspaceInspector.swift`.

## Verification debt — added 2026-09-08

### Owed on screen from C4(c): failures and confirmations
The four failure paths (ROI-sum, sidecar inventory refresh, configurator
single-pattern preview, "No preview available") reaching the status strip, and
the Remove / two Reset confirmation dialogs, were not exercised in the
2026-09-08 drive. Everything else in C4(c) was seen (`status.md`'s C4(c) row).

## Science — Gate D or Gate B owed

### A red real-data gate names the symptom, not the cause (2026-09-09)
`compare.py`'s `fail()` raises `SystemExit`, so a run stops at the first
mismatching field of the first mismatching file. On 2026-09-08 it printed
`diskSampleCandidateCounts` and never reached `diskProbeRadiusPixels`, where
the change was, nor the cubes after it — and the one golden verdict in the log
was read as three, because the harness's own `PASS: <file> <shape> in <t> s`
lines look like verdicts. Wanted: collect every mismatch, fail once. Confirmed
by the Gate D refuter. `comparator-test` gates this file too. Owner: cheap.

### Real-data numbers are pinned by one harness only `all` reaches (2026-09-09)
`tools/real-data-acceptance/run.sh` says `all` "is the only one that reaches
this harness at all". `ba6360d` moved a measured probe radius on 2026-09-05,
`scientific` stayed green three days, and by the time `all` ran, 43 commits
stood between change and symptom — the entry written from it blamed two
innocent ones. Options, uncosted: add the harness to `scientific` (which
already reads the cubes), or gate science-lane commits on it by hand.
Main-only: `ba6360d` postdates v2.5.1, so no shipped build carried it.

### The acceptance harness pins peak COUNTS, never positions (2026-09-09)
Gate D refuter: `AcceptanceReport` (`main.swift:6-22`) has no coordinates, so a
change moving every peak while preserving the count is invisible. On `ba6360d`
all 36 `downsample_Si_SiGe_exp` peaks shifted 0.005-0.02 px and one
`calibrationData_bullseyeProbe` peak was SUBSTITUTED — (114.2198, 194.8632) ->
(140.6368, 196.8596), ~26 px — count unchanged at 11, harness silent
(`scratchpad/drift/refuter/peak-position-diff.txt`). Likely two near-threshold
noise peaks trading places (the noise item below), not a defect; the defect is
that the gate cannot tell. Owner: a checksum needs a tolerance — a design pass.

### Bullseye disk detection accepts noise — two of three fixes landed 2026-09-05, drive owed
Owner playthrough 2026-09-01 (`calibrationData_bullseyeProbe.h5`). Gate D on
py4DSTEM truth (`tools/bragg-spacing-probe/bullseye-kernel-truth.py`): (1) the
probe-size estimator reads the ring-shaped probe at 7.4 px where the ring ends
at ~10–12; (2) the trench kernel at THOSE radii leaves the beam never
brightest — at the true radii it works as well as flat, so (2) is (1) in
another guise; (3) correlation noise is 2–5 % of the beam peak, so the 0.5 %
default keeps ~130 noise peaks/position. LANDED: flat mode + Use File's
Probe, parity 878/878 and 164/164 with py4DSTEM's flat route (`status.md`).
OPEN: (1), an outer-edge probe size for structured probes (it also feeds the
origin window — its own Gate D). Owner: drive Map ▸ Bragg disks on the file
with Flat + Use File's Probe at Min relative intensity ~0.05.

### Origin-fit gate has two unresolved holes (2026-09-05)
(a) closed 2026-09-05: `probeSize` refuses (nil, `probeNotMeasurable`) when
no finite pixel is above zero or no mass clears the threshold; non-finite
pixels are skipped at every step; the median matches `np.median` for even n
(`ProbeSizeTests`; the refuter's +inf escape closed, two mutants caught).
(b) Which statistic gates `originFitIsSane` is open: full-scan RMS (current)
cannot see bias; the robust/kept-set residual tried 2026-08-28 was reverted —
it passes a 15 px-displaced fit at 9.94 px. (c) The trimmed fit is blind to
spatially clustered failure and contamination ≥ 50 % (a 40 px-off quarter of
the scan gives 100 % kept, 20.6 px error; an exactly bimodal residual zeroes
the MAD guard). Owner: a design pass — no statistic proposed yet separates
displacement from contamination. `docs/q-calibration-design.md`.

### The origin's coarse block seed lands on the wrong blob on noisy cubes (2026-09-05)
Gate B refuter (`q-calibration-design.md` §9,
`tools/origin-fit-diagnostics/origin-kernel-twin.py`): against py4DSTEM's
Gaussian-argmax seed, the app's block-sum seed puts 28/169 positions of
`downsample_Si_SiGe_exp`, 29/195 of `Particle_1` and 2/169 of `COPL` more
than 1 px away — unchanged by the iterated window, which cannot leave a
wrong block (a DEVIATION recorded in the kernel header). Clean cubes: 0.
Trap: the plane fit's trimming hides most of these, so the fitted origin
looks fine while `excludedFraction` carries them. Owner: a design pass on
the coarse step (Gaussian-filtered seed, or a coarse-to-fine window) before
the origin-fit holes (b)/(c), which it would move.

### CIF import can silently accept a wrong crystal (2026-09-01)
(a) A non-P1 declaration with a PARTIAL ops list still imports the wrong
cell (`verifyFamily` can pass it — Gate B refuter escape E2, 2026-09-01,
recorded not fixed; the missing/identity-only case is guarded). Trap: needs
a 230-entry IT-number→group-order table the importer deliberately lacks —
cheap mitigation, new scope. (b) closed 2026-09-05: the ACOM recipe step
records `material_fingerprint` (`CrystalModel.contentFingerprint`, FNV-1a
over cell, symmetry and basis) for imported models and `resolveMaterial`
refuses by name when the session's same-named import differs; pre-key
records still resolve by membership (`ReplayPlanTests`, `CIFImportTests`).
Owner: (a) unclaimed, Gate B when picked up.

### ACOM orientation/export coverage gaps (2026-08-31)
Found in W4b Gate B; the shipping numbers are believed correct but nothing
gated would catch a regression. (a) Exported Euler angles are labelled
py4DSTEM/orix-compatible but differ by frame rotation `P` — median 38.55°
misorientation if compared naively; math right, label wrong. (b) The
projection convention (`OrientationPlan.project`) is verified three
independent ways, but every gated ACOM harness builds its own peaks through
the function it tests, so two frame-mutation bugs stay green — no analytic,
non-self-referential fixture exists yet. (c) The exported orientation matrix
can decouple from the reported template index unnoticed. (d) Unpinned: an
additive radial offset, the reliability distinctness test, `intensityPower`.
Owner: (a) relabel-vs-convert decision then Gate B; (b)–(d) Gate B.

### Q-calibration scale defects on real crystals (2026-09-02)
(a) closed 2026-09-05 by Gate D + B (`q-calibration-design.md` §8): the
per-position minimum was the same spoke at 99 % of WS₂ positions — a 0.26 px
origin-fit offset, which a symmetric cluster MEAN cancels; the cluster reads
18.902 px against 18.901 from the independent 11-20 shell; `estimate` now
averages the same-shell cluster (14 mutations, 79 harness checks). Residual,
folded into (b): on a single crystal with a 2.4 % Friedel-pair asymmetry
(sim_Au) the band truncates clusters and neither estimator is shown to be
truth. (b) The reference-shell pick has no l-filter or visibility filter; on
2H-WS₂ it selects (0002), which a [0001]-zone specimen never shows —
predicted mis-scale 2.26×, silent; at that scale the correlation score
HALVES while median `reliability` RISES, so no fix may lean on reliability
to choose between scales. Owner: (b) its own design pass.

### Twisted bilayer graphene finds only the beam at defaults, at either reference (2026-09-05)
Observed (`det-experiment-20260905.log`): 10 201 positions, one accepted
peak each, with `relativeToPeak` 0 AND 1 — so the relative threshold is not
what removes the disks; the funnel is one local maximum before any threshold
(probe r 25.3 px, spacing 16, edge 5 on a 128 px detector). Not diagnosed:
whether the 25-px synthetic kernel's correlation has a single maximum, or
the edge boundary/spacing swallow the ring at ~38 px. Owner: unclaimed; a
Gate D with the per-pattern funnel on one position.

### #18 — training-dataset campaign can't reproduce the app's Si_SiGe strain (2026-09-02)
Mechanism resolved: the campaign's fitted mean origin is ~7 px off centre
(non-quantitative fit), which poisons `estimateLatticeBasis`'s clustering
scale; the app's own gate rejects that fit and falls back to the true
detector centre. Latent app-side risk: a genuinely off-centre beam with
`meanOrigin` nil would fail the same way. Two candidate fixes, neither made
(science changes, own Gate B): floor `minRadius` at the probe radius or
scale it with fit quality; or have the campaign adopt the app's origin
gating. Full diff in the archive.

### ACOM omits py4DSTEM's `power_radial` weighting (2026-08-28)
`orientation_plan` applies `power_radial=1.0` to the template side
(`crystal_ACOM.py:32,810` in the pinned source); `OrientationPlan.buildPolar`
doesn't, so outer shells are under-weighted by ~r relative to py4DSTEM.
Untested materiality — apparatus exists (`tools/acom-groundtruth`) but the
Python driver that built prior test inputs wasn't retained. Also
un-DEVIATION-noted (hard rule violation): the app subtracts each ring's mean
where py4DSTEM leaves that line commented out. Owner: whoever next touches
ACOM weighting.


### No automated visual baseline (2026-08-17)
Every acceptance run is numeric-only; the owner driving the app is the only
evidence anything "looks right" — say who drove it and when. Driving has
caught defects with every harness green (colormap control missing, readiness
row self-contradicting, three more in the clean-account run, five sessions
running in September). The retired checklist's trap notes are in
`docs/archive/v2/visual-acceptance-checklist-2026-09-03.md`. Never seen on
screen: the six `status.md` rows marked unverified, light appearance, every
divider, a real load cancel, the bounded promote run. Owner: C3, one sitting.

### macOS 14–25 is supported and has never been run there (2026-09-04)
Floor lowered 2026-09-04 (`decisions.md`): `MACOSX_DEPLOYMENT_TARGET` 14.0 in
all four configurations, `Package.swift` `.macOS(.v14)`; two cosmetic symbols
behind `#available` (`ToolbarSpacer`, `.pointerStyle(.columnResize)`); macOS
13 is unreachable (`@Observable`). Established by building at 15.0, 14.0 and
13.0. Published as macOS 14+ from v2.5.1: a true statement about the
artefact's floor, not a claim every version was exercised. **The live gap:
no machine or VM here runs below 26**, so 14–25 is compile-verified and never
executed; a VM would close it and needs ~40 GB. `tools/package-test`'s floor
assertion is derived from the project, so it no longer flags a floor change.

### Residency `.automatic` cannot be re-measured without a second machine (2026-08-19)
Dropped by decision (v2 S3), not dormant — do not set
`ResidencyAdmission.measuredWorkingSetFraction`. The three checked-in
training cubes top out at working-set ratio 0.19 on this machine; no knee
exists in that data. A second-machine sweep is the only thing that could
reopen it, and if two machines disagree the rule needs a second term.

### An emptied manual Q field, confirmed, discards the file's calibration (2026-09-07)
Agent drive, C3 (`scratchpad/drive/shots-c3/b2-qr-unset-bug.png`): on the COPL
cube (Q pixel scale green "From file 0.156828"), typing `0.2` into Prepare's
Manual field entered nothing (this locale wants `0,2`; the period was dropped
silently), and Return on the now-empty field flipped the row to "Not set /
Reciprocal dimensions remain in pixels" and the scale bar from `0.5 Å⁻¹` to
`5 px`. `0,25` typed afterwards worked live. Two things to establish before a
fix (Gate D): why a period is rejected rather than parsed, and whether an empty
manual entry should clear the file value or restore it. Owner: `/diagnose`.

### The first sidecar save already names the file `.mac4dstem.h5.h5` (2026-09-07)
Agent drive, C3 (`shots-c3/b3-savepanel.png`, `b3b-sidebar.png`): "Save
Calibration to Session Sidecar" on the COPL cube proposed the dataset stem and
wrote `…20240912.mac4dstem.h5.h5`; the sidebar and the reopen both use that
name, so it works, but the doubled suffix recorded as a repeat-save residual
below happens on the FIRST save. The owner's own folder already holds
sidecars of both spellings. Owner: `/diagnose` (the save panel's default name
vs its allowed extension is the first thing to look at).

### C3 drive leftovers: presentation observations (2026-09-07)
Presentation (C4, no Gate D): the status bar's `0` / `%` wraps during a run
(`shots-c3/a5-running.png`); at ~1 080 pt the status text wraps and the bar
grows (`a3b-narrow.png`); the log opens at its top (`a6-log.png`); a fresh
open shows the Bragg-vector slot or the automatic pass's Virtual detector
depending on the previous state (`b1-configurator.png` vs `b3d-reopened.png`);
"Open with Options…" is reachable only from the empty-state view; "Correlation
power, 1.00" wraps with a stray comma (`a9-strain.png`); System Events cannot
resolve the window's content (VoiceOver question); launching with `-NSRequiresAquaSystemAppearance 1` or
`-AppleInterfaceStyle Light` gives a windowless process. The owner's four
checks closed 2026-09-07 23:38 (light, Remove, crop restore, the warning).
Still unprovoked: staleness (f), and "Fit Detector Ellipse" on the demo ending
in "residual is too large (0.247)".

### Two diagnostic harnesses gate nothing (2026-09-02)
`tools/bragg-spacing-probe/` and `tools/residency-sweep/` both need
gitignored multi-GB data and stay diagnostics only — not a gap to close,
a standing limit to remember before citing them as coverage.

### Learned detector above 256 px: the probe channel's anchor (Gate B, 2026-09-08)
`LearnedDiskDetector.detectAll` crops the probe channel clamped-centred for
every window while the pattern windows sit at `windowOrigins`, so on a
detector above 256 px the probe and the pattern do not share one anchor —
the opposite of every training input (`simulate.py` "the SAME anchor for
both"). The >256-px path has no Python reference (`evaluate.py` never tiles);
its tests are Swift against Swift. Nothing shipped is above 250 px. Owed: one
synthetic >256-px detector scored under clamped-centred vs per-window-anchored
probe placement before the windowed path is quoted as measured.

### #30 — origin calibration over a NAS runs at ~3 MB/s (2026-08-06)
Investigation owed; nobody has measured it since.

## Known, scoped, not blocking

**UI findings** — the merged, trust-ordered list (provenance inference, ACOM
confidence gating, calibration-state vocabularies, unit labels, Phase
linearity, inspector layout) lives in
[`docs/archive/v2/v2.5-plan.md`](archive/v2/v2.5-plan.md) §3. Do not
duplicate it here and do not patch findings 1/4/5/7 on the current facade —
they wait on the architecture seams (C4/C5).

### UI polish: six papercuts, all verified live 2026-09-09
Presentation only, no Gate D. Info renders the "Reloads the whole cube" cost
sentence and a `PromoteRunCaption` for a button C4(c) moved to Settings
(`WorkspaceInspector.swift:295,301`; move the caption to the button, do NOT
re-add the button); `gammaControl` prints "Gamma, 1.00" as one string where
slice 1 made every other slider two texts; ⌘R (`mac4DSTEMApp.swift:89`) and ⌘↩
(`WorkspaceView.swift:229`) both run the primary action; no `representedURL`
anywhere, so no proxy icon; `TabView` (`WorkspaceInspector.swift:32`) unstyled;
log height is `@State` (`WorkspaceView.swift:25`) where eight siblings use
`@SceneStorage`. Triaged against the drive's findings, fix-now list lands
before 3.0.0 (`decisions.md` 2026-09-09). Stale claims struck: CUA works, and
both gates ran at 8.2 GB free.

### Concurrent HDF5 use crashes the process (2026-08-19)
`EXC_BAD_ACCESS` in `libhdf5.dylib`\`H5SL_search`, reproduced under lldb
within a few dozen iterations; the bundled build is `Threadsafety: OFF`.
Live latent crash: `loadSession` runs on `Task.detached` while an
`H5Reader` actor may be working, plus an uncancelled
`preloadResidentCube`. Unowned.

### Fabricated provenance on pre-2026-08-18 sidecars (2026-09-02)
`AppState.swift:2854,2867` do `snapshot.loadSpecification ?? .fullExtent` —
a sidecar saved from a cropped view before that attribute existed is now
asserted full-extent rather than unknown. Both prior reproducers were
overwritten by later driving sessions; demonstrating it again needs a
synthesised sidecar, not a training-set one. Unowned, belongs with the
trust fixes.

### DM4Reader silently reads the whole file into RAM off non-local volumes (2026-09-02)
`.mappedIfSafe` (`Core/Data/DM4Reader.swift:97`) declines to map on any
volume failing `MNT_LOCAL && !MNT_REMOVABLE` (confirmed by S9b: every
external disk, every disk image even on internal SSD, all smbfs) and
silently falls back to a full anonymous-memory read — held for the whole
session. `H5Reader`/`VendorRawReaders` are immune (hyperslab/seek reads).
No fix landed; `.alwaysMapped` trades this for a SIGBUS risk if the
volume disappears mid-read. Needs a CI fixture (a disk image on the internal
disk reproduces `MNT_REMOVABLE` with no external hardware). **The original
2026-08-18 8 GB-machine death that motivated this is still NOT explained** —
the mechanism is real and worth fixing but not established as that
incident's cause. Owner: a later session, Gate B.

### Scan-fastest DM4 detector pair may be transposed — Gate D owed (2026-09-05)
`Si-SiGe.dm4` stores its scan pair fastest; the reader maps the tags as
`[Rx, Ry, Qy, Qx]`, a pattern 480 wide × 448 tall. DM's convention, which the
same code applies to the scan pair (survey `Spectrum Image Rect` 202 × 895 px
= 17 wide × 77 tall confirms it) and to detector-fastest files, is x first:
dim 3 = 448 = width. Nothing in the 2026-09-05 commit justifies the
asymmetry; its fixture was generated from the code's own model. A transposed
pattern silently flips strain axes and the R–Q rotation. Owed: the owner
reads the pattern's width and height in GMS. If 448 wide: flip
`DM4Reader.scanFastestStrides` and the scan-fastest shape line, then pin a
checksum from ncempy's raw array on the real file. Residual: honour newer
GMS's `Meta Data.Data Order Swapped` tag (LiberTEM reads it first).

### The open/promote unwind is sixfold, and Cancel can vanish mid-load (2026-09-04)
Six begin/finish brackets, not three: `openFileAsync`, `commitPendingLoad`,
`promoteToFullExtent`, plus `selectDataset`, `openManualPath` and
`openDemoFixture` with no cancel handling at all. The old hazard 1 is
refuted — no suspension point sits between the last cancellation check and
`finishDatasetLoading` on any path (`AppState` is main-actor isolated,
`project.pbxproj:492`). Hazard 2 is worse than recorded:
`finishDatasetLoading` (`AppState.swift:2800`) unconditionally nils
`datasetLoadCancellation` and clears `isLoadingDataset`, both of which
`canCancelDatasetLoad` (`:1162`) depends on — with two loads in flight the
FIRST tail to finish disarms Cancel for the second. Unification alone is not
the fix; no fixture exercises these branches, and that is the precondition.
Owner: whichever session next touches any of the six.

### Promote/replay residuals (2026-09-02)
(a) Owner design question: should promote carry the scan position across,
or land at (0,0) as today? (b) Fitted origin maps are crop-sized and dropped
by the full-extent restore's shape check, so a promoted recipe recorded
against "calibrated origins" refuses — expected behaviour, not a bug. (c)
Parallax/ptychography are deliberately NOT in the replay record (not
bit-reproducible); folding them in is its own session. (d) A user-initiated
analysis mid-replay steals the Cancel control from the replayed step. (e)
Per-kind replay contracts live in three places (record/parse/apply) held
together by tests, not structure — co-locate per kind when the next kind is
added.

### Recents/window-state edge cases, both low priority (2026-09-02)
Each window's `AppState` holds its own `RecentDatasets` snapshot over one
`UserDefaults` key, so a second window's save can clobber the first's
entry (single-window use, the shipped reality, is unaffected). Separately,
`openRecent`'s failure path removes a dead entry from the list but leaves
"Reopen" dead-ending in "No recoverable dataset." Both unclaimed.

### Legacy `.icns` tops out at 256 px — reopened 2026-09-07 (the floor is 14)
Called moot on 2026-09-04 because the floor was 26; the floor is 14 since
v2.5.1 (`decisions.md`, 2026-09-04), so the reasoning inverts. On macOS 26+
Get Info, Quick Look and large Finder icon views render from the `.icon`
source; below 26 they render from the legacy `.icns`, whose largest
representation is 256 px, so a 512/1024 px icon view shows an upscaled icon
there. Cosmetic; never observed (no machine here runs below 26). Fix: a full
legacy PNG set (16–1024 px, @1x/@2x) in the `.icns`. Owner: unclaimed;
verify on the first report from an older system, or in the VM above.

### Resident/streaming residuals (2026-09-02)
`releaseResident()`'s "freed" claim is asserted by a derived byte count,
never a measured one — a leaked `MTLBuffer` is invisible to every test.
`TiledDiskDetection.detectAll` still stages each tile into a fresh
`MTLBuffer` (out of S18's bounded staging-copy elimination). Resident
cancellation is 2.5× coarser than streaming (one indivisible dispatch) —
academic until something under `mac4DSTEM/` requests `.resident`, which
nothing does today.

### Toolbar Cancel button renders wrong during a run — cosmetic, not blocking (2026-09-04)
Owner, seen driving a full-scan Bragg detection on
`sim_Au_data_all_binned.h5`. `WorkspaceView.swift:231` is a bare
`Button("Cancel", role: .cancel)` with no `.buttonStyle`, so it renders as a
bordered text pill beside three icon-glyph toolbar buttons; `role: .cancel`
buys nothing in a toolbar. The action WORKS — appearance only, and the owner
called it not a big deal. Note the comment above it (`WorkspaceView.swift:224`):
the old inline progress bar was removed there precisely because it squeezed
this label to "C…", so a fix must not reintroduce a width contender in that
slot. Exact symptom still the owner's to pin down (style vs size vs
placement) before anyone changes it.


### Sidecar/session UX residuals (2026-09-02)
Recents-row location labels unverified on screen (F1.1c). A sidecar
retarget made before any save survives only until the next dataset
change. Repeating "Save Session Sidecar As…" can prefill a doubled
`.h5.h5` suffix. Pre-S4 calibration-only sidecars remain unrecognisable
(extension/open-panel-filter half is an owner decision). The configurator's
beam proxy has no "load anyway" override (owner question; unifying it with
`CalibrationReReference`'s gate is a deliberate non-unification,
`Session/SessionGates.swift`).

### DPC's banner contradicts its badge — entry corrected 2026-09-04
Three claims here were wrong. **Mechanism:** the fall-through is `.relative`
(`AppState.swift:761`), not `.quantitative` — only named families are
quantitative (`:759`). Still true: it pattern-matches strings and consults no
calibration readiness, while `idpcPhysicalCalibration` consults three gates.
**Carrier:** not XMP — the PNG `Description` JSON chunk and the status burned
into the caption's pixels (`ResultExport.swift`). **Headline:** iDPC's badge
and banner AGREE; the contradiction is `PhaseSettings`' always-shown
qualitative banner over `dpc_magnitude` / `dpc_angle`, which
`quantitativeStatus` calls quantitative. Before any fix: status is frozen at
publish and at persist and preferred over re-derivation on restore, so a
change corrects neither existing sidecars nor exported PNGs, and there is no
version field to migrate on. Owner: the trust-fixes session; a judgement call.

### Misc unclaimed, low priority (2026-09-02)
Load-cancel: F1.1d (cancel a real load on screen) never driven; resident
buffer/cropped-view teardown unpinned. #17a: the wider pane-arrangement
question (design decision, reverted on sight once). Detector-bounds
convention sweep: whether other tests use an index convention for
continuous positions besides the one already fixed, nobody has checked.
HDF5 multi-dataset axis order is assumed (`[ry,rx,qy,qx]`), not checked —
only Ry↔Rx/Qy↔Qx transpositions would be silent, and the app names the
dataset it picked. `MAC4DSTEM_ACOM_SCALE_OVERRIDE`: the sidecar keeps the
estimate scale, not the override scale the map was matched at (design call).
Virtual-detector mask boundary (`r² < rOut²` vs `<=`) is unpinned against
analytic truth. #31 `validationIssues` is O(n²) in a SwiftUI view body. #32
`isSymmetry`'s bijection check has no fixture coverage.

### The constraint-loop crash: nothing in a split may change its own minimum (2026-09-04)
`NSGenericException` from `_postWindowNeedsUpdateConstraints`, through
`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`. **The
rule, demonstrated 2026-09-04: nothing inside a split's hosted content may
repeatedly change its own minimum size.** SwiftUI's split machinery loops on
it, and `NavigationSplitView` and `.inspector` are splits too. `.fixedSize()`
on text whose string changes is the easiest way to do it by accident, and it
only fires on a dataset big enough for an operation to tick — every
demo-fixture launch was clean and a real one died. Two sites, both in the
status bar, both fixed. Full diagnosis and the refuted `HSplitView`
conjunction: commits `e608dbd`, `27de9bb`; the S17 record is archived.
Residuals: n=1 each way against a fault once called intermittent; the
inspector's Performance rows still tick per second. Owner: unclaimed.

### `PaneSplit` residuals from the refuter (2026-09-04)
(a) header overflow and (c) the divider resetting to centre are closed and
were seen on screen 2026-09-07 (`shots-c3/a3b-narrow.png`, `a4b-divider-back.png`).
(b) **The image floor lapses
below 2× itself**: the fraction saturates at 0.5 under ~360 pt of usable
width, and UI declares no detail-column minimum where the retired AppKit UI
had `SplitViewPolicy.detailMinimum` = 360. SwiftUI offers no detail-column
minimum short of the window's own floor, and announcing one from inside the
split is the constraint-loop shape; recorded, not made. Owner: with the
owner's drive (C3).


### Manual Q and R pixel scale cannot be corrected once entered — fixed in code, drive owed (2026-09-04)
Owner, on `downsample_Si_SiGe_exp.h5`: enter a manual Q or R pixel size, the
row turns green and the field disappears with it. A wrong R scale silently
rescales every real-space axis, scale bar and export, so this is a trust
defect. **Code fix 2026-09-05** (second cut; the first locked a restored
session value and an imported Q, and committed two red tests against
itself): `PrepareSettings.shouldShowManualScaleEditor` keeps R editable
always and Q editable for every provenance except measured-in-app, with the
hover text naming the value an entry replaces; Prepare and ExportSheet share
it, three unit tests pin it. Owed: the owner drives both surfaces and sees
the fields stay visible and editable after the row is green.

### `calibration.*` identifiers exist twice while the export sheet is open (2026-09-04)
`ExportSheet` re-renders the readiness rows, so `calibration.readiness`,
`calibration.item.*`, `calibration.rScale.filenameConflict` and
`calibration.action.originProbe` are each emitted by both it and
`PrepareSettings` while the sheet is up. Harmless today — nothing queries them
at runtime — but it would defeat any future UI test that addresses a readiness
row by identifier. The old app had the same collision. Owner: unclaimed.

## Code hygiene

### `tools/free-space.sh` still spells shared path knowledge three times (2026-09-04)
Fixed 2026-09-04, the misreporting half: it prints the two volumes the
preflight gates (`$ROOT`, `$TMPDIR`), answers "will the gate run?" against the
8 GB floor, and surveys the regenerable roots outside its two (DerivedData,
`ModuleCache.noindex`, `CodingAssistant`, `.build`). Report-only;
`guard_path()` untouched, and `build/release` (notarized, stapled images)
prints as PROTECTED. Residual: the temp prefix is spelled by producer and
reaper separately and the MCP root is hardcoded (the 50 untagged
`mktemp -d` sites were tagged `mac4dstem-<harness>` in C2, 2026-09-07). A
`tools/lib/` constants file is deliberately NOT taken — every gate sources
through `run-tests.sh` under `set -euo pipefail`, so a bad line there kills
the whole harness. Owner: whoever next touches `run-tests.sh`.

### Acceptance-gate test-infrastructure residuals (2026-09-02)
`real-data-acceptance/run.sh` sources `tools/lib/sources.manifest` since C2
(2026-09-07). Its empty-glob SKIP exits 0, so a machine with
zero datasets passes the gate; whether it should consult `expected.json` is
open. The 15 s acceptance budget gates the 4 pinned datasets only —
pin-or-refuse vs the advisory `UNPINNED` line is an open call. `abs_tol=1e-3`
on virtual-image fields exceeds `polycrystal_2D_WS2`'s whole dynamic range
(5.3e-4); not tightened, but the fixture carries a WS₂-magnitude case so the
boundary is testable. Comparator: `rel_tol` on `diskProbeRadiusPixels` is
inert below 50 px; `if not actual:` is unkillable by any mutation. The runner
aborts at the first red harness, so it cannot say how many are red.

### `.fixedSize()` in `UI/`, audited 2026-09-04 — one armed site, contained
12 bare call sites against the constraint-loop rule above (an unanchored grep
says 16; four are comments *about* it — use `grep -rn '^\s*\.fixedSize()'`).
**One is armed**: the zoom badge (`ImagePanes.swift:587`, inside
`zoomModeBadge`): `ZoomPan.liveZoom` is written on every magnify event, the
digit count moves (×9.9 → ×10.0 → ×100.0), the value is unclamped mid-pinch,
and the badge appears and disappears across ×1.0 — a `.fixedSize()` child
inserted and removed repeatedly in one gesture. The rest are literals or
change once per published product. **Not fixed, deliberately:** a reserved
slot closes the string-width channel and NOT the appears/disappears one.
**Not urgent:** `PaneSplit` gives each pane `.frame(width:)`, which
terminates its minimum, and none of the 12 is in the one `.safeAreaInset`
where both crashing sites lived. Owner: with `PaneSplit` residual (a).

### Harness type replicas of `Aperture` (2026-09-02)
Every runner sources `tools/lib/sources.manifest` since C2 (2026-09-07; the
inventory fails one that does not). What remains: `Aperture` is declared in
`App/AppState.swift`, and scientific harnesses carry their own copies that
would still compile and pass if the app's gained a field — it belongs in
`Core/`. The app build is the only real gate for actor isolation
(`tools/load-spec-test` compiles nonisolated; the manifest's isolation flags
buy visibility, not enforcement). Owner: the next `AppState` extraction (C5;
the first, the fit overlays, landed 2026-09-07).
