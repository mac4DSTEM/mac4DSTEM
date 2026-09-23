# Precipitate objects: a data-free cross-check of `classObjects` (2026-09-23)

**Nothing here ran Swift.** This container has no Swift toolchain. Every statement below about
what the app does comes from reading the source, not from running it. Swift sources read at HEAD
`996eddd` (no Swift file differs from `3d0134a`, where the reading started). Neither Gate D
trigger applies: no app code, test or default changed.

## What was cross-checked

`tools/cloud-analysis/precipitate_objects_ref.py` re-implements, in stdlib + numpy, `classObjects`,
`measure`, `connectedComponents`, `principalAxis`, `labelImage` (`PrecipitateSegmentation.swift`,
"SEG"), `PrecipitateStatistics.density` ("STA") and `PhaseMapObjectsBridge.labeledMap` ("BRI"),
each definition citing its SEG/STA/BRI line. Swift `Float` is reproduced in float32 in the same
operation order, including the flood-fill visit order. It is a reference, not the app.

- `selftest`: 18 **T-** cases recompute every assertion of `PrecipitateSegmentationAnalyticTests`
  (8 tests), `PhaseMapObjectsTests` (5), the three classObjects/density tests in
  `PhaseMapObjectsWiringTests` and the two hand-built density tests in `PrecipitateTests`. Six
  **X-** cases pin doc-comment rules that **no Swift test pins**.
- `mutate`: one-token mutants of the reference must turn a T- case red (M14: expected gap).
- `crosscheck`: 200 random maps vs `scipy.ndimage.label` (3×3) and float64 `numpy.linalg.eigh`.

Run 2026-09-23 (Python 3.11.15, numpy 2.4.6, scipy 1.17.1):
`python3 -B tools/cloud-analysis/precipitate_objects_ref.py all > ref-all-2.log 2>&1`, then
`echo $?` → `0`. The log is in the session scratchpad, not retained; summary lines quoted:

```
selftest: 24 cases, 24 PASS, 0 FAIL        (18 T- cases, 133 checks; 6 X- cases, 13 checks)
M1  8- -> 4-connectivity            KILLED  T-ANA-4,T-ANA-2,T-PMO-2
M2  length drops the +1             KILLED  T-ANA-1,T-ANA-4,T-PMO-1,T-PMO-4
M3  width drops the +1              KILLED  T-ANA-4,T-PMO-1,T-PMO-4
M4  edge rule drops bottom row      KILLED  T-ANA-3              (only case that catches it)
M5  edge rule drops right column    KILLED  T-ANA-3,T-PMO-1,T-PMO-4,T-WIR-c
M6  edge rule row==1 (M9-like)      KILLED  T-ANA-3,T-ANA-5,T-PMO-1,T-PMO-4,T-WIR-c
M7  orientation sign flipped        KILLED  T-ANA-4              (only case that catches it)
M8  not-indexed kept in area        KILLED  T-PMO-3,T-PMO-4,T-WIR-b,T-WIR-c
M9  refusal lets negative px in     KILLED  T-ANA-5
M10 edge objects counted            KILLED  T-ANA-3,T-PMO-1,T-PMO-4,T-WIR-c,T-PRE-D2
M11 median takes upper element      KILLED  T-PRE-D2
M12 classes merged (>= label)       KILLED  T-ANA-6,T-PMO-1,T-PMO-2,T-PMO-3,T-PMO-4
M13 half-max 0.5 -> 1.5 (collapse)  KILLED  T-ANA-1,T-ANA-4,T-PMO-1,T-PMO-4
M14 tie-break reversed              GAP confirmed: no T- case fails; caught only by X-5
M15 other labels leave area (multi-token, the gateD-2026-09-21 mutant)  KILLED  T-PMO-3
mutate: every mutant behaved as expected
crosscheck: 200 random maps, 2382 objects vs scipy.ndimage.label(3x3) ...; 1014 anisotropic
  objects vs float64 eigh: worst |d orientation| 2.05e-04 deg, worst |d length| 3.65e-06 px -> PASS
```

Every value agrees. Only the Python was mutated; M14 surviving the Swift suite is inferred.

## Disagreements between code, doc comments and test expectations

1. **"Length" is centre span + 1, not end-to-end.** The `Object` doc (SEG:43) says "pixel extents
   along and across the principal axis (end to end)"; the code takes the span between outermost
   pixel centres plus 1 (SEG:430-431), which is the end-to-end extent only for a horizontal or
   vertical axis. The analytic test pins 4√2+1 = 6.657 for the 45° five-pixel diagonal and calls
   it the length "along the true axis" (`PrecipitateSegmentationAnalyticTests.swift:104-107,123`);
   the unit squares span 5√2 = 7.07, and the 1-px diagonal's width reads 1 where its squares span
   √2. `PrecipitateTests.swift:282-285` already concedes the +1 "is exact only when the object's
   axis is axis-aligned". Direction is the true principal axis (M7, crosscheck); the extent is an
   orientation-dependent convention. Owner: state it in SEG:43, or change it.
