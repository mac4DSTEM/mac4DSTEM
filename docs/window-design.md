# Window design — the reset (2026-09-22)

**Status: proposal, owner decisions owed. No UI code lands until the six
questions at the end are answered.** Written after the owner drove the
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
┌ toolbar ───────────────────────────────────────────────────┬──────┐
│ ◧ sidebar   [dataset name ▾]                     ⋯   ⊟ run  │  ◨   │
├──────────┬──────────────────────────────────────────────────┼──────┤
│ Navigator│ Canvas header: Prepare › dataset  [Calibrate ▸] │Inspec│
│ workspace│                                  save · reveal  │ tor  │
│  steps   │ ┌─────────────┐ ┌─────────────┐                 │ ⚙ ⓘ ?│
│ dataset  │ │ Diffraction │ │ Virtual det │                 │ cards│
│ session  │ └─────────────┘ └─────────────┘                 │      │
│          ├──────────────────────────────────────────────────┤      │
│          │ ▤ second area (products · lineage) │ Output Run  │      │
├──────────┴──────────────────────────────────────────────────┴──────┤
│ status · progress                       1.2 GB · resident   ◫  ⌃⌘L │
└────────────────────────────────────────────────────────────────────┘
```

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

**Inspector = a stack of cards (Pixelmator), Xcode's header.** Header: an
icon segmented control — Settings ⚙ · Info ⓘ · Help ? — with its own row
height, then a scroll of cards. A **step card** has a title row: number,
name, state glyph and text ("Not set" / "From file · 49.5 nm/px" /
"Measured 23:51"), a reset control, and on the right the step's **one
action** as a regular bordered button — never three in a row. Its body
uses **one alignment rule**: label left, control right, value at the far
edge; a slider row is label · slider · value; a note is one line under its
row. A **readiness row** at the top of the stack replaces the orange
paragraph: "Quantitative in 2 of 6 steps" with a chevron to the missing
ones. Cards are `GroupBox`es (native), regular control size, 13-pt text,
8-pt rhythm, 12-pt padding. Advanced controls live in a collapsed card at
the bottom of the stack, and a card header is one full-width button —
clicking anywhere on it toggles it.

**Rooms read as workflows.** Prepare = 1 Origin & probe · 2 Ellipse ·
3 R–Q rotation · 4 Q scale · 5 R scale · 6 Voltage, in that order, each a
card with its state and verb; manual fields appear inside the card they
belong to. Bragg disks = 1 Probe kernel · 2 Detector · 3 Detect, then
Display and Advanced. The same shape in every room: the primary action in
the header is always the next step's verb.

**Bottom area (Xcode's debug area).** The whole status strip is the grab
handle: drag anywhere on it to reveal the area; ⌃⌘L toggles it; its height
is the dragged height regardless of what is inside. Inside: a **second
central area** on the left — a product view side by side with the canvas,
the lineage graph when it exists — and the utility tabs **Output · Run**
on the right, Xcode's console-beside-variables split. Run keeps the live
numbers (ADR 034); the strip stays one line.

**What stays as decided.** SwiftUI only, `LayoutPolicy` for every fixed
point, `AppState` gains no state, live numbers on `OperationCenter`
(ADR 034), the Unvalidated badge, every accessibility id.

## 5. Sequence, driven at every step

- **Phase 1 — window anatomy** (small, no vocabulary change): inspector on
  the split view and fully toggleable; the canvas header with the primary
  action, Save to Session and Reveal; the strip as grab handle; the pane
  height bug; regular control size in the inspector. The owner drives.
- **Phase 2 — the Prepare reference room** as cards with the readiness
  row. Driven and accepted before any other room changes.
- **Phase 3 — the other rooms**, one per session, each driven.
- **Phase 4 — the bottom area's second workspace** (products, then the
  lineage graph after the record exists).

Cost is counted in points before each phase, as the rules require, and
each phase is mocked as a picture the owner can reject before code.

## 6. Decisions owed to the owner

1. Cards (Pixelmator) for step and adjustment content, flat sections
   (Xcode) for facts in Info — or one style everywhere?
2. The primary action in the **canvas header** (proposed) or at the
   toolbar's leading edge like Xcode's Run?
3. Inspector header: icon segments ⚙ ⓘ ? (proposed) or text?
4. Inspector default width 320 → 360 pt, so a card's title row never wraps?
5. Bottom area: second workspace **beside** Output/Run (proposed) or
   tabs only, as today?
6. Keep the 2026-09-21 vocabulary and restyle it, or retire it once the
   cards exist? (Proposed: retire; the cards replace it.)
