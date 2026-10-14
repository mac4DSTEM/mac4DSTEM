# Refuter RF2 report — ring-fit Gate D, step 2 (2026-10-14)
Independent (Sonnet 5.5). Own parser (an2.py in this dir). Did not read lanes/F, lanes/F2; did not run or import RF's an_rf.py /
an_T.py or any lane's compare.py / an.py. RF's raw logs, generators, binaries and truth files are treated as UNVERIFIED data.
Predictions are written before each step; results are appended under dated headings.

## Predictions for step 1 (written 2026-10-14 before any parsing)
Definitions: row = one plant; "profile" = status=profile; wrong = profile and |dR| > 0.01; right = profile and |dR| < 0.001 at HEAD
(and "right lost" = right under HEAD, not right under the variant — where "not right" includes becoming a conic fallback or a throw, which
I will count separately: profile->conic, profile->wrong, ->threw). dR is (a+b)/2/R - 1; dba is the ABSOLUTE b/a error (b/a fit - true).
- C: I expect to reproduce head 29 / a 0 / b 25 / ab 0 exactly; b/a error of the wrong fits reaches several 1e-2 under HEAD.
- P: I expect wrong counts to reproduce (148 / 66 / 105 / 47) within +-3 if the lead used the same definition; the "a loses 21 right"
  is the number I distrust: it depends on whether a conic fallback counts as lost. Expect lost-by-wrongness smaller than 21.
- N: head 91, a loses ~1, b turns ~19 into conic and loses ~6 right. Expect to reproduce within +-2.
- T: head 44 wrong; a rescues 15; a loses 4 right (all neighbour). Expect to reproduce within +-2.

