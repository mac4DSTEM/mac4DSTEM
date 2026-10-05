# EDX analysis methods for v5.0 — design analysis (Fable, 2026-10-05)

**Keep-awake:** `caffeinate -d -i -s -t 86400` (PID 4914) has been running 31 min, plus the 2 h one (PID 7722); nothing more was needed. Nothing was written to the repo; no files were created.

**How claims are marked.** `[velox] [gms] [formats] [market] [ownerdata] [repo] [validation]` = the sibling reports above. `[verified: path]` = I read that code or log myself this session. `[estimate]` = my arithmetic from stated assumptions. `[unverified]` = memory or inference, not checked. Owner decisions are numbered **M1–M8** at the end.

What I verified myself beyond the reports: espm's model and estimator (`espm/models/edxs.py`, `EDXS_function.py`, `estimators/smooth_nmf.py`, `datasets/base.py`), HyperSpy's Poisson scaling (`hyperspy/learn/_mva.py:1605-1690`), the three validation logs (`lowcount-`, `li-`, `fept_quant-2026-10-05.log`), and the repo hooks `PhaseVectorResult` (`Core/Crystal/PhaseVectorMatching.swift:332-362`), `PrecipitateSegmentation.Object` (`:24-40`), `AtomSite` (`Core/Crystal/Crystal.swift:37-48`), the built-in β″ model (`Crystal.swift:267`) and the registered thickness rule (`memory/precipitate-density-goal.md`: thickness is typed ± σ; N_V = (1/A)·Σ 1/(t + hᵢ)).

---

## 0. The facts that constrain every choice

| Fact | Consequence for method design | Source |
|---|---|---|
| The owner's own EDX SIs hold **10.8–18.7 total counts/pixel**, ~70 % of them Al Kα; net Mg Kα and Si Kα per pixel are **well below 1** | Per-pixel composition is meaningless on his data; only pooled estimators carry information. Any per-pixel map is a display, not a number | [ownerdata §7] |
| A 4D-STEM dwell (10–20 ms) is 13–27× the Velox per-pixel dwell; a true joint scan might give order 10² counts/px | Per-pixel methods (B, D on single pixels) become *possible* only on data that does not exist yet | [ownerdata §7, estimate, unverified] |
| **No simultaneous 4D-STEM + EDX recording exists** on the owner's disks; the closest pair (190330, 2026-06-03) is same lamella, different field and tilt | Registration across sessions is the first joint "method"; its uncertainty must propagate into every pooled result | [ownerdata §1, §5] |
| Pooled Cliff-Lorimer at N = 1–10 counts/px lands 0.1–1.7 wt% from truth; per-pixel at N = 10 scatters σ ≈ 23–28 wt%; exspy's default vacuum mask removes 74–100 % of pixels below 10 counts/px | Pooling is the estimator; the exspy defaults are dataset properties, not method properties | [verified: `lowcount-2026-10-05.log`] |
| Li has no line in any table; T1 (Al₂CuLi) and θ′ (Al₂Cu) renormalise to the same 66.7/33.3 Al/Cu | An "EDX-indistinguishable candidates" check is mandatory before any arbitration | [verified: `li-2026-10-05.log`] |
| Least-squares vs Poisson-ML on the same FePt spectrum: Pt Lα 14921 vs 15511 (4 %) | Parity and science modes must name their loss function; they will not agree | [verified: `fept_quant-2026-10-05.log`] |
| exspy bundles only 1D spectra; its model rides on HyperSpy's `Model1D` | Window/quant parity is bit-exact (integers); fit parity is a tolerance; SI parity needs a synthetic SI | [validation §1] |
| Existing repo hooks: per-position `score`, `runnerUpScore`, `phaseContrast`, `entryIndex`; per-object `pixelIndices`, `widthPx`, `lengthPx`; embedding `coordinates`/`groupOf`; `AtomSite(z, occupancy)` per CIF; thickness typed ± σ | E, B*, D, I, K can be built from what exists; A/C's "restrict the matcher" would move phase-map numbers (Gate D) and is avoidable | [verified: repo paths above] |

---

