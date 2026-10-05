# v5.0 EDX suite: validation and science plan

Scratch root: `X = <scratch>/edx`. I wrote nothing under the repo.

**What I did to get here.**
- I shallow-cloned exspy into `X/exspy`, at commit `7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e` (2026-10-02).
- I also shallow-cloned espm into `X/espm` (commit `e882ed6b`), which goes slightly beyond the task: it is source code from GitHub and I only read it.
- I made a scratch venv at `X/venv` and installed packages from PyPI: hyperspy 2.4.0, rosettasciio 0.14.0, numpy 2.5.3, scipy 1.18.1 and pytest 9.1.1. This is also beyond the task.
- I downloaded no dataset files. I read two notebooks (Figshare and Zenodo) by streaming them through a parser; neither was saved.
- Every number labelled "run" below comes from a dated log in `X/`.

---

## 1. Parity pins (exspy at `7185a4d1`)

### 1a. Environment pin
The exspy EDS tests pass in this environment: **238 passed in 9.82 s** (`X/pytest-eds.log`, 2026-10-05). That is 108 test functions, expanded by parametrize and the lazy-copy class decorator.

Pinning exspy alone is not enough. Much of the behaviour that sets the numbers lives in hyperspy:
- **Value-to-index rounding.** Hyperspy truncates at 1e-12, then rounds half towards zero for positive values (`X/venv/.../hyperspy/axes.py:1283-1334`).
- **Half-open window slicing:** `isig[a:b]` (`axes.py:401-471`).
- **Window sums:** `integrate1D` sums counts on a binned EDS axis.
- **Fit defaults:** `Model1D.fit` defaults to optimizer `"lm"` with least-squares loss `"ls"`; `"ML-poisson"` is available (`hyperspy/model.py:1774-1775, 1841`).

**Recommendation:** add a `fetch-exspy.sh` lock in the style of `tools/lib/fetch-py4dstem.sh`, with exspy `7185a4d1`, hyperspy 2.4.0 and rosettasciio 0.14.0 pinned together.

### 1b. Closed-form and integer pins, confirmed by running
Logs: `X/verify_doctests-2026-10-05.log`, `X/checks2-2026-10-05.log`, `X/reimpl_windows-2026-10-05.log`, `X/fept_quant-2026-10-05.log`.

**Line width (FWHM)**, from `utils/eds/_xray_lines.py:138-175`:
- Al Kα: 0.07661266213883969 keV at 130 eV; 0.073167615787314 at 128 eV. Test-pinned at `tests/signals/test_eds_sem.py:411-416`.
- Fe Kα 0.13477017 keV, Pt Lα 0.16049455, C Kα 0.05334557, Cu Kα 0.14924058 (run).
- The function returns keV. A comment at line 175 says "mrad"; that is wrong but changes no number.

**Take-off angle**, from `_geometry.py:24-85`:
- Test pins (`tests/misc/test_eds.py:85-90`): `take_off_angle(30,0,10)` = 40.0; `(0,90,10, beta=30)` = 40.0; `(45,45,45,45)` = 73.15788376370121.
- SEM test pins (`test_eds_sem.py:206-213`): 12.886929785732487, and 24.202671071140102 with beta = 15.5.
- Docstring values I confirmed by running: (10, 45, 22) gives 28.865971201155283 (`_geometry.py:51-53`); TM002 gives 37.0, and 57.0 at tilt 20 (`signals/_eds.py:719-724`).

**Window intensities on the bundled FePt spectrum** (integers):
- `get_lines_intensity()` gives Fe_Ka **3710**, Pt_La **15872**. Test-pinned at `test_eds_tem.py:628-634`.
- With background windows at `line_width=[5,2]`: **2754 / 15090**. These appear only in docstrings (`_eds.py:818-824`), and I confirmed them by running.
- My independent numpy re-implementation reproduces all four exactly. The channel index ranges are [304, 318) and [455, 471) (`X/reimpl_windows-2026-10-05.log`).

**TM002 pins:**
- Default intensities [84163, 89063, 96117, 96700, 99075] (Al Kα, C Kα, Cu Lα, Mn Lα, Zr Lα), test-pinned at `test_eds_sem.py:346-351`.
- From docstrings, confirmed by running: Mn Kα with a 2.1×FWHM window gives 53597 (`_eds.py:619-623`); Mn-only background-subtracted gives 46716 (`_eds.py:625-631`).

