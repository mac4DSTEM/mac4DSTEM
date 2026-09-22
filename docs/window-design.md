# Window design — the reset (2026-09-22)

**Status: decided 2026-09-22 (§6); phase 1 committed (`b0cf8e0`) and corrected the same day after its first on-screen look (ADR 035, [`archive/v3/ui-review-2026-09-22.md`](archive/v3/ui-review-2026-09-22.md)); the shell is frozen; owner drive owed.** The owner said on 2026-09-22 that he wants further changes; details and acceptance are pending. Written after the owner drove the
2026-09-21 restyle (`9fd386d`) and rejected it: "cramped, no logic to the
panes, no workflow behind it". The findings are in `open-items.md` (Owner
drive 2026-09-21). This file says what the window is for, what the two
reference apps do, what today's window gets wrong structurally, and the
anatomy proposed instead. It is a design doc, not a truth doc.

## 1. The owner's brief (2026-09-22) — read this first

mac4DSTEM is a scientifically useful 4D-STEM app: load a cube, calibrate,
detect disks, map strain and orientation, identify phases, export what a
paper can cite, every step reproducible from the session sidecar. The
window's job is to make the pipeline's state legible and the next step
obvious. Its anatomy is **Xcode's**, in **plain, robust macOS**, on any
Mac a microscopist owns.

**Anatomy.** One toolbar. Three columns. Left, the navigator — workspaces
as pipeline steps with their state, the dataset, the session — from the
toolbar to the window's bottom edge, toggled by the toolbar's leading
button. Right, the inspector — Settings · Info — from the toolbar to the
bottom edge, toggled by the toolbar's trailing button. Both collapse
completely and the window remembers them. The toolbar carries only
window-level controls: the two panel toggles, dataset switcher and global
run indicator while busy. The centre column has a header row (workspace ›
dataset pinned left; the one blue primary action, Save to Session and Reveal
grouped at the right), the science panes, the **infobar**, and the process area.
In every combination of open and closed side panels, that header remains
inside the centre column:
the space between the breadcrumb and actions grows or shrinks with the centre
column. The actions never migrate into a side panel or the toolbar. The
infobar is the divider: one fixed-height line (status, progress, memory glance, the
toggle at its right end), draggable over its whole width from the
column's bottom edge (process area hidden) to its top edge (panes gone);
⌃⌘L toggles it. Switching a tab in the process area (Output · Run ·
Lineage) never moves the bar.

**Inspector.** One style everywhere, Xcode's: a single top-level
columns-style form — bold section headers, right-aligned labels in a
fixed column, controls to the right, a hairline between sections, regular
control size, 13-pt text. A section header toggles from anywhere on its
row. A button never shares a row and never truncates. A step section
shows its number, name, state and its one action; manual fields live in
the section they belong to; readiness is one row, never a paragraph.

**Rooms are workflows.** Each workspace's inspector reads as ordered
steps; the header's blue verb is always the next step; the navigator
shows each step's state.

**Robust for many users on many machines.** A 13-inch MacBook Air at the
microscope and a 27-inch display at the desk must both work: at the
default 13-inch window all three columns fit with the science panes at
their scientific minimum, and below that the side panels collapse before
a pane ever shrinks past it. No number is fixed outside `LayoutPolicy`;
nothing scrolls sideways; nothing truncates; light and dark, Increase
Contrast and Reduce Motion all render correctly; a state (loading,
streaming, refused, stale) is drawn, never assumed; status is never
colour alone — glyph and text too. Numbers parse and print in the user's
locale (a German user types 49,5). Trackpad and mouse both drag the
infobar; every action is reachable from a menu and a shortcut; every
control keeps its accessibility identifier and label. The UI never waits
on the data: live numbers arrive by observation from `OperationCenter`,
the glance ticks at 2 s, the log is capped, big cubes stream, and the
memory figure is on screen so a user on an 8 GB Mac sees why a run is
slow. Window state (panels, infobar position) restores per window.

**Native only.** SwiftUI: `NavigationSplitView`, `.inspector` on the
split view, the standard toolbar, standard controls at standard sizes,
system fonts and colours. No custom chrome, no AppKit in `UI/`, no
split-view classes (ADR 009). When SwiftUI cannot do something in this
brief, that is a decision for the owner, never a hack.

**Process.** One phase at a time. Each phase is drawn as a picture the
owner can reject, costed in points, built, driven by him, and only then
followed by the next. Prepare is the reference room; no other room
changes until he has accepted it. A change he rejects is reverted, not
patched.

