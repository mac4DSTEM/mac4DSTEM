# Known-variants rule (the paper's classifier) — S1 record, 2026-09-21

Pre-registration: `docs/v3-precipitates-and-materials-project-plan.md` §2. Diagnosis evidence:
`phase-map-residual-detail-2026-09-21.md`. Code: `ClassificationRule.knownVariants` in
`Core/Crystal/PhaseVectorMatching.swift` (off by default; `.search` byte-identical, pinned by
`testKnownVariantsRuleDoesNotChangeSearchsOwnResult`). Seven `testKnownVariants…` tests; three
break-first mutations (denominator, cutoff flip, matched-only sum) each exit 65 then green
(`s1-M1.log`, `s1-M2.log`, `s1-M3.log`). Gates: unit 777 / 0 / 2 = 779 (`unit-s1.log`), core exit 0
(`core-s1.log`), `phase-vector-matching` 32 / 0 (`phase-vector-matching-s1.log`).

## Prediction refuted

Control (`s1-control.log`, 94 s): **1230 / 29 241 = 4.21 %**, unchanged.
Experiment `--rule known-variants` (`s1-known-variants.log`, 56 s): **5 296 / 29 241 = 18.11 %** —
the pre-registered ≤ 3 % did not happen.

```
truth \ ours    Al    θ′ edge  θ′ face   T1    not idx
Al             98 %     0        0        0       0      (21 494)
θ′ edge-on      ·       ·        ·      100 %     ·        (417)
θ′ face-on      ·       0       99 %      ·       0        (970)
T1              1 %     ·        0       30 %    69 %    (6 358)
```
Winner-score quantiles (min / p10 / p50 / p90 / max, Å⁻¹; cutoff 0.07): indexed T1 n=1904
0.0010 / 0.0059 / 0.0149 / 0.0575 / 0.0699; not-indexed T1 n=4415 0.0701 / 0.1015 / 0.1297 /
0.1383 / 0.2071; not-indexed Al n=107 0.0707 / 0.0747 / 0.1010 / 0.1384 / 0.1759; not-indexed θ′
edge n=410 0.0710 / 0.1035 / 0.1446 / 0.1845 / 0.2129. Exploration, not tuning: cutoff 0.05 →
19.26 %, 0.10 → 16.62 % — the cutoff is not the lever.

## Reading

The rule sums every survivor's nearest-reference distance. On the paper's LoG peaks that is a
sharp score; on this app's correlation peaks at `--min-relative 0.001` (0.1 % of the brightest
maximum, chosen in decision 026 to raise search-rule recall) the extra survivors at T1 positions
(6–10+ per position, of which 2–4 lie within 0.02 Å⁻¹ of the reference) inflate the mean past
any cutoff. θ′ edge-on → T1 went 52 → 417: with T1 free in-plane and no floor, some T1 entry
explains an edge-on pattern's survivors more cheaply than the constrained θ′ entries (S2's OR
derivation is the pre-registered fix for T1 being free). Whether the far survivors are noise or
unmodelled reflections, and how both rules behave at the paper-like detection regime, is the
next measurement (`survivor-detail-20260921.log`, `sweep-*-20260921.log`) — appended below.

## Survivor detail and detection-threshold sweep

