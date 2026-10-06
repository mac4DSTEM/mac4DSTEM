# Lane H: two pictures of the frozen shell (owner decision, ADR 035 / ux-spec-2 §4 items 1 and 2)

Open both HTML files in a browser at 1470 x 923 (dark appearance, CSS-only glass). They are mocks built from the code's structure, not screenshots of the app.

**A: mock-A-glass-shell.html. Glass shell, today's widths.** Sidebar 230, inspector 320 (the code's ideal widths; the brief said 220 but `LayoutPolicy.sidebarWidth.ideal` is 230). Glass (blur, translucency, 1-px rim) on the toolbar, the sidebar and the inspector background; the centre column and the maps stay flat. Periodic table cells are about 15 px, symbols 9 pt: readable, but tight. Centre column 920 px: nothing lost.

**B: mock-B-wide-inspector.html. Same glass, inspector 380.** Cells about 19 px, symbols 9.5 pt, the table reads like the PTE. The centre column drops from 920 to 860 px (60 px, about 6.5 %); the sidebar is unchanged.

**Effort and risk.** Both S. Glass lives in the frozen shell (`WorkspaceView`, `ContentView`, `WorkspaceInspector`), so it needs this picture accepted first; it changes background styling only, no structure and no width. B additionally moves `LayoutPolicy.inspectorWidth.ideal` 320 to 380 (min 280 and max 460 stay). The ideal feeds the derived window floor (`datasetWindowMinimumSize.width` = 230 + 320 + 4 + 361 = 915 becomes 975), so `NavigationSeamTests.testDatasetWindowMinimumWidthCoversTheIdealColumnsAndBothSciencePanes` and the `InspectorWidthBudgetTests` change with it; a saved inspector width stays valid. Risk of B: the window floor rises 60 pt, so a 915-pt window is no longer reachable. Risk of A: none beyond Reduce Transparency, which frosts the glass.

**Recommendation.** A now: it answers the owner's glass bullet at zero layout cost, and the periodic table already scales by drag (max 460) for anyone who wants cells larger. Take B only if the owner finds 15 px cells too small in a real window; the width is a one-constant change later.

**Second opinion (against).** The table is the room's main control, and an inspector that needs a drag to be comfortable on first open is the wrong default; B's 60 px comes out of a centre column that is already 920 px wide, a cost few will notice, and raising the floor to 975 costs nothing on a 1470-px display.
