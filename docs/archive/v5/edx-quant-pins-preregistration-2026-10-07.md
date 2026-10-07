# eXSpy quantification pins — pre-registration (2026-10-07 night; nothing run yet)

Reference-software sheet 2026-10-07, row 2a: eXSpy stays oracle 1; `tools/edx-pins` gains `quantification` pins. Pinned reference:
eXSpy `7185a4d1` + hyperspy 2.4.0 + rosettasciio 0.14.0 (the versions `tools/edx-pins/README.md` names).

**What is pinned.** eXSpy's `quantification(intensities, method=...)` for **Cliff-Lorimer** (k-factors) and **ζ-factor** (with its
dose), with and without its thin-film absorption correction where eXSpy offers it, on (a) eXSpy's own example data
(`EDS_TEM_FePt_nanoparticles`) with the k/ζ values eXSpy's documentation uses, and (b) synthetic intensity sets spanning two to four
elements and a near-zero intensity. The Swift side feeds the same intensities and factors to `CliffLorimer`, `ZetaFactor` and
`AbsorptionCorrection` and compares the compositions.

**Prediction.** Without absorption, compositions agree to 1e-9 relative (closed-form arithmetic on the same inputs). With absorption,
agreement within eXSpy's own iteration tolerance; any larger gap is named with its cause as a `DEVIATION` or opens a Gate D.

**Refuting observation.** Any composition differing by more than the stated tolerance without a named cause. A miss is a finding, not a
fix: the code is changed only through its own Gate D. Each new pin is broken once (k order swapped, ζ dose dropped) and seen red.

## Result (2026-10-07 night, 4cc5581c)
Prediction held. 12 cases, 47 runs (FePt with eXSpy's documented k and ζ, synthetic 2–4-element and near-zero sets): without absorption
bit-identical; with absorption ≤ 1e-15 relative and the same iteration count under eXSpy's signed stop rule. The app's default `.absolute`
stop runs 1–2 iterations longer where eXSpy stops early and lands ≤ 0,08 pp closer to the converged value (two seeded 3- and 4-element
cases). Nine mutations red. Generator `tools/edx-pins/quant_pins.py`, fixture `mac4DSTEMTests/Fixtures/eds-quant-pins-exspy-7185a4d1.json`,
tests `EDSQuantPinsTests`. The venv needs `PYTHONPATH=<exspy checkout>` beside the editable install.
