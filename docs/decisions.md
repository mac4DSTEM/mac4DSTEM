# Decisions

Amend by appending. One paragraph per decision: what, why, when; a later
entry supersedes an earlier one by saying so. (The header said "append-only"
until 2026-09-07 while three entries had been rewritten in place — the C1
entry at the end names them.) The evidence behind each lives in
`docs/archive/`; this file is the index a reader checks before re-opening a
settled question.

**2026-08-17 — The `AppState` seam rule.** Any stage touching `AppState`
extracts one seam first, at a green test boundary, the extracted type itself
`@Observable`. Splitting into `extension AppState { }` does not count.
Reason: the facade was growing faster than it was being decomposed.

**2026-08-18 — The v2 contract and the three gates.** All-in scope with the
promote run and reduced export; `.automatic` residency dropped, not tuned;
Gate A (review), Gate B (independent refuter for science), Gate D (written
diagnosis and experiment before a fix). Reason: three confident wrong
diagnoses had each passed every test written for them.

**2026-08-31 — W4a merged.** S14 and S15 merged by owner decision.

**2026-09-01 — v2 endgame scope.** All five remaining Group A review
findings ship fixed; the "hand a colleague" and "promote overnight" claims
are discarded; token conservation is a standing directive (lower-tier models
when safe, terse docs, heavy gates only for science). S22 (UX overhaul)
moved ahead of the fix queue on the owner's "not a good v2" verdict.

**2026-09-02 — Naming.** What exists ships as v2.0. The architecture
consolidation is codenamed v2.5 and releases as v2.x increments. v3 is
reserved for the owner's feature plan and bumps when its first feature lands
on the new legs. Process and architecture docs are version-free.

**2026-09-02 — Tag before ship.** v2.0.0 was tagged on the Gate D closeout
commit so the consolidation could start on `main` without waiting for the
DMG. Release fixes, if any, go on a `release/2.0` branch from the tag.
Major version on the §5 evidence: a v1.0.0 build silently misreads
reduced-view sidecars.

**2026-09-02 — Consolidation order and scale.** Package split first (Core
already imports no UI; one line to move), then `ScientificProduct`, then
owners, then the registry, then the Phase split. Scope is the 12–16 week
foundation, not the full 6–9 month proposal; the HDF5 writer is wrapped,
not decomposed. Full record: `docs/archive/v2/v2.5-plan.md` §4 (path corrected 2026-09-07, C1).

**2026-09-02 — Gate ceremony.** Gate D unchanged. Gate B only for changes
that alter a number in Core. Gate A fleets retired in favour of one
reviewer. Track B is a ten-row drive per user-visible slice and the full
checklist once per tag. Session records are commit messages plus one
paragraph here.

**2026-09-02 — The inventory is the review.** `tools/run-tests.sh inventory`
runs at every closeout and in CI. Three independent reviews converged on the
same findings; what drifted was the state, so the state is now checked by
script. No further whole-codebase review passes are commissioned.

**2026-09-02 — Step 2 lands as a build guard first.** `Package.swift`
compiles `Core/` as `DSTEMCore` from the shell while the app target keeps
compiling the same sources directly. Reason: the compiler found an upward
dependency (`Aperture`) that grep had missed, and the guard is worth having
before the `public` API pass that a real target dependency needs. The split
into a dependency (2b) and `DSTEMSession` follow.

**2026-09-03 — `package` access, not `public`, at the Core boundary.** The
app depends on `DSTEMCore` through Swift's `package` access level and the
`SWIFT_PACKAGE_NAME` setting rather than a designed public API. Reason:
Core is one module consumed by one app in one repository; a public surface
would be API design work with no second consumer, while `package` makes
the boundary real for the compiler at the cost of a mechanical pass
(1 645 modifiers, 96 generated initializers). If Core is ever published as
a library, that is the moment to design `public`.

**2026-09-03 — The py4DSTEM lock is fetched, not vendored.** The 196 tracked
source files under `References/` are replaced by `tools/lib/fetch-py4dstem.sh`,
which clones upstream at commit `f050d207` (dev, 2026-03-26, version 0.14.19)
— the commit whose tree matched the tracked copy byte for byte — into the
gitignored folder on demand; CI and the scientific runner call it. Reason: the
public repository should not carry a copy of another project; the file:line
citations in `DEVIATION` notes stay true because the pin is exact. History is
not rewritten (3.6 MB is not worth a force-push).

