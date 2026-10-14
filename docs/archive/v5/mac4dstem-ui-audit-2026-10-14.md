# mac4DSTEM UI and HIG review: final pass (2026-10-14)

Read-only. Nothing was run, built or launched. Every finding comes from code and the Apple docs server, not from the screen. I spot-checked 14 findings against the code. All 14 hold. I corrected two line numbers and one claim, marked below.

## Summary

**Good already.**
- Prepare's calibration verdict colours only the symbol (PrepareSettings.swift:178).
- Zoom and pan, the spectrum and the lineage graph have VoiceOver actions and a clamp.
- The 2026-10-07 fixes (Reduce Motion in most places, FormatStyle in readouts, focus strokes) landed.
- Hover guards, refusal text and the "Reset Recommended Settings" confirmation exist.
- The inspector kit is consistent, and Return and Esc work in most sheets.

**The five changes that would help the study most.**
1. **Precision on the diffraction pane.**
   - Add a hover readout (qx, qy, value). Only RealSpacePane has one (ImagePanes.swift:1108; the cursor model sits at 661-787).
   - Add typed aperture centre and radii for virtual BF/DF.
   - Draw the Fit Ellipse annulus on the pattern (only PrepareSettings.swift:342 uses the radii).
2. **Zoom for mouse and keyboard users, everywhere.**
   - Anchor the zoom at the pointer.
   - Add View-menu Zoom In, Zoom Out and Actual Size.
   - Give the Results comparison pan, a visible reset and a zoom badge.
3. **Protect hand-made work.**
   - Grep finds no `UndoManager` in the app.
   - Import Labels, the Al–Mg–Si preset and the phase minus button destroy work with no undo and no dialog.
   - Maps export silently overwrites files (MapsExport.swift:203-214).
   - The object table's CSV export swallows write errors.
4. **Make caveats readable.** One change to `InspectorWarning` (InspectorRows.swift:593) puts the colour on the symbol only. The EDX Auto ID reasons, sum-peak suspects and misfits then move out of hover-only text.
5. **Figures you can trust.**
   - Add a "Same scale" toggle for the comparison panels.
   - Add PDF or TIFF export. Today every export is PNG: `savePNG` allows only `.png`, ResultExport+Rendering.swift:230.
   - Merge the three export entry points.
   - The figure-export lane is in this code now, so route items 3 and 5 through it.

## Tables

Columns: impact (H/M/L), effort (S/M/L), tier (T1 number can move, T2 behaviour, T3 wording), frozen. Study-relevant rows are marked ★. Ranking order is study relevance, then impact, then effort.

### Prepare and Imaging

| Finding | File:line | Change | HIG page | Imp | Eff | T | Frozen |
|---|---|---|---|---|---|---|---|
| ★ No hover readout on the diffraction pane | ImagePanes.swift:41-455 (none) | Reuse `CursorSampleModel` in the header: pixel, value, q when calibrated | Pointing devices | H | M | 2 | N |
| ★ Aperture is drag-only | ImagingSettings.swift:75 | Rows for Center X/Y, inner and outer r (NumericField plus stepper, same snapped commit). Drop the read-only Info rows. | Sliders; Keyboards | H | M | 2 | N (Info rows are in WorkspaceInspector:446, frozen) |
| ★ Fit annulus never drawn | PrepareSettings.swift:339 | Dashed circles on the pattern while the section is open | Sliders | H | M | 2 | N |
| ★ Zoom about the centre, no menu or wheel route | ZoomPan.swift:99; mac4DSTEMApp.swift (no Zoom item) | Anchor at the pointer. Add View > Zoom In, Zoom Out, Actual Size, using the existing step and reset. Fix the header comment: the mouse-wheel claim is unverified. | The menu bar; Gestures; Accessibility | H | M | 2 | N |
| ★ No zoom badge on the diffraction pane | ImagePanes.swift:41 | Same badge as RealSpacePane | Pointing devices | M | S | 2 | N |
| Load crop is redraw-only | ReductionSections.swift:269 | X, Y, w, h rows in the sheet | Sliders | M | M | 2 | N |
| ★ Histogram handle same colour as bars | HistogramView.swift:160 | Contrasting handle | Color | L | S | 3 | N |