`--survivor-detail` (`survivor-detail-20260921.log`, min-relative 0.001, known-variants): mean survivors per
truth-T1 position **7.16**, per truth-Al position 0.15. Nearest-reference distance d of the 45 464 survivors
scored against the (would-be) winning T1 entry: 0–0.01 5 056 · 0.01–0.02 6 447 · 0.02–0.05 2 312 ·
0.05–0.1 4 325 · 0.1–0.2 14 012 · 0.2+ 13 312. **Far survivors (d > 0.05, n = 31 649) peak at |q|
0.36–0.38 (13 466), 0.66–0.68 (5 830), 0.22–0.24 (4 832)** — T1's own [0 -4 1] zone reflections
{014} 0.367, {214} 0.679, {100} 0.233. Near survivors (d ≤ 0.02, n = 11 503) peak at 0.44–0.48 (10 518):
{200} 0.467 and {114} 0.493, the reflections the entry carries. The refuting observation ("far survivors
are noise, spread in |q|") did **not** occur: they are real reflections absent from the reference.

Detection-threshold sweep (`sweep-<rule>-rel<v>-20260921.log`, `--or`, everything else as the control):

| min-relative | rule | mislabelled | T1→T1 | T1→NI | Al→NI | edge→T1 | T1 survivors 0/1/2/3/4+ % |
|---|---|---|---|---|---|---|---|
| 0.001 | search | 1230 = 4.21 % | 5666 | 617 | 354 | 52 | 0.2/0.5/14.2/11.2/74.0 |
| 0.001 | known-variants | 5296 = 18.11 % | 1886 | 4415 | 107 | 0 | same |
| 0.005 | search | 3729 = 12.75 % | 3755 | 252 | 28 | 37 | 35.0/1.9/52.1/3.3/7.6 |
| 0.005 | known-variants | 4012 = 13.72 % | 3610 | 394 | 0 | 1 | same |
| 0.01 | search | 5722 = 19.57 % | 1816 | 61 | 7 | 24 | 63.5/6.9/27.3/0.5/1.7 |
| 0.01 | known-variants | 5774 = 19.75 % | 1810 | 66 | 0 | 1 | same |
| 0.02 | search | 7171 = 24.52 % | 396 | 2 | 1 | 15 | 91.1/2.6/5.7/0.2/0.4 |
| 0.02 | known-variants | 7163 = 24.50 % | 383 | 15 | 0 | 3 | same |
| 0.05 | search | 7619 = 26.06 % | 33 | 1 | 0 | 15 | 99.2/0.3/0.5/0.0/0.0 |
| 0.05 | known-variants | 7587 = 25.95 % | 33 | 1 | 0 | 1 | same |

Reading: detection noise is not the mechanism — a stricter threshold removes T1's real reflections
faster than noise (at 0.05 a T1 position keeps 0 survivors 99 % of the time). Both rules are
starved by the same incomplete T1 reference; the paper's rule merely pays for it on every survivor.
Next pre-registered experiment: the T1 entry at `minimumIntensityFraction` 0 (`t1-entry-*`,
`map-*-min0-*` logs) — recorded in the follow-on section when run.

## The T1 reference is incomplete — measured and confirmed

Pre-registered before the run: the T1 [0 -4 1] entry lacks {014} 0.367 and {214} 0.679 Å⁻¹ because
`PhaseReferenceSettings.minimumIntensityFraction` (0.05 of the entry's strongest) drops them; refuting
observation: they stay absent at floor 0. Probe flags `--min-intensity`, `--max-vectors`, `--dump-entry`.

`--dump-entry T1` at defaults (`t1-entry-default-20260921.log`, 18 vectors): 0.0575 ×2 (001) rel 0.17 ·
0.233 ×2 (100) 0.25 · 0.455 ×4 (113) 0.37 · 0.467 ×2 (200) 1.00 · 0.470 ×4 (201) 0.10 · 0.493 ×4 (114) 0.53.
**0.367 and 0.679 absent; 0.233 present** (the prediction's "probably 0.233" clause was wrong).
At `--min-intensity 0` (cap 48 binding, 48 vectors): **0.367 ×4 (014) rel 0.018 and 0.679 ×4 (214)
rel 0.017 present** (a distinct off-zone (027)-type family, rel 0.006, coincides at 0.679 — the refuter
caught the first draft conflating them); cap 96 adds only two weaker groups. Chance-match fraction of the entry 0.5 % →
1.3 % (cap 48) → 1.5 % (cap 96).

Phase maps, `--or --min-relative 0.001`, floor 0 (`map-<rule>-min0-cap<N>-20260921.log`):

| rule · cap | mislabelled | T1→T1 | T1→NI | Al→T1 | Al→NI | edge→T1 | edge→Al |
|---|---|---|---|---|---|---|---|
| search · 48 | **1102 = 3.77 %** | 5764 | 490 | 12 | 352 | 11 | 20 |
| search · 96 | 1132 = 3.87 % | 5730 | 523 | 12 | · | 5 | · |
| known-variants · 48 | **773 = 2.64 %** | 6313 | 4 | 264 | 4 | 15 | 107 |
| known-variants · 96 | 785 = 2.68 % | 6316 | 1 | 280 | 0 | · | · |

Known-variants · 48 full table: Al → Al 21 087 · edge 90 · face 49 · T1 264 · NI 4; edge-on → Al 107 ·
edge 295 · T1 15; T1 → Al 39 · face 2 · T1 6 313 · NI 4. Winner-score quantiles, indexed T1 (n 6 315):
p50 0.0100, p90 0.0179, max 0.0698; not-indexed T1 n 4 (0.071–0.076). `--survivor-detail`: far survivors
31 649 → 1 500; the 0.36–0.38 bin 13 466 → 192 far / 0 → 13 018 near; 0.66–0.68 5 830 → 30 far / 0 → 5 039 near.

Scorecard: (i) partly confirmed (0.233 was never missing); (ii) confirmed; (iii) confirmed, 4.21 → 3.77 %,
T1→NI 617 → 490; (iv) confirmed, T1→T1 1 886 → 6 313. The pre-registered ≤ 3 % bar is **met by the
known-variants rule at floor 0** — one boundary value, scored once, on the dataset that motivated it; the
shipped default floor is unchanged (0.05) and moving it for any rule is `open-items.md`'s item (3) — the
paper's 0.96–1.75 % band is not met. The 0.22–0.24 far-survivor peak is **not** explained by the floor
({100} was always present): with T1 a free 180-entry sweep, `--survivor-detail` scores survivors against
the single winning entry only, so a real {100} spot at another azimuth reads as far — S2's relationship
is the check. Raw logs differ only in the print order of three exactly tied matrix zone-axis candidates
(the Dictionary tie-order swap already recorded); every count is identical. Cost: Al → T1 false calls 109 → 264
under known-variants (the rule has no chance guard; the search rule's guards hold Al → T1 at 12).
**Open, mechanism not established:** edge-on → Al 107 under known-variants against 20 under search at the
same floor — both rules share the matrix removal and the ≤ 1-survivor → matrix path, so this needs its own
Gate D before S3 wires the rule. Also open: the S2 T1 relationship (180 free T1 entries → ~40) is the
pre-registered lever on the Al → T1 chance matches.

The 2026-09-17 open item's "the T1 reference length is correct; do NOT change it" stands for the {200}
length; what was missing were the weak {014}/{214} families under the intensity floor, which that
measurement (at min-relative 0.005, two survivors per position) could not see.


Gate B (independent Sonnet refuter, 2026-09-21): PASS WITH CORRECTIONS — the four above are applied; it
recomputed the T1 radii and the (h,k,4k) zone law independently, checked Al {220} (0.699 Å⁻¹, wrong bin)
as the alternative, confirmed the `.search` dispatch is textually disjoint and its result pinned, and
verified every headline number byte-for-byte against the named logs.
