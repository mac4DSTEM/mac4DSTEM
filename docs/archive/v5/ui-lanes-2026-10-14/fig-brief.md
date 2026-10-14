# Lane FIG brief — talk-quality figure export (mac4DSTEM, tier 2, 2026-10-14)
REPO = /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM (you WORK here, on main; commit by explicit paths; never push, never branch).
SP   = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
Your lane dir (logs, notes, report): $SP/lanes/FIG/.

Why (the owner, 2026-10-14; suite ROADMAP.md "What blocks the study", item 2): his talk needs figures straight out of the app.
Build, in mac4DSTEM:
1. Apertures drawn on the exported mean diffraction pattern (the virtual detectors the user placed — BF disc, ADF annulus, etc. —
   as outlines, the same geometry the app draws on screen).
2. The EDX region box (the drawn region(s)) on exported EDX maps, as on screen.
3. A multi-panel figure: several of the current images (e.g. HAADF/virtual image, mean pattern with apertures, EDX maps) in one
   exported image, each panel labelled, each with its scale bar where the app already has one.
4. High-DPI output: an export scale (e.g. 1x/2x/3x pixels, or vector PDF if the existing rendering path allows it cheaply).

Read first: $REPO/CLAUDE.md and ../CLAUDE.md ("Rigour follows risk": you are TIER 2 — behaviour without numbers: tests that fail
when the code is broken, checked by sampling 2-3 mutations; one refuter later; no pre-registration; "Build on, drive when needed";
"Wait on events, not loops"), $REPO/docs/status.md, $REPO/docs/architecture.md (where files go), the existing export code
($REPO/mac4DSTEM/Support/ResultExport.swift, ResultExport+Rendering.swift, ProductDataExport.swift, UI/ResultsWorkspace.swift,
UI/Spectroscopy/MapRasters.swift, UI/MapSettings.swift — find the rest: the scale-bar export, the Export menu/commands, how
apertures and EDX regions are drawn on screen). Owner preferences (memory files, read them):
/Users/paullobpreis/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/memory/{owner-design-standards,inspector-hig-recipe,lean-app-directive,number-entry-locale-trap,swiftui-macos-accessibilitylabel-appends,never-build-under-running-app}.md

Rules:
- Nothing in Core/ (no scientific number moves). Rendering goes where the existing export rendering lives (Support/), UI in UI/.
- Frozen shell: do NOT edit UI/ContentView.swift, UI/WorkspaceView.swift, UI/WorkspaceInspector.swift, UI/LayoutPolicy.swift,
  App/WorkspaceNavigation.swift. Put new controls in the existing export path (menu/sheet), small and conventional.
- Reuse the on-screen geometry and scale-bar code; one implementation, not a parallel copy. Lean: no option the talk does not need.
- AppState: add no stored state unless no other home would do; say why in the commit.
- Tests: unit tests that render the export into pixels and check them (aperture outline pixels where the geometry says, the region
  box where the region is, panel count/layout and labels, pixel size at 2x/3x). Break each new test once by a mutation in the
  code it guards (sample 2-3) and record red → green.
- Gates: `tools/run-tests.sh unit` ONLY through `$SP/heavy.sh <log> $REPO/tools/run-tests.sh unit` (it takes a build slot and waits
  while a `drive` or a macTEM `unit-*` lock exists; exit in <log>.exit), plus `tools/run-tests.sh core` and `inventory` (not
  through heavy.sh is fine for inventory). Read exits from files, never through a pipe. Run long commands with run_in_background
  and wait for the notification; no sleep/poll loops. Count passed/failed/skipped by name against `grep -rh 'func test'
  mac4DSTEMTests | wc -l` (2236 before you; 4 or 5 skips depending on the owner's recents).
- Commit at each green checkpoint, by explicit paths (another session commits docs/archive files in the same tree — never
  `git add -A` or `.`), messages naming tier 2 and the gate numbers, ending with the line
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not edit docs/status.md, docs/open-items.md, CLAUDE.md, ROADMAP.md:
  put the rows you would add in your report; the coordinator writes them.
- Do NOT drive the app and do not launch it. When the features are built and the gates green, STOP and report: a scratch-build
  command (a scratch -derivedDataPath under $SP/lanes/FIG/), and a drive plan — per feature, what to open (the demo data or a
  file under References/), what to click, what the exported file must show — so a guarded drive can be done in one block later.
Report $SP/lanes/FIG/report.md (what was built where, tests and their mutations, gate logs and totals, commits, the drive plan, the
"Unverified on screen" items, what you did not do). Final message <= 25 lines with the commits, gate totals and the report path.
