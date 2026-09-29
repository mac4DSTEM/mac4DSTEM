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
