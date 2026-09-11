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

## Repository review 2026-09-09 — added 2026-09-09

### D002 and D003 are CLOSED, and the register's count is now 111 (2026-09-09)
Both CRITICALs were taken through Gate D, refuted by an independent agent, and
fixed the same day. Evidence:
[`docs/archive/2026-09-09-review/d002-d003-gate-d.md`](archive/2026-09-09-review/d002-d003-gate-d.md).
Two hypotheses were **refuted** there and must not be re-walked: (a) that the
D003 overrun crashes `H5Reader` on open — it crashed one prebuilt binary 40/40
and a fresh build of the same sources survives 40/40, so the SIGTRAP is
allocator-layout luck, not a reproducible property; (b) that the ptychography
transpose result was proven by the demo cube — that cube is square with equal
row/column object sampling, so transpose was a geometric no-op there and the
finding was re-run on a non-square crop. Still unproven and stated as such:
that any real instrument writes a multi-element `units`/`name`.

### 119 unverified defect claims, and the adversarial pass that never ran
The whole-repo review produced 259 records and stopped mid-run; the
verification pass was still in flight. Deduplicated to 156 clusters in
[`docs/archive/2026-09-09-review/register.md`](archive/2026-09-09-review/register.md).
Three are fixed, 16 repeat and 8 may repeat the 2026-08-31 review, 8 are
already tracked here, **119 are new and none is verified**. They are claims
with a file and a line, not defects. Do not fix from the register: each one
that can move a scientific number is a Gate D of its own, and this repo has
shipped three confident wrong diagnoses. Triage before v3.0.0 should verify
the release-blocking ones only — a number moves, a clone breaks, the process
dies — and leave the rest listed. Owner: triage order.

### The three redistributed dylibs have no rebuild path
`libhdf5.dylib`, `libaec.0.dylib` and `libsz.2.dylib` are committed binaries.
As of 2026-09-09 `NOTICE` states each one's SHA-256, byte size and declared
`LC_ID_DYLIB` version, the licence texts are in `Licenses/` and ship at
`Contents/Resources/Licenses/` (verified in a built bundle, not assumed), and
`run-tests.sh inventory` fails if a dylib is unnamed in NOTICE or its hash
moves. What is still missing is a way to *make* them: they came from Homebrew
`hdf5 2.1.1` / `libaec 1.1.7` on one machine, and nothing in the repo rebuilds
them. Two consequences the hashes do not fix — a security update means hand
work, and the arm64-only build has no `ARCHS` pin, so the Archive path can
still produce an x86_64 slice that launches and fails on every data file
(register `D064`, unverified). Owner: whether v3.0.0 needs a script.

## Accessibility — added 2026-09-09 by the delegated drive

**Does NOT block v3.0.0** (owner, 2026-09-11; `decisions.md`). Deferred to a
far-future release. Kept here in full because it is a live defect, not a closed
one, and because it is not VoiceOver-only: any AX client resolving labels on the
front window trips it, so it blocks any automated driving rig and it crashed the
owner's own session twice on 2026-09-08.


### Reading an accessibility label crashes the app
Two crash reports, 2026-09-08 22:41:36 and 22:47:48, identical faulting stack
(`~/Library/Logs/DiagnosticReports/mac4DSTEM-2026-09-08-2241*.ips`,
`-2247*.ips`): `EXC_BAD_ACCESS`, `KERN_PROTECTION_FAILURE` at a stack guard
page — a stack overflow in
`AccessibilityNode.accessibilityLabel()` → `labelsToResolve` →
`resolvedRole(forPlatformElement:)` → AppKit `_accessibilityFindRoleFromProtocol`.
Triggered both times by an AX client resolving labels on the front window.
**VoiceOver does exactly this**, as do Accessibility Inspector and any UI
automation, so a VoiceOver user very likely cannot use the app at all. Not yet
narrowed to a view; the recursion is in SwiftUI's own machinery, so the trigger
is probably one view's accessibility modifiers, not app logic. Repro: walk the
window's AX tree resolving `AXTitle`/`AXDescription`. Owner: Gate D — cause not
established, and this is a crash. Blocks a credible accessibility claim at 3.0.0.

