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

## Amendment — registered before any app number was read (the probe had finished; its output unopened)

The scorer's self-test failed the rule as first registered. **The truth itself failed it**: T1 count
ratio 0.919 and median ratio 1.349 against the raw truth. Under P/9 the truth loses its own 3 small
T1 objects (37 → 34, the refuter's "fair T1 reference is 34"), and the limits had been read from
ratios rounded to two decimals. A bar that fails a perfect map is miscalibrated, so it is amended:
- **Ratios are taken against the truth under the same convention** (truth · P/9: T1 34 objects,
  median 29.6745 px, area 0.217161; face-on 3 / 22.2271 / 0.033173; edge-on area 0.014261), so a
  perfect map scores exactly 1.
- **The ratio limits are recomputed** from the four published P/9 rows against that reference:
  - T1: count 0.0588, median **0.0834**, area 0.0500;
  - face-on: count 0, median 0.0334, area 0.0671;
  - edge-on area: 0.3604.

  The T1 median limit tightens from 0.33 to 0.083, because the published medians sit well below
  the cleaned truth's. The error-count limits are unchanged.
- **New validity 0:** the truth itself must PASS, and the truth with its largest T1 object deleted
  must FAIL. Both hold (`selftest2-truth.log`).
- **Validity 2 follows T4's own wording:** "off-by-one on the ÷ 9 rounding, **or** 4- vs
  8-connectivity for face-on, must move at least one reported number". So at least one break must
  move a number, not both. On the truth, face-on 8-connectivity moves nothing, because face-on
  objects are large; the rounding break moves T1 vanished from 3 to 0.

The predictions above stand unchanged, except that the T1 median ratio's pass/fail call now uses
the tighter limit: 0.95–1.15 against |r − 1| ≤ 0.083 **may fail**.

## Result (scorer `t4_score.py`; probe and scorer logs all exit 0 on their own lines)

**Scored configuration** (known-variants, `--or`, floor 0.15 %, guard k = 1; `probe-0.0015.log`,
`t4-0.0015.log`): per-position error **1.31 %**. 774 245 peaks. **The run counts:**
- validity 0: the truth passes, and a deleted T1 object fails;
- validity 1: the null FAILS, on T1 raw spurious 22 > 13 (its cleaned counts all pass, exactly
  as the refuter predicted);
- validity 2: the rounding break moves 5 numbers, and face-on 8-connectivity moves 2;
- validity 3: Swift = Python, all 9 object-table rows identical (`dc-app-0.0015.log`).

**Verdict: FAIL, on one metric: θ′ edge-on raw spurious objects, 7 against the published limit
of 5.** Every other scored metric passes:

| metric | T1 | θ′ face-on | θ′ edge-on |
|---|---|---|---|
| raw spurious (limit) | **1** (≤ 13) | 33 (≤ 113) | **7 (≤ 5) FAIL** |
| raw merges | 0 (≤ 1) | 0 (≤ 0) | 11 (reported) |
| split / merge / vanished after P/9 | 2 / 0 / 5 (≤ 2 / 0 / 5, both at the limit) | 0 / 0 / 0 | — |
| count / median / area ratio vs truth · P/9 | 1.000 / 1.002 / 0.967 | 1.000 / 1.021 / 0.993 | area 1.115 (≤ 0.360 off) |

**Against the predictions:**
- Held: T1 raw spurious down to ≤ 5 (it is 1); face-on 20–40 (it is 33); the edge-on raw
  spurious FAIL.
- **Refuted in the app's favour:** the edge-on area ratio (predicted 1.2–1.6 and "likely FAIL";
  it is 1.115, a pass), and the face-on median (at its tight limit, "may fail"; it is 1.021, a
  pass).
- The T1 median passes the amended 0.083 limit at 1.002.

The H/9 bracket fails θ′ face-on as well: one face-on object is lost, giving count 0.667 and
median 1.228. So face-on sits close to the stricter annotator's cut.

**A mislabel corrected:** `t4_score.py`'s "unguarded" section is not unguarded. Since ADR 038 the
shipped matcher applies the guard itself, so the probe's `baseline` dump is already guarded; the
two maps are identical (1.31 % both). No unguarded map was scored.

**Reported, not scored: the shipped default floor, 0.5 %** (`probe-0.005.log`, `t4-0.005.log`).
Per-position error is **11.42 %**. After P/9 **θ′ face-on vanishes entirely** (count ratio 0), and
T1 has 8 splits, 11 vanished and an area ratio of 0.63. Raw spurious objects are low (2 / 11 / 0),
because too little is detected. This continues the floor sweep (0.1 / 0.15 / 0.2 % → 1.81 / 1.45 /
4.07 %). **On this dataset the default detection floor is far too high.** One dataset does not set
a default, per the threshold rule in CLAUDE.md, so whether the default moves is the owner's call.
The app records the floor in the product's provenance.

**What the verdict means:** on the one dataset with truth, and at the owner's working
floor, the app's maps match or beat the worst published method on every object metric except
θ′ edge-on speckle (7 small spurious edge-on objects against the published 0–5). Phase mapping
stays badged unvalidated: one dataset, and a FAIL.

## Independent refuter (Sonnet), same day

**NOT REFUTED. No correction of substance.** The refuter re-derived everything with its own scipy code,
without importing the scorer's object functions (`refuter-recompute.py`, `refuter-null-edge.py`).
- **The amendment is principled and fair.** Commit times: registration 15:28:14, probe labels
  written 15:30:11, amendment committed 15:31:01, the first scored output 15:31:11. The
  amendment's cause is in truth-only self-tests from 15:29:20 and 15:30:44. The label file existed
  50 s before the amendment. It is an unreadable pixel array without the scorer, and it was not
  opened: stated so that the gap is on the record. The published methods and the app are scored by
  the same function against the same reference.
- **Every limit recomputed by hand** from the T2 rows matches the scorer (to rounding). The verdict
  recomputed independently matches too: T1 / face-on / edge-on raw spurious 1 / 33 / **7**, raw
  merges 0 / 0 / 11. At 0.5 %: 11.4155 %, and face-on P/9 count 0.
- **The FAIL is genuine speckle.** Of the 7 spurious edge-on objects, six are 1 px and one is 2 px,
  and none touches the scan boundary. 5 of the 7 sit next to another truth class (boundary
  spill-over); 2 are isolated in Al. Whether a different stride-3 offset would change the count
  cannot be tested: no full-resolution prediction exists.
- **Validity 1 has a blind axis, now measured.** The registered null never flips Al to edge-on,
  the one class that failed. An edge-on null at the app's own Al → edge-on rate (0.256 %, several
  seeds) gives **47–54** spurious edge-on objects, 7–8× the app's 7. So the metric separates
  structured calls from noise on that axis too, and the FAIL is not an artefact of the metric.
  **Follow-up for any later scored run: flip all three classes in the null.**
- **Confirmed:** the probe's `baseline` is built under the shipped guard
  (`PhaseVectorMatching.swift:239`, k = 1), so `baseline == guarded` byte for byte in both dumps.
