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
