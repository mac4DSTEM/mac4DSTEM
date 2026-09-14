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
`docs/archive/v2/v2.5-plan.md`, `docs/open-items.md`, `docs/development-process.md`,
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
the consolidation review (`docs/archive/consolidation-plan.md` §3).

**2026-09-07 — Consolidate before any new feature; the owner pushes.**
`docs/archive/consolidation-plan.md` §6 (gates C0–C8, each with an exit criterion)
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

**2026-09-08 — C6 verdict (owner, in chat): the learned disk detector earns
its place; the 256-px model; one picker in Disk detection; default
threshold 0.7; the labels are good enough for now.** Judged on the frozen
hand-labelled bullseye set (40 positions, 306 centres, 2 px match,
`archive/v3/learned-detector-2026-09-06.md` "C6 — the table"): at 256 px
the net 0.667 / 0.840 against the classical 0.487 / 0.485; inside the 128-px
square the shipped asset sees, 0.810 / 0.903 against 0.659 / 0.735. The
net does not add disks the classical misses; it finds the same real disks
with far fewer inventions (the classical's unmatched peaks are 128-to-30
outside the central window, on the background of sparse patterns), and its
misses are the faint outer disks. The owner's words: "overall the net earns
its place"; "we keep it simple stupid and macOS-like"; "we take the 256
model"; "why not use a lower number per default, the user can change it
anyways"; "discs are labelled good enough for now, maybe we retrain in the
end but let's first get a clean app". Consequences: (1) C7 ships the
256-px model (whole 250-px pattern in one pass, padding below 256, windows
only above), exported to Core ML per the 2026-09-07 decision, with a
several-shape export tried first and 256 + windows the fallback. (2) The
2026-09-07 "no AI code in the classical configurator" rule is overruled for
disk detection: a "Detector" picker (Classical | Neural net) and, when the
net is chosen, its threshold row live in the Disk detection section of
Strain & ACOM, because the net's output is the candidate list the classical
refinement measures either way; the AI Analysis room keeps precipitates and
groups. (3) Default threshold 0.7 — the knee measured on the labels
(0.9: 0.67 / 0.84; 0.7: 0.77 / 0.71; 0.5: 0.79 / 0.59; 0.3: 0.79 / 0.45;
`c6-compare-256-thr*.log`). (4) No relabelling before C7.

**2026-09-08 — C7 session 1: the Core ML runtime on `main`, and four
choices made in-step.** (1) The asset ships VERBATIM: the `.mlpackage` is a
folder resource in the bundle (`Models/DiskDetector/`, the one `.gitignore`
exception), compiled by `MLModel.compileModel(at:)` at first load. Why: the
hash in provenance is then `export.py`'s `sha256_tree` of the package, the
same number the run's `export.json` and the record JSON carry; an Xcode-time
compile would ship an `.mlmodelc` whose bytes depend on the compiler, so no
reader could reproduce the hash from the Python side. Load is once per
launch, outside any run. (2) The app always sends the package's default
batch of 32, zero-padded, although the package accepts 1…64: on the Neural
Engine a batch-1 heatmap differs from the batched one by up to 0.035
(`check.json`), enough to move a pick across the threshold, and the fixture
is written at that same shape for the same reason. (3) The several-shape
export the owner asked to try first (enumerated 256 and 512 px) converts and
passes the check; it is not shipped — nothing above 250 px has truth, and
one model frame with windows above it keeps the science to what was
measured. (4) The frame rule in Swift is `simulate.fit_to`'s: a detector
below 256 is one frame at `fit_offset` (round-half-to-even, never clamped —
the frame hangs over the detector and the overhang is zero), exactly 256 is
used as is, above 256 is windows. The branch's `DetectorClass`, `Candidate`,
`correlation` and `refine` came to `main` unchanged (Gate B 2026-09-07 on the
branch); the Core AI class is not ported, `#if canImport(CoreAI)` is gone.

**2026-09-08 — C7 session 2: the picker in Disk detection, and five
choices made in-step by an agent (overrule on sight).** (1) A recorded
`disk_detection` step without `detector_class` replays as classical: every
recipe written before this session has no such key, and every one of them
ran the only class that existed — the one absent key that is a fact, not a
default (`ReplayPlanTests`). A step recorded as learned replays only when
this build's model hash equals the recorded `learned_model_sha256` and the
recorded threshold parses; a mismatch refuses naming both prefixes, the
`kernel_source` rule again (a substituted model would move candidates with
no summary line saying so). (2) The live rings on the current CBED follow
the picker — the owner's 2026-09-07 drive on the branch found them still
classical with Learned selected. (3) The picker's labels are the owner's
words, "Classical" and "Neural net"; the provenance IDs are unchanged.
(4) Both classes name themselves: `detector_class` joins the classical
provenance and, with `learned_threshold` and `learned_model_sha256`, the
Bragg vector map's Provenance rows — until now the inspector read nothing
of the detector; only the EMD writer did. (5) The line budget: AppState's
wiring (about 50 lines) was paid by `ACOMSession.resetForDataset` (the
activation block), one probe-radius prologue, and 41 blank `///` / `//`
separator lines removed file-wide — that last payment is cosmetic and is
said so here; the next one should be §4's `OperationCenter` forwarders.

