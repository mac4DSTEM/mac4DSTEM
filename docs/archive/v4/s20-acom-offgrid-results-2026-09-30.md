# S20 ACOM off-grid recovery: results (2026-09-30) — STOPPED AT THE REPRODUCTION GATE

Pre-registration: `s20-acom-offgrid-preregistration-2026-09-30.md` (committed 04d2560 before any run). Verdict: **the entry's "26 of 200"
did not reproduce, so per the registered rule the run stops; P1-P4, the dump and any proposal were NOT run. No patch.**

## What was run
`s20-acom-offgrid-gate-probe-2026-09-30.swift.txt` (this directory; copy to a `main.swift` beside `HEAD` copies of the 20 `acom` sources
in `tools/lib/sources.manifest`; `swiftc -O -package-name mac4DSTEM`; run `probe gate` and `probe gate wl`). Al fcc a = 4.0495 A, kMax 1.2,
200 templates, 32 x 128, shipped defaults; plan built with no wavelength ("nil") and with 200 kV (0.02508 A). Pattern i = template i's own
`templateSpots`, intensity = weight^(1/0.25), rotated by the stated angle, matched by the production `OrientationMatcher.match`
(CPU). Failure = winner's zone axis more than 0.5 deg from template i's. Logs (session scratchpad, not retained): `gate-nil.log`,
`gate-wl.log`, both exit 0 on their own line (`gate-nil.exit`, `gate-wl.exit`); each run 4-5 s.

## Result (gate: 20-32 failures at the off-grid rotation, 0/200 on-grid)
| Condition | on-grid 0 / 2.8125 / 5.625 / 8.4375 / 11.25 deg | off-grid 1.4 deg | sweep 0.35 x k, k = 1..16 (3200 trials) |
|---|---|---|---|
| plan, no wavelength (`gate-nil.log`) | 0 / 0 / 0 / 0 / 0 of 200 | **43 / 200** | 430 failures; per rotation 13, 20, 35, 43, 45, 37, 21, 0 (k = 8, 2.80 deg), then repeats |
| plan, 200 kV (`gate-wl.log`) | 0 / 0 / 0 / 0 / 0 of 200 | **37 / 200** | 367 failures; per rotation 11, 20, 31, 37, 35, 30, 19, 0 |

- On-grid 0/200 reproduces (five grid rotations). The failure count does not: 43 and 37 are outside 20-32, so **26 is not reproduced
  under this pattern definition and rotation.** The count is rotation-dependent (0-45 of 200 within one bin, worst near 1.75 deg), so the
  entry's 26 was measured under a rotation or pattern I do not have; the harness for it was never kept (only the entry text).
- What DOES reproduce: the entry's own worked example (template 1 -> template 160 at 1.836 deg, here 1.84) and its maximum error
  (9.3 deg, here template 46 -> 7 at 9.28 deg, both plans). Errors 1.64-9.28 deg (entry: 1.7-9.3).
- Not a reproduction, stated so nobody reads it as one: a 26-failure count would need an error threshold near 1.85 deg (26th largest
  error 1.87 deg no-wavelength, 1.82 deg 200 kV). The entry states its range as 1.7-9.3 deg, which gives 40 (no wavelength) and 34 (200 kV).
- Descriptive only, no mechanism inferred: at 1.4 deg the winner-minus-truth score gap is 0.0003-0.059 (median 0.014, no wavelength) and
  0.0001-0.056 (median 0.015, 200 kV); 6 (no wavelength) and 4 (200 kV) failing pairs are mutual (i -> j and j -> i), i.e. near-neighbour
  templates 1.7-2.3 deg apart confused for each other. Failure counts vanish at a bin-aligned rotation (2.8 deg: 0/200) and peak
  mid-bin, consistent with an azimuth-grid effect but that is exactly what P1 was written to test and was not.

## Prediction vs outcome
| Registered | Outcome |
|---|---|
| Gate: 20-32 failures at off-grid, 0/200 on-grid | 0/200 on-grid holds; 43 (nil) and 37 (200 kV) at 1.4 deg: gate NOT met |
| P1, P2, P3, P4, the dump, the fix class | not run (behind the gate); no amendment was made |

## What follows and what a refuter should attack
- The item's headline number is not a reproducible property of the shipped code as defined here: it depends on rotation and on the
  failure threshold (0.5 deg used here; the entry's is unstated). `open-items.md` should say "37-43 of 200 at 1.4 deg (2026-09-30
  probe), 0/200 on-grid, worst 9.3 deg" if it is updated, and drop "26".
- Attack the definition: is 0.5 deg the right failure line, and is the pattern (own spots, weight^4 intensities, rotation about the
  origin, origin at pixel 128) the entry's? A different intensity mapping or an in-plane rotation applied in Cartesian pixels (Float
  rounding of positions) could change the count. The `gate` mode takes only a rotation list, so the entry's exact rotation can be
  tested directly if its author's rotation is known.
- The registered next step, if the owner wants it despite the gate: amend the prereg BEFORE reading (state the new gate: e.g. accept
  37-43 as the reproduced count and restate the bar as "recover >= 90 % of the failures at 1.4 deg and across the sweep"), then run
  the dump and P1-P4 (the probe already holds the polar builder, the exact-azimuth deposition and per-ring correlation to extend).

