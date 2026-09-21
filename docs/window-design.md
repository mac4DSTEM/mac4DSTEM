# Window design — the reset (2026-09-22)

**Status: decided 2026-09-22 (§6); phase 1 in build.** Written after the owner drove the
2026-09-21 restyle (`9fd386d`) and rejected it: "cramped, no logic to the
panes, no workflow behind it". The findings are in `open-items.md` (Owner
drive 2026-09-21). This file says what the window is for, what the two
reference apps do, what today's window gets wrong structurally, and the
anatomy proposed instead. It is a design doc, not a truth doc.

## 1. What we are building

A scientifically useful 4D-STEM app for a working microscopist: load a
cube, calibrate it, detect disks, map strain and orientation, identify
phases, export something a paper can cite — every step reproducible from
the session sidecar, every refusal naming what is missing. The window's one
job is to make the pipeline's **state legible and the next step obvious**:
where am I, what has been computed, what is the one thing to do next, and
what is the app doing right now. Science lives in `Core/`; the window only
presents it (ADR 009). Everything below is judged against that job.

## 2. The two references

**Xcode** (window anatomy). One unified toolbar. Three full-height columns:
navigator · editor · inspector. The inspector reaches the window top; the
only toolbar item above it is its toggle; ⌥⌘0 removes it completely. The
editor owns its own header (the jump bar) — actions about the thing being
edited sit over the thing, not in the window chrome. The debug area rises
from the bottom by dragging the bar above it, and it is a real area with a
job (console · variables), not a log. Calm editor, dense utilities.

**Pixelmator Pro** (the tools bar). One panel, one alignment rule: the
name left, the control right, the value at the far edge. Each adjustment is
a card with a title row — name, reset, auto, an on/off switch — and slider
rows beneath it; sub-choices are a small segmented control inside the card.
Regular-size controls, 13-pt text, an 8-pt rhythm, generous card padding.
Nothing truncates, nothing is centred, every row looks like every other
row. Dense because it is consistent, not because it is small.

## 3. What today's window gets wrong (from the five screenshots)

1. **The inspector is inset under the toolbar.** `.inspector` is applied to
   the detail view (`ContentView.swift`), so the column starts below the
   toolbar and the toolbar's trailing group — the room's blue primary action,
   archive, folder, toggle — floats over it, or over the canvas at other
   widths. The sidebar reaches the top; the inspector does not.
2. **The room's primary action lives in the window chrome**, which is why
   the inspector cannot own its top edge or toggle away cleanly.
3. **Three alignments in one column** (Prepare): trailing action rows,
   leading bare buttons, a label column, and status text floating mid-row.
4. **Everything is `.controlSize(.small)`**: 11-pt controls, three buttons
   crammed in a row and truncated ("Use Cu…", "Vacuu…").
5. **Sections toggle on the chevron only** (macOS `DisclosureGroup`).
6. **No workflow in a room.** Prepare is Pattern → five calibration items
   each with its own button → manual Q fields (before the calibrations they
   depend on) → R scale → a five-line orange paragraph → Voltage → Clear.
   The step order, each step's state and its one verb are not legible.
7. **The bottom pane is a log with tabs.** The strip is not a grab handle,
   the pane's height jumps with the tab, and nothing "second workspace"
   comes up.
8. **Settings / Info** is a two-word segmented control jammed under the
   floating toolbar buttons.

None of this is a wrong number; all of it is structure. The 2026-09-21
vocabulary (`InspectorRows.swift`) is not the problem — the problem is
that it was applied to the old structure without a design.

## 4. The proposed anatomy

```
┌ toolbar ──────┬──────────────────────────────────────────┬────────────┐
│ ◧             │                                          │          ◨ │
├───────────────┼──────────────────────────────────────────┼────────────┤
│ Navigator     │ Canvas header  Prepare › dataset         │ Inspector  │
│ top to bottom │             [Calibrate Origin] save ▾ ⌂  │ top to     │
│               │ ┌─────────────┐ ┌─────────────┐          │ bottom     │
│ workspaces    │ │ Diffraction │ │ Real space  │          │            │
│ dataset       │ └─────────────┘ └─────────────┘          │ Settings   │
│ session       ├─ infobar  status · progress · glance · ◫ ┤   Info     │
│               │ Process area   Output · Run · Lineage    │ sections   │
│               │                                          │            │
│ filter        │                                          │            │
└───────────────┴──────────────────────────────────────────┴────────────┘
```