## Step 1 — results (2026-10-14; parser an2.py/step1.py; full table: logs/step1_summary.txt; clean-plant check: logs/step1_cleancheck.txt)
Source logs (RF's, unverified, re-parsed by me): RF/logs/{C,P,N,T}_{head,a,b,ab}.log, 275/480/280/256 rows each, rows aligned by name; truth
is in each ROW (R, ba_true, sigma_true), cross-checked against the generator's conventions (clean g0 plants land at |dR|~1e-11 under HEAD).
Definitions: wrong = status profile and |dR|>0.01; right = accepted fit (profile OR conic) with |dR|<0.001; "lost" = right at HEAD and not
right (>=0.1%) under the variant (a throw counts as lost). dba = ABSOLUTE b/a error (what the app applies).
Integrity checks (t4.py): in all four sets every profile row under b is bit-identical to HEAD's row (221/221, 392/392, 155/155, 240/240)
and every profile row under ab is identical to a's (269/269, 458/458, 221/221, 236/236); every b refusal has min(sin,sout) <= 0.30 and no
fit with min sigma <= 0.30 escaped (so b = HEAD + guard exactly, ab = a + guard exactly; refusals are the only difference).
REPRODUCED EXACTLY (my definition = lead's):
 C noisy(144): HEAD 29 wrong; a 0 and ab 0 (29/29 rescued: 27 to <0.1%, 2 to 0.1-1%; 0 right lost); b leaves 22 profile + 3 conic fallbacks
   still >1% = 25 wrong accepted fits (b catches only 7 of 29: 4 conic <1%, 3 conic >1%).  [Lead's "b leaves 25" counts the conic fallbacks.]
 P(480): HEAD 148 wrong; a 66; ab 47; b 105 profile-wrong (+9 conic fallbacks >1% = 114 wrong accepted; 1 new throw).
   a: 21 right lost (17 -> >1%, 3 -> 0.1-1%, 1 -> conic), 25 newly wrong (17 right + 8 mid); by amplitude 10/20/50/200: 8/8/5/0 lost. ✓.
   ab: 18 right lost under the any-model definition (13 profile->conic of which 3 conic are still <0.1%, 3 ->0.1-1%, 5 -> >1%).
   [Correction: counted by the same state transition as for a (R->not-R, profile only) ab loses 21, not 18; 18 is the any-model count.]
 N(280): HEAD 91 wrong; a rescues 91/91, loses 1 (right -> 0.1-1%); b refuses 106 HEAD profile fits (86 wrong, 19 right, 1 mid; 2 of the refused
   right go to a conic >1%), leaves 5 wrong profile + 2 wrong conic, loses 6 right (5 at 3% noise); ab loses 7. ✓
 T(256): HEAD 44 wrong; a rescues 15 (11 ->right, 4 ->0.1-1%), loses 4 right but all 4 stay within 1% (R->M); ✓ but see below.
CORRECTIONS / SHARPENINGS:
 T-neigh (72 plants, the only trap subset where a loses): HEAD 30 wrong; a 31 profile-wrong + 4 conic-wrong = 35 wrong accepted: a rescues
   4 (->0.1-1%) and breaks 9 (M->W), net +5 wrong; ab 22+13 = 35; b 26+4 = 30. In the trap set a does NOT cut the wrong count where the
   neighbour is in the annulus; HEAD errors there are R errors with small b/a errors (HEAD wrong with |dba|>0.01: 4 of 30; a: 10 acc fits).
 b/a (what the app applies): P: accepted fits with |dba|>0.01: HEAD 148, a 60, b 131, ab 56. C noisy: 25 / 0 / 22 / 0. N: 56 / 1 / 4 / 0.
 Clean plants (set C, 84): a converts all 25 HEAD conic fallbacks (24 gapped clean) to profile fits; for the 24 clean-gapped plants the HEAD
   conic had |dba| <= 1.7e-4 (median 7e-5) while a's profile fit has |dba| up to 1.6e-3 (median 6e-4), i.e. ~10x WORSE b/a on clean gapped
   plants. On the 59 clean profile fits kept both ways, max |Delta dR| = 1.3e-3 (10 above 1e-4), max |Delta theta| = 0.128 rad (7 above
   1e-3): the P3 clean clause (<=0.01% R, <=1e-3 rad) FAILS. (The clean plants are noise-free and geometrically identical to set A's, so this is the same evidence as lane M's, not an independent replication.)

## Step 2 — predictions (written before the spot runs)
Spot set (my own binaries bin/rf2-{head,a,b,ab} built from src/main.swift against the HEAD copy + patches via harness/build.sh under heavy.sh,
log logs/build_all.log): ALL 21 P plants right-lost under a, ALL 19 N plants right and refused under b, ALL 4 T-neigh plants right-lost
under a, the 8 P and 9 T plants that a turns M->W, and 6 C control plants (3 rescued W->R, 3 clean-gapped conic->profile). ~67 plants x 4 variants.
Prediction: every status and every dR/dba/dth/cerr/resid agrees with RF's rows to 9 significant digits (deterministic code, same source,
same pixels); I expect 0 mismatches. If a mismatch appears it will be in the *.f32 pixels (data regenerated?) or in an RF binary built
from other source; I will say which.

## Step 2 — results (spot reproduction, 2026-10-14)
Own harness src/main.swift (prints %.17g and the full profile parameters), built for head/a/b/ab from the HEAD copy + patches/EllipseCalibration.*.swift
(logs/build_all.log, exit 0). First verified that patches/EllipseCalibration.{a,b,ab}.swift are exactly HEAD's file + core-{a,b,ab}.diff
(patchcheck/: cmp identical for all three) and that HEAD's file equals `git show HEAD:` of the repo.
Re-ran 86 plants x 4 variants (C 6, P 29, N 38 [19 of them are not right-at-HEAD-profile controls: my filter caught head-conic rows too], T 13)
= 344 rows (logs/spot_{C,P,N,T}_{head,a,b,ab}.log, exit files all 0). Compared with RF's rows (status, dR, dba, dth, cerr, resid, I1, sin, sout, s0)
with step2.py -> logs/step2_compare.txt: 344 rows, 0 mismatches at 1e-9 relative (agree to the 9 significant digits RF printed).
So RF's binaries behave as the patches build, and its logs are a faithful record of {fitBestAvailable on these pixels}. NOT re-run: the other ~1000 rows
per variant (parsed only).

## Step 3 — predictions (written before the cost runs)
Own cost model cost2.py (numpy replica of predictions(); validated by reproducing the logged normalised residual at each fit).
Tests: (i) T-neigh f1.155 A0.8 plants: cost at a's fit > cost at HEAD's fit > cost in the truth basin  (RF's claim 3770 > 2366 > 1733; I expect it
to reproduce in order, magnitudes within 10%). For A1.5 the neighbour is the brighter ring, so truth is a debatable target there: I expect the
neighbour-ring basin to have the lower cost for several A1.5 plants.
(ii) P right-lost under a (21): I expect a's cost <= HEAD's cost on about half of them (a reached the model's optimum, HEAD was right by luck), and
cost(truth basin) <= cost(a) on the rest (a is stuck in a worse minimum = a genuine loss). Paired over all 480 Poisson plants I expect a's |d(b/a)|
median to be smaller than HEAD's, i.e. the net effect on the Poisson set is positive even though 17 right fits go >1%.

## Step 4 — predictions (written before the N analysis, from RF's N logs)
b's refused-right fits (19): true sigma <= 0.5 px for nearly all (the ring is narrower than a pixel-ish), fitted min sigma at the 0.25 floor or just above;
the conic fallback is within 1 % in R for nearly all (<= 3 outside), within 0.1 % for about 2/3, and its |d(b/a)| is a few 1e-3 at most.
Whether a user "sees" the loss: conic error 0.1-1 % in R and <= 1e-2 in b/a is invisible next to the 1-50 % errors of the wrong profile fits that b catches (86 in N).

## Step 4 — results (narrow rings; N logs; logs/step4_N.txt, step4.py)
- b refuses 106 HEAD profile fits in N: 86 wrong, 19 right, 1 mid. EVERY one of the 19 right ones has true sigma 0.25 or 0.30 px (10 + 9); HEAD's right fits with true
  sigma >= 0.35 (n=140) have min fitted sigma = the true sigma (0.350, 0.400, 0.500, 0.700, 1.000 medians) and none is <= 0.30. So the 0.30 threshold
  separates "genuinely sub-pixel ring" (FWHM <= 0.71 px, at or below the 0.25 floor) from everything else on this set; no right fit with sigma >= 0.35 is refused.
- The conic those 19 fall back to: |dR| max 1.14e-2, median 1.2e-4; 6 are >= 0.1 %, 2 are > 1 % (both 3 %-noise, R=60, margin 20: 1.02 %, 1.14 %); |d(b/a)| max 4.7e-3,
  median 3.0e-4. 13 of 19 stay within 0.1 %. b catches 86 wrong N fits (HEAD median |dR| 11 %, |d(b/a)| 2.3e-2): their conic is within 0.57 % (0 above 1 %).
- Verdict on item 4: refusing the sub-pixel-ring fits is a loss of <= 0.6 % / 5e-3 (b/a) typically and 1.1 % at worst, for rings narrower than a pixel;
  it is not a loss the user would see unless their data has sub-pixel rings (not P5's, which start at 2-2.75 px). The N-set as a *gate* for b is mostly a
  test of b's own definition (a sigma-at-floor guard fires on rings whose true sigma is at the floor).
- ab on N: refuses 59 of a's profile fits, 58 of them right (a-right) with true sigma 0.25 (32) or 0.30 (27): a deletes the wrong-start errors, then b refuses the
  correct sub-pixel fits that a made right. So "ab loses 7" is the cost of that refusal over right-at-HEAD ones; a alone loses 1.

## Item 5 — lane headline numbers re-derived from the lanes' raw logs (own parsers; logs/step5_P5.txt; M numbers printed by an inline script, reproduced below)
Lane M (lanes/M/logs/{head,a,b,ab}_{A,B}.log, 275 rows each, noisy tier = 144): wrong = noisy, status profile, |dR|>0.01.
  set A: head 35 / a 0 / b 20 / ab 0; b refuses 15 noisy HEAD-profile fits (15 wrong, 0 right); ab rows identical to a on 275/275 (status, dR, dba, dtheta).
  set B: head 32 / a 0 / b 16 / ab 0; b refuses 16 (16 wrong, 0 right); ab == a on 275/275.   REPRODUCED EXACTLY (claim: 35/0/20/0, 15).
  noisy max|d(b/a)|: set A head 0.508, a 0.0033, b 0.508, ab 0.0033; set B 0.468 / 0.0035 / 0.468 / 0.0035.  Clean: 25 HEAD conic fallbacks -> 84 profile under a/ab, b unchanged (as the lane says).
Lane P5 (lanes/P5/logs/{head,a,b,ab}.log + dbg/err.log): same model head vs a on 8/8 annuli (counting W1, which throws excessiveResidual in all four);
  worst |da|,|db| = 1.0e-5 px (A2), theta 1.7e-6, centre 7e-7; REPRODUCED.  a's estimator nil on 5 of the 7 annuli where it ran (W1 never reaches it:
  the conic stage throws) — lane says "5 of 8"; correction: 5 of 7 reached. Where it runs (A1, A2) the output equals HEAD's to 1e-5 px.
  What the P5 table also shows (not claimed by the lane as a finding): HEAD's profile fits on this real pattern are pathological on 4 of 7 annuli and
  the candidates reach only one of them: A4 I1=0, sigma_in 0.25 (b refuses it -> conic); A2 central sigma at the 0.25 FLOOR with I0 = 738549 (neither
  catches: b only tests the ring sigmas); W3 outer sigma 62 = the CEILING max(2, 2*outer) (neither catches); W4 inner sigma 78 = CEILING, a = 57.6 px
  outside its [29,39] annulus (neither catches). On real data a is inert (5/7 nil, 2/7 identical), so P5 carries no evidence FOR a, and b's one catch is
  a "ring-less constant" fit; ceiling-type failures stay accepted under every candidate.

## Item 6 — predictions for the estimator probe (written before running bin/est; src2/main.swift, exposed copy of patch a)
E1 (theta sign/convention): with the seed's own theta the start is within ~30 % of the true sigma on 3 %-noise rings with sigma >= 2 px; with theta negated or rotated by 90
   the start is clearly larger when a-b is comparable to the ring width (eps 3 %, R=120: a-b = 3.6 px) — i.e. the sign convention in the estimator is right, and the
   estimator is NOT insensitive to it (so a sign slip would be visible). At eps 1 % (a-b = 1.2 px) the difference is small.
E2 (narrow rings, S4): start_a = 1.0 (the floor) for every true sigma <= 0.7 and about 1.0-1.2 at sigma 1.0.
E3 (Poisson, S3): start_a/sigma_true is in [0.5, 2] for most amplitude >= 50 plants; for amplitude 10 the estimator is mostly nil or off by > 2x (noise-dominated peak/min).
E4 (annulus edge): ring within ~4 px of an annulus edge -> start_a nil (no crossing) and HEAD's start stands.

## Item 6 — results of the estimator probe (logs/est_{C,P,N,T}.log, logs/step6_est.txt; bin/est built under heavy.sh, logs/build_est.log exit 0)
E1 CONFIRMED (and my prediction on size is right): the estimator's theta convention matches the model's. On set-C noisy rings with eps 3 % (a-b = 3.6 px) start/sigma_true is 1.05
   (p10-p90 1.05-1.06) with the seed's own theta, 1.14 (1.05-1.53) with theta negated, 1.47 (1.19-2.08) with theta + pi/2, 1.14 with the circular radius; at eps 1 % all within 1.05-1.16.
   (A sign slip would therefore show; the code has none.) The start is a uniform ~5 % above sigma (3 bins mean + 1 px bins), harmless.
E2 (narrow): start_a is 1.27 px for sigma 0.25-0.4, 1.28-1.31 at 0.5-0.7, 1.44 at 1.0 — not exactly the 1 px floor I predicted but it is 4-5x the true sigma of the sub-pixel rings. N shows this is
   harmless (a rescues 91/91, loses 1): LM walks down to the floor from 1.27 px.
E3 (Poisson): the start is NOT the problem: P-a20/a50/a200 start/sigma_true in [1.05, 1.42] (p90) for 120/120 plants each; P-a10 in [0.5, 2] for 96/120, the other 24 = 24 of 24 'exp' (central-beam tail)
   backgrounds are nil (monotone profile: no crossing) and fall back to HEAD's start. So the 21 P right-lost plants under a start from a good width; if they end worse, it is where LM converges, not a bad start.
E4: T-edge nil 8/56 (ring 3 px from an annulus edge: HEAD's start stands), T-slope nil 32/64 (a is inert on half of the steep-background plants; those rows equal HEAD), T-neigh f1.155 A1.5 nil 8/8,
   T-neigh f1.07 A0.8 start = 2.13x sigma (two rings merged). T-wide 0.78-1.01x. NaN paths: none produced a trap or a NaN start in 1291 plants (no crash, no 'nan' value in any column).

## Item 6 / S1 — one-sided sharp ring edge (b's min(sigma_in, sigma_out) guard) — prediction (written before the run)
Own generator gen_s1.py -> data/plantsS1 (128 plants: R=120, eps 1/3 %, (sigma_in,sigma_out) in {(0.3,3),(3,0.3),(0.5,3),(3,0.5),(0.3,0.3),(3,3),(0.3,6),(1,3)} px, noise 0/1/3/10 %,
theta 20/112.5). The profile IS the model's own asymmetric Gaussian, so truth is exactly representable and HEAD should be right on most (not at 10 % noise).
Prediction: b refuses every plant with min sigma 0.30 (by construction) even though the sharp edge is physical; the conic fallback measures the ring by its
centroid-like position, so its |dR| for a one-sided edge (sigma_out - sigma_in = 2.7 px) is about 0.5-2 % and its |d(b/a)| a few 1e-3 — larger than for symmetric narrow rings.
a alone leaves these fits as HEAD does (start from a width between the two). ab == b on the 0.30 plants.

## S1 result (logs/S1_{head,a,b,ab}.log, logs/S1_summary.txt; 128 own plants, pixel-integrated 3x3)
Prediction (b refuses a legitimately sharp one-sided edge, conic off by 0.5-2 %) is REFUTED on pixel-integrated data: for every one-sided plant (sigma_in/out = 0.3/3, 3/0.3, 0.3/6, 0.5/3, 3/0.5, 1/3) the
HEAD fit already ends with min sigma above 0.30 (pixel integration alone broadens a 0.3 px edge to >= 0.42 px), so b never fires: b == HEAD on all of them, a == HEAD to 1e-6 (all within 0.2 %, i.e. the same
0.19 % peak-shift bias for every variant). b fires on 8 of the 16 symmetric 0.3/0.3 plants at <= 3 % noise — exactly where HEAD is WRONG (dead ring, I1=0, dR up to +35 %): b -> conic (|dR| 6e-5 on the noise-free one),
a -> profile within 1e-5. b refused 0 right fits in S1. Together with N-ss4 (pixel-integrated narrow rings: b refuses 13, all HEAD-wrong, 0 right lost) this says: b's right-fit losses in N come from POINT-SAMPLED
sigma 0.25-0.3 rings (unphysical for a pixel detector, whose box response alone gives sigma_eff >= 1/sqrt(12) = 0.29 px) — an artifact of how N was rendered. Not tested: a one-sided edge rendered point-sampled.

## Item 6 / S2 — larger centre mis-guess — prediction (written before the run)
Set C noisy+clean (228 plants) re-run with the caller's centre guess 7.8 px (6,-5) and 15.6 px (12,10) from the true centre (RF's sets use 1.6 px) — own manifests data/plantsC_G6, plantsC_G12
(symlinked pixels, only guess_row/guess_col changed). The estimator then bins by the seed ellipse about the seed centre but the samples come from a circle about the guess, so edge bins are
partial. Prediction: HEAD's wrong count on noisy rises or stays (>= 29); a still rescues most (>= 80 %) but may lose a few; b catches less than half; a's clean-plant results unchanged
(<= 1 clean plant changes class). If a collapses at the large offset (>10 % of right fits lost), that is a finding against a.

## Step 3 — results (P set; logs/step3b_P_all.txt, logs/step3_P_summary.txt, logs/step3_P_bg.txt; cost model cost2.py)
Validation of my cost replica: normalised residual recomputed from the printed parameters equals the logged `resid` to 5 decimals for every profile fit of the T-neigh and P runs (an3b/an3p).
RF's 4 P-"right lost" claim, decomposed (21 plants right at HEAD and not right under a):
 - NOT right-by-luck: in 19 of the 20 where a still returns a profile fit, a's cost is ABOVE HEAD's (a ends in a worse minimum; HEAD is within 2 % of the cost of the truth basin in 17 of 21 and the
   truth-basin optimum itself has |dR| < 0.1 % in 19 of 21). So the model's optimum IS at the truth there; a missed it. |dR| of the lost under a: median 5.7 %, p75 10 %, max 64 %; HEAD median 1.6e-4.
   |d(b/a)| under a: median 7.1e-3, p75 1.8e-2, max 0.41 (HEAD median 1.5e-4, max 4.6e-3).
 - It is a SPECIFIC failure, not scatter: 20 of the 21 are the 1/r^2 ("r2", central-beam-tail) background, 1 is a tilt background. By background kind over all P: r2: HEAD wrong 15 -> a wrong 38 (R 64 -> 49; ab: 23 W + 18 conic);
   on none / const / tilt a goes from 41/34/16 wrong to 0/0/0; on the exponential tail 42 -> 28. Right-at-HEAD lost under a on r2 by amplitude tier: a10 7/12, a20 8/12, a50 5/20, a200 0/20.
 - A low-count effect (noise 15-45 % of the ring at amplitude 10-50 counts; none at amplitude 200 = 7 %). The estimator start is fine there (1.2-1.5x sigma, E3b), so the cause is the trajectory: the narrow
   start (3.3-4.4 px) vs HEAD's wide 10 px start on a ring sitting on a falling background. Whether the cause is the slope or the noise level is tested next (S3 plants).

## S3 — slope x noise: prediction (written before the run)
Own plants data/plantsS3: R in {80,140,200}, eps {1,3} %, bg in {none, const 0.3, r2 0.4, r2 0.8, exp25 0.8} (amplitude relative to the ring's 1, at the ring radius), GAUSSIAN noise {15, 30} % of the ring amplitude,
theta {20,112.5}: 120 plants. Prediction: if the Poisson-set failure is the slope at high noise (not Poisson per se), a loses a sizeable fraction (>= 25 %) of HEAD-right plants on the r2 backgrounds and ~0 on none/const;
if instead it needs the heteroscedastic Poisson noise, a loses ~0 here. I expect the first (slope at high noise), at 60 % confidence.

## S3 — results (logs/S3_{head,a,b,ab}.log, s3an.py -> logs/S3_summary.txt, s3dba.py -> logs/S3_dba.txt; 120 own plants, Gaussian noise)
Prediction (slope x high noise, not Poisson per se) CONFIRMED: with a 1/r^2 background and Gaussian noise of 15 % / 30 % of the ring amplitude, HEAD is RIGHT on 12/12 and 11/12 (r2 0.4) and 12/12 and 11/12 (r2 0.8), while a loses
 9/12 and 8/11 (r2 0.4) and 2/12 and 5/11 (r2 0.8) of those right fits (a: 13 of 24 plants >1 % in R on r2 0.4; 8 of 24 on r2 0.8). On flat backgrounds a is the cure: none: HEAD wrong 13/24, a 0; const 0.3: 10/24 -> 0; (b leaves 7 and 5).
 On the exponential tail (exp25 0.8) a == HEAD (3 wrong both; estimator nil/inert). b == HEAD on every r2 plant (no right fit refused: b lost 0 of 100+).
 b/a (what the app applies), accepted fits |d(b/a)| > 0.01 on the 24 r2-0.4 plants: HEAD 0 (max 0.001), a 3 (max 0.080, 10 of 24 above 0.003), ab 7 (max 0.080; the conic fallbacks that b's guard substitutes for a's dead rings
 are themselves biased by the sloping background), b 0. On r2-0.8: HEAD 0, a 3 (max 0.706), ab 3 (max 0.019).
 => The registered evidence for (a) (sets A, B, and my C: flat background, no tail) cannot see this regime; the real patterns the app fits (mean pattern with a central-beam tail) are in it. Where the tail is steep enough to remove the
 half-maximum crossing, a is inert (T-slope 32/64 nil, P5 5/7 nil) and equals HEAD; where there is a crossing and the noise is >= 15 % of the ring, a is worse than HEAD.

## S4 — noise threshold for the r2 failure of (a) (logs/S4_{head,a,b,ab}.log, logs/S4_summary.txt; 48 own plants, Gaussian noise 5 / 10 %)
Not predicted in advance (added after S3 to pin where the failure starts). r2 background at 0.4 x ring: HEAD right on 24/24; a loses 4/12 at 5 % noise (all stay 0.1-1 % except one conic) and 8/12 at 10 % (4 of them
> 1 %, one with |d(b/a)| 0.396); r2 at 0.8 x ring: a == HEAD on 24/24 (the steep slope removes the half-maximum crossing, estimator nil -> HEAD's start). b == HEAD on all 48. So the failure starts at a noise of 5-10 %
of the ring amplitude with a MODERATE 1/r^2 tail, i.e. inside the registered sets' own noise range (3 / 10 %) once the background is not flat.

## Guess-offset dependence of HEAD's failure (logs/goff.txt; own manifests plantsC_G{0,1,3,6,12}; 228 set-C plants each, HEAD and a)
HEAD, set C noisy 144 (R / wrong / conic fallback), caller's centre guess at distance d from the true centre:
 d = 0 px: 111 / 12 / 21;  0.75: 106 / 20 / 18;  1.6 (RF's and macTEM's setting): 99 / 29 / 15;  3.0: 104 / 21 / 18;  7.8: 142 / 0 / 0;  15.6: 143 / 0 / 0 (1 throw).
a: 142 right + 2 mid at every distance 0-15.6 px (all 144 within 1 %). Clean 84: HEAD 25 conic fallbacks at 1.6 px, 21 at 0, 8 at 3.0, 0 at 7.8; a 84 profile fits right at all distances.
=> the 29-of-144 (20 %) prevalence is a property of the harness's 1.6 px guess, not of the method: HEAD's dead-ring/drift failure on flat-background noisy rings exists only for accurate guesses (<= ~3 px here) and
vanishes by 7.8 px. The app's guess is `aperture.center` (AppState+Calibration.swift:179, recentred on the measured beam at :112-115) — an accurate centre is the normal case, so the defect is real in the regime the app works in, but the "1 in 4"
figure must be quoted with its condition. (Mechanism not established; not claimed.) a does not share the dependence.

## Step 3 — T-neigh (80 plants; logs/step3b_T_neigh.txt, step3_Tneigh_groups.txt, step3b_T_neigh_summary.txt)
My cost replica reproduces RF's cost.py ratios on the same plant (T-neigh-f1.155-A0.8-e3-n10-t20-014: a/HEAD cost 3912/2491 = 1.570 (RF) vs (0.2044/0.1631)^2 = 1.571 (mine); HEAD/truth-start 2491/2083 = 1.196 vs 1.197).
By neighbour (fraction of R, amplitude relative to the ring) - HEAD / a states R(<0.1 %) M(0.1-1 %) W(>1 %) C1(conic >1 %):
 f0.87 A0.5 (16): HEAD M12 R4, a M16; HEAD's 4 'right' fits (T-neigh-f0.87-A0.5-e1-n3-...-040/041/064/065) have residual 0.116-0.121 vs 0.070-0.072 at the optimum (HEAD 'right by luck'); a at the optimum, |dR| 0.1 %: NOT a loss (RF's "4 right lost" are these).
 f0.87 A1 (8): HEAD W8, a M4 W4 (a helps; both above the truth basin cost 0.129).
 f0.9 A1.5 (8) and f1.155 A1.5 (8): HEAD W8 / a W8 each; the truth basin costs MORE than the returned fit (0.166 vs 0.125; 0.210 vs 0.191): a neighbour 1.5x brighter than the ring makes the truth an unfair target
   (the fit returns the brighter ring, -11.6 %; or leaves the annulus, +75 % = axis ceiling). 16 of HEAD's 44 T-wrong are these; no candidate is expected to fix them.
 f1.1 A0.8 (8): HEAD M8 (0.83 %, = the model optimum, cost equal to the truth basin: the merged neighbour displaces the optimum), a M1 W7 (1.5 %, cost +2 %): a drifts off the optimum by 0.6 %. A threshold effect plus a real small loss.
 f1.155 A0.8 (8): HEAD M2 W6 (1.2 %), a W4 + 4 conic fallbacks >1 % (7.2 %; cost 0.204 vs HEAD 0.189 vs basin 0.171; truth basin |dR| 0.02 %): REAL loss, a lands in a worse minimum (RF's claim reproduced in order and ratio).
 f1.155 A0.4 / f1.07 A0.8 / both-0.5: a >= HEAD (A0.4: 4 M -> R).
 In b/a terms T-neigh is mild: HEAD 4 of 30 wrong have |d(b/a)| > 0.01 (max 0.018); a has 10 accepted fits above 0.01 (max 0.027).

## Totals and corrected counts (all from the logs named above)
New throws (head not THREW, variant THREW) over 1995 plant-rows per variant (C,P,N,T,S1,S3,G6,G12): a 0, b 1 (P-a50), ab 1 (S3) — logs/newthrows.txt. Not verified by me: lane T's grains_12 test failure under b.
Accepted fits with |d(b/a)| > 0.01 (what the app applies) HEAD / a / b / ab: C(275) 25/0/22/0; P(480) 148/60/131/56; N(280) 56/1/4/0; T(256) 18/14/18/12 (logs/step1_summary.txt).
Lead items vs mine: C, P, N, T counts all reproduce (lead's "b leaves 25" = 22 profile + 3 conic; "ab loses 18" is the any-model count, 21 by profile-state transition); the two interpretive claims change:
 (i) T "a loses 4 right fits" = right-by-luck at HEAD (normalised residual 0.116-0.121 vs 0.070-0.072 at the optimum a reaches, i.e. SSE ~2.8x), a lands at the model optimum 0.13 % off, still within 1 %: not a loss. The real a-loss in T is f1.1/f1.155 at 0.8 amplitude (+0.6 % to +6 % in R) and 16 of 44 HEAD-wrong are unfair targets.
 (ii) P "a loses 21 right" = not luck (a's cost above HEAD's in 19/20, HEAD at the truth-basin optimum in 17/21) and not scatter: 20/21 are the 1/r^2 background, 20 of 44 right-at-HEAD plants there.
 (iii) N "b loses 6 right" = point-sampled sigma 0.25-0.30 rings (19 refused, conic within 1 % for 17); pixel-integrated narrow rings (N-ss4, S1): 0 right fits refused.

## Verdicts
a  UPHELD WITH CORRECTIONS — holds: rescues 29/29 (C), 91/91 (N), lane M 35/35 and 32/32 (A, B), 0 right lost on A, B, C, and a is insensitive to the centre-guess offset where HEAD is not. Refuted clauses: (1) "no fit within 0.1 %
   before is outside it after" — false outside A/B/C: 1/r^2-tail backgrounds with 5-30 % noise (S3, S4, P): 36 of 94 right-at-HEAD S3+S4 r2 plants lost (>= 0.1 %) and 25 of the 96 r2 plants end > 1 % off where HEAD has 0, and 20 of 44 right P r2 plants lost: real optimiser losses (cost above HEAD's);
   neighbour 0.8x at 1.1-1.155R (+0.6..6 % in R); (2) clean clause (<= 0.01 % R, <= 1e-3 rad) false on set C and in lane M: kept profile fits move to 0.13 % / 0.128 rad, clean gapped plants get a profile fit with ~10x the
   |d(b/a)| of the conic HEAD used (1.6e-3 vs 1.7e-4). Safe: flat or tilted background, any noise, accurate or poor guess, pixel-integrated rings. Not safe alone: a moderate 1/r^2 tail with noise >= 5 %; a is inert (= HEAD) on steep tails.
b  UPHELD WITH CORRECTIONS — holds: every refusal has min sigma <= 0.30; 0 right fits refused in A, B, C, P, T, S1, S3, S4 and the pixel-integrated N-ss4; 1 new throw in 1995 rows. Corrections: it removes few of HEAD's wrong
   fits (refuses 7/29 on C [4 land within 1 %, 3 do not], 15/35 on A, 16/32 on B, 43/148 on P [38 within 1 %]; leaves 22/29 profile-wrong on C), so "catches >= 10" fails out of sample (C: 7); refused 19 right fits only on point-sampled sub-pixel rings (sigma 0.25-0.30; conic 0.01-1.1 % off, b/a <= 5e-3);
   adds a throw path (conic residual > 0.2). Safe: never worse than HEAD except sub-pixel point-sampled rings; not a cure: the drifting (non-floor) failures and the ceiling failures on real data (P5 W3, W4) pass.
ab UPHELD WITH CORRECTIONS — holds: 0 wrong on A, B, C (and a's lane-M equivalence 275/275); lowest wrong count in P (47 vs a 66, b 105, HEAD 148) because b's guard converts a's dead-ring failures into conic fallbacks.
   Corrections: loses right fits in P (18) and N (7, point-sampled); on r2 tails the conic fallbacks are themselves biased (S3 r2 0.4: 7/24 fits with |d(b/a)| > 0.01, max 0.080, vs HEAD 0/24); P3/P6 clean clause as a.
   Safe: where a is safe, plus a bounded downside on tails (conic instead of >1 % profile); not safe: weak 1/r^2 tail with noise >= 5-10 % (b/a worse than HEAD).
Neither: HEAD is wrong on 12-29 of 144 flat-background noisy fits for guesses within ~3 px (P 148/480, N 91/280, S3 flat 24/48 with |dR| > 1 %), right on tails (S3/S4 r2: 0 wrong of 96 r2 plants) — "neither" is the safe choice only on tails.

## What I did NOT test
Full re-runs of C/N/T/S3 variants b and ab by my own binaries (only P,T head/a full; 86 spot plants x 4 variants; the rest parsed from RF's logs, which my spot/full reruns found faithful). Real data beyond lane P5's logs (no new run on Au_ref).
Lane T's and lane F's claims (grains_12, the fixture). Mechanism of HEAD's guess-offset dependence and of a's r2 failure (observed, not explained). A point-sampled one-sided sharp edge. r2 failure at large guess offsets.
The Poisson set's physical realism (counts 10-50 per ring pixel). Whether the app's Bragg-vector-map source (flat background) vs mean-pattern source (tail) dominates real use. Other SDK/arch builds of the maths.

## Addendum to step 2
I also re-ran ALL of P (480) and T (256) for head and a with my binaries (logs/full_{P,T}_{head,a}.log, exit 0): 1472 rows, 0 mismatches against RF's rows at 5e-9 relative (cmpfull.py -> logs/step2_full_compare.txt).
Together with the 344 spot rows: RF's P/T logs are faithful for head and a; b and ab rows were checked structurally (b profile rows == HEAD's, ab == a's, every refusal has min sigma <= 0.30) and by 86 spot plants x 4.
