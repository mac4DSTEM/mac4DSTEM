# Common rules for the UI lanes (FIG, H1, H2), mac4DSTEM, 2026-10-14
REPO = /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM — you edit the working tree on main. THREE lanes and the
coordinating session work in this one tree at once:
- Commit ONLY your own files, by explicit paths (`git commit -- <paths>`); never `git add -A`/`.`, never stash, reset, checkout or
  revert anything you did not write. If a file you need is modified by another lane (git status shows it and you did not edit it),
  do not touch it; wait for that lane's commit (the session will message you) or work around it.
- Gate exactly what you commit: make an isolated copy with `$SP/gate-copy.sh <name> <repo-relative files...>` (HEAD + the listed
  working-tree files, References symlinked, directory named mac4DSTEM) and run there:
  `TMPDIR=$SP/gates/<name>/tmp $SP/heavy.sh <log> $SP/gates/<name>/mac4DSTEM/tools/run-tests.sh unit` (heavy.sh holds the ONE
  test host machine-wide: it waits on `drive` and every `unit-*` lock and holds its own), then `core` and `inventory` in the copy
  (`$SP/heavy-build.sh <log> ...` is fine for those). Read exits from <log>.exit, never through a pipe. Run gates with
  run_in_background and wait for the notification; no sleep/poll loops. Delete the copy's tmp/DerivedData and .build after.
- Count tests by name: passed + failed + skipped = `grep -rh 'func test' mac4DSTEMTests | wc -l` in the copy (4 or 5 skips are
  normal: one test depends on the owner's recents).
- Tiers (../CLAUDE.md "Rigour follows risk"): name the tier of each item in its commit. Tier 1 (a number a scientist reads can
  move or appears): a short registration (what, the predicted check, the test) committed under docs/archive/v5/ BEFORE the code,
  every new test broken once by a mutation, a refuter later (the session runs it). Tier 2 (behaviour without numbers): tests that
  fail when the code is broken, 2-3 mutations sampled. Tier 3 (wording, refactors with identical output): review only.
- Frozen shell (UI/ContentView.swift, UI/WorkspaceView.swift, UI/WorkspaceInspector.swift, UI/LayoutPolicy.swift,
  App/WorkspaceNavigation.swift): untouchable EXCEPT the six presentation items the owner accepted for H2 (see H2's brief).
- No AppKit where SwiftUI has it (owner); keep controls few and conventional; read the owner's design memories:
  /Users/paullobpreis/.claude/projects/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/memory/{owner-design-standards,inspector-hig-recipe,lean-app-directive,number-entry-locale-trap,swiftui-macos-accessibilitylabel-appends,sidebar-list-wrap-recipe}.md
  and as documents: the swiftui-macos skill (SKILL.md + references/ under ~/Library/Application Support/Claude/local-agent-mode-sessions/e8cc4cca-236d-4450-b00c-f4c60db989aa/204c51ef-4c9e-41b1-92cc-62b11ca108fd/rpm/plugin_01SDdTApvUzQaB5AhL7VqCHk/skills/swiftui-macos/)
  and ~/xcode-skills/{swiftui-whats-new-27,swiftui-specialist}.
- AppState: new stored state names its owner; a lane touching AppState moves one responsibility out where that makes the app
  better, or says why none would.
- Do NOT launch or drive the app. When built and gated, stop and report a drive plan (per item: what to open, click, see).
- Do NOT edit docs/status.md, docs/open-items.md, CLAUDE.md, ROADMAP.md: put the rows you would add in your report.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Report $SP/lanes/<LANE>/report.md; your final message (<= 25 lines, as text) lists commits, gate totals, what is left.

## Added 2026-10-14 (suite ../CLAUDE.md "UI in every app of the suite", owner)
- SwiftUI and native macOS only. AppKit only where SwiftUI cannot do the job — then name it in the code (a comment saying why)
  and in the commit message. If an item seems to need new AppKit (an NSUndoManager-only route, an NSDocument API, NSSavePanel
  options SwiftUI lacks), first look for the SwiftUI way (`@Environment(\.undoManager)`, `fileExporter`/`fileImporter`,
  `dropDestination`, `commands`/`CommandGroup`, `focusedSceneValue`); use AppKit only if none does the job, and say why.
- Robust and reliable first; great design and UX, not merely correct.
- Design each control with the swiftui-macos skill files, ~/xcode-skills/swiftui-whats-new-27 and the HIG BEFORE code; review it
  against them before you hand back, and list in your report, per control, what you checked. The end-of-session drive checks it on screen.
