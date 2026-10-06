# 056 — The Spectroscopy room becomes one window: maps first, steps in the inspector, regions live on the map

**Date:** 2026-10-06 · **Status:** accepted (owner) · **Supersedes:** the five-step room structure built under ADR 055

## Context
The owner drove the first build and called it "horrible… not intuitive at all, couldn't get to the point of having
mappings" (2026-10-06). The fault was structural, not cosmetic. The room was a five-step wizard (Spectrum image ·
Elements & maps · Regions · Quantify · Export) in the left sidebar, the map was a small square, the periodic table had
8–13 pt cells, and the spectrum spent most of its width on an empty 2–20 keV range. Velox, his reference, is one
processing window. The accepted mock v2.1 is in `docs/archive/v5/spectroscopy-mock-v2.1-2026-10-06/`.

## Decision (owner's answers, 2026-10-06)
1. **Maps own the content.** A grid of HAADF, ColorMix and one large tile per element, with the int / net / wt% / at%
   switch and the draw tools in its header. Below it, the spectrum strip, auto-zoomed to the lines, and beside it the
   quantification panel.
2. **The left sidebar is static.** It lists the rooms, and under Spectroscopy only "EDX" (later EELS), as other rooms
   list their tools. The sidecar is the one dynamic exception. No steps, regions or dataset there.
3. **The steps become inspector sections:** Elements (the periodic table), Region, Fit, Map display, Export, Expert.
   This is "true to the logic of this app".
4. **The periodic table** sits in the inspector as two bands (main groups, transition metals) with the f-block folded,
   about 22-pt cells, and states shown by fill. It fits the 248-pt narrowest column at the shell's existing 320-pt ideal
   inspector, so ADR 035 needs no change.
5. **Regions are live.** A rectangle or polygon on any map. Dragging or resizing it updates the spectrum as it moves.
   The inspector shows only the selected region's facts and a way to pin one for comparison. Never a fixed list in the
   left panel.
6. **On open,** Auto ID runs and its proposed elements are mapped, marked as proposed and not yet quantified. Nothing is
   quantified until Quantify.
7. **The quantification panel sits beside the spectrum.**

## Consequences
- The room's UI is rebuilt against a final mock (v2.1, regions live), drawn before code. The Core science (readers,
  fit, k, absorption, statistics, proposer, unlisted-line check, export) is reused unchanged.
- `UI/Spectroscopy/` is largely rewritten. The frozen shell files change only where the sidebar's room entry needs the
  "EDX" tool row (structure, not width), against the accepted mock.
- A drive of the rebuilt room is owed before any more Spectroscopy surface lands.

## Addendum 2026-10-06: the accepted picture
The owner accepted mock v2.1 (`docs/archive/v5/spectroscopy-mock-v2.1-2026-10-06/`) with these words: "Yes, build it… stay true
to the style and categories/menu logic of the app so far, keep it clean… simple, robust, pure macOS/SwiftUI, a good UI/UX
just like Velox". **Pin** freezes a copy of the live region: the copy keeps its spectrum overlaid in its own colour while
the live rectangle moves on, up to about three pins.
