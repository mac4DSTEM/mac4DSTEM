# Phase-map residual detail — measured 2026-09-21 (Gate D step 1 for the known-variants rule)

Control: `tools/thronsen-dataset/run.sh probe --min-relative 0.001 --or --residual-detail`
(`residual-detail-20260921.log`, exit 0, 58 s). Headline reproduced: **1230 / 29 241 = 4.21 %**.
Shipped defaults in play: `minimumVectors 2, minimumMatchedVectors 3, friedelPairMinimumMatchedVectors 2,
chanceMatchMultiple 5, notIndexedAboveInvAngstrom 0.015`. Buckets 0 1 2 3 4 5 6–9 10+.

```
truth \ ours       Al       θ′ edge   θ′ face    T1        not idx   total
Al              21087 98%   21  0%    21  0%    11  0%    354  2%   21494
θ′ edge-on         22  5%  292 70%     2  0%    52 12%     49 12%     417
θ′ face-on          ·        ·       966 100%    ·          ·         970
T1                 39  1%    9  0%    27  0%  5666 89%    617 10%    6358
disagreement        ·        ·         2         ·          ·           2
```

| cell | n | survivingCount | matchedCount | score Å⁻¹ (finite n; p10/p50/p90) |
|---|---|---|---|---|
| T1 → not indexed | 617 | 0·0·328·166·62·29·29·3 | 604·0·2·11·0·0·0·0 | 13; 0.0152/0.0165/0.0172 |
| Al → not indexed | 354 | 0·0·187·57·25·17·42·26 | 347·0·3·4·0·0·0·0 | 7; 0.0157/0.0163/0.0176 |
| θ′ edge-on → T1 | 52 | 0·0·0·0·0·0·0·52 | 0·0·51·1·0·0·0·0 | 52; 0.0051/0.0083/0.0116 |
| T1 → T1 (ref.) | 5666 | 0·0·576·547·382·171·2029·1961 | 0·0·4563·377·726·0·0·0 | 5666; 0.0043/0.0065/0.0090 |
| Al → Al (ref.) | 21087 | 19621·1466·0·0·0·0·0·0 | all 0 | none |

`removedCount` is 4 at essentially every position (the four {200} matrix spots inside the 0.68 Å⁻¹ reach).

**Reading.** (1) 604 / 617 and 347 / 354 of the not-indexed residuals never got a scored winner: two or
more vectors survive matrix removal, none lands within the 0.02 Å⁻¹ pair radius of a reference that also
clears the matched floor / chance guard; only 13 + 7 reached the 0.015 cliff. The refuting observation
pre-registered in `docs/v3-precipitates-and-materials-project-plan.md` §2 ("survivors mostly 0–1") did
**not** occur, so the paper's rule — score all survivors, no radius, no floor — can act on them.
(2) All 52 θ′ edge-on → T1 errors have 10+ survivors and a T1 winner that explains exactly 2 of them
(the Friedel-pair floor): a partial explanation wins by mean distance. The paper's score sums every
survivor's distance, so a reference explaining 2 of 12 spots scores badly by construction.
(3) Al → Al positions have 0–1 survivors, which is why the paper's "≤ 1 survivor → matrix" rule is safe here.

`PhaseVectorResult` records no refusal reason; the breakdown is approximated from `matchedCount`/`score`
(Core untouched). The probe run without the flag is byte-identical except one pre-existing tie-order swap.
