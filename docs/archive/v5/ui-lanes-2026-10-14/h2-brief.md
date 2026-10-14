# Lane H2 brief — app and safety (UI audit 2026-10-14)
SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
Read $SP/lanes/UI-COMMON.md first (rules for all UI lanes), then the audit /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/docs/archive/v5/mac4dstem-ui-audit-2026-10-14.md
(Summary items 3-4, the "Shell and app" and cross-cutting tables, "The five older findings") and its JSON beside it.
Build (the owner asked for these, 2026-10-14), tier 2 unless stated:
A. Safety: undo, or a confirmation when work exists, for Import Labels, the Al-Mg-Si preset and the phase minus button.
B. InspectorWarning (InspectorRows.swift ~593) colours only the symbol; route the non-frozen hand-rolled warning sites through it
   (skip sites in lane H1's files — ImagePanes, ImagingSettings, PrepareSettings, ZoomPan, HistogramView — until H1 commits; list them).
C. Reduce Motion in InspectorRows (the section animation, ~163).
D. The 2026-10-13 findings: AppState built lazily per window (mac4DSTEMApp.swift:66, AppState.swift:364 — tier 3 if output is
   identical; this touches AppState: say what responsibility moves out or why none would); the object table rows cached
   (PrecipitateObjectsWindow.swift:29); the cancellation sibling (SpectroscopyRoomController.swift:443) — VERIFY it is a defect
   with a reproducing observation before fixing, else record it as not reproduced; replace the two fixed-sleep tests
   (SessionGatesTests.swift:180, ReviewOwnerCardsTests.swift:137) with waits on events.
E. The object table: right-aligned numbers, a dataset-named CSV, write errors surfaced, Copy.
F. Menus (App/mac4DSTEMApp.swift is YOURS, but only AFTER lane FIG commits — it has uncommitted edits there now; the session will
   message you): File > Open Recent, Open with Options…, Show in Finder, Cmd-. for Cancel, drop-to-open; and lane H1's one-line
   View-menu hookup when H1 sends it.
G. The six frozen-shell fixes the owner ACCEPTED WITHOUT A PICTURE (2026-10-14, relayed by the suite coordinator and confirmed in
   the session's chat; presentation only — no structure or width change). Record that in the commit message exactly so, citing
   ADR 035/050:
   1. WorkspaceInspector, the four warning sites (lines ~227, 826, 881, 1026): colour only the glyph, through InspectorWarning.
   2. Inspector shortcut: one visible key, the same in the menu and on the button: Opt-Cmd-I (HIG); drop the hidden Opt-Cmd-0.
   3. ContentView toolbar: a fixed ToolbarSpacer between the text verb and the icon group.
   4. WorkspaceView dividers (~925, ~737): accessibilityAdjustableAction and a keyboard route.
   5. WorkspaceView Welcome: cut the marketing copy down to the doors.
   6. WorkspaceInspector captions (~411, ~883): .secondary and larger.
Order: D (tests first), C, B, A, E, G, then F after FIG's commit. Do not touch lane FIG's files (its uncommitted ones in git status:
Support/ResultExport*.swift, FigureExport*.swift, FigureRendering.swift, UI/FigureExportSection.swift, PaneOverlays.swift,
ResultsSettings.swift, ResultsWorkspace.swift, SettingsWindow.swift, UI/Spectroscopy/*, App/mac4DSTEMApp.swift,
Session/AppPreferences.swift and their tests) until the session says FIG has committed. Commit at each green checkpoint.
