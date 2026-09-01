# Probe radius — Gate D + fix (2026-09-01)

Step 1 item 7 (owner decision 2026-09-01). Scope:
`Core/Analysis/OriginCalibration.swift` call sites only — `probeSize` itself
is untouched. Gate D first (the recorded discriminator, run on real data for
the first time), then the fix, then Gate B (refuter authorization requested
from the owner at session end).

## Gate D — pre-registered, run, confirmed on every prediction

**Hypothesis** (recorded 2026-08-28, confirmed on synthetic only): `probeSize`
measures the equivalent-circle radius of above-threshold pixels faithfully,
but is fed `statistics.maxDP` — the pixel-wise max over the scan, where every
Bragg disk seen anywhere exceeds threshold and is counted as probe area.

**Instrument**: new `tools/origin-fit-diagnostics/run.sh probe-size` mode —
the REAL `probeSize` via the real pipeline (`tiledRun`), fed maxDP, meanDP,
and the two lowest-sum single patterns per dataset. Measures, does not
assert; not gated (needs gitignored training data).

**Results** (all px; "app" = shipped `tiledRun` figure):

| dataset | app | maxDP | meanDP | minSum | p05Sum |
|---|---|---|---|---|---|
| SPED_MgO (114×109) | 14.138 | 14.138 | 5.434 | 2.964 | 2.952 |
| SPED_MgO_1 (228×219) | 19.068 | 19.068 | 5.436 | 5.334 | 5.615 |
| Si_SiGe (50×200) | 5.026 | 5.026 | 3.738 | 2.619 | 2.282 |
| Particle_1 (90×45) | 10.624 | 10.624 | 6.123 | **31.767** | 2.263 |
| polycrystal_2D_WS2 | 1.859 | 1.859 | 1.858 | 1.858 | 1.865 |
| sim_Au | 6.096 | 6.096 | 5.113 | 5.117 | 5.046 |

- The shipped numbers ARE `probeSize(maxDP)` — 14.138 and 19.068 reproduce
  the owner's 14.1 (2026-08-28) and 19.1 (2026-09-01 screenshot) exactly.
- **The causal clincher is within-file** (wording corrected by Gate B, which
  found the cross-file version confounded): nested sub-scans of SPED_MgO_1 —
  one dtype, one preprocessing — read **16.07 → 16.50 → 19.07 px** as the
  scan grows 57×54 → 114×109 → 228×219, and SPED_MgO reads 13.14 → 14.14. A
  per-pattern property cannot do that; a union of every disk seen anywhere
  does. The cross-file 14.14-vs-19.07 pair points the same way but also
  carries a float64-vs-uint8 and field-of-view difference (~2.5 px of it),
  so it must not be quoted as a pure scan-area effect. Both refutation
  candidates die either way: meanDP ≉ maxDP, and maxDP is nowhere near the
  visible disk.
- The max-union also drags the CoM centre **2.6–2.7 px** from where every
  other input puts it — the recorded origin-bias mechanism, live on real
  data.
- **Parity fact that reframes the fix**: py4DSTEM's own origin path feeds
  `get_probe_size(dp_max)` (`process/calibration/origin.py:268`) while its
  docstring says "a position averaged … DP works best" (other py4DSTEM call
  sites use the mean or a vacuum probe). The app faithfully copied the
  reference's weakest usage; the defect is inherited, and the fix is a
  DEVIATION-with-reason from py4DSTEM's origin path *toward* py4DSTEM's own
  documented recommendation.
- **Alternatives pre-refuted by the same table**: a single low-sum pattern is
  NOT a safe input (Particle_1's minimum-sum position returns a pathological
  31.8 px); meanDP is never worse than maxDP anywhere in the corpus and
  tracks the substrate proxies on sim_Au and both SPED cubes. Its residual
  inflation on Si_SiGe (3.74 vs ~2.4) is descan blur — bounded by real beam
  wander (which is arguably the right scale for a kernel), unlike maxDP's
  unbounded growth.

