# Refuter RFIG report: talk-quality figure export (tier 2), frozen commits f3ba44e8 + cbf7848a
Written progressively; predictions are entered BEFORE the experiment that tests them. Trees: new = `git archive cbf7848a`, old = `git archive f3ba44e8^`
(both under lanes/RFIG/, probe files copied in, builds in lanes/RFIG/dd-new, dd-old; scripts build.sh / runtests.sh; probes in probe-src/, output in probe-out/).

## Predictions (written before any run)
- P1 (geometry, E1): in a 1x/2x/3x diffraction export of a 64x48 pattern (burn magnification 8), the yellow outer ring of annulus
  (cx,cy)=(20,10), inner 4, outer 8 has centroid (20.5, 10.5) x 8s within 0.5s px and mean radius 64s within 1s px; the cyan inner ring mean radius 32s.
  Non-square 80x30 circle: centre (65.5, 6.5) x mag. Independent of the lane's own metrics (analytic numbers from the pane's stated convention).
- P2 (E1b, pane vs export): ImageRenderer of the real SwiftUI `ApertureOverlay` in the same 512x384 box: yellow ring mask IoU with the export > 0.85 for
  circle/annulus/rectangle; cyan (dashed) IoU lower (dash phase/direction differ) but the same radius; colour at the ring top equal up to the colour-scheme.
- P3 (E2, bar lengths): the ladder bar (result/pattern) is nice/upd x mag x s pixels long within 2 px at 1x/2x/3x, in a figure panel and in the PDF page
  rasterised at 1x and 2x; the map bar in a figure is plan.lengthPoints x s. So bars do mean their stated length at every scale.
- P4 (E2b): the 2x/3x burnt-in bar plate is NOT the 1x plate with more pixels (plate pad 6, text gap 4 are unscaled px in drawLadderBar): plate bbox at 2x is not 2x
  the 1x bbox; a small but non-zero fraction of pixels (> 0.1 %) differ from the 1x image enlarged. Cosmetic.
- P5 (E3, files): PNG/TIFF at 2x/3x carry DPI 144/216 through the real `figureFile` path, 1x carries none; PDF message says vector/points.
- P6 (E4, Maps folders): a file named like the folder is skipped ("scan-maps 2"), existing dirs skipped, the first export is never touched; a mid-write failure
  throws but leaves the partial folder (benign: the next export goes beside it); a read-only parent throws a permission error.
- P7 (E7, colours): the export resolves Color.yellow/cyan/accentColor in a default (light) environment; the app is dark here (AppleInterfaceStyle = Dark), so the
  export colours differ from what the pane shows (cyan most), contradicting the "pane's colour, not a near one" comment. Accent resolved in an empty environment
  may not be the user's accent.
- P8 (byte identity): every hash of the lane's probe inputs AND of my own different inputs (odd sizes, "1/Å"/"µm" units, mrad, caption of 6 lines, magnification 1, 7-px strip,
  PNG file bytes with the provenance chunk, Maps with two tiles 50x40, scale bar on/off) is identical old vs new.
