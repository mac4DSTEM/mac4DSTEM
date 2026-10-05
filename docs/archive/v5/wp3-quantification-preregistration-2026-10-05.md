# v5.0 WP3 — quantification — pre-registration (2026-10-05; NOT started)

Drafted by Fable 5.1 at the session's request (the owner delegated review to Fable while away) and committed by the
session.

**What it builds on.**

- ADR 054 (quantification), ADR 053 (M2 record, pooling by mask transport) and ADR 055 (the room). The flags at the end
  correct ADR 054 in two places; they are recorded in its addendum.
- WP2's deliverables only: `XRayLines`, `EnergyAxis`, the FWHM law, `SpectrumImage` (dense + sparse), window net counts
  with their eXSpy pins, the simulator with `truth_edx.json`, and the room shell.

**Reference.** eXSpy `7185a4d1` + hyperspy 2.4.0. Every difference gets an inline `DEVIATION`.

## Lanes

**How the lanes run.**

- Four Sonnet lanes run in parallel, with disjoint write-sets, each in an isolated copy under the session's
  `LANE-RULES.md`.
- **Q is not a lane.** It is a measurement session.
- **Shared project files.** Lanes list their `membershipExceptions` / `sources.manifest` additions in their report;
  the supervisor applies them.

| Lane | Writes (all new) | Builds | Needs |
|---|---|---|---|
| **F — fit** | `Core/Spectroscopy/Fit/` (`EDSModel`, `LinearDesign`, `LeastSquaresFit`, `PoissonMLFit`, `Continuum`, `EnergyAxisRefinement`, `ReferenceShapes`), `FitTests.swift`, `tools/edx-parity-test/cases_fit.py` | Items 1, 2, 3, 8 | WP2 C |
| **K — k-factors and absorption** | `Core/Spectroscopy/Quant/` (`CliffLorimer`, `ZetaFactor`, `MassAbsorption`, `TakeOff`, `FourDetectorAbsorption`, `BrownPowellK`, `DetectorEfficiency`, `KFactorSource`), `KTests.swift`, `cases_quant.py`, `Resources/Spectroscopy/` (EPQ `LineWeights.csv`, `FFastMAC.csv` with the NIST notice) | Items 4, 5 | WP2 C |
| **T — statistics, proposer, normalisation** | `Core/Spectroscopy/Statistics/` (`CountingInterval`, `Currie`, `SigmaTerms`, `LiveTimeNormalisation`), `Core/Spectroscopy/Proposer/` (`ElementProposer`, `LineConflicts`), `StatisticsTests.swift`, `ProposerTests.swift` | Items 6, 7, 9 | WP2 C; F's amplitude covariance via a protocol `FittedAmplitudes { values, covariance }` that T declares |
| **M — method, replay, registration, pooling** | `Core/Spectroscopy/Method/QuantificationMethod.swift`, `Core/Spectroscopy/Registration/` (`RegistrationRecordM2`, `MaskTransport`, `PoolBuilder`), `Session/SpectroscopyQuantification.swift`, the kind `"quantification"` in `Core/Data/SessionReplayRecord.swift`, `MethodTests.swift`, `RegistrationTests.swift` | Items 10, 11 | WP2 R and S; the settings sub-structs that F, K and T own |
| **Q — measurement** (after F and K land) | `docs/archive/v5/wp3-ls-vs-ml-<date>.md`, `wp3-background-acceptance-<date>.md` | LS vs ML and the background acceptance on the owner's pooled Al-Mg-Si spectra; the Velox k cross-check | F, K, the owner's one Velox quantification |

**Integration.** After the four lanes, the supervisor runs R3: it wires the fit, k, σ and the method into WP2's views
and the Quantify verb.

## Items by lane

### F — fit, background, energy axis, reference shapes

**Model.**

- One Gaussian per line, centre and width fixed (FWHM law). Family lines are tied by the database weights.
- Line areas are non-negative. With a fixed design, LS is NNLS and ML is IRLS on the same design.
- Escape peaks (E − 1.74 keV) are always fitted, as tied Gaussians for parents above the Si K edge (none for Mg, Al,
  Si). The footer names this.

**Background.**

- Default: a fitted whole-spectrum empirical continuum with the Al K-edge step at 1.56 keV, fitted jointly with the
  lines.
- Expert, parity: eXSpy's 6th-order polynomial inside the model. There is no Velox-shaped "polynomial in windows"
  (flag 3).

**Axis refinement.** Offset, gain and FWHM at Mn Kα are refined on the pooled spectrum. The file's values are kept
beside the refined ones.

**Reference shapes.** A slot for two components measured on the owner's pure-Al spectrum:

