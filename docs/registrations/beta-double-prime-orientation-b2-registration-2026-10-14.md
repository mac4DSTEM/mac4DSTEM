# β″ orientation maps, item B2: the 2/m group with a monoclinic library density — registration (2026-10-14)

A **new item** (ADR 050). Item B (`beta-double-prime-orientation-registration-2026-10-14.md`) closed at 21:50: P2 was refuted as
registered (86.5 % of 600 draws within 7.7° at the default 200 templates, band ≥ 95 %). P1, P3 and P4 held
(`beta-double-prime-orientation-results-2026-10-14.md`). Tier 1, Gate D. Nothing from item B lands except through this item.

**What item B showed, and what is in-sample.** The group code (patches in `beta-double-prime-orientation-2026-10-14/`) passed
P1, P3, P4 and five mutations. The P2 misses, by class, were 22 half-turn in-plane, 15 axis right with in-plane wrong, and 44
axis 6–34° off at reliability 0.01–0.06. Mirrored and sampled-zone draws failed alike. A post-hoc run on **the same 600 draws**
gave 96.3 / 99.0 / 99.5 % within 7.7° at 400 / 800 / 1600 templates (`diag2.log`). Those numbers are in-sample. They set this
item's design; they are not evidence for it.

**The candidate.** Item B's code, unchanged, plus one rule: a monoclinic phase's template library has 4× the quality preset's
count (Fast 96 → 384, Balanced 200 → 800, Best 400 → 1600). 4× halves the library spacing on the quarter-sphere zone (7.7° →
3.9° at Balanced, design note's formula d = √(2A/(√3 N))), which is the density at which the in-sample set reached 99 %. The
Work row and the duration estimate show the multiplied count (the estimate already scales by template count). Cubic and
hexagonal libraries are unchanged.

**Truth.** Synthetic kinematic patterns of `References/crystal-structures/beta_double_prime_Mg5Si6.cif` at item B's settings
(200 kV, kMax 1.2, 0.008 Å⁻¹/px, random direction over the full sphere, random in-plane angle). **Fresh draws:** a seed stream
disjoint from item B's (item B's base seed plus 1 000 000, stated in the test), 600 draws. No β″ truth set exists; real needles
cannot be validated here.

**Predictions** (set before any run on the fresh draws):
- P1, P3, P4 as item B, unchanged, on the candidate.
- P2′ at Balanced (800 monoclinic templates): disorientation (min over {E, C₂ ∥ b}) ≤ 7.7° for **≥ 97 %** of the 600 fresh
  draws. Basis: 99.0 % in-sample at 800; the binomial standard error at 600 draws near 99 % is 0.4 %, so 97 % is five standard
  errors below the in-sample value and allows for in-sample optimism. Reported, not gated: the fraction ≤ 3.9° (the 800-template
  spacing), the median, p90 and max, and the 22-class half-turn count.
- P6 cost: the measured match time per pattern at 800 monoclinic templates is within 3.5–4.5× the time at 200 on the same
  machine and patterns (the matcher is linear in templates). Reported in the result; the Work row's estimate agrees with it.
- P7 cubic and hexagonal outputs byte-identical to HEAD (the existing ACOM tests and the scientific gate).

**Refuting observations** (any one): P2′ below 97 %; any of P1, P3, P4 failing; a cubic or hexagonal output changing; the Work
row's count or estimate not showing the multiplied library; a mutation of the multiplier (1× for monoclinic) that the tests do
not catch.

**Ships badged unvalidated** as item B planned (`validation: "none"`, "monoclinic orientation — no β″ truth set", one inspector
warning row). UI cost: none beyond item B's row; the Work row's numbers change for monoclinic phases only.

**Gates.** Tests first, each broken once; unit (cold), core, scientific, inventory; one fresh Gate B refuter (Sonnet, a
reviewer that did not write the code) on the diagnosis, the multiplier and the fresh-draw result. No owner number moves
(monoclinic phases were refused for maps before), so no card unless the refuter finds one.

Registered 2026-10-14 before any run on the fresh draws.

## Results (2026-10-14 night; lane B, Sonnet; refuter RB, Sonnet, fresh; fix lane BF)

- **P2′ held:** 600 fresh draws (base + 1 000 000) at 800 monoclinic templates: 98.5 % within 7.7° (median 1.79°, p90 2.74°,
  max 179.0°), 98.3 % within 3.9°. The refuter's own third stream (base + 2 000 000, 1000 draws, 0 skipped for < 3 peaks):
  **99.0 %** within 7.7° (median 1.76°, p95 2.93°); the B and B2 streams share 0 outputs in 200 k.
- **P1, P3, P4, P7 held** (cubic and hexagonal paths untouched; the scientific gate green). **P6 missed as worded:** 3.33× at
  800 against 200 templates (band 3.5–4.5; one run on a loaded machine) — cheaper than predicted; reported, not a refuter.
- **Refuting observations:** none met. The 1× multiplier mutation goes red (three density tests and P2′); two estimate and plan
  mutations were not caught at first and a test was added (`cfe0f634`).
- **Refuter RB:** physics UPHELD (`Crystal.swift`: b along +y for α = γ = 90°, so C₂ = diag(−1, 1, −1); a c-unique cell loads
  Unreduced, not mis-reduced; `confirmedFamily` needs an atom-verified 2-fold or mirror); the fold UPHELD; the 4× rule UPHELD
  (plan, Work row, estimate, export `template_count`); no existing number moves. **Corrections, both made before landing:** the
  2/m colour key was not injective ((1 − cos 2φ)/2 gives φ and π − φ one colour) → an HSV key, hue 120° + 2φ, saturation the
  polar angle from b, tested by inverting it; the IPF legend was the cubic one over a monoclinic map → `IPFLegendKind` and a 2/m
  half-disk legend drawn from the same colour function. Mutations: old key → two tests red; cubic legend → the legend test red.
- **Gates** (lane clone, at the fixes): unit 2396 / 0 / 4 = 2400 = `func test`, warm and cold; core, inventory exit 0. Landing gate
  on `main`: status.md's row. Unverified on screen (no β″ dataset was driven).
