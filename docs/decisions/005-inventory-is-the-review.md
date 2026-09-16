# 005 — The inventory gate is the repo's review

Dates: 2026-09-02

Status: live

## Decision

`tools/run-tests.sh inventory` runs at every closeout and in CI. Three
independent whole-codebase review passes converged on the same findings; what
drifted afterward was the repo's state, not the findings, so the state is now
checked by script instead. No further whole-codebase review passes are
commissioned.

## Why

A one-off review goes stale the moment the tree changes again; a script that
runs every time does not.

## Governs

`tools/run-tests.sh inventory`, CI's `inventory` job.

## Sources

- 2026-09-02 "The inventory is the review", log line 54

Evidence: `tools/run-tests.sh` (verified: has an `inventory)` case).