Minor, not tabled: the 8% white pane border is invisible in Light mode (ImagePanes.swift:346). The "Real-space crop" section holds only a stride (PreprocessSheet.swift:144).

### Crystal Maps and Bragg Disks

| Finding | File:line | Change | HIG page | Imp | Eff | T | Frozen |
|---|---|---|---|---|---|---|---|
| ★ Replace-all actions unguarded | MapSettings.swift:590; PhaseMappingSettings.swift:444, 525 | Register undo (preferred). Failing that, confirm only when labels or phases exist. The Import Labels tooltip already says REPLACE. | Undo and redo; Alerts | H | M | 2 | N |
| ★ Object table: numbers left-aligned, static filename, `{ _ in }` swallows errors | PrecipitateObjectsWindow.swift:88-89, 148 | Right-align numeric cells. Name the file after the dataset. Show failures. Add Copy. | Lists and tables | M | S | 2 | N |
| ★ Whole-sentence orange/red in the phase rooms | PhaseMappingSettings.swift:125-150, 545, 557; MapSettings.swift:1405, 1486 | Fixed through `InspectorWarning` (see cross-cutting). Use `.caption`, not `.caption2`, for the "undecided" paragraphs. | Color; Typography | M | M | 3 | N |
| Steppers over 1…500 | MapSettings.swift:682, 737-800, 1083-1105 | NumericField for peaks, spacing, radius, Center X/Y | Steppers | M | S | 2 | N |
| Materials Project sheet: Return re-fetches, Import is never default | MaterialsProjectImportSheet.swift:207-213 | Swap the default action by state. Add initial focus. | Sheets | M | S | 2 | N |
| ★ Legend truncates the axis | PhaseClaimOverlay.swift:206 | Middle truncation, `.help` | Lists and tables | L | S | 3 | N |
| ★ `String(format:)` decimals | PhaseMappingSettings.swift:120, 332; MaterialsProjectImportSheet.swift:164 | FormatStyle (display only) | Right to left | L | S | 2 | N |

Minor, not tabled: threshold slider and a one-item Detector picker (MapSettings.swift:323); API key Return and Save; fine-tune sheet caveat size.

### Reconstruction and Results

| Finding | File:line | Change | HIG page | Imp | Eff | T | Frozen |
|---|---|---|---|---|---|---|---|
| ★ Comparison zoom: pinch only, no pan, no visible reset, mouse users cannot zoom | ResultsWorkspace.swift:457 (only `MagnifyGesture`) | Pan inverted in the hover mapping. Visible Reset and −/+ buttons. If the no-pan rule stays, still add reset and a mouse route. | Gestures; Pointing devices | H | M | 2 | N |
| ★ Panels A and B each use their own colour range, and cannot be cleared | ResultsWorkspace.swift:347; ResultExport.swift:856-857 (line corrected; the audit said 842) | "Same scale" toggle, a header note when ranges differ, a Clear button | Color | H | M | 2 | N |
| ★ Figure export is PNG only; scale is hidden from the button | ResultExport+Rendering.swift:229-232; FigureExportSection.swift:41 | Panel title and message with size. Add PDF or TIFF. | File management; Panels | H | L | 2 | N |
| ★ Export entry points overlap, with mixed naming and no ellipsis. Also "Export Diffraction PNG…" vs "…Pattern…". | ResultsWorkspace.swift:86-100; WorkspaceView.swift:213 vs mac4DSTEMApp.swift:177 | One Export menu, one name. Keep the bundle button visible, disabled with a reason. | Buttons; Toolbars | M | M | 2 | N for Results; N for the menu; Y for WorkspaceView:213 |
| ★ Result bar can clip at narrow widths | ResultsWorkspace.swift:69 | `ViewThatFits` with a single Export menu fallback | Layout | M | S | 2 | N |
| ★ Compare "A"/"B" are small bare letters | ResultsSettings.swift:89-101 | Regular size, "Set as A" and "Set as B" | Buttons | M | S | 2 | N |
| ★ Lineage values truncated, not selectable | LineageGraphView.swift:566 | Wrap, selectable | Accessibility | M | S | 2 | N |
| History plots have no axis values | ReconstructionSettings.swift:944 | Y min and max, x name | Charting data | M | S | 2 | N |