**Frozen shell** (owner, 2026-09-22, ADR 035). `ContentView`,
`WorkspaceView`, `WorkspaceInspector`, `LayoutPolicy` and
`WorkspaceNavigation` change only against a picture he has accepted. The
side panels' width budget is the window width against the columns' ideal
widths (915 pt with both panels), kept apart from the user's intent so a
panel a narrow window closed returns when the window widens; the toolbar
draws no title; the infobar carries the resize pointer.

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
│ top to bottom │       [Calibrate Origin] Save   Reveal   │ top to     │
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
panes: *workspace › dataset* pinned left; the room's **one primary action**
(blue), *Save to Session* and *Reveal in Finder* grouped at the right. As
the left or right panel toggles, the centre grows or shrinks and the space
between these groups changes; the actions stay in the centre header at every
width. Actions about the work sit over the work. This is where the blue
button goes.

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

- **Phase 1 — window anatomy, nothing else** (`b0cf8e0`; seen on screen by
  the agent 2026-09-22 at 1100/1280/1470 pt and corrected — the width budget,
  the doubled title, the infobar pointer, the canvas teardown at fraction 1,
  the inspector `TabView`; ADR 035; **driven by the owner that evening and
  accepted in substance** — the toolbar's content is his parked decision, §6.7):
  `.inspector` on the `NavigationSplitView`, toggled from the toolbar's
  trailing button; the navigator's toggle at the leading edge; the canvas
  header with the primary action, Save to Session and Reveal, so the
  toolbar carries no room action; the infobar as the centre column's
  divider from bottom edge to top edge; the process area's height
  independent of its tab. The owner drives.
- **Phase 1b — the toolbar carries the room** (ADR 036, built 2026-09-22
  evening on his answer to the mock; corrected once on his own build the
  same hour — the inspector's toggle is the only item over the inspector).
- **Phase 2 — the Prepare reference room** as Pixelmator's cards (his
  choice, 2026-09-22 evening, over the columns form) with the readiness
  row: **built 2026-09-22 evening (ADR 037), owner drive owed.** Driven and
  accepted before any other room changes.
- **The same night, on his drive of the evening's builds (§9):** the
  inspector's tabs as icons in its own row, the infobar at 34 pt carrying
  the live run, the process area as Output · Lineage side by side with the
  Run tab folded into the bar, Prepare rebuilt as `GroupBox` cards (the
  grouped form rejected on sight), the Settings window's sidebar toggle
  removed. Owner drive owed.
- **Phase 3 — the other rooms**, one per session, each driven.
- **Phase 4 — the bottom area's second workspace** (products, then the
  lineage graph after the record exists).

Cost is counted in points before each phase, as the rules require, and
each phase is mocked as a picture the owner can reject before code.

## 6. Decided by the owner, 2026-09-22

1. One style everywhere, Xcode's inspector: a top-level `.columns` form
   (see §4). Yes, it is plain SwiftUI.
2. ~~The primary action, Save to Session and Reveal in the canvas header.~~
   **Superseded the same evening (ADR 036):** the toolbar carries them —
   the file and the live run as a display in the centre; the run button,
   Save, Reveal and the dataset menu over the room at its right; only the
   inspector's toggle over the inspector; the canvas header row is gone.
3. The inspector header is text: Settings · Info. — superseded the same
   night: icons in the inspector's own first row (§9.1).
4. Withdrawn (the width follows from the form).
5. The bottom area is Xcode's debug area: the infobar is the divider and
   the toggle, draggable over the whole centre column.
6. Withdrawn; the `.columns` form replaces the 2026-09-21 vocabulary in
   phase 2.
7. **Decided, later the same evening (ADR 036):** the toolbar carries the
   room — the file and the live run as a display in the centre; over the
   room, right of it, the run button (Stop while busy), then Save / Reveal /
   dataset menu as icons; only the inspector's toggle over the inspector;
   the breadcrumb row removed; the infobar 28 pt. Built and driven on his
   own build the same hour, corrected three times on his word.
8. **Decided (2026-09-22 evening): the inspector is Pixelmator's cards** — a
   grouped form, one card per step with a title row (number, name, state,
   action) and rows beneath; Prepare first. Supersedes §6.1's columns form.
   Built the same evening (ADR 037): cards do not collapse, Advanced is a
   disclosure row inside its card. Rebuilt as `GroupBox` cards the same
   night after the grouped form was rejected (§9.4).

The 2026-09-22 00:15 wireframe drew the status strip across the full
window width under the sidebar and the inspector — wrong; the owner's
red-box screenshot (00:28) is the anatomy of record.

## 8. The owner's vision by area — 2026-09-22 evening (his words in substance; not decided)