**Cliff-Lorimer on FePt** with k = [1.450226, 5.075602] (run):
- Window intensities: Fe **15.409297 at%** (4.956176 wt%).
- Model-fit intensities: Fe 15.775466 at%, with fitted intensities 2800.0213 / 14921.183.
- The test only requires these two routes to agree within 5% (`tests/models/test_edsmodel.py:253-277`).

**Mass absorption coefficients (MACs)**, test-pinned at `tests/material/test_material.py:96-127`:
- Al at 3.5 keV: 506.0153356472.
- Ta at [1, 3.2, 2.3] keV: [3343.708…, 1540.082…, 3011.265…].
- Zn absorbing Zn Lα: 1413.291119134.
- 50/50 Al-Zn mixture at Al Kα: 2587.4161643905127.
- Cu-Sn mixture: [8003.05391481, 4213.4235561].

From docstrings, confirmed by running: Al absorbing [C Kα, Al Kα] gives [26330.38933818, 372.02616732] (`material/_material.py:340-342`).

**Ranges and composition conversions:**
- Electron range, Cu at 30 kV: 2.8766744984001607 (docstring at `utils/eds/_particle_matter_interaction.py:55`, confirmed by running). Test pins at `test_eds_sem.py:375, 385`: 0.41350651162374225 and 0.1900368800933955.
- X-ray range, Cu Kα at 30 kV: 1.9361716759499248; in carbon: 7.641881128085545.
- Weight to atomic, Cu/Sn 88/12: 93.196986 / 6.803013 (`test_material.py:52-58`).

**Quantification pins on the synthetic Al-Zn image** (`test_eds_tem.py`):

| Method | Result | Lines |
|---|---|---|
| Cliff-Lorimer, k = [1, 2.0009344042484134] | 22.70779 wt% | 238, 245, 258, 530 |
| Cliff-Lorimer + absorption, t = 1 nm / 300 nm | 22.743013 / 31.816908 | 320-326 |
| Zeta | 80.962287987 wt%, mass thickness 2.7125736e-3 | 335-340 |
| Zeta + absorption | 65.5867 | 358-360 |
| Cross-section, factors [3, 5] | atoms 21517.1647 / 21961.6166; composition 49.4889 | 445-451 |
| Zeta from cross-section | 36.2969 | 437 |
| Cross-section + absorption | 44.02534 | 473-474 |
| Cross-section → zeta, Pt/Ni | [1079.815272, 162.4378035] | 510 |
| Mass thickness (CL helper) | 6.1317741e-4 | 541 |
| Zero handling | [[.2,.2,.6], [0,.25,.75], [.25,0,.75], [.5,.5,0], [1,0,0]] | 478-504 |

**Line database pins:**
- Fe Kα 6.4039, Fe Lα 0.7045, Pt Kα 66.8311, Pt Lα 9.4421, Pt Mα 2.0505, Pt Mβ 2.1276 (weight 0.59443) (`test_eds.py:93-114`).
- Exact ordered lists of lines near 1.36 keV and 5.4 keV (`test_eds.py:30-82`).
- Exact printed tables (`test_eds.py:117-160`; `test_eds_sem.py:419-464`).

**Model-fit pins (closed loop):**
- Fe/Cr/Zn fit recovers [0.5, 0.2, 0.3] within 1e-4 (`test_edsmodel.py:53-59`).
- Quantification returns [50, 20, 30] (`:229-243`).
- Model components are a 6th-order polynomial plus Cr Kα, Cr Kβ, Fe Kα, Fe Kβ, Zn Kα (`:61-72`).
- Fe Kβ sub-weight calibration: 0.0347 within 1e-3 (`:201`).
- `multifit` reproduces mixed maps within 1e-7 (`:313-342`).

These synthetic tests are built with `xray_lines_model`, where line area equals weight fraction, so the k-factor is 1 by construction (`_xray_lines.py:226-239`). They test the arithmetic only, not the physics.