**2026-09-03 — Step 7c decisions (plan §11g), owner.** (1) The Phase tasks
are DPC & iDPC / Parallax / Single-slice ptychography as coded; the ADV
marker stays on both ptychography tasks. (2) Results gets its own inspector:
the selected product's units, frame, sampling, quality fields, provenance
and origin, the session inventory, and the Diagnostics group (the
session-vs-view and invalidated-calibration warnings matter most there).
(3) `ActivePane` is not widened — it also drives Prepare's ROI direction;
a separate `FocusedPane` value, set by the pane with the focus ring and read
only by the inspector, replaces the per-workspace conditions. (4) The run
functions (`runACOM`, `runStrainMapping`, `applyACOMDisplay`, the orientation
plan/map) move into their session objects within 7c, as each family's last
slice: sidebars first so views stop reading `AppState`, then the family's
run functions move with the state they need and its forwarder block is
deleted in the same commit.

**2026-09-03 — A system-only presentation (owner).** Tools stay on the
left, information (dataset, product, preview, sidecar, diagnostics) on the
right; every settings group is a system `Form`; no custom backgrounds,
tints, bars or fixed frames outside the scientific panes; the app takes the
system's appearance (Liquid Glass on macOS 26) from its containers. The
contract is `architecture.md` "Presentation contract"; the adopting pass is
one session with the owner's screenshots as input, one workspace per commit,
driven by the owner before anything is released.

**2026-09-03 — The columns are AppKit's (owner).** After the drag crash's
mechanism was measured (below, and `open-items.md`), the owner chose to own
the columns with `NSSplitViewController` — sidebar, workspace, inspector
items — the way Xcode, Finder and Mail do, instead of policing SwiftUI's
`NavigationSplitView` from outside. Hosted SwiftUI content sizes nothing
(`sizingOptions = []`); the divider is the only authority over width. The
bridge to SwiftUI is small and stays: the two visibility flags in and out,
and a remembered open width per side so a toggled column reopens where it
was. Not reinvented: collapse on drag, bounds, holding order, autosave are
AppKit's own.

**2026-09-03 — One split-view contract, like Xcode (owner).** Both side
columns behave the same: drag far, collapse past the minimum, reopen at the
last width; the data pane keeps a floor; a narrowing window squeezes the
inspector, then the sidebar, then the pane. `SplitViewPolicy` is the only
enforcement — AppKit split-item bounds and holding priorities — and the
SwiftUI frame floors on the columns are gone. The sidebar's maximum goes
from 340pt (the 2026-09-01 cap after a 750pt drag) to 600pt, the inspector's
from 560 to 600: wide is allowed, content wraps. Measured before writing:
SwiftUI already collapses on drag and reports it to the navigation flags;
it does not apply the sidebar's declared minimum as an item bound.

**2026-09-03 — Four lanes and a number rule (owner).** `open-items.md`'s
sections are the lanes: patches (v2.5.x) for reported bugs and the known,
scoped items; science one item at a time with the origin-fit guard leading;
verification debt closed by its run; hygiene riding with whichever session
touches the file. A patch changes no scientific output; a landed change to
one cuts v2.6.0 and the changelog names the number. Releases are cut when
what has landed is worth a build, never scheduled against a number.

**2026-09-03 — Steps 2c–4 decisions (unattended session; the owner drives
them).** (1) A slider is a labelled `Slider` row, never a `LabeledContent`
value: as a trailing value it collapses to its knob at the column
minimum; both width-range tests now refuse a slider under 80 pt. (2) A
badge on a pane is a word in its colour, not a capsule; the owner's capture
showed "Relative" wrapped to three lines inside one. (3) Sheets have bands
(`WindowPolicy`), not fixed sizes, so a short display shrinks the sheet
rather than losing its footer. (4) Agents in isolated worktrees cannot
build this repo (the local package name derives from the directory); their
patches were applied to the main tree and gated there, which is the
procedure from now on.

