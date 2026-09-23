# Q-calibration design — closed process sections (moved 2026-09-23)

Two sections moved verbatim out of `docs/q-calibration-design.md` when it
was brought current for HEAD: S13's build order (§5, all seven items
shipped 2026-08-28–2026-09-05) and S12's own list of what its design left
unverified (§7, every item answered by S13's Gate D/B work, §§1–4 and §§8–9
of the live file). Section numbers §1–4, §6, §8, §9 stay in
`docs/q-calibration-design.md` unmoved and unrenumbered — they are cited by
exact section number from shipped code (`Core/Data/Calibration.swift`,
`Core/Analysis/QCalibration.swift`, `Session/SessionGates.swift`,
`Session/QCalibrationRun.swift`, `mac4DSTEMTests/QCalibrationOriginGateTests.swift`,
`tools/origin-fit-diagnostics/*.swift`) and from `CHANGELOG.md`'s v4.0.0
entry, none of which this pass may edit.

---

## 5. What S13 should build, in order

S13 is **Gate B** (`docs/archive/v2/v2-release.md` §8): a separate agent briefed to refute,
plus a `tools/` fixture whose negative controls name the line they break.

1. **Robust origin fit.** Iteratively-trimmed plane refit (§1.2). This is the
   largest single win and it changes both what the app *computes* and what it
   *refuses* — on Particle_1 it improves the fitted origin by up to 6 px and
   turns a wrong refusal into an admission. Fixture: the trimmed-vs-untrimmed
   fit on a synthetic map with a planted outlier population, plus the
   `tools/origin-fit-diagnostics` numbers as the real-data anchor.
2. **The origin fallback.** S11's confirmed worst finding — `.fileMean` /
   `.sessionMean` leaving `calibration.origin` nil so `calibratedBraggVectors`
   substitutes `(qx/2, qy/2)` for the file's recorded beam centre, in Q
   calibration, strain, ACOM and the Bragg map at once. **One policy owner for
   the fallback**, replacing the four divergent derivations S11 catalogued.
   Note S11's blind spot: every `QCalibrationOriginGateTests` case builds origin
   *maps*, so the suite has never run the nil branch — a test that exercises it
   is part of the fix, and must be broken before it is trusted.
3. **The split** (§2), on the S7 `SessionGates` seam, not as a fifth copy.
4. **The estimator-internal checks** (§3), each with its threshold measured by
   its own pre-registered experiment, never invented.
5. **The refusal text** (§1.1) — it leads with three fit functions that
   provably cannot clear the gate on either dataset where it is shown, and
   buries manual entry, the one remedy that works, at the end. It should say
   what actually failed (broad measurement failure vs excluded outliers) and
   lead with the remedy that succeeds.
6. **The strain-weighting provenance key** — already S13's from S11, unchanged
   by this session.
7. **Not** the coarse step (§4).

## 7. What S12 did **not** verify

- **Nothing was implemented or reviewed.** This is a design; §3's thresholds do
  not exist, and §1's robust fit is a measurement made by a diagnostic tool, not
  by app code.
- **§3's two checks were not prototyped against data.** Their *shape* follows
  from S11's structural findings and §1's measurements; their discriminating
  power is asserted, not demonstrated. That demonstration is S13's pre-registered
  experiment, and it may refute the design.
- **The trimmed refit is a plane refit**, matching the app's default. Whether
  trimming should also be offered for the constant and parabola fits is not
  addressed.
- **Two of four datasets carry no phase model**, so Q calibration has been
  exercised end to end on exactly one (sim_Au). Every claim about the Q
  estimator's *behaviour* here is read from the code path and from S11's
  triage, not from a red test.
- **The cost table is synthetic-pattern timing** of the kernel alone. The coarse
  loop's cost is data-independent by construction (fixed iteration count, no
  early exits), but the stage percentages combine that timing with the
  campaign's wall-clock stage time on real data — two runs, not one
  instrumented run. **The tile heights are this machine's**: `scanTileRows`
  bounds them by physical RAM, so an 8 GB and a 16 GB machine do not tile the
  same and will not reproduce these ratios exactly.
- **Three claims in the first draft of this document were refuted in review and
  are corrected above, not quietly dropped:** that the refusal's remedies
  "cannot work" (the fourth, manual entry, does — and a Gate B decision from
  2026-08-25 says so); that a robust fit "clears the gate" (it does not — the
  gate's statistic has to change too); and the entire §4 cost table (timed at
  invented scan shapes rather than the tile grid the app dispatches). The
  design's conclusions survived all three, but two of them survived with
  different reasoning than they were first given.
- **Track A was not run**, and is not owed: nothing under `mac4DSTEM/` was
  touched.
