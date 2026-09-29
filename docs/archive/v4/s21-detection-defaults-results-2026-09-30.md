# S21 — bullseye detection defaults: results (2026-09-30)

Pre-registration `s21-detection-defaults-preregistration-2026-09-30.md` (commit 6142a36; three amendments A1/A1b/A2/A3 written before any grid read).
Everything printed is in `s21-detection-defaults-evidence-2026-09-30.txt` (scratch logs `profile-*.log`, `score-run{1,2}.jsonl`, `rule.log`, `radii.jsonl`, `moves-auref.log`, `runsh-patched.log`, harness source appended).
Engine: production `DiskDetector`/`ProbeKernel` from a `git archive HEAD` snapshot (04d2560); tree untouched. Labels: A2, 40 positions, 370 centres, 2 px one-to-one, recall / precision. Peak footprint 1.1 GB (guard 2.5 GB; the first Al_Mg_Si profile pass tripped the guard, rerun with 2-row tiles: 191 MB).

## Validity controls (all passed)
Central-beam label matched 40/40 and is the label nearest the pattern centre 40/40; swapping row/col drops B_flat recall 0.627 → 0.073 (the null);
two full runs are byte-identical (`cmp`); B_flat at the parity settings gives 878 peaks, identical to `bullseye-parity-probe` (max position difference 0.0, the 2026-09-05 record's 878). B_syn's radius from meanDP reproduces the pinned 6.843.

## Result (recall / precision, 2 px; sel = even 20 positions, conf = odd 20, all = 40)
| flow / setting | sel | conf | all | peaks/pos, at cap 70 |
|---|---|---|---|---|
| B_flat, app defaults (spacing 7, 0.15 %) | .689 / .082 | .576 / .084 | .627 / .083 (3 px .778 / .103) | 70.0, 100 % of positions |
| B_syn, app defaults (trench, r 6.843) | .096 / .016 | .138 / .025 | .119 / .020 (3 px .246 / .042) | 53.8, beam brightest at 0 % |
| B_syn, kernel radius 11 only | .790 / .416 | .773 / .442 | .781 / .430 (3 px .873 / .481) | 16.8, beam brightest 100 % |
| B_flat best of grid on sel (spacing 22, floor 2 %) | .671 / .124 | .567 / .124 | .614 / .124 | 45.6 |
| B_syn/r 11 best on sel (sigma_cc 3) | .868 / .477 | .833 / .493 | .849 / .485 | 16.2 |

Grid facts (all 40, `evidence` §score analysis): in B_flat the floor does nothing between 0.15 % and 2 % (the 70-peak cap decides), then at 5 % gives .381 / .425; spacing 11 changes nothing (.616 / .081), 22 gives .614 / .119; sigma_cc 3 gives .641 / .139, corr_power 0.9 .632 / .084; the origin choice (125,125 vs the fitted 125.05,125.00) is inert (.630 / .083). relativeToPeak 1 is inert in B_flat.
In the trench flow no scalar besides the radius helps: at radius 11 the floor trades (0.5 %: .695 / .781; 2 %: .378 / .946; 5 %: .203 / .949).
**Exploratory, not in the grid (radii.jsonl):** trench radius 8 .224 / .050, 9 .900 / .296, 10 .886 / .419, 11 .781 / .430, 12 .719 / .422, 14 .616 / .388, 16 .365 / .234, 20 .122 / .078 (all positions, spacing 7; spacing coupled to the radius as in the app moves these by < .012). A cliff between 8 and 9, then a broad plateau — not a knife edge at 11.

## Gate quantity on every dataset (meanDP, the app's own probe-size input; A1/A1b)
| dataset | r_est | R_out | D (restricted) | structuredProbeOuterRadius |
|---|---|---|---|---|
| bullseye (probe_template image: D 0.055, R_out 11) | 6.843 | 11 | **0.222** | 11 |
| Au_ref_ROI15 (64 px) | 8.056 | 26 | **0.006** | nil (guard R_out ≤ qMin/8 = 8) |
| Particle_1 / Si_SiGe / WS2 / sim_Au | 6.12 / 3.74 / 1.86 / 5.11 | 10 / 15 / 2 / 6 | 0.894 / 1.0 / 1.0 / 1.0 | nil |
| Si-SiGe_calibrated, Al_Mg_Si ×2, Thronsen A, demo | 3.69 / 2.54 / 2.54 / 2.84 / 2.98 | 4 / 3 / 3 / 4 / 3 | 1.0 | nil |
Unrestricted D (A1b, reported): Si_SiGe 0.017 (a Bragg ring at r 8), Au_ref 0.006; the 2 r_est restriction is what keeps Si_SiGe out.

## Predictions against outcomes
- **P0 held**: cap binds at 100 % of positions, precision .083 (≤ .15), recall .627 (in .55–.80); .30 not reached.
- **P1 held**: spacing 7 → 11 gives −.002 precision, −.011 recall; → 22 gives +.036 / −.013 (< +.05).
- **P2 held for B_flat**: no scalar gives +0.10 precision within −0.02 recall (best on conf +.041 / −.010; sigma_cc 3 +.056 / +.014; 5 % floor +.34 / −.25); it also holds after the radius change (best further +.05 / +.06, or the floor at −.09 to −.58 recall).
- **P3 held on its thresholds, wrong on its baseline**: beam brightest 100 % (> 90 %), recall +.66 (≥ .10) — but B_syn's baseline is not "about 41 %": it is 0 %, recall .119, precision .020. The app's default flow on this cube finds almost none of the labelled disks.
- **P4 refuted**: Au_ref's meanDP has a ring (D 0.006 < 0.25), and the bullseye's meanDP D is 0.222, only 0.028 under the pre-registered 0.25 (its own probe image 0.055).
- Overall prediction ("bar not met for scalar levers, met at most by P3") held.

## Bar (against B_syn, the default flow the rule changes)
1. **Met**: conf +.417 precision / +.635 recall, sel +.400 / +.694, all +.410 / +.662. For B_flat and every further scalar: **not met** (no patch for those).
2. **Met with a caveat**: the raw gate fires on Au_ref. Its moves if applied there (radius 8.06 → 26 on a 64 px detector, spacing 8; `moves-auref.log`): peaks at the three harness positions 9 / 10 / 1 → 1 / 2 / 1. The patch adds a bound chosen AFTER seeing this (R_out ≤ qMin/8) so Au_ref stays unchanged; nothing else in the tested set is touched. A gate tuned on one firing dataset and one non-firing dataset carries no evidence for a third structured probe.
3. **Met, and vacuous for the moved cube**: `tools/real-data-acceptance/run.sh` in a patched scratch copy exits 0 (`runsh-patched.log`, all five pins PASS). The harness builds its kernel itself and never calls the new function, so it cannot see the app-path change on bullseye; the other 10 datasets return nil (`rule.log`), so their app path is unchanged by construction.
4. **Met** (controls above).

## Verdict
**The pre-registered bar is met for one rule; a READY PATCH is at `s21-detection-defaults-proposal-2026-09-30.patch` (applies to the tree with `git apply --check`, not applied).**
It adds `OriginCalibration.structuredProbeOuterRadius(meanDP:qy:qx:)` and builds the synthetic trench kernel at that radius when the mean pattern's probe is ring-structured; `probeSize` and everything the origin window reads are unchanged. Not in the patch, by design: any floor, spacing or sigma default (not met).
Not done: no XCTest is in the patch (the harness in the evidence file is the only check of the function); the mutation check on a new test, the Gate B refuter and any on-screen drive are all still owed (**unverified on screen**; the app was not launched).

## What a refuter should attack
- **One cube, one labeller, 40 positions.** A2 labels are by eye (label-vs-net scatter 1.2 px), and the radius that wins here (9–14 plateau) is this probe's. The rule's radius comes from the profile, but a differently shaped ring is untested; no second structured probe with truth exists on this Mac.
- **The gate margin**: bullseye's meanDP D is 0.222 against 0.25. The threshold is a property of these 11 files (threshold rule); a descan or a different scan area moves the meanDP dip. The unrestricted quantity separates nothing (Si_SiGe 0.017).
- **Side effects of `probeKernel.probeRadius` = 11** (not measured): `fittedProbeRadius` feeds the spacing default (7 → 11, measured inert in the trench flow), the peak-overlay ring radius, the learned detector's probe reference and the kernel status line; provenance/replay records the kernel radius (`KernelRestore`) — check a replay of a pre-patch session.
- **The Au_ref guard** was chosen after its result; the what-if number rests on 3 positions with no truth.
- **B_flat at defaults is 8 % precise** (70-peak cap): a separate finding, no lever here fixed it; the floor (0.15 %) is ADR 041's, untouched.
- I inferred no mechanism for why radius 6.84–8 fails and 9 works (the cliff between them); only the outcome is measured.
