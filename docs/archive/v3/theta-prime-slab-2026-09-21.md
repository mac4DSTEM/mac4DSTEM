# θ′ edge-on reference — measured 2026-09-21; the excitation slab must be per phase

Pre-registered in `t1-relationship-2026-09-21.md` ("measure the θ′ edge-on entry the way T1 was"). Probe
flags `--survivor-detail N` (truth label), `--slab`, `--slab-width`; `--dump-entry` prefix-matches.
All runs `--or --min-relative 0.001 --min-intensity 0`; exits 0 on their own line.

**Entry at defaults (slab 0.05)** (`theta-entry-min0-20260921.log`, 18 vectors, chance 0.5 %): 0.302 (011)
rel 0.37 · 0.345 (002) 0.09 · 0.495 (020) 1.00 · 0.573 (013) 0.16 · 0.603 (022) 0.002 · 0.690 (004) 0.49 —
exactly the in-zone [100] list.

**Survivors at truth edge-on positions** (`survivor-detail-theta-20260921.log`, n 417, mean 16.4 survivors):
d 0–0.01 746 · 0.01–0.02 1251 · 0.02–0.05 1932 · 0.05–0.1 1010 · 0.1–0.2 1908 · 0.2+ 5. **Far (d > 0.05,
n 2923) |q| bins: 0.40–0.42 454, 0.24–0.26 313, 0.42–0.44 312, 0.52–0.54 281, 0.28–0.30 210** — not the
in-zone radii (0.30–0.32 35, 0.34–0.36 8, 0.56–0.58 129) and not T1's. Refuting observation for "out-of-zone
reflections" did not occur; the "other variant / T1" cause is refuted by the same bins.

**Entry at slab 0.3** (`theta-entry-min0-slab03-20260921.log`): 18 → 46 vectors, chance 1.2 %; new families
0.172 (101), **0.248 (110), 0.425 (112), 0.524 (121)**, 0.517 (103) — three of them on three of the four
largest far bins (0.40–0.42 stays unexplained). Their kinematic weight at width 0.03 prints 0.0000: they
enter only because the floor is 0, which is the paper's geometric reference. T1 unchanged (capped); Al 8 → 16.

| run (known-variants unless noted) | mislabelled | edge→edge | edge→NI | edge→T1 | face→Al | T1→T1 |
|---|---|---|---|---|---|---|
| slab 0.05 (S2 record) | 780 = 2.67 % | 122 | 250 | 45 | 0 | 6287 |
| slab 0.15 | 2.71 % | 122 | 262 | 33 | 0 | · |
| **slab 0.3** | **4.89 %** | **399 (96 %)** | **0** | 0 | **954 (98 %)** | 6276 |
| slab 0.3, search rule | 7.51 % | 210 | 45 | · | 954 | · |

Scorecard: (i) confirmed; (ii) confirmed with the weight caveat; (iii) confirmed, 250 → 0 and 122 → 399;
(iv) confirmed, T1 → T1 6 276, Al → precipitate 366. **Unregistered finding:** at a global slab of 0.3 the
Al entry grows 8 → 16 and matrix removal (tolerance 0.02 Å⁻¹) strips θ′ face-on's genuine reflections
before classification — 86 % of face-on positions keep 0 survivors and 954 / 970 become Al under both rules.

**Consequence, pre-registered for the next slice:** the slab is a property of the phase's shape (a thin
plate streaks its reciprocal-lattice points along the plate normal), so it must be **per phase** — the
paper's own split, T1 0.03 / θ′ 0.3. Prediction for `PhaseDefinition` carrying an optional slab, θ′ edge-on
and face-on at 0.3, Al and T1 at the global 0.05: edge → not indexed ≈ 0, edge → edge ≈ 399, face-on
unchanged (≈ 965), T1 → T1 ≥ 6 270, Al → precipitate ≤ 400; headline **≤ 2.0 %**, with the paper's
0.96–1.75 % band as the target. Refuting observation: face-on collapsing anyway (then the mechanism is not
the Al entry), or edge → edge staying near 122 (then the 0.40–0.42 residual dominates).
