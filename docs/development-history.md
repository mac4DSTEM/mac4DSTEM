# Development history

Detailed checkpoint-by-checkpoint agent notes were removed during the 2026-07-16
stabilization cleanup because they duplicated README, roadmap, test output, and Git
history while rapidly becoming stale.

The durable records are:

- [`v1-scope.md`](v1-scope.md) — frozen product and release contract.
- [`../ROADMAP.md`](../ROADMAP.md) — current priorities and scientific scope rules.
- [`training-dataset-evaluation-2026-07-15.md`](training-dataset-evaluation-2026-07-15.md)
  — reproducible real-data operational evaluation and its explicit limitations.
- [`releasing.md`](releasing.md) and [`distribution.md`](distribution.md) — package,
  signing, and notarization process.
- `tools/run-tests.sh all` — executable aggregate acceptance gate.
- Git history — implementation-level decisions and superseded checkpoints.

Historical counts or performance numbers should not be copied forward as current
claims. Re-run the relevant harness and record the hardware, build configuration,
dataset manifest, commit, and interpretation limits with any new measurement.
