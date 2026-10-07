# SwiftUI review fixes — on-screen verification list (2026-10-07)

The 21 commits `37252cdc..1434275c` fix the SwiftUI review's findings (observation, concurrency, accessibility, redraw
cost, the Metal bridge). Every row below is **unverified on screen** until a drive marks it. One drive, one build of
the tree, every shot reviewed; record the result in the right-hand column (PASS / FAIL + what was seen / NOT RUN + why).
VoiceOver and Full Keyboard Access rows need those turned on (System Settings › Accessibility); "VO actions" means the
VoiceOver Actions rotor (VO-Cmd-Space) on the element.

## Image panes and the Metal view

| ID | Check | Result |
|---|---|---|
| V1 | Colormap change recolours the pane at once; an RGBA result (IPF, DPC wheel) still draws. || PASS (drive 1): Gray chosen in the diffraction popover recoloured the Metal pane and colourbar at once; Viridis restored. RGBA result not tried. |
| V2 | Display-range low/high and gamma drags follow live, no stale frame. || PASS (drive 1) for gamma: 1.00 → 2.49 drag followed live. Display-range drag not tried. |
| V3 | A new result of the same size shows the new pixels. || PASS (drive 1): Re-calibrate Origin re-ran the virtual detector; the pane redrew with the new range (1.16e+04–1.17e+04). |
| V4 | Window / sidebar / inspector resize redraws to the new size; a pane in a sheet or the comparison panel draws on first open. || Partial (drive 1): both panes drew on first open, also in a second window. Resize not tried. |
| V5 | Hover and pan fast over an image: no flicker, no blank pane. | |
| V6 | Cold launch, then virtual detector, mean diffraction, origin measurement, centre of mass each run once (pipelines built eagerly). || Partial (drive 1): virtual detector and origin measurement ran on a cold launch; mean diffraction and CoM not run. |
| V7 | Prepare, Fit overlay on, an origin fit that trimmed positions: grey wash + "N of M positions excluded" legend as before; zoom/pan/hover smooth; Fit overlay off, leaving Prepare, a refit each clear or update it. || NOT RUN: the demo origin fit trimmed no position, so there was no wash to see. |
| V8 | Real-space hover readout follows the pointer and clears on exit; header spacing unchanged. || PASS (drive 1, against base): "X 5, Y 6: 1.153e+04 intensity" under the pointer, gone outside. A synthetic glide misses the same intermediate stops in base d67b0f3d and in this build (tool limit, not a regression). |
| V9 | Object-table selection outlines the objects, follows a new selection, clears with it. | |
| V10 | ACOM region reference ↔ scalar result toggling always shows the right image (fresh session too). | |
| V11 | Scan navigator inset correct while scrubbing; another dataset in the window replaces it. || PASS (drive 2): after Detect All the inset drew on the diffraction pane; clicking a cell moved its marker and the pattern followed. Another dataset not tried. |
| V12 | Virtual Detector: aperture drag / radii / shape switch / pattern zoom follow and commit; fit overlay chip in Prepare, Strain, ACOM. || PASS (drive 2): radius drag committed and the real-space image followed live (1.15e+04 → 2.80e+04); Circle retitled the pane and redrew overlay and image. |
| V13 | VO actions on both panes: Zoom in, Zoom out, Reset zoom (2× steps, 0.25×–64×); double-click reset, pinch, drag as before; Reduce Motion makes reset instant. || PASS (drive 1): both panes list Zoom in / Zoom out / Reset zoom; Zoom in = 2× (badge "Pan ×2,0", scale bars 0.1 Å⁻¹ and 0.5 nm), Reset zoom back. Reduce Motion not tried. |

## Concurrency

| ID | Check | Result |
|---|---|---|
| V14 | **First:** two dataset windows merged into tabs; start a long job in one, switch tabs — the job must NOT stop. Minimise/restore mid-run — the job continues. || PASS (drive 1, logging build of this tree): no window-close hook on Merge All Windows, three tab switches, minimise or restore; exactly one on ⌘W. |
| V15 | Close a window mid-run (ACOM / phase contrast / Detect All): CPU drops within seconds, no result appears, app stays up. | |
| V16 | Close a window mid-load of a large .h5: the load unwinds, another window still opens files. | |
| V17 | Open an .h5 in window A while window B loads a large Velox file: A stays responsive while its open waits. | |
| V18 | Detect All (classical, learned), Diffraction Groups, origin calibration, Fine-tune, live learned overlay: UI responsive, progress advances, Stop works. || Partial (drive 1): Re-calibrate Origin finished with the UI live (probe 6.93 px, RMS 0.0018 px). Drive 2: classical Detect All, 1 296 peaks (9 per pattern), UI live. Learned detection, groups, fine-tune not run. |