Said after the phase-1 drive, with UI decisions parked for the session:
"open for discussion", "we will see". Numbered by the labelled dummy of
the window (1 toolbar · 2 navigator · 3 centre header · 4/5 science panes
· 6 infobar · 7 process area · 8 inspector). Reference screenshots he
sent: Xcode's window (the toolbar and its wide debug bar), the app as it
is, and Pixelmator's Color Adjustments panel as "a cleaner example" for
the inspector.

1. **Toolbar** — "maybe" the dataset's name, the current process button,
   Save to Session and Reveal in Finder, as buttons that are always there:
   with both side panels toggled away and the data at full size, the
   analysis can still be run from the process button.
2. **Navigator** — as it is (workspaces, dataset, session); the design
   could be more macOS, more basic, better looking — "Liquid Glass
   maybe!?"
3. **Centre header** — "maybe" the process and the step we are at, or
   something else; not sure yet.
4. / 5. **Science panes** — good so far.
6. **Infobar** — good; should be wider, like Xcode's debug bar.
7. **Process area** — a new space to fill with useful information: Output
   makes sense; Lineage should become a graph view; how the sub-spaces
   toggle is open — maybe only two (Output and the graph), with the option
   of side by side like Xcode's console and variables.
8. **Inspector** — good so far but needs a UI/UX rework: the fonts are too
   small, it does not look like a good macOS app, the workflows are not
   considered, the design is not optimal; Pixelmator's panel as the cleaner
   example; still to discuss.

If adopted, 1 reverses §6.2 and §1's "the toolbar carries only
window-level controls" (the mock of 2026-09-22 draws it Xcode's way: run
or stop at the left, the file name or the live run as a display in the
centre, the actions and toggles at the right, the breadcrumb row gone); 7
changes ADR 034's three tabs; "Liquid Glass" is a macOS 26 material
(`glassEffect`) on a 14 floor, so a refinement behind `#available`, and
his decision; the infobar's height is a `LayoutPolicy` number (22 pt today;
Xcode's bar is about 28). Nothing decided; nothing built; the shell stays
frozen (ADR 035).

## 9. His drive of the evening's builds — 2026-09-22, late (his words in substance)

Driven on his own Xcode build of `9bac67d`, demo fixture, dark, with crops
of the toolbar, the process area's three tabs and the Prepare cards.

1. **Toolbar / inspector header.** "Settings and Info jump to the left of
   the toggle button — doesn't make sense, looks bad. Make it clean; if
   there is a standard Mac way you are more comfortable with, do it
   instead, maybe like in Xcode." → Xcode's anatomy: only the toggle in
   the toolbar over the inspector; the inspector's tabs in its own first
   row (icons that night; text in glass since §9.6).
2. **Infobar.** "Still very thin — I told you to make it wider. Apart from
   that the movement and the toggle work well."
3. **Process area.** "See what happens when I change Output to Run and then
   to Lineage — very bad visually" (the tab bar moved with the tab: the Run
   tab's content did not fill the pane, so the stack centred it). "Put the
   info from the Run tab into the infobar itself — much more useful, and it
   has the width now; maybe some logos (icons) if it makes sense. Then the
   lower panel has two things, Output and Lineage; toggle them left and
   right like Xcode's debug area (his two screenshots of Xcode's bar-end
   buttons). Lineage should become a graph view of some sort — open to
   discuss the details."
4. **Prepare.** "Looks like shit. Do you think Pixelmator's panes look and
   behave like this? Even the previous version, which the other rooms still
   have, was better. Is there no standard macOS SwiftUI way?" → the grouped
   form is the Settings look, not a card; the native card is `GroupBox`,
   title row inside, 13-pt text.

Then: "note my wishes in the docs and start implementing; ask when
something is unclear, in simple English; implement it all now." Assumptions
taken without asking: the infobar shows the live run (bar, done/total,
rate, ETA, Stop) while busy and the last run while idle, with the engine
beside the memory glance; hiding the last process pane closes the area and
opening the area with none shown shows Output; the lineage graph is a chain
of the recorded steps until the record carries input edges (ROADMAP).

5. **Settings window** (added later that night): "no need to toggle
anything there — leave the left categories standing, maybe a search bar
on top; standard macOS." → the sidebar toggle removed; the search field
is optional, later.