The navigator and the inspector run from the toolbar to the window's
bottom edge and never change; each toggles from its own toolbar button.
The **infobar is the divider** of the centre column: drag it anywhere on
its width from the column's bottom edge (process area hidden) to its top
edge (canvas hidden — Xcode's two extremes, the owner's screenshots of
2026-09-22 00:28–00:35); its right-hand button toggles the process area.

**Window.** Three full-height columns under one toolbar. The inspector is
`.inspector` on the `NavigationSplitView` itself (allowed by ADR 009: still
SwiftUI, still no split views), so it reaches the top and ⌥⌘0 removes it
entirely. The toolbar keeps only window-level items: sidebar toggle, the
dataset switcher, the inspector toggle, a global "run" indicator while busy.

**Canvas header (per workspace).** A jump-bar-style row over the science
panes: *workspace › dataset* on the left; on the right the room's **one
primary action** (blue), *Save to Session*, *Reveal in Finder*. Actions
about the work sit over the work. This is where the blue button goes.

**Navigator.** Unchanged in content (workspaces, dataset, session), but
the workspace list is the pipeline: each row shows its state glyph (not
started · computed · stale · refused), and the session list is the
lineage's first surface.

**Inspector = Xcode's inspector, one style everywhere** (owner,
2026-09-22). Header: a text segmented control — Settings · Info — in its
own row. Body: one top-level `Form` styled `.columns`: bold section
headers, right-aligned labels in a fixed leading column, controls in the
trailing column, a hairline between sections, regular control size, 13-pt
text. That is the native SwiftUI form of Xcode's Identity-and-Type panel;
the 2026-09-21 trial failed by nesting it inside a `.grouped` form. A
**step section** shows its number, name, state ("Not set" / "From file ·
49.5 nm/px") and its one action button on the section's first row;
manual fields live in the section they belong to; a readiness row at the
top ("Quantitative in 2 of 6 steps") replaces the orange paragraph;
buttons never share a row; a section header is one full-width button.

**Rooms read as workflows.** Prepare = 1 Origin & probe · 2 Ellipse ·
3 R–Q rotation · 4 Q scale · 5 R scale · 6 Voltage, in that order, each a
card with its state and verb; manual fields appear inside the card they
belong to. Bragg disks = 1 Probe kernel · 2 Detector · 3 Detect, then
Display and Advanced. The same shape in every room: the primary action in
the header is always the next step's verb.

**Bottom area = Xcode's debug area, exactly.** The infobar is the
divider and the grab handle across its whole width; its height is fixed;
the process area's height is the dragged fraction of the centre column,
from 0 (hidden) to 1 (the canvas gone); ⌃⌘L and the bar's right-hand
button toggle between hidden and the last dragged height. Inside the
process area: Output · Run · Lineage as its utility tabs, with Run's live
numbers (ADR 034); switching a tab never moves the bar.

**What stays as decided.** SwiftUI only, `LayoutPolicy` for every fixed
point, `AppState` gains no state, live numbers on `OperationCenter`
(ADR 034), the Unvalidated badge, every accessibility id.

## 5. Sequence, driven at every step

- **Phase 1 — window anatomy, nothing else** (in build 2026-09-22):
  `.inspector` on the `NavigationSplitView`, toggled from the toolbar's
  trailing button; the navigator's toggle at the leading edge; the canvas
  header with the primary action, Save to Session and Reveal, so the
  toolbar carries no room action; the infobar as the centre column's
  divider from bottom edge to top edge; the process area's height
  independent of its tab. The owner drives.
- **Phase 2 — the Prepare reference room** as cards with the readiness
  row. Driven and accepted before any other room changes.
- **Phase 3 — the other rooms**, one per session, each driven.
- **Phase 4 — the bottom area's second workspace** (products, then the
  lineage graph after the record exists).

Cost is counted in points before each phase, as the rules require, and
each phase is mocked as a picture the owner can reject before code.

## 6. Decided by the owner, 2026-09-22

1. One style everywhere, Xcode's inspector: a top-level `.columns` form
   (see §4). Yes, it is plain SwiftUI.
2. The primary action, Save to Session and Reveal in the canvas header.
3. The inspector header is text: Settings · Info.
4. Withdrawn (the width follows from the form).
5. The bottom area is Xcode's debug area: the infobar is the divider and
   the toggle, draggable over the whole centre column.
6. Withdrawn; the `.columns` form replaces the 2026-09-21 vocabulary in
   phase 2.

The 2026-09-22 00:15 wireframe drew the status strip across the full
window width under the sidebar and the inspector — wrong; the owner's
red-box screenshot (00:28) is the anatomy of record.
