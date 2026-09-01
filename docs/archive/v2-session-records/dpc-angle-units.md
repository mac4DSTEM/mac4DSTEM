# DPC angle units — Gate D and Gate B session record

**Date:** 2026-09-01
**Scope:** `core-analysis-physics-01` from the 2026-09-01 v2 triage.
**Constraint:** No production-code change until the Gate D experiment below
has run against the production implementation.

## Gate D preregistration — written before the experiment

### 1. Diagnosis as currently believed

`DPC.angleImage` stores direction as a normalized turn in `[0, 1)`: it takes
`atan2(cy, cx)`, wraps the angle into `[0, 2π)`, and divides by `2π`.
`AppState.applyDPCDisplay` publishes those pixels unchanged. The production
metadata path calls the product `DPC angle` with `valueUnits = "rad"`, and the
sidecar and PNG paths persist the same pixels with that unit string. Therefore
the app reports a value smaller than the claimed radian angle by exactly `2π`
for every nonzero direction.

Evidence before the experiment:

- `mac4DSTEM/Core/Analysis/DPC.swift`: `angleImage` divides by `2π`.
- `mac4DSTEM/App/AppState.swift`: `.angle` publishes `angleImage` directly.
- `mac4DSTEM/Support/ResultExport.swift`: `.angle` declares `rad`; sidecar
  persistence copies `image.pixels` and `metadata.valueUnits` unchanged; PNG
  provenance reads the same unit value.
- The 2026-08-31 review independently recorded the same source-level path, but
  explicitly left a production known-answer experiment owed.

### 2. Observation that would refute the diagnosis

The diagnosis is refuted if the production `DPC.angleImage` returns radian
values for known vectors, or if a production conversion multiplies its stored
values by `2π` before every path that claims `rad`. It is also refuted as a
shipping defect if the persisted/exported product declares normalized turns
rather than radians.

### 3. Predicted outcome of the discriminating experiment

Run the production `DPC.angleImage` on sign-discriminating vectors rather than
only cardinal/symmetric cases:

| `(cx, cy)` | Physical angle | Predicted shipping pixel | Correct radians |
|---|---:|---:|---:|
| `(0, 1)` | `π/2` | `0.25` | `1.570796…` |
| `(-1, 1)` | `3π/4` | `0.375` | `2.356194…` |
| `(1, -1)` | `7π/4` | `0.875` | `5.497787…` |

The production metadata inspection is predicted to return `valueUnits =
"rad"` for those unchanged pixels. Seeing both legs confirms the `2π` error;
either a radian pixel or a normalized-turn unit label refutes it.

## Gate D outcome

**CONFIRMED.** The experiment compiled the production `DPC.swift` unchanged
and observed:

```text
vector (0,1):  production=0.250000000  radians_expected=1.570796251
vector (-1,1): production=0.375000000  radians_expected=2.356194496
vector (1,-1): production=0.875000000  radians_expected=5.497786999
```

The production metadata branch simultaneously returned `("dpc_angle", "DPC
angle", "rad")`, and the sidecar writer copies the pixels and unit string
without conversion. The refuting outcome did not occur. The first compile
attempt did not run the experiment because Swift's default module cache was
outside the sandbox; the identical preregistered build ran with its module
cache redirected to `/private/tmp`.

Git history supplies the migration boundary: commit `919c0d0` introduced
`angleImage` with the `/ 2π` storage on 2026-07-05, and no later production
version stored radians before this session. Therefore an app-authored saved
result with `kind=dpc_angle`, `valueUnits=rad`, and no explicit encoding marker
is a legacy normalized-turn result.

## Implemented response

- `DPC.angleImage` now stores wrapped radians in `[0, 2π)`. The color-wheel
  code retains its independent normalized hue calculation.
- New scalar DPC-angle products carry `dpc_angle_encoding=radians` in result
  provenance, including the PNG provenance carrier and sidecar save path.
- The scalar sidecar reader converts legacy absent/`normalized_turns` encoding
  to radians exactly once, records the migration, leaves explicit `radians`
  unchanged, and refuses an unknown explicit encoding.
