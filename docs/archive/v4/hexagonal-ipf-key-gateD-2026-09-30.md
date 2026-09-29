# Hexagonal IPF key labels — Gate D record (2026-09-30)

Trigger: the v4.0.0 known issue "the hexagonal IPF colour key may be labelled the wrong way round" (2026-09-11), cause
not established. Pre-registered before the experiment and the fix.

**Diagnosis.** The key's corners are Cartesian z, x (azimuth 0) and azimuth 30° in the basal plane
(`HexagonalOrientationSymmetry.reduceDirection` folds with a 60° period and a mirror at 30°). The app's crystal frame
is py4DSTEM's (`Crystal.swift` `latReal`: a along +x, b at γ = 120°; `crystal.py` `calculate_lattice` line for line), and
the vector coloured is the ACOM zone axis in that frame (`py4DSTEMOrientationMatrix.columns.2`). There azimuth 0 is the
a-axis [2-1-10] (the ⟨11-20⟩ family) and 30° is [10-10]. The shipped legend said the opposite: 0 → "10-10" green,
30° → "11-20" blue.

**Refuting observation (would have killed it).** py4DSTEM's own chain (`calculate_lattice` → `cartesian_to_lattice` →
`lattice_to_hexagonal`) mapping Cartesian (1,0,0) to [10-10]. It maps it to [2 -1 -1 0]; 30° → [1 0 -1 0];
60° → [1 1 -2 0]; z → [0 0 0 1].

**Fix.** Labels, accessibility text and the `ipfColor` doc only, read from one table in Core
(`HexagonalOrientationSymmetry.keyCorners`); the colour function is untouched, so every IPF pixel, export and
replay is byte-identical. Correct key: 0001 red, 2-1-10 green, 10-10 blue (the orix/MTEX vertex set).

**Gates (2026-09-29, session 85a5f653 `p1/run1..3.log`).** `HexagonalIPFKeyTests` red on the shipped labels
(run1, exit 65, only that test), green after with the precipitate tests (run2, 41 passed, exit 0), red on mutation
(run3: a duplicated label plus a 0.1 rad rotation of `latReal`, applied together — three key tests red).

**Independent refuter (Opus, 2026-09-30): HOLDS** on all five points — the frame, the vector fed to the colour
function (crystal frame, not sample frame or transposed; the lab-z sign folds away), the folding, an independent
computation (plane normals give the same answer), and the other places naming the corners (none left in export or
session metadata). The v4.0.0 release notes' known issue is fixed on `main`; the next release notes say so.
