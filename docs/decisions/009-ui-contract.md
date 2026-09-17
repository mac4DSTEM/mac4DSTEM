# 009 — The UI contract: SwiftUI only, no AppKit shell, `LayoutPolicy`, three columns, no focus model, no new state on `AppState`

Dates: 2026-09-03, 2026-09-04

Status: live (the 2026-09-03 AppKit-column entries are superseded by the
2026-09-04 SwiftUI rebuild)

## Decision

`UI/` is the SwiftUI rebuild; there is no second UI and no flag selects one.
The left column is navigation only; every control the selected workspace
owns lives in the inspector's Settings tab beside an Info tab; that is
Xcode's/Pages'/Keynote's shape and it ports to iOS, where an inspector
becomes a sheet. `UI2PaneSplit` replaces `HSplitView`, which aborts nested in
a `NavigationSplitView` detail; `inventory` greps for the ban. The pane focus
model (`FocusedPane`) is retired; `AppState.activePane` survives only as ROI
direction storage. A run button is enabled by `ProductWorkflow.mayRun` and
nothing else; a sidecar-writing control by `SessionGates.mayWriteSidecar`;
ad-hoc `appState.*` conditions duplicating a prerequisite are removed rather
than kept "for safety". Superseded: the 2026-09-03 decision to own the
columns with `NSSplitViewController` (AppKit) — that shell and its 27 pinning
tests were deleted the next day when the SwiftUI rebuild replaced it wholesale.

## Why

Keeping two UIs compiling doubled the build and let display logic drift
apart silently (a 1-2-5 scale-bar quantiser existed as two separate copies).
The Settings/Info split retires two failure modes of the old shared column at
once (a 250pt wall and a 600pt sprawl) and gives iOS a natural home. A
workflow could not express every prerequisite the ad-hoc conditions were
guarding, and none needed adding once the audit was done.

## Governs

`mac4DSTEM/UI/LayoutPolicy.swift`, `UI2PaneSplit`, `ProductWorkflow.mayRun`,
`SessionGates.mayWriteSidecar`, `AppState.activePane`, `tools/run-tests.sh inventory`'s UI greps.

## Sources

- 2026-09-03 "The columns are AppKit's" (superseded), log line 108
- 2026-09-03 "One split-view contract, like Xcode" (superseded), log line 119
- 2026-09-03 "Step 7c decisions" (Results inspector, FocusedPane — later retired), log line 84
- 2026-09-02 "Results is three columns (7c slice 1)", log line 383
- 2026-09-04 "`UI/` retired; the SwiftUI rebuild IS the UI", log line 206
- 2026-09-04 "UI2's shape: navigation left, science centre, controls right", log line 244
- 2026-09-04 "UI2 may not use `HSplitView`", log line 260
- 2026-09-07 night "C4(a): one enable logic, named", log line 537
- 2026-09-03 "Presentation contract rule 3 is held by a grep, not a hosted
  test" (the UI-contract enforcement `tools/run-tests.sh inventory` still
  uses), log line 172
