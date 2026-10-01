# T1b — kernel default across datasets (classical detector), 2026-10-01
## Predictions (written BEFORE any run)
Options: A = Synthetic trench at probeSize radius (today); B = File-probe kernel (flat, the app's File-probe default) when the file carries a probe image, else A;
C = A, but at S21's structuredProbeOuterRadius when it returns non-nil (the committed patch rule); C_all = Synthetic at the unrestricted outer edge (largest r with azimuthal mean >= 20 % of max) on EVERY dataset (not a proposal; shows what an unconditional outer edge would move).
P1 Bullseye A reproduces S21/T1: all-40 recall .119 / precision .020. B-flat .627/.083, B-trench(file probe) ~.616/.101. C (r 11) .781/.430. Estimator r 6.84, outer edge 11.
P2 Solid-disk datasets (Particle_1, Si_SiGe, WS2, sim_Au, Si-SiGe_calibrated, Al_Mg_Si, Thronsen A, demo): structuredProbeOuterRadius is nil (S21 rule.log) so C == A bit for bit: 0 moved peaks.
   Au_ref (ring in meanDP): nil through the qMin/8 guard, C == A.
P3 B exists only where the file carries a probe image on the detector grid; I expect bullseye only (possibly one more). Where B exists on a solid-disk probe and uses the FLAT kernel, it WILL move peaks vs A (different kernel family), so B is not move-free there.
P4 C_all moves normal probes where R_out > r_est by more than a pixel or two: Si_SiGe (3.7 -> ~15), Au_ref (8 -> 26), Particle_1 (6.1 -> 10), sim_Au (5.1 -> 6); WS2/Al_Mg_Si/Thronsen ~ unchanged (R_out within 1-2 px of r_est).
P5 Control: A with the real-data-acceptance harness's probe input (max of the 3 sampled patterns) reproduces expected.json peak counts on the 5 pinned cubes.
Truth exists for the bullseye only (A2 labels, 40 positions/370 centres). Thronsen/demo truth is phase maps, not disk positions; elsewhere the comparison is against option A (the pinned golden where pinned).

## Method
Tool: $LD/probe/main.swift + run.sh (scratch; HEAD 38c0e52b via git archive, repo untouched, no xcodebuild, no app). Classical DiskDetector, params detectorAdapted(probeRadius = r_est) identical in every arm so only the kernel differs.
r_est = OriginCalibration.probeSize on the mean pattern of <= 300 evenly spaced positions (the app's input; S21 used the full meanDP). 24 positions per cube (the harness's 3 + 21 evenly spaced). C = structuredProbeOuterRadius copied from the S21 patch (`docs/archive/v4/s21-detection-defaults-proposal-2026-09-30.patch`).
Logs: run-bullseye.log, run-others.log (build-probe.log: build only). Truth: bullseye A2 labels (40 pos / 370 centres, 2 px greedy, DetectionScorer). No other cube has disk-position truth (Thronsen/demo truth is phase maps) so there the comparison is vs A.
Control (P5): harness-style A at the 3 pinned positions reproduces expected.json counts on all five pinned cubes: bullseye [27,7,18], Particle [1,21,1], Si_SiGe [19,25,17], WS2 [1,4,1], sim_Au [1,29,1] (run-*.log CONTROL lines).
Not run: Al_Mg_Si ellipse-variant file (same cube data as the plain one), vacuum-scan / measured-ROI kernels (need the app's UI selection).

## Table 1 — radii (px) and what each option does to the peaks (24 positions; moved = A's peaks NOT reproduced within 0.05 px)
| dataset | file probe? | r_est | outer edge (unrestr.) | S21 rule | C vs A | B vs A | C_all (outer edge everywhere) vs A |
|---|---|---|---|---|---|---|---|
| bullseye 250 px | yes (probe_template) | 6.90 | 11 | 11 | 485 peaks vs 1245, 0/1245 kept | B_flat 1540 pk, 0 kept; B_trench 1339, 0 kept | = C |
| Particle_1 | no | 6.38 | 10 | nil | identical (485/485) | = A | 409 pk, 2/485 kept |
| Si_SiGe (downsample) | no | 3.91 | 15 | nil | identical | = A | 373 pk, 0/743 kept |
| WS2 | no | 1.86 | 2 | nil | identical | = A | 103/105 kept |
| sim_Au | yes (vacuum_probe, r 5.17) | 5.10 | 6 | nil | identical | B_flat 962 pk vs 50, 2 kept; B_trench 50 pk, 0 kept to 0.05 (all within 2 px) | 28/50 kept, all within 2 px |
| Au_ref (64 px) | no | 8.23 | 26 | nil (qMin/8 = 8 guard) | identical | = A | 35 pk vs 167, 0 kept |
| Si-SiGe_calibrated | no | 3.72 | 4 | nil | identical | = A | 313/729 kept (726 within 2 px) |
| Al_Mg_Si | no | 2.51 | 3 | nil | identical | = A | 68/205 kept (all within 2 px) |
| Thronsen A | no | 2.80 | 4 | nil | identical | = A | 366/490 kept |
| demo AlMgSi | no | 2.99 | 3 | nil | identical | = A | identical |
Distribution of outer edge / r_est (unrestricted): bullseye 1.59, Particle 1.57, Si_SiGe 3.8, Au_ref 3.2, Si-SiGe_cal 1.08, Al_Mg_Si 1.2, Thronsen 1.43, sim_Au 1.18, WS2 1.08, demo 1.0. The ring is not separable by this ratio (Si_SiGe, Au_ref exceed it; both have Bragg disks in the mean pattern, not a probe ring) — only S21's dip test + qMin/8 guard keeps them out, and that guard was chosen after seeing Au_ref (S21 record).

## Table 2 — bullseye vs truth (all 40 positions, 370 centres, 2 px; run-bullseye.log)
| option | recall | precision |
|---|---|---|
| A: Synthetic at r_est 6.90 (today) | .124 (46/370) | .022 |
| B_flat: File-probe, flat (the app's File-probe default) | .627 (232) | .083 |
| B_trench: File-probe, sigmoid trench | .616 (228) | .101 |
| C: Synthetic at outer edge 11 | .781 (289) | .430 |
(T1's r 10 gave .887/.419; S21's r 11 .781/.430 reproduced exactly.)

## Findings
- Moves no normal (solid-disk) probe AND fixes the ringed one: only C. On the eight solid-disk cubes without a file probe C is bit-identical to A (0 of 3 pinned harness positions or 24 sampled positions moved), so no pin re-pins except the bullseye's. Au_ref (meanDP ring structure) is the near miss: held out only by the qMin/8 guard.
- B does NOT move nothing: where a file probe exists on a normal probe (sim_Au vacuum_probe) B_flat changes the answer drastically (962 vs 50 peaks over 24 positions; at the vacuum positions A finds 1 beam, B_flat 38-45) — flat/untrenched kernel matches Bragg-disk-free structure; B_trench keeps the count (50/50) but shifts every position by sub-pixel to <= 2 px. On the bullseye B_flat helps recall (.62 vs .12) but precision is .08 (the 70-peak cap saturates), C is better on both.
- A (today) fails the ringed probe and passes everything else; C fixes it with exactly one affected dataset in this set. The evidence for C's gate on any OTHER ring probe is nil: one ring probe exists here; C_all shows an unconditional outer edge would wreck Si_SiGe/Au_ref/Particle_1.
- Caveats: one structured probe, one labeller; the gate margin (D 0.222 vs 0.25) and the 20 % edge are properties of these files. B was measured with the classical detector only; T1's learned-path File-probe result (.584/.657) is unchanged and is a different quantity. No threshold or rule proposed beyond what the tables show.
## Repo
No writes (git status unchanged by this lane).