- P9 (tests do not pin the bar): a mutation that drops the device scale from the ladder bar's units (`/ Double(magnification * max(deviceScale, 1))` -> `/ Double(magnification)`)
  leaves FigureExportTests green (the bar's length and label at 2x/3x/figure/PDF are measured by no test), while my probe E2 goes red on it: at 2x the bar would be labelled
  with twice its length.

## Method
Read-only on the repo: `git archive cbf7848a` (new) and `git archive f3ba44e8^` (old) into lanes/RFIG/{new,old}/mac4DSTEM; built with heavy-build.sh (logs/build-*.log, exit 0), tests through heavy.sh
(logs/test-*.log, test2-*.log, mut-*.log). Probes (never committed): probe-src/RFIGHash.swift (both trees), probe-src/RFIGGeom.swift (new only); outputs in probe-out/ (baseline/ = unmutated geometry runs).
No app launch, no drive. Everything below is from those runs unless marked "read".

## Results against the predictions
- **P1 geometry HOLDS.** Annulus (20,10) in/out 4/8 on a 64x48 pattern: yellow ring centroid (164.00, 84.00)/(328.00,168.05)/(492.00,252.00) at 1x/2x/3x = (20.5, 10.5) x 8s exactly (the half pixel is there, x = column, y = row);
  mean radius 64.01 / 127.96 / 192.02 (expected 64s); cyan inner ring mean radius 32.00 / 63.99 / 96.03 (expected 32s); line sd 0.4/0.8/1.3 px = the stroke. Non-square 80x30 circle: centroid (458.50, 45.50) = (65.5, 6.5) x 7, radius 35.02. (probe-out/baseline/geom-E1.txt)
- **P2 against the real SwiftUI pane HOLDS.** `ApertureOverlay` rendered by ImageRenderer in the same 512x384 box vs the export (handles excluded): yellow ring mask IoU annulus 0.982, circle 0.968, rectangle 1.000
  (centroids equal to 0.15 px, mean radius equal to 0.00); the dashed cyan inner ring IoU 0.745 (dash phase/direction of CGPath vs SwiftUI circle differ, same radius). Point detector NOT compared (my handle-exclusion disc swallowed the 8 pt crosshair). (geom-E1b.txt)
- **P3 bars HOLD.** Result/pattern ladder bar: 80 / 160 / 240 px at 1x/2x/3x = nice(5 nm)/0.5 x 8 x s exactly, in `burnScaleBar`, in a figure panel, and in the PDF rasterised at 1x/2x (80/160). The map bar in a figure: 60/120/180 px = plan.lengthPoints x s.
  So the bars mean their stated length and the labels do not change with the scale. (geom-E2.txt)
- **P4 HOLDS (cosmetic).** The 2x/3x burnt-in bar plate is not the 1x plate with more pixels: plate bbox width 92 / 172 / 252 px (proportional would be 92 / 184 / 276), plate left edge at x = 6 / 19 / 32 (proportional: 6 / 12 / 18); 0.59 % (2x) and 0.74 % (3x) of pixels differ from the 1x image enlarged.
  Cause: `pad: 6`, the `+ 4` gap and the `max(10,..)/max(11,..)` floors in `drawLadderBar` are pixels, not points. (geom-E2b.txt)
- **P5 files HOLD.** Real `figureFile` path: PNG and TIFF 1x carry no DPI, 2x 144x144, 3x 216x216, pixel sizes 944x470 / 1888x940 / 2832x1410; PDF page 944x470 pt at any scale, message "vector ... points". PNG gets an sRGB profile, the TIFF has none. (geom-E3.txt)
- **P6 Maps files HOLD.** A FILE named `scan-maps` in the picked folder -> `scan-maps 2`; with a dir `scan-maps 3` present the next is `scan-maps 4`; the first export stays byte-intact; a read-only parent throws a permission error (surfaced in exportNote, read);
  a failure mid-write throws but leaves the partial folder (`partial/ok.png`), which the note does not name (the next export goes beside it, nothing is lost). Tiles are keyed by Z, so file names inside one export cannot collide (read). (geom-E4.txt)
- **P7 HOLDS.** `Color.cgColor()` resolves in an empty (light) environment. Light vs dark: yellow (1.000,0.800,0.000) vs (1.000,0.839,0.000); cyan (0.000,0.753,0.910) vs (0.235,0.827,0.996); accent (0.000,0.533,1.000) vs (0.000,0.569,1.000).
  This Mac is in Dark mode and the app follows the system, so the pane shows the dark variants and the export the light ones: the "pane's colour, not a near one" comment (PaneOverlays.swift ApertureOutline, FigureRendering.swift `Color.cgColor`) is false for dark appearance (cyan most visible). Cosmetic. (geom-E7.txt)
- **P8 byte identity HOLDS.** 38 hashes, f3ba44e8^ vs cbf7848a, all identical (probe-out/hashes-old.txt vs hashes-new.txt, `diff` empty): the lane's 16 keys (equal also to its recorded FIG/probe/hashes-head.txt; 15 distinct, the CSV appears twice) plus 22 of mine on
  different inputs (37x29, 48x200, 512x512, 300x7 images; "1/Å", "µm", "mrad"; a 6-line caption, masksNoData, gamma 0.6, no colorbar; the PNG FILE bytes with the provenance chunk; `MapBitmap.pngData`; Maps with two tiles 70x40 and bar on/off).
  Not covered at 1x: Maps with a drawn region and regions ON (changes by design: outline + `-region` in the name).
- **P9 HOLDS: the tests do not pin the bar.** Mutation A (drop `deviceScale` from the ladder bar's `unitsPerOutPixel`, FigureRendering.swift:166): FigureExportTests 44/44 green + all my probe tests; the probe's measured bar is 320 px at 3x (expected 240) and, at 2x, 160 px with the label "10 nm" for a true 5 nm (a length-only test passes there).

## Mutations (item 5)
Baseline FigureExportTests on the frozen tree: 44 passed, 0 failed (test2-new.log). Sampled from the lane's 13, re-run by me:
- "map bar ignores the scale" (MapRasters.swift:168 `* scale` dropped): RED, 1 test (testTheMapsExportAtTwoAndThreeTimes), as claimed. (logs/mut-B.log)
- "free folder name ignores what exists" (MapsExport.swift:217): RED, 2 tests (testAFreeFolderNameCountsUp, testASecondMapsExportNeverReplacesTheFirst), as claimed. (logs/mut-C.log)
- Also read from the lane's logs (FIG/logs/mut-A-M1, M4, mut-B-M12): the failures are in the logs. 
Mine, behaviours the tests do not pin (both survive 44/44):
- A: ladder bar scale (above). 
- D: `figurePanels` hands the EDX map panels `overlays: []` instead of the region outlines (FigureExport.swift:207): all 44 green. The EDX branch of `figurePanels` (HAADF/ColorMix/element panels: regions flag -> overlays, scanPixel -> bar, figureOrder) is exercised by no test because `hasSpectrumImage` is false in every test.
All four files were restored byte-identical (logs/mut-*.restore).

## Verdict: UPHELD WITH CORRECTIONS
The claims hold: the detector outline sits where the pane draws it (to 0.15 px, 1x-3x, non-square), bars mean their length at every scale and in the PDF, ppi tags are right, the Maps export cannot overwrite or lose a file, 1x output is byte-identical.
What is wrong is the safety net, not the behaviour.

### Must-fix (tests only, no behaviour change)
1. FigureExportTests: pin the ladder bar at 2x/3x/figure/PDF. Mutation A survives. The check must pin LENGTH and LABEL together (at 2x the broken code draws the right length under a doubled label). Cleanest: factor the bar's plan out of `drawLadderBar`
   (ResultExport+Rendering.swift:328 (`pad: 6` at :350)) into a pure `(label, lengthPixels)` function and assert label equal at 1x/2x/3x and length = s x the 1x length; plus one pixel measurement of the longest white run as in my probe (RFIGGeom.testBarLengths).
2. FigureExportTests: pin the EDX branch of `figurePanels` (FigureExport.swift:192-210) - panels in `figureOrder`, outlines present when `export.regions` is on and absent when off, `.map` bar from `scanPixel`. Mutation D survives. Either a spectrum fixture that makes `hasSpectrumImage` true, or move the branch into a pure
   `MapsExport.figurePanels(model, ids)` the test can call.
Neither changes a number the owner sees; both are what "break every new test before trusting it" asks for on claims the hand-back makes.

### Notes (not blocking)
- N1 (drive item) The pattern panel's detector depends on `navigation.analysisMode == .virtualDetector` (FigureExport.swift `patternExportOverlays`). Results has no task of its own (`analysisModes` is empty), so the mode left behind by the last room decides whether the Figure carries the detector: Image(VD) -> Results draws it, Bragg Disks -> Results silently does not. The drawn aperture is the live one, not necessarily the one that made the result panel. Suggest a "Detector outline" tick in the Figure section (or a line saying whether it will be drawn). Drive: VD -> Disks -> Results -> Figure.
- N2 Colours resolved in a light environment against a dark app (P7); fix is one line in `Color.cgColor` (resolve with `colorScheme = .dark`), and the two comments.
- N3 Plate padding does not scale (P4).
- N4 Regions default ON changes the default Maps output (outline + `-region` names) whenever a region is drawn; decision for the owner (the lane flagged "overrule on sight"). At 1x a 2 pt outline on a 64 px map PNG is chunky; 2x/3x are the talk sizes.
- N5 The figure's result panel has no colourbar, no caption and no "no data" legend although `masksNoData` pixels are painted grey (82,82,87): `figurePanels` ignores `raster.masksNoData`. A ticked panel that `resultExportRaster` cannot make is skipped silently (`try?`), so a figure can lack a ticked image without a word.
- N6 TIFF carries no ICC profile (PNG gets sRGB). Dash phase of the cyan ring differs from the pane (IoU 0.745).
- N7 AppKit: NSSavePanel stays for File-menu exports (no view there, frozen shell: justified), but the Results header "Export PNG..." button is in a view and goes through the same function; the Figure shows fileExporter works from such a place. Open-item, not a defect.
  The result/pattern bar text stays NSString (moved unchanged, bytes proven identical). New controls: Image size appears in Settings, the Figure section and Spectroscopy Export (Format twice, Regions twice): one preference, five controls; the label "Image size" could be read as the dataset's.
- N8 A failed Maps write leaves a partial `<stem>-maps` folder and the note does not name it. The figure size guard is per side (16384), not per area (up to ~1 GB).
- N9 The frozen commits carry no docs/status.md / open-items.md rows (the coordinator writes them, per the brief); the "Unverified on screen" items from the lane's drive plan are still the whole on-screen evidence: nothing here was driven by me or by the lane.

## Not done
No app launch or drive (the Figure section's layout, the fileExporter panel and its message, Reveal in Finder, narrow-inspector behaviour are unseen); point detector vs the pane; region outline vs the pane's Canvas (shared `RegionOutline` path read, not rendered); the other 11 mutations not re-run (3 read from the lane's logs); PDF font embedding rights not examined.
