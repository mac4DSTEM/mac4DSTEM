# Volumetric precipitate density — pre-registration (2026-09-28 night)

ROADMAP step 2's last item. Registered before any code; the owner's three decisions of 2026-09-28 night are in §1.

## 1. Decided (owner, 2026-09-28)

- **Thickness is typed, not measured.** Nanobeam precessed data cannot measure foil thickness: PACBED fitting works
  at ~7–25 mrad convergence (LeBeau et al., Ultramicroscopy 110 (2010) 118; Xu & LeBeau, Ultramicroscopy 188 (2018)
  59), Thronsen's is 1.13 mrad with 1.04° precession, and precession averages away Kossel–Möllenstedt fringes. The user
  enters t (nm), its uncertainty σₜ, and its source (EELS, CBED, assumed). PACBED estimation is deferred until a
  large-convergence dataset exists.
- **No independent thickness exists yet;** the owner will acquire EELS or CBED with the next microscope session.
- **Per-object correction:** N_V = (1/A) · Σᵢ 1/(t + hᵢ), hᵢ = object i's extent along the beam.

## 2. The formula and where it comes from

Nie & Muddle (Acta Mater. 56 (2008) 3490), as applied to θ′ in Al-4Cu (Rodriguez-Veiga et al., arXiv:1804.09634,
Eq. 2): n = N / (A (d + δ)) for {100} plates of true diameter d in a foil of thickness δ — a plate is counted when any
part of it lies in the foil, so its centre may sit in a slab δ + (extent along the beam) thick. They use d for every
variant because the face-on variant is invisible in their images and is estimated (their Eq. 3). The app classifies
face-on plates directly, so each object takes its own extent:

| Class (beam ∥ ⟨001⟩Al) | hᵢ | From |
|---|---|---|
| θ′ edge-on ([100], [010] variants) | measured trace length Lᵢ (≈ d) | the object table |
| θ′ face-on ([001]) | plate thickness, not measurable here → the owner types it (default: none, refuse) | typed |
| T1 on {111} | d·sin 54.7° ≈ 0.82 d, d from the trace | geometry — **to verify** before build |

Uncertainty: σ(N_V) from σₜ by propagation per object; the count's own Poisson error beside it.

## 3. Refusals (never silently volumetric)

No t → areal only, and the row says why. t ≤ 0 or σₜ < 0 → refused. A class without an hᵢ rule → that class areal only.
Areal density stays shown beside every volumetric one. Provenance and the CSV carry t, σₜ, source, hᵢ per object.

## 4. Pass bar (T6), fixed before the build

A synthetic foil, generated in `tools/` (not the app): circular plates of known N_V in a slab of thickness t, the three
{100} variants (and T1's four {111}), random centres including plates cut by both surfaces, projected along [001];
counted with the app's own `PrecipitateObjectReport` path. **Pass:** the estimator recovers the true N_V within 5 %
(mean of 20 seeds) for t ∈ {50, 100, 200} nm and d ∈ {20, 100} nm; **and** the naive N/(A·t) fails the same bar at
d = 100 nm (the test must be able to fail). This validates the formula and the code, not a thickness. The real bar
waits for the owner's EELS/CBED measurement.

## 5. State, surface, tests

- **Owner of the state:** thickness is a property of the specimen area, per dataset, persisted in the sidecar beside
  the calibration — not `AppState` (a new stored field in `PhaseMappingProduct`'s precipitate settings; confirm at
  build).
- **Surface (costed):** in Precipitates, two rows — "Foil thickness [ 120 ] ± [ 10 ] nm" and "Source [EELS ▾]" —
  and one line per phase, "N_V 3,1 ± 0,3 ×10³ /µm³"; the Object Table summary gains one column. A mock goes to the
  owner before the UI is built (Drive before more surface).
- **Tests before code:** the hᵢ rule per class; the refusal cases; the propagation against a hand-derived value; each
  broken first. Gate D applies (a new scientific number) — an independent refuter on the formula, not the diff.

## 6. Open before the build

1. T1's hᵢ geometry at the Thronsen zone axis (§2) — derive and check against a drawing.
2. Face-on θ′: accept a typed plate thickness, or report that class areal-only.
