# Lane F-A — independent refuter (Gate B), 2026-10-01

Read-only Opus refuter of `slot2-fa-record-2026-10-01.md`. Its probes (scratch copies of the matcher with forward-only /
mirror-only switches, an nAzimuthal sweep) ran in the session scratchpad: `probe1-3.log`, `q.log`.

## Must-fix before row 1 lands
- **M1 — the regression's diagnosis is REFUTED as worded.** The 15 new Au-sampled failures in `acom-convention-test`
  (in-plane < 20°: 116 vs bound 120; HEAD 131) are not achiral float ties and not "mirrored across a plane, 3–5°":
  `convention-fixed3.log` shows every one is the in-plane half-turn class (in-plane 169–180°, matrix 37–60°), HEAD's
  13 failures' class. They are not ties: on the y = 0 edge (0.25 bin off-grid) the mirror pass wins 64/64 at 0.99965
  against the forward pass's correct 0.98606 (gap 0.0136); the lane's own `mirror-fixed4.log` gives sampled gaps 0.022–0.37.
  Mechanism, tested: the port deposits azimuth to the nearest bin (`OrientationPlan.swift:262`, `.rounded()`); py4DSTEM
  keeps sub-bin position (templates by linear interpolation, `crystal_ACOM.py:800-818`; experiment by a Gaussian at the
  exact qphi, `:1046-1080`). The mirror pass doubles the quantised candidates. `q.log` (18 axes × 8 angles): nAzimuthal
  128 → 131 forward / 116 both passes (the lane's numbers); 512 at the same 4.2° blur → 135 / 130. It is the S20
  quantisation class (the root of grain B) and an undocumented py4DSTEM deviation. py4DSTEM was not run on these trials.
- **M2** — `FitOverlays.swift:226` draws a mirrored win's template unmirrored (about half of generic positions): lands with row 1.
- **M3** — rows 4/5/2 had only been built with row 1 in the tree: gate them alone before committing.

## Verdicts
1. Row 1 port HOLDS: conjugate pass (equivalent to py4DSTEM's conj(T)·conj(E) up to index reversal), +π, column 1/2
   negation, strict `>` per template, Metal via −Im, `mirrored` = the winning template's flag. `tools/acom-mirror-test`'s
   truth is independent (own basis, operators, zone test). Reproduced: mirror-zone 62 → 3 of 93 wrong, sampled 3 → 9 of
   107, WS2 72 → 1; py4DSTEM's frozen 40 orientations 25 → 37 within 5° (a scratch probe, not the gate).
2. Convention regression: the number HOLDS (an independent full-matrix count gives 131 / 116), the diagnosis is REFUTED (M1).
3. Rows 4, 5, 2 HOLD; each test went red on its own mutation (`break-row4`, `break-row52`).
4. Grain B HOLDS WITH CORRECTIONS: a positive sweep (exact at every on-grid angle, a neighbour off-grid), but the cube's own
   t84 at 6.50° is not reproduced (synthetic: t106 at 3.56°); owed: rotate one B position's peaks to the nearest bin, rematch, predict t1.

## Options for the owner (row 1)
(a) land row 1 + FitOverlays, re-pin the Au bound to 116 with the quantisation reason (net 65 → 12 of 200 wrong);
(b) land row 1 and port py4DSTEM's sub-bin azimuthal deposition — the shared root of S20, grain B and this regression
(the 512-bin proxy predicts 15 → ~5; cost unmeasured; overlaps candidate F); (c) a tie rule / margin — not supported, the
gap populations overlap; (d) hold row 1 (≈ 31–36 % of random orientations stay wrong, `mirror-head3.log`).
Minor: `ACOMSession.estimatedDuration` is ≈ 2× optimistic under the ×2 CPU pass.