### 1c. Rules a Swift port must reproduce exactly
- **Integration window:** E ± (width × FWHM)/2, default width 2.0 (`_eds.py:552, 783`).
- **Background windows:** the scaling factor is `(i5-i4)/((i1-i0)+(i3-i2))`, computed on rounded indices (`_eds.py:679`). Overlapping windows from different lines are merged (`_eds.py:~835-845`). On TM002 the merge alone changes the background-subtracted results: exspy gives 69287.29 etc.; my version without merging gives 63805.
- **Line selection:** with `only_one`, the highest-energy line below beam energy / 2 is used (`_eds.py:513-518`). Lines are returned in alphabetical order, so factors must follow that order (`_eds.py:489`; user guide `doc/user_guide/eds.rst:683-685`).
- **Cliff-Lorimer reference element:** the first two lines above `min_intensity = 0.1` are the reference (`_quantification.py:61, 75`). A pixel with only one line above that threshold reports 100% of that element (`:83-86`).
- **Absorption correction:** factor = x / (1 − e^(−x)) with x = μ/ρ · ρt · csc(TOA), and MACs converted ×0.1 to m²/kg (`_quantification.py:214-225, 309-315`).
- **Iteration:** stops when the change is below 0.5, up to 30 iterations (`_eds_tem.py:306, 313`). The test uses the *signed* maximum change, `np.max(new−old)`, before taking the absolute value (`:512-518`).
- **Mass thickness for Cliff-Lorimer:** a weight-fraction average of pure-element densities (`_eds_tem.py:922-965`).
- **MAC interpolation:** log-log, via `searchsorted` (`_material.py:357-374`). Every one of the 90 elements in the absorption table ends with a (0, 0) sentinel row (`X/checks3-ffast-2026-10-05.log`); a port must strip it.
- **Model:** one Gaussian per line, with fixed centre and width. Family lines are tied to the main line with weights from the database. Starting amplitude is the data at the line × FWHM / channel width. The background is a 6th-order polynomial (`models/edsmodel.py:183-299`).

### 1d. Proposed DEVIATION notes (owner decides)
1. **Vacuum mask.** `vacuum_mask` defaults to a threshold of 1.0 count on the per-pixel spectral maximum. `quantification` and `decomposition` both apply it by default (`_eds_tem.py:307, 410, 622, 634`). Whether a pixel passes depends on channel width and dose, so it is a dataset property. On a synthetic Al₂Cu image (2048 × 10 eV channels) it masks **100% of pixels at 1–3 counts per pixel and 74–96% at 10 counts** (`X/lowcount-2026-10-05.log`).
2. **Single-line pixels.** At ≤ 3 counts per pixel, 30–51% of pixels have exactly one line above 0.1 and would report 100% of that element (same log).
3. **H and He entries.** The line database has H "Kα" at 0.0013598 keV and He at 0.0024587 keV. These are not real EDX lines; exclude them.
4. **Lithium is dropped silently.** `set_elements(["Al","Cu","Li"])` keeps Li as an element but gives it no lines, and raises no warning (`X/li-2026-10-05.log`).
5. **Signed convergence test:** see 1c.
6. **Absorption-table sentinel:** strip the trailing (0, 0) row.
7. **Invented geometry.** Missing metadata is filled in silently: tilt 0°, azimuth 0°, elevation 35°, resolution 130 eV (`_defaults_parser.py:90-110`, applied at `_eds_tem.py:85-112`).

### 1e. Do not use these as pins
- **Doctests do not run.** `pyproject.toml:117-118` has no `--doctest-modules` and only collects `exspy/tests`.
- **`_eds.py:615-617`** asks for Mn Kα but prints "Mn_La … 96700". Run as written it gives Mn_Ka **52773**.
- **`_eds.py:767-773` and `818-824`** label the 3710/15872 and 2754/15090 examples as `EDS_SEM_TM002`. They only hold on `EDS_TEM_FePt_nanoparticles`; TM002's elements are Al, C, Cu, Mn, Zr (`tests/data/test_data.py:28`).
- **`test_eds_tem.py:186-189`** sets the Gaussian's σ to the FWHM.
- **`test_eds_tem.py:336`** checks 2.71e-3 with an absolute tolerance of 1e-3, so it barely constrains the value.
- **`test_eds_tem.py:646-649`** wraps a comparison in `sorted(...)`, which always passes.
- **k-factor mismatch.** exspy-demos `EDS/TEM_EDS_nanoparticles.ipynb` cell 42 uses k = [1.450226, **5.75602**]. The exspy docs, tests and the same notebook's cell 95 use **5.075602**.

