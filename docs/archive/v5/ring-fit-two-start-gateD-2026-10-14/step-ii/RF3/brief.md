# Refuter RF3 brief — ring-fit two-start Gate D, step (ii) (fresh; independent; you wrote none of this)
SP = /private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/91438f32-5c41-4f54-be46-379a85bee9b3/scratchpad
REPO = /Users/paullobpreis/GitHub/mac4DSTEM_Organization/mac4DSTEM (READ-ONLY). Write only in $SP/lanes/RF3/. Do NOT read $SP/lanes/G
(another lane's fixture work) or $SP/ii/analyse_ii.py / its output (the session's own analysis): write your own parser.

What is claimed. The record $REPO/docs/archive/v5/ring-fit-two-start-gateD-2026-10-14.md: step (i) (the owner's real patterns) and the
step (ii) registration (candidates c = two starts keeping the lower cost, b2 = the 0.25 px floor guard, s = an 8 % seed check, and the
combinations cb, cs, cbs; `none` = the refactor alone; predictions Q0-Q6). Candidate code: $SP/patches/EllipseCalibration.<v>.swift
(generated from $SP/patches2/master.swift by gen.py). If a candidate lands, the b/a and θ the app applies to every Bragg vector change
on the owner's data. Your job: find what would make landing it wrong. Review the diagnosis and the measurements, not the diff's style.

Material: raw logs $SP/ii/logs/<set>_<variant>.log (rf2 rows, harness $SP/lanes/RF2/src/main.swift; sets A, B, C, P, N, T, S3, S4 —
plants in $SP/data/plants{A,B}, $SP/lanes/RF/data/plants{C,P,N,T}, $SP/lanes/RF2/data/plants{S3,S4} with planted.json truth; binaries
$SP/ii/bin/rf2-<v>); real sources: $SP/cubes/runs2/<src>-<v>.log (harness $SP/cubes/harness/main.swift, binaries $SP/cubes/bin/fit-<v>,
inputs and annuli under $SP/cubes/{almgsi,ws2,nicu} and $SP/cubes/au-annuli.txt with $SP/au/au_mean.f32); step-2 history in
$REPO/docs/archive/v5/ring-sigma-start-gateD-2026-10-13.md and its step2/RF2/report.md.

Predictions first into $SP/lanes/RF3/report.md, then at least:
1. Own parser: per set and variant, wrong (> 1 % in (a+b)/2, any accepted model), right (<= 0.1 %), right lost vs head, newly wrong,
   new throws, accepted fits with |d(b/a)| > 0.01. Check each registered prediction Q0-Q4 against your numbers; say held / not held.
2. The two-start rule's weak point: "lower cost" is not "closer to truth" (step 2 found 8 of 441 disagreeing pairs where the worse fit
   costs less; gapped rings with a gap-less model). Find every plant where c picks a fit farther from the truth than the other start's
   (rerun a few with an exposed copy if you need both starts' fits) and size it in b/a and θ — what the app applies.
3. The seed check out of sample: the 8 % was set on step 2's in-sample rows. On S3/S4 (tails) and the real sources, does s refuse a
   right fit, or keep a wrong one it should catch? Is the conic it falls back to any better (b/a)? Are there real-data cases (step (i))
   where the conic seed itself is biased (sloping background) so that "far from the seed" is the right fit?
4. The guards' order and per-start semantics: in cbs a start refused by a guard hands the choice to the other start. Construct or find
   a case where that makes cbs worse than both c and b2/s alone.
5. Code read: refine(start)'s closure captures, the error chosen when both starts fail, ties, NaN paths, the half-maximum estimator
   reused from step 2, the 0.30 px and 8 % constants, and whether `none` is truly behaviour-identical to HEAD (check Q0 on all rows).
6. Real data: the owner's cubes (step (i)) — is any change cbs makes there wrong by a truth-free check (b/a agreement across annuli of
   one source, mean pattern vs map of one cube)?
Verdict per candidate c, b2, s, cbs: UPHELD / UPHELD WITH CORRECTIONS / REFUTED, with evidence (log names, counts), and one plain
line each on where it is and is not safe. Say what you did not test. Budget: parse the logs; re-run only what an experiment needs (a
swiftc build goes through $SP/heavy-build.sh <log> <cmd...>); no xcodebuild, no test host, no app. Final message <= 30 lines.
