# DiffractoKit switch, accepted inputs (P4′) — a new registration (2026-10-15, tier 1)

Opened because P4 of `diffractokit-switch-registration-2026-10-15.md` failed as worded (its results section). Not an
amendment: new claims, checked on plants that were not in the lane's corpus, by the switch's refuter with its own oracle.
Registered before the refuter runs.

## Claims
- **Q1, Friedel and the hexagonal reduction.** A structure whose atoms have Laue class 6/mmm in a hexagonal cell imports as
  `.hexagonal`, polar or not (point groups 6mm, -6m2, 622, 6/mmm). Basis: a kinematic pattern obeys Friedel's law, so
  |F(Rg)|² = |F(g)|² for every rotation R of 622, which is what the hexagonal reduction assumes. Plants: ZnO wurtzite
  (P6₃mc; a 3.2496, c 5.2042 Å, u 0.3819), WC (P-6m2; a 2.906, c 2.837 Å), CdS greenockite (P6₃mc; a 4.1367, c 6.7161 Å,
  u 0.3770) → `.hexagonal`; LiIO₃ (P6₃, Laue 6/m) → `.identity`. Check: for every `.hexagonal` plant and every kept g at
  k ≤ 1.2 Å⁻¹, |F(Rg)|² equals |F(g)|² to 1e-12 relative for all 12 rotations of 622 (the kit's structure factors; R
  applied to hkl).
- **Q2, close contacts.** Two sites whose occupancies sum above 1.02 and whose centres lie closer than 0.5 Å (the app's and
  the kit's `closeContactLimit`) refuse the import (`invalidStructure`, `close_contact`); at 0.51 Å the same pair imports;
  a split pair (occupancies 0.5 + 0.5) at 0.1 Å imports.
- **Q3, the cell test.** Laue m-3m in a primitive rhombohedral cell (α = 60°), 6/mmm atoms written in an orthohexagonal
  C-centred cell, and 2/m with c unique each import as `.identity`, never `.cubic`, `.hexagonal` or `.monoclinic`.

## Refuting observations
Any plant with another family than stated; a `.hexagonal` plant whose |F|² is not invariant under 622; a pair at < 0.5 Å
that imports or one at 0.51 Å that refuses. A failure closes this item; the importer then refuses what fails until a new
registration.
