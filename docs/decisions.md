# Decisions

Append-only. One paragraph per decision: what, why, when. The evidence
behind each lives in `docs/archive/`; this file is the index a reader
checks before re-opening a settled question.

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
not decomposed. Full record: `docs/v2.5-plan.md` §4.

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
picker. The full contract is `architecture.md` "The UI2 contract".

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
contract.
