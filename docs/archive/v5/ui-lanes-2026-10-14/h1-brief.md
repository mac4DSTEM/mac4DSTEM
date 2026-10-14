# Lane H1 brief — precision and zoom (UI audit 2026-10-14, the study's top item)
SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
Read $SP/lanes/UI-COMMON.md first (rules for all UI lanes), then the audit /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM/docs/archive/v5/mac4dstem-ui-audit-2026-10-14.md
(Summary item 1-2, the Prepare/Imaging table and the cross-cutting zoom rows) and its JSON beside it.
Build (the owner asked for these, 2026-10-14):
1. A cursor readout on the diffraction pane: reuse CursorSampleModel (ImagePanes.swift ~661-787; RealSpacePane's readout ~1108):
   pixel (qx, qy), value, and q in calibrated units when the dataset is calibrated. TIER 1 (a new number on screen): register it
   first (docs/archive/v5/diffraction-readout-2026-10-14.md: the formula with its source — reuse the app's own pixel→q conversion
   and frame conventions, find them; the predicted check; the test), commit the registration, then build; test the readout against
   the real-space readout's conventions and the calibration (a known origin/pixel size/ellipse gives a known q), break the test once.
2. Typed aperture centre and radii in ImagingSettings, committing through the same snapped path as the drag (locale-safe entry:
   DecimalEntryFormat). Tier 2.
3. The Fit annulus (inner/outer radii) drawn on the pattern while the Fit Ellipse section is open (PrepareSettings.swift ~342 holds
   the radii). Tier 2. If the overlay belongs in UI/PaneOverlays.swift, that file is lane FIG's until it commits: do the rest first
   and wait for the session's message before touching it.
4. Zoom anchored at the pointer, a zoom badge, and View > Zoom In / Zoom Out / Actual Size; check ZoomPan.swift's claim that the
   mouse wheel synthesises magnification and fix the comment or the behaviour. Tier 2. Put the menu commands in a NEW file of yours
   (e.g. UI/ZoomCommands.swift, a `Commands` type plus whatever focused value it needs); do NOT edit App/mac4DSTEMApp.swift — lane H2
   owns it and adds your one-line hookup; give the exact line in your report and message the session when the file is committed.
Your files: ImagePanes, ImagingSettings, PrepareSettings, ZoomPan, HistogramView (+ your new files and tests). Lane H2 will not
edit these until you commit; you do not edit H2's (mac4DSTEMApp.swift, InspectorRows.swift, the frozen-shell files, the object table).
Order: 1 (registration first), then 2, 4, 3. Commit at each green checkpoint.