### In-body controls report no accessibility label — the same bug
`Compute Mean / Max`, `Fit Detector Ellipse`, the two image-pane buttons and
every `Advanced` disclosure come back as bare `AXButton` / `AXDisclosureTriangle`
with empty title, description and value, while AppKit-backed toolbar items
(`Hide Sidebar`, `Save to Results`, `Dataset`) and the `Accelerating voltage (kV)`
field report correctly. **This is NOT missing labels in the source** — checked
2026-09-09: they are already `Button("Fit Detector Ellipse")`,
`DisclosureGroup("Ellipse correction")`, `Label("Compute Mean / Max", …)`.
Adding `.accessibilityLabel()` would restate text that is already there, so it
was deliberately NOT done. The emptiness and the crash above are almost
certainly one defect in the same SwiftUI resolution path — the crash happens
while SwiftUI tries to DERIVE a label, and these are exactly the controls whose
label never resolves. Treat as one Gate D, not two fixes.

## Verification debt — added 2026-09-08

### Owed on screen from C4(c) and C7, after the 2026-09-09 drive
Still unexercised: the four failure paths (ROI-sum, sidecar inventory refresh,
configurator single-pattern preview, "No preview available") reaching the status
strip, and both Reset confirmations. **Remove IS confirmed** — the 2026-09-09
drive saw `Remove Saved Result?` with a red destructive button and a working
Cancel (`archive/v3/drive-2026-09-09.md`, finding 17). **C7's sidecar reopen is
half-answered**: the calibration round trip works — origin, probe and R–Q
rotation come back as "From session" / "Restored from session" after quit,
relaunch and reopen, and fields never set stay "Not set" (finding 10). The
disk-centre LABEL round trip is still unverified: the rig could not place a
label on the diffraction pane at all (finding 7), which is a Metal/Canvas view
that may simply not take synthesised clicks. That one needs the owner's hand, or
a rig that can. Also unreached, same cause: every `Advanced` disclosure, the
Strain / Orientation / Parallax / ptychography sub-pages, and the WS2 CIF import.

## Science — Gate D or Gate B owed

### The Quantitative badge consults no origin gate at all (2026-09-11)
`AppState.quantitativeStatus(for:units:)` is a pure lookup on a product's kind
and units strings: a `kind` in `["strain", "local_lattice", "dpc", "idpc",
"virtual_detector", "disk_detection", "matched_template"]` returns
`.quantitative` unconditionally, with **zero** references to `originFitIsSane`,
`originSupportsReciprocalMetrology` or `origin_reference_is_measured`.
Observed on the owner's drive: a strain map badged **Quantitative** on the same
screen where Prepare badged its origin **Not quantitative** (RMS 9.72 px against
a 3.74 px probe), computed against `origin_reference = apertureCentre`.
`Calibration.originFitIsSane`'s doc claims to be "the single owner of that
decision" (`Calibration.swift:550-570`); it is not consulted.

**A fix was written 2026-09-11, REJECTED by Gate B, and reverted** —
[`archive/2026-09-11-drive/quantitative-badge-gate-b.md`](archive/2026-09-11-drive/quantitative-badge-gate-b.md).
It recorded the verdict in provenance and gated the badge on it, and it changed
nothing: `publishProduct` composes provenance from
`currentScalarPersistenceMetadata`, whose strain branch never merges
`strain.originProvenance` — that snapshot has exactly ONE consumer in the tree
(`ResultExport.swift:516`, `scientificBundleMaps()`). Five tests passed and two
mutations that disabled the whole mechanism survived all of them, because every
test called the decision function directly and none asserted on
`publishedProduct?.quantitativeStatus`.

**The real defect is larger and is the thing to fix:** products do not carry the
origin they were computed against. Strain snapshots it and nothing reads it; DPC
snapshots nothing; **ACOM alone is correctly wired** (`ACOMWorkflow.swift:145-150`).
A gate on the badge cannot work until the products carry the fact.
**Four assumptions to not repeat**, each checked: `local_lattice`,
`matched_template` and `disk_detection` are overlay/replay kinds, never product
kinds; the app publishes `virtual_circle`/`virtual_annulus` with units
`"intensity"`, never `virtual_detector`; ACOM must be IN the gated set, not out;
and a restored sidecar already carries `quantitative_status`, which wins.
**Ships in v3.0.0 as a stated known limitation** (owner, 2026-09-11), because a
fix that looks like one and is not is worse than the open defect. Gate D and
Gate B both owed on the real fix.

### A radius-only aperture drag destroys the fitted origin (2026-09-11)
Latent, found by the Gate D refuter, and **not** what happened on the owner's
drive. `ApertureOverlay.emit` rounds the centre to whole pixels and hands the
WHOLE `Aperture` to `updateAperture`, which tests
`newAperture.centerX != aperture.centerX` (`AppState.swift:3112`). After any
origin fit or restore the live centre is fractional — (69.3133, 54.5009) on
`downsample_Si_SiGe_exp`. So dragging an inner/outer RADIUS handle, never
touching the centre, rounds it by up to 0.5 px, trips the centre-change branch
and destroys `calibration.origin` and `recordedOriginX/Y`. Distinguished from
the owner's incident by magnitude: rounding moves <= 0.5 px, his centre moved
10.884 px. The pinning test the refuter proposes is a hypothesis and must be
broken before it is trusted: restore a calibration holding the sidecar's origin
maps, set the aperture to `meanOrigin`, drive `emit` with an outer-radius-only
change, assert `calibration.origin` survives. Owner: cheap, Gate D (a number
can move).

