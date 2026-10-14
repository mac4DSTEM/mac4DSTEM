# Lane FIG report (saved by the session from the lane's hand-back; the lane's Write was refused), 2026-10-14
Commits: f3ba44e8 (tier 3: ApertureOutline in PaneOverlays.swift, menu names; gate unit 2232/0/4 = 2236) and cbf7848a (tier 2: the
rest, 17 files, +2011/-204; nothing in Core, no frozen file, app not launched).
Built: detector outline on Export Diffraction PNG (Virtual Detector task only; pane's own geometry, CG stroke); region outline (live
dashed + pins) on every exported EDX map (-region / -2x names); multi-panel figure from the Results inspector Figure section (result,
pattern, HAADF, ColorMix, elements; labels; each source's scale bar; PNG, TIFF or one-page vector PDF; SwiftUI fileExporter over a
WritableDocument; fileDialogMessage states scale and pixel size); 1x/2x/3x export scale (AppPreferences.exportScale) in Settings, the
Figure section and Spectroscopy Export (bars/outlines drawn large; 144/216 ppi tags). Audit items: Maps export writes into a new
<stem>-maps folder ("<stem>-maps 2" next), never overwrites, Reveal follows; File > Export Result PNG… / Export Diffraction PNG…;
Results buttons Export PNG… / Export Bundle…; save panels state scale and pixel size. No AppState stored state.
Gates (isolated copies): unit 2277/0/4 = 2281 = func test (2236 + 44 FigureExportTests + 1 AppPreferencesTests), exit 0 (unitF2.log);
core 0, 0 warnings; 1x byte identity for burnScaleBar, publicationFigure, map bar, Maps files (15 hashes, probe/hashes-*.txt);
13 mutations red on named tests. AppState + ResultExport lines 3337 -> 3303.
AppKit kept: NSSavePanel for the File-menu Result/Diffraction exports (a menu command has no view for fileExporter; shell frozen);
the result/pattern bar text stays NSString (output pinned byte for byte). New AppKit: none.
Checked against swiftui-macos, swiftui-whats-new-27, swiftui-specialist: hidden-title names; stable ids; InspectorDataRow truncation at
248 pt; @State initial values only; key-path bindings (one commented closure binding); WritableDocument not FileDocument.
Decisions to overrule: region outline on every map; a new subfolder per Maps export instead of a Replace/Keep Both dialog; only the
live aperture drawn; no colourbars; no File > Export Figure… (the Results inspector button is the entry); PDF/TIFF for the figure only.
Drive plan (all unverified on screen): build Debug -O to a scratch DerivedData ($SP/lanes/FIG/dd-drive); (a) --demo-fixture, Virtual
Det annulus, ⌥⌘E: message "… · 1× · W × H pixels", PNG with yellow ring + dashed cyan inner ring, no handles; 2× doubles at 144 ppi;
no ring in Disks mode; (b) --demo-spectrum-fixture: draw + pin a region, Maps… into a folder -> <stem>-maps with -region-2x files,
second export "<stem>-maps 2", Reveal works; (c) Results > Figure: PNG, TIFF, PDF (Image size greys out for PDF; "vector … points";
PDF text sharp in Preview); the section at a 280 pt inspector; (d) File-menu and Results-header names; header must not clip narrow.
Rows: status "Talk-quality figure export (2026-10-14, tier 2, f3ba44e8, cbf7848a) ... Unverified on screen"; open-items: Result/
Diffraction exports still NSSavePanel and PNG-only; earlier replay detectors not drawn; no colourbars in the figure.
Not done: the session's refuter; a mutation of ApertureOverlay itself; PDF/TIFF for the single exports.