**2026-09-08 — C7 session 3: the disagreement map pairs peaks, the ceiling
on Core ML, and four choices made in-step by an agent (overrule on sight).**
(1) The disagreement map pairs peaks position by position — greedy, closest
pair first, each peak once — within 2 px, C6's evaluation radius
(`evaluate.py`); both detectors end in the same classical refinement, so a
shared disk lands well inside it. The map's value is the UNPAIRED peaks at a
position (classical-only plus learned-only); the summary carries both
directions, the pooled median residual and the counts. The count-only
`countDifferenceMap` of sessions 1–2 is deleted: equal counts at different
places read as agreement there, and the new summary reports counts too.
(2) The map is a product with its own domain (scan, not Disk detection's
detector domain) and its own provenance keys, so `publishProduct` gained a
domain override and per-product keys rather than a second publish path; it
records no recipe step — it is derived from two completed runs and a replay
reproduces it by re-running both. (3) AppState's new lines are paid twice over
by two relocations of stateless code, each pinned by existing or new tests:
the classical replay dictionary into Core as
`DiskDetectionParams.replayParameters(kernel:)` (a record → parse round
trip), and `count`/`scanProgressStatus` onto `SystemMonitor` in `Session/`,
beside the `byteString` they embed (the three progress tests follow them);
the first payment alone left the pair 26 lines up and `inventory` said so.
The `OperationCenter` forwarders named last session have 146 call sites and
are a session of their own. (4) The ceiling is re-measured on
the runtime that ships: `scan-bench` on Core ML, same 525-pattern 250-px
geometry as the 2.81× run, one 256-px frame, no tiling — 1.44–1.64× (two
runs; `tools/disk-detector/README.md`). The 2026-09-07 acceptance "at the
measured edge of the ceiling" is therefore no longer a waiver; the number
quoted for v3.0 is this one. Not decided here: which labels the sidecar
holds (`open-items.md`).

**2026-09-08 — Labels in the sidecar: centres, as one attribute (owner, in
chat).** A sidecar label is a set of hand-clicked disk CENTRES at one scan
position in the detector's native frame — the format the C6 verdict was
measured against (`label_centres.py`), not the branch's confirmed/rejected
verdict per position, which cannot score a detector per disk. They live as
one JSON attribute on the session sidecar's root group, beside the
calibration, so they survive reopen and travel with the file; a proper HDF5
group is not opened now. The click mode lives in the app on the diffraction
pane; the export writes the click tool's JSON so `evaluate.py` and the
fine-tuning step read app labels and tool labels alike. The branch's
`DiskLabelStore` is superseded, not ported. Why now: this is C7's last
completion item; the owner wants C7 closed so the AI room (C8) and v3.0 can
follow.

**2026-09-08 — C7 session 4: the centre labels built, and six choices made
in-step by an agent (overrule on sight).** (1) Labels are written only by
the calibration save: `saveCalibrationToSessionSidecar` carries the store's
JSON, and "Save to Sidecar" in the labels rows calls that same function —
one rewrite path, one gate, no second save routine. A save with nothing to
say about labels (an empty store) preserves what the file holds; the writer
never erases labels. (2) A click within 3 px of an existing centre removes
it, otherwise it adds one — the click tool's add/right-click-remove folded
into one gesture, since a secondary click is awkward inside a zoomable pane.
(3) The click catcher and the crosses exist only in Disks mode and only for
the Current pattern; Mean and Max have no single position to label. (4) The
JSON's `sha256` is the app's own canonical encoding of `positions` (sorted
keys), not byte-identical to Python's `json.dumps`; `evaluate.py` records the
value and recomputes nothing from it. (5) The AppState budget was paid by
four stateless relocations, two beyond the brief: `realSpaceRegionShape` →
`DetectorShape.realSpaceRegion` (Core), `isDataSourceFailure` →
`SessionGates` (the harness lists rule out `TiledDiskDetection.swift`; a
data-source failure classifier on the gates type is a stretch of that type's
role and is said so here), `exportableRecipe` → `ReplayRecordFrameMap`,
`copySidecarFile` → `SessionSidecarLocator`. (6) Of 18 new tests, 4 were
broken by mutation; the rest were not individually broken — recorded, and
handed to the Gate B campaign rather than claimed.

**2026-09-08 — C7's Gate B campaign (sessions 1–4): one claim refuted, five
surviving mutations closed, one design gap opened.** Refuted: "`evaluate.py`
reads app labels and tool labels alike" — the app wrote `ingredient: "app"`,
and `evaluate.py` keys the probe on that name in the ingredients npz
(`KeyError: 'app_probe'`); now the store carries `ingredient`/`seed` through
a round trip and `evaluate.py --ingredient` names the npz key for an app
export. Closed with an assertion each, every one broken by the refuter's
own mutation before being trusted: the disagreement matcher's tests all sat
on the diagonal x == y (an axis swap in one input was invisible — one
off-diagonal pair pins it); `fitOffset`'s half-to-even rounding was vacuous
on the fixture's centre (63.6, 64.3); `removeNearest`'s test had the nearer
centre added last; the export's destination was untested; a border click
stored a centre off the detector (refused now). Changed on the findings: a
refused learned replay no longer switches the picker or applies the
recorded threshold; the asset hash and `export.py`'s `sha256_tree` now
share one rule (no path component starting with "."); `scan-bench` records
the crop origin under the keys the detector writes. Corrected in the docs:
the ceiling is ≈ 1.5×, the 1.44–1.64× band being run-to-run noise, with the
250² vs 256² FFT caveat stated. Opened (`open-items.md`): the probe channel's
anchor for detectors above 256 px. Held: the Python parity of `modelInputs`,
`toCounts`, peak picking and the shift back (17 mutations, `fixture` gate
exit 0), the replay rules, the preserve-on-nil sidecar write, the Neural
Engine per-shape trap re-measured at 0.036. Process: `-only-testing` with a
FILE name that is not a class runs nothing and exits 0.

