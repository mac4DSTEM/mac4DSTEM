# S2 — T1's orientation relationship in the app's form, measured 2026-09-21

Pre-registered (`docs/v3-precipitates-and-materials-project-plan.md` §2, board S2). Diagnosis by a Sonnet
derivation, unrefuted except by the experiment below. Code: `tools/phase-map-probe/thronsen.swift` only —
the app's phase list states relationships in the same form through the user's OR text, nothing in Core moved.

**Derivation.** The paper states `(0001)T1 ∥ (111)Al, [1-10]Al ∥ [10-10]T1`. In the three-index basis
`Crystal` uses, `[10-10]` → `[u−t, v−t, w]` = `[2 1 0]`, at 30° from a — and exactly perpendicular to the
zone axis `[0 -4 1]` by the hexagonal metric (`2·0·a² + (2·(−4)+0)(−a²/2) + (−4)·a²… = 0`). The beam
`[001]Al` in T1 coordinates is `(1/√6, −1/√2, 1/√3)`, i.e. `[0, −√2·c/a, 1]` = `[0, −4.043, 1]`, 0.28–0.29°
from `[0 -4 1]` — the zone axis stays. The OR filter (`PhaseVectorMatching.swift:1111-1174`) compares
projected azimuths mod 180 with a 10° tolerance and skips pairs whose vectors are not in the entry's zone,
so two pairs against Al's ⟨110⟩ 90° apart select four T1 in-plane variants:
`(candidate .direction(2,1,0), matrix .direction(1,−1,0))` and `(… , matrix .direction(1,1,0))`.

**Pre-check** (no `--or`, floor 0, `s2-precheck-*.log`): T1 → T1 winner azimuth relative to the matrix,
folded to [0, 90) in 5° bins, sits 66 % (search) / 84 % (known-variants) in one bin (25–30°) — one
dominant cluster, as four 90°-spaced variants fold to.

**Predictions.** T1 candidates 180 → ~40; T1 → T1 must not fall below 6 313 (known-variants) / 5 764
(search) at floor 0; edge-on → T1 (295) and Al → T1 (264) fall.

**Result, known-variants, `--or --min-relative 0.001 --min-intensity 0`** (`s2-kv-or-min0.log`, exit 0):
**780 / 29 241 = 2.67 %** (was 773 without the T1 pairs).

```
truth \ ours    Al      θ′ edge   θ′ face    T1      not idx   total
Al           21087 98%   129 1%    57 0%    176 1%    45 0%    21494
θ′ edge-on      ·       122 29%     ·        45 11%   250 60%    417
θ′ face-on      ·         1        965 99%    ·         4        970
T1              39 1%     ·          8      6287 99%   24 0%    6358
```
- edge-on → T1 **295 → 45**, Al → T1 **264 → 176**: confirmed. T1 → T1 **6 313 → 6 287** (−26, still
  99 %): the "must not fall" prediction is narrowly refuted; T1 → T1 azimuth now 91 % in one bin.
- **The freed edge-on positions did not become edge-on: edge-on → not indexed 15 → 250** (edge → edge
  107 → 122). Under the search rule at the same floor edge → edge is 322 / 417, so the θ′ edge-on
  reference explains those patterns partially (median 20 detected vectors at edge-on positions, the
  survivors sum past the 0.07 cutoff) — the same incompleteness class the T1 entry had, unmeasured for
  θ′. Next: `--survivor-detail` for truth edge-on against the θ′ edge-on entry, then its own Gate D.
- Net: the headline did not move (2.64 → 2.67 %) because a wrong label and a refusal count the same.

**Result, search rule, same flags** (`s2-search-or-min0.log`, exit 0): **1 129 = 3.86 %** (was 1 102 = 3.77 %).
edge-on → T1 11 → 1, edge → edge 322 → 326; T1 → T1 5 764 → 5 733, T1 → not indexed 490 → 521; Al row
unchanged (Al → T1 12 → 10, Al → NI 354). The relationship removes the T1 overmatch under both rules at a
small T1-recall cost (−0.4 % / −0.5 %); it is kept in the probe's phase list as the paper states it.
