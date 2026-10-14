# FIG fix-up after the refuter (RFIG: UPHELD WITH CORRECTIONS; report $SP/lanes/RFIG/report.md — read its MUST-FIX and NOTES)
Same rules as your brief and lanes/UI-COMMON.md (absolute paths, gate copies, heavy.sh, explicit-path commits, tier in the message).
1. MUST-FIX test gap: FigureRendering.swift:166 — dropping deviceScale from the ladder bar's unitsPerOutPixel leaves all 44 tests
   green (3x bar 320 px instead of 240; 2x right length but label "10 nm" for 5 nm). Pin bar length AND label together at 1x/2x/3x
   (the refuter suggests a pure bar plan out of drawLadderBar, ResultExport+Rendering.swift:328, plus one pixel measurement; see its
   RFIGGeom.testBarLengths in $SP/lanes/RFIG/probe-src/). Confirm the mutation now goes red.
2. MUST-FIX test gap: FigureExport.swift:192-210 — the EDX branch of figurePanels (region outlines, scanPixel bar, figureOrder) is
   untested (hasSpectrumImage false everywhere); `overlays: []` at :207 survives. Add a test with a spectrum image that pins the
   region outline and the map bar; confirm the mutation goes red.
3. Colour: FigureRendering.swift:324 resolves Color.cgColor in a light environment while the pane draws in the app's appearance —
   export colours must match the pane's (make the resolution explicit and match what the pane shows; say which appearance you pick
   and why in the code comment), fix the "pane's colour" comment if it stays approximate.
4. Notes you may take if cheap (tier 2, else list as open): the Figure's detector depends on the last room visited
   (FigureExport.swift:157) — a tick in the Figure section ("Draw the virtual detector") is the refuter's suggestion; the TIFF lacks
   an sRGB ICC profile (the PNG has one). Leave the bar-plate padding and the colourbar for later (list them).
Gate in a copy (unit + core), commit by explicit paths, tier 2, then hand back (<= 15 lines): commits, totals, what you left.