## Part 2 (Amendments 1-2, committed bcb9cd5 / 9aa309e, precede every result below): dump, variants, real cubes
Probe `s20-acom-offgrid-probe-2-2026-09-30.swift.txt` (adds check/dump/variants/planted/p4 and a spectral scorer; rounded azimuth + 128 shifts reproduces production `templateScores` to 1e-5, 24 patterns x 200 templates, winner 24/24, both plans). Logs (scratchpad, exit 0): dump-*, variants-*, planted-*, harn-*, real/*.
| Registered claim (population 43 no-wavelength / 37 at 200 kV) | Outcome | Verdict |
|---|---|---|
| P1a truth ring-shift spread >= 2 distinct AND winner 1, >= 85 % | 33/43 = 76.7 %; 30/37 = 81.1 % (post-hoc pi-fold: 33/43 unchanged) | NOT met |
| P1b continuous score truth >= winner, >= 92 % | 43/43, 37/37 = 100 % | met |
| P2 median spot-count ratio 0.75-1.33; <= 15 % winners > 1.5x | median 1.000 both; 1/43, 0/37 | met (density refuted) |
| P3 sg down-weighting explains < 1 % of the planted <122> gap | gap 5.13 % / 6.38 % (0.35 deg, winner t80, 13.61 deg); sgWidth 1000 -> 77.8 % / 66.7 %, which also admits every \|sg\| < 0.1 reflection | UNDECIDED (confounded) |
| P4 512/1024 bins, blur held in degrees | not run: registered "only if P1 holds" and P1a failed | not run |
P1 (a AND b) is not confirmed; clause b's refutation did not fire, so the quantisation reading is not refuted either. Disclosure: `variants` and `planted` were queued with the dump, before P1 was read, so the fix-class numbers below exist although the registration made them conditional.
Factorial, failures at 1.4 deg / on-grid (5 x 200) / sweep 0.35 deg x k (3200); production = rounded azimuth, 128 shifts. Recovered counts are of the 43 / 37.
| variant | no wavelength | 200 kV |
|---|---|---|
| rounded/128 (production) | 43 / 0 / 430 | 37 / 0 / 367 |
| rounded/4x shifts | 26 / 0 / 277 (17 recovered) | 23 / 0 / 231 (14) |
| exact/128 | 65 / 0 / 294 (12 recovered, 34 new) | 57 / 0 / 232 (10, 30 new) |
| exact/4x shifts (candidate F) | 0 / 0 / 24 (43; 12 new in sweep) | 0 / 0 / 0 (37) |
Only the two together fix it. 136 planted patterns (production reproduces the recorded 40 wrong, 18.79 deg; exact/128 30 wrong, 20.10 deg): F leaves 17 wrong (all <123>, 1.39 deg), <122> 12.82 -> 0.00 deg (no wavelength) but 11.47 deg at 200 kV (17/17 wrong); no axis exact today (<100> <111> <012> <112>) becomes wrong.
F as a scratch-tree patch (exact-azimuth spectra in `OrientationPlan`, 4x zero-padded shifts in `OrientationMatcher`, Metal kernel + params, acom-matching-test scalar reference rewritten as a direct sum; 4 files, 179+/62-): acom-matching-test (Metal parity 2.4e-7, WS2 8/8), acom-orientation-test, acom-convention-test, fit-overlay-test, phase-vector-matching, parity-metric-test all exit 0. The independent convention test improves: Au median matrix error 1.25 -> 0.156 deg (in-plane <20 deg 131 -> 144/144), WS2 0.78 -> 0.156, py4DSTEM external 2.06 -> 0.84 deg (<5 deg 25 -> 27/40). Unit classes NOT run (a second xcodebuild tree cannot share the one DerivedData).
| Real cube (same detection, known-crystal Q, 200 templates, CPU) | template changed | truth check | matching time |
|---|---|---|---|
| demo 10 000 pos, kMax 1.2 | 23.9 % (median 1.64, max 3.34 deg) | A 5.03 deg both; B 6.50 both; **C [111] 0.00 -> 1.64 deg, all 2250 positions (t2 -> t198)** | 1.0 -> 4.5 s |
| demo, bank kMax 0.9 (= exporter) | 23.2 % | A 0.00 both; B 6.50 both; **C 0.00 -> 1.64 again** | 4.0 s patched |
| Thronsen A stride3, 1849 pos, no orientation truth | 5.8 % (median 2.19 deg); median score 0.5195 -> 0.5559 | none | 0.19 -> 0.87 s |
Not run (time, memory): sim_Au, WS2, Si-SiGe, Particle_1, raw Al-Mg-Si, Au_ref, bullseye.
## Verdict against the amended bar: NOT MET, NO PATCH proposed
Recovery 100 % (>= 90 %), 0 on-grid regressions, no exact axis made wrong, pinned harnesses inside tolerance: met. The last clause fails: F worsens the demo cube's truth-bearing grain C on every position, unchanged when the bank's kMax matches the exporter (so the phantom-ring account does not explain it; cause not found). Also 4.5x slower CPU matching. The scratch diff (`s20/candidate-F.patch`, `git apply --check` clean) is not a proposal; an owner weighing the synthetic and independent-test gains above grain C would need the unit classes and a refuter first.
## What a refuter should attack
Failure definition and pattern (0.5 deg, own spots, weight^4; 43/37 is that definition's count, not 26). P1a's 2 % active-ring rule: 5 of 43 truths show one distinct shift and still lose, so ring-group disagreement is not the whole story. Grain C: t198 vs t2 with noise and the exporter's spot list, or a Float tie. The 12 new sweep failures and 17 planted <123> failures (plan-dependent). Whether the patch equals the spectral probe (only harnesses were run on it, not the probe's 136/3200 grids).
