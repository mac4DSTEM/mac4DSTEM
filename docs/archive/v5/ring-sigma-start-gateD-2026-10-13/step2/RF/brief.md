# Refuter brief — ring-fit Gate D, step 2 (independent; you did not write any of this)
Read $SP/lanes/COMMON.md first (paths, rules). Your lane dir: $SP/lanes/RF/. You are READ-ONLY on the repo and on every
other lane's files; build your OWN harness and analysis (do not import or run the lanes' compare.py / an.py).

What is claimed. The record $REPO/docs/archive/v5/ring-sigma-start-gateD-2026-10-13.md (Diagnosis, Predictions, the
Step 2 amendment, step-1 Results) and the lane reports $SP/lanes/{M,T,P5,F}/report.md say how two held candidate fixes to
`EllipseCalibration.fitAmorphousRing` behave: a (ring sigmas start at a half-maximum width of the seed ellipse's radial
profile), b (refuse a fit whose smaller ring sigma ends <= 0.30 px; fitBestAvailable falls back to the conic), ab (both).
The candidate files: $SP/patches/EllipseCalibration.{a,b,ab}.swift (diffs core-{a,b,ab}.diff). The owner will choose
a, b, both or neither on the strength of this. Your job is to find what would make that choice wrong. Review the
diagnosis and the measurements, not the diff's style.

Write your attack plan and your predictions into $SP/lanes/RF/report.md BEFORE running anything. Then at least:
1. Out of sample. Make a THIRD noisy plant set with macTEM's generator ($SP/data/plants_a.py; read it — change only its
   SEED0 to a value of your choosing, say which, and its output dir under your lane). Run head, a, b, ab with
   `fitBestAvailable` (default arguments, the plant's guess and annulus) using your own harness (build with
   $SP/harness/build.sh <out> <your main.swift> <variant>). Count accepted profile fits off by > 1 % and > 0.1 % in
   (a+b)/2, b/a errors (what the app applies), and right fits lost. Does a rescue as on sets A/B? Does b catch as claimed?
2. A noise model the plants do not have: Poisson counting noise (e.g. ring peak ~20-200 counts on a background of a few
   counts, as a summed or mean diffraction pattern might be), and a smooth background under the ring. Does a still help,
   does b refuse right fits, does either make a right fit wrong?
3. b's threshold against a legitimately narrow ring: a clean or lightly noisy ring whose true sigma is 0.3-1.0 px
   (binned detectors make such rings). Does b refuse a right fit? Does a's 1 px floor on the start matter there?
4. a's estimator against its traps: a neighbour ring inside the annulus, a strong background slope, a 60-degree gap, a
   ring wider than a quarter of the annulus, a ring near the annulus edge. Does the start ever become worse than HEAD's
   (a right HEAD fit turned wrong)?
5. Check the lanes: re-derive at least two headline numbers from the lanes' raw logs with your own parsing (e.g. lane M's
   wrong counts per variant on set A, lane P5's per-annulus agreement), and state whether they reproduce.
6. Read the code of a's estimator and b's guard for a defect (an off-by-one in binning, the elliptical radius formula vs
   the model's, the crossing interpolation, the NaN paths, the sign of theta), and test any suspicion by experiment.
Verdict: one of UPHELD / UPHELD WITH CORRECTIONS / REFUTED, per candidate (a, b, ab), each with the evidence (log names).
Say what you did not test. Final message <= 30 lines with the verdicts and the path of report.md.
