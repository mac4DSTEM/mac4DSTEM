# 059 — The owner's drive of the Velox landing: Compute Image returns, the glass goes to the buttons, the spectrum gets weight and colour, lines follow Velox's table, Auto ID is measured against Velox

**Date:** 2026-10-07 · **Status:** accepted (owner's findings of 12:30, verbatim in `docs/archive/v5/owner-drive-findings-2026-10-07.md`) · **Amends:** 058 §4–5, 054 §6 (line families), ADR 035 (shell materials only)

## Context
The owner drove the ADR 058 landing on SI 1339, SI 1438 and the synthetic cube at midday and gave eight findings. Two reversed this
morning's choices (Compute Image, which his own 4 October card had removed; the glass panes, which he found worse than flat columns),
the rest were gaps Velox fills. Two facts were found for the answers: the owner's EMD files carry Velox's own element table and his
selections (`Operations/ImageQuantificationOperation`, 41 of 112 files; fixture `docs/archive/v5/velox-family-table-200kV-2026-10-07.json`),
and the VeloxLite 3.22 guide, carved from his second installer, states that line choices affect maps and markers only, never the fit.

## Decisions
1. **Compute Image is back** as the Imaging verb for the virtual detector (`runVirtualDetector`, a recorded step); the live preview stays.
2. **Flat columns, glass buttons.** The sidebar and inspector panes return to the flat shell; the inspector's action buttons take the
   glass style and the toolbar verb the prominent glass, as Xcode 26 does. No pane glass. (058 §5 reversed on his word.)
3. **The spectrum has weight and colour.** Curves 1.6 pt, markers 1.2 pt with 11 pt names; the live region's outline, its handles, its
   capsule and its curve share one colour; pins keep their tints. The Show menu leaves the header: its layers are a Spectrum section of
   the inspector (curve buttons, Linear/Log, Per pixel, Windows).
4. **Zoom without AppKit**: a drag in the keV row zooms about the start energy, ⌘-drag draws a zoom box, "Zoom to range" heads the
   right-click menu after an ⌥-drag; double-click, Home, pinch and ⌃-wheel stay. A plain mouse wheel needs an AppKit event view: the
   owner's 2026-09-28 rule forbids it until he says otherwise (open-items).
5. **Every map carries a scale bar**; Maps… writes it into the PNGs or not (Export › Scale bar; the file name says which).
6. **Line families follow Velox** (replaces eXSpy's "α below beam / 2"): K while Kα ≤ 20 keV, else L, never M by default — the boundary
   Velox's table shows at 200 kV (Ru K, Rh L), measured on the owner's files only and said so in a `DEVIATION`. Per element the person may
   check α and β lines separately for the maps and the markers (Velox's "Lines used for intensity maps"); the fit keeps whole families.
   Two checked lines of one element never share a signal channel (the later window is clipped), so a summed map counts each channel
   once. A Quantify step records the chosen lines under `map_lines`. Default windows move for Z ≥ 45 only.
7. **Auto ID is measured before it is changed**: a diagnostic tool runs the proposer on every owner file that carries a Velox selection
   and reports precision and recall; the peak-based rules Velox's manual implies are pre-registered from those numbers, not built blind.

## Consequences
Five Sonnet lanes from the seam 77088f52, merged and gated as one (unit 2238 / 0 / 4, core 0, build 0) with the supervisor's Gate B on
the line rule and the overlap clip. Not driven by the session: the owner's own copy was running during the landing, and a second
instance would have fought his hands; the on-screen checks are his, listed in `docs/status.md`.
