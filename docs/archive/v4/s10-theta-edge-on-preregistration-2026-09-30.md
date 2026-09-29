**S10: θ′ edge-on speckle. Gate D pre-registration (2026-09-29, not run)**

**1. The 7.** B1 (`b1-edge-on` §table, §Addendum): **3 truth-Al** (10,103) (100,54) (151,57), 4/2/2 specific reflections, 1–2 full-res px from truth needles. Al→edge-on within 1 px: app 54/55, vectors 137/138. **4 objects (5 positions) deep in T1**, each on one weak specific hit, T1 runner-up. Refuted: global k = 2 (T1 split 4 > 2, 1.93 %); edge-on→T1 guard (T1 speckle 1 → 12, right half 4 fixed / 5 broken; `b1-narrow-guard` §Result). Tolerance 0.0190 passes, 0.0200 gives 7 (`phase-tolerance-results` §Thronsen).

**2. Candidates.**
- **A: zero-weight evidence.** θ′'s slab 0.3 (`thronsen.swift:104–111`) admits off-zone families, |s_g| 0.17–0.25 Å⁻¹, weight ≤ e⁻³³ (`theta-prime-slab` §slab 0.3). The guard counts them as specific (`PhaseVectorMatching.swift:1253–1270`). Rule: a specific hit needs |s_g| ≤ the global slab 0.05 (`PhaseReferenceLibrary.swift:253`), score unchanged. Inert on T1/Al (built at 0.05); failures go to Al (`:1231–1245`), no other scored class.
  - Step 0: ≥ 4 of 5 single hits off-slab; **≤ 3 → stop.**
  - Rule: edge-on spurious 7 → 3; ≤ 11/398 correct edge-on lost; area 1.02–1.12; error 1.28–1.31 %; face-on loses ≤ 1 %; **T1 rows byte-identical**. Any miss refutes.
- **B: noise hit.** Single hit < 3σ (t1-edge addendum's disc-vs-ring; 3 is convention). Predict 5/5 < 3σ, ≤ 19 correct edge-on lost. Global: T1 split 2/2 and vanished 5/5 sit at the limit. Any of the 5 ≥ 3σ refutes.

**3. Commands.** Probe-only additions: hkl and s_g per specific hit in `--position-detail`; `--evidence-slab X` in the guarded map (`main.swift:1763–1798`).
```
tools/thronsen-dataset/run.sh probe --rule known-variants --or --min-relative 0.0015 \
  --min-intensity 0 --object-table --dump-labels a.json --evidence-slab 0.05 \
  --position-detail "6,91;6,92;8,91;22,10;46,126;10,103;100,54;151,57" > a.log 2>&1
echo $?
python3 tools/cloud-analysis/t4_score.py a.json \
  References/thronsen-datasetA/truth_stride3.json > t4-a.log 2>&1
echo $?
```
Repeat flag-off, on the demo (`--truth`) and Al-Mg-Si stride 3. One build (df ≥ 4 GB). Thronsen ~1.5 min/run; raw ~20 s, 1.13 GB peak (`phase-tolerance-registration:67`). Thronsen footprint unrecorded (est. < 1.5 GB): alone, under a 1.5 GB phys_footprint guard. ≈ 25 min.

**4. Bar.** Valid only if flag-off reproduces T4 (383, 1.31 %), truth passes, a null with edge-on flips fails, and the inverted rule moves the map. PASS = `t4_score` PASS, error ≤ 1.31 %, raw spurious T1 ≤ 1 and face-on ≤ 33, fixed ≥ broken per half (cols < 86 / ≥ 86). Only Thronsen has θ′/T1 truth; A is inert without a slab override, so demo and Al-Mg-Si label maps must be byte-identical (no collateral, not validity). No default moves before Thronsen B or full-res A (A3).

**5. Recommendation.** Ship the quantity now: 7, of which 3 sit at the stride-3 truth's resolution; the 4 genuine are inside the published 0–5 (vectors 5). Then A's step 0 only; B only if A is refuted.

## Notes from the pre-registering agent (verbatim substance, 2026-09-30)

- `PhaseReferenceLibrary.swift:491–506` says every zone axis in use has a Laue-zone spacing ≥ 0.066 Å⁻¹; T1 at
  [0 -4 1] (added 09-21) has ≈ 0.041 Å⁻¹ (a 4.948 Å, c 14.145 Å) — below the 0.05 slab, so T1's entry can hold
  first-order-zone reflections at weight ≈ e⁻¹·⁹. Arithmetic, not measured: step 0 dumps T1's entry.
- T1 split (2/2) and vanished (5/5) already sit at their limits in the scored run; any rule touching a correct T1 call
  can fail T4 at once.
- The spurious test has no tolerance (`direction_check.py:124–141`): a 1-px call beside a needle that falls between
  stride-3 grid points counts as spurious — the mechanism of the 3 needle-edge objects.
- Soft predictions: "≤ 11/398 lost" reuses B1 P2's budget; B's "≤ 19" is a proxy count.
- The probe lacks `--evidence-slab` and hkl/s_g printing; the scorer lacks the edge-on-flipping null.
