# 036 — The toolbar carries the room: run/stop, the file and the live run, the actions; the breadcrumb row goes

Dates: 2026-09-22 (evening)

Status: live — decided on the owner's own build, corrected six times on his word the same evening (toggle placement, a doubled toggle, the verb's side, the picker's row, the picker hiding with the column, the picker back into the inspector's row as icons)

## Decision

The window's toolbar is Xcode's (owner, 2026-09-22 evening, `window-design.md`
§8.1, answered "as drawn, row 3 goes" to the mock):

- **Centre, a display, never a button:** the file, the room and the scan
  size when idle ("Demo.h5 · Prepare · 144 positions"); the running
  operation, its bar and its elapsed/ETA when busy. A constant width
  (`LayoutPolicy.toolbarDisplayWidth`), so a ticking string never reflows
  the toolbar (011); the 2026-09-04 "C…" trap was a *button* in the centre.
- **Trailing, over the room:** first the room's one run button — the blue
  verb, **Stop** in its place while a run is in flight — then Save to
  Session (archive box), Reveal in Finder (folder) and the dataset menu
  (cube stack) as icons, the words on hover and for VoiceOver. Always
  present, so the analysis runs with both side panels hidden and the data
  at full size. The mock had put the verb at the leading edge, Xcode's Run
  position; the owner moved it on his build: the parameters are set in the
  inspector on the right, so the verb belongs under it, not by the
  navigator.
- **Over the inspector: only its toggle**, declared in the inspector's own
  toolbar, the standard SwiftUI shape (the split view supplies the
  navigator's toggle, the app supplies the inspector's). Items declared
  there stay in the toolbar once while the column is hidden, so the
  toggle needs no fallback and any fallback doubles it (the owner saw
  two, twice). The Settings · Info tabs are icons in the inspector's own
  first row under the toolbar — Xcode's anatomy; the text picker up in
  the toolbar row was rejected the same night ("jumps to the left of the
  toggle button, looks bad").
- **The breadcrumb row (phase 1's centre header) is removed**; the panes
  gain its height. The room is named in the navigator's selection and in
  the centre display.
- **The infobar is 34 pt** (was 22, then 28): "wider, like Xcode's" debug
  bar. While a job runs it carries the live run — a progress bar,
  "done / total · rate · elapsed · ETA" and a Stop button; idle, it shows
  "Last run · <name — duration>". Always the glance "engine · memory ·
  residency", and the two process-pane buttons beside the area's own
  toggle. The toolbar's centre display then shows only the operation's
  name and elapsed while busy.

This supersedes §6.2 of the same morning (actions in the centre header) and
010's "toolbar carries only window-level controls".

## Why

The owner's drive of phase 1 (2026-09-22 evening): the room's actions must
survive hiding both side panels, and a header row that repeats the
navigator's selection is space taken from the science.

## Governs

`ContentView.windowToolbarContent`, `WorkspaceInspector`'s toolbar
(`InspectorToggleButton`, the picker), `ToolbarRunDisplay`,
`ToolbarDisplayFormat` (one test, red under a mutation); the
`--inspector-hidden` / `--inspector-shown` / `--navigator-hidden` /
`--navigator-shown` launch flags, capture scaffolding in the
`--demo-fixture` shape;
`WorkspaceView` without `CanvasHeader`; `LayoutPolicy.toolbarDisplayWidth`,
`statusStripHeight`, `LayoutPolicy.runReadoutWidth`, and the two
process-pane toggle buttons at the infobar's right end. The shell stays
frozen (035): this is the picture he accepted.

## Sources

- `docs/window-design.md` §8.1, §8.6, the two mocks of 2026-09-22 evening
- `docs/archive/v3/ui-review-2026-09-22.md` §4 (item 1)