**2026-09-08 — C8: the four pure engines stay on the branch (owner, in chat:
"leave").** `Core/Analysis/Precipitates/*` and `DiffractionEmbedding.swift` on
`ml/disk-detector` are not ported unwired; they re-enter with their product
and UI layers through the §1.5 design session, whose four questions may
change their contracts. Why: 1 400 lines of Core and 1 700 of tests that never
met a compiler would sit dead in the tree about to become v3.0.0. C8 is closed
as a triage (`archive/v3/c8-triage-2026-09-08.md`).

**2026-09-08 — C4(c)'s final drive delegated (owner, in chat).** The owner
asks the agent to drive every panel and report screenshots, then exit the
consolidation plan and cut v3.0.0. This supersedes the owner-only driver
restriction for this sitting; observations remain agent-verified and do
not assert the owner's outstanding sidecar-reopen check. C4(c) keeps
physical controls and workflow choices visible, remembers Advanced
algorithm settings per window, moves sidecar actions into Dataset, and
uses native confirmation for Remove and the two Resets. The recovery
command Change Session Sidecar stays usable when the write gate refuses.

**2026-09-09 — 3.0.0 ships a UI that has been looked at (owner, in chat).**
The objection: a published v3.0.0 must be a decent, usable product, not merely
a green one. The gap is not known ugliness — it is that C4 slices 1 and 2 have
never been seen on screen at all and two C4(c) screens are owed, so a third of
the UI coherence work is unverified, and no test can tell you whether an app is
presentable. Decided, in order: the delegated drive covers every workspace,
every Phase stage, the load configurator, comparison, colorbar and dividers and
produces screenshots and a findings list; the owner triages those together with
the six papercuts verified live on 2026-09-09 (Info's orphaned "Reloads the
whole cube" caption, Gamma's value-in-label, the duplicate Run shortcuts, the
missing document proxy icon, tab styling, per-window log height) into
fix-before-3.0.0 and after; one presentation-only session fixes the fix-now
list. NOT reopened: the deeper UI findings list, which `open-items.md` holds
against the C5 extractions and which would pull architecture into the release.
Findings still enter through `/diagnose`.

**2026-09-09 — the even-count median is pinned below the `all` gate, and
`calibrationData_bullseyeProbe.h5` is pinned at all.** Gate D on the
2026-09-08 red gate found `ba6360d`'s `np.median` parity correction, not a
regression: the goldens were stale and no code changed. Two consequences the
refuter argued for and this session adopted. (1) A unit test now pins the
even-count rule on a fixture where the two rules differ by 0.144 px; until
2026-09-09 the ONLY thing standing behind it was one harness reachable solely
from `run-tests.sh all`, which is how a corrected number sat against a stale
golden for three days. `ba6360d`'s own entry in this file records its refusal
decision and says nothing about the median — only `CHANGELOG.md` did. (2) The
bullseye cube is pinned in `expected.json`. It had drifted invisibly because
`compare.py` only compares what is pinned and prints an `UNPINNED:` line
otherwise. The cost is accepted knowingly: bullseye's counts sit on ~130 noise
peaks per position (`open-items.md`), so future noise-handling work will turn
the gate red and need a re-pin with evidence. That is the gate working. One
line to reverse if the owner disagrees.

## 2026-09-11 — the accessibility crash does not block v3.0.0 (owner)

Asked directly whether the `accessibilityLabel()` stack overflow blocks the
cut, the owner: *"i dont care about VoiceOver, it is not part of the
consideration... we care about something like this in v8.0.0 or whenever, if it
has no other practical meaning we don't care about it until the distant
future."* So: **3.0.0 is cut with the crash open**, and it leaves the v3.0.0
blocker list.

Recorded with the caveat the owner's condition asks for, because the condition
is not fully met. The defect is **not** VoiceOver-only: `open-items.md` records
that it fires when any AX client resolves labels on the front window, which
includes Accessibility Inspector and any UI automation. Both crash reports
(2026-09-08 22:41:36 and 22:47:48) are from the owner's own driving session, so
it has already cost him a running app twice, and it is a hard blocker on ever
restoring an automated driving rig — which matters because agent driving was
retired on 2026-09-09 for unrelated reasons and may be revisited. None of that
overrides the decision; it is written down so the next person to propose an
automation rig knows what they will hit.

Consequence for the release: the README and CHANGELOG say nothing that claims
accessibility support, and the crash stays in `open-items.md` as a known defect
rather than being quietly dropped. One line to reverse if the owner disagrees.

## 2026-09-11 — the consolidation plan is archived and v3.0.0 is the next cut

Every §7 criterion was checked rather than assumed, and the checks are in the
archived file's own header. The one that needed measuring: `AppState` +
`ResultExport` went **7 624 → 7 508 lines** (−116) between `84b2498`
(2026-09-06) and today, so C5's "smaller than on 2026-09-06" holds on the
number, not on the intention.

The feature freeze the plan carried ("no new feature until it exits") lapses
with it. `CLAUDE.md` and both copies of the `/pickup` skill are updated so a
feature target is no longer refused.

**The number is v3.0.0, not v2.7.0.** Asked directly on 2026-09-11, the owner
chose to go for it. The reasoning: the learned disk detector is a FEATURE and it
is in the build with a passed verdict, and `releasing.md`'s rule is that a
feature cuts a major version. Cutting the same work as v2.7.0 would be the same
release under a number that hides its largest change. Three things remained
undriven at the decision — Parallax and ptychography on real data, the four
Phase E failure paths, both Resets — and none blocks: they are named in
CHANGELOG's "Known limitations at 3.0.0" instead of being discovered by a user.

## 2026-09-11 — clicking a pane selects it again, reversing two earlier calls

Owner, driving `060_STEM_SI_…bin_4`: clicking the real-space image does nothing,
only the Direction buttons move the accent outline. *"Why did we lose this
feature? We need to keep things simple, stupid macOS."*