## The fix

Both `probeSize` call sites in `OriginCalibration` now feed **meanDP**
(`tiledRun` and the resident-cube variant), each with a DEVIATION note
carrying the measurement. `probeSize` itself is unchanged — its recorded
2.15×/demo behaviour was the max-union input, not the formula.

## Verification

- `mac4DSTEMTests/ProbeSizeTests` — **the estimator's first unit coverage**
  (a Group-D-class gap found in passing): clean-disk recovery, the
  Bragg-inflation mechanism pinned as documentation, and the load-bearing
  pin — `tiledRun` must equal `probeSize(meanDP)` on a satellite cube where
  max and mean discriminate by >1.5×.
- **Broken before trusted**: call sites reverted to maxDP + π doubled in
  `probeSize` → all three tests red, each for its own reason; restored.
- Gates: unit + scientific runs on the final tree (counts in closeout).
  Expected ripple reviewed deliberately, not re-baselined blindly — the demo
  and every dataset's kernel radius, minPeakSpacing, CoM window and
  origin-gate threshold shift with the smaller radius.

## Consequences, stated

`Calibration.probeRadius` feeds the synthetic kernel, `minPeakSpacing`, the
CoM refinement window, the ptycho cutoff, and the origin sanity gate
(`residual ≤ probeRadius`). The smaller (honest) radius makes that gate
STRICTER — datasets may flip from quietly-accepted to refused, which is the
safe direction under the refusal rule but is a behaviour change the owner
will see. Track B row queued (the overlay circles and readiness rows draw
differently).

## Gate B — RAN 2026-09-01, verdict STAND WITH CORRECTIONS, all applied

The refuter rebuilt the pre-fix importer from `git show HEAD:` and reproduced
every number to the digit; ran the record's named-but-unmeasured failure
modes as 8 deterministic synthetics (meanDP ≤ maxDP and closer to truth in
ALL of them — worst mean case, descan ±5 + Bragg: 8.35 px vs max's 15.17
against truth 4); verified both DEVIATION cites verbatim; and measured the
satellite fixture's discrimination as real (1.979×) through the production
GPU path, with the self-consistency trap closed by the absolute-geometry
anchor test.

**Its paying-question answer: one survivor.** Reverting ONLY the
resident-cube call site survived every gate — `OriginCalibration.run(cube:)`
has **zero callers in the repo**, so no test could see it (measured: 8.44 px
from the mutated variant vs 4.27 from the mean while every shipped test
stayed green). Its added `testResidentCubeRunMeasuresTheProbeOnTheMeanPattern`
kills it (verified red under the mutation, green restored); deleting the
dead variant instead is noted as an owner option in the code. Full unit
suite on the final tree: **402 passed / 2 skipped / 0 failed, exit 0** (the
refuter's own run).

**Two of this record's claims corrected by measurement:** (1) the demo
kernel went to **6.93 px, not "the drawn 4.5"** — the session's triage read a
test-fixture constant as the app's value; the demo draws rings into every
pattern, so the mean keeps their reduced-strength share (the scan-union
share is what collapsed); (2) the scan-size clincher rewritten within-file
as above; CoM drag corrected to 2.6–2.7 px. Also corrected: stale
"max pattern" text in the `OriginCalibration` header, the `run(cube:)`
docstring, and the diagnostic tool's printed label.

## Not verified / residuals

- On-screen: new radius on the overlay/readiness surfaces (Track B row
  F1.49; its expected SPED figure is ≈5.4 px).
- meanDP's own failure modes remain recorded, unmeasured on a strong
  amorphous-background specimen (no such cube in the corpus); the
  min/p05-sum columns of the new diagnostic are the standing instrument.
- The acceptance-threshold factor from the original SPED_MgO observation
  (`Minimum absolute 0 CC`, `relative 0.5%` admitting noise) is SEPARATE and
  untouched — the recorded entry said not to blur the two, and this session
  did not.
