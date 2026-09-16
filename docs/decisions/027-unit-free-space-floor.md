# 027 — `unit` free-space floor 4 GB

Dates: 2026-09-12

Status: live

## Decision

`run-tests.sh unit`'s free-space preflight floor drops 8GB → 4GB, not to the
owner-suggested 6GB. `scientific` and `benchmark` keep 4GB already; `all` and
`campaign` keep 8GB because nobody has measured their peak.

## Why

Sampling free space every 3s through a full `-only-testing:mac4DSTEMTests`
run measured peak consumption 1245MB, and the suite completed 602 passed / 0
failed with 7GB free — below the floor that had been refusing to start it.
4GB is 3.2× the measured peak, chosen by measurement rather than by guess;
lowering an unmeasured floor (`all`/`campaign`) would be exactly the guess
this change refuses to make.

## Governs

`tools/run-tests.sh`'s preflight floor values for `unit`/`scientific`/`benchmark` vs. `all`/`campaign`.

## Sources

- 2026-09-12 "the `unit` free-space floor drops 8 GB → 4 GB, on a measurement", log line 1124
