# Refuter RFIG brief — figure export (tier 2), frozen commits f3ba44e8 + cbf7848a (mac4DSTEM, 2026-10-14)
REPO = /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM (READ-ONLY; other lanes are editing its working tree — read the
committed state with `git show <commit>:<path>` and `git diff f3ba44e8^ cbf7848a`, never the working tree).
SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
Your dir: $SP/lanes/RFIG/ (write only there). Lane FIG's evidence: $SP/lanes/FIG/logs/, $SP/lanes/FIG/probe/.

What is claimed (the lane's hand-back, summarised): the exported diffraction PNG draws the live virtual detector's outline with the
pane's own geometry (ApertureOutline shared with the overlay); every exported EDX map carries the region outline (live dashed + pins);
a multi-panel figure (result, pattern, HAADF, ColorMix, elements; labels; each source's scale bar) exports as PNG, TIFF or one-page
vector PDF through SwiftUI fileExporter; 1x/2x/3x export scale (AppPreferences.exportScale) scales bars and outlines and tags 144/216
ppi; Maps export never overwrites (a new <stem>-maps folder, then "<stem>-maps 2"); 1x output is byte-identical to HEAD for the
existing exports (15 hashes); unit 2277/0/4 = 2281; 13 mutations red; NSSavePanel kept for File-menu exports (no view for fileExporter).

Tier 2 refuter (suite ../CLAUDE.md "Rigour follows risk"; once, on the frozen commits): find what is wrong or would break for the owner
preparing a talk. At least:
1. Geometry: is the outline on the export where the pane draws it (pixel centres, the half-pixel, row/column order, the ellipse
   correction if one is applied, the annulus inner/outer, at 2x/3x)? Check by reading the code and by a small experiment (a Swift
   script or a unit-style harness compiled against the committed sources in a git-archive copy named mac4DSTEM via
   $SP/gate-copy.sh <name> then `git -C $REPO archive cbf7848a` is NOT what gate-copy does — gate-copy archives HEAD; use
   `git -C $REPO archive cbf7848a | tar -x -C <dir>/mac4DSTEM` yourself). Builds through $SP/heavy-build.sh; any xcodebuild test
   through $SP/heavy.sh (one test host machine-wide).
2. Scale bars and units at 2x/3x and in the PDF: does a bar still mean its stated length? Is ppi tagging right?
3. Files: can the Maps export still lose or overwrite data? Name collisions, a folder that exists as a file, write errors surfaced?
4. The byte-identity claim: re-derive at least 3 of the 15 hashes yourself.
5. Tests: sample 2 of the 13 mutations and confirm they go red; find one behaviour the tests do not pin that a user would see.
6. SwiftUI/HIG (as documents: ~/xcode-skills/swiftui-whats-new-27, swiftui-specialist; the swiftui-macos skill under
   ~/Library/Application Support/Claude/local-agent-mode-sessions/e8cc4cca-236d-4450-b00c-f4c60db989aa/204c51ef-4c9e-41b1-92cc-62b11ca108fd/rpm/plugin_01SDdTApvUzQaB5AhL7VqCHk/skills/swiftui-macos/):
   is any new control or the AppKit kept justified?
Verdict: UPHELD / UPHELD WITH CORRECTIONS / REFUTED, with must-fix items (file:line) separated from notes. No app launch, no drive.
Write $SP/lanes/RFIG/report.md (predictions before each experiment). Final message as text, <= 25 lines.
