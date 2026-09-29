# The app aborts in the AI Analysis room below ~1000 pt — Gate D (2026-09-29 night)

Found by overnight drive 3 (scratch Debug build of `e1ea1ff`'s tree, Thronsen A loaded): six SIGABRTs, all the same
uncaught NSException from `-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]`, raised under
`NSHostingView.setNeedsUpdate` ← `AppKitPlatformViewHost.invalidateLayout` ← SwiftUI's update group (the stack drive 3
also read through `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`). Triggers: entering AI Analysis
(Phase mapping) at 915 or 950 pt wide, or shrinking to 915 or 975 pt while in it. 1000 × 720 and 1000 × 760 survive;
Prepare and Bragg disks survive 915. Nothing computing; footprint ~130 MB. Crash reports `d3-crash-{1..6}.ips`.

## Diagnosis (not yet established)

The same family as 2026-09-28's launch crash (`archive/closed-items-2026-09.md`: window − sidebar ≤ 639 pt): a split
child whose content minimum exceeds the width the split can give it, so the hosting view's min-size update and the
window's constraint pass invalidate each other until AppKit throws. What differs in AI Analysis is its content's
minimum width — a row, pane header or overlay in the phase-mapping room that will not compress — not tonight's code.

## Refuting observations

1. The pre-night tree (`1a76089`, before A1–A4) does NOT crash at 975 pt in AI Analysis → tonight's work caused it
   (A4 touched `ImagePanes.swift`'s scan pane and `PhaseMappingSettings.swift`).
2. The crash needs a loaded dataset or a phase map in AI Analysis and does not occur on an empty AI room → the minimum
   comes from result content, not the room's settings.

## Experiment and prediction

E1: build `1a76089` exported with `git archive` (no branch, no worktree) to scratch DerivedData; drive: Thronsen A,
window 975 × 720, open AI Analysis. **Predicted:** it crashes too (pre-existing). E2: the same build/tree, AI Analysis
entered with no dataset loaded at 915 × 720. **Predicted:** no crash if the minimum is result content; a crash if it is
the settings column. E3 (only after E1/E2): bisect the minimum by hiding one AI-room section at a time in a scratch
copy, never in the repo. Nothing ships from this record without a refuter; a fix that touches a Frozen Shell file is
the owner's.

## E1 + E2 (2026-09-29 02:40, the orchestrator driving; build-pre.log, `e1-pre-crash.ips`)

The pre-night tree `1a76089`, exported with `git archive` and built to scratch DerivedData (Debug), launched alone at
915 × 720: AI Analysis → Diffraction groups and → Phase mapping with **no dataset** survived (E2, as predicted);
opening Thronsen A from Recents with Phase mapping selected **aborted** with the identical exception and stack (E1, as
predicted). **Pre-existing, not tonight's work**; refutation 1 did not fire, refutation 2 did not either (the empty room
lives). The minimum comes with loaded content. Next: E3, bisect it in a scratch copy.

## E3 — the minimum found (Opus diagnostician, scratch copy only; `e3-result.md`, `e3-log.md`, predictions logged first)

A width probe in a scratch copy: the detail column's minimum stayed 0 (panes and overlays are not involved); the
**inspector's** content minimum is set by one Phase-mapping row, "Ignore peaks beyond" (`PhaseMappingSettings.swift:218`):
a fixed-size label + 12 pt + the 72-pt field + the fixed-size unit "Å⁻¹ (0 = detector)" = **332 pt**, so the inspector
cannot go below 364 pt (2 × 16 padding) where the room is given 288 (ideal 320) or 248 (minimum 280). Before the abort the
inspector was offered 320 and answered 364 repeatedly while the detail was offered 284 → 404 — the loop. Every other
room's widest row fits (Prepare 207.5 pt). With the unit shortened to "Å⁻¹" (row 244, inspector 276) the same start
**survived** (T6). Two Known-variants rows are also too wide (306, 267 pt) but alone did not abort (the split took the
difference from the sidebar). Refuted along the way: a clean width threshold — once the inspector had grown, 950 pt
did not abort but pushed the inspector off the window's right edge (path-dependent; the same row's second symptom).

## Refuter (Opus, read-only; `e3-refuter.md`): NOT REFUTED WITH FIXES

Holds: the loop is caught in the act (inspector offered 320, answers 364; detail minimum 0), and drive 3's crash 1 is
its own discriminator (Diffraction groups drawn at 915 lived; the click to Phase mapping aborted). **Corrected:** T2
reopened on Phase mapping, not Diffraction groups (the measured 332-pt minimum exists only there); and the trigger is not
"the split cannot give the width" — a fresh launch at 950 had 392 pt to spare and aborted — but **a content minimum
larger than the column's current width at the moment the content appears or changes**, which explains the path
dependence. The only line the evidence supports: **content minimum ≤ the inspector's declared minimum − padding
(280 − 2 × 16 = 248 pt)**. Also: one surviving trial is thin; drive 3's full state (Known variants, three phases, a
map) was not reproduced; **data-derived labels** (the legend's phase names, unbounded — a long Materials Project name)
are fixed-size and would bring it back. Fixes: every row measured ≤ 248; data-derived names truncate (middle) with the
full name in help; a guard test over the rooms' settings widths; a confirming drive (three fresh launches at 915, both
classifier modes, a computed map, resizes 915 → 1000 → 975 → 950 → 915, a long phase name).