Minor, not tabled: the lineage focus ring is hidden (LineageGraphView.swift:116); "WP3" appears in user text (SpectrumOnlyViews.swift:107), which is a ruled-out kind of wording and fixable freely.

### Spectroscopy (EDX)

| Finding | File:line | Change | HIG page | Imp | Eff | T | Frozen |
|---|---|---|---|---|---|---|---|
| ★ Maps export overwrites silently, uses an open panel | SpectroscopyInspectors.swift:493; MapsExport.swift:203-214 | List existing names and ask Replace, Keep Both or Cancel, or write into a new subfolder. Add Reveal in Finder. Do this through the figure-export lane. | File management | H | M | 2 | N |
| ★ Caveats hover-only (Auto ID reasons, suspects, misfit icon) | SpectroscopyInspectors.swift:96-98 | A visible "Details" disclosure. Failure line under the row. Shorter tooltips. | Offering help | H | M | 2 | N |
| ★ Data curve and model are both accent blue; region outline is the accent too | SpectrumStripView.swift:441; MapsGridView.swift:343 | Fixed distinct hues, white under-stroke | Accessibility | M | S | 3 | N |
| ★ Region drawn by mouse only, extent not shown, no pointer feedback | MapsGridView.swift:220, 394 | x, y, w, h rows. `pointerStyle` from the existing hit test. | Pointing devices; Accessibility | M | M | 2 | N |
| ★ Fit only and per-line choice are right-click only | PeriodicTableView.swift:147 | "Selected element" rows | Context menus | M | M | 2 | N |
| ★ Exports and Pin missing from the menu bar | mac4DSTEMApp.swift:172 | Room-specific File > Export items | The menu bar | M | M | 2 | N |
| ★ Results cells use locale-blind decimals | QuantPanelView.swift:9 | FormatStyle, digits identical (test it) | Right to left | L | S | 2 | N |

The periodic-table contrast and 12 pt cells stay as the owner's density choice. Report them and leave them.

### Shell and app (menus, toolbar, settings)

| Finding | File:line | Change | HIG page | Imp | Eff | T | Frozen |
|---|---|---|---|---|---|---|---|
| No Open Recent once a dataset is open | mac4DSTEMApp.swift:144-171 | `Menu("Open Recent")` from `recents` | Keyboards (Cmd-O); convention | H | S | 2 | N |
| Toolbar-only commands: Reveal in Finder, Open with Options… | mac4DSTEMApp.swift:172 | Menu items | Toolbars | M | S | 2 | N |
| Shortcuts disagree: Control-Cmd-I vs a hidden Opt-Cmd-0; no Cmd-. for Cancel | mac4DSTEMApp.swift:198-216; WorkspaceInspector.swift:161 | One visible key. Add Cmd-. | Keyboards | M | S | 2 | Y for the button key; N for the menu |
| Drop a file to open it | mac4DSTEMApp.swift:84 | `dropDestination` on the root | Drag and drop | M | S | 2 | N |
| Divider not keyboard or VoiceOver adjustable | WorkspaceView.swift:925, 737 | `accessibilityAdjustableAction` | Accessibility | L | S | 2 | Y |
| Text-labelled verb touches icon buttons in the toolbar | ContentView.swift:249 | Fixed spacer. Confirm on screen first. | Toolbars | L | S | 2 | Y |
| Welcome marketing copy | WorkspaceView.swift:457 | Cut to the doors | Owner rule: no filler | L | S | 3 | Y |
| Settings reopens on General | SettingsWindow.swift:52 | Remember the last pane | Settings | L | S | 3 | N |

### Cross-cutting

