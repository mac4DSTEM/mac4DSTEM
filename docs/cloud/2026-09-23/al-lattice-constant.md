# Al lattice constant, 4.0495 vs 4.04 Å: decision memo (owner decision 3)

Cloud session 2026-09-23, HEAD `3d0134a`. Arithmetic only: no Swift toolchain here, and no
data or CIF read. It answers `docs/status.md` handoff item 3. **Nothing in this memo is applied.**

## 1. Where each value lives, and who uses 4.0495

| Value | Where | Used by |
|---|---|---|
| 4.0495 | `mac4DSTEM/Core/Crystal/Crystal.swift:254` `aluminum = fcc(a: 4.0495, z: 13)` | See below |
| 4.04 (Al) | `References/crystal-structures/Al_thronsen2024.cif`, gitignored and **absent from this container**. The value is quoted only by `docs/archive/v3/precipitate-overnight-2026-09-23.md:49` and commit `a6d82d0` | `--cif-check` / `--cif-crystals` only (`tools/phase-map-probe/main.swift:112-127, 130-195`) |
| 4.04 (θ′) | `tools/phase-map-probe/thronsen.swift:59-61`, their Table 2 | The Thronsen phase list |

The app's users of `Crystal.aluminum`:
- **The built-in library:** `CrystalModel.swift:340-341` (`al_fcc`). Since S5 that library is a replay **resolver only** (`CrystalModel.swift:328-336`). It is no longer offered in the ACOM picker or the phase "Add Phase" menu (`UI/MapSettings.swift:843-853`), and `ACOMSession.modelSelection` defaults to `.none` (`Session/ACOMSession.swift:23`).
  So **no user-facing default depends on 4.0495.** The one path that still reaches it is replaying an old recipe that names `al_fcc` (`Session/ReplayPlan.swift:524`, `App/AppState.swift:783`). That path would then feed ACOM templates (`AppState+ACOM.swift:165`, kMax 1.2) and the shell-based q self-check (`:87`).
- **Tools and tests:** the probe's Thronsen list (`thronsen.swift:98`, the only one that matters for 1.81 %), the probe's β″ lists (`main.swift:550, 560, 761`), `tools/phase-vector-matching/main.swift:192`, `tools/real-acom-benchmark/main.swift:81`, the demo-cube generator (`tools/demo-dataset/export_reflections.swift:99-101`, so a demo cube is baked at 4.0495) and 16 references in `mac4DSTEMTests/PhaseVectorMatchingTests.swift`. The tests assert against `al.a`, not the literal (for example `:729`).
- **Provenance gap:** the repo records no source, licence or fetch step for the three `*_thronsen2024.cif` files. `tools/crystal-structures/` holds only `make_beta_double_prime.py`. A reader cannot reproduce "a = 4.04000" from the repo.

## 2. Knife-edge arithmetic (recomputed)

```python
import numpy as np
fam = {"111": 3, "200": 4, "220": 8, "311": 11, "222": 12}          # N = h²+k²+l²
for a in (4.0495, 4.04):
    print(a, {f: round(np.sqrt(N)/a, 5) for f, N in fam.items()})
print("200 shift", round(2/4.04 - 2/4.0495, 5))
fcc = sorted({h*h+k*k+l*l for h in range(8) for k in range(8) for l in range(8)
              if h%2 == k%2 == l%2 and h+k+l > 0})
for kmax in (0.70, 1.2, 1.6):                  # set is fixed for sqrt(N_in)/kMax <= a < sqrt(N_out)/kMax
    for a in (4.0495, 4.04):
        Nin = max(N for N in fcc if np.sqrt(N)/a <= kmax); Nout = min(N for N in fcc if np.sqrt(N)/a > kmax)
        print(kmax, a, Nin, round(np.sqrt(Nin)/kmax, 5), round(np.sqrt(Nout)/kmax, 5))
for a in (4.0495, 4.04):                        # [001]: l=0 ZOLZ within 0.70; nearest layer at sg = 1/a
    z = [(h, k) for h in range(-4, 5) for k in range(-4, 5)
         if (h, k) != (0, 0) and h%2 == 0 and k%2 == 0 and np.hypot(h, k)/a <= 0.70]
    d = 0.70 - np.sqrt(8)/a
    print(a, len(z), round(1/a, 4), f"{d:+.5f} 1/A = {d/0.01904:+.3f} px")
```

| | {111} | {200} | {220} | {311} | {222} | [001] ZOLZ ≤ 0.70 | kMax − \|g220\| |
|---|---|---|---|---|---|---|---|
| a = 4.0495 | 0.42772 | 0.49389 | **0.69846** | 0.81902 | 0.85544 | **8** | +0.00154 Å⁻¹ (+0.081 px) |
| a = 4.04 | 0.42873 | 0.49505 | **0.70011** | 0.82095 | 0.85745 | **4** | −0.00011 Å⁻¹ (−0.006 px) |

Values are \|g\| in Å⁻¹; px is at 0.01904 Å⁻¹/px. The {200} shift is 0.00116 Å⁻¹, which matches the record's "worst \|q\| separation 0.00116".

