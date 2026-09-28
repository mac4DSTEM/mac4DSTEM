# B1 — a narrow guard for θ′ edge-on inside T1: registration and result (2026-09-28)

Follows `b1-edge-on-gateD-2026-09-28.md` and its full-resolution addendum: 4 of the 7 spurious edge-on objects (5
positions) are edge-on calls deep inside truth T1, each resting on one edge-on-specific reflection with T1 as the
runner-up. Measurement in `tools/phase-map-probe` only; no `mac4DSTEM/` code changes and no default moves in this step.

## Registered before the run

**The rule.** At a position where the winner is θ′ edge-on, the winning entry matches exactly one edge-on-specific
reflection (not shared with Al; the shipped guard's own count), and the runner-up phase is T1, the label becomes T1.
*Reported, not scored:* the same rule sending such positions to Al instead.

**Why this rule, and why edge-on only.** Edge-on's entry is dense (46 vectors, chance match 1.2 %) and overlaps T1's
reflection set. Where T1 is the alternative, one extra reflection is within what chance and T1's own weak reflections
supply, so it is not evidence against T1. The rule has no tunable number: "one" is the shipped guard's minimum, and
the runner-up is the matcher's own. A global k = 2 was rejected earlier because it also removes single-reflection T1
calls; this rule touches only edge-on-over-T1.

**Configuration.** T4's scored run: known-variants, `--or`, floor 0.15 %, `--min-intensity 0`, shipped guard k = 1,
plus `--edge-t1-guard t1` (primary) or `al` (reported). Scored by `t4_score.py` against the stride-3 truth.

**Holdout.** The rule was designed from positions in both halves (cols 10 and 91–126). It is reported separately for the
left (cols < 86) and right (cols ≥ 86) halves, and must help in both.

**Predictions (primary, `t1`).**
- **P1.** θ′ edge-on raw spurious objects 7 → 3. The 4 T1-interior objects go; the 3 needle-edge ones stay. Refuted if ≠ 3.
- **P2.** Every scored T4 metric passes. Refuted if any fails.
- **P3.** Per-position error 1.31 % → 1.26–1.33 %.
- **P4.** At most 11 of the 398 correct edge-on calls are lost; the edge-on area ratio stays within its limit.
- **P5.** In each half, positions fixed (truth T1, now T1) ≥ positions broken (truth edge-on, now T1). Refuted if not.

The run counts only if the rerun without the flag reproduces the T4 labels (label arrays equal) and the scorer's own
validity checks hold (the truth passes; the null fails).
