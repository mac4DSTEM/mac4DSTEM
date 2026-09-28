# Phase mapping's first run under the adopted object-level pass bar (T4) — 2026-09-28

The bar: `docs/cloud/2026-09-23/T4-object-preregistration-DRAFT.md`, adopted in ADR 040. The data is
Thronsen et al. (2024) dataset A at stride 3, with its truth (`References/thronsen-datasetA/`,
CC BY 4.0). This is measurement only: no `mac4DSTEM/` source changes, and phase mapping stays
badged unvalidated whatever the verdict. One dataset with truth is not "validated"
(CLAUDE.md, "Unvalidated stays labelled").

## Registered before the run

**Scored configuration (primary).** The shipped matcher as the owner runs it:
- the known-variants rule, per-phase slab, `--or`, library intensity floor 0;
- detection floor **0.15 %** (`--min-relative 0.0015`, the owner's working floor since
  2026-09-23);
- the phase-specific-reflection guard **k = 1** (shipped on, ADR 038). This is the probe's
  `guarded` map, which ADR 038 showed byte-identical to the app's guard.

**Reported, not scored:** the unguarded map at the same floor, and the shipped default floor
0.5 % (`--min-relative 0.005`, guarded).

**Scoring (the adopted bar, made operational).** Everything is on the stride-3 grid, with the
cleanup rule P applied to the prediction as P/9, areas rounded up. The H/9 bracket is reported
beside it.
- **"Within the published range" means no worse than the worst of the four published methods**
  on the same footing (`T2-T3-report-output.md`, § Stride 3, rows "stride then P/9"; raw rows for
  the raw metrics). A value better than every published method passes.
  - For error counts (spurious, split, merge, vanished): app ≤ the published maximum.
  - For ratios to truth (count, median length, area fraction): |app − 1| ≤ the largest published
    |ratio − 1|.
- **This is my operationalisation; the owner may overrule it.** The literal alternative,
  "inside [min, max]", would fail a map for being better than all four methods (for example a
  T1 area ratio of 1.000 against the published 0.949–0.988). The bar never meant that.

| metric (class) | published limit (stride 3) | source rows |
|---|---|---|
| raw spurious objects (T1 / face-on / edge-on) | ≤ 13 / ≤ 113 / ≤ 5 | raw rows |
| raw merges (T1 / face-on / edge-on) | ≤ 1 / ≤ 0 / ≤ 16 | raw rows |
| split / merge / vanished after P/9 (T1) | ≤ 2 / ≤ 0 / ≤ 5 | "stride then P/9" |
| split / merge / vanished after P/9 (face-on) | 0 / 0 / 0 | "stride then P/9" |
| count ratio (T1 / face-on) | within 0.08 / 0.00 of 1 | ratios, "stride then P/9" |
| median length ratio (T1 / face-on) | within 0.33 / 0.03 of 1 | same |
| area fraction ratio (T1 / face-on / edge-on) | within 0.051 / 0.068 / 0.360 of 1 | same |

θ′ edge-on is scored only on area fraction and raw spurious objects, as the bar says. Its raw
merges are reported, not scored. **The verdict is PASS only if every scored metric passes.**

**The run counts only if:**
1. **The null map FAILS the bar.** The null is the stride-3 truth with Al positions flipped to
   face-on and T1 at the scored map's own measured false-call rates (seed 20260928). This is the
   stride-3 null of `tools/cloud-analysis/refute_null_maps.py`, built from the stride-3 truth
   because the full-resolution truth is not on this disk.
2. **Breaking the convention moves at least one reported number.** The two breaks are ÷ 9
   rounded down instead of up, and face-on 8- instead of 4-connectivity.
3. **Swift = Python.** The probe's own `--object-table` rows equal `direction_check.py app`'s
   Python rows on the same map, row for row.

## Predictions (primary configuration against the T3 baseline row: 0.1 %, unguarded)

The baseline raw spurious objects are face-on 67, T1 23, edge-on 49, and its P/9 ratios are
face-on 1.00 / 1.03 / 1.04, T1 1.00 / 1.01 / 1.00, edge-on area 1.54.

| class | metric | prediction |
|---|---|---|
| T1 | raw spurious | **down**, to ≤ 5 (the floor sweep printed 1 guarded at 0.15 %) → pass |
| T1 | raw merges | 0–2 → probably pass; limit 1 |
| T1 | split / merge / vanished after P/9 | about 0–3 / 0 / 2–5 → pass, near the vanished limit |
| T1 | count / median / area ratio | 0.95–1.05 / 0.95–1.15 / 0.97–1.03 → pass |
| face-on | raw spurious | **down**, 20–40 → pass (limit 113) |
| face-on | raw merges | 0 → pass |
| face-on | split / merge / vanished after P/9 | 0 / 0 / 0 → pass |
| face-on | count / median / area ratio | 1.00 / 0.98–1.05 / 1.00–1.06 → the count passes; the median sits at its tight limit (0.03) and **may fail** |
| edge-on | raw spurious | **down**, 10–30 → **FAIL** (limit 5) |
| edge-on | area ratio | 1.2–1.6 → **likely FAIL** (limit 1.36) |

**Predicted verdict: FAIL**, on θ′ edge-on raw spurious objects and probably its area fraction.
The app's edge-on speckle is the known weakness. **The null** is predicted to FAIL on T1 raw
spurious objects (the refuter measured 93 raw T1 objects on its null against the truth's 37)
while passing the cleaned counts. That is the demonstration that the primary tier has teeth.
