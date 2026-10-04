# Lane N stage 0 — on-screen reproduction (P1, P10c)
Archived 2026-10-04: the shots named 09, 18, 42, 43, 44, 46, 50, 52 and 54 are kept beside this file as 1400-px JPEGs; the rest were scratchpad-only.
- commit: a841f9ae4cc6ae98d995b4e52dfd2a87d81d374f (scratch Debug build, headbuild/dd)
- display: 3024x1964 Retina (2x), points 1512x982
- other mac4DSTEM instances seen before launch: none (pgrep -fl mac4DSTEM empty)

## P10c — Preprocess Write with an uncommitted Threshold
Prediction: typing 20 in Threshold (no Return) then clicking Write with the mouse writes a file whose hot-pixel record carries the old threshold (8), not 20. Control with Return: records 20.
- shot 09-threshold-typed20.png: Filter hot pixels on, Threshold field focused showing 20, NO Return pressed. Next: mouse-click Write...
- Prediction line (P10c, mouse path): file records threshold 8 (old), not 20.
- Clicked: sidebar Preprocess..., chose copy drive/data/demo.h5 (panel), toggled Filter hot pixels, clicked Threshold, cmd-A, typed 20 (shot 09: field focused showing 20, no Return), mouse-clicked Write... -> save panel (shot 10), saved to N/out/p10c_mouse_thr20.h5 (shot 17, status line shot 18: "Wrote p10c_mouse_thr20.h5 ... 655,4 MB").
- SEEN (mouse path): written file's root attr mac4dstem_derivation = {"detector_bin":1,...,"hot_pixel_threshold":8,"hot_pixels":[[0,81],[127,46]],...,"source_file":"demo.h5"}. Threshold typed was 20; file records 8 (old default). Prediction confirmed.
- Control (Return before Write): same steps, but pressed Return after typing 20 (shot 22: field shows 20); Write -> N/out/p10c_return_thr20.h5. Written attr: "hot_pixel_threshold":20, "hot_pixels":[[0,81],[127,46]].
- Shots: 09 (typed 20, focus still in field), 10/17 (save panel), 18 (status line after mouse write: "Wrote p10c_mouse_thr20.h5 · 100 × 100 × 128 × 128 · 655,4 MB · 2..." -- names no threshold), 22 (control), 26.
- Note: on demo.h5 the detected hot-pixel SET is identical at threshold 8 and 20 (two strong pixels), so only the recorded threshold differs; a cube with weaker hot pixels would also change the replaced set.
- VERDICT P10c: REPRODUCED (mouse-click Write records the OLD threshold 8; Return-first records 20). Cause: Write path snapshots pending.preprocess without PendingEdits.commitAll.

## P1 — unedited number field commits its rounded display
Path chosen: (b) ACOM Exploratory scale on demo.h5 (uncalibrated => the slider is shown). Parallax/ptycho on demo.h5 show warning badges (Advanced, needs calibration) and the demo has random disks, not a defocused probe, so path (a) was judged not meaningful here.
Prediction: drag Exploratory scale slider (many digits, 4 shown), run ACOM so a result exists at that value, switch room away and back, Info/inspector shows the ACOM result gone though nothing was edited (invalidateResult via blur/disappear commit of rounded text).
- Setup: opened drive/data/demo.h5 copy (shots 28), Bragg Disks > Detect All Disks (shot 32: 93,209 peaks). Next: Crystal Maps > Orientation.
- Q scale on demo.h5 is physical (From file 0,012) so the Exploratory slider is hidden; used Prepare > Clear Calibration (in-memory, scratch copy; app dialog confirmed) to make it non-physical. CIF Al_thronsen2024 imported (copy in N/out).
- Shot 42: after dragging the Exploratory scale slider: the Q scale read-out says 0.0125597 Å⁻¹/px (stored, 6 sig. digits) while the Exploratory scale field shows 0,0126 (4 digits). No edit typed. Next: Preview Orientation -> result at 0.0125597; then leave the room and return.
- Shot 43: Preview Orientation ran: ACOM preview IPF-Z map (Exploratory) exists; inspector Q scale 0.0125597 Å⁻¹/px; field 0,0126; "Cached plan 200 templates"; sidebar Orientation row has the result icon. Status line "ACOM preview ✓ ...". Next: click Imaging (leave the room, nothing edited), then Crystal Maps > Orientation.
- Shot 44 (Imaging room right after leaving Orientation): right pane still showing the ACOM preview IPF-Z. Then clicked Crystal Maps (opens Strain), then Orientation (shot 46): "No Result Yet"; Q scale read-out now 0.0126 (was 0.0125597); sidebar Orientation row lost its result icon (shot 45: empty circle). No field was edited, no Return typed. The stored exploratory scale was rounded to the shown text and the ACOM result discarded.
- Next: control — re-run (value now equals shown text 0.0126), switch rooms and back: result should survive.
- Control (shots 47-50): re-ran full scan at the now-rounded value 0.0126 (shot 47: Orientation row ✓, "Re-run Full Orientation Map", Q scale 0.0126, field 0,0126), then Imaging -> Crystal Maps -> Orientation (shots 49, 50): result SURVIVES (row ✓, "Re-run Full Orientation Map" button, CBED fit overlay, Cached plan 200 templates, Q scale 0.0126). Incidental: the right ACOM pane showed "No Result Yet" in 49/50 although the result exists (separate presentation oddity after a room round trip; not P1).
- Contrast with the defect case (shot 46): row empty circle, button "Run Full Orientation Map", no fit overlay toggle, Q scale 0.0126 (from 0.0125597).
- Re-test of the defect: drag slider again, re-run, leave & return (below).
- Re-test (shots 51-54), minimal route: dragged slider again (shot 51: dragging itself discards the result by design — didSet invalidateResult; Q scale 0.0155254, field 0,0155), re-ran full scan (shot 52: row ✓, Q scale 0.0155254, field 0,0155), clicked sibling tab Strain then Orientation again (shots 53, 54): result GONE (row empty circle, "Run Full Orientation Map", no fit overlay), Q scale read-out 0.0155 (was 0.0155254). Nothing typed, no Return.
- VERDICT P1: REPRODUCED twice (path b, ACOM Exploratory scale; evidence = the stored value visible in the Q scale read-out changing from the unrounded to the shown 4-digit value with no edit, and the ACOM result being discarded by leaving the inspector). Path (a) Parallax -> Use Parallax Fit -> Defocus NOT driven: demo.h5 has no defocused probe (Parallax/ptycho carry warning badges), so the scientifically important Defocus/C12 case is shown only by shared mechanism (one resolve() path in InspectorRows), not on screen.
- Incidental (not part of P1/P10c): after a room round trip the ACOM right pane can read "No Result Yet" while the result exists (shots 49, 50).

## End
Window frame set to position {0,33} size {1470,923} before quitting; quit via the app menu (Quit mac4DSTEM); pid 55368 confirmed gone. Written files p10c_*.h5 (656 MB each) deleted after their derivation attributes were recorded above; only N/out/Al_thronsen2024.cif (copy) remains. No other mac4DSTEM instance was touched.
