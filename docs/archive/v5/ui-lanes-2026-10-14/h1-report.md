# Lane H1 report (saved by the session from the hand-back; the lane's Write was refused), 2026-10-14
Commits (trailer: Sonnet 5.5, the lane's model): 3e873c82 tier-1 registration (readout) before code; 515257ea readout (tier 1:
header Qx · Qy · I · q, q = s·|E(p − o)| with the app's ellipse correction and per-position fitted origin; q only for a physical Q
scale and a measured origin; overlay in the header's flexible gap, shortens then vanishes, never truncates; sibling
DiffractionCursorModel); 0ca20be4 typed aperture centre/radii (NumericField + Stepper per shape, through snappedEdit ->
updateAperture -> commitApertureChange as the drag; the frozen WorkspaceInspector's Info rows now duplicate them); aa4df75a zoom
(pinch about its start point; menu and VoiceOver zoom about the pointer or the centre; badges on both panes; ZoomCommands.swift:
View > Zoom In ⌘+, Zoom Out ⌘−, Zoom to Fit ⌘0 — "Zoom to Fit" because 1× is fit-to-pane; ZoomPan's wheel claim withdrawn, no
wheel route exists; FinalPolishR2Tests marker follows the rename); b15a9d5d Fit Ellipse annulus overlay (new file; centre = the
aperture centre as calibrateEllipse uses; a synthetic ring checks the frame; reuses the section's @SceneStorage key); 101fab78
histogram handles white on a dark halo, pane border visible in Light (tier 3).
Gates (isolated copies): h1d unit 2274/0/4 = 2278, core 0; h1f unit 2323/0/4 = 2327 (one interleaved line read by name), core 0;
h1g 50 tests over the affected classes, 0 failed. Mutations: every new test red on a mutation (readout: floor→round, transposed
index, ellipse skipped, mean for per-position origin, gate removed, non-finite, physical unit, mrad, far edge, sqrt dropped, field
swap, θ symbol; tier 2: 16 more); one vacuous notify test removed. Strays: ApertureEntryTests in 0ca20be4, ZoomAnchorTests in aa4df75a.
Hookup: `ZoomCommands()` in `.commands { }` after `DatasetCommands(menuRelay: menuRelay)` (present at mac4DSTEMApp.swift:386 in the tree).
Open: Info rows duplicate the aperture rows (frozen file); SpectrumStripView and RealSpacePointerPolicy comments repeat the withdrawn
wheel claim; the menu zooms the pane last clicked, no outline outside Imaging; readout refreshes on patternVersion only; q hidden
without explanation when the origin fit exceeds the probe radius; Results comparison pan/zoom not done.
Drive plan: (1) readout on a calibrated fitted cube: hover -> Qx·Qy·I·q, q 0 at the beam centre; widths ~420/500/700 pt; drag the
aperture centre -> q goes, pixel/I stay; arrow-key the scan -> value updates; zoom -> clears; mrad -> θ. (2) Imaging > Detector:
type 70.4 and 70,4 in Center x, steppers, per shape; radius edit keeps the fitted origin, centre edit sets it aside, Restore works.
(3) zoom: pinch an off-centre disk stays put; ⌘+ ⌘− ⌘0 with hover; View menu after the hookup; real-space pane zoom; badge; ⌃-scroll
does not zoom. (4) Prepare > Ellipse correction open: red dashed circles at the radii; vanish on collapse/leave; Fit Ellipse ring
between them; strokes thin under zoom. (5) histogram handle white in Dark and Light; pane border visible in Light.
Checked per control against swiftui-macos, swiftui-whats-new-27, swiftui-specialist, HIG (listed in the hand-back).