**The refuter is confirmed.** Along [001], the l = 0 zone holds 4 {200} + 4 {220} vectors. The nearest other layer (l = ±1, for example {111}) sits 1/a = 0.2469 Å⁻¹ off the zone, and that is beyond both the global slab (0.05, `PhaseReferenceLibrary.swift:253`) and θ′'s 0.3 (which Al does not use, `thronsen.swift:98`). Every in-zone reflection has sg = 0 exactly and passes `PhaseReferenceLibrary.swift:519` at weight exp(0) = 1 whatever the slab. So the slab cannot account for 8 versus 4.

The 4 lost vectors are {220}, removed at `Crystal.swift:144` (`gLen > kMax`). They are the vectors the probe's kMax 0.70 (`thronsen.swift:121`, applied at `main.swift:475`) admits at 4.0495 and not at 4.04. The count of 8 at 4.0495 also shows that {220} clears the 5 % intensity floor.

**Window at kMax 0.70:** the reflection set {111, 200, 220} holds for 4.04061 ≤ a < 4.73804 Å.
- 4.0495 sits **0.00889 Å (0.22 %) above** the edge.
- 4.04 sits **0.00061 Å (0.015 %) below** it, with {220} excluded by 0.006 px.

**At the app's defaults the two values give the same set.** Phase mapping (kMax 1.6, `PhaseReferenceLibrary.swift:247`, user field `PhaseMappingSettings.swift:144`) has a window of [3.95285, 4.09840). ACOM (kMax 1.2) has [3.72678, 4.08248). The knife edge exists only at the probe's 0.70.

**Side observation, not asked:** the Thronsen run passes `--reach 0.68`. That discards every detected peak at \|q\| ≥ 0.68 (`main.swift:745`, `PhaseVectorMatching.swift:400`). So at 4.0495 the 4 Al {220} references (0.6985) can never be matched, only counted. The Al entry differs only by these 4 unmatchable references plus the 0.00116 Å⁻¹ {200} shift, so the 5-position change is a bookkeeping effect of those two differences. It is not evidence for either cell, and which of the two drives it was not separated.

## 3. Physical context (sourcing marked)

- **Pure Al:** the commonly quoted room-temperature value is a ≈ 4.0494–4.0496 Å. A web-search summary attributes 4.0494 Å to Swanson & Tatge, NBS Circular 539 vol. 1 (1953, public domain), but **I did not check the value against the primary text.** 4.0495 is consistent with that range.
- **Solutes:** Cu and Li dissolved in Al are reported to contract the Al lattice. This comes from secondary sources seen in search results, so the direction is uncertain and **no magnitude is claimed**. Whether the paper's Al 4.04 was measured on this alloy, or is a round value shared with θ′'s a = 4.04 (`thronsen.swift:59`), **is not established.**

## 4. Options

The measured number is 529/29 241 = 1.81 % (hand-typed Al) against 534/29 241 = 1.83 % (CIF Al), per the overnight record (lines 55-66). The difference is 5 positions (0.017 points), well inside the record's block-bootstrap 95 % interval [1.55, 2.08] (line 290).

| Option | Change | Consequence for the number |
|---|---|---|
| **A. Keep 4.0495 + DEVIATION note** | Comment only, at `thronsen.swift:98` (and fix the header, line 13) | 1.81 % stands. Every record from `theta-prime-slab-2026-09-21.md` on stays comparable. The guard's 1.45 % stays valid. |
| **B. 4.04 for the Thronsen list only** | A local `Thronsen.aluminum = fcc(a: 4.04, z: 13)` at `:98`. `Crystal.aluminum` untouched | The baseline becomes 1.83 %. The 1.45 % guard figure must be re-measured. {220} membership then rests on 0.00011 Å⁻¹, so any rounding of a or kMax flips it. |
| **C. Per-dataset parameter** | The app already has one: the user's CIF or Materials Project cell. For the probe, a flag (`--cif-crystals` exists) | 1.81 % or 1.83 %, depending on the value stated. Each record must name its value. |

Not recommended: changing `Crystal.aluminum` itself. That moves replayed `al_fcc` recipes, the demo-cube geometry and the benchmarks, and gains nothing at the app defaults (§2). A change to kMax (for example to the 0.68 reach, which drops {220} under both values) would move a scientific number, so it needs Gate D and is not proposed here.

Lean: **A**. B puts the reflection set on a 0.006 px edge, and nothing measured favours 4.04 for this alloy.

### DRAFT DEVIATION note (not applied; for `thronsen.swift`, above line 98)

```swift
// DRAFT — DEVIATION (2026-09-23, owner decision pending): Al is the app's
// `Crystal.aluminum`, a = 4.0495 Å (pure Al), not the paper's CIF value
// 4.04 Å. At this list's kMax 0.70 Å⁻¹ the difference is a cutoff knife
// edge, not an excitation-slab effect: Al {220} sits at √8/a = 0.6985 Å⁻¹
// (kept) at 4.0495 and 0.7001 Å⁻¹ (dropped) at 4.04, so the [001] entry
// carries 8 vectors vs 4; the set is unchanged only for a ≥ 4.04061 Å.
// With --reach 0.68 those 4 {220} references are never matchable. Measured
// effect: 529 vs 534 / 29 241 (1.81 % vs 1.83 %),
// precipitate-overnight-2026-09-23.md Finding 4 (mechanism corrected by its
// refuter, §6).
```
