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