**2026-09-03 — Step 2a decisions (unattended session; the owner drives
them).** (1) The sidebar is one grouped `Form` on the column's material,
rows filling the group as System Settings' do — rule 1's "spare width is
margin" is applied to controls (a numeric field is `FormPolicy`'s width,
never the row), not to rows. (2) Two numbers live in `FormPolicy` and
nowhere else: the numeric field width and the thumbnail height cap; the
inventory grep enforces it once step 4 lands. (3) The 2026-08-06 "sidebar
fits its column without scrolling" gate is retired: a Form with system
row metrics is taller than the old list and scrolls; #16 stays pinned by
its own tests and rule 5 is the new width-range gate. (4) The columns
stay flat: on macOS 26 the sidebar/inspector material is within-window
and only content beneath a column shows through it; letting the workspace
under the columns clipped the diffraction pane (Gate D, `open-items.md`).
(5) Hosted column content gets compression resistance 1 so no control can
widen a column past a drag — measured: a four-segment picker held 283 pt.

**2026-09-03 — The presentation pass is a complete UI rework; releases
are parked.** After driving step 1 the owner widened the scope: every
surface of the app is reworked to Apple's standards under the presentation
contract, and no release or tag is considered until it is complete and
right. v2.5.0 keeps its number but has no date and no gate on it.

**2026-09-03 — Presentation contract rule 3 is held by a grep, not a
hosted test.** A test counting `NSVisualEffectView`s outside the AppKit
columns was written and broken first: it counted 2 with the header's and
footer's `.background(.bar)` in place and 2 without — zero-sized AppKit
scroll-view backgrounds; SwiftUI's bar material never reaches the NSView
tree. A gate that cannot see its subject was deleted; `run-tests.sh
inventory` greps the UI files (scientific panes exempt) instead.

**2026-09-03 — v2.5.0 is the next release; Track B is retired.** v2.0.0
was tagged and never built; the consolidation supersedes it, so the next
release is v2.5.0 from `main` after the owner's own driving pass. The tag
stays as the pre-consolidation anchor. Track B (the human checklist) is
retired: the owner drives the app and reports bugs, each entering through
`/diagnose`; a drawing change is stated as unverified on screen until the
owner has seen it, and the checklist's trap notes live in the archive. The
owed science items (`open-items.md`) carry no release number — each is a
Gate D or Gate B session of unknown size, and the changelog names the
number it changes when one lands.

**2026-09-04 — the `UI2` type prefix is dropped.** The folder rename left
`UI/ContentView` named `UI2ContentView`, the confusing half-state the rename
existed to remove. A blanket strip would have been wrong in five places and a
compile error in one: `ProductComparison` is already a `package enum` in
`Core/Data/DisplayedProduct.swift`. So it went through an explicit map —
`LayoutPolicy`, `WorkspaceRoute`, `WorkspaceView`, `ProductComparisonView`,
`PatternFitOverlay` — with everything else taking the name the retirement had
just freed (`ContentView`, `MetalImageView`, `HistogramView`, `ScaleBar`,
`ComparisonPanel`, `WelcomeWorkspace`, `ResultsWorkspace`, `NumericField` …),
and files renamed to match. The trap for anyone repeating it: the same pass
rewrote prose `UI2` → `UI` in the live docs, which silently corrupted the three
passages that were ABOUT the prefix ("renamed `UI/` onto `UI/`"). Rewritten by
hand afterwards; a prose substitution and an identifier substitution are not
the same job.

**2026-09-04 — `UI/` retired; the SwiftUI rebuild IS the UI.** The
AppKit-hosted window and its 32 files are deleted, `UI2/` is renamed to `UI/`,
and no flag selects a UI any more. Keeping both compiling was the thing that
cost: it doubled the build, and it kept alive four duplications that could
drift apart silently — the 1-2-5 scale-bar quantiser (the on-screen bar and
the PNG export were quantised by separate copies), two calibration helpers
whose only tests defended the retired copy, and a diagnostic plot. Git history
is the archive; a second UI folder is not. What moved rather than died:
`PeakOverlayGeometry`, `RealSpacePointerPolicy` and `ComparisonHoverMapping`
into `UI/`, and `Colormaps` into `App/` — it is display vocabulary that
`AppState` and the exporter both consume, and it imports AppKit for its
`NSImage` swatches, which the UI contract's grep now forbids in `UI/`. What
died: 27 tests, all of them pinning the AppKit column shell
(`SidebarLayoutTests`, `ColumnMaterialTests`, `SplitViewHeightTests`,
`SplitViewPolicyTests`, `SidebarDensityMeasurementTests`) — a gate for a
deleted shell is not coverage. Six tests were repointed instead, because the
rule each pins still exists. Type names keep their `UI2` prefix: it is a name,
not a namespace, and `UI2Metrics` → `Metrics` / `UI2Route` → `Route` are too
generic to grep.