| Finding | File:line | Change | HIG page | Imp | Eff | T | Frozen |
|---|---|---|---|---|---|---|---|
| ★ Coloured warning sentences (orange, red, green) and `.caption`. Merges the shell, Prepare, Crystal and Reconstruction duplicates. | InspectorRows.swift:593; LoadConfigurator.swift:179; PreprocessSheet.swift:334; ReconstructionSettings.swift:75, 119, 732; WorkspaceSidebar.swift:357; WorkspaceInspector.swift:227, 826, 881, 1026 | `InspectorWarning` tints the symbol only. Route the hand-rolled sites through it. The "Missing values are rejected" line (ReconstructionSettings.swift:732) is a plain note. | Color; Accessibility | H | M | 3 | N for all but the four WorkspaceInspector sites (Y). Do the non-frozen sites first. |
| ★ Caveats in `.caption2` `.tertiary` | ReductionSections.swift:158; WorkspaceInspector.swift:411, 883 | `.secondary`, larger | Accessibility; Typography | M | S | 3 | Y for the WorkspaceInspector lines |
| 8 bare Buttons beside glass buttons | CalibrationReadinessRow.swift:181-206; FigureExportSection.swift:59; SpectroscopyInspectors.swift:87, 458, 489 | `.glass` inside `InspectorActionRow`, or convert to `InspectorAdaptiveButton` | Buttons | M | S | 2 | N |
| Slider reset only by double-clicking the label | InspectorRows.swift:416 | Visible reset when the value differs | Accessibility | M | S | 2 | N |
| Periodic table: 90+ Tab stops | PeriodicTableView.swift:129 | One focus group with arrow keys | Keyboards | M | M | 2 | N |
| Reduce Motion ignored on section disclosure (same as older item 3) | InspectorRows.swift:163 | Read `accessibilityReduceMotion` | Accessibility | L | S | 2 | N |
| Glass chips: on-state is tint only, 12 pt | InspectorRows.swift:1007 | Checkmark cue, 13 pt. Check ADR 057/058 first. | Toggles | L | M | 2 | N |

The remaining low-impact items are dropped from the tables: caption sizes, toggle style, room-jump wording, and the "σ" label.

## The five older findings

1. **`DatasetWindow.init` builds an `AppState` every time** (mac4DSTEMApp.swift:66). It still holds. The disk read is the property default `WorkspaceRecoveryStore.recovery()` at AppState.swift:364. Tier 3, S, not frozen. Fix by building lazily.
2. **Object table re-filters and re-sorts on every selection** (PrecipitateObjectsWindow.swift:29). It still holds. `rows` is a computed property. Low impact. Cache it on filter or sort change.
3. **Section animation ignores Reduce Motion** (InspectorRows.swift:163). It still holds. Merged into the cross-cutting table.
4. **A long task does not cancel cleanly.** Open. The only cancellation handler is MapSettings.swift:230. The likely sibling is `await task.value` at SpectroscopyRoomController.swift:443. This is not confirmed, because the old note did not name the site. Check it before filing.
5. **Test waits.** Both still hold: a fixed 200 ms `Task.sleep` at SessionGatesTests.swift:180 and ReviewOwnerCardsTests.swift:137. I did not check the "50 yields" part. Tier 3.

## Not assessable without the screen

- How the Liquid Glass toolbar groups and overflows at narrow widths.
- Real contrast of orange, tertiary and tinted-chip text in light and dark mode, and under each accent colour.
- Truncation and clipping: the result bar, the diffraction header with a new readout, and the 12 pt aperture handles.
- Periodic-table cell size at the narrowest inspector width.
- The feel of the spectrum gestures on a mouse versus a trackpad.
- VoiceOver and Full Keyboard Access, Reduce Transparency, and sheet sizes on small displays.
- Whether the "mouse wheel synthesises magnification" claim in ZoomPan.swift is true.
- The Apple docs server returned page titles only, not full text. HIG quotations in the audits come from the auditors' own knowledge, except where noted. The Open Recent and drop-to-open findings rest on Mac convention.

Every change to a frozen file (ContentView, WorkspaceView, WorkspaceInspector, LayoutPolicy, WorkspaceNavigation) needs a picture the owner has accepted. Wording that corrects a false claim is the only exception (ADR 050). The new menu items, the zoom commands and the room-view changes touch none of them.