### "Computed this session" reports what EXISTS, not what was computed (2026-09-11)
This is what the owner actually reported. The two rows are bare predicates —
`product("Origin calibration", done: ...calibration.hasFittedOrigin)` and
`done: ...hasRotation` (`WorkspaceInspector.swift:563-565`) — so a session
restored from a sidecar shows both green having computed nothing. The owner's
session WAS restored (the sidecar reproduces his 9.72 px and 3.74 px exactly),
so his green ticks were restored, not computed, and the tick went grey because
the origin was cleared, not because a computation was undone. The label is the
defect. Owner: presentation only, neither Gate D trigger applies.

### Moving the detector destroys the origin fit with no durable warning (2026-09-11)
Gate D closed: `updateAperture`'s centre-change branch is doing exactly what it
was designed to do (Gate B note, 2026-08-28), and the design is the problem. The
aperture centre silently IS the calibration, and after a fit the aperture sits
on the fitted mean — 10.9 px from the pattern's visual middle on this dataset —
which is precisely what invites a user in an imaging workspace to "correct" it.
The only notice is a transient `statusText`; the undo (`canRestoreFittedOrigin`)
is real but sits inside `DisclosureGroup("Fit diagnostics & advanced
correction")` with `@SceneStorage showsDiagnostics = false`
(`PrepareSettings.swift:30,120-128`) — collapsed by default and the last row of
a different workspace's sidebar, as the 2026-09-01 drive already recorded. The
app gives no indication that moving the detector destroys the origin fit until
after it has. Owner: decide whether a confirmation, a non-transient banner, or
refusing to clear without consent.


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
(`drift/refuter/peak-position-diff.txt`). Likely two near-threshold
noise peaks trading places (the noise item below), not a defect; the defect is
that the gate cannot tell. Owner: a checksum needs a tolerance — a design pass.

### The one-peak warning is below the fold, and Strain unlocks without it (2026-09-09)
Driven on `polycrystal_2D_WS2.h5` (`archive/v3/drive-2026-09-09.md`, finding 16;
shot `B33-ws2-detect-done.png`). `Detect All Disks` completed to a green status
strip `Disks ✓ 16384 peaks (Parabolic subpixel)` — exactly one peak per
position, the direct beam only, which is the documented WS₂ behaviour at the
shipped 0.5 % (`DiskDetection.swift:290-296` names this cube) and is what
`expected.json` pins. **The app is not silent**: the acceptance funnel reads
`45 candidates → 1 accepted · absolute 45 · relative 1 · spacing 1`, an amber
smoothing warning is shown, and `summary.warnings` — which includes the
median ≤ 1 text naming Min relative intensity — renders at
`MapSettings.swift:211`. The defect was placement and gating, not absence:
that block sat immediately after the `Per pattern median…` row, which at the
default window height put it **below the visible fold** while the green headline
sat in the bottom bar. **Placement fixed 2026-09-09** — the warnings now render
BEFORE the two count rows (`MapSettings.swift`); unverified on screen. Still
open, and the harder half: `Strain` moved from `!` to enabled on a
median-1 result, because readiness gates on Bragg vectors EXISTING, not on being
usable. The driving agent first reported this as "nothing distinguishes it from
a healthy run"; that overstated it and the review corrected it — recorded so the
next reader does not re-derive the wrong version. Owner: presentation plus a
readiness question; no Gate D (mechanism established by reading the two call
sites, no number moves).

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
Agent drive, C3 (`drive/shots-c3/b2-qr-unset-bug.png`): on the COPL
cube (Q pixel scale green "From file 0.156828"), typing `0.2` into Prepare's
Manual field entered nothing (this locale wants `0,2`; the period was dropped
silently), and Return on the now-empty field flipped the row to "Not set /
Reciprocal dimensions remain in pixels" and the scale bar from `0.5 Å⁻¹` to
`5 px`. `0,25` typed afterwards worked live. Two things to establish before a
fix (Gate D): why a period is rejected rather than parsed, and whether an empty
manual entry should clear the file value or restore it. Owner: `/diagnose`.

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