**Nothing was lost by accident.** Two recorded decisions removed it. 2026-09-04
retired the pane focus model, leaving `AppState.activePane` "surviving only as
the ROI direction's storage behind an explicit Direction picker". C4(c) then cut
the click path as consolidation finding #5, *"Clicking the image rewrites the
inspector"* — tapping a pane set `activePane`, which swaps the Settings tab
between Detector and Region, and the review called that a pane focus model the
contract says does not exist.

**Reversed, because the review's premise was wrong about the platform.**
Selection driving the inspector IS the Mac idiom — Xcode, Keynote, Sketch and
Figma all do it. What made the old behaviour confusing was not that the
inspector followed the selection; it was that nothing showed WHAT had been
selected. The owner identified that himself in the same week and asked for the
indicator that became `ActivePaneOutline` ("the app needs an indicator which the
active plane is because the settings plane changes and it is confusing when
setting the detector", recorded in that view's doc comment). With the outline in
place the objection no longer holds, and the accent outline already looks
exactly like a selection — so refusing to let a click move it is the surprising
behaviour, not the other way round.

Implementation: a `simultaneousGesture(TapGesture())` on each pane in
`UI/ImagePanes.swift`, so it composes with the detector drag, the scan scrub and
the ROI handles instead of swallowing them, and a `TapGesture` rather than a
zero-distance drag so a drag passing over a pane does not steal the selection.
It writes `activePane` directly, the idiom the ROI handles already use, which
keeps it out of `AppState` and its measured line budget.

Neither Gate D trigger applies: presentation only, and the cause was established
from this file and `archive/consolidation-plan.md` §4(5) rather than guessed.
**Unverified on screen until the owner drives it** — and the thing to watch is
whether the tap composes cleanly with the detector drag and the scan scrub,
which no unit test can establish.


## 2026-09-11 — mac4DSTEM ships arm64 only, and the artefact proves it

**Decision.** The release artefact contains one architecture, `arm64`, and the
release path measures that on the built Mach-Os rather than trusting a build
setting. The alternative — making `Core/ML/LearnedDiskDetector.swift` compile on
x86_64 so the universal build succeeds — is rejected.

**Why.** The app is Apple-Silicon-only by design and `README.md` has always said
so. Two independent things in the tree enforce it: the embedded HDF5 stack is
arm64-only, and the ANE path uses `Float16`, which does not exist on x86_64
macOS. An Intel slice therefore cannot work even when it compiles: `H5Reader`
dlopens libhdf5 at runtime, so such a build launches and then fails every
dataset open. Making `Float16` compile would convert a loud build failure into a
silent shipping defect, which is what v2.5.1 already is.

**What was established first** (Gate D, because the cause was not established).
Project-level `ARCHS` does not reach the SwiftPM package targets where `Core/`
and `Session/` are compiled; nor does project-level `EXCLUDED_ARCHS`, measured
rather than assumed. A command-line `ARCHS=arm64` does. The `archive` action is
not special — a plain `build` with a generic destination reproduces the failure
with no credentials. Full record: `archive/closed-items-2026-09.md`.

**Consequence for v2.5.1.** It shipped universal on 2026-09-04 and is broken on
Intel Macs. It is recorded as a live item rather than quietly superseded, and
whether to withdraw or annotate that download is the owner's call.

**The rule this leaves.** A gate that does not build the way the release builds
is not covering the release. `package-test` was green while the archive could
not compile, because it used the concrete-machine destination; it now uses the
release destination and the release pin.

**2026-09-11 — the AI pipeline is ported onto `main`, reversing "leave"
(owner, in chat).** The 2026-09-08 entry above ("C8: the four pure engines
stay on the branch") is superseded, not silently overridden. Its stated
reason — 1 400 lines of dead Core sitting in a tree about to become
v3.0.0 — lapsed when v3.0.0 shipped. Its condition, that the engines
re-enter *with* their product and UI layers, is kept: the three decisions
below are the design session it demanded. The port is by hand-applied
forward port, never a rebase or merge: `ml/disk-detector` is 27 ahead and
45 behind, merge base 2026-09-06. The branch stays at `origin` as the
record; nothing is deleted. Plan and evidence:
`archive/2026-09-11-ai-port-analysis.md`.

**2026-09-11 — the AI work gets a sixth workspace, "AI Analysis" (owner,
in chat).** `WorkspaceArea` gains a sixth case. Considered and rejected:
mounting the two Sections in Imaging and Map, which is smaller and was the
analysis's recommendation. Why the owner overruled it: the five rooms are
named by outcome (D1, 2026-09-01), and precipitate density and
diffraction-pattern grouping are neither "form virtual images" nor "strain
and orientation" nor "phase" — a Form section inside a room whose own
subtitle describes something else hides the one capability that has no
py4DSTEM equivalent. Discoverability was the deciding argument. The name
states the method rather than the outcome, against D1; the owner chose it
knowing that. Costs, all accepted: eight files, the five-title pin in
`ProductWorkflowTests`'s `testPrimaryNavigationUsesUserOutcomes` updated
deliberately, and `Results` moves off Cmd-5 (shortcuts are hand-written
literals at `mac4DSTEMApp.swift:145-149`). A ninth site both the analysis and
this entry's first draft missed: the `WorkspaceArea` switch at
`AppState.swift:1331`, which is exhaustive with no default.

**2026-09-11 — precipitates ship only if the pre-registered baseline is
built and beaten (owner, in chat).** `docs/ai-ml/precipitates.md` §6
(open it with `git show`; it is not on `main`) demands a baseline — threshold plus connected components with
the ridge filter disabled — that the ridge filter must beat on both the
synthetic fixture and an Al-Si-Mg hand count, "or it does not ship". It
was never written and the hand count was never made. The owner declined
both the waiver and the fixture-only variant. It is a live comparison, not
a formality: the segmentation's own doc comment records the ridge mask
running ~2x the drawn bar, so `area` — which reaches the export through
`arealDensity` — is systematically inflated in a way a plain threshold is
not. This is step 4 of the plan and it may end the precipitate half. The
hand count is owed by the owner; everything around it is not.

**2026-09-11 — `.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])` is
accepted in `Package.swift` (owner, in chat).** `DiffractionEmbedding`
needs `__LAPACK_int`, which only exists behind Apple's new Accelerate
LAPACK interface; verified empirically, `dsyevd_` alone compiles without
the macro but `__LAPACK_int` is a hard error. The cost is that SwiftPM
will refuse to resolve DSTEMCore as a versioned remote dependency for as
long as the flag is there — nothing consumes it that way today, and it is
an `XCLocalSwiftPackageReference "."`. Considered and not taken: Apple's
deprecated legacy interface (keeps publishability, adopts a deprecated
API, needs its own proof the eigenvalues are unchanged), and a C shim
target using `cSettings: [.define(...)]` (keeps both, unverified, would
need a spike). If publishing DSTEMCore ever matters, the shim is the path
back. **Landing the flag silently breaks two harnesses** —
`tools/bragg-spacing-probe/run.sh` and
`tools/training-dataset-campaign/run.sh` compile `Core/**` themselves with
a bare `swiftc` and are classed `diagnostic`, so no gate reports it. Their
two swiftc lines get the flag in the same commit as `Package.swift`.

**2026-09-11 (second round) — how the unattended port behaves where it cannot
be scored (owner, in chat, before an unattended run).** Four answers, given
together with the run's shape in front of him:

1. **The Al-Si-Mg hand count is not made** ("no time"). Step 4 computes the
   baseline comparison and commits **the full metric table, explicitly
   UNSCORED**, under `archive/v3/`. No winner is declared. Precipitates are
   **not wired**: steps 5-7 do not happen this run.
2. **"Beats" means recall and precision, and a tie passes.** Consequence,
   stated to him before he chose: on the synthetic fixture both arms detect
   all six needles (amplitude 200 on sigma≈2 noise is a >70-sigma signal
   against a 3-sigma threshold), so the fixture half is a **tie, and therefore
   a pass**. The fixture cannot discriminate the arms at all — it contains no
   touching needles, no faint needles and no elongated background, which are
   the failure modes the ridge filter exists for. Sharpening it now would be
   re-registering after peeking and is refused. **The real-data half is the
   only half that can decide, and it is unscored.** One hand count on the
   frozen target unlocks steps 5-7 with no other work owed.
3. **If precipitates never ship, the AI Analysis room ships anyway**, for
   diffraction grouping alone, and the run continues to steps 8-9. The
   embedding half shares only step 1 and step 2 with the precipitate half.
4. **One commit per step; never push.**
5. **Exit 69 is recoverable: delete `~/Library/Developer/Xcode/DerivedData`
   and retry, once per refusal.** Asked again after free space fell to exactly
   8 GB mid-session against `run-tests.sh`'s hard 8 GB floor (`have < need`, so
   8 passes and 7 refuses) while `tools/free-space.sh` reclaims 0 bytes. The
   cache is ~921 MB of regenerable build product outside the repo; the cost is
   one slower rebuild. **Not** authorised, and so never done: thinning the
   Time Machine local snapshot made 18:38 today, which is probably the larger
   consumer. A refusal is always reported as a disk event, never as a test
   failure.

**Correction the same session, to a claim this file and `status.md` both
carried.** The port analysis says twice (§3 step 1, §5) that step 1 "creates
the headroom every later step spends". It does not. `tools/run-tests.sh:135`
measures each commit against its *immediate* predecessor — `HEAD` while a
budgeted file is dirty, `HEAD^` when clean — so every commit must be <= the one
before it and a saving is never bankable. What step 1 does buy is permanent and
different: the new `AnalysisMode` cases land in `ProductWorkflow.swift`, outside
both budgeted files. Step 6 still pays for itself inside its own commit, and
step 9 has no lever named yet.

**2026-09-11 — precipitate density is measured by CLASSIFYING diffraction
patterns, not by segmenting a virtual image (owner, in chat: "i approve").**
Supersedes `v3-plan.md`:64 ("per-object, real-space segmentation", 2026-08-06,
re-requested 2026-08-26) and stands in for the §1.5 design session, which was
skipped when the 2026-09-11 port reversed the 2026-09-08 "leave" decision — the
design session existed to question exactly these contracts, and porting to the
branch's design dropped it.

Why, and the owner reached it himself: the shipped route collapses each
diffraction pattern — 4096 numbers on the Al-Si-Mg cube — to ONE number, the
aperture sum, before any decision is made, and every later step tries to
recover structure already discarded. His two arguments, both correct: a virtual
dark-field image is *as an image* worse than HAADF, because a small aperture
collects few electrons; and the 4D dataset is far richer than any image formed
from it.

Three measured failures this session are all downstream of that one choice: a
shape filter deleted the end-on needle variant (17 counted where there were 35,
low by 2.1x); the ridge filter's own pre-registered baseline came out a TIE,
with both arms reporting every round particle the ridge filter exists to
reject; and the route has no upstream counterpart, so no parity harness is
possible for it — established 2026-09-11 and unchanged.

The decisive argument is verifiable rather than aesthetic:
`References/py4DSTEM-dev/py4DSTEM/process/classification/` already ships
`Featurization` (PCA, ICA, NMF, GMM, `spatial_separation`, `consensus`) and
`BraggVectorClassification` (NMF refine, split, merge) — including
`spatial_separation`, which is the segmentation step done on CLASSES rather
than pixels. **So the classification route can have a py4DSTEM parity harness
and the image route provably cannot.** The owner's own library carries the
method papers (Thronsen 2024 on SPED phase mapping of precipitates; Vogl 2024
on classifying fine beta-precipitates in AA6061; Ånes 2018; Bruefach 2023).

Pre-registered before any code in `docs/v3-precipitate-classification.md`, with
a symmetric ship gate: the new route must beat the image route on the owner's
adjudicated count, a tie passing, **or it does not ship and the image route
stands**. Five decisions are recorded there as still owed, including PCA vs NMF
and whether this retires the ridge filter.

**2026-09-11 — the AI work is NOT consolidated into one folder (owner asked;
explained and declined).** Only ONE file in the repository imports CoreML
(`Core/ML/LearnedDiskDetector.swift`); `DiffractionEmbedding` and
`Precipitates/*` call themselves "classical" in their own headers and are PCA,
k-means and image processing. `Core/` is organised by subject —
Analysis/Data/Crystal/Compute/Workflow — with `ML/` earning its place as the
repo's only strict framework boundary. An `AI/` folder would group by
technique, which is the mistake D1 (2026-09-01) forbade when it renamed Bragg
to "Strain & ACOM", and would mislabel two files that are not AI. One known
wrinkle, left alone deliberately: `Core/ML/LearnedDiskDetection.swift` is
orchestration and imports no CoreML, so it would strictly belong in `Analysis/`
beside `DiskDetection` — splitting two files about one feature costs more
cohesion than the taxonomy gains.

**2026-09-11 — the `docs/ai-ml/` design brief is ported to `main`; it should
have been ported at step 3 and was not.** The handoff listed
`docs/ai-ml/{README,precipitates}.md` under "what is unmerged and wanted", and
the port repointed every source citation to `ml/disk-detector:docs/ai-ml/…`
instead of bringing the documents across. The app therefore cited a design
brief that was not in the repository, and the inventory gate could not see it
because that gate judges truth docs, not `.swift` sources. Both files are now
under `docs/ai-ml/` and all nine citing files are repointed to plain paths the
gate can check.

**What that miss cost, and the owner caught it, not a gate.** README §5 is
"Thickness and the path to number density" — PACBED foil-thickness estimation
and the explicit chain to a VOLUMETRIC number density, which is the owner's
actual goal; areal is a way-station. §6 is "Diffraction clustering, similarity
and discovery", which the 2026-09-11 classification pre-registration partly
reinvented. **No code was lost — thickness was never implemented on either
branch, and `precipitates.md`:15 marks volumetric density a v1 non-goal — but
the design was, and writing a pre-registration without reading it was the
error.**

**2026-09-11 — PCA stays for now (owner, in chat).** NMF remains a named
comparison, not a prerequisite. For: a diffraction pattern is a non-negative
SUM of contributions and NMF models exactly that, while a negative PCA
coefficient means "subtract this pattern", which photon counts cannot do; NMF
components are indexable patterns rather than signed difference-patterns.
Against: NMF is non-convex with a random start, so runs differ unless seeded,
and it has no explained-variance equivalent for choosing a component count. PCA
is deterministic, fast and already gated.

**2026-09-11 — class identification should be TEMPLATE-MATCHED, not
unsupervised (owner's objection; recommendation recorded, not yet approved).**
He asked: "the user has to check by hand anyway what each class really is — can
we feed information beforehand? maybe we are running into slop here." He is
right that it is slop: k-means returns k *unlabelled* groups and nothing makes
them "matrix + 3 variants" rather than "thin + thick + bent + oxide". Since the
β″ structure is known, the classes can be labelled by matching against
predicted diffraction from an imported CIF — and **the app already owns that
engine**: `Core/Crystal/{CIFImport,CrystalModel,OrientationMatcher,Orientation‐
Plan,ScatteringFactors}.swift`, what ACOM runs on. Pointing an existing engine
at a second structure, not a new capability. Clustering becomes the fallback
for what templates do not explain. Owner owes a β″ CIF or agreement to fetch.

**2026-09-11 — the ridge filter is PARKED, not retired (owner: "maybe it has to
go, or come back later — maybe we were too fast").** A third option was not
visible when the question was first put: it is fixable.
`PrecipitateSegmentation.swift:389` computes both Hessian curvatures and keeps
only the most negative (`max(0, -lambdaMin)`), so a round blob — curved
downward in every direction — scores at least as high as a needle. It does not
measure elongation; it measures "is this a bump", which is exactly why its own
pre-registered baseline came out a TIE with both arms reporting every round
particle. Elongation selectivity requires comparing the two curvatures. It
should not be retired on a tie it lost for a correctable reason: if
classification wins, it is moot; if classification loses, fix the comparison and
re-run the baseline.

**2026-09-11 — class identification is TEMPLATE-MATCHED and MATERIAL-GENERAL
(owner, in chat: "yes that is a great idea! … more versatile for different
samples not just al").** Approves the recommendation recorded above. Identity
comes from an imported CIF, never a hardcoded Al-Mg-Si assumption — which also
discharges `docs/ai-ml/README.md` §2's standing requirement to "derive
everything from the data, not from Al-Si-Mg-specific constants".

**What that makes it: multi-phase identification**, already ranked immediately
before precipitates in `v3-plan.md`:20. Two blockers, measured rather than
assumed: `Core/Crystal/OrientationMatcher.swift:324` hardcodes `phaseID: 0`
(the field exists, one phase is ever written), and `ACOMCrystalSymmetry`
(`Core/Analysis/OrientationResult.swift:489`) covers cubic, hexagonal and
identity only, so monoclinic β″ falls back to "Unreduced".

**One hypothesis, explicitly untested, that would de-risk the second:** point
groups are needed to REPORT an orientation, not to decide WHICH PHASE a pattern
is — so `.identity` may cost search time rather than correctness, and
`v3-plan.md`:22's "multi-phase needs point-group coverage" may apply to the
orientation half alone. **Test it before relying on it.** Multi-phase for
precipitates also does not need grain segmentation; the plan pairs those for
polycrystal work and a precipitate is not a grain.

**2026-09-12 — the `unit` free-space floor drops 8 GB → 4 GB, on a
measurement (owner asked: "lower the floor to 6 GB?").** Not to 6, and not by
guess. Sampling free space every 3 s through a full
`-only-testing:mac4DSTEMTests` run measured **peak consumption 1245 MB**, and
the suite completed **602 passed / 0 failed with 7 GB free** — below the floor
that had been refusing to start it. The floor was blocking work it did not need
to block, and `run-tests.sh`'s own comment already admitted the floors were
"deliberately margin, not measurement".

4 GB is 3.2x the measured peak and is the value `scientific` and `benchmark`
already use, so this aligns the floors rather than inventing a weaker one. The
failure mode the floor exists for — a near-full disk producing varied spurious
failures, three different failure sets in three runs on 2026-08-06 — needs the
disk to actually fill during a run, which 4 GB against a 1.2 GB peak prevents.

**`all` and `campaign` keep 8 GB.** They add the scientific harnesses,
package-test and real-data-acceptance on top of the unit suite and nobody has
measured their peak. Lowering an unmeasured floor is exactly the guess this
change is refusing to make.

**What was NOT done, and why.** Moving `References/training_dataset` (7.1 GB)
off the internal disk would free far more, and nothing gated depends on it —
`real-data-acceptance` skips cleanly when it is absent and every other consumer
is `diagnostic`. It was not proposed as a destination because the only mounted
volume is the Time Machine backup drive, and working data does not belong on a
backup destination.

## 2026-09-12 — vector matching lands unvalidated, deliberately

The owner asked whether step 3 of `v3-vector-matching-plan.md` — scoring
against Thronsen et al.'s published ground truth — could be deferred and done
later. It can, and it was, on one condition: **the output is labelled
unvalidated everywhere it appears.** It is, in four places — `validation:
"none"` in every product's provenance, the task's guidance line, a banner above
the panel's legend, and the run's own status line.

The precedent is this repo's: the precipitate engines are on `main` unwired
with their ship gate openly unmet, and that has held up. The cost of deferring
is rework risk, not correctness — if step 3 later fails, steps 1 and 2 need
fixing and anything built on them was premature. That is bounded, and it would
be found before anything is published. The blocker is disk, not licence: their
`datasetA` is ~7.4 GB against a machine that ended the session at 5.7 GB free,
and the owner has already deleted everything he is willing to delete.

## 2026-09-12 — β″ becomes a built-in structure, not an import-only CIF

The same reasoning as WS₂ on 2026-08-31: an `.imported` model does not survive
into a new session, so a recipe recorded against an imported CIF cannot replay.
A built-in entry is what makes an Al-Mg-Si workflow reproducible at all. The
values are Andersen et al., *Acta Materialia* 46(9) 3283 (1998), Table 3 set 3
— experimental, and deliberately not Materials Project mp-31404, which is the
same phase under a compatible licence but DFT-relaxed, and relaxed volumes run
a few percent high in exactly the quantity this method matches on.

The C2/m expansion is written out in source rather than stored pre-expanded, so
it can be read, and it is asserted at Mg₁₀Si₁₂ = 22 atoms — the cell content
the paper states. Sources disagree on the axis setting (some publish a = 15.16,
b = 6.74, c = 4.05 with γ = 105.3°), which is what makes that assertion worth
having.

## 2026-09-12 — the matrix is stated by the user, never inferred

Which phase is the bulk is knowledge about the specimen, not about the data.
`PhaseDefinition.Role` carries it, exactly one phase may be the matrix, and a
library without one is refused rather than defaulting to the first in the list
— because a default there would make the verdict depend on the order the user
happened to add phases. This is also what makes "assign the matrix by
exclusion" possible, which is the part of Thronsen et al.'s method that lets a
precipitate be found without the matrix competing with it for the label.

## 2026-09-12 — an in-plane angle is reported modulo the projected symmetry

The gated harness demonstrates it on fcc [001]: 13.7° and 283.7° produce the
same spots, so no method that looks at spots can separate them. The matcher's
in-plane rotation is therefore recorded as
`matrix_in_plane_deg_mod_symmetry`, is shown in the panel as "(mod symmetry)",
and is never presented as an absolute orientation. The first version of the
harness check asserted the ANGLE and failed at 89.7° — the test was wrong, not
the code, and the check is now on the vector set with a sign-flipped plant
shown not to satisfy it.

## 2026-09-12 — the chance guard stays although it is inert at shipped settings

Gate B refuted the claim first made for it: removing it changes nothing at the
shipped settings, because its bar crosses `minimumMatchedVectors` only above
~45 surviving vectors per pattern and real SPED patterns here carry ~7. The
99.2 % → 5.5 % collapse credited to it is the matched-vector floor's.

It is kept rather than deleted, and the reason is not sentiment: a fixed
`maximumVectorsPerEntry` bounds a library's SIZE, and nothing else bounds what
that size costs on a pattern rich enough for the size to matter. The guard is
the only thing that scales with the pattern. What changed is the honesty of the
record — the gate now prints the three conditions apart, and the source names
the threshold at which the guard starts to bind, so the wrong one cannot be
credited again.

## 2026-09-12 — completeness is a chance-level test, not a fraction

A minimum matched FRACTION is the obvious guard against a phase explaining one
vector in ten beating one explaining nine. It was implemented, and it failed on
real geometry: the reference library is capped at `maximumVectorsPerEntry`, so
a pattern showing more spots than the library holds can never reach any
fraction — the harness's β″ positions went to 0 % indexed while being perfectly
matched. What replaced it has a number behind it: an entry must beat its own
`chanceMatchFraction` expectation by 5×. Removing it takes random-vector
accuracy from 99.2 % to 5.5 %, which is the measurement that says it is
load-bearing.

## 2026-09-12 — throughput leaves the status strip, which narrows a 2026-09-04 decision

On 2026-09-04 the owner asked for elapsed, throughput and ETA beside the
progress bar rather than "only one tab away" in the inspector. On 2026-09-12 he
called the same strip not "simple, stupid, macOS". Both are right, and the
resolution keeps the half that carries the decision.

**Elapsed and ETA stay in the strip. Throughput does not.** Three reasons, in
descending weight. Apple's own chrome carries units-per-second nowhere — the
HIG asks a progress indicator for "a description that provides additional
context", and rate belongs to Activity Monitor. It was the longest token in the
line by a wide margin: the widest string the formatter could produce with it is
180.9 pt against 113.6 without, so it alone was most of a 190 pt reservation in
a bar now called cluttered. And it is the one of the three a user can infer
from what remains — the bar and the elapsed time give it — whereas neither
elapsed nor ETA is derivable from anything else on screen.

It survives in Info › Performance, which is where it was before 2026-09-04. The
part of that decision this does NOT reverse is the part that mattered: the
numbers a user waits on are still beside the bar they are waiting at.

## 2026-09-12 — a readout is not an event

`ActivityLog` now has a one-shot suppression, and the scan-position line uses
it. The rule it encodes: the status line has two jobs — reporting what
happened, and showing where you are — and only the first belongs in a log.

Measured, on the owner's screen: every click on the scan image wrote
"Pattern x 154, y 152 from <filename>" through `statusText.didSet`, the
consecutive-repeat rule never fired because the coordinates differ every time,
and a 330 × 330 scan offers 108 900 of them against a 300-line capacity. Cursor
movement was evicting the run's real events — the detection, the import, the
phase map — from the record kept to explain them. The filename went too: it is
in the window subtitle, the sidebar and the toolbar, and repeating it in a line
that truncates is what truncated it.

## 2026-09-14 — `Crystal.reflections` deviates from py4DSTEM's tile bound, and a gate owns its own frame

py4DSTEM bounds every Miller index by `ceil(k_max / k_leng_min)`, the shortest
of ten reciprocal directions. That is not a bound on an index: `h = g·a₁`, so
`|h| ≤ kMax·|a₁|`, and on an oblique cell the shortest reciprocal direction can
be longer than `1/|a₁|`. Measured on the β″ shape at kMax 1.6: 6 reflections
lost at β = 110°, 48 at 115°, 198 at 125°, with no signal. The port now tiles
each index by `ceil(kMax·|aᵢ|)` and says so inline as a `DEVIATION`; every
shipped cell returns the identical set, and the deviation exists because phase
mapping is the first feature to hand this function arbitrary imported cells.
Parity with py4DSTEM on an oblique cell would now be parity with a defect.

The second rule this session sets: a harness may not take its in-plane frame
from the code it gates. `tools/phase-vector-matching` shared
`ACOMOrientation.detectorBasis` with `PhaseReferenceLibrary`, so a handedness
flip mirrored both and 27 of 27 checks stayed green. It builds its own seeded
frame now, as `acom-convention-test` always did, and the flip fails two checks.

## 2026-09-14 — Two verdicts a user reads: the matrix gets the last word, and a spotty annulus is refused rather than flagged

**A grain of the matrix phase on another orientation is reported as `.matrix`,
not "not indexed".** The alternative was tempting: matrix removal never ran for
that position, so the label means something operationally different from the
`.matrix` a removed pattern earns. It is still the truthful answer to the
question a phase map asks. The crystal there IS aluminium, a phase fraction
computed over that map is right only if it counts as aluminium, and a
hatched "unknown" over a quarter of the scan would be a worse lie than a
neutral grey. The evidence line carries the numbers either way.

**A Bragg-spot annulus makes the ellipse fit REFUSE, not warn — TAKEN, THEN
WITHDRAWN THE SAME SESSION.** The reasoning for refusing over warning still
stands: a warning next to a number is read as a number, and the owner's own run
carried a = 43.68, b = 39.72 downstream into a zone-axis fit and a phase map
before anything questioned it. What did not stand is the test. The shipped
statistic — the 90th-percentile azimuthal bin at 4× the median — was measured
by Gate B to be wrong in both directions: it refuses an amorphous halo carrying
sharp crystallite reflections, where the fit is exactly right at a/b = 1.000,
and it stops firing on the multi-grain case it was written for as the specimen
gets more polycrystalline (3 grains refused, 6 grains fitted and reporting
26.6 % distortion). It is a bright-bin-count test wearing a percentile's
clothes. The guard and its fixtures were reverted rather than tuned, because
the calibration that chose 4 had no legitimate SPOTTY single-radius ring in it,
and a bar placed between two clusters with the intermediate population
unsampled is a tuned number however it is described. The decision the next
attempt needs from the owner is which behaviour he wants at all — refuse, flag,
or leave — and `open-items.md` carries the three refuted remedies, the one
untried lead, and the fixture that is missing. Recording the withdrawal here
rather than deleting the paragraph: the argument for refusing over warning is
worth keeping, and so is the evidence that a good argument is not a test.