2. **A test comment names the wrong branch.** The diagonal test reasons v = 0, so width comes
   from the `else 1` branch (test :104, :124). In float32 cos 45° ≠ sin 45°: the reference gives
   width `1.0000002`, orientation `44.999996`, i.e. `vMax - vMin + 1` runs. It passes only inside
   the 1e-6 tolerance. Inferred from the emulation; Swift's `cosf`/`sinf` may round differently.
3. **Header oversells the covariance:** SEG:9-10 says measured "from the pixel-coordinate
   covariance"; only the axis is (SEG:418). SEG:43-47's "Historically … 4 x sqrt" is dead text.
4. **Orientation is consistent.** x = column, y = row (SEG:410-411); atan2(vy, vx) from +x toward
   +y (SEG:511); the doc says positive reads clockwise on screen (SEG:65-69). The (-90, 90] fold is
   right: +90 only when cxy == 0 exactly, −90 never (vx = λ1 − cyy > 0 whenever cxy ≠ 0). Only
   X-3 (vertical → +90) and X-4 (anti-diagonal → −45) pin these on a class map; no T- case does.
5. **touchesEdge matches its doc** — the map's four borders (SEG:401, STA header). A not-indexed
   hole is not an edge: B1 in `PhaseMapObjectsTests` touches two N pixels and is counted, so an
   object cut short by missing data counts at full weight. A question of meaning, not a mismatch.
6. **Mixed bases, documented.** `pixelCount`/`areaFraction` include edge objects (SEG:365,368);
   the density count and length summaries exclude them (STA:106-121). The inspector prints
   `density.acceptedCount` as "N objects" (`UI/PhaseMappingSettings.swift:682-683`), so edge
   objects drop out of that count unannounced. Presentation only.
7. **Test comments with wrong details (no expected value affected):** analytic test 3's header
   promises an interior pixel in the 6×6 map (there is none; the control is a separate 5×5) and
   says "every pairwise row/col gap is >= 2" ((2,0)/(3,5) have a row gap of 1; the Chebyshev ≥ 2
   claim that matters holds). `PrecipitateTests.swift:612-619` still speaks of "object 3's 15 px"
   though object 3's length is 999. The analytic test's MARK numbers run 1,4,2,3,6,5,7a,7b.
8. **Tie-break order is unpinned** (M14): equal areas are ordered by first pixel index
   (SEG:346-350) and ids follow across classes (SEG:351-360); reversing it fails no T- case.

## Open-items "Precipitate segmentation defects", re-checked by reading HEAD

Read only, nothing re-measured; `segment()` and `PrecipitateReflections` have no caller outside
`Core/Analysis/Precipitates/`, so "unwired" holds.

| defect | status at HEAD | where |
|---|---|---|
| Contiguous invalid region fabricates objects | **Still present**: median imputed, threshold over the whole `filtered` | SEG:235-243, :260, :472-479 |
| Non-finite pixels on a feature erase it silently | **Still present**: `valid[i] = false`, no imputed count; `segment` returns `[Object]` only | SEG:239-242, :184-186 |
| `1.4826 * mad` and the median fill unpinned | **Still present**: no test mentions 1.4826 or tells median from mean. The detail file's `:305` / `:104-107` are stale — now :477 / :179-183 | SEG:477, :238 |
| Dark ridges register through their flanks | **Still present**: `max(0, -lambdaMin)`, doc still says troughs "never register"; no dark fixture | SEG:519-547 |
| Negative peak collapses an object to 1×1 | **Still present in `segment()`**: `half = 0.5*peak`, `thresholdSigmas` unvalidated (SEG:33). Impossible in `classObjects`: binary footprint (SEG:338), peak = 1 | SEG:420-431 |
| NaN beside a maximum passes | **Still present**: `isFinite` on the candidate only; `NaN > v` is false | `PrecipitateReflections.swift:124-129` |

## The refuter's two small errors (overnight record §7): both in the probe only

- **"Label 4 is excluded from the analysed area"** is a probe comment
  (`tools/phase-map-probe/main.swift:1548-1555`). App code does what its doc says: a label in no
  role set is indexed "other" and stays in the area (SEG:310-313, :330-333); X-1 reproduces it
  (two label-4 pixels → other 2, analysed 16 of 16). The comment cites
  `phase-map-objects-gateD-2026-09-21.md` as precedent; lines 16-21 there say the opposite.
- **Label identity by phase order** is probe-only: `--object-table` compares truth labels 0-3
  with the bridge's `phaseIndex` and hard-codes names (main.swift:1557-1558, :1644). The app
  never compares to outside truth; bridge (BRI:47-65) and inspector
  (`PhaseMappingSettings.swift:663-668`) both index `map.phaseNames` — consistent by construction.
- **A third probe-only difference, not in §7:** the Step 3 table's "median length" is the
  upper-middle element over **all** objects incl. edge ones (main.swift:1611-1614), and its
  "objects" column is `objects.count` (:1659, :1664). The app's `medianLength` excludes edge
  objects and averages the middle pair (STA:106-120). The table is not the app's definition.

**For whoever lands this:** `inventory` fails on an unclassified `tools/` directory
(run-tests.sh:108-134) and `cloud-analysis` is in no list — add it to `diagnostic=(…)` first
(not done here: two-file limit), or inventory and the pre-push hook go red.