## Fix, part 1 — the room's own rows (landed); drive 4: two triggers remain, both in the Frozen Shell

Landed (`PhaseMappingSettings.swift`, `InspectorRows.swift`, `PrecipitateObjectsSection.swift`): "Ignore peaks beyond"
unit "Å⁻¹" (meaning in the help); "Direct matrix, max", "Specific reflections, min", "Min. intensity … of max" (each
measured ≤ 248 pt); phase names in the legend and Precipitates rows truncate in the middle (`InspectorDataRow`).
`InspectorWidthBudgetTests` (12 tests) hosts every room's settings and asserts a minimum ≤ 248 pt — phase mapping 245
in both classifiers, with Advanced open and a 53-character phase name; red on the old unit (333), each old label (267,
306, 287), a fixed-size legend (431) or Precipitates row (395). Unit 957 / 0 / 2 = 959 (`unit-fx.log`).
**Drive 4** (build-app-4, five launches at 915 × 720; `report-drive4.md`, unified-log excerpts `d4-crash-{1,2,3}.log` —
ReportCrash wrote no .ips): entering AI Analysis and Phase mapping, three CIFs, Known variants, Map Phases and the
915 → 1000 → 975 → 950 → 915 resizes now **survive**; a 60-character phase name truncates and widens nothing
(`d4-L4-03`). **Still aborting, same exception:** (1) switching the inspector to its **Info** tab at 915 (twice; its
dataset rows — path, shape, size — are wider than 248 pt); (2) dragging the inspector divider to its **widest**
(max 460 > what 915 leaves). After Info has been shown once, the layout overflows the window by ≈ 17 pt (sidebar and
the settings' units clipped, `d4-L1b-03`) and the restored Info tab carries that into the next launch. Both triggers
live in `WorkspaceInspector.swift` / `LayoutPolicy.swift` (Frozen Shell): **the owner's**, with the proposal in the
overnight plan §5 — the Info rows truncate like `InspectorDataRow`, and the inspector's maximum follows the window.

## Fix, part 2 — the shell (owner's go 2026-09-30: "go with your proposal for the 915-pt floor")

Frozen Shell files changed against the proposal the owner accepted (overnight plan §5 A): (1) `InspectorValueRow`'s
label keeps its full width when it fits (priority 2) and truncates in the middle only when it cannot — Info labels
are often data (provenance keys); (2) the inspector's maximum follows the window, `LayoutPolicy.inspectorMaximum` =
window − (sidebar max, when shown) − dividers − both science panes' floor, clamped to 280–460, read from the window's
width outside the split; (3) the sidebar steps aside when the panes would fall under 240 pt
(`LayoutPolicy.navigatorFits`), as a width flag separate from the user's intent (`navigatorCollapsedForWidth`),
written only on crossings, so Show Tools on a narrow window sticks and nothing is saved. Tests (4, in
`InspectorWidthBudgetTests`): the Info sections with long real data ≤ 248 pt; the inspector's maximum never
overflows any window 915–2000 pt; the collapse line; the toggle semantics — each red under its mutation
(`floor-mut-3.log`, `floor-mut-2.log`: fixed-size label, fixed 460, toggle not clearing the flag, visibility ignoring
the flag, collapse never). Unit 965 / 0 / 2 = 967 (`unit-floor.log`). **Unverified on screen** until a drive at 915.

## Part 2 regression, found by the confirming drive (2026-09-30 morning) — registered before the experiment

Drive (scratch build of `98bb0d3` + a row-layout change, Thronsen A): 915 pt, Info tab — lives; inspector dragged to its
widest (460) at 915 — lives, nothing clipped. Then widening to 1150 **jumped the window to 1420** (the sidebar came back
by the width flag and macOS grew the window by its 270 pt), and narrowing to 960 put AppKit in an update-constraints
loop (`update constraints count` past the 300 limit, unified log) and the process died — twice, two launches.
**Diagnosis:** the inspector's live maximum depends on `navigatorIsVisible`, which the width flag flips in the same
pass the window narrows: at 960 pt the maximum is 325 with the sidebar and 460 without, while the inspector sits at 460 —
the column is squeezed and released in alternation. **Refuted if** a build whose maximum ignores the sidebar's
visibility (window − sidebar max − dividers − science floor, always) still loops on the same sequence. **Predicted:**
that build lives through the sequence; the collapse alone (static 460 maximum) is not the loop. A second observation
to fix regardless: the sidebar's return growing the window (1150 → 1420) is a jump the user did not ask for.
