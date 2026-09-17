# 017 — Clicking a pane selects it again

Dates: 2026-09-11

Status: live

## Decision

Clicking the real-space or diffraction pane sets `AppState.activePane` again,
via a `simultaneousGesture(TapGesture())` on each pane, composing with the
detector drag, scan scrub and ROI handles rather than swallowing them. This
reverses two earlier calls (the 2026-09-04 focus-model retirement and a
consolidation finding that called selection-driven inspector switching "a
pane focus model the contract says does not exist").

## Why

Selection driving the inspector is the Mac idiom (Xcode, Keynote, Sketch,
Figma). What made the old behaviour confusing was not that the inspector
followed the selection — it was that nothing showed what had been selected.
With `ActivePaneOutline` in place, refusing to let a click move the selection
became the surprising behaviour.

## Governs

`mac4DSTEM/UI/ImagePanes.swift`'s tap gesture, `ActivePaneOutline`,
`AppState.activePane`.

## Sources

- 2026-09-11 "clicking a pane selects it again, reversing two earlier calls", log line 821