- the Al Kα incomplete-charge tail, tied to the Al Kα amplitude;
- the Si internal-fluorescence peak, tied to the **integrated counts above the Si K edge (1.84 keV)** (flag 2).

The slot ships empty, and results say "reference shapes: none".

**Tests (each broken first).**

| Test | Value or check | Broken by |
|---|---|---|
| Closed-loop Fe/Cr/Zn | [0.5, 0.2, 0.3] within 1e-4 (pin) | dropping a family weight |
| FePt LS amplitudes | 2800.0213 / 14921.183 (tolerance measured first) | an unbounded LS |
| Poly-6 path | equals the closed-loop pin | — |
| IRLS on the simulator | deviance non-increasing per iteration, converges within the cap | a wrong IRLS weight |
| Axis refinement | recovers a planted offset and gain | — |
| Continuum | standardized residual flat on the simulator's matrix pool | — |

### K — k-factors and absorption

**Ported from eXSpy:**

- Cliff-Lorimer: first two lines above `min_intensity`; refused on a single line (the "100 %" case, a DEVIATION).
- ζ: Core only, no menu.
- MACs: log-log interpolation with the (0,0) sentinel stripped.
- Take-off angle.
- Iterative absorption x/(1−e⁻ˣ): stop below 0.5, at most 30 iterations, signed test (a DEVIATION note).
- Mass thickness, and weight↔atomic conversion.

**Computed k (Brown-Powell).**

- k_AB = (ω_B a_B ε(E_B) σ_A A_A) / (ω_A a_A ε(E_A) σ_B A_B).
- σ comes from the Brown-Powell parametrisation, implemented from the paper and cited by equation number.
- ω and a come from EPQ (public domain).
- ε(E) is a named `DetectorEfficiency` curve, and its source string is shown in the k badge.

**Typed k** carries source, date and σ_k. **σ_k** is 20 % per k-factor, editable. **Bote-Salvat** is not in WP3
(rights check).

**Four-detector absorption** (flag 1).

- Inputs per selected segment: azimuth, elevation, α/β, holder.
- Each segment's transmission: T_d = (1−e^−x_d)/x_d.
- Combined as the **solid-angle-weighted mean transmission** T̄ = Σ Ω_d T_d / Σ Ω_d, so the correction is 1/T̄.
- Thickness ± σ is propagated by finite difference.
- Refused with the reason when any segment's geometry or the tilt is missing.

**Pins (exact, 1e-9 relative).**

| Quantity | Value |
|---|---|
| Take-off angle | 40.0 (30, 0, 10); 73.15788376370121 (45, 45, 45, 45); 28.865971201155283 (10, 45, 22); TM002 37.0 / 57.0 at tilt 20 |
| MACs | Al @ 3.5 keV 506.0153356472; Ta [3343.708…, 1540.082…, 3011.265…]; Zn Lα in Zn 1413.291119134; Al-Zn 50/50 at Al Kα 2587.4161643905127 |
| CL FePt | 15.409297 at% (k [1.450226, 5.075602], windows 3710/15872) |
| Al-Zn image | CL 22.70779 wt%; + absorption 22.743013 / 31.816908 (t 1 / 300 nm); ζ 80.962287987 wt% and 2.7125736e-3; cross-section 49.4889; mass thickness 6.1317741e-4 |
| Cu/Sn 88/12 | 93.196986 / 6.803013 |
| Zero handling | eXSpy's zero-handling table |

Each pin is broken once: swap the MAC ×0.1, drop the sentinel strip, invert the k order.

**Not pinnable, tested instead:**

- Four identical segments reduce exactly to the single-detector pin.
- The simulator's geometry recovers the planted per-phase composition (K2).
- k_Mg,Si / k_Cu,Si falls within a published table's spread, quoted from its source in the report.

### T — statistics, proposer, normalisation

**Statistics.**

- Net N = G − s·B, with Var = G + s²·B.
- Fisher covariance for fitted amplitudes.
- **Garwood exact intervals for every window count** (flag 6).
- Currie: L_C = z·σ₀, σ₀² = sB + s²B, L_D with the window scale s.
- σ is shown as named terms, combined in quadrature.

**Pins.**

- Garwood 95 %: n = 0 → [0, 3.689]; n = 1 → [0.0253, 5.572]; n = 5 → [1.623, 11.668].
- At s = 1: L_C/√B → 2.33, and L_D → 2.71 + 4.65√B.
- Broken by using 2n instead of 2n+2 in the upper limit.

**Coverage.** On the simulator, 68–80 % at nominal 68 % over ≥ 10⁴ pooled pseudo-regions on the dose ladder. Halving
the interval must drop it below 50 %.