6. **His drive of `03cfa10`** (2026-09-22 afternoon, his own build,
`datasetA_stride3.h5`, 171 × 171 streaming, live origin calibration and
disk detection in the infobar): "much better now! good work." Three small
things, then "consolidate this state — a step forward in the skeleton;
fix the few small things and we discuss later how to make further
progress": (a) "cancel button is not stop, is there a reason?" — asked
back: the buttons say Stop, the status says "Cancelling…"; whether he
means the word or that a run did not stop is not yet answered; (b) Settings
· Info "only icons — I prefer them to be text and in Liquid Glass" →
built the same day: text tabs as the standard glass buttons in one
`GlassEffectContainer` (macOS 26; a text segmented picker before that);
(c) **"everywhere in the app should be Liquid Glass where it fits"** —
a standing wish for the discussion, not built: on macOS 26 the toolbar,
sidebar and menus are glass by themselves; Apple's guidance keeps glass
to the control layer floating over content (toolbars, overlays such as the
canvas legends and scale bars, floating buttons), never on content, cards
or text, and never glass on glass. Candidates and costs come to him as a
picture before any code (ADR 035).
Then, on the text tabs: "it is better now." And (d) **"the Prepare panel
still looks different from the rest — make it look like the other panels,
make everything the same, then improve from there"** → Prepare returned to
the rooms' `InspectorRows` kit the same day (ADR 037 reversed); every
improvement to a room's look is a kit change from here on. (e) "Next I
want to consolidate the app — provide a prompt to review everything" → §10.
His next look, at launch with no dataset: (f) **"the right panel looks
weird"** — the tab row sat mid-column: the no-dataset placeholder does
not fill the column and the unpinned stack centred it (the Run-tab
mechanism again; never captured because every agent capture used the
demo fixture) → the column is pinned to the top and the launch state is
in the capture set. (g) **"Settings and Info is still not Liquid Glass as
I asked — it should look like in the screenshot from Xcode, but with
text"** (his crop: Xcode's inspector tab bar, one capsule, the current
segment a lighter pill) → one glass capsule spanning the row, text
segments, the current one a lighter pill. (h) "Is everything in the
background wired correctly? We really need to polish this — the next
release is around the corner and this still looks bad." → the review of
§10, in its own session, before any more UI.

## 10. Prompt: the consolidation review (owner, 2026-09-22 afternoon)

> You are reviewing mac4DSTEM whole, on `main`, for consolidation — not
> building. The owner's words: "consolidate the app; review everything."
> Read `CLAUDE.md`, `docs/status.md`, `docs/open-items.md`,
> `docs/architecture.md`, then this file §1, §6 and §9, then ADR 034–037.
> Rules that bind you: `main` only, never a branch, never a push; the
> frozen shell (ADR 035); no new on-screen surface; Gate D is not yours —
> a scientific number you doubt is a finding, never a fix; nothing is
> "seen" unless you captured it (the marked-instance recipe in
> `docs/archive/v3/ui-review-2026-09-22.md`), and every claim names its
> evidence. Review in this order, one section of findings each:
>
> 1. **The window.** Every room (Prepare, Imaging, Strain & ACOM and its
>    three children, Phase, AI Analysis, Results) × Settings and Info, in
>    every panel state, dark and light, at 1100 and 1470 pt, on the demo
>    fixture and one real cube. Score each capture against §1 and the
>    Xcode/Pixelmator references in §2: one kit, one alignment per panel,
>    no truncated control, no control that does nothing, no text under
>    13 pt in the inspector, nothing that moves when it should not.
> 2. **The UI code.** `UI/` and `App/`: what the four shell rebuilds left
>    behind — dead types, duplicated kits (`InspectorRows` is the one
>    vocabulary; anything beside it is a finding), `@SceneStorage` and
>    `@AppStorage` keys with no owner, sync sites between
>    `WorkspaceNavigation` and views, AppKit or split-view classes,
>    constants outside `LayoutPolicy`, availability guards that hide a
>    macOS 14 path nobody has run.
> 3. **The tests.** Which UI tests assert a constant rather than a
>    behaviour; which would stay green if the view were deleted; which
>    gates can fail silently. Count declarations against the log by the
>    outcome suffix.
> 4. **The docs.** Contradictions between `status.md`, `window-design.md`,
>    the ADRs and `open-items.md`; items over 12 lines; narrative that
>    belongs in `docs/archive/`; the handoff's word count; what a new
>    reader would read twice.
> 5. **The science boundary.** Any UI change since `6132ff1` that could
>    move a number (a default, a threshold, a format that rounds) — name
>    it for Gate D, do not touch it.
>
> Output: `docs/archive/v3/consolidation-review-<date>.md` — findings
> ranked, each ≤ 12 lines in the `open-items.md` format (what is wrong,
> the evidence, the trap, the owner, the residual), the captures beside
> it; then a consolidation plan of at most ten steps, each costed in hours
> and in what it deletes, for the owner to accept or strike. Change no
> code except deletions of code you have proven dead, each with the
> three gates in the commit message. Land the review with `status.md` and
> `open-items.md` updated in the same commit, net negative markdown or
> say why.
