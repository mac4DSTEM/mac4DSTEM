**S14 results: origin coarse seed vs a Gaussian-argmax comparator (2026-09-30). Pre-registration `2c1356e`, amended in §9/§10 of that file. Verdict: BAR NOT MET. No patch.**

Probe and logs: `s14-origin-seed-probe/` (`main.swift` measures, `gen.py` derives every variant kernel from the shipped `OriginMeasure.metal`, refine step verbatim; `grid-rerun.log` is the table below, `grid-first.log` the first run with contended timing). Fits are the shipped `fitOriginTrimmed`, plane. r is `probeSize` on the mean DP, as `tiledRun`. Peak phys_footprint 1.46 GB (guard 2.5 GB); bullseye streamed in 17-row tiles. V0 shipped block seed; V1 box side 2·round(r)+1 (registered primary); V2 variance-matched box; G Gaussian seed (`mode="nearest"`); PY py4DSTEM single pass 1.2 r from G; WIDE 3 r iterated CoM from G.

**1. Comparator validity (checked first).** The numpy twin reproduces the recorded 28/169 (Si_SiGe_exp) and 29/195 (Particle_1) exactly; the recorded metric is `|NEW − PY| > 1 px` (OLD/PY on Particle_1 is the 70/195), at app r 32/195 (`twin-recorded-counts.log`, `validate1-…log`). On 60 strided patterns of every cube: GPU V0 = twin NEW to ≤ 8.5e-5 px; the Swift Gaussian seed = scipy 60/60; V1 = float64 clipped-box argmax 60/60 everywhere (`validate2-all-cubes.log`). V2 matched only 12/60 on WS2 (exact-tie plateaus in float32 sliding sums; refined origins still identical).

