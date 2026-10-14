# Refuter RF2 brief — ring-fit Gate D, step 2 (independent; fresh; you wrote none of this)
Read $SP/lanes/COMMON.md first (paths, rules; SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad).
Your lane dir: $SP/lanes/RF2/ (write only there). READ-ONLY: the repo, every other lane dir. Do NOT read or use $SP/lanes/F
or $SP/lanes/F2 (another lane's fixture work; you must stay independent of it).

What is claimed. The record $REPO/docs/archive/v5/ring-sigma-start-gateD-2026-10-13.md (Diagnosis, Predictions, Step 2
amendment, step-1 Results) and lane reports $SP/lanes/{M,T,P5}/report.md say how two held candidate fixes to
`EllipseCalibration.fitAmorphousRing` behave: a (both ring sigmas start at the half-maximum width of the seed ellipse's
radial profile), b (refuse a profile fit whose smaller ring sigma ends <= 0.30 px; fitBestAvailable falls back to the conic
or throws when the conic residual > 0.2), ab (both). Code: $SP/patches/EllipseCalibration.{head,a,b,ab}.swift and
core-{a,b,ab}.diff. The owner will choose a, b, both or neither on the strength of this. Find what would make that choice
wrong. Review the diagnosis and the measurements, not the diff's style.

Starting material: an earlier refuter (RF) was cut off by a usage limit after running four attack sets; it left raw logs and
generators but NO verdicts, and its analysis script was never reviewed. Its dir $SP/lanes/RF/: brief.md (its brief, same
items as yours), report.md (its plan and predictions only), gen/plants_c.py (set C = macTEM's plants_a.py with SEED0 52817),
gen/gen_extra.py (sets P Poisson, N narrow rings, T estimator traps), rf.swift (its harness), bin/rf-{head,a,b,ab} (built),
data/plants{C,P,N,T} (the rendered plants + truth), logs/{C,P,N,T}_{head,a,b,ab}.log (+ .err/.exit), logs/cost_Tneigh.txt,
cost.py, dead.py, an_rf.py, an_T.py. Treat all of it as UNVERIFIED. Do not run or import an_rf.py / an_T.py / any lane's
compare.py or an.py: write your own parser from the log format and the generators' truth files.

Leads to confirm or refute (a coordinator's print-only recount with RF's an_rf.py; unreviewed). "Wrong" = accepted profile
fit off by > 1 % in (a+b)/2; "right" = within 0.1 %; "right lost" = right under HEAD, not right under the variant:
- Set C (out of sample, 144 noisy): HEAD wrong 29; a and ab rescue 29/29, lose 0 right; b leaves 25 wrong.
- Poisson P (480): HEAD wrong 148; a leaves 66 wrong and loses 21 right (25 newly wrong; by amplitude 10/20/50 counts:
  8/8/5 lost); ab leaves 47, loses 18 (13 profile->conic); b leaves 105, loses 0, 1 new throw.
- Narrow N (280; ring sigma 0.25-1.0 px): HEAD wrong 91; a rescues all, loses 1; b turns 19 profile->conic and loses 6
  right (5 at the 3 %-noise tier); ab loses 7.
- Traps T (256): HEAD wrong 44; a rescues only 15 and loses 4 right fits, all "neighbour ring inside the annulus" (4 of 72);
  cost_Tneigh.txt: a ends at cost ~3770 vs HEAD 2366 vs truth 1733 on f1.155 A0.8 plants (a's width start merges the two
  rings and lands in a worse minimum, dR 0.07 vs HEAD -0.01).

Work (predictions into $SP/lanes/RF2/report.md BEFORE each step; results appended under dated headings):
1. Own parser: re-derive every count above per set and variant from the raw logs + truth; say which reproduce exactly,
   which differ and why (definitions, parsing, tiers). Report b/a errors (what the app applies) next to (a+b)/2.
2. Spot reproduction: re-run at least 8 plants per lead (the ones that carry each claim: P right-lost under a, N
   refused-right under b, T neighbour right-lost under a) with RF's binaries, and confirm the log rows reproduce
   bit-for-bit or say not. Check the binaries match the patches (rebuild one with $SP/harness/build.sh <out> <main.swift>
   <variant> through `$SP/heavy.sh <log> <cmd...>` if in doubt; heavy.sh takes a build slot and writes <log>.exit).
3. Fairness of the truth. For the neighbour-ring plants: is RF's truth (which ring, which R) a fair target for "right"?
   If a fit lands on the neighbour ring, or on a merged two-ring profile that is a legitimate optimum of a one-ring model,
   is it "wrong" in the sense the record means (the Fit returns a wrong ellipse to the user)? Measure, do not argue: cost at
   truth vs at each fit on the same pixels (RF's cost.py is unreviewed — check it or write your own), and b/a error.
   Similarly for Poisson: are the "right lost" ones right-by-luck at HEAD (HEAD at 0.09 %, a at 0.11 %), or real losses?
   Give the distribution of |dR| and |d(b/a)| for the lost ones.
4. Narrow rings: for b's refused-right fits, what is the true sigma, the fitted sigma, and the conic's error it falls back to
   (is the fallback within 1 %)? Is refusing them a loss the user would see?
5. Lanes: re-derive two lane headline numbers from their raw logs with your own parsing: lane M's wrong counts per variant on
   set A (claimed head 35 / a 0 / b 20 / ab 0; refused by b 15) from $SP/lanes/M/logs/, and lane P5's per-annulus agreement
   (claimed: same model 8/8, worst |da| 1.0e-5 px, a's estimator nil on 5 of 8) from $SP/lanes/P5/logs/. Reproduce or not.
6. Code read: a's estimator (binning, the elliptical radius formula vs the model's, the 3-bin mean edges, the crossing
   interpolation, the NaN paths, theta's sign) and b's guard (min of the two sigmas: a legitimately one-sided sharp edge?).
   Test any suspicion by experiment.
Verdict per candidate a, b, ab: UPHELD / UPHELD WITH CORRECTIONS / REFUTED, each with the evidence (log names, counts),
and a one-line plain statement of where each candidate is and is not safe. Say what you did not test.
Budget: re-derive from the logs; re-run only spot plants and any experiment you need (no full set re-runs). No test host,
no xcodebuild, no app. Final message <= 30 lines: verdicts, the corrected counts, path of report.md.
