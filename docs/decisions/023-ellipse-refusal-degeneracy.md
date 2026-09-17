# 023 — Ellipse refusal is a degeneracy bound; the flag sits behind a click

Dates: 2026-09-14, 2026-09-15

Status: live

## Decision

The ellipse fit refuses on a degeneracy bound, not the withdrawn
percentile-bin test (ADR 022): three statistics (azimuthal contrast, fit
residual, radial multiplicity) were each measured against a fixture sweep
and all three failed to separate a three-grain annulus from a legitimate
sparse ring — the two occupy the same twelve azimuthal bins and differ in
nothing measurable except the answer. The guard refuses wherever five
parameters cannot be decided by spots at a dozen azimuths, whether or not
the answer would have been right. The owner's requested fix — fit anyway on
a sparse legitimate ring — follows an explicit click, never a silent mark:
the Prepare panel offers "Fit Anyway" only when a retry could succeed
(12–29 of 36 sectors), and the result is marked `Fit anyway` in orange on
the readiness row. "Fit Anyway" still refuses more than one ring, bounded by
per-sector mean-radius spread across the fitted centre (10%).

## Why

A silent mark on an auto-applied value would let a 68% "ellipse" back into
strain with a word beside it — the defect the refusal existed to close. A
three-grain annulus and a sparse single ring are the same measurement to the
fitter; only the person who placed the annulus knows which it is.

## Governs

The ellipse-calibration refusal logic and the Prepare panel's "Fit Anyway" control.

## Sources

- 2026-09-14 (later) "the ellipse refusal is a degeneracy bound, on the owner's decision", log line 1318
- 2026-09-15 "the ellipse flag sits behind a click, and \"fit anyway\" still refuses more than one ring", log line 1339
