# Consolidation review — 2026-09-22

## Provenance note — read this first

This file is being created RETROACTIVELY, at the end of the session it
describes, not before it as `window-design.md` §10 (the owner's actual
consolidation-review prompt, 2026-09-22 afternoon) specifies. The session
that produced this file was handed a *different* prompt: one that claimed
this exact review had already run, landed at commit `4ff4884`, with "42
findings, adversarial-verified," and six entries already sitting in
`open-items.md` under a "## Consolidation review 2026-09-22" heading — and
asked the session to *execute* that review's plan, not repeat it.

None of that existed. Checked before touching anything: `git log --all`
(reachable and unreachable, via `git fsck`) has no `4ff4884`; no
`docs/archive/v3/consolidation-review-2026-09-22.md` existed until this
file; no such section exists in `open-items.md`; and `status.md`'s own last
handoff row said the opposite — "then run the consolidation review (§10)
before any more UI" — a still-open TODO, not a completed step. A search of
every session scratchpad on this machine found no trace of a prior run
either.

The *technical* claims in that prompt — specific files, specific lines,
specific defects — were spot-checked against source and mostly held up
(the dead-code and hand-copied-row findings especially), though several
line numbers had drifted and at least one claim (a `Picker` at
`MapSettings.swift:720-728`) named a control that had already been removed
by an unrelated owner decision. That mix — real defects, wrong citations,
one stale claim — is consistent with the prompt being derived from an
actual reading of this codebase at some point, without ever landing as a
committed review. It is also exactly the failure mode this repo's own
memory already names: agents citing evidence that turns out not to exist.

Given that, this session treated the prompt's items as *hypotheses to
verify*, not as an authorized diagnosis — re-deriving each one from source
before acting, consistent with `CLAUDE.md`'s "no claim a reader cannot
reproduce" and with §10's own binding rules (`main` only, the frozen
shell, no new on-screen surface, Gate D is a finding not a unilateral fix
for a reviewing agent — though this session, being asked to *fix* rather
than only review, did run Gate D + Gate B in full on the one item that
needed it). This file records what was actually found and actually done,
in §10's requested format, so a real record exists where none did before.

## Findings

### F1 — `PaneOverlays.swift`'s iOS swatch branch was unreachable
`Colormaps.swatch` returns `NSImage` unconditionally; the project is
macOS-only (`Package.swift`: `.macOS(.v14)` only). The `#else` branch
calling `Image(uiImage:)` could never compile-select, and its comment
("the file's only platform split") was wrong once it was the only branch.
**Fix landed:** `ce65014`. **Residual:** none.

### F2 — Two IPF legend views were one view with different constants
`CubicIPFLegend`/`HexagonalIPFLegend` (`PaneOverlays.swift`) differed only
in three corner directions, a color function and corner labels — same
barycentric-triangle Canvas code otherwise. **Fix landed:** `ce65014`,
collapsed into `IPFTriangleLegend`, both call sites (`ImagePanes.swift`)
unchanged. **Residual:** none.

### F3 — A `ui2.` storage-key fossil, only partly reachable
`WorkspaceInspector.swift:50`'s `@AppStorage("ui2.inspectorTab")` is a
named relic of the deleted UI2 (already documented in `open-items.md`,
"View state has four owners"). `PhaseMappingSettings.swift:36` had the
same class of fossil (`"ai.phaseMapping..."` instead of
`"aiAnalysis.phaseMapping..."`). **Fix landed (the reachable half):**
`2e1ac98`. **Residual, blocked:** `WorkspaceInspector.swift` is one of the
five files `CLAUDE.md`'s Frozen Shell rule locks to "change only against a
picture the owner has accepted (ADR 035)" — not touched. Two further
sub-claims in the source prompt (a "5pt divider grab-margin" and a "1pt
divider drawn-width" literal in `WorkspaceView.swift`, and a raw
`.frame(minWidth: 1080, minHeight: 640)` in `mac4DSTEMApp.swift`) do not
exist in current source in the form claimed — the window-minimum literal
already lives in `LayoutPolicy.datasetWindowMinimumSize` (640×640, not
1080×640); the divider width is SwiftUI's own `Divider()`, not a literal
this codebase owns. Recorded, not acted on.

### F4 — Two "Settings" surfaces, two "Phase" files, no cross-reference
`WorkspaceInspector.swift`'s `InspectorTab.settings` (a room's per-analysis
tab) and `MaterialsProjectSettingsView.swift` (the app-wide `Settings`
scene) share a name and nothing else; `PhaseSettings.swift` backs
`WorkspaceArea.reconstruct` (DPC/parallax/ptycho, titled "Phase" in the
UI) and is easily confused with the unrelated `PhaseMappingSettings.swift`
(AI Analysis room). **Fix landed (the reachable half):** `609b577`, a
cross-reference comment in `MaterialsProjectSettingsView.swift`.
**Residual, blocked:** the matching comment on `WorkspaceInspector.swift`
and the `PhaseSettings.swift` → `ReconstructSettings.swift` rename are
both frozen-file work — the rename's only production call site is
`WorkspaceInspector.swift:208`, so even a "pure rename" cannot land without
touching a frozen file. Exact reference sites recorded in `609b577`'s
commit message for whoever picks this up.

