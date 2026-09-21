# 034 — Bottom workspace holds live state; the inspector holds durable state

Dates: 2026-09-21

Status: live for live/durable state; 2026-09-21 layout rejected and revised by owner 2026-09-22

## Decision

The main window's bottom area is a second workspace, not a resizable log
(owner, 2026-09-21). It has three tabs — **Output** (the rolling log),
**Run** (the live operation monitor: step, positions done / total,
throughput, MB streamed, elapsed and ETA, residency, Cancel) and
**Lineage** (the replay record's steps and the displayed product's
provenance; the lineage graph with rewind follows the record, `ROADMAP.md`).
The permanent status strip stays one line: status text, a tiny progress
bar with elapsed/ETA in its reserved slot (011), a memory/residency glance
in a second reserved slot, and the bottom-pane toggle.

The split that decides where a number goes: the inspector holds **durable**
state and settings (what the dataset and the session are); the bottom pane
holds **live** operational state (what the app is doing now). The
inspector's Performance rows therefore move to the Run tab, and the strip
gains a glance rather than a readout.

The inspector follows Xcode's utility pane: flat collapsible sections with
a caption header, one label column (`LayoutPolicy.inspectorLabelWidth`),
hairline separators, and Lightroom-style adjustment rows (slider plus an
editable value field) — the shared vocabulary in `UI/InspectorRows.swift`
(`InspectorSection` with an optional header icon and emphasis, an untitled
`InspectorGroup`, `InspectorRow`, `InspectorValueRow` with a monospaced
form for paths and shapes, `AdjustmentSlider`, `InspectorNote`,
`InspectorActionRow`). A section remembers its own collapse under a key
scoped by tab and room, so two rooms' "Dataset" sections never collapse
together. The `.grouped` boxes and the 2026-09-21 nested `.columns` trial
are retired.

**2026-09-22 layout amendment:** The owner rejected the 2026-09-21 restyle
on screen. `docs/window-design.md` §1 and §6 now govern the anatomy: the
infobar itself is the full-width drag handle within the centre column; the
inspector uses one top-level `.columns` form; the room actions live in the
centre header with breadcrumb pinned left and actions grouped right. Its
width flexes when either full-height side panel toggles. The shared row
vocabulary above records the rejected implementation, not the target for
phase 2. Phase 1 has not been accepted on screen.

## Why

The owner's reading of the app (2026-09-21): the centre panes were noisy,
runtime feedback was one line, and the inspector looked assembled rather
than designed. Xcode's model — calm editors, a debug area with a real job,
a dense utility pane — is the one he works in all day.

## What it governs

All height and width numbers are `LayoutPolicy` constants (009): the strip
is `statusStripHeight` (22 pt, was ~24), the tab bar `bottomTabBarHeight`
(26 pt) rides on the pane's dragged height (`bottomWorkspaceHeight`, capped
at `bottomWorkspaceMaxFraction` of the workspace). The pane stays a SwiftUI
drag-resized inset, never a `VSplitView` (009). Live numbers are owned by
`OperationCenter` / `AnalysisOperationController` — positions done, bytes
streamed (frozen by the same guard as progress once a run is cancelled),
and the last run with its outcome, so a cancelled run reads "cancelled
after 3 s", never as a success; the tab selection by `WorkspaceNavigation`;
nothing new is stored on `AppState`. The tab bar's 26 pt exist only while the pane is open. Copy, search
and filter for Output, and the lineage graph, are later steps. The old
maximum fraction is superseded by `window-design.md`: dragging the infobar
must span the centre column's full usable height, subject to a documented
SwiftUI limitation if that proves impossible.
