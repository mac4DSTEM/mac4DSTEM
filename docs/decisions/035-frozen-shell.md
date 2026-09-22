# 035 — The shell is frozen; the width budget is the ideal columns; the toolbar draws no title

Dates: 2026-09-22

Status: live

## Decision

The window shell — `UI/ContentView.swift`, `UI/WorkspaceView.swift`,
`UI/WorkspaceInspector.swift`, `UI/LayoutPolicy.swift` and
`App/WorkspaceNavigation.swift` — is frozen (owner, 2026-09-22, approving
item 1 of [`archive/v3/ui-review-2026-09-22.md`](../archive/v3/ui-review-2026-09-22.md)):
it changes only against a picture the owner has accepted, and every other
UI session is a room, Prepare first. Three corrections landed with the
freeze, all from the first on-screen look at phase 1:

1. **The width budget is a function of the window width alone, summed at
   the columns' IDEAL widths** (915 pt with both panels, 683 without the
   navigator) — and it is a request, not a mutation. `WorkspaceNavigation`
   keeps intent (`showToolsPane`, `showInspectorPane`) apart from what fits
   (`navigatorFits`, `inspectorFits`) and derives what is shown
   (`navigatorIsVisible`, `inspectorIsVisible`). A panel a narrow window
   closed returns by itself when the window widens; the toolbar toggles and
   the View-menu items are enabled by the same `fits`.
2. **The toolbar draws no title** (`.toolbar(removing: .title)`, macOS 26+;
   the toolbar is declared on the detail column, which is what keeps the
   dataset menu and the inspector toggle at the trailing edge once the title
   is gone — on the split view they moved to the leading edge, spacer or
   not). The window keeps the dataset's name as its title for the Window
   menu and accessibility; the centre header's breadcrumb is the one place
   the room and the dataset are named.
3. **The infobar shows the row-resize pointer and drags in global
   coordinates** (a local-space drag on a bar that moves with the pointer
   reached 0.51 of the column for a full pull, measured twice), **the canvas
   stays in the hierarchy at fraction 1, and the inspector header is a
   segmented `Picker` in a row of its own**, not a `TabView`. The pane
   divider's drag takes the same coordinate space.

**Amended 2026-09-22 night:** the width budget is no longer a runtime
maximum — the window floor is now derived and fixed:
`LayoutPolicy.datasetWindowMinimumSize.width` = sidebar ideal 230 +
inspector ideal 320 + 2×2 dividers + two 180-pt image panes + 1 = 915 (was
640). `WindowAnatomyPolicy` (`collapseInspector`/`collapseNavigator`,
`navigatorFits`, `inspectorFits`, `availableWindowWidth`) and ContentView's
width-reporting plumbing are deleted; Show/Hide Tools/Inspector are never
disabled by width. Driven: System Events asked for 800 pt, the window held
915; Prepare rows did not wrap there.
`NavigationSeamTests.testDatasetWindowMinimumWidthCoversTheIdealColumnsAndBothSciencePanes`
replaces the four retired-policy tests, red at 640 before the change, green
on the derived value.

## Why

Four shell rebuilds in three weeks (09-03, 09-04, 09-21, 09-22), each landed
unseen and reviewed days later by the owner alone. The maxima-based budget
hid the inspector on an 1100-pt window and greyed its toggle, and because
the collapse overwrote the intent, widening to 1280 did not bring it back.
The `TabView` and the doubled title were two of the eight 2026-09-21
findings.

## Governs

The five files above; `LayoutPolicy.datasetWindowMinimumSize`
(`WindowAnatomyPolicy` retired 2026-09-22 night); `NavigationSeamTests`
(four tests, each red under one mutation); `CLAUDE.md` "Frozen shell".

## Sources

- `docs/archive/v3/ui-review-2026-09-22.md` §2, §4, §5
- `docs/window-design.md` §1, §5 (phase 1)