**Live time.** Pools weight pixels by live time when the file carries it per pixel, otherwise by the Al Kα internal
reference, and the result names which. Test: two equal-composition regions at 30 % and 60 % dead time agree within
1σ on each route.

**Proposer.**

- Significance at Currie L_D on the pooled spectrum, with α = β = 0.05 (a dataset property, reported, not tuned).
- Named conflicts: Al sum 2.973 vs Ar Kα 2.958; Ga L 1.098 beside Mg Kα; Cu grid vs Q phase (the hole-region check when
  a hole mask exists).
- Never mutates the element list (a structural test). Cu defaults to Quantify. Li, Be, H and He are refused with the
  reason.

### M — method, replay, registration, pooling

**`QuantificationMethod`.**

- Codable, sorted keys, byte-stable. It composes the settings sub-structs, the element states and the k source.
- Stored in the sidecar, and recorded as one replay step `"quantification"` with `phases` / `objects` / `calibration`
  input edges (ADR 047). Rewind restores it.

**Registration record M2.** A 2×3 affine from the 4D grid to the spectrum grid. det < 0 is allowed, and the source is
named (file rect / typed / simulator truth).

**`MaskTransport`** moves a 4D-grid mask (a phase index, an object's pixels or a drawn ROI) onto the spectrum grid by
area overlap and reports the eroded fraction.

**`PoolBuilder`** pools by phase or region (approach E). The pool inherits its source's badge.

**Tests.**

- The round trip is byte-identical.
- Replay reproduces the pinned LS number bit for bit, and ML to its recorded cap and tolerance.
- A reflection transport equals the hand-computed mask.
- The simulator's planted transform recovers per-phase pools matching truth.

## What `truth_edx.json` must contain

WP2 S delivers what it can, and `tools/demo-edx/` is extended before any lane starts.

| Lane | Required in truth |
|---|---|
| **F** | Per-phase expected counts per line before noise; the generator's axis and the deliberately perturbed axis written into the file; the continuum's parameters; the planted tail and Si-fluorescence fractions |
| **K** | Per-pixel areal density per element; the forward model's line intensity per unit areal density (the truth k); the ε(E) used; the four segments' geometry and the stage tilt; the thickness map (a wedge) and the MACs. **The generator's absorption must be a numerical per-segment path integral, not the closed form, so K2 is not circular** (flag 7). |
| **T** | Per-pixel live time (a dead-time ladder); the seed; the N ladder {0.3, 1, 3, 10, 30, 100}; every planted nuisance (Cu grid peak, the Al+Mg 2.740 / Al+Si 3.226 sum peaks, Ga L, escape of any line above 1.84 keV) |
| **M** | The planted registration transform (offset, bin, reflection) and the per-phase masks on both grids |

## Predictions (written before any run)

| | Prediction | Refuted if → consequence |
|---|---|---|
| F1 | Closed-loop LS within 1e-4; FePt LS amplitudes within the measured-first tolerance | Any miss → Gate D |
| F2 | Simulator, N = 10/px, 10⁴ single pixels: ML's bias on the Mg Kα amplitude is within 2σ of zero, and LS's exceeds it | ML bias larger → the IRLS is wrong, Gate D |
| F3 | Simulator matrix pool: every standardized residual channel in 1.1–1.9 keV has \|r\| ≤ 3, and the band mean \|r̄\| ≤ 1 | Fails → the step model is wrong |
| F4 | Axis refinement recovers −10 eV and +0.2 % within 1 eV and 0.05 % on ≥ 10⁵ counts | Fails → no refinement is shown |
| K1 | Every K pin is exact | Any miss → Gate D |
| K2 | The four-detector correction recovers Mg/Si within 1σ_counting ⊕ σ_thickness at the planted thickness; four identical segments equal the single-detector pin exactly | Fails → the combination rule is wrong; the geometric mean is tried and both are reported |
| T1 | Coverage 68–80 % across the dose ladder; halving the interval → < 50 % | Over 80 % → intervals too wide; under → the variance formula |
| T2 | The proposer proposes every planted element above L_D, names every planted conflict, and proposes nothing unplanted without a named conflict | A miss → the bar is re-measured per dose, never raised silently |
| M1 | Round trip and replay are bit-identical; registration recovers the planted transform within 0.5 px; each phase pool is within 2σ of truth | Fails → per-object pooling stays off |
| Q1 | On the owner's pools, LS and ML Mg/Si net ratios differ by < ½ σ_counting, so LS stays the default | Gap > ½σ → the default switches to ML (a sheet to the owner); the gap is recorded as the data's property |
| Q2 | The continuum residual on the owner's matrix pool meets F3's band | Fails → the default background is reopened as a sheet |
| Q3 | Computed Brown-Powell at% on the owner's matrix pool agrees with Velox's quantification of the same pool within 10 % relative per element | Fails → ε(E) or the cross-section port; Gate D before any number is shown unbadged |

## Gates

- **Gate B on every lane:** each one produces numbers. The reviewer (Fable) reads the parity output and the simulator
  truth scores, not the diff.
- **Gate D** applies the moment any prediction is refuted.
- **Q runs on the owner's private files** as diagnostics only. The gates are the simulator and the pins.

## Decisions

**The session decides alone:**

- names;
- the IRLS cap and tolerance (recorded in the method);
- poly order 6;
- Garwood everywhere;
- the proposer's α = β = 0.05;
- fixtures;
- weighted-mean transmission primary, geometric mean as the comparison;
- which published k table K quotes.

**Fable reviews before landing:**

- **The ε(E) source.** Velox metadata holds no layer thicknesses (unverified). The candidates are Thermo's published
  Super-X data, GMS `Detector Info` layer tags, or back-derivation from the owner's Velox quantification.
- The Brown-Powell parametrisation and its equation source.
- The continuum's functional form.
- Every DEVIATION on a dataset-property default: the vacuum mask, `min_intensity` 0.1, the single-line 100 %.
- The `"quantification"` step's input edges.

**Owner:** the Q1 switch, as a sheet.

## Flags on the decided design (accepted by the session; ADR 054 addendum)

1. **The four detectors are combined by weighted mean transmission, not a geometric mean.** The summed stream is
   Σ_d I₀ Ω_d T_d(E), so the exact correction for the sum is 1/T̄ with T̄ = Σ Ω_d T_d / Σ Ω_d. A geometric mean agrees
   only to first order and diverges for a shadowed segment at α = −16.9°.
2. **Si internal fluorescence cannot be tied to Al Kα.** Al Kα (1.487 keV) is below the Si K edge (1.839 keV) and
   cannot ionise Si K. The detector's Si peak is excited by photons above 1.84 keV, so it is tied to the integrated
   counts above the edge. The Al Kα tail is correctly tied to Al Kα.
3. **"Polynomial windows" conflated two models.** The parity path is eXSpy's whole-range poly-6 inside the model. No
   Velox-style windows are added.
4. **Unweighted LS, stated.** hyperspy's `ls` is unweighted. On Al-rich pools, the Al Kα misfit can drive the Mg Kα
   amplitude. That is exactly what Q1 measures. Every footer says "least squares, unweighted".
5. **σ_k enters per k-factor.** A Mg/Si at% ratio carries about 28 %. On the ratio-of-ratios, k cancels. The σ-terms
   line shows the ratio's k term.
6. **The "~20 counts" Garwood switch was a threshold, and it is dropped.** Garwood is exact at every n.
7. **K2 is not circular** only if the simulator generates absorption numerically per segment.

## Not in WP3

Bote-Salvat (rights), an espm physical continuum, Poisson-PCA, NMF, per-object pooling on sequential data, EELS t/λ,
and frame-by-frame drift tracking.

## Addendum 2026-10-05: corrections found by lane K, confirmed by Fable

1. **The FePt pin pairing was wrong in this pre-registration.**

   | Windows | at% |
   |---|---|
   | 2754 / 15090 (background-subtracted) | 15.409297 |
   | 3710 / 15872 (raw) | 18.9171866 |
   | 2800.0213 / 14921.183 (model fit) | 15.77546544 |

   `validation.md` §1b had it right. The tests pin all three.
2. **The k_AB formula above has σ_A and σ_B swapped.** For a thin film, I_i = N_i σ_i ω_i a_i ε_i with N_i = C_i/A_i, so
   k_AB = (A_A σ_B ω_B a_B ε_B)/(A_B σ_A ω_A a_A ε_A). eXSpy's per-element k_i = A_i/(σ_i ω_i a_i ε_i) gives
   k_A/k_B = k_AB exactly. It is the textbook k_AB after a ratio, the same convention as Velox and Bruker (k_Si ≡ 1), so
   typed Velox values go in unchanged. The UI says "k-factors relative to <reference>".
3. **With a reference element (k ≡ 1, σ_k = 0)**, the Mg/Si term is 20 %, not the "about 28 %" of flag 5. That figure
   holds only for two independent typed k.
4. **Computed k uses Bote-Salvat + Krause 1979 + EPQ's SDD efficiency model**, not Brown-Powell (ADR 054 addendum: no
   licence-clean Brown-Powell source).
5. **K2 and `cases_quant.py` are deferred.** K2 waits for simulator S2's per-segment absorption truth.