**2026-09-04 (owner's first drive of UI2) — the toolbar's trailing edge owns
the run action, and the sidebar's foot owns session trust.** Two calls, both
from driving it. (a) The primary action moves from `.principal` to
`.primaryAction`: centred, the busy state had no room and truncated "Cancel"
to "C…", and its progress bar was a second copy of the status bar's. Trailing,
and busy means one plain Cancel — the bottom bar keeps progress. (b) The empty
lower sidebar takes a Dataset and a Session section, and the three
session-vs-data disagreements (sidecar unreadable / describes a region this
file lacks / computed on a different view) are promoted out of the Info tab
into permanent view, because "an old sidecar loaded with a cube" is exactly
the case nobody thinks to go looking for. Detail stays in Info; the wording is
shared so the two cannot drift. Also from that drive: shape and direction
pickers are segmented pictograms (the 283 pt reason for menus died with the
shared column), the pane the Imaging Direction drives carries an accent
outline, Results' real-space pane drops the scan marker (it has no diffraction
pane to drive), keeping a result is offered where the result is made, and the
toolbar's bare folder icon became the dataset menu the migration had dropped.

**2026-09-04 — UI2's shape: navigation left, science centre, controls right.**
The question `status.md` had been carrying as owed ("decide where the
workspace's controls live") is answered for UI2: the left column is
navigation and nothing else, and every control the selected workspace owns
moves to the inspector's **Settings** tab, beside an **Info** tab holding the
dataset and product descriptors. That is Xcode's, Pages' and Keynote's shape;
it retires both failure modes of the shared column at once (the 250 pt wall
and the 600 pt sprawl), and it ports to iOS, where an inspector becomes a
sheet. Consequences taken deliberately: the workspace "hero header" is gone —
the window title carries the task and the toolbar carries the one action that
runs it; readiness has exactly one home, the Settings tab's first section, so
`TaskPrerequisiteChecklist` is not carried over; and the pane focus model
(`FocusedPane`, `inspectorContent`) is retired, with `AppState.activePane`
surviving only as the ROI direction's storage behind an explicit Direction
picker. The full contract is `architecture.md` "The UI contract".

**2026-09-04 — UI2 may not use `HSplitView`, and the presentation contract's
rules 2 and 5 are amended.** `HSplitView` nested in a `NavigationSplitView`
detail aborts the app (Gate D, `open-items.md`); `UI2PaneSplit` replaces it,
and `inventory` now greps for the ban. **Corrected the same day by the Gate D
refuter:** the mechanism first recorded here — "it hosts each child in its own
`NSHostingView` and re-enters layout on every change of a content-derived
minimum" — is REFUTED by `UI/ContentView.swift:539`, which does exactly that
and does not crash. The decision (no `HSplitView` in UI2) stands on the
probe table; the explanation does not, and `open-items.md` carries what is
actually established. Separately, the two
presentation-contract rules the 4b pass found wrong are now amended in
`architecture.md` rather than only reported: navigation is a source list and
only controls are a `Form` (rule 2 as written produced no `List` anywhere in
the app), and overflow — not wrapping — is the finding for a fixed-width
column (rule 5 was backwards, and its gate cannot see text at all).

**2026-09-04 — A status-bar number that ticks gets a reserved slot, not its
own size.** Elapsed / throughput / ETA sit in a constant
`LayoutPolicy.operationMetricsWidth` frame and truncate inside it, held for
the whole operation. Reason: the obvious "improvement" — let it be as wide as
it needs — IS the bug that crashed the app (constraint-loop rule,
`open-items.md`). The constant is measured, not chosen
(`StatusBarMetricsTests`). Corollary: `docs/status.md` no longer records push
state; it went stale twice in two commits, and git is the authority.

**2026-09-04 — The macOS floor comes down to 14, and the claim stays at 26.**
`MACOSX_DEPLOYMENT_TARGET` 26.0 → 14.0 in all four configurations and
`Package.swift` to `.macOS(.v14)`. Exactly two symbols stood above the floor,
both cosmetic and both now behind `#available`: `ToolbarSpacer(.flexible)`
(`ContentView`) and `.pointerStyle(.columnResize)` (`WorkspaceView`). macOS 13
is NOT reachable — `@Observable` is macOS 14 and the whole state layer rests on
it. Determined by building at 15.0, 14.0 and 13.0 and reading the errors, not
by inspection. **Amended the same day, owner: the published requirement moves to 14+ too,
in v2.5.1.** The first call held the claim at 26 because 14–25 is
compile-verified only. The owner's counterargument decided it: at 26 those
users get nothing, so untested-but-probably-working strictly beats no access,
and "requires macOS 14 or later" is a true statement about the artefact's
floor — not a claim that every version was exercised. That is precisely how it
differs from the site's earlier "macOS 14+", which was false about the file:
the floor was an enforced 26 and the download could not launch. v2.5.0's
artefact still cannot; only the v2.5.1 build reaches older systems, which is
why this needed a new release and not just a doc edit. 14–25 stays untested
until a VM exists (~40 GB, which this machine has not got). Related: `package-test`'s floor
assertion changed from the literal `26.0` to a value derived from the project,
because a literal had already gone stale once (S19, aeaeacc) and sat red on
`main` unnoticed. That does mean the audit no longer flags a floor change on
its own — which is why the floor is a decision recorded here.

**2026-09-04 — Gate D's trigger is sharpened; the refuter stays.** The rule
read "anything that changes a scientific number" and was in practice reached
for on changes that touch no number. It now names two triggers — a change that
can move a scientific number, OR a defect whose cause is not yet established —
and states plainly what does not need it: placement and presentation, renames,
docs, tooling, and defects with a proven reproducing mechanism. The independent
refuter is NOT relaxed. It earns its place: on the day this was written it
caught that the session's own sidecar fix was aimed a level too low, and found
a worse defect underneath it that the author had not looked for. Owner-approved
2026-09-04. `AGENTS.md` is generated from `CLAUDE.md`; regenerate after editing.

**2026-09-04 — A file's own labels decide what is a datacube; no size
floor.** Discovery refuses a rank-3 or rank-4 node only on a signal a known
writer stamps: emdfile / py4DSTEM's `_labels_` on the dim of a stack axis, and
this app's `RGBA` dim / `rgba8` units on a saved map. A stored rank-4 cube
anywhere beats a promoted rank-3 array anywhere within the link search;
paths only break ties, and a canonical path is honoured first as the file's
own declaration, unless a file-root sidecar marker says the canonical node is
part of the saved-result file. Legacy v0.12 string labels are scoped to the
pinned `data/diffractionslices` subtree. The detector-plausibility floor the
open item asked for is
DECLINED, not impossible — Gate B refuted the first reason given (the
calibration fixture is stored rank 4, untouched by a floor scoped to stored
rank 3): the reason is the rank-3 contract, under which an unlabelled rank-3
array with nothing better opens as one scan row (`load-spec-test`), and a
floor on its last axis would be a magic number tied to one channel count.
The v2.5.1 sidecar-subtree skip STAYS beside the label rule as a
writer-independent location guarantee (Gate B, same day), and
`DatasetDescriptor.storedRank` is the one new field — the descriptor knows it
was promoted, `is4D` stays what every consumer expects, and
`pixelCalibration` uses it to read a promoted rank-3's dims as (N, Qy, Qx).
Amended 2026-09-05 after independent review: the file-root sidecar marker is
checked before canonical probes, and the legacy string-label rule is confined
to the pinned `data/diffractionslices` subtree.

**2026-09-05 — Nothing measurable is a refusal, not a default.** `probeSize`
returns nil when a pattern has no finite intensity above zero, and origin
calibration throws `probeNotMeasurable` with a sentence, where it used to
carry on against an invented 1 px probe at the geometric centre with a
"measured" provenance. The same rule the DM4 reader took the same day for a
calibration it cannot trust: an absent number the user can supply beats a
plausible one nobody measured. Corollary for NaN: a dead pixel is skipped,
not a reason to refuse — py4DSTEM's `np.max` would void the whole
measurement (inline DEVIATION). Compute-time facts are snapshotted on the
product (`ACOMRunSemantics.originProvenance` joins `StrainProduct`); an
export never reads live calibration to describe a map.

**2026-09-05 — DM4 calibration domains decide which axis pair is scan.** DM
dimension tags are fastest-first, but Gatan writes both detector-fastest and
scan-fastest cubes (LiberTEM's "F/C-hybrid `(sig, nav)`" layout), and axis
sizes cannot tell them apart. A real-space unit pair (`nm`, `µm`, Å) and a
reciprocal pair (`1/nm`, `1/Å`, `mrad`) are explicit evidence, so the reader
uses those domains. Missing or unknown units keep the legacy detector-fastest
interpretation. Amended the same day after independent review: units that
contradict each other (a mixed pair, or both pairs in one domain — py4DSTEM's
documented "invalid calibration" case) no longer REFUSE the file; the cube
opens detector-fastest with no pixel sizes and the reason in the log, because
a wrong calibration is the user's to override and a closed file is not. This
deviates from py4DSTEM's generic DM importer, which wraps ncempy's reversed
axes blindly and loads `Si-SiGe.dm4` swapped. Which detector axis is x inside
the scan-fastest pair is NOT decided here — `open-items.md`, Gate D owed.
`loadPushdown` reads the parsed layout through a lock cell: `.scanOnly` for
detector-fastest files as before, `.none` for scan-fastest, where every
pattern spans the whole blob.

**2026-09-03 — The run functions stay on `AppState` (7c 4b).** `runACOM`,
`applyACOMDisplay` and `runStrainMapping` each reach ~20 `AppState` members
outside their own state; a session that ran them would need that surface
injected as a host protocol, which moves the coupling rather than removing
it. So `ACOMSession` owns the state, the plan and map, and their
invalidation, and hands the effects that need the window to `AppState`
through hooks (`StrainProduct`'s seam); the runs stay where the operation
center, replay recording and product publishing are. Revisit as one run
layer for every family, not per family — unscheduled.

**2026-09-02 — Results is three columns (7c slice 1).** The saved-product
chooser moved from a third column inside the Results detail pane to
`ResultsSidebar`; the pane shows the product and the A/B comparison, and
`ProductInspector` describes it — an inspector beside the old column would
have put three panels on the right. Beside strain, orientation and Phase
products both panes carry the product's descriptor (7b's rule, F1.59).

**2026-09-02 — Live doc set.** `CLAUDE.md` (rules), `docs/status.md`,
`docs/v2.5-plan.md`, `docs/open-items.md`, `docs/development-process.md`,
`docs/architecture.md`, this file, plus the reference docs and Track B
checklist. Everything else moved to `docs/archive/v2/` unchanged. The
former `v2.5-contract.md` from the plan's §6 was dropped: the plan is the
contract. *(Amended 2026-09-04: `v2.5-plan.md` is itself archived and
`docs/v3-plan.md` took its place in the set; the Track B checklist went with
Track B's retirement. `CLAUDE.md`'s reading order is the current list.)*

**2026-09-06 — Learned disk detector is Neural-Engine-native, trained by
us.** The ANE is reached only through Core ML, which has no FFT; FCU-Net's
Fourier layer can never run there, and MLX runs on the GPU. So: a plain-conv
U-Net on three channels (pattern, probe, and the Metal correlation — the
third decided in the same day so the net learns ring artifacts directly),
own simulator, own weights (no weight licence), PyTorch to train (Apple's
documented path, PyTorch → `coremltools` → Core ML; MLX is out of this
loop because `coremltools` cannot read it and a hand-written export is a
moving part for no gain at this size), Core ML to serve; the net proposes,
classical refinement measures. The confirmed/rejected patterns the owner
clicks are owned by the session sidecar. Weighed and not
taken: MLX Swift in the app (GPU only), FCU-Net via Core ML (impossible on
the ANE), FCU-Net-first-then-ANE. Accepted cost: no py4DSTEM parity —
simulated truth and a net-vs-classical disagreement map on real cubes are
the ground, and the owner's clicks on that map build the fine-tuning set.
Working method: one feature branch with the per-commit rules loosened and
the full discipline re-applied at the merge; throughput ceiling 2× the
classical detector on the same cube (both owner, 2026-09-06 evening).
`v3-plan.md` §3a is the complete record, long by the owner's instruction.
*(Amended the same evening: Apple's Core AI — 27.0 OS generation, beta on
2026-09-06 — is a second door to the Neural Engine and exports from PyTorch
only, so the PyTorch decision stands with a second reason. The shipping
runtime, Core ML or Core AI, is an owner decision deferred to step 3 unless
taken earlier; §3a's Core AI block.)*
*(Late evening: the owner chose Core AI exclusively — the learned detector
is a macOS 27-only option, the classical detector serves everyone else, the
Core ML export stays in tooling as insurance. The design leaves the CPU
out of the per-pattern loop: batch as a model dimension, in-graph
peak-picking returning candidates not heatmaps, the probe as model state,
compute streams; the correlation kernel moves in-graph only after it is
verified against the Metal engine. The third-party "3.5× faster than
Core ML" claim is about LLM token loops and is not a reason here.)*

**2026-09-07 — The learned detector ships on Core ML; Core AI stays as the
insurance in the tooling.** Inverts the 2026-09-06 late-evening decision
above. Reason, from the branch's own step-2 table (`v3-plan.md` §3a
evidence): Core ML `CPU_AND_NE` 0.305–0.338 ms per pattern against Core AI's
0.344–0.363 ms on the Neural Engine — no measured speed reason to prefer
Core AI; Core ML runs on the macOS 14 floor decided 2026-09-04, where Core
AI is macOS 27 and beta; the branch recorded a segfaulting stateful asset
and a GPU delegate returning half the peaks, both Core AI. The `.mlpackage`
export the tooling already produces becomes the shipped asset; the Core AI
class on `ml/disk-detector` is replaced, not kept beside it. Provenance
records `runtime: coreml` and the package's SHA-256. Owner, 2026-09-07, on
the consolidation review (`docs/consolidation-plan.md` §3).

**2026-09-07 — Consolidate before any new feature; the owner pushes.**
`docs/consolidation-plan.md` §6 (gates C0–C8, each with an exit criterion)
is executed in order by `/pickup` before any new model, feature or UI room;
the first v3 feature waits for C4 and C6 to exit. Agents commit when asked
and never push — the owner pushes every branch (`CLAUDE.md`, the pickup
skill). Owner, 2026-09-07.

**2026-09-07 — C0 of the consolidation plan is closed (owner).** Four
answers, in the order the plan asks them. (1) Disk: `tools/free-space.sh
--clear` was run; the amount freed is not recorded here — each gate's own
preflight (8 GB unit, 4 GB scientific and benchmark) is the measurement, and
a refusal names it. (2) The learned detector's throughput at the cube's
native 250 px, 2.81× the classical path with 3×3 tiling, is ACCEPTED for
now; a 256-px retrain is owed and recorded as the condition to revisit, not
a reason to narrow the net. (3) The AGPL `yolov8n.mlpackage` stays in
`main`'s history; `main` is not rewritten. Its removal from the tree lands
in C2 with a `NOTICE` line. (4) No `v2.0.0` tag will be created for a past
event; the six files that call it tagged (`CLAUDE.md`, `status.md`,
`ROADMAP.md`, `CHANGELOG.md`, `releasing.md`, this file) are corrected in
C1 to say what happened: v2.0.0 was named, never built, superseded by
v2.5.0.

**2026-09-07 — C1 of the consolidation plan: the docs made true, and three
housekeeping facts recorded.** (1) This file's header now says "amend by
appending": three entries were rewritten in place — the macOS-floor entry
(`a9a0437`, whose message says it amended), the DM4 axis-order entry
(`8555803`) and MLX → PyTorch (`c2fa3c1`); they stay as they are, and from
here a correction is a new entry. (2) The py4DSTEM reference is ONE version:
the lock commit `f050d207` (0.14.19) that `tools/lib/fetch-py4dstem.sh`
fetches and every gated harness imports through `PYTHONPATH`. The conda
environment's own `py4DSTEM` package (0.14.17 here) is not the reference;
four scripts import it directly (`open-items.md`, code hygiene) and the
branch's detector parity ran against it, which C6 re-runs against the lock.
(3) `v2.0.0`: a local tag exists on this machine (created 2026-09-02, never
pushed; `origin` carries v1.0.0, v2.5.0 and v2.5.1 only). No tag will be
pushed for it; the six files now say "named, never built, superseded by
v2.5.0". Owner decision C0 (4), executed by C1.

**2026-09-07 — C2 (hygiene): three choices made while pointing every
harness at `sources.manifest`.** (1) A runner that compiles no `Core/`
source (five) carries one comment line saying so, and `inventory` fails a
`tools/*/run.sh` that neither sources the manifest nor mentions it: the rule
is "every runner is accounted for". (2) Nine groups were added rather than
per-harness lists (`detection`, `replay`, `ellipse`, `parallax`,
`ptychography`, `presentation`, `crystal`, `fitoverlays`, and `core` — every
`Core/` source by glob, for the two diagnostics that touch most of it). A
gated harness may now compile a superset; `scientific` ran green before and
after, the check the plan asked for. (3) `acom-groundtruth`'s hand-copied
`BraggPeak`/`BraggVectors` replicas are gone. The AGPL package left the tree
(C0 (3)), `NOTICE` says so, and `*.mlpackage`/`*.mlmodel`/`*.aimodel` are
gitignored.

**2026-09-07 — C5: the `AppState` rule is a number, not a sentence.** "A
session that touches `AppState` moves one responsibility out" was waived four
sessions running because nothing measured it. From here `run-tests.sh
inventory` fails when `App/AppState.swift` + `Support/ResultExport.swift`
hold more lines than at HEAD (or HEAD^ once the tree is clean), so the commit
being made is the one judged and CI judges the one just made. Comments and
blank lines count on purpose: the file's size is the debt, and a rule with a
carve-out is a rule with a loophole. The first extraction under it is the
fit-verification overlays (`Session/FitOverlayPresentation.swift`, −93 lines),
chosen because a value over a snapshot has a boundary a unit test can hold.

**2026-09-07 — C6, the Python side: what "one truth rule" turned out to
mean.** (1) `simulate.VISIBLE_MIN = 0.5` on `disk_visibility` is the rule the
NET is trained for and scored against: target amplitude continuous,
validation, and every evaluation row (fixture and real cubes) take that cut.
(2) The port proof `verify_fixture.py` keeps its intensity rule on purpose —
it judges py4DSTEM at its own `minRelativeIntensity`, not the net; tried under
the visibility rule it recovered 207/230 visible fixture disks = 0.9000,
exactly its limit, which is now reported as `fixture_classical` beside the
net's rows rather than used as a gate that passes by rounding. (3) Float cubes
are scaled into counts by one rule, `simulate.to_counts`: a pattern whose
maximum is ≤ 1 is a fraction of a nominal 2×10⁴-count beam (the value the
2026-09-07 WS₂ evaluation passed by hand); the Swift side mirrors it at C7.
(4) `check_export.py` exits 1 outside a tolerance (0.1 of the heatmap range
against PyTorch float16), below 0.98 in-graph peak recall, or when nothing was
checked. (5) A smoke run of that check overwrote `run3/export/check.json`
under `References/` (owner's data); the real check was rerun the same night to
regenerate it — logged in `status.md`. (6) The hand-labelled set is labelled
with `label_centres.py` (matplotlib, ~60 lines), positions drawn once from a
seeded RNG before any heatmap is looked at, and `evaluate.py --labels` scores
the net at the shipped threshold and the classical detector against the same
truth.

**2026-09-07 night — C3 delegated (owner).** "Do it by yourself with a Sonnet
driver, review the screenshots": the C3 sitting is an agent drive of the
list in `status.md`'s handoff, with the assistant reviewing every screenshot
and classifying what it sees; findings still enter through `/diagnose` with
a reproducing observation, and the rows are marked "agent-verified" rather
than owner-verified. The owner keeps the right to re-drive anything.

**2026-09-07 night — C4 (a): one enable logic, named.** A run button is
enabled by `ProductWorkflow.mayRun(mode, readiness:, isBusy:)` and nothing
else; a sidecar-writing control by `SessionGates.mayWriteSidecar`; every
parameter control is disabled while its panel's run is in flight through one
modifier. Ad-hoc `appState.*` conditions that duplicated a prerequisite were
removed rather than kept "for safety"; a readiness the workflow could not
express would have been added to `ProductWorkflow.prerequisites`, and none
was needed. The parallax stage buttons keep their in-memory sequencing checks
on purpose: whether the previous stage's product exists is pipeline state,
not a prerequisite the workflow models. "Reconstruction Ready" as a disabled
prominent button is gone: readiness is shown by readiness text, not by a
button that cannot be pressed.

**2026-09-07 23:45 — C6's size session, the design as briefed (so a crash
loses nothing).** `simulate.S` stays 128 by default; every entry point takes
`--size`; one function `fit_to(pattern, centre, size)` centre-crops or
zero-pads, never rescales; ingredients probes prepared at the requested size;
labels recorded in NATIVE pattern coordinates with `frame: "native"` and
mapped by evaluate through the same offset, so one labels file scores a
128-px and a 256-px asset; the 128-px fixture stays byte-identical and is
padded for a 256-px asset's fixture rows; `overnight-256.sh <out>` chains
ingredients → train (`--size 256 --width 12 --max-minutes 90`) → export →
check → evaluate, stopping at the first non-zero exit.