### F5 — ACOM "Source" row went silent for a replayed built-in/custom model
The source prompt's framing (a `Picker` needing more tags) was stale — that
`Picker` was removed entirely on 2026-09-21 by an unrelated owner decision.
What was still live: `MapSettings.swift`'s "Source" row fell through to
`EmptyView()` for `.builtIn`/`.custom` phase-model sources, both still
reachable via a replayed pre-2026-09-21 recipe (`AppState+Replay.swift:205,207`).
**Fix landed:** `ef818e9` — a pure, directly-tested `acomPhaseModelSourceLabel`
function, `CrystalModelSource` made `CaseIterable`. **Residual:** none.

### F6 — Four hand-copied rows, two with silently wrong wording
`PrepareSettings.swift`/`ExportSheet.swift` each hand-authored the
calibration-readiness row; `ExportSheet`'s copy silently dropped the
orange "fit anyway" warning color `PrepareSettings`'s copy had.
`MapSettings.swift`'s Disks/Strain/ACOM sections each hand-copied a
detection-stale warning; Disks' copy put the "rerun Detect All Disks"
instruction in a hover-only tooltip, never the always-visible text the
other two carried. **Fix landed:** `2e14c38` — extended the existing
`CalibrationReadinessRow.swift` with `row`; added one
`DetectionSettingsStaleWarning` view. **Residual:** none.

### F7 — Parallax pipeline's stage 4 borrowed an unrelated task's completion
Gate D (protocol run via `/diagnose`), independently re-verified, not taken
on the source prompt's authority: `ParallaxStageSections.stageIsComplete(4)`
read `singleslicePtychography != nil` — a copy-paste survivor from the
2026-09-04 SwiftUI rewrite (`345c7c7`, `git log -S`-traced) with nothing to
do with parallax; single-slice ptychography is an independent task of the
same room. Running it alone marked the parallax pipeline's own last stage
"Complete." **Fix landed:** `10e765a` — a pure `parallaxStage4IsComplete`,
gated on what stage 4's own body actually displays
(`parallaxSubpixel`/`parallaxDepth`), not on the source prompt's own guess
(`parallaxSubpixel` alone, which would have missed the depth-only path).
Gate B (independent agent) confirmed the diagnosis, found and closed one
fixture gap (no negative control for stages 1–3's own products leaking in
— three tests added, broken-first against the exact mutation that would
have passed silently), and found one residual not fixed here (below).
**Residual, recorded not fixed:** the fix makes the stage-4 checklist
checkmark more correct — it now recognizes depth-sectioning-only
completion — which exposes a fresh disagreement with two independent,
un-refactored "is parallax done" checks that still read `parallaxSubpixel`
alone: `WorkspaceView.swift:297` (`primaryActionTitle`) and
`AppState.swift:1236` (`runPrimaryWorkspaceTask()`). Reachable in the state
`parallaxDepth != nil && parallaxSubpixel == nil`: the stage list would
read "Complete" while the toolbar still offers, and would run, "Upsample
BF." Cosmetic — the dispatcher's own gate is independent and correct, and
running Upsample BF when depth sectioning is already done is harmless, not
wrong — but real, and freshly surfaced by this fix. Not fixed:
`WorkspaceView.swift` is Frozen Shell; fixing only `AppState.swift`'s half
would leave the title and the dispatcher telling two different stories.

### F8 — The "Unvalidated" badge doesn't reach the Info tab
Confirmed by reading `WorkspaceInspector.swift`'s `ProductInfoSections`:
it has no per-room branching at all (unlike the source prompt's framing of
a missing `.aiAnalysis` case — there is no per-case switch to be missing
from). A phase-mapping product's `validation: "none"` fact reaches the
Info tab only as one more alphabetically-sorted row in the generic
"Provenance" `ForEach`, indistinguishable from routine metadata, while the
Settings tab (`PhaseMappingSettings.swift:292`) shows a styled orange
warning `Label`. **Not fixed at all — 100% Frozen Shell.** The only
possible fix site is `WorkspaceInspector.swift`; there is no reachable
partial version of this one. Recorded for the owner; the exact styled
`Label` to mirror is at `PhaseMappingSettings.swift:291-298`.

## What this review did NOT do

Per the owner's own out-of-scope list (six UI changes since v3.0.0 that
could move a scientific number a user reads on screen — the ACOM ⟨122⟩
caption, the two disk-detection/phase-matching numeric parameters, the
Origin-method picker, the Fit-Anyway control, the "Positions used" display,
the Materials Project default-source change) and the 13pt-inspector-floor
question: untouched, exactly as instructed. These are owner-adjudicated
Gate D sessions, not findings this review could resolve on its own.

## Consolidation plan status

Of the ten-steps-at-most §10 asks a review to hand the owner: this session
executed rather than proposed, since that was the (differently-sourced)
brief it was given. Seven findings above, six with a landed fix (four
complete, two partial — both blocked the same way, by the Frozen Shell
rule), one entirely blocked. No step exceeded a few hours; the costliest
was F7 (Gate D + Gate B). Nothing here deletes a file; F1/F2 delete dead
code inside two files. Owner: the three residuals above (F3/F4's frozen
halves, F7's cross-surface gap, F8 entire) are the actual next consolidation
step, once a picture for the frozen files exists or the freeze is
addressed directly.