- `tools/idpc-test` gained independent NumPy known answers. It failed on the
  original production implementation (`max error 4.6227875`) and passed after
  the fix.
- `tools/sidecar-result-test` proves legacy conversion and current-radian
  round-trip through real HDF5, then reads the final radian data and metadata
  through vendored py4DSTEM. Its full run passed.
- `ProductWorkflowTests` pins the app/export encoding marker. Removing the
  production marker produced the required red; restoring it returned green.
- The sidecar save path now consumes a panel-free
  `currentScalarResultMapForPersistence` seam. Its test pins the exact `π/2`
  pixel, `rad` unit and `radians` marker handed to the writer; dividing that
  seam by `2π` made the focused XCTest fail (exit 65), then restoration made
  both focused DPC persistence tests pass.
- The in-memory session inventory and decoded current result now share one
  read-time DPC migration/refusal helper, so a legacy descriptor cannot
  disagree with its converted pixels. Restored foreign DPC results are not
  relabelled: the app synthesizes the marker only for a fresh app-authored
  radian angle result.

## Gate B

**SURVIVED after corrections.** A separate refuter found no remaining blocking
scientific or persistence defect. The review did find and close five gaps:

1. legacy current-result pixels migrated while the inventory descriptor kept
   raw provenance;
2. exact +x/signed-zero wrapping was unpinned;
3. the independent normalized hue contract for the DPC colour wheel was
   unpinned;
4. the AppState-to-`ScalarResultMap` composition was unpinned; and
5. unconditional marker synthesis could relabel a restored foreign angle.

Mutations actually run and rejected included normalized-turn production
(`max error 4.6227875`), swapped `atan2` axes, `a == 0 → 2π` (`6.2831855`),
radians fed directly to HSV hue (`max channel error 221`), save-seam `/2π`
(focused XCTest exit 65), legacy migration by `π`, relabel-without-scale,
explicit-radian double scaling, accepting an unknown encoding, and bypassing
descriptor normalization. No review mutation remains. The independent oracle
is mathematical NumPy `atan2`/mod rather than a claimed py4DSTEM port:
vendored py4DSTEM exposes corrected CoM components but no standalone wrapped
direction-map convention.

## Verification and closeout

- `tools/run-tests.sh all`: **exit 0**, 44/44 harnesses completed, including
  42 scientific harnesses, real-data acceptance and packaging. Four real-data
  `SKIP` lines were the expected `.mac4dstem.h5` sidecars; the advisory
  `UNPINNED` line still names four measured cubes.
- Standalone `tools/run-tests.sh unit`: **exit 0**, **393 passed / 2 skipped /
  0 failed**, read from the retained xcresult bundle. The two skips are the
  documented unmounted-volume bookmark probe and the explicit uncalibrated
  Prepare geometry quarantine.
- Focused `tools/idpc-test` and real-HDF5/py4DSTEM
  `tools/sidecar-result-test`: **exit 0** after the final Gate B changes.
- Track B row **F1.47** is queued. The numerical colourbar/export carrier is
  **not verified on screen** until the owner drives the current Xcode build.
- Closeout kickoff tax: **3790 lines** (`CLAUDE.md` 349 + `open-items.md` 2479
  + `v2-release.md` 962), up 23 from the session's starting tree; the increase
  is the live status and unverified-row record rather than duplicated narrative.

Not verified or deliberately outside this scope: DPC-specific provenance read
back from a manually exported PNG (the generic PNG carrier has an actual-file
unit test); NaN/Inf CoM semantics, which remain unspecified; and the inherently
ambiguous case of a third-party file imitating an app-authored markerless legacy
sidecar. The living v2 board was not republished because the Artifact tool was
not exposed in this session; closeout leaves that owed.

Skill note: `pickup`, `diagnose`, `adversarial-review`, `track-b` and `closeout`
all triggered at their intended boundaries. None misfired; the separate review
materially changed both code and fixtures before the session was called done.