**2. Seed misses, refined origin > 1 px from the comparator, full scan** (the bar's statistic)
| cube (n, r) | V0 vs G | V1 vs G | V2 vs G | V0 vs PY | V1 vs PY | V1n vs G / PY (exploratory) |
|---|---|---|---|---|---|---|
| Si_SiGe_exp (10000, 3.74) | 1860 (18.6 %) | **241 (2.4 %)** | 1628 | 1860 | 241 | 241 / 241 |
| Particle_1 (4050, 6.12) | 705 (17.4 %) | **418 (10.3 %)** | 1283 | 806 | 449 | 308 / 434 |
| Au_ref (63550, 8.06) | 35338 (55.6 %) | 12989 (20.4 %) | 34721 | 41859 | 20331 | 12138 / 19710 |
| bullseye_polyAu (8400, 6.84) | 7611 (90.6 %) | 2438 (29.0 %) | 5968 | 8394 | 7983 | 2438 / 7983 |
| bullseye_sim (8400, 6.78) | 8014 (95.4 %) | 1444 (17.2 %) | 6969 | 8400 | 8155 | 1444 / 8155 |
| simAu poly / nano (8400) | 1 (24.9 px) | 0 | 0 | 1 | 0 | 0 |
| WS2, SiSiGe_cal, AlMgSi_060, thronsenA, demo cube, fixture | 0 | 0 | 0 | 0 | 0 | 0 |
Half of V1's remaining Particle_1 misses (202/418) have a seed within r of the detector edge (Au_ref 1327/12989; none elsewhere). V1n (replicate-padded edges) lowers Particle_1 to 308 vs G (−56 %) and 434 vs PY (−46 %). Raw-seed differences are not misses (a block centre sits up to bin/2 off by construction).

**3. Final fitted origin, V1 − V0** (all positions of the shipped plane fit) and the gate
| cube | fitted-origin \|Δ\| median / max px | scan-mean shift (x, y) | fullScanRMS V0 → V1 (gate r) | excluded V0 → V1 |
|---|---|---|---|---|
| Si_SiGe_exp | **1.991 / 5.488** | (0.65, 1.82) | 9.720 → 9.550 (3.74) BLOCK both | 0.100 → 0.072 |
| Particle_1 | 0.053 / 0.124 | (−0.002, 0.008) | 18.059 → 15.723 (6.12) BLOCK both | 0.262 → 0.235 |
| Au_ref | **0.489 / 0.651** | (0.18, −0.40) | 13.549 → 12.090 (8.06) BLOCK both; V2 7.087 PASS | 0.000 → 0.000 |
| bullseye_polyAu | **2.329 / 4.132** | (1.16, 1.61) | 3.261 → 3.659 (6.84) PASS both | 0.015 → 0.0002 |
| bullseye_sim | **2.827 / 5.493** | (1.33, 1.92) | 2.729 → 3.268 (6.78) PASS both | 0.018 → 0.001 |
| simAu poly / nano | 0.0005 / 0.0009, 0.0007 / 0.0017 | ≤ 0.0005 | 0.516 → 0.437, 0.305 → 0.140 PASS | unchanged ± 0.001 |
| SiSiGe_cal, AlMgSi_060 | 0.0005 / 0.0006, 0.0014 / 0.0034 | ≤ 0.0026 | unchanged to 0.001 | ≤ 0.0014 |
| WS2, thronsenA, demo cube, fixture | 0.0000 / 0.0000 | 0 | unchanged (thronsen 0.0355) | 0 |
Against the proxies, V1 moves the mean toward them where it moves at all. Mean fitted origin V0 / V1 / G / WIDE / mean-DP centre: Si_SiGe_exp (69.31, 54.50) / (69.96, 56.32) / (70.20, 56.39) / (70.17, 56.39) / (70.41, 59.19: drift, not a reference); bullseye_polyAu (125.99, 125.79) / (127.15, 127.41) / (127.13, 127.42) / (127.05, 127.46) / (126.98, 127.48); Au_ref (33.53, 29.84) / (33.71, 29.44) / (33.84, 29.51) / (33.85, 29.50) / (33.80, 29.61). So the shipped seed sits 0.4–2 px from all three references on those cubes. Per-position scatter is not better: bullseye V1 fullScanRMS 3.66 / 3.27 against WIDE 0.75 / 0.28, and V1's per-position distance to WIDE is still median 3.4 px (the r + 1.5 window truncates a ringed probe whatever the seed).

**4. Cost, median of 41 dispatches at the app's tile grid, µs/pattern, whole kernel V0 → V1 (ratio; coarse-only ratio in brackets)** (re-run, quiet GPU; `grid-rerun.log`). fixture 7.46 → 18.11 (2.43× [2.63]); WS2 1.18 → 3.68 (3.13× [3.18]); Si_SiGe_exp 1.39 → 3.93 (2.83× [2.82]); Particle_1 1.93 → 4.09 (2.13× [2.22]); simAu poly 2.95 → 6.10 (2.07× [2.14]); nano 2.95 → 6.14 (2.09× [2.11]); bullseye poly 9.38 → 35.48 (3.78× [3.83]); sim 9.73 → 35.40 (3.64× [3.93]); SiSiGe_cal 67.2 → 332.5 (4.95× [4.96]); Au_ref 0.55 → 0.76 (1.39× [1.56]); AlMgSi_060 0.38 → 0.76 (1.99× [2.15]); thronsenA 1.30 → 4.31 (3.32× [3.31]); demo 1.33 → 4.15 (3.12× [3.08]). V2 within 0.2× of V1 everywhere. The first run, GPU contended, read 1.4–5.4×, so the ratios move by ± 2× with load. Refine is < 5 % of the kernel, so whole ≈ coarse-only. The Gaussian seed costs 7–236 µs/pattern on all CPU cores (`G CPU`), not comparable to the GPU kernels.

**5. Prediction vs outcome (§5)**
- (a) V1 misses ≤ 5 %: Si_SiGe_exp 18.6 → 2.4 % HELD; Particle_1 17.4 → 10.3 % (PY 19.9 → 11.1 %) REFUTED (−41 %/−44 %); V2 "no better than V1" REFUTED in the other direction: V2 is much worse (16.3 % and 31.7 %).
- (b) clean cubes, 0 misses, fitted \|Δ\| < 0.10: HELD on WS2, both Au sims (1 V0 miss each, fixed by V1), SiSiGe_cal, AlMgSi_060, thronsenA, demo cube, fixture (fitted \|Δ\| ≤ 0.0034). bullseye ×2 and Au_ref were misclassified as clean by the registration; their \|Δ\| 0.5–5.5 px REFUTES the bound for them.
- (c) Si_SiGe_exp fitted max < 1 px REFUTED (5.49; trimming hides nothing there: 10 % → 7 % excluded); BLOCK unchanged HELD. Particle_1 fitted max 0.124 (< 2), RMS −12.9 % (within ± 25 %), excluded −2.7 points (≤ 5), BLOCK unchanged: HELD. thronsen/AlMgSi_060 max < 0.10: HELD.
- (d) coarse-only 2–4×, whole ≤ 1.6×: REFUTED (whole 1.39–4.95×, > 3× on 6 of 13 cubes with V1; largest on the big-detector cube whose per-thread column-sum array is 480 floats).

**6. Bar (§6), all required.** (1) ≥ 50 % fewer misses on both noisy cubes, both metrics: NOT MET (Particle_1 −41 %/−44 %). (2) no dataset worse, no flip, bounds kept: NOT MET on the registered bounds (4 cubes move 0.5–5.5 px; that movement is toward G, WIDE and the mean-DP centre, but the registered bound is a bound); V1 flips no verdict, V2 flips Au_ref BLOCK → PASS. (3) complete change table: yes. (4) cost ≤ 3× at every tile grid: NOT MET. No patch, so no harness was re-run; candidates for a repin had it been met are §6 of the pre-registration, unverified.

**7. What this does and does not show.** Shown: the shipped block seed, on Si_SiGe_exp, both bullseye cubes and Au_ref, leaves the trimmed plane 0.5–2.8 px (median) from the fit any of V1, G or WIDE gives; "plane-fit trimming hides most" (open-items) is refuted on those four (it holds on Particle_1, 0.12 px). Not shown: that G or V1 is right on those cubes (WIDE and the probe centre are proxies; a ringed or 8-px probe on a 64-px detector breaks the r + 1.5 window for every seed). Mechanism for the V0 offset is unidentified; a null on the fit's residual is not one. Untried: a cheaper two-level seed (block sums, then an exact box around the top blocks); V1n untimed.

**8. What a refuter should attack.** (i) the misclassified-clean datasets, whether the bound was fair; (ii) `validate2` compares 60 seeds per cube, not the scan; (iii) V1's edge clipping vs V1n; (iv) timing on a loaded GPU (first vs re-run) and an unoptimised thread-private array; (v) that WIDE, seeded from G, is not independent of G.