### 1f. Bundled datasets
Both are single spectra; exspy bundles no spectrum images.

| File | Size | Content |
|---|---|---|
| `X/exspy/exspy/data/EDS_SEM_TM002.hspy` | 31,008 B | 1024 channels, int32, SEM at 10 kV (Zeiss Nvision40, Oxford X-max 80), BAM EDS-TM002 layer of C, Al, Mn, Cu, Zr on Si (`data/_eds.py:35-50`) |
| `X/exspy/exspy/data/EDS_TEM_FePt_nanoparticles.hspy` | 28,680 B | 992 channels, uint32, Tecnai Osiris 200 kV, Super-X, elevation 22°, resolution 133.312296 eV |

Both are below the repo's 1 MiB tracked-file guard (`tools/large-files.allow`).

### 1g. File-reader pins (rosettasciio 0.14.0)
- **Velox 4-detector file** (`rsciio/tests/test_emd_velox.py:441-445`): per-detector sums 865236 / 913682 / 867647 / 916174; total 3562739. The reader sums the detectors by default (`rsciio/emd/_api.py:118`).
- **Missing coverage:** rosettasciio has **no Gatan dm4 EDS spectrum-image test file**. Its only Gatan EDS file is the single spectrum `test-EDS_spectrum.dm3`.
- **dm4 metadata:** the reader maps azimuth, elevation, solid angle, live time and real time (`rsciio/digitalmicrograph/_api.py:1073-1101`).

---

## 2. Data licences (my reading, not legal advice)

| Source | Licence | Can a GPL-3.0 app bundle it? |
|---|---|---|
| exspy JSON and Python tables | GPL-3.0 (`X/exspy/LICENSE`) | Yes, as GPL. Upstream provenance is stated in comments only (`material/_elements.py:1-11`): line energies "Chantler2005" (unverified — the attenuation tables tabulate edges, not emission lines), line weights from epq, EELS edge fields from the Gatan EELS atlas. An EDX port does not need the EELS file. |
| FFAST absorption table (`_misc/eds/ffast_mac.py:1-6`) | NIST SRD 66 | **Unclear.** NIST's database page carries a copyright notice and says NIST "reserves the right to charge for these data in the future" (nist.gov/pml/x-ray-form-factor-attenuation-and-scattering-tables). SRD compilations can be copyrighted under 15 USC 290e; terms are per database and no blanket licence is granted (nist.gov/open/license). The same page warns of high uncertainty below 1 keV. |
| NIST EPQ / DTSA-II | Public domain in the US, with a notice to keep (`usnistgov/EPQ/LicenseFile.txt`) | Yes, keeping the notice. EPQ itself ships `FFastMAC.csv`, `LineWeights.csv`, `deslattes.csv`, `SalvatXion/` and `Henke93/`. Sourcing absorption data from NIST's own permissive distribution is a cleaner permission chain than copying exspy's table (my interpretation). Third-party data inside EPQ (Henke, Salvat) may keep its original rights: unverified. |
| xraylib | BSD-3-Clause (`license_all.txt`) | Yes, keeping the notice. How its data was sourced in detail is unverified (Schoonjans et al. 2011, Spectrochim. Acta B 66:776). |
| espm and emtables | MIT (`X/espm/Licence.txt`; adriente/emtables `Licence.md`) | Code yes. emtables data comes from xraylib plus `Bote2009_*.txt` (journal coefficient tables, rights unverified) plus a Periodic-Table-JSON submodule licensed **CC BY-SA 3.0**. CC states that no non-CC licence is compatible with BY-SA 3.0 (creativecommons.org compatible-licenses page). Whether any espm table field comes from it is unverified, so **don't bundle the espm tables wholesale**. Also, espm imports exspy's absorption table at runtime (`X/espm/espm/conf.py:3`). |
| Gatan EELS atlas | Not checked (the site returned HTTP 429) | Not needed for EDX. |

---

## 3. Public datasets: truth or published reference results