## 1. Part (a) — the plain-EDX baseline

### 1.1 Layer-by-layer: parity port vs science alternative

Rule I propose for the whole suite: **two named modes.** *Parity* reproduces eXSpy's number (the gate); *Science* is the estimator that is right for the count regime, badged, with every deviation an inline `DEVIATION` naming the eXSpy line it departs from. The user sees which mode produced a number.

| Layer | eXSpy (port 1:1 for parity) | Alternatives and what they add | Verdict for v5.0 |
|---|---|---|---|
| **Energy calibration** | offset/scale from file; `calibrate_energy_axis` fits Gaussians to chosen lines and refits offset+scale (`models/edsmodel.py:612`) | Velox "Re-measure" also refits the noise term of the width model [velox §1]. DM: offset = −Origin·Scale [formats §2.1] | Port exspy. Run only on the **pooled** spectrum (millions of counts); show file-vs-fitted values side by side |
| **Line database + FWHM** | `xray_lines.json`; FWHM(E) = √(2.5·(E−E_MnKα)·1000 + FWHM²_MnKα)/1000 keV; pins Al Kα 0.07661 @130 eV [validation §1b] | exspy table has known energy errors up to 9.6 % (Ce Mβ, exspy#100, PR closed unmerged) [market §0.8]; xraylib (BSD-3) and NIST EPQ (public domain) are cleaner sources [validation §2] | Parity: exspy table verbatim. Science: a second table (EPQ/xraylib) with a `DEVIATION` per corrected line. **Exclude H/He "Kα" rows** (not real EDX lines) [validation §1d.3]. **M1** |
| **Line ID** | manual `set_elements`/`set_lines`; `get_xray_lines_near_energy` | Velox Auto-ID + four-state periodic table incl. "deconvolution only" [velox §1]; Oxford Spectrum Examiner for trace elements [market O2] | Manual-first (owner: simple). Add a Poisson-significant peak finder on the pooled spectrum that *proposes* lines; adopt Velox's "fit but exclude from at%" state (needed for Cu grid, C, O). Flag escape (E−1.74 keV) and sum (2E) positions |
| **Intensities: windows** | E ± width·FWHM/2, default 2.0; background windows with scale s = (i5−i4)/((i1−i0)+(i3−i2)) on rounded indices; overlapping windows merged (changes TM002 results: 69287 vs 63805 unmerged) [validation §1c] | Velox "int" maps = raw windows [velox §1] | Port exactly (pins 3710/15872; 2754/15090 on FePt). This is the per-pixel map engine on sparse data: one scatter-add over events |
| **Intensities: model fit** | Gaussian per line, centre+width fixed, family lines tied by table weights, 6th-order polynomial background; HyperSpy `fit` default LM/least squares; `ML-poisson` available [validation §1a] | GMS: MLLS peak-family fit [gms §3]; Velox: ML with non-negativity, family-as-whole [velox §1]; DTSA-II filter-fit needs element standards the lab lacks [market P6] | Parity: LS, tolerance gate. Science: **Poisson-ML with fixed design matrix** (non-negative amplitudes), same Gaussians. For pooled spectra this is cheap; per pixel see §1.6 |
| **Background** | polynomial(6) in the model; windows for the window method | Velox: 3-parameter Bethe-Heitler "Empirical", or per-window polynomials order 0–2 [velox §1]. espm: two-term Lifshin-type continuum × absorption × detector efficiency as two fixed G-columns [verified: `EDXS_function.py:127-290`]. Kramers (E₀−E)/E. SNIP (PyMca): non-parametric clipping, good for display/line-ID, biased at low counts [unverified: PyMca details] | Parity: poly6. Science: espm's 2-column physical continuum (2 free parameters extrapolate sanely under peaks and at low counts). SNIP only for the line-ID proposer. Velox's rule "residual must look like noise inside the background windows" becomes a shown diagnostic |
| **Detector response / peak shape** | none (k-factors absorb efficiency); Gaussian only | espm: `det_efficiency` from layer thicknesses via MACs [verified: `absorption_edxs.py` imports]; Velox tables carry Si escape columns [velox §0]; PyMca Hypermet (tail, step) [unverified] | v5.0: no efficiency model (k-factors). Add **escape peaks** as tied Gaussians in science mode. **Al Kα's low-energy tail sits under Mg Kα** (0.233 keV ≈ 3 FWHM away, Al Kα = 70 % of all counts): no Gaussian model represents it. Use the diffraction-defined **matrix pool as the empirical blank** for Mg/Si (see E). Pile-up: flag, do not fit |
| **Quantification** | Cliff-Lorimer (first two lines above `min_intensity` 0.1 as reference; single-line pixel ⇒ 100 %), zeta (needs probe current + live time), cross-section (user factors) [validation §1c] | Velox: theoretical k from Brown-Powell/Bote-Salvat/Schreiber-Wims, 20 % k-uncertainty rule [velox §1]; Bruker ζ + polynomial interpolation [market B4]; Oxford M2T single-standard mass thickness [market O4]; DTSA-II uncertainty budgets [market P6] | Port CL + zeta + cross-section exactly (pins exist). Theoretical k-factors are **out of v5.0** (needs ionisation cross-sections, yields, efficiency — table rights unverified). k-factors come from a user file with source+date shown; "20 %" shown as a separate uncertainty term, never folded silently |
| **Absorption** | thin-film, x/(1−e^(−x)), x = μ/ρ·ρt·csc(TOA), iterate until Δ < 0.5, ≤ 30 iterations, MACs ×0.1; log-log interpolation; strip the (0,0) sentinel row [validation §1c] | Velox: Super-X geometry per segment, holder shadowing profiles, no fluorescence, negligible < 20 nm [velox §1]; GMS: unverified | Port exactly for parity. **Refuse** on summed multi-detector data unless the stream is per segment (the owner's Super-X G1 files are one summed stream [ownerdata §4] ⇒ refusal with reason on his data). Thickness input = the typed ± σ value already in the app. MAC source: **M2** (EPQ `FFastMAC.csv` recommended by [validation §2]) |
| **Decomposition** | HyperSpy PCA with Poisson scaling: X_ij / √(a_i·b_j), a = row sums, b = column sums [verified: `_mva.py:1648-1652`]; exspy `decomposition` applies the vacuum mask by default | Potapov & Lubk "optimal" PCA: Marchenko-Pastur component cut [unverified detail]; NMF-GKL; **espm**: X ≈ G·W·H, GKL divergence, Laplacian smoothness on H, log-sparsity, simplex; G = per-element characteristic columns + 2 continuum columns, MIT code [verified: `smooth_nmf.py:1-60`, `edxs.py:179-290`]; PSNMF (arXiv 2405.14649) [unverified] | Parity: Poisson-PCA with HyperSpy's scaling, synthetic-SI gate. Science: espm-style physics-guided NMF with **G built from our own line table** (needs only line energies and family weights; cross-sections only set absolute scale, which W absorbs) — so no espm tables are bundled [validation §2 licence caveat] |
| **Denoising** | none (binning) | Velox pre-filter (count-conserving box/Gaussian), post-filter Wiener, count-based recommended kernel [velox §1]; PCA reconstruction (Bruker AutoPhase, HREM MSA) [market] | Count-conserving spatial bin/pre-filter with the kernel shown; PCA reconstruction labelled "reconstructed, k components"; diffraction-guided smoothing is approach G. Rule: **quantification never reads a denoised cube** — it reads pooled raw counts or per-pixel raw counts with CIs |

### 1.2 The statistics layer (common to every method; Swift-native, no upstream to match)

This is what no vendor ships [market §4.3] and what the repo's rule demands.

- Net counts: N = G − s·B, Var(N) = G + s²·B (independent Poisson windows). Model-fit amplitudes: covariance from the observed Fisher information of the Poisson likelihood.
- Two-element CL ratio r = k·N_A/N_B: (σ_r/r)² = Var(N_A)/N_A² + Var(N_B)/N_B² + (σ_k/k)². Report the counting term and the k term **separately**.
- Below ~20 net counts: Garwood exact Poisson intervals on gross counts; profile-likelihood intervals for net; never a Gaussian CI that crosses zero.
- Detection: Currie critical level L_C ≈ 2.33·σ_B and detection limit L_D ≈ 2.71 + 4.65·σ_B per element per pool, shown next to the net count. "Mg: 12 ± 6 net, L_D = 9" is a result; "Mg detected" is not.
- Planning quantity ("would I see it?"): expected counts of line X in a pool, from the matrix pool and k-factors only: λ_X = N_Al(pool) · (C_X/C_Al)_projected / k_X,Al. No cross-sections needed. Lets the app say "this object needs 4× the dose to put Mg above L_D at 3σ".
- Coverage is the test: on the synthetic cube, the fraction of stated 68 % intervals that contain the truth must be ~68 % across the dose ladder N ∈ {0.3, 1, 3, 10, 30, 100} [validation §4]. Break the test by shrinking the CI by 2× and confirm it goes red.

### 1.3 Port order and provenance (dependencies first, fixtures available)

| # | Package | Take from | Gate fixture |
|---|---|---|---|
| P0 | Line table, FWHM, energy axis, `.msa` + `.hspy` readers, parity harness + `fetch-exspy.sh` pin (exspy `7185a4d1`, hyperspy 2.4.0, rsciio 0.14.0) | exspy | FePt + TM002 pins; FWHM pins [validation §1b] |
| P1 | Window intensities + background windows + merge rule | exspy | 3710/15872; 2754/15090; TM002 [84163, 89063, 96117, 96700, 99075]; Mn Kα 53597/46716 |
| P2 | CL + absorption + MAC table + CL mass thickness | exspy; MAC source per **M2** | Al-Zn pins (22.70779; 22.743013/31.816908; 6.1317741e-4); MAC pins |
| P3 | Statistics layer (§1.2) | own | synthetic coverage test |
| P4 | Velox stream decoder → CSR, DM SI reader | rsciio semantics [formats] | rsciio 4-detector sums 865236/913682/867647/916174 [validation §1g] |
| P5 | Gaussian + poly6 model, LS (parity), then Poisson-ML (science) | exspy/HyperSpy; loss from **M3** | Fe/Cr/Zn closed-loop [0.5,0.2,0.3] within 1e-4; FePt model 2800.0213/14921.183 within tolerance |
| P6 | Poisson-PCA | HyperSpy scaling | synthetic SI, eigenvalue pins from the pinned env |
| P7 | zeta + cross-section + probe-current entry | exspy | zeta 80.962287987 / 2.7125736e-3; cross-section pins |
| P8 | Physical continuum, escape peaks (science) | espm functions (MIT code, no tables) | synthetic science tier |
| P9 | NMF-GKL + Laplacian (espm-style) | espm algorithm | espm's built-in generators (particles N=500; grain boundary N=15) [validation §3] |

Everything from P4 onward can run against the owner's 107 Velox streams as *diagnostics*, never as gates [repo §4.5].

### 1.4 `DEVIATION` notes to expect (owner decides each)

Vacuum mask default 1.0 count (dataset property — ship the per-pixel max-count map instead); `min_intensity` 0.1 single-line = 100 % (refuse: report "one line only"); H/He rows; Li dropped silently (refuse Li/Be/H/He with the reason); signed convergence test; sentinel row; invented geometry defaults 35°/0°/130 eV (refuse: ask, show source "file"/"typed"); corrected line energies; LS→Poisson-ML in science mode; Al Kβ/tail handling via the matrix blank. [validation §1d] plus mine.

---

## 2. Part (b) — joint 4D-STEM + EDX approaches

### 2.0 Common substrate

- **Joint grid = the 4D source grid.** Registration is a recorded 2×3 affine (spectrum px → 4D source px) with method, evidence and residual [repo §1b]; resampling is count-conserving footprint summation, never interpolation. Every pooled result carries the registration residual and the mask erosion it implies (erode object masks by the residual before pooling; show how many pixels that removed).
- **Pools** are the four things the app already defines: precipitate objects (`Object.pixelIndices`), phase verdicts (`PhaseVectorResult.phaseIndex`), diffraction groups (`groupOf`), virtual-detector ROIs — plus the **matrix pool** (`.matrix` verdict pixels), which is the blank.
- **Projection model** (used by E and B*): C_apparent ≈ f·C_ppt + (1−f)·C_matrix, f = h/t, h = object extent along the beam, t = typed foil thickness ± σ. For an in-plane β″ needle h ≈ needle width (`widthPx` × pixel size); for an end-on needle h ≤ t. f is shown, editable, and the inversion C_ppt = (C_app − (1−f)·C_matrix)/f is reported **with its error blow-up at small f**, never hidden. (β″ needle widths ~4 nm are literature values [unverified]; the app measures its own.)
- **Indistinguishability check:** from each candidate CIF's `AtomSite(z, occupancy)`, compute at% over *detectable* elements (Z ≥ 5 with a line below E₀/2). Two candidates whose detectable-element compositions differ by less than the pool's resolving power are flagged "EDX cannot separate these"; the T1/θ′ pair is the unit test (identical by construction). The app derives phase stoichiometries from the CIFs it holds (built-in β″ Mg₅Si₆ exists at `Crystal.swift:267`); the Al-Mg-Si zoo (β′, Q, U1, U2, B′) needs CIFs imported — **M5**.
- **Back-of-envelope for the owner's system** [estimate, all inputs stated]: at 13 counts/px with 70 % Al Kα, k_MgAl ≈ 1, a β″ needle at 40 at% Mg: end-on (f ≈ 0.3–0.5 for a 30–50 nm needle in a 100 nm foil) gives ~1–2 Mg counts/px over ~7 px ⇒ ~10 net counts per object (≈ 30 % relative); in-plane (f ≈ 0.04) ≈ 0.3 counts/px over ~100 px ≈ 30 counts. At a 10 ms 4D dwell (×13) both become 10²-count pools. So **E works on his existing data for end-on needles only at the ~30 % level and on joint data for all** — if the dwell/current estimate holds [unverified].

### 2.1 The approaches

**E. Diffraction-guided pooling (per object / phase / group / ROI / matrix).**
*Computes:* per pool, the live-time-weighted summed spectrum, net line counts, apparent composition with the §1.2 statistics, detection limits, f-corrected composition, difference spectrum (pool − f-scaled matrix blank). *Inputs:* registration ∘ view, the four pool sources, typed thickness. *Statistics:* exact Poisson on sums; registration erosion; blank subtraction adds Var(blank)·(N_pool/N_blank)². *GPU:* none needed (≤ 109k joint pixels; sums over CSR). *Failure modes:* mis-indexed pools (a wrong phase verdict pools the wrong pixels — mitigated by showing `phaseContrast` distribution of the pooled pixels and letting the user pool by *group* instead of verdict); projection through matrix (f shown); Li (indistinguishability flag); registration drift (residual shown, erosion shown); frames with beam damage (Velox frames: first-vs-last frame check [velox §1]). *Display:* one evidence row per pool: gross/net/L_D per line, at% ± (stat) ± (k), f, N_px, live time, erosion, nearest-zone-axis angle (from I), registration residual; difference spectrum plot with residual. *Validation:* synthetic tier 1 (parity arithmetic) and tier 2 (espm forward model, coverage of CIs across the dose ladder, planted projection fraction and registration offset) [validation §4]; YAlO₃ dm4 (1:1:3 stoichiometry, pooled) [validation §3]; Ni65Cu35 as a homogeneity *stability* check; the owner's re-acquired 190330 field as the first real registered pair (Velox's own net maps as vendor reference, not truth). *Novelty:* no vendor pools over diffraction-defined objects or reports per-object Poisson CIs/detection limits [market §4]. Gatan's "mask by element map" is the reverse direction (see H).

**B\* — candidate arbitration table (absorbs A and C).**
Rather than three features, one table per pool: for every candidate phase p the diffraction evidence (best `score`, `runnerUpScore`, `phaseContrast`, matched/surviving counts — all existing) beside the EDX evidence: the profile log-likelihood ℓ_p = max_f Σ_lines [n log λ_p(f) − λ_p(f)] under λ_p(f) = dose-scaled (f·C_p + (1−f)·C_matrix) via k-factors, and the pairwise LLR Δℓ_pq. A one-sided "would have seen" test (expected counts at f_min vs L_D) is approach **A** as a row flag; running the matcher restricted to survivors is approach **C** — unnecessary here because the matcher scores all candidates anyway (templates are few; Bruker restricts for SEM speed [market B]) and restricting would move phase-map numbers (Gate D on `classify(candidateEntryIndices:)` [repo §3]). *Combining the two columns into one posterior* requires a map from the diffraction score to a likelihood; that calibration is a **dataset property** (repo rule) — so v5.0 ships the two columns and the LLR, and a calibrated posterior is pre-registered against the synthetic truth and shipped later with its calibration curve visible. *Statistics:* Poisson profile likelihood; f and thickness as nuisances; k uncertainty inflates λ. *GPU:* none. *Failure modes:* Li/indistinguishable pairs (flag ⇒ LLR shown as "0 by construction"); thin objects (f small ⇒ LLR → 0, shown); mis-registration (erosion); wrong k-factors (20 % term). *Display:* the table, sortable; colour on symbols only. *Validation:* synthetic Al/β″/Q (Cu discriminates Q; Mg:Si ratios differ between β″ and β′ — values from the CIFs, not from me) and the T1/θ′ pair which must yield LLR = 0; Kho 2025 (simulated Au + Al₂Cu, CC BY) [validation §3]. *Novelty:* TESCAN's weighting is proprietary and TENSOR-only [market X4]; Oxford TruPhase, EDAX ChI-Scan, Bruker Advanced Phase ID are SEM [context]. An open, inspectable, uncertainty-carrying arbitration on 4D-STEM does not exist. Gate D when the posterior is combined.

**D. Joint clustering (Duran 2023 / Parish 2022).**
*Computes:* per pixel (or binned pixel), concatenated features [diffraction embedding `coordinates` (k-dim, existing) ‖ EDX Poisson-PCA scores (m-dim)], each block scaled by a robust σ, then `kMeans` (existing; fuzzy c-means later). *Statistics:* the block scale ratio is the dataset property Duran chose by hand; ship it, plus variance explained per block, plus ARI between the joint clustering and each single-modality clustering. *GPU:* PCA Gram from CSR (trivial), k-means existing. *Failure modes:* at 10 counts/px the EDX block is noise and the clustering is diffraction + noise (ARI vs diffraction-only → 1 tells the reader); binning helps (4×4 → ~200 counts) at the cost of resolution (bin shown); random starts (report the spread over starts). *Display:* cluster map, per-cluster pooled spectrum (= E on cluster pools) and mean pattern; ARI table. *Validation:* Duran's Co₂FeSi data (cluster agreement only, no truth), Kho 2025, synthetic ARI. *Novelty:* no commercial joint clustering; Bruker AutoPhase and JEOL Phase Analysis 2 are EDX-only [market]. Cheap because PCA and k-means exist; exploratory badge.

**G. Diffraction-regularised EDX maps.**
*Computes:* per line, the Poisson MAP map λ minimising Σ_i (λ_i − n_i log λ_i) + β Σ_ij w_ij (λ_i − λ_j)², with w_ij from diffraction similarity (embedding distance or group identity) between neighbours — a guided, count-aware smoother. *Statistics:* convex; "effective counts" per pixel = Σ_j w_ij n_j is the honest resolution statement. *GPU:* sparse iterations on ≤ 109k nodes, trivial. *Failure mode that matters:* chemistry boundaries that are not diffraction boundaries — **grain-boundary segregation** is smoothed away if the guide says "same grain on both sides". Mitigation: continuous weights (never hard groups), β shown, raw map always beside, and a synthetic test with a planted segregation line that must survive at the stated effective-count resolution. *Validation:* synthetic only at first; Kho 2025. *Novelty:* none commercial. v6.

**F. Shared-abundance joint factorisation.**
X_edx ≈ G·W·H and D_diff ≈ P·H with shared H. The EDX half is espm. The diffraction half has no honest linear mixing model: the same phase at different orientations is a different pattern, so "components" would be (phase × orientation) classes, and the only physical coupling between composition and pattern is phase identity — which B* already uses — unlike Hovden's HAADF ∝ Σ Z^γ x coupling that makes fused tomography work [context]. In practice F collapses to "espm NMF with H regularised by diffraction groups", i.e. G applied to abundances. *Verdict:* pre-register as research after G; do not plan v5 effort on it. Badged unvalidated; synthetic truth only.

**Additional approaches the reports surface**

- **H. Masking both ways** (Gatan's demonstrated joint step [gms §3]): EDX map → mask on orientation/phase map, and 4D map → mask on EDX map. Display feature of E; trivial; include.
- **I. Channelling flag from orientation.** From ACOM, the misorientation of each pool/pixel from the nearest low-index zone axis; EDX quantification near zone axes is biased (MacArthur 2021, Liao & Marks 2013 [validation §5, unverified detail]). Ship the angle in the evidence row and the Al Kα rate vs orientation across grains as a plot; no threshold. Novel; cheap; needs the existing ACOM result only.
- **J. Reverse pooling.** EDX-defined pixels (e.g. net Si above a user-visible count) → pooled diffraction pattern → sent to the phase matcher. Identifies a chemically distinct region whose pattern is unknown. Mechanism likely exists in `VirtualDetector.realSpaceRegion` [repo §3, unverified that the mean pattern over a region is exposed].
- **K. EDX thickness into the density goal.** Zeta mass thickness per pool (needs probe current — entered, labelled, **M6**) or CL mass thickness (needs composition) feeds the registered N_V = (1/A)·Σ 1/(t + hᵢ) with a per-object t instead of one typed value. Unvalidated until ζ is measured on a standard (none in the lab [ownerdata]); Oxford M2T is the commercial analogue but unlinked to objects [market O4].
- **Excluded for v5:** CNN EDS-from-4D-STEM (Kumar & Rakita) — needs training truth that does not exist; Direct Electron's BF-disk-edge composition patent [market N4]; fused tomography (no tilt series).

### 2.2 Comparison

| | Needs per pixel ≥ | New Core maths | GPU | Gate | Truth available now | Commercial precedent |
|---|---|---|---|---|---|---|
| E | none (pools) | small | no | B | synthetic; YAlO₃ (stoich.) | none for objects + CIs |
| B* | none (pools) | profile likelihood | no | B; D when combined | synthetic; Kho 2025 | TESCAN (closed) |
| I, H, J, K | none | tiny | no | B | synthetic | none / Gatan mask / Oxford M2T |
| D | ~10² (binned) | PCA block | PCA Gram | B (exploratory badge) | Duran (no truth), Kho | none |
| G | ~10 | convex solver | trivial | D + pre-reg | synthetic | none |
| F | ~10² | NMF + diffraction model | moderate | D + pre-reg | synthetic | none |

GPU note: all joint work lives on the ≤ 109k-pixel 4D grid. The only heavy plain-EDX work is per-pixel model fitting on the full Velox grid (4.2 M px × 4096 ch, 35 M events [formats §2.2]): fixed-design LS is one sparse projection (sub-second); Poisson-ML multiplicative updates are ~10¹¹ flop per iteration dense, 10× less with line-window support — seconds to a minute on an M5 Pro [estimate, unverified]. Default per-pixel fits to a visible spatial bin.

---

## 3. Three strategies for v5.0

**S1 — "Count-honest companion"** (favoured). Baseline P0–P5 + statistics layer; readers (Velox stream, DM SI, msa/hspy); registration record; **E** with matrix blank and projection model; **H, I, K**; the indistinguishability check as a standing refusal. Everything else is display. Roughly the repo report's packages 0–9 minus the `.bcf` reader: 24–34 sessions [repo §6, estimate].
*Staging:* (1) plain EDX on the owner's Velox files, pooled by ROI and by EDX cluster — usable before any 4D link; (2) cross-session registration on the 190330 pair, then a re-acquired field at the 4D tilt; (3) E on precipitate objects.

**S2 — "Arbitrated phase map"** = S1 + **B\*** (table first, calibrated posterior pre-registered) + the Al-Mg-Si CIF set + the synthetic truth cube with θ′/T1 and β″/β′/Q. Adds ~3–5 sessions [repo §6]. This is the open TESCAN-equivalent and the one thing that bears on the owner's own science question (which Mg-Si-(Cu) phase a needle is) — provided the pools reach 10² counts.

**S3 — "Joint-statistical"** = S1 + **D** (cheap, exploratory) then **G**, then F as research. D costs ~2 sessions because PCA and k-means exist; G/F 6–10+ sessions with no precedent and synthetic-only truth.

**Staged order I recommend:** v5.0 = S1 + the B* *table* (no combined posterior) + D behind an exploratory badge; v5.x = the calibrated posterior once the synthetic coverage test and one real pair exist; v6 = G, then F if G earns it.

---

## 4. Why S1(+B* table) and what would change it

Why: (i) the owner's data are 11–19 counts/px with sub-count Mg/Si — only pooling yields a number with a defensible interval, and that number plus its detection limit is the honest product; (ii) no joint recording exists, so registration, not fusion, is the first problem on every real dataset he has; (iii) the arbitration posterior needs a dataset-dependent calibration, which the repo's threshold rule forbids shipping blind — the table ships the quantities and defers the calibration; (iv) Li/indistinguishability must be a refusal before any arbitration exists, and it costs little; (v) per-object Poisson CIs + detection limits + explicit "apparent/projected" + the channelling angle are exactly the gaps the market study found empty, and they are small Core work against existing hooks.

Evidence that would move me:
- A real 4D-STEM + EDX acquisition on the Talos showing ≥ 10² counts/px (one short STEMx + Esprit `ExternControl` test, saved as `.dm4` [gms §6]) ⇒ B*'s posterior and D move into v5.0; per-pixel science-mode fits become meaningful.
- The owner's stated question is phase identity of needles (β″ vs β′ vs Q) rather than composition per se ⇒ S2 is the product; pull B* forward and acquire the CIFs first.
- Synthetic tier-2 coverage test showing E's intervals under-cover at f < 0.1 ⇒ the projection inversion is removed from the row (keep apparent only).
- A planted-segregation test that G passes at the dose ladder ⇒ G earns a v5.x slot as the map denoiser instead of PCA reconstruction.
- If MAC/line-table rights block bundling (M1/M2) ⇒ parity ships with exspy's tables as GPL data and science mode waits.

---

## 5. Unverified items and decisions for the owner

Unverified: 4D-dwell count estimate (beam current and CL differ between modes); β″ needle dimensions (app measures them); PyMca licence and SNIP details; Potapov-Lubk cut rule; PSNMF content; whether `VirtualDetector` exposes a mean pattern over a region; M5 Pro GPU throughput; whether the owner's GMS has EDS/Hi-Speed SI licences; Velox probe current in metadata; espm table rights (CC BY-SA submodule) — the plan above avoids bundling them.

Decisions (each needs the second opinion the ADR 050 sheet requires):
- **M1** line table: exspy verbatim (parity) + corrected table (science) with per-line DEVIATION, or exspy only.
- **M2** MAC source: EPQ `FFastMAC.csv` / exspy copy / xraylib (= validation D1).
- **M3** science-mode loss: Poisson-ML (recommended) vs LS everywhere (= validation D3).
- **M4** dataset-dependent exspy defaults (vacuum mask 1.0, min_intensity 0.1): port or refuse-and-show (= validation D2; I recommend refuse-and-show).
- **M5** Al-Mg-Si candidate CIFs to import for B* (β′, Q, U1, U2, B′) and the synthetic cube's phase set (θ′/T1 pair included as the mandatory refusal test).
- **M6** probe-current entry for zeta/K: typed with source, or zeta deferred.
- **M7** B* in v5.0 as table only (recommended) vs with a combined posterior (Gate D, needs calibration per dataset).
- **M8** first real truth dataset: ePSIC YAlO₃ dm4 (recommended, also a dm4 reader pin), SRM 2063a (SEM physics), or a lab standard (= validation D5).