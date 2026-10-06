# Spectroscopy room — first drive (2026-10-06)

Scratch build of `ac80c988` (Debug, own DerivedData), launched with `open -n`, driven by a session agent through
CGEvent clicks and AX presses; 34 window-only screenshots, the decisive ones reviewed by the supervising session
(05, 07, 08, 10, 11, 12, 13, 16, 18, 22, 23, 24-room-3, 25). The shots stay in the session scratchpad: they show the
owner's private Velox file. No crash (`log show` grep for crash/fatal/abort/exception: 0 lines).

Files: the owner's `References/EDX` Velox EMD (O, Si, Ti, Ni, Ge, In, Sn — not Al-Mg-Si; open < 10 s) and the
simulated `References/demo-edx/AlMgSi_4D_EDX.dm4`.

## Seen working
Velox opens straight into the room (five steps, summed spectrum, axis from the file, 1607 frames summed, hover
readout); periodic-table pick, line markers, tiles, ColorMix; the right-click role menu; a rectangle region drawn on
the map with its own spectrum and table; Quantify (fit, residual strip, "unvalidated", "at% ± σ · no absorption", a
bound line flagged); Expert (estimator, σ_k, axis lock); the GMS joint file opens the cube and attaches the EDX
("same scan as the 4D cube"); Quantify without a beam energy asks for one and fits once 200 is typed; seven rooms
switch; at the 915 pt minimum the layout stacks and the inspector does not clip.

## Found
| # | Shot | Finding | Kind |
|---|---|---|---|
| 1 | 10, 11 | Region 1: the window method finds Ti 3058 ± 153, the fit holds Ti at 0; the continuum lies above the data 3–20 keV, χ²ᵣ 2417 | science, diagnosed (unlisted Ge/Cu/Ga) — WP3b |
| 2 | 11, 12 | The model drops to ~1 % of the data at 1.557 keV (corrected 2026-10-06 from "≈ 1.84 keV, with escape peaks": the continuum's lower segment collapses at the uncoupled Al-edge split; escape peaks play no part) | science, diagnosed — WP3b |
| 3 | 16, 23 | Prepare shows 200 kV for the joint file; Quantify says the file gives no beam energy | wiring |
| 4 | 16, 18, 22, 24-room-3 | Status bar "Looking for an EDS spectrum image…" never clears after the attach | wiring |
| 5 | 13 | Export says "lands with quantification (WP3): there is no fit to export yet" while a fit exists | false text |
| 6 | 11, 23 | The Al weak-line warning shows on a spectrum with no Al | false text |
| 7 | 11, 23, 25 | The fit footer is cut mid-token: "Kramers×Bernstein(9 · χ²ᵣ" | presentation |
| 8 | 07, 23, 25 | Line-marker labels overprint (Ti Kα/Kβ; Mg/Al/Si Kα) | presentation |
| 9 | 05 … 25 | x axis: "keV" collides with the "20" tick; a "−0" tick | presentation |
| 10 | 05, 18 | "no fit" said three times (header, plot centre, footer) | filler |
| 11 | 11 | Provenance carries raw RSS values (33277231246 → 27299677670) | filler |
| 12 | 05 | Velox live/real time read as 0 s | reader, unchecked |
| 13 | 22, 25 | The Mg tile is not ticked into ColorMix by default | unclear |
