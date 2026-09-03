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
plus [`docs/archive/closed-items-2026-08.md`](archive/closed-items-2026-08.md).
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

## Verification debt

### S17 sidebar intermittent — observation log
`SidebarLayoutTests.testEveryNonQuarantinedWorkspaceSidebarFitsItsColumn`
fails intermittently with **Strain & ACOM (calibrated) at 810.5pt against
786pt**, the number the test's own comment records for rows wrapping at the
250pt minimum width (`ContentView.swift` publishes `max(width − 34, 216)`).
2026-09-03, v2.5 step 2c tree, no app instance running, no sidebar key in
the defaults domain: failed 2 of 5 runs (full unit run; class run), passed 3
(single test; class twice); the 2b tree passed its one class run. Then 0 of
14 full runs through step 4b; on the step 5a tree 3 of 4 (one full run and
two class runs red at the same 810.5, the next full run green). 5a adds
observation reads to the header action, which may raise how often the
width race fires; the content is unchanged (the extra disks row is shown
only while unmet). Trap: it
is not a package-split regression — the A/B was run — and it is not the
autosave leak the comment describes, since the domain was clean. Owner:
whoever next touches the sidebar layout; the pin-then-measure sequence needs
a second look at what re-applies the 250pt minimum after `setPosition`.
2026-09-03 owner repro changed the severity: dragging the left tools panel
crashed with `NSGenericException` ("window has been marked as needing another
Update Constraints in Window pass..."). Diagnosis: the hard SwiftUI
`.frame(minWidth:)` on the column root fights AppKit's split-view drag.
Fix in progress: remove that hard floor; rely on `NavigationSplitView` +
`SplitViewPolicy` AppKit bounds/restoration clamp; needs live re-drive. 2026-09-03, the split-view policy tree: 1 of 2 full-class runs red at the
same 810.5 (the red run also carried a 144pt sidebar a new test had autosaved
into the shared domain — the tests now unpin the autosave first); the re-run
was green.

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
560pt sidebar squeezes the inspector first, no exception. Owner's drive
still owed before the entry moves to the archive.

### No automated visual baseline
Every acceptance run is numeric-only (`--no-screenshots`); the owner
driving the app is the only evidence anything "looks right" — say who
drove it and when. Standing: driving has caught defects with every harness
green (colormap control missing, readiness row self-contradicting, three
more in the clean-account run). The retired checklist's trap notes are in
`docs/archive/v2/visual-acceptance-checklist-2026-09-03.md`. Never seen on
screen: everything from 7c slice 1 on (Results sidebar and inspector, the
inspector following the focused pane), the clean-account run, the bounded
promote run, a real load cancel.

### `tools/run-tests.sh all` has not been re-run on the newest tree
Last full green run was the DPC-angle-unit closeout tree; `unit` and
`scientific` have each re-run green individually since (including on the
FFT/R23 tree, 429/0/2 and 42/42), but the aggregate `all` itself has not.
Do not quote an aggregate you did not just run.

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

### The UI rework — what the owner's drives found, by step
Owner drives 2026-09-03 (`df80e8e`, then step 1 `9493242`): (a) a wide
sidebar puts every trailing value ("Not set", the voltage, the Manual
scale fields) at the far edge — hand-built `LabeledContent`/`Spacer` rows
fill whatever width they get (step 2); (b) the inspector's Real space,
Mean and Max thumbnails fill the column (S22a told them to; step 3);
(c) the dividers' grab zone — fixed in step 1, owner-confirmed; (d) no
Liquid Glass on the sidebar and inspector while the toolbar has it —
something inside the columns paints over AppKit's material, candidate
the hosting `List`'s own background; diagnose before touching (step 2a);
(e) dragging one divider moves the opposite column — holding priorities
(inspector 260 < sidebar 261 < content 262) make the inspector yield on
any drag; Xcode's editor holds least, so a drag resizes only the content
(step 2a). Trap: cap the columns and you lose the wide-drag the owner
asked for. Owner: the rework; lane: the rework, no release number.

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

### Sidecar restore doesn't check the calibration frame against the view
`applySessionCalibration` adopts a saved calibration verbatim; a sidecar
saved at full extent and restored onto a reconfigured (cropped/binned)
view leaves a source-frame calibration beside reduced pixels (S10 Gate B
finding 2). Related: `AppState.exportableRecipe` refuses rather than
composing across frames when recorded frame ≠ live view — a three-frame
composition (recorded→source→exported) that needs a transform
`ReplayFrameTransform` doesn't have. Both unowned, predate S10.

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

### The open/promote unwind choreography is triplicated
`openFileAsync`, `commitPendingLoad`, `promoteToFullExtent` each hand-roll
the same begin→activate→cancel/discard→finish tail, with the ordering
rules documented in only one copy. Two live hazards: a cancel landing
between the last check and `finishDatasetLoading` is silently swallowed
as success; a second initiator (e.g. ⌘O mid-load) replaces the shared
cancellation token so Cancel only hits the newer load (open-during-load
direction; promote's own entry is already guarded). Owner: whichever
session next touches any of the three.

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

### Legacy `.icns` tops out at 256px
On the macOS 14 floor this app declares, Get Info/Quick Look/large Finder
icon view upscale past 256px (macOS 26+ renders from the `.icon` source
correctly; the Dock is unaffected). Undecided whether to ship a legacy
PNG set alongside.

### `recordedLoadSpecification` bypasses the security-scoped bookmark
`App/AppState.swift:1416-1431` reads the sidecar through the derived path
only, never `resolvedSessionSidecarURL`, and swallows the failure with
`try?`. If the sandbox/bookmark hypothesis is right, F1.3f (crop survives
session save/reopen) fails silently — reopens at full extent, says
nothing. Driving F1.3f is both the acceptance row and the discriminator.

### Status line leaks a full filesystem path
~330 characters including the absolute path, rendered raw in
`StatusFooterView` and `ProductWorkspaceViews`' header progress; the
archived checklist's screenshots (public docs) have carried it since 2026-08-19. Worth
truncating for display while keeping the log copy. Still open.

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

### DPC result badged Quantitative while its banner says qualitative
`AppState.quantitativeStatus(for:units:)` pattern-matches strings and
falls through to `.quantitative` for anything unrecognised, never
consulting calibration readiness — verified escaping into exported PNG
XMP and a self-contradicting strain-export dictionary. Same architectural
family as the archived v2.5 plan's §3 item 1 (provenance is inferred, not typed);
fix is a judgement call (status consults readiness, or the badge changes
wording). Owner: the trust-fixes/error-honesty session.

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
bijection check has no fixture coverage. Launch-screen cards push real
entry points below the fold; at the 171pt pane-width floor the header
truncates and a badge wraps one letter per line. A saved sidebar divider
can restore below its declared 250pt minimum (observed 144pt).

## Code hygiene

### `tools/free-space.sh` duplicates path knowledge it can't see change
The temp-file prefix is spelled by the producer (`run-tests.sh:37`) and
twice more by the reaper, no shared constant; ~35 harness `run.sh` files
use bare untagged `mktemp -d`, invisible to any reaper. The
XcodeBuildMCP workspace root is hardcoded. The script reports `df -g /`
while the preflight gates on `$ROOT`/`$TMPDIR`'s volumes, which can
differ on a non-boot checkout. Measured once at 10GB free: the script
reported 0B reclaimable because the real pressure (Claude Desktop's VM
bundle, `~/.cache/codex-runtimes`, package caches) is outside its two
roots — do not conclude "nothing to reclaim" from a 0B report. Fix wants
one `tools/lib/` constants file. Owner: whoever next touches
`run-tests.sh`.

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

### 31 `.fixedSize(horizontal: false, vertical: true)` sites in `UI/`, unaudited
Count drifts with every UI change (was 22, then 31) — safe today and
covered by `SplitViewHeightTests`, but nobody has audited the set as a
whole, including the 4 in `TaskPrerequisiteChecklist` that caused a past
defect.

### Runner source lists still hand-spelled in places
`SessionReplayRecord.swift` is patched into seven runners by hand rather
than through the manifest, after predicted breakage recurred once
already. `Aperture` is declared in `App/AppState.swift`; scientific
harnesses carry their own copies that would still compile and pass if the
app's gained a field — belongs in `Core/`. The app build is the only real
gate for actor isolation (`tools/load-spec-test` compiles nonisolated;
the manifest's isolation flags buy visibility, not enforcement).

## Working methods that earned their keep

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
