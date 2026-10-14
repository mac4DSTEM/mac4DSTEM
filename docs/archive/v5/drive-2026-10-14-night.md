# Drive 15 — 2026-10-14 night (pane keys, the three UI lanes)

Build: a scratch Develop build of `b8daad70` (git archive, scratch DerivedData), launched by binary path, pid-pinned; every
click and key through a wrapper that refuses unless that pid is frontmost; window-id screenshots only (reviewed by the
session, kept in its scratchpad). `--demo-fixture` (12 × 12 scan, 64 × 64 detector) unless named. The `drive` lock was held
20:30–20:47 CEST. The owner's window frame (0, 33, 1512 × 949) was left as found.

## (a) Pane keys (macTEM hand-off, `open-items.md`)

| Check | Seen |
|---|---|
| Click on the Imaging (real-space) pane, then ← → ↑ ↓ | Steps the scan: X 4 → 5 (→), Y 5 → 6 (↓), ⇧→ +10 clamped at X 11 (AX value of the scan marker) |
| The same after dragging the pane divider (50 → 46 %) | ← X 11 → 10, ↑ Y 6 → 5; the divider stays at 46 % |
| `--inspector-hidden` | Keys step the scan as above |
| LLDB, breakpoint on `-[NSWindow makeFirstResponder:]` during the click (inspector shown and hidden) | One call per click, from `NSHostingView.mouseDown` → `FocusBridge.didHitTest` → `moveFocus`; the responder is the detail column's own host (`NSHostingView<…NavigationSplitCoordinator.ColumnView…NavigationPaneModifier<ContainerStyleContext>>`) both times; nothing takes it afterwards |

**Outcome:** the shell does not take focus in mac4DSTEM, so the frozen-shell fix (item 1, owner-accepted only on that
condition) is not made. macTEM's dead keys lie in its own content or in a host its probe added; its Gate D stays open there.

## (b) The drive plans of `ui-lanes-2026-10-14/`

| Item | Seen |
|---|---|
| Readout (H1) | "Qx 31 · Qy 20 · I 0,9624091 · q 0,2408 Å⁻¹" on the pattern; q = 12.04 px × 0.02 Å⁻¹/px from the origin by hand; drops q when the pane's "Current" picker takes the room (the short variant); clears while zoomed |
| Typed apertures (H1) | Center x "40,5" → 41 and "30.4" → 30 (both separators; a changed centre snaps to whole pixels as a drag does); Outer radius stepper 16 → 17 |
| Zoom, View menu (H1/H2) | ⌘+ twice about the pointer: badge ×4; ⌘0 back to fit; View has Zoom In / Zoom Out / Zoom to Fit |
| Fit annulus (H1) | Red dashed circles at 11.2 / 28.8 px while Prepare › Ellipse correction is open; fade out on collapse; Fit Ellipse on the demo refuses ("residual is too large"), as it should on a spot pattern |
| Histogram handles, borders (H1) | Handles white on a dark halo; in Light (`-NSRequiresAquaSystemAppearance YES`) the pane edges and divider are visible |
| Export Diffraction PNG (FIG) | Panel says "Diffraction pattern · 1× · 512 × 512 pixels"; the PNG has the yellow detector ring at the typed centre, no handles, a scale bar |
| Results › Figure (FIG) | PDF: Image size greys out; panel "… · vector · 828 × 450 points"; two labelled panels, scale bars, the detector outline (no colourbar, known) |
| EDX Maps export (FIG, `--demo-spectrum-fixture`) | Al picked, a rectangle pinned: `…-maps/` holds `-Al-region.png`, `-ColorMix-region.png` and the CSV, the outline drawn; a second export went to `…-maps 2` |
| Undo (H2) | Phase mapping: Remove Si (the matrix) → ⌘Z puts it back in place as the matrix, ⇧⌘Z removes it again; Presets › Al–Mg–Si with the β″ CIF → Al + β″ × 2, ⌘Z restores Si + MgO, ⇧⌘Z re-applies |
| Warning glyphs (H2) | Orange symbol only; requirement text white (Crystal Maps, Prepare) |
| Menus, ⌥⌘I (H2) | File has New Dataset Window, Open Dataset…, Open with Options…, Open Recent, Show in Finder; ⌥⌘I hides and shows the inspector |
| Toolbar gap (H2 G) | A gap between "Compute Image" and the icon buttons |

**Found:**
1. **The detector outline thickens with zoom** (×4 → about 6 pt; the overlay sits inside the pane's zoom transform, the Fit
   annulus already divides its stroke by the zoom). Fixed after the drive in `564d0519` (tier 2), unverified on screen.
2. The colormap popover's system glass shows the bright pattern through the histogram (legibility); system material,
   recorded, not changed.
3. The first launch restored no window (the owner's last quit); File › New Dataset Window opened one and the demo loaded.
   Later launches opened a window. Recorded only.

**Not driven (stay unverified on screen):** the object table (needs a precipitate run), drop to open, ⌘. cancel, Open Recent's
contents, Full Keyboard Access to the divider and status strip, Reduce Motion, VoiceOver, the Edit menu's undo titles
(read closed only), the six frozen-shell fixes beyond the toolbar gap, the earlier rows of `status.md`'s "Unverified on screen".