## Spectroscopy room

| ID | Check | Result |
|---|---|---|
| V19 | Periodic table at rest looks identical (fills, outlines, size; unavailable cells' ink; tooltips; right-click menu incl. the unavailable reason; hover highlights lines). || PASS (drive 1) at rest: cells, fills and the faint unavailable H/He/Li/Be unchanged (full-resolution crop). Tooltips, right-click and hover highlight not opened. |
| V20 | Full Keyboard Access: Tab walks the cells, Space toggles Quantify/Off; VO reads "Al, mapped", VO actions Quantify / Fit only / Off; "Mapped" rotor; Reduce Motion makes the fold instant. || PASS (drive 1, AX): cell = button, label "Fe", value off → mapped after the Quantify action; actions Off / Fit only / Quantify; He offers none. Full Keyboard Access and the rotor not tried (system settings left alone). |
| V21 | ColorMix tile: focus shows a thin inset accent stroke only while focused; VO value "No region" / the region caption; "Clear region" action only with a region, same effect as Delete. HAADF/element tiles read once. || PASS (drive 1): value "No region" → "Region · 208 px · live"; Clear region listed only with a region and clears it; Backspace clears; element tiles read once. Focus stroke seen on a directly launched build; an open-launched instance showed none (unexplained, not reproduced). |
| V22 | Spectrum focused: ←/→ pan a fifth, + / = / − zoom about the centre, Home and Esc as before, ⌘+/⌘− untouched; inset focus stroke; VO actions Zoom in/out, Pan left/right, Show full range, Reset view; label stable, value carries the energy span. || PASS (drive 1): six actions; value "Energy from 1,086 to 2,086 keV. Y axis in counts." moves with Zoom in / Pan right; after a click ←, −, = pan and zoom; inset accent stroke while focused. ⌘± not tried. |
| V23 | Pin chip reads "Unpin Pin 1" with the pixel hint; click removes the pin; look unchanged. || PASS (drive 1): "Unpin Pin 1", hint "1 024 pixels"; pressing it removed the pin; chip look unchanged. |
| V24 | **First in the room:** right-click on the spectrum lists candidates for the hovered energy; after ⌥-drag the first item is "Zoom to …"; picking adds the element. || PASS (drive 1): Al Kα 1,486 keV first at the peak, Ge/Gd/Tb/Mg at ~1.19 keV; picking Al Kα mapped Al (tile, marker, results row). ⌥-drag "Zoom to" not tried. |
| V25 | Spectrum identical zoomed out (no shaved peak), Per pixel on/off, log/linear, model/background/residual/pins; hover guide + readout smooth; crowded marker names hide/show with the help text in step; at the minimum height nothing draws. || Partial (drive 2): Per pixel + Log over the full range — axis "counts / px / 10 eV" in decades, Al Kα intact; Linear restored. Model, background and residual not drawn (no fit, see V26). |
| V26 | Rapid element clicks during a running fit settle on the last selection, no stuck "fitting"; Quantify then an immediate edit reports the fit that stands; Auto ID on open still applies. || Partial (drive 2): Quantify with Si switched on and off during it settled on Off, nothing stuck. The fixture states no beam energy, so the fit declines at% and the newest-fit wait was not exercised. |
| V27 | Export › Spectrum CSV… writes the shown spectrum (header names file + region; after Quantify the model/background columns); disabled only before the first spectrum. | |
| V28 | Live region drag smooth; Region section shows only the phase row; Smooth changes every tile at once; at%/wt% switch updates every Quantify row. || Partial (drive 2): Smooth 5 × 5 changed the ColorMix and every tile at once, each labelled; None restored them. The Region section shows no phase row (none set). at%/wt% not exercised (no at%). |

## Elsewhere

| ID | Check | Result |
|---|---|---|
| V29 | Output tab past 300 lines keeps auto-scrolling; a text selection stays on its line; Clear works. | |
| V30 | Bragg Disks › Probe kernel ring warning still appears; colormap / log / display-mode / region-radius toggles do not recompute it; a new dataset updates it. | |
| V31 | Load configurator, VO on "Scan · real space": reads title + caption; Scan X / Scan Y steppers move the picked position and the single-pattern pane follows; click-to-pick and drag-to-crop unchanged. | |
| V32 | Inspector slider with a default: VO actions list "Reset to default" and it resets; increment/decrement still work on the combined element. || PASS (drive 1, gamma slider): actions Increment, Decrement, Reset to default; reset 2.49 → 1, increment 1 → 1.28. |
