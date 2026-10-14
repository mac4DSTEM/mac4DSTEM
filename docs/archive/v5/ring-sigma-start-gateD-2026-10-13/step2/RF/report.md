# Refuter RF report — ring-fit Gate D step 2 (2026-10-14)
Author: independent refuter (Sonnet 5.5), own harness and own generators. Order: ATTACK PLAN and PREDICTIONS first (this
section, written before any run), results appended below under dated headings.

## Reading before running (no run yet)
Code read: patches/core-ab.diff, HEAD fitAmorphousRing / fitBestAvailable. Conventions checked by reading: the estimator's
A, B, C coefficients and the (a+b)/2 scale equal `predictions`'s (and the generator's u,v rotation); bins are
floor(elliptical radius - inner), 1 px; 3-bin mean with edge windows of 2; crossings interpolated in bin-index units
(consistent between left and right, so the width is right); NaN bins are skipped by the mean; max(0, NaN) is 0 in Swift so a
NaN radius would skip, not trap. Suspicions to test by experiment (not asserted):
 S1 b's guard looks at min(sigma_in, sigma_out): a legitimate one-sided sharp edge (one sigma at the floor, the other fine)
    is refused; and a truly narrow ring (sigma <= ~0.35 px) is refused by construction.
 S2 a's estimator bins by ELLIPTICAL radius about the seed but the annulus is a CIRCULAR annulus about the caller's centre,
    so the edge bins hold a partial angular sample (bias at an annulus edge, narrow annulus, large eps, centre offset).
 S3 a's half-maximum is between the profile MIN and PEAK of a noisy profile; at low SNR (Poisson 10-20 counts) peak and floor
    are noise extrema, so the start can be arbitrary (worse than HEAD's 10 px?).
 S4 a's 3-bin mean and 1 px bins give sigma_eff = sqrt(s^2 + 1/12 + 2/3) -> a narrow ring (s<=0.7) starts at the 1 px floor.
 S5 a's `scales` for the ring sigmas stay (ro-ri)/4 = 10 px while the start is 1-3 px: LM damping is per-diagonal so it
    should be benign, but the finite-difference epsilon scales with it: test narrow rings.
 S6 b throws `ringWidthAtFloor` when the conic residual > 0.2 (fitBestAvailable rethrows): a user-visible new refusal on a
    pattern HEAD accepted; count them.

## Attack plan
1 Set C: plants_a.py with only SEED0 changed to 52817 (HEAD copy of the generator, lane dir). Same geometry as A (centres come
  from k), fresh noise. Own harness rf (bin/rf-{head,a,b,ab}); fitBestAvailable default arguments, plant guess+annulus.
  Counts per variant: accepted profile fits off > 1 % and > 0.1 % in (a+b)/2; b/a and theta errors; right (HEAD < 0.1 %)
  lost; thrown. Over noisy (144), clean (84) and printed/refusal tiers (printed only).
2 Poisson set P: 512x512, R in {80,140,200}, eps {1,3} %, 60 deg gap {0,1}, ring amplitude above bg in {10,20,50,200}
  counts, bg {2,5} counts, plus smooth backgrounds (constant, central exp tail, linear tilt, 1/r^2), Poisson-sampled.
3 Narrow rings N: sigma in {0.25,0.3,0.35,0.4,0.5,0.7,1.0} px, eps {1,3} %, noise {0, 1 %, 3 %} Gaussian and a Poisson pair.
4 Estimator traps T: neighbour ring inside the annulus (both sides, 0.5-1.2 amplitude), strong slopes (1/r^3 and linear),
  60 deg gap, wide rings (sigma 8-14 px), annulus edge (ring 2-6 px from the inner/outer edge), narrow annulus; for these I
  expose the estimator (lane copy of patch a with the private func made `package`) and print the start next to the true
  sigma and next to HEAD's start (ringWidth/4); and count right-HEAD fits turned wrong under a/b/ab.
5 Lanes' numbers: LAST, only if their reports have Results.
6 Code defects: by experiment (S1-S6 above).

## Predictions (written before any run)
 Item 1 (set C, 144 noisy): HEAD accepts 22-45 wrong profile fits (A: 35, B: 32 per the record, so my 144 should land
   similar). a leaves 0-4 wrong (rescues >= 85 %, fewer than "all"); b alone catches 40-65 % of the wrong ones and leaves the
   drifting kind; ab leaves 0-4. b refuses 0-2 right fits; a loses 0-2 right fits (within 0.1 % at HEAD, outside after).
   On clean (84): a and b change no model choice (<= 1 change), kept profile fits move < 0.01 % of R.
 Item 2 (Poisson): a still reduces wrong fits vs HEAD (HEAD wrong on the weakest, amplitude 10-20, perhaps 30-60 % of those);
   a is not perfect at amplitude 10 (the estimator is noise-dominated: S3) and leaves some wrong fits there; no right fit is
   turned wrong at amplitude >= 50. b refuses only dead-ring fits; refusal of a right fit < 3 %.
 Item 3 (narrow): b refuses right fits for sigma <= 0.35 (>= 50 % of those cases) and not for sigma >= 0.7 (<= 5 %); the
   refusal costs little when the conic is good (clean): conic within 0.1 % on most clean cases but not on the noisy ones.
   a's 1 px start does not hurt narrow rings (a == head on right fits) for sigma >= 0.5.
 Item 4 (traps): a's start is within a factor 2 of the true sigma in most trap plants; where it is not (neighbour merged,
   edge ring) it falls to HEAD's start (nil) or to a plausible width; I expect 0-2 right-HEAD fits turned wrong in the whole
   trap set under a; the likeliest offender: a ring 2-4 px from the annulus edge, or a neighbour ring with amplitude > 1.
 Item 6: I expect no arithmetic defect in the estimator (index conventions agree); the real risk is S1 (one-sided floor).