**Joint 4D-STEM + EDX:**
- **Kho 2025, Zenodo 10.5281/zenodo.14859606** (CC BY 4.0). Contains `EDS-100.0_electrons_per_pixel.hspy` (0.6 MB), `SEND.hspy` (102.8 MB) and notebooks. This is a **simulated** Au-matrix plus Al₂Cu-precipitate case: the EDX was made with espm (the file's signal type is `EDS_espm`), and diffraction was also simulated. Paper: APL Materials 13 (2025). It is the only public joint case with simulation truth that I found. Whether the truth labels ship with the data is unverified.
- **Duran 2023, Figshare 10.48420/21610977.v1** (CC BY 4.0). Co₂FeSi Heusler on Si. Files: `dataset1_CBED.hspy` 459.3 MB, `dataset1_EDS.hspy` 1.06 MB (just over 1 MiB), `dataset2_CBED.hspy` 308.1 MB, `dataset2_EDS.hspy` 0.25 MB, plus notebooks.
  - Acquisition: **CBED, not precession**, with a 1.5 mrad convergence angle, Merlin Quad detector, Talos F200X, Super-X at 0.9 sr, dwell 2–25 ms (`X/papers/duran2023.txt:133-144`).
  - Reference pipeline (notebook): 150×50 scan, 4000-channel EDX, CBED binned to 128². Robust scaling per feature, variance matching (σ_diffraction/σ_EDX), concatenation, 10-component PCA, probabilistic Gustafson–Kessel fuzzy clustering into 6 clusters with 10 random starts, membership cut at 0.5.
  - No ground truth. Comparison must be cluster-agreement, not number-for-number, because the starts are random.
- **Mills et al. 2024, Acta Mater., Zenodo 10.5281/zenodo.8000141** (CC BY 4.0). Ni-20Cr corroded in FLiNaK, 300 kV. Files: `4DSTEM_EDS_scan_300kV_Diffraction SI.dm4` (5.3 GB), an EDX `.hspy` (0.8 MB), a hits file, and an Al calibration dm4 (1.1 GB). The diffraction data is a **dm4 "Diffraction SI"**, the same family as the owner's GMS files. No truth.
- **Parish 2022** (SEM EBSD + EDS on TiB₂/TiC, 80×60 pixels), ORNL DOI 10.13139/ORNLNCCS/1819695. Licence and size not stated. No truth.

**EDX quantification with truth:**
- **ePSIC YAlO₃, Zenodo 10.5281/zenodo.10609594** (CC BY 4.0). Contains `EDS Spectrum Image.dm4` (39.5 MB), `EDS_SI.hdf5` (0.9 MB) and EELS files. JEOL ARM200F at 200 kV, powder sample.
  - Truth is the **stoichiometry, Y:Al:O = 1:1:3**.
  - It is a GMS-format EDS spectrum image, so it also gives a dm4 reader pin.
  - Caveat: powder of unknown thickness, so O K absorption matters.
- **NIST mds2-2975** (NIST open licence, `STEMinSEM.zip` 0.34 MB). Spectra from **SRM 2063a, certified composition**, at 20–30 keV in an SEM, with DTSA-II scripts.
- **HyperSpy core-shell FePt@Fe₃O₄** (Rossouw 2015; Dropbox zip of about 1 MB; licence unverified). Published reference results:
  - exspy-demos notebook: bare core 16.64 at% Fe, separated core component 15.98 at% Fe.
  - Teurtrie 2024: bare cores 18 ± 3 at% Fe; shell 40/60 Fe/O, consistent with Fe₃O₄.

**Simulated EDX truth:**
- espm's built-in generators:
  - Particles: 80×80 pixels, N = 500 counts per pixel, seed 91.
  - Grain boundary: 100×400 pixels, **N = 15 counts per pixel**, seed 0.
  - Both defined at `X/espm/espm/datasets/built_in_EDXS_datasets.py:16-97`.
- Teurtrie 2024 (arXiv 2404.17496) tests at 18 and 293 counts per spectrum and scores spectral angle and abundance error.

**Real spectrum images bundled with espm** (`X/espm/generated_datasets/`):
- 71 GPa sample: 201×201×2048, mean 176.5 counts per pixel, 95.5% of channels zero.
- ES-LP sample: 80×80×1917, mean 112 counts per pixel.
- Both are 200 kV Bruker data recorded with mapping dwell times (`X/espm_data-2026-10-05.log`).

**Aluminium alloys (Thronsen / NTNU):**
- Zenodo 6645396 (SPED phase mapping) includes `ground_truth.hspy` but **no EDX**.
- Zenodo 2652906 (sheared β″ in AA6060, 46.6 GB) is SPED/STEM with no EDX listed.
- I found no public Al-alloy dataset with joint 4D-STEM + EDX. Neither the NCEM nor the Materials Data Facility catalogues produced a hit (unverified absence). ePSIC's open-data page lists no joint dataset.

---

## 4. Synthetic-truth strategy

Extend the existing demo cube (`tools/demo-dataset/make_demo.py`). It already has 12 per-region recipes, a seeded Poisson draw, and a `truth.json` plus PNG. Each recipe would gain an expected EDX spectrum, with every pixel drawn by Poisson at N counts.

**Two tiers, so the model that generates the data is not the model that scores it:**
1. **Parity tier.** Generate with exspy's own `xray_lines_model` (Gaussian lines, k = 1, no continuum or absorption). This tests that the port's arithmetic matches exspy.
2. **Science tier.** Generate with espm's forward model: cross-sections, a detector-efficiency curve, absorption and bremsstrahlung, with the noise formula at `datasets/base.py:15-70`. Score with the ported exspy pipeline.
   - The two upstreams model line width differently. espm uses a linear law, FWHM = 0.01·E + 0.065 keV (`built_in_EDXS_datasets.py:31-32`), against exspy's square-root law. That gap is a real model error the gate should measure, not hide.

**What `truth.json` must record:**
- Areal density of every element per pixel, **including the invisible Li**.
- Projected phase fraction per pixel (precipitate thickness ÷ foil thickness).
- Thickness map.
- Expected counts per line before noise.
- N, the seed, and every planted nuisance.

**Phases:**
- The demo's Al matrix and β″.
- Add θ′ (Al₂Cu) next to T1 (Al₂CuLi). Their Cu:Al ratios are identical (`X/li-2026-10-05.log`), so **any EDX-only method that separates them must fail the gate**.

**Nuisances, each switchable:**
- A Cu grid/system peak that does not depend on phase.
- Si escape peaks at E − 1.74 keV and sum peaks at 2E. Their strength fractions are assumptions to declare.
- A per-grain channelling multiplier on line intensities.
- A thickness wedge (absorption gradient).
- A known EDX-to-4D-STEM scan offset, binning difference and drift. ROADMAP:78-80 already requires the registration transform to be recorded.
- Per-quadrant detector efficiency.
- A dose ladder: N ∈ {0.3, 1, 3, 10, 30, 100}.

**Metrics:**
- Per-phase composition error with Poisson confidence intervals, and whether the reported intervals actually cover the truth.
- Spectral angle and abundance error (espm's metrics).
- Adjusted Rand index for clustering methods.
- Registration error in pixels.
- Score methods A–G on the same cube.

**Practical constraints:**
- numpy's Poisson stream cannot be reproduced in Swift. Generate the cube in Python, hash it, and test against truth within statistical tolerances, not byte-identity.
- A 100×100×2048 uint8 cube is about 20 MB, over the 1 MiB guard. Commit the generator, seed and hash, not the cube.

---

## 5. Physics limits the user must be told, and where to show them

- **Lithium and light elements.**
  - Li has no lines in exspy (`xray_lines.json`) or in espm's tables, which start at Z = 5.
  - Detecting Li needs special windowless SDDs, reaches only above about 20 wt%, and has a fluorescence yield around 10⁻⁴ (search summary of Hovington et al. and vendor notes; unverified detail).
  - EDX normalises over the elements it sees, so T1 appears as 66.7 / 33.3 at% Al/Cu, identical to θ′.
  - **UI:** the element picker blocks Li, Be, H and He, saying why. Results carry a footer "Li not measurable; at% renormalised over detected elements".
- **Projection through the matrix.** The composition of a thin precipitate is an "apparent, projected" value.
  - My estimate of beam broadening (Goldstein single-scattering formula, standard textbook): about 4 nm in 100 nm Al at 200 kV. That is comparable to θ′ plate thickness and larger than T1's (computed here, unverified against data).
  - **UI:** label it "apparent", and show the thickness the estimate assumes.
- **Channelling at zone axis.** Quantification is nonlinear at zone axis (MacArthur et al. 2021, Microsc. Microanal.). Tilt or precession reduces the effect (Liao & Marks 2013, Ultramicroscopy, cited from a search result).
  - **UI:** joint data lets the app see when a region is near a low-index zone axis, from its own orientation mapping, and flag that region's EDX.
- **Absorption and geometry.** The correction assumes a parallel-sided thin film and one detector (`doc/user_guide/eds.rst:821-829`), but Velox sums the four detectors by default.
  - In the rosettasciio Velox test file the four detectors' totals differ by up to 5.9%. The cause is not established.
  - Holder shadowing on Super-X strongly affects low- and medium-Z elements (Kraxner 2017, Ultramicroscopy 172:30).
  - **UI:** show the take-off angle and where each geometry value came from ("from file" or "default"). Refuse the absorption correction on summed multi-detector data.
- **Counts at 4D-STEM dwell times.**
  - My estimate from espm's Al cross-section (units assumed cm², so order of magnitude only): about **1 Al K count per pixel at 50 pA, 1 ms, 0.9 sr** and about 0.15 at 0.12 sr. It reaches 44 counts at 200 pA and 10 ms.
  - Mapping-dwell data has 112–177 counts per pixel (espm files above).
  - Per-pixel Cliff-Lorimer at 10 counts scatters by ±22–28 wt%, while the pooled estimate stays within 0.1–0.7 wt% of truth (`X/lowcount-2026-10-05.log`).
  - **UI:** a histogram of counts per pixel, with per-pixel confidence intervals instead of a hidden threshold, and pooling by phase, grain or object (method E).
- **Fit loss at low counts.** Least squares (exspy's default) and Poisson maximum-likelihood give Pt Lα of 14921 vs 15511 on the same spectrum, a 4% difference (Nelder–Mead convergence not checked; `X/fept_quant-2026-10-05.log`). Both the parity mode and any science mode must name the loss function used.
- **Beam damage and contamination.** Li loss and C/O build-up are not verified for these alloys.
  - **UI:** show dose per pixel in e/Å² for both signals, and compare first and last frames when frames exist (Velox `sum_frames=False`).
- **Where the k-factors came from.** exspy's docs accept vendor k-factors but prefer measured ones (`eds.rst:687-690`), and the demo/docs Pt mismatch in §1e shows the risk. Every result should show its k-factor source and date, and stay badged **unvalidated** until measured on a standard (SRM 2063a or YAlO₃).
- **Spurious peaks.** Neither exspy nor espm models escape peaks, pile-up, holder or grid peaks (a grep finds nothing). In practice exspy's own FePt test adds Cu to fit the background (`test_edsmodel.py:257`), and the demo fits Cu Kα and Co Kα but excludes them from quantification (cell 86).
  - **UI:** flag possible system peaks and escape/sum positions; let the user include them in the fit but never in the quantification.
- **Light-element absorption.** NIST flags high uncertainty in its tables below 1 keV, which affects O K, C K and Cu L. Badge any absorption-corrected value that relies on lines below 1 keV.

---

## 6. Corrections to the prior survey
1. The 3710/15872 and 2754/15090 pins belong to **EDS_TEM_FePt_nanoparticles**, not TM002, and exspy's doctests are never run.
2. Duran 2023 used **CBED 4D-STEM, not precession**. Its data is on Figshare, not in the paper.
3. The FWHM law and the "Gaussian per line plus 6th-order polynomial" model description are confirmed as stated.

## 7. Decisions for the owner
- **D1 – absorption-table source:** EPQ's `FFastMAC.csv` (recommended), exspy's copy, or xraylib.
- **D2 – dataset-dependent defaults:** port the vacuum mask (1.0 count) and the 0.1 minimum-intensity cut as they are, or deviate.
- **D3 – fitting loss:** least squares for parity versus Poisson ML for science.
- **D4 – synthetic generator:** use espm's forward model, or write one in Swift.
- **D5 – first real dataset with truth:** ePSIC YAlO₃ (dm4), SRM 2063a, or a standard from his own lab.

Every one of these needs an independent second opinion before it goes on a decision sheet.