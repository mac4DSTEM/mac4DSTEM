# Refuter RF3 report — ring-fit two-start Gate D, step (ii) (2026-10-14)
Independent (Sonnet 5.5). Own parser (lanes/RF3/p1.py etc.). Did not read lanes/G, ii/analyse_ii.py, ii/an_partial.py, analysis-ii.txt,
extra-ii.txt, nor the repo's step-ii/G or step-ii/runs analysis. Read: the record, patches/EllipseCalibration.{head,cbs}.swift (diff),
patches2/{master.swift,gen.py}, lanes/RF2/{src/main.swift,report.md (first 150 lines)}, AppState+Calibration.swift (the one app caller).
Predictions are written before each step; results appended under dated headings. Numbers only from logs named.

## Predictions for step 1 (written 2026-10-14 after reading the code, before parsing any ii/logs row)
Definitions: row = one plant; wrong = accepted fit (profile OR conic) with |(a+b)/2/R - 1| > 0.01; right <= 0.001; "right lost" = right
under head and not right under the variant (a throw counts as lost); "newly wrong" = not wrong under head, wrong under the variant;
new throw = THREW under the variant, not under head; dba = ABSOLUTE b/a error (what the app applies).
- X0 (Q0 refactor): `none` == head on every numeric field of every row of all 8 sets (0 mismatches at full printed precision). `b2`
  == step 2's `b` row for row (same status, dR, dba). Possible exception: the `fallback=` message text only (not numeric).
- X1 (c is a selector): every c row equals either the head row or the a row exactly (c = min-cost of the two starts, nothing else).
  Same for cb = {head row, a row, conic}, etc. If this fails the registration's description of c is incomplete.
- X2 (Q1, c): total wrong over 2009 plants within 80-105 (registered <= 90: I give 55 % that it holds). Right lost <= 10 holds
  (most of a's 21 P right-lost are r2 plants where a's cost is above head's). Newly wrong <= 5 is the one I doubt (T-neigh: a's M->W 9;
  c keeps head's fit only if head's cost is lower, which RF2 showed for 19 of 20 on P-r2 but not measured on T-neigh): I predict 3-12.
  S3/S4 1/r2 tier: wrong <= 3 holds for c; right lost <= 2 holds.
- X3 (Q2, b2): REFUTES "refuses no right fit": RF2 found b refuses 19 right fits (true sigma 0.25 / 0.30, point-sampled N set) and loses 6.
  b2 == b so Q2 does not hold on N as worded (refusal of a right profile fit); whether the *conic* fallback stays right is separate.
- X4 (Q3, s): flags ~ 55-70 % of head's wrong fits over all sets; refuses >= 1 right fit on T (traps) and/or S3/S4 (1/r2 tail bias in the
  conic seed): I expect Q3's "<= 2 on S3 + S4" and "0 on any set" to fail with 3-15 refused right fits, mostly on T-slope/T-neigh and S3/S4.
- X5 (Q4, cbs): wrong <= c's holds; right lost <= c's + 2 FAILS (N: b2's 6 right lost + s's); "b/a > 0.01 on fewer plants than any
  other variant": holds or ties (cs / cb); not strictly fewer than all.
- X6 (item 2): there are 10-40 plants (of 2009) where c's fit is farther from truth than the other start's (|dR| difference > 1e-3),
  concentrated in T (gapped rings with a gap-less model, neighbour rings) and the clean-gapped tier of A/B/C (sub-0.2 % differences);
  the b/a damage at worst a few 1e-2 (not 0.1+).
- X7 (item 4): there exist plants where cbs is worse than c AND worse than b2 and s alone, by construction (start 1 right but refused by
  a guard at its edge [sigma 0.30, seed 8 %]; start 2 wrong but passes): expect 1-10 such plants, mostly N (point-sampled sigma 0.25-0.30)
  and T-neigh. On the real sources the cbs changes beyond Au A4 / W4 / NiCu R3: none expected.
- X8 (real data): the s refusal of Au W4 is right (ring at 57.6 px outside [29,39]); a *conic seed bias* case on the WS2 map (S4)
  or Au mean (tailed) where the profile is right and the 8 % check refuses it: I expect none refused at 8 % on the six real sources,
  but small-R rings (NiCu R~10 px on a 32 px detector: 8 % = 0.8 px) are the risk; I will check the seed departure of every real fit.

## Step 1 results (2009 rows x 10 variants, ii/logs; my parser lib.py + p1..p14, outputs in lanes/RF3/out/p*.txt) — written before step 3
(Parsed with my own code after predictions above. HEAD 414 wrong / a 135 reproduce the session's registered numbers independently.)
X0 HELD: `none` == `head` on 2009/2009 rows (all numeric fields exactly, error/fallback text identical); `b2` == `b` 2009/2009 (out/p2.txt).
X1 HELD: every c row equals the head row or the a row exactly (0 of 2009 equal to neither); cb in {head,a,b}, cs in {head,a,s}, cbs in {head,a,b,s,c}.
Totals over 2009 (out/p1.txt): wrong head 414 / a 135 / b 251 / c 80 / b2 251 / s 181 / cb 79 / cs 48 / cbs 50; right 1401 / 1773 / 1468 / 1830 /
 1468 / 1452 / 1814 / 1830 / 1815; right lost vs head: a 62, c 5, b2 6, s 0, cb 11, cs 5, cbs 11; newly wrong: c 3, b2 2, s 0, cb 5, cs 1, cbs 3;
 new throws: s 13, cs 9, cbs 9, b2 1, c 0; accepted fits with |d(b/a)|>0.01: head 319, a 85, c 58, b2 225, s 132, cb 59, cs 40, cbs 40.
Q1 (c): wrong 80 <= 90 HELD; right lost 5 <= 10 HELD (1 P, 4 T-neigh0.87 to 1.2-1.3 permille, all still within 0.1 %-1 %); newly wrong 3 <= 5 HELD but
 the 3 are the worst failures in the study (below); S3 wrong 3 <= 3 HELD, S4 0; S3/S4 right lost 0 HELD. Real sources: c changes no model; moves b/a <= 4e-4 HELD.
Q2 (b2): "refuses no right fit on any set" NOT HELD: N set, 19 right head fits refused (4 -> M, 13 stay R, 2 -> W); right lost 6 (all N, point-sampled
 sigma 0.25/0.30 rings; known from step 2 RF2). Real sources HELD (refuses Au A4 and Ni65Cu35 R3 only).
Q3 (s): 0 right fit refused on any of the 8 sets HELD (in 2009 plants; S3 12 of 27, S4 0 of 0 wrong); flags 268 of 414 head-wrong fits = 64.7 % >= 60 % HELD
 (per set A 24/36, B 24/33, C 23/30, P 110/153, N 56/91, T 19/44, S3 12/27). Real sources HELD (A4 13.4 %, W4 71.7 %). BUT s alone creates 13 new throws (P),
 all plants where head's wrong fit (dR -10 to +33 %, dba -0.17 to -0.57) is replaced by a refusal because the conic residual is 0.24-0.27 > 0.2.
Q4 (cbs): wrong 50 <= c's 80 HELD; right lost 11 <= c's+2 = 7 NOT HELD (+6, all N from b2); "b/a>0.01 on fewer plants than any other variant" NOT HELD
 as worded (cbs 40 == cs 40, tie; both fewer than every other variant). Real sources HELD.

## Step 3 — predictions for my own small-ring tail set Z (written 2026-10-14 BEFORE parsing logs/Z_*.log; the runs finished but were not read)
Set Z (lanes/RF3/gen_z.py -> data/plantsZ, 384 plants): 96x96, R in {10,17.5,25,34} px, ring sigma {1.5,2.5}, eps {1,3 %}, central beam (sigma 2.75, 100x ring)
+ 1/r^2 tail whose value AT THE RING is {0.1, 0.5, 1.5} x ring peak, noise {1,3 %} of ring peak, Au-like annuli (R-5,R+3) and (R-6,R+5), no gap.
Real-pattern geometry (small R, annulus width / R of 0.5-1) that none of step 2's sets (R 80-200, annulus +-20) covers. Variants rf3-{none,a,c,s,b2,cbs}.
- Z1: the conic seed is biased by more than the 3.7 % (S3) / 5.2 % (T-slope) of the registered sets: p90 |seed dR| >= 6 %, max >= 15 % at R=10 with tail 1.5.
- Z2: s (and so cs, cbs) refuses RIGHT head fits here: >= 5 of the plants where head's profile fit is right (<=0.1 %); the 8 % constant is a property of R 80-200.
- Z3: where s refuses a right fit, the conic it falls back to is worse in b/a than the right profile fit (|dba| ratio >= 3 median).
- Z4: HEAD's wrong count is lower than on the registered sets (smooth noise, no gap) but c/a improve it; c == a on the large majority.

## Step 3b — prediction for set E (steeper exponential tails; written before generating/running)
Set E (gen_e.py -> data/plantsE, 20 plants): the registered worst tail is T-slope exp25 amplitude 2 (seed bias 5.2 %, right-fit move 5.4 %).
E: amplitude 2, 3, 4, 6, 10 (at the ring, decay 25 px), R 120, sigma 3, noise 3 %, eps 1/3 %. Prediction: seed bias and right-fit move grow roughly
linearly in the amplitude, crossing 8 % at an amplitude of 3-4; from there s refuses the profile fit and falls back to a conic that is biased
as much as the seed (|dR| >= 8 %), so the 'refusal' is a WRONG answer (conic dR ~ -8..-20 %) where the head profile fit is within 1 %.

## Step 3c — Z and E results were written above in out/p16_Z.txt, p19_E.txt; predictions Z1-Z4 and E: see "Results of steps 3 and 3b" below.
## Step 3d — prediction for set X (wide annulus relative to R; written before generating/running)
Z/E used annuli of +-20 px on R 120 (+-17 %) or (R-5, R+3)/(R-6, R+5) at R 17.5-34 (+-25-35 %). Real mean patterns use wider ones (Au W1 4-14, W2 12-22; the
code's own default bounds run 0.5 inner to 1.5 outer). Set X (gen_x.py -> data/plantsX): R in {17.5, 25, 34}, annulus (0.45R, 1.45R), tail at the ring {0.5, 1.5, 4} x ring
peak, sigma 2.5, eps 1/3 %, noise 1/3 %, central beam as Z, no gap. Prediction: the seed bias grows with the annulus half-width: p90 >= 8 %, max >= 12 % at tail 4;
s then refuses RIGHT head fits (>= 5 plants) and the conic falls back with |dba| >= 3x the profile fit's.

## Step 3d (cont.) — correction of my own set Y before it is used
Y (gen_y.py, 96 x 96 image, R up to 60) was INVALID for R = 60: a 60 px ring does not fit a 96 px image (only four corner arcs). I discovered this while reading its
result (R60: seed bias 11-18 %, head right, s refuses 8), so that result is withdrawn and set Y2 replaces it (image side = 2*(1.35 R + 10), full rings).
Prediction for Y2 (written before generating): the bias grows with R at fixed sigma and tail because the tail's share of the annular intensity grows as R^2 vs the
ring's R. At R = 60, annulus +-35 %, tail 0.3: seed |dR| >= 5 %; at +-50 % >= 8 %; s then refuses right head fits (a few plants at the widest annuli); at +-15 % none.

## Step 3e — Y withdrawn, Y2 result, and the Bragg-vector-map regime for the 0.30 px guard (predictions written before the runs)
Y2 (full rings, half-width 15-50 % of R, R 30/60/100, tail 0.1-0.7): out/p16_Y2.txt. Prediction written above (seed bias >= 5 %) is REFUTED: seed |dR| max 1.7 %,
right fits' departure max 1.8 %, s/cbs refuse 0 right fits (Y2: head wrong 10 / c 3 / cbs 2). The invalid Y's 11-18 % seed bias came from a ring clipped by the image
edge (only four corner arcs, the tail carries the angular coverage); it is kept below only as a labelled constructed case.
Set V (gen_v.py -> data/plantsV): the app's Fit runs on the Bragg-vector map when vectors exist: peaks deposited BILINEARLY (DiskDetection.swift:746) -> a ring of exact
point peaks is a triangle-filtered delta of sigma = 1/sqrt(6) = 0.408 px before any scatter. 128 x 128 map, R in {20, 35, 50}, 2000 ring peaks, radial scatter s in
{0, 0.05, 0.15, 0.3} px, eps 1/3 %, theta 20/112.5, 10 % stray peaks, annuli R +- 3 and R +- 6. Prediction: the fitted min(sigma_in, sigma_out) of right fits is 0.35-0.45
at s <= 0.05 (the S4 map's 0.37 is the lowest real value); b2 refuses 0-6 of the 24 plants with s <= 0.05 (those with min sigma <= 0.30 from estimation noise)
and refuses right fits only there; HEAD is right on >= 80 % of all.

## Step 6 — predictions for the real-source annulus sweep (written before running)
Sweep: for each step-(i) annulus of Au_ref mean (8), WS2 mean (S3, 10), WS2 py4DSTEM map (S4, 10), Ni65Cu35 mean (S5, 6) shift inner and outer independently by -2,-1,0,+1,+2 px
(25 annuli per base, inner >= 1, width >= 3); no truth: the check is agreement of b/a among the fits of one ring (consensus = median over fits that head and cbs both accept unchanged).
Variants fit-{head,none,c,b2,s,cbs} built by me from cubes/harness/main.swift (the session's runs2 logs reproduced byte for byte first: 36 of 36 files).
- W1: s refuses <= 3 % of annuli whose head fit lies within 0.01 of the consensus b/a (healthy fits); cbs's b2 refuses <= 3 % of those.
- W2: where cbs differs from head by more than 0.005 in b/a, cbs is closer to the consensus in >= 70 % of the annuli; no cbs result lies > 0.03 from the consensus where head lay within 0.01.
- W3: c moves b/a by <= 0.005 on >= 95 % of annuli; the exceptions are Au_ref's (tailed, 64 px) annuli.

## Results of steps 2, 3, 3b-3e, 4, 5, 6 (2026-10-14; every number from a log named in out/ or logs/; scripts p1..p34, lib.py, swlib.py)

### Independence of my evidence
- My harness rf3 (src/main.swift; own build of none/a/c/s/b2/cbs via the session's harness/build.sh from patches/EllipseCalibration.<v>.swift) reproduces the session's ii/logs
  rows with 0 mismatches at 1e-9 relative on S4, S3, T, N, C, P for none/a/c (out/p27*.txt; 2009-of-2009 for 3 variants where run). patches/*.swift == gen.py(master.swift) for
  none c b2 s cb cs cbs (cmp), head patch == `git show HEAD:` file, archive master.swift == scratch master.swift.
- My own builds of the real-source harness (cubes/harness/main.swift) reproduce the session's cubes/runs2 ROW lines byte for byte: 36 of 36 files (au s1 s2 s3 s4 s5 x head none c b2 s cbs).
- COUNT CORRECTION: the 2009 rows are 1747 independent plants. Sets A, B, C share 275 names; the 131 non-noisy plants (clean 84 + 47 special tiers) are three identical copies
  (same head result in all three), only the 144 noisy plants differ by noise draw (out via p28). Independent-plant tallies: wrong head 412 / c 78 / cbs 48 (rows: 414 / 80 / 50).
  The 15 "clean, c farther" rows below are 5 designs x 3 copies.

### Item 2 — c picks a fit farther from truth (out/p3.txt, p14.txt, p4.txt, p11.txt, p25.txt)
- c is exactly min-residual of {head-start fit, a-start fit}: 1668 of 1668 differing profile pairs agree with the lower `resid`; 4 exact ties (first start kept).
- Of 1876 plants where the two starts differ at all (557 differ materially: |dR| by 1e-3 or |dba| by 2e-3) c picks the closer (in |dR|) in 526, farther in 31 (5.6 %).
  38 plants in all have c farther by the looser test: P 22, clean-gapped 15 (5 designs x 3), T 1.
- Both wrong, c farther: 16 plants (P, gapped 1/r^2 and exp tails at 10-20 counts); extra |dba| vs the other start: median 0.306, max 0.389.
- c WRONG while the other start is within 1 %: 4 plants (the Q1 "newly wrong" are 3 of them):
    P-a10-R200-e1-g60-r28-423   head dR -0.0060 dba -0.0175  ->  c dR +0.200 dba -0.403 dth 0.367 (head 0.249); cost 0.1152 vs 0.1347 (15 % LOWER)
    P-a20-R140-e1-g60-r28-108   head dR -0.0022 dba -0.0061  ->  c dR -0.070 dba -0.108 dth 0.385 (head 0.168)
    P-a20-R140-e3-g60-r28-148   head dR -0.0015 dba -0.0033  ->  c dR -0.079 dba -0.102 dth 0.529 (head 0.100)
    P-a50-R140-e3-g60-r28-393   head start dR +0.0154 dba +0.019 (a-start refused to a conic dR +0.0019 dba +0.0046; c cannot choose the conic)
- Clean, noise-free, 60 degree gap (15 rows = 5 designs): c's b/a error 0.0025-0.0033 against 0.0003-0.0005 at the head fit (the model optimum of a gap-less model is the biased one).
  At 1 % ellipticity that is 25-33 % of the distortion. Known from lane M, not new, but c makes it the rule where HEAD was luckily better.
- Cell P / gap 60 / 1/r^2 tail (48 plants): wrong head 14, a 21, c 16, cbs 5; mean |dba| 0.048 / 0.151 / 0.109 / 0.021; at amplitude 10 (12 plants) head W11 median |dba| 0.175,
  c = a: W12 median 0.452 (cbs W3 + 1 refusal, median 0.022). So on gapped, low-count 1/r^2 tails c is NOT better than HEAD; the headline 414 -> 80 hides this cell.
  Cell P / gap 60 / exp tail: head 36 wrong, c 24, cbs 7 (+8 refusals).
- Applied-quantity view (b/a and theta are what the correction uses, CalibrationSession.swift:98): accepted fits with |dba| > 0.01: head 319, a 85, c 58, b2 225, s 132, cb 59, cs 40, cbs 40;
  of the head-bad ones c rescues 263 and newly breaks 2 (P-108, P-148); theta error > 0.3 rad (fits with ellipticity >= 1 %): head 198, a 58, c 31, cbs 27 (out/p21.txt, p23.txt).
  The registered "wrong" (|dR| > 1 %) is a proxy for this: 21 cbs-accepted fits are within 1 % in R and still > 0.01 in b/a (c: 9, head: 20; out/p20.txt), mostly conic fallbacks.

### Item 3 — the seed check out of sample (out/p12*.txt, p15*.txt, p16_*.txt, p19_E.txt, p22.txt, p31.txt, p32.txt)
Prediction misses: my Z1/Z2 (small-ring tail set Z) and E, Y2 predictions were wrong (the seed is biased far less than I predicted: Z max 4.2 %, E saturates at 5.2-5.9 %, Y2 max 1.7 %).
- Synthetic: over 4614 right profile fits (|dR| <= 0.1 %) of head/a/c on S3 S4 T N C P Z E V Y2 the largest departure from the conic seed is 5.44 % (T-slope exp25, amplitude 2),
  30 fits are above 5 %, none above 6 %; 455 mid fits (0.1-1 %) peak at 7.1 % (T). s refused 0 right fits on A B C P N T S3 S4 (ii logs), 0 on Z (227), Y2 (104), V (37). Margin to 8 %: 2.6 points (0.9 for mid fits).
- Within-sample vs out-of-sample: S3/S4 are step-2 data (ok); the real sources at the step-(i) annuli hold Q3.
- THE FAILURE, on the owner's real Au_ref pattern, not in any registered set: annulus-shift sweep (each step-(i) annulus with inner and outer moved by -2..+2 px; 726 annuli over Au_ref mean 200, WS2 mean 224,
  WS2 py4DSTEM map 188, Ni65Cu35 114; truth-free). Au_ref ring A1/W1 (R ~ 10.3 px): HEAD gives 24 profile fits with radius 10.24-10.65 px and b/a 0.9676-0.9783 (consistent); the conic seed of
  the same annuli swings 9.14-11.51 px (b/a 0.940-0.993, residual 0.215-0.398, i.e. over the 0.2 cap). s refuses 5 of the 24 (departures 8.1, 9.8, 12.2, 13.7, 9.2 %): rad 10.31-10.46, b/a 0.9732-0.9783,
  inside the kept fits' range; all 5 become a HARD REFUSAL ("moved the ring x %"), because the conic is over its cap so there is no fallback. Same on W3 (3-4 of 25: rad 25.28-26.0, b/a 0.966-0.981
  against family median 24.87 / 0.9826), A3/W2 1 each (one of these refusals is a real outlier: A2 rad 13.7 b/a 0.84), WS2 mean R3w 2 of 34 (conic 9-12 % low, b/a within 0.002).
  Totals: cbs/s newly refuse 14 of 494 annuli HEAD fits (all Au_ref; 9 consistent with their neighbours: A1 5, W3 3, W2 1; 5 outliers/junk: A2, A3/W3 (same annulus 19-31, R 19.5), W4 x2); b2 refuses 1.
  Conclusion: "far from the conic seed" is the right fit on a real ring when the conic residual exceeds 0.2 (4 of 7 Au_ref step-(i) annuli); the 8 % rule has no way to tell.
- Counterfactual from logs (not run as code): ii s-refusals by the conic residual of the seed: 255 with cres <= 0.2 (all head-wrong), 13 with cres > 0.2 (all head-wrong; these are exactly the 13 new throws);
  all 8 refused-consistent Au_ref fits have cres 0.215-0.398. A seed check that acts only when the conic residual is <= 0.2 keeps 255 of 268 synthetic catches and none of the Au refusals (and A4/W4
  at cres 0.124/0.154 stay refused). It would also give back the 13 P plants to HEAD's wrong answer.
- Is the conic any better? s alone: 255 refusals with a conic fallback; |dba| smaller than the refused fit's in 230, same in 13, worse in 12 (P const-tail plants whose refused fit had R off 7-12 % but b/a nearly right,
  conic dba +0.013-0.015 = half the 3 % ellipticity). On tails the conic's own b/a bias is 0.010-0.025 (S3 p50 0.007, T max 0.025, S4 p50 0.0105): a refusal swaps a wrong fit for a b/a good to ~0.01-0.02.
- 13 new throws under s (9 under cs/cbs): all P plants where head's profile fit is wrong (dR -10..+33 %, dba -0.17..-0.57) and the conic residual is 0.24-0.27 (> 0.2): the Fit now says no instead of applying
  a wrong ellipse. I count that as a gain, but it IS a behaviour change on 'broad ring' fits that the code comment (fitBestAvailable) says should survive.

### Item 4 — guards' order and per-start hand-over (out/p8.txt, p9.txt, p24_handover.txt, p16_Y.txt)
- Strict test (cbs worse than c AND b2 AND s, |dR| +1e-3 or |dba| +2e-3, all accepted): 0 plants in the 2009 rows; the registered Q4 "wrong <= c's" holds (50 vs 80).
- Hand-over cases (a refused lower-cost start passes the choice to a higher-cost start that passes the guards), all P gapped tails (out/p24_handover.txt):
    -107/-227/-387/-427 (exp tails): head start dR +0.21..+0.28 (departs +21..+28 %, refused by s); a-start dR -0.05..-0.08, dba -0.068..-0.116, departing -5.0..-7.9 % (inside 8 %): cbs accepts it;
      s ALONE returns the conic: dR -0.002..-0.007, dba +0.004..+0.020. cbs is worse than s alone by 0.05-0.11 in b/a (and still better than c/head's dba -0.42..-0.47).
    -063/-263/-303 (1/r^2): s alone refuses (THREW); cbs accepts the a-start fit (dR -0.057..-0.070, dba -0.195..-0.208, departing -6.8..-7.9 %).
    -148: the a-start fit departs -8.1 % and is refused by 0.1 point; -108: departs -7.2 %, accepted: dba -0.108 where b2 and s alone give -0.006. A hard edge in a region where wrong fits
      (5-8 %) and right fits (up to 5.4 %) overlap: no threshold separates them.
- Constructed (labelled): set Y (a ring clipped by the 96 px image so only four corner arcs show, R 60, tail 0.3, annulus +-35 %; kept as a constructed case, not a representative one): plant
  Z-R60-s1.5-e1-t0.3-n3-X-th20-150: conic seed -13.8 % (cres 0.297); head, c, b2 are RIGHT (dR -2.7e-5, dba +0.0018, resid 0.0247, departing +16 %); s alone refuses (THREW); the a-start is a DEAD RING
  (I1 = 0, sigma 5.6/6.5 px, dR -0.191, resid 0.151, departing -6.1 %), which b2 cannot see (its test is sigma <= 0.30) and the seed check passes: cbs accepts it. cbs worse than c, b2 and s alone.
  In Y 2 of 192 plants end this way under cbs; none in the 2009 plants (every I1 = 0 fit there has sigma <= 0.30: 132 of 132 under head; 0 survive in cbs).

### Item 5 — code read (patches/EllipseCalibration.cbs.swift, master.swift)
- `none` == HEAD: exact on 2009 rows x 8 sets and on the 6 real sources (incl. error text). Q0 HELD; b2 == step 2's b on 2009 rows.
- refine(start) captures samples/scales/initial/centre limits by reference; the shadowed `var parameters` is local; `starts` is built from the outer `let parameters`: no leakage found. Guards order:
  residual, centre/axis ratio, sigma floor, seed departure: only the message differs by order.
- Both starts fail -> the FIRST start's error is thrown (firstError), which may not be the more informative (e.g. excessiveResidual of the head start while the a-start died on the seed check).
  When fitBestAvailable's conic residual is over 0.2 that error is the Fit's answer: the 14 real Au_ref and 9 synthetic new refusals.
- `fit.normalizedResidual < best?.normalizedResidual ?? .infinity`: `??` binds tighter than `<`, as intended; strict `<` keeps the first start on ties (4 exact ties in 1672 pairs); NaN residual/departure cannot pass
  (isFinite guard; `NaN <= 0.08` is false). Half-maximum estimator: nil without a crossing on both sides (annulus edge, monotone tails) -> single start (head == a on 133 of the 2009 rows).
- ringWidthAtFloor reads "fell to the 0.25 px floor" but fires at <= 0.30 (a fit at 0.28 reads wrong). The only handler of FitError cases outside Core is CalibrationSession.refuseEllipseFit (coverage only): new cases
  cannot break a switch.
- 0.30 px: BVM rings deposited bilinearly have a floor sigma of 1/sqrt(6) = 0.41 px: my V set (48 BVM-like plants) fits min sigma median 0.42 (p25 0.41) at zero scatter: margin 0.11 px, b2 refused 1 (a head-wrong dead ring).
  Real WS2 map S4: fitted min sigma as low as 0.35-0.37 on the step-(i) annuli; in the annulus sweep 25 of 170 healthy-looking S4 head fits end at the 0.25 floor with small I1 and b2 turns them into conics:
  b/a change <= 0.003 (the map is circular to 0.002), so no harm but no margin either.
- Cost: +25 % wall time (9 noisy 512 x 512 plants 6.9 s head, 8.7 s c, 8.8 s cbs; Au_ref 0.34 s -> 0.38 s; S4 0.31 -> 0.51 s per the session's own timings).

### Item 6 — real data, truth-free (out/p7.txt, p29-p34, runs3/)
- Step-(i) annuli: c moves b/a by <= 4e-4 (S3 R1, R1w, R2w; theta moves are meaningless at b/a 0.9997); c is inert in the sweep too (1 of 494 accepted annuli moves b/a by > 0.005).
- b2 catches exactly Au A4 and Ni65Cu35 R3; s catches A4 (13.4 %) and W4 (71.7 %): Q2/Q3/Q4 real-source parts HELD. Au A4 (dead ring b/a 0.9359): cbs gives the conic 0.9974, the unflagged Au fits are 0.9712-0.9846,
  so the replacement is 0.013-0.026 above them where HEAD was 0.037-0.049 below; W4 (b/a 0.9545) -> conic 0.9855 (inside the cluster). Ni65Cu35 R3: 0.9473 -> conic 0.9889 against R3w 0.9702 (distance 0.023 -> 0.019:
  not a decisive improvement).
- Annulus sweep (726 annuli; 494 HEAD fits): cbs changes 88 of 494 (17.8 %): 14 refusals (all Au_ref), 74 profile -> conic; 31 of the 494 move b/a by more than 0.005. The family medians show HEAD is itself annulus-sensitive
  on Au_ref (A2: b/a 0.76-0.99 across +-2 px shifts); no candidate repairs that (A2 family 13 outliers under head, 12 under cbs).

## Registered predictions Q0-Q4: held / not held (my numbers; out/p1.txt, p10.txt)
- Q0 HELD (none == head 2009/2009 rows, 6/6 real sources, text included; b2 == b 2009/2009).
- Q1 (c) HELD as worded: wrong 80 <= 90; right lost 5 <= 10; newly wrong 3 <= 5; S3 wrong 3 <= 3, S4 0; S3/S4 right lost 0 <= 2; real sources: no model change, b/a moves <= 4e-4. Not checkable: "every set within 5 of the
  projection" (per-set projection not given; per set c vs oracle min(head,a): A/B/C 1/1, P 45/41, T 29/29, S3 3/3, N 0/0, S4 0/0). Not said by the registration: the 3 newly wrong are the worst fits in the study.
- Q2 (b2) NOT HELD on N: 19 right head fits refused (4 -> M, 13 stay R, 2 -> W), 6 right lost; real sources HELD.
- Q3 (s) HELD on synthetic (0 right refused, 64.7 % of head-wrong fits flagged: 268/414) and at the step-(i) real annuli; NOT HELD on shifted real annuli (Au_ref A1 5/24 ...); 13 new throws.
- Q4 (cbs): wrong 50 <= 80 HELD; right lost 11 vs c's 5 + 2: NOT HELD (+6, all N, from b2); b/a>0.01 fewest: 40 = cs's 40, a tie: NOT HELD as worded; real step-(i) annuli HELD.
- Q5 / Q6: not tested by me (tool run needs the repo python with scipy; unit/core gates need a test host).

## Verdicts
- c (two starts, lower cost): UPHELD WITH CORRECTIONS. Evidence: wrong 414 -> 80, |dba|>0.01 319 -> 58, theta > 0.3 rad 198 -> 31, exact selector of {head, a} (2009/2009), picks the closer start in 526 of 557 materially different
  pairs, inert on real data (1 of 494 swept annuli moves b/a > 0.005). Corrections: (1) lower cost is not closer: 31 farther picks, 4 where HEAD was within 1 % (P-423 ends at dR +0.20, dba -0.40; P-108/148 dba -0.10), cost lower by 1-15 %;
  (2) on gapped (60 degree) low-count 1/r^2 tails c is not better than HEAD (W16 vs 14, mean |dba| 0.109 vs 0.048); (3) 2009 rows are 1747 independent plants. Safe: any ring with a flat/const/tilt/exp background, narrow rings,
  real Au_ref/WS2/NiCu patterns. Not safe alone: gapped rings on a 1/r^2 tail at <= 20 counts.
- b2 (floor guard sigma <= 0.30): UPHELD WITH CORRECTIONS. Refuses all 132 dead rings (I1 = 0) of the 2009 plants and Au A4 / Ni65Cu35 R3; refuses 19 right fits in N (point-sampled sigma 0.25-0.30 rings, conic fallback <= 1.1 % R, <= 0.005 b/a)
  and ~15 % of annulus choices on the real WS2 map (b/a change <= 0.003); its sigma proxy misses a dead ring with sigma > 0.30 (constructed Y case), and its message says 0.25 for a 0.30 test. Safe: Au_ref, WS2, any ring wider than ~0.4 px;
  not safe: point-sampled rings under 0.3 px.
- s (8 % seed check): REFUTED as registered (unconditional 8 %). On 4614 synthetic right fits it never fires wrongly, but on the owner's real Au_ref ring A1 it refuses 5 of 24 annulus choices whose profile fits agree with the other 19
  (R 10.31-10.46, b/a 0.973-0.978) because the conic seed swings 9.1-11.5 px at residual 0.2-0.4, and the refusal is final (no conic fallback over the 0.2 cap). A version gated on the seed's conic residual <= 0.2 keeps 255 of the 268
  synthetic catches (counterfactual from logs, not run) and none of the Au_ref false refusals; that is the version to test. Safe: seeds with residual <= 0.2 (all of S3/S4 at the step-(i) annuli); not safe: seeds over the 0.2 cap.
- cbs: UPHELD WITH CORRECTIONS (as a combination, s to be gated or dropped before landing). Best variant on every synthetic measure (wrong 50, b/a>0.01 40, theta>0.3 rad 27, 1 newly b/a-bad plant, 9 new refusals of fits that were
  wrong by 10-33 %), identical to c on all real step-(i) annuli but A4, W4 (Au_ref) and R3 (Ni65Cu35) where it is right to act; but (1) it inherits s's real-data false refusals (14 Au_ref annuli, 9 of them consistent),
  (2) the per-start hand-over accepts a wrong second-start fit 5-8 % from the seed in 8 P plants where s alone would refuse or give the conic (b/a 0.05-0.11 worse than s alone) and a dead ring in the constructed Y case,
  (3) right lost 11 (6 more than c), (4) ellipse fits that were accepted at HEAD now refuse in 28 vs 19 plants.

## What I did not test
- Q5/Q6: tools/ellipse-calibration-test and the unit/core gates (no test host; the tool needs the repo python+scipy). The grains_12_one_annulus expectation is the session's own (record Q5).
- The app's own detection on the Al-Mg-Si cube (S1, S2 refused by coverage at every annulus); the app's own Bragg-vector map for any cube other than the py4DSTEM-peaks WS2 map; wide default annuli on real patterns
  (the app's default annulus 0.35-0.9 x detector half size holds several rings); real sources other than the six; macTEM's copy of Core; the owner's Au_ref ring identification (A1 consistency is internal, no truth).
- The cres <= 0.2 gated seed check as code (counterfactual only); a third start; timing on a 512 x 512 detector beyond 9 plants.
- My sets Z, E, Y2, V are my own generators (gen_z.py, gen_e.py, gen_y2.py, gen_v.py): point-sampled, no pixel integration except V's bilinear deposition; they are not validated against real tails.
  Set Y/X are invalid or empty as noted above (Y: ring clipped by the image; X: every plant refused by the conic stage under HEAD too).
