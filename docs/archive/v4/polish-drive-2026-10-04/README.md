# Polish drive — 2026-10-04 (Slot 4⅞)

A scratch Debug build of `a1a8d234` (git-archive copy, its own DerivedData), pid-pinned, window-only shots, every cited shot reviewed by
the supervisor. Drive A on a copy of the demo cube; drive B on copies of the owner's twisted_bilayer_graphene, calibrationData_bullseyeProbe
and Si-SiGe_calibrated. The first attempt (17:34–18:16) reached nothing: the screen had locked. Reports: `reportA.md`, `reportB.md`
(they name every shot; the ones kept here are 1400-px JPEGs, prefixed A- or B-).

| Item | Seen | Verdict |
|---|---|---|
| Memory strip vs `footprint` (lane M) | 342 MB vs 326 MiB; 2.4 GB vs 2245 MiB on bullseye (`A-02`) | pass |
| Open Dataset… / Preprocess with no window (M) | both enabled; a window and the open panel appear | pass |
| Open under a remembered DPC task (R) | Prepare shows the virtual image, no DPC run | pass |
| Fit key at 4× zoom; parked inner handle (M) | key fixed top-left (`A-08b`); a visible gap at inner 0 (`A-10`) | pass |
| Virtual detector without a verb, ⌘R off (F) | `A-11`; Groups keeps Group Patterns | pass |
| Groups map re-shown (R) | same map, same title | pass |
| Go to Imaging (R) | shows the previous room's Bragg vector map (`A-24`) | fail — the deferred room-switch class |
| SCAN inset beside the pattern (R2) | top-right of the diffraction pane at 1× and 4×, drag scrubs (`A-18`); 1 of 9 disks under it on the demo; on a 17 × 77 scan 118 × 534 pt over ~30 % of the pattern (`B-48`) | pass, with the tall-scan size fixed afterwards (lane P) |
| Exploratory Q kept across a room switch (N) | 0.0167649 kept with the ACOM result (`A-39`) | pass |
| A mirrored ACOM pixel | "Mirrored Yes" at (7, 87) and 5 of 8 more (`A-43`) | pass |
| Remove a saved result (S) | the live virtual image stays (`A-53`) | pass |
| Ignore Session Sidecar… dialog (S2) | names the sidecar, Reopen red, Cancel changes nothing (`A-55b`); the inspector button opens the same (`A-64`) | pass |
| Sidebar warning (S2) | full headline, one remedy line (2 visual lines), hover without the Info sentence (`A-61`) | pass |
| Promote caption (F) | no "keeping this Mac awake" (`A-64`) | pass |
| Bottom area floor (F) | stops at ≈ 140 pt (header + ~6 log rows), reopens at the floor, a far drag closes it (`A-67`) | pass |
| Preprocess form at its smallest | the window floor 915 × 692 gives a 720 × 600 sheet: ≈ 2–3 form rows, footer always visible (`A-79b`) | usable, cramped — the owner's call |
| Preprocess export voltage (V) | demo.h5 has none, so both read "Not set" (h5dump: no attribute) | consistent; the unit round trip carries the case |
| β″ legend on a run | Aluminium matrix, β″ [0 1 0], β″ [0 0 1], Not indexed, No peaks (`A-97`) | pass |
| Room switches with results held (lane J) | Strain, Orientation, Phase mapping each show their own; Strain reads "No Result Yet" after an Orientation visit with no result (`A-103`, 3×) | pass, one more symptom of the deferred class |
| ADF 3r–6r | bullseye r = 6.84: 20.4 / 40.9 px (`B-15`); graphene r = 25.3 > edge/3: ADF falls back to fractions (16–35 px, inside the BF disk) with no line saying so (`B-06`) | pass on bullseye; graphene's silent fallback registered |
| Defocus precision after Use Parallax Fit (N) | seed −663.422 Å; after a room switch and a field click the run's title says −663.422 Å, provenance −663.42 (`B-40`, `B-43`) | pass |
| SCAN inset on reconstructions (R2) | parallax BF and single-slice phase uncovered, the inset scrubs (`B-40`) | pass |
| SCAN inset after lane P (scratch build of `95359efb`, `reportP.md`) | Si-SiGe 17 × 77: 29.0 × 118.0 pt, "SCAN" on one line, rings and colour bar uncovered; a drag down the strip moves y 1 → 32 → 76 (`P-03`, `P-03b`); the demo cube still 118 × 118 | pass |
| README hero | `hero-strain-candidate.jpg` — Si-SiGe Strain ε_xx, window-only, 1470 × 923; a tall narrow map (17 × 77) | candidate — the owner's call |

No crash report, no self-resize, the demo cube byte-unchanged. New, minor (open-items): the ADF fallback is silent; the seed status line
cuts at "defo…" (hover holds it); before a run the ptychography pane is titled "Parallax aligned BF" over "No Result Yet"; the ACOM
Q-scale read-out uses a decimal point beside comma fields; shrinking the window to its floor collapses the sidebar for good; after File ›
Reopen under a DPC task Prepare shows no annulus overlay.
