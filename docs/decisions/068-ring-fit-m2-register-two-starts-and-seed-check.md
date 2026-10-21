# 068 — Card M2: no held ring-fit fix lands; one new Gate D item, measured on the owner's cubes first

> Moved (2026-10-21): the ring and ellipse fit (`EllipseCalibration`) is DiffractoKit's; the decision stands, the file cited below left this repo.

**Date:** 2026-10-14 · **Status:** decided by the owner (card M2, option **d**, as recommended) · **Follows:** the ring-fit
Gate D record `../_archive/mac4DSTEM/docs/archive/v5/ring-sigma-start-gateD-2026-10-13.md` (registered `ce245821`, step 2 `5594d2db`), ADR 050
(a failed reproduction gate closes an item; a new registration is a new item), ADR 065 (M1)

## Context
The Fit button's profile fit (`fitAmorphousRing` behind `fitBestAvailable`) accepts wrong ellipses on noisy rings with a
good centre guess: up to 48 % in R and 0.51 in b/a, which the app applies to every Bragg vector. Step 2 built and tested
two fixes as held diffs, and neither met its registration:
- (a), a half-maximum ring-sigma start, cured every wrong fit on flat backgrounds but failed the clean-ring clause (kept
  fits move 0.131 % of R and 0.128 rad), and out of sample, on a 1/r² background tail with 5–30 % noise, put 25 of 96 fits
  more than 1 % off where HEAD had none;
- (b), refusing a ring sigma at its 0.25 px floor, refused no right pixel-integrated fit but barely moved b/a (set C: 25 → 22
  fits off by more than 0.01), and turned `tools/harnesses/ellipse-calibration-test` red (`grains_12_one_annulus`);
- (ab) equals (a) where (a) works, and its conic fallbacks are biased on the tails.
Two leads came out of the runs, both read off the same logs (in-sample, thresholds unmeasured): keeping the lower-cost fit of
the two starts (80 wrong of 2009 logged rings, against HEAD 414 and (a) 135; 8 of 441 disagreeing pairs violate the cost
order), and refusing a profile fit whose radius left the conic seed by more than 5 % (333 of 379 wrong HEAD fits flagged,
4 of 1155 right ones). Card: `../_archive/mac4DSTEM/docs/archive/v5/owner-decisions-2026-10-14-ring-sigma-m2.json`.

## Decisions
1. **None of the held diffs lands.** `core-{a,b,ab}.diff` and the fixture tests stay in the record as evidence; the
   step-2 item is closed as not met (ADR 050). The defect stays in `open-items.md` until a fix lands.
2. **One new Gate D item, in this order:**
   1. **Measure 2–3 of the owner's cubes first** (a mean pattern and a Bragg-vector-map source; HEAD, (a) and (b), with
      the P5 harness), to learn which background his data has: flat (HEAD's failure) or tailed ((a)'s failure).
   2. **Register before any run:** fit from both starts and keep the lower cost; the floor guard; a seed-consistency check
      whose threshold is measured before it is set; each also gated alone. Sets A, B, C, P, N, T, S3, S4 (regenerated from
      the record's `step2/` generators), Au_ref, the owner's cubes and `tools/harnesses/ellipse-calibration-test`; the fixture plants
      from `step2/F2/`; a fresh refuter.
   3. **A card** if the result changes a number the owner sees.
3. **Until it passes, the Fit stays as it is.** v5.0 is not released before this is settled (owner, 2026-10-13).

## Consequences
- A landed two-start fit runs two profile fits per click instead of one.
- If the floor guard is in the landed form, the `grains_12_one_annulus` expectation ("fit, isotropic") comes back to the
  owner as a decision: the Fit would refuse a 12-spot pattern whose wrong circle happens to carry the right b/a.
- macTEM copies `EllipseCalibration.swift` verbatim; it hears of the change when it lands.
