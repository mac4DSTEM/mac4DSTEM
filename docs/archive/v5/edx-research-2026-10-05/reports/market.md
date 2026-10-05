# EDX software market study, round 2 (2026-10-05)

## What I did and where it is saved

- **Sources used:** public vendor pages and datasheets, university SOPs and manuals that are hosted publicly, conference abstracts, patents, GitHub issue trackers, and the docs that ship inside the owner's GMS 3.6.1 installer (already extracted by another agent; I read PDF and text files only).
- **Nothing was executed and nothing was written to the repo.**
- **Downloaded documents:** saved under `<scratch>/edx/market2/` (called `M2/` below). GMS installer documents sit under `.../scratchpad/edx/gms/` (called `GMS/` below).
- **How claims are marked:**
  - A tag in square brackets points to the source index at the end.
  - "unverified" means I could not open or confirm the source.
  - "(inference)" means it is my reasoning, not something a source states.
- **Quoting:** vendor text is paraphrased. There is one short quote, in the TESCAN section.

## Executive summary

1. **Only one commercial product does joint 4D-STEM and EDX analysis, and it is not the owner's platform.**
   - TESCAN TENSOR/Explore uses the EDX signal to weight candidate phases inside its diffraction template matching [X4].
   - Every other vendor that co-acquires the two signals only does so and then overlays the results:
     - Thermo Velox, with the Ceta camera and the EMPAD G2 detector [T1, T3].
     - Gatan GMS through eaSI [G4].
     - JEOL's FEMTUS platform (claimed, unverified) [J3].
   - Gatan's one joint step is to mask the orientation map with an EDS element map [G4]. That is the owner's platform.
2. **TESCAN's published demonstration used a lot of signal.** It ran at 1 nA with a 10 ms dwell [X3], and the authors warn that too few X-ray counts cause misidentification [X4].
   - (inference) At the owner's 0–10 counts per pixel, per-pixel weighting will not carry much. Pooling spectra over objects defined by diffraction (approach E) fits that count regime.
3. **Low counts are handled cosmetically everywhere.** The tools offer filters, binning, smoothing or a threshold:
   - Velox: average or Gaussian pre-filter [T2].
   - AZtec: binning, Gaussian smoothing and sigma thresholding [O2].
   - None of them fits a Poisson likelihood per pixel in the documents I found.
   - The only low-count claim is Thermo's ChemiPhase for SEM, which says it can start phase identification from as few as 10 counts per pixel [T5].
4. **Uncertainty is reported per result at best, never per pixel.**
   - AZtec shows a sigma column for wt% [O2]; Bruker lets the user choose the sigma level shown [B4].
   - I found no per-pixel uncertainty map in any product.
   - eXSpy reports no uncertainty from `quantification` at all [L1].
   - Only NIST DTSA-II and NeXL carry uncertainty budgets [P6, P7], and both are aimed at SEM bulk analysis.
5. **TEM quantification itself is a commodity.**
   - Cliff-Lorimer with theoretical or experimental k-factors, ζ-factors and thin-film absorption correction appear in Bruker [B1, B4], JEOL [J1], Oxford [O1, O4, O5] and Velox [T2].
   - Oxford's "Modified Cliff-Lorimer" plus M2T is effectively a ζ-like mass-thickness calibration: a single Si₃N₄ standard plus the user's density input gives mass thickness and thickness [O4, O5] (inference about equivalence).
6. **Every vendor tool is Windows-only and licensed tightly.**
   - AZtec: Windows 10 64-bit only [O7].
   - Velox: Windows 10/11 [T1].
   - GMS: Windows 10/11 or Windows Server [G1].
   - ESPRIT: Windows, hardware key, and a USB dongle for standalone data stations [B4].
   - The only public price is AZtecFlex, a 12-month licence locked to one PC with no acquisition: US$699 for EDS+WDS and US$1,399 for EDS+WDS+EBSD; £999 in the UK. TEM is not listed [O7].
   - Gatan gives away an offline DigitalMicrograph licence and time-limited "FreeAnalysis" builds [G1, G5].
7. **Format lock-in is the most documented user pain.**
   - RosettaSciIO has no reader for AZtec `.oip` or for H5OINA EDS data. A user on AZtec 6.3 asked for one in April 2026, and someone reverse-engineered legacy `.oip` in July 2026 [GH1].
   - The Bruker `.bcf` reader still has open gaps [GH2–GH5, GH14].
   - A new Velox release (3.20) broke an older HyperSpy/RosettaSciIO install [GH6].
   - GMS has written `.dm5` since 3.5.0 [G1], and RosettaSciIO cannot read it [L2].
8. **Porting hazard for v5.0.** eXSpy's X-ray line energy table has known errors of up to 9.6% (Ce Mβ 0.8154 keV against 0.9023 keV in Bearden).
   - The issue is open [GH9]. The PR that switched to xraydb was closed without merging, and the latest release is v0.3.2 (2025-03-02) [GH9].
   - Matching eXSpy number-for-number would reproduce the wrong line energies.

## 1. Product by product

### 1.1 Oxford Instruments AZtecTEM (Hitachi TEMs also use it)

**Workflow**
- SmartMap stores every spectrum per pixel at up to 4k [O1].
- Element identification uses AutoID or manual confirm. Overlays include fitted spectrum, theoretical spectrum and spectrum without pile-up correction [O2].
- From there the user picks a map type:
  - Plain window maps.
  - TruMap: peak deconvolution on the map sum spectrum, removing background and overlaps [O2].
  - QuantMap: standardless quantification on every pixel [O2].
- QuantMap settings: normalise, choose deconvolution elements, pulse pile-up correction, and sigma-level thresholding [O2].
- AutoPhaseMap then groups pixels into phases.
- Linescans can be extracted from maps (TruLine/QuantLine) [O2]. Settings can be copied to every site in a specimen [O2].
- Reporting goes to Word or Excel templates, with batch reports [O2].

**Quantification for TEM**
- "Modified Cliff-Lorimer" that takes thickness and density into account. K-factors are theoretical or user-defined, and the line series (K, L or M) is selectable [O1].
- Pulse pile-up correction (PPC), quoted up to 200,000 cps [O1].
- FLS (filtered least-squares) spectrum processing that, per the vendor, needs no background-fit tuning [O1].
- Absorption correction is automatic once mass thickness is known [O5].
- M2T thickness measurement [O4, O5]:
  - Acquire an Oxford Si₃N₄ reference with fixed beam settings.
  - Enter the reference's mass thickness and the specimen density.
  - Get specimen mass thickness and thickness in the Quant Results view.
  - The vendor's own caveats: density must be known, and FIB wedges need measurements close to the region of interest.
- Light or undetectable elements such as Li can be set "by difference": a chosen element absorbs the shortfall from 100% [O2].
  - (inference) This is the only Li handling available, and it bakes in an assumption that cannot be checked from the data.

**Phase identification**
- AutoPhaseMap works on the X-ray element maps, not on the full spectra [O3]. Defaults are Boundary Tolerance 3 and Grouping Level 2 [O2]. A search summary of the vendor page says it uses statistical measures rather than clustering or PCA (vendor claim, algorithm not disclosed; unverified).
- Demonstration (SEM, Al alloy) [O3]:
  - 60 counts per pixel, 786k pixels, seconds to compute.
  - It missed a Sr-bearing phase until the user found it in a reconstructed spectrum and added a Sr L map.
  - (inference) Clustering on maps of user-chosen elements is blind to elements nobody selected.
- Spectrum Examiner scans pixel by pixel for minor elements that are concentrated in small areas [O2].
- Match ranks spectra against a mineral database or a user library and shows the top three with a good/OK/bad colour [O2].

**Low counts:** binning factor, rolling-average or Gaussian smoothing, TruMap/QuantMap, sigma-level thresholding [O2].

**Uncertainty:** a sigma column appears for wt% (and oxide%) results [O2]. No per-pixel uncertainty map found.

**Offline and batch**
- Maps, linescans and spectra can be rebuilt from archived SmartMap data [O1].
- Batch Export appeared as beta in 6.2 [O6].
- Projects must be copied to a local drive; they cannot be opened from a share [O2].
- Northwestern runs a 50-seat network licence over VPN [O2].

**Export**
- EMSA spectra, TIFF, CSV/TSV map values, Word/Excel reports [O2].
- Data cubes as raw files [O1]; ePSIC reads the "Raw Smart Map" export into HyperSpy [E1].
- H5OINA from 6.0, an HDF5-based format with an open specification; full EDS data cubes from 6.2 [O6].
- AZtec also has a REST API, which ePSIC drives from Python [E1].

**Licence, price, platform**
- AZtecFlex: 12-month personal licence, one PC, Windows 10 64-bit only, no acquisition [O7].
- US$699 for EDS+WDS and US$1,399 for EDS+WDS+EBSD; UK £999 for EDS+WDS+EBSD [O7].
- A student price of US$139 appears in an e-store page title (unverified).
- No AZtecTEM item is sold in the e-store, so whether TEM-specific processing is included is unverified.

**Documented pain** [GH1]
- No open reader for `.oip`.
- An AZtec 6.3 STEM-EDS user found no H5OINA reader in April 2026. A HyperSpy maintainer notes H5OINA is export-only, so users must export every time.
- `.oip` was reverse-engineered in July 2026.

**Hitachi:** the ER-C HF5000 runs Oxford AZtec Energy TEM (Ultim TLE) [H1]. I found no Hitachi-made TEM EDS software (search only; unverified as a general rule).

### 1.2 Bruker ESPRIT / QUANTAX EDS for TEM

**Quantification**
- Three TEM approaches: theoretical and experimental Cliff-Lorimer, ζ-factors, and interpolation of missing ζ-factors [B1].
- Absorption correction is built into the Cliff-Lorimer quantification [B1].
- Three background models: physical for bulk, physical for thin lamellae, and a mathematical model [B1].
- ζ-factor workflow (2017 manual, §5.10–5.13) [B4]:
  - Probe current is entered in pA, or set through a system-factor calibration on Co, Mn or Cu.
  - ζ-factors start from the theoretical Cliff-Lorimer factors.
  - After measuring standards, a polynomial is fitted across the standard elements, which interpolates ζ for elements not in the standards.
- Method editor defaults: Series fit for deconvolution; PB/ZAF for bulk; φ(ρz) for light elements [B4].
- Wedge-lamella demonstration (CIGS, ZnO at 200 kV, 440 pA): ζ keeps Zn:O near 1:1 whatever the thickness; Cliff-Lorimer underestimates O in the thicker parts [B2].
- "Bayes deconvolution": a 2024 conference paper by Nissen, Eggert et al. is titled "WDS-supported Bayesian Peak Deconvolution for optimized Standardless EDS-Quantification" [B5]. Its link to ESPRIT is unverified; I saw only the metadata.

**Phase analysis**
- AutoPhase runs PCA on the HyperMap spectra with an adjustable sensitivity [B3].
- It can also be supervised: the user seeds regions, then the whole map is analysed [B3].
- It works on qualitative, quantitative and hyperspectral maps [B3].

**Low counts**
- MaximumPixelSpectrum, to catch locally enriched trace elements [B4].
- Map filters, online deconvolution maps, and element correlation scatter plots and histograms; the manual warns these need good count statistics [B4].

**Uncertainty:** the results display can show different sigma levels [B4].

**Offline and export** [B4]
- Reprocessing is possible only from `.bcf`, which is proprietary.
- `.raw` export in NIST Lispix format, for third-party software, is an optional licensed feature.
- `.rtm` saves maps only. Images go out as bmp/png/jpg/tif.
- The TEM page offers an offline option with individual or LAN access, plus scripting and API options [B1].

**Licence and platform** [B4]
- Windows (Windows 7 in the 2017 manual).
- The licence is bound to a hardware key in the QUANTAX server. Standalone data stations need a USB dongle.
- Options can be time-limited.

**Documented pain:** the `.bcf` reader is reverse-engineered and has open issues [GH2–GH5, GH14]:
- Esprit project files and per-pixel timing are not implemented.
- Live and real time are not loaded.
- M4 Tornado spectra do not match.
- A KeyError appeared in August 2026.
- A major rewrite is pending.

### 1.3 Thermo Fisher Velox (from public docs only; another agent reads the installer)

**Acquisition**
- Drift-compensated, frame-by-frame spectrum imaging. Every frame is kept; "peel back" removes frames after beam damage starts [T1].
- Independent detector channels: 4 on Super-X G2, 6 on Ultra-X. Any channel can be dropped in post-processing [T1].
- Compensation for holder shadowing at any tilt [T1].
- 4D-STEM with the Ceta camera, up to 8 live virtual detectors; multimodal STEM+EDS, STEM+EDS+EELS, and STEM+Camera+EDS [T1].
- EMPAD G2 (available from 2026-08-31): simultaneous 4D-STEM and EDX in Velox, offline 4D reprocessing with export, AutoScript scripting [T3].
- No joint diffraction+EDX analysis is described [T1, T3].

**Quantification as the user sees it** (UF Themis Z SOP, 2021) [T2]
- Map types:
  - "int" maps: plain energy-window counts, no background or deconvolution.
  - "net" maps: background removed and overlaps deconvolved, but only one line family per element.
  - Elements can be marked "deconvolution only".
- Settings:
  - Background model "Empirical" with automatic background windows.
  - Absorption correction is optional and needs thickness and/or density input.
  - Ionisation cross-section model: Brown-Powell by default; Schreiber-Wims suggested for transition metals and oxides.
  - "Use optimized spectrum fit", then Apply to SI, gives wt% and at% maps. These exist only after acquisition stops.
- The SOP warns that wt%/at% maps are unreliable with vacuum in the area or under strong channelling.
- Low counts: "pre-filtering" with an average or Gaussian kernel to improve quantification; "post-filtering" (including radial Wiener) for appearance only.

**Export, licence, platform**
- Exports PNG/JPG/8- and 16-bit TIFF/MPEG-1, plus a batch raw-to-TIFF exporter [T1]. Native `.emd` (HDF5-based) is read by RosettaSciIO [L2].
- Windows 10/11. The recommended post-processing PC has 64 GB RAM and an i7 [T1].
- The catalog page asks for a quote [T4]. Offline licence terms are not public.

**Documented pain**
- Velox 3.20 files would not load in an older HyperSpy install [GH6].
- EMD EDX spectra loaded as zeros; this turned out to be user error [GH13].

**Related Thermo products**
- Maps automates tiled STEM-EDS with Super-X/Dual-X [T6].
- ChemiPhase (SEM) [T5]:
  - Finds every statistically significant spectrum in the cube, then gives each pixel a probability of belonging to each one, with one phase per pixel.
  - Needs no prior element identification and claims a start from 10 counts per pixel.
  - It is the clearest low-count phase-ID experience on the market, but SEM only.

### 1.4 Gatan GMS (DigitalMicrograph), plus "EDAX EDS Powered by Gatan". This is the owner's lab platform.

**Ownership:** AMETEK bought Gatan from Roper (search: US$925 M). EDAX merged into Gatan on 2023-03-28 under the Gatan name [G6] (search snippets; gatan.com sits behind a bot check, so I did not open it).

**EDS hardware and software**
- Elite T detectors: 70 mm² (Super) and 160 mm² (Ultra), windowless [G2; search].
- Requires DigitalMicrograph 3.5.0 or later; the EDS licence is sold separately [G2].
- Spectra and SI maps are quantified in the "Elemental Quantification" palette [G2]. Detector geometry from the setup dialog feeds the spectrum and background model [G2].
- GMS 3.4.0 (January 2020) introduced a "New EDS Analysis": a new quantification engine, MLLS peak-family fitting, full background modelling, and faster SI mapping [G1].
- The exact quantification method is not described in the docs I read (Cliff-Lorimer and ζ options, absorption): unverified. It is in the GMS help, which the other agent covers.

**4D-STEM together with EDS**
- In STEMx the diffraction image is just another signal in the STEM SI palette [G3].
- Only one on-axis signal at a time, so EELS and CBED cannot be simultaneous [G3].
- The data is stored as a 4D DM cube; K2 IS data is captured as binary and then extracted [G3].
- eaSI allows simultaneous 4D-STEM + EDS and sequential 4D-STEM + EELS [G4].
- STEMx OIM [G4]:
  - Template matching with no scripting; each pixel gets the best match across all candidate phases.
  - Image Quality, Confidence Index and Similarity maps.
  - Orientation data exports to `.ang` for EDAX OIM Analysis.
- The joint step is masking: orientation maps can be masked by an elemental map [G4]. EDS does not enter the indexing [G4].
- (inference) The owner's `.dm4` files from eaSI should hold the 4D-STEM cube and the EDS SI as linked datasets from one scan.
- GMS 3.5.0 added the `.dm5` format [G1]. RosettaSciIO lists only `dm3`/`dm4` [L2], so any `.dm5` output has no open reader (risk to check).

**Scripting, licence, platform**
- Embedded Python, updated to 3.10 with NumPy 1.23.5 in 3.6.0 [G1].
- A free offline licence: DigitalMicrograph Offline, site ID GATAN_FREE, 64-bit Windows [G5].
- Periodic "FreeAnalysis" builds with expiry dates, e.g. 3.6.0 build 4437 expired 2024-07-31 [G1].
- Supported OS: Windows 10/11 Pro (offline) or Windows Server (IS cameras) [G1].

**Third-party DigitalMicrograph add-ons**
- HREM Research sells Watanabe's MSA plug-in (Poisson-weighted PCA of spectrum images), commercial since 2009 [G8].
- Watanabe's XUtils is free (filters, EMSA import) [G8].
- St4DeM is DigitalMicrograph-scripted multimodal acquisition (CC BY 4.0, GitHub AutoEM/St4DeM). EDS SI needs a commercial SI plug-in [N2].

### 1.5 EDAX APEX

- APEX is EDAX's SEM EDS software (Element and Octane Elect detectors). Search snippets mention an HDF5 single-file container for EDS+EBSD and "Smart Phase Mapping"; ChI-Scan is the SEM EDS+EBSD method (unverified; the product page returned 404).
- I found no "APEX for TEM" on edax.com or gatan.com. EDAX's TEM EDS is now the Elite T inside DigitalMicrograph [G2].
- RosettaSciIO reads EDAX `.spd/.spc/.lsd` [L2].

### 1.6 JEOL (JED-2300T Analysis Station; Phase Analysis 2; FEMTUS)

- **JED-2300T** [J1]:
  - Quantification with k-factors or ζ-factors.
  - "Lossless drift compensation" and storage of every spectral frame, with playback.
  - Linescans extracted from maps.
  - Results export to Word, PowerPoint or PDF.
  - Single or dual SDD; JEOL TEMs only.
- **Phase Analysis 2 (EX-36430PHA2)** [J2]:
  - Cluster phase maps from multivariate analysis of the map data, plus VCA maps with colour gradation.
  - Trace-element phase identification; area fraction for cluster phases only.
  - Listed under SEM EDS. Whether it works on TEM data is unverified.
- **FEMTUS:** all detectors synchronised (dual SDD for EDS, CEFID EELS with Dectris ELA, SAAF-Quad DPC/OBF) on a JEM-F200 [J3]. Search snippet only, unverified.
- **Formats:** RosettaSciIO reads `.pts/.asw/.map/.eds` [L2]. ePSIC keeps JEOL multi-frame EDX conversion code and a k-factor file [E3].
- **Price and platform:** not public.

### 1.7 TESCAN TENSOR and Explore (the only joint 4D-STEM + EDX product)

**Hardware**
- 100 kV FEG [X1].
- Dectris Quadro detector, up to 4,500 fps at 8-bit (2,250 at 16-bit) [X1, X5].
- Beam precession at 72 kHz [X1, X5].
- Two windowless SDDs: 1.6 sr per the flyer [X1], but "dual 100 mm², 2 sr" at ER-C [X5]. The sources disagree.

**What the user sees**
- Guided workflows in Explore with on-the-fly maps [X1, X2]:
  - Phase and orientation maps from template matching; the TESCAN team cites Rauch & Véron 2005 [X6].
  - Virtual dark-field images [X8].
  - EDX element maps.
  - Strain maps and STEM/EDX tomography [X1].

**The joint rule** [X4]
- Hooley et al. (TESCAN, MMC 2023) state that EDX information was used to "assign weights to the phases in the diffraction pattern matching algorithm".
- The test sample was Al foil with Au nanoparticles (a = 4.049 vs 4.078 Å) at 100 kV, 50 pA, 0.4° precession.
- The authors warn that enough X-ray counts are needed to avoid misidentification.
- The later application page uses 1.0 nA, 1.5 mrad, 0.8° and a 10 ms dwell, and shows Al regions no longer labelled as Au [X3].
- The exact weighting function is not public.

**Other details**
- AA2099 (θ′ / δ′ / T1): the application note sits behind a form that asks for personal details. I did not submit it.
- ExpertPI is a Python library; the flyer calls it a proprietary API [X1, X7].
- Data exports to HDF5 and is said to work with HyperSpy, LiberTEM and py4DSTEM [X1, X7].
- Price and platform: not public.

### 1.8 NanoMegas (ASTAR / TopSpin)

- ASTAR: precession electron diffraction plus template matching for phase and orientation maps; spatial resolution 1–4 nm on a FEG [N1]. Over 500 papers since 2009 (search summary).
- TopSpin: synchronised beam scanning and precession with multi-signal acquisition, and EDX/EELS improved by precession because it reduces channelling [N1].
- I found no ASTAR feature that uses EDX in indexing.
- RosettaSciIO reads `.blo` and `.app5` [L2]. Licence and platform: not public.

### 1.9 Newer entrants and pipelines

- **ePSIC at Diamond** (JEOL ARM300CF + Merlin + Oxford EDX) [E1]:
  - Simultaneous 4D-STEM + EDX is home-built: a Python GUI drives Merlin and AZtec through AZtec's REST API, with AZtec acting as scan generator.
  - 128×128 is recommended. "Internal" stop trigger needs the EDX dwell at least 1.5× the Merlin dwell. "Rising edge" adds a flyback column (the data comes out 128×127) and spike pixels.
  - 256² scans are unstable.
  - Output is two separate products: Merlin MIB files and an AZtec Raw Smart Map, both read with HyperSpy.
  - Related talk: Ryu et al., APMC 2025 [E2].
- **St4DeM** (DigitalMicrograph scripts): EDS SI on the same region as 4D-STEM [N2].
- **CEOS Panta Rhei**: Python, open source except device drivers, Windows and Linux. Covers EELS, EFTEM, 4D-STEM and SI; EDX is not mentioned [N3]. RosettaSciIO reads its `.prz` files [L2].
- **Direct Electron:** patent US11310438B2 infers elemental composition from the slope of the bright-field disk edge in 4D-STEM, with no EDS [N4].
- **DECTRIS:** the ARINA detector is supported in Velox (search). DECTRIS CLOUD for EM launched at M&M 2025 for 4D-STEM; no EDX feature found [N5].
- **Quantum Detectors:** Merlin plus a scan engine. Their Xspress readout is for synchrotron XRF; no EM EDX product [N6].
- **Thermo EMPAD G2 and Maps:** see §1.3.

## 2. Open tools and documented complaints

**HyperSpy / eXSpy (GPL)**
- Cliff-Lorimer, ζ and cross-section quantification; iterative absorption correction; returns mass thickness [L1: `_eds_tem.py:297,303,377,494`].
- Poisson-normalised decomposition, citing Keenan & Kotula [L1: `:631–633,740`].
- No uncertainty in quantification output [L1: `utils/eds/_quantification.py`, no variance or sigma terms].
- Open gaps:
  - Line database errors [GH9].
  - Missing U M lines [GH12].
  - No SEM ZAF [GH11].
  - No thickness from EDS; one user still relies on an old STRATAGem program [GH10].
  - Live/real-time metadata is inconsistent across formats [GH7], which matters for ζ.
  - k-factor units confuse users [GH8].

**RosettaSciIO** [L2, GH1]
- Reads: bcf/spx, emd, dm3/dm4, pts, spd/spc, rpl, msa, mib, blo, app5, prz.
- Does not read: `.oip`, H5OINA EDS, `.dm5`.

**Other tools**
- NIST DTSA-II: public domain, Windows/macOS/Linux. Gives each concentration an uncertainty budget (counting statistics plus systematic Z and A terms) and has a thin-film algorithm [P6].
- NeXL: Julia, Unlicense, under 1 ms per spectrum filter-fit, with an uncertainty package [P7].
- Sandia AXSIA: MCR-ALS spectral image analysis [P8].

**Forums**
- I searched Reddit r/electronmicroscopy, the microscopy listserv and ResearchGate and found no retrievable threads; ResearchGate returned 403.
- The documented pain therefore comes from GitHub issues and the literature:
  - Newbury 1998: standardless analysis puts 95% of results within ±50% relative (first-principles) or ±25% (fitted standards), against ±5% with standards [P1].
  - Conconi et al. 2025: k-factor sets are specific to one microscope plus EDS system [P2].
  - Xu & LeBeau 2017: specimen and holder geometry adds uncertainty; symmetric multi-detector arrays reduce it [P3].
  - Hu 2021 (NUANCE): calculated k-factors for L and M lines are good only to ±10–20% [P4].
  - Aughterson, Zaluzec & Lumpkin 2025: precision below 1% is achievable; channelling biases results; amorphisation is a remedy [P5].

## 3. Feature baseline matrix

Legend:
- **Y** = documented
- **P** = partial or claimed
- **N** = not offered, or none found in the docs I read
- **?** = not found publicly (unverified)
- **3p** = third-party plug-in
- **AS** = JEOL Analysis Station

Hitachi uses AZtec. EDAX TEM EDS lives inside GMS.

| Feature | AZtecTEM | ESPRIT-TEM | Velox | GMS + EDAX | JEOL AS | TESCAN Explore | NanoMegas | eXSpy | DTSA-II / NeXL |
|---|---|---|---|---|---|---|---|---|---|
| 4D-STEM + EDX co-acquisition | N (home-built via REST [E1]) | N | Y [T1, T3] | Y eaSI [G4] | P FEMTUS [J3] | Y [X1] | P TopSpin [N1] | n/a | n/a |
| Joint diffraction+EDX algorithm | N | N | N | P mask by EDS map [G4] | N | Y EDX-weighted matching [X4] | N | N | N |
| Theoretical k / cross-sections | Y | Y | Y Brown-Powell / Schreiber-Wims | Y? (method unverified) | Y | ? | n/a | user-supplied k; cross-section | Y (bulk) |
| ζ-factor | P M2T single standard | Y + polynomial interpolation | ? | ? | Y | ? | n/a | Y | P thin-film |
| Thin-film absorption correction | Y auto | Y | Y (thickness + density input) | ? | ? | ? | n/a | Y iterative | Y (bulk) |
| Thickness from EDX | Y M2T | Y via ζ | ? | ? | ? | ? | n/a | Y mass thickness | P |
| Overlap model fitting | Y FLS | Y series fit (Bayes?) | Y optimised fit | Y MLLS | ? | ? | n/a | Y Gaussian + polynomial | Y filter-fit |
| Per-pixel quant maps | Y QuantMap | Y | Y wt/at% | Y | Y? | ? | n/a | Y | P |
| EDX-only phase / cluster | Y AutoPhaseMap (on maps) | Y AutoPhase (PCA) | N | 3p HREM MSA | P (SEM product) | n/a | n/a | P decomposition | N |
| Poisson-weighted decomposition | ? | ? | N | 3p | ? | ? | n/a | Y | N |
| Low-count aids | bin, smooth, σ-threshold | max-pixel spectrum, filters | pre-filter | ? | frame playback | "needs counts" caveat | n/a | binning | n/a |
| Uncertainty per result | Y σ (wt%) | Y σ | ? | ? | ? | ? | ? | N | Y budgets |
| Per-pixel uncertainty map | N | N | N | N | N | N | N | N | N |
| Per-detector channels / shadowing | ? | ? | Y | ? | dual SDD | 2 SDD | n/a | N | N |
| Time-resolved frames | ? | ? | Y peel-back | ? | Y | ? | n/a | N | N |
| Offline licence | AZtecFlex $699–1,399/yr | dongle / LAN | ? (quote) | free offline DM | ? | ? | ? | free (GPL) | free |
| Open export of full cube | raw/rpl, H5OINA, EMSA | .raw (licensed option), .bcf closed | .emd | .dm4 (.dm5 not readable) | .pts | HDF5 | .blo/.app5 | Y | Y |
| Scripting | REST API | API | AutoScript | Python 3.10 | ? | ExpertPI (proprietary) | ? | Python | Java / Julia |
| macOS | N | N | N | N | ? | ? | ? | Y | Y |
| Algorithm inspectable | N | N | N | N | N | N | N | Y | Y |

## 4. Clear gaps

1. **No open, inspectable joint 4D-STEM + EDX analysis exists.**
   - TESCAN's rule is proprietary and works only on TENSOR.
   - On the owner's platform, Gatan co-acquires the two signals but its joint step is a mask; neither signal informs the other.
   - Velox, JEOL and ePSIC only co-acquire.
2. **Nothing models the 4D-STEM count regime.**
   - Vendors smooth or bin, and TESCAN's demonstration used a 10 ms dwell at 1 nA.
   - No product pools spectra over objects defined by diffraction (grain, phase or precipitate), and none reports a Poisson likelihood or posterior per pixel (approaches E/F/G remain open).
3. **No per-pixel or per-object uncertainty.** That makes "is this T1 or θ′?" unanswerable with any stated confidence.
4. **What EDX cannot see is hidden, not flagged.**
   - Li is handled by assumption ("element by difference", or normalisation).
   - No tool uses diffraction to supply information about invisible elements or to flag the T1-versus-θ′ ambiguity.
   - Signal projected through the matrix is not modelled anywhere.
5. **Lock-in and fragility.**
   - Proprietary or export-only formats (`.oip`, `.bcf`, `.dm5`, H5OINA-only EDS).
   - Version breakage (Velox 3.20).
   - Live-time and dose metadata are inconsistent, which breaks ζ quantification.
6. **Windows, dongles and subscriptions everywhere**; prices are hidden except AZtecFlex.
7. **The open reference itself has data errors** (eXSpy line energies), and the vendors' k-factors are instrument-specific black boxes.

## 5. What a macOS-native open tool could own (all inference)

- **The joint layer, done openly.** Read the owner's GMS eaSI `.dm4` (linked 4D-STEM and EDS SI) natively, plus Velox `.emd`, `.bcf`, `.pts`, AZtec raw/rpl and H5OINA.
  - An H5OINA EDS reader is a concrete gap that RosettaSciIO users are asking for in 2026.
- **Count-honest chemistry for each diffraction-defined object (approach E as default).** Pool spectra over each grain or precipitate mask that mac4DSTEM already produces, then report composition with Poisson uncertainty and a counts-per-object figure.
  - Offer TESCAN-style EDX weighting of phases (approach B) only behind a minimum-count gate.
- **Uncertainty as a first-class output,** per object and per pixel. No vendor does this.
- **Explicit limits labelling:** Li not detectable; T1 and θ′ share the same Cu:Al ratio; thin precipitates are projected through matrix. In line with the repo's rule that unvalidated results stay labelled, results should carry that label until they pass on a dataset with known truth.
- **Validated port, not a blind one.** Match eXSpy number-for-number where eXSpy is right, and record a `DEVIATION` note where its line database is wrong (Bearden / xraydb; check the xraydb licence, unverified).
- **Free, no dongle, Apple Silicon/Metal speed for offline reanalysis on a laptop,** with mac4DSTEM's replay record as provenance.
- **Do not compete on:** acquisition and hardware synchronisation (vendor-owned), SEM bulk ZAF or standardless quantification, or mineral databases.

## Source index

Local paths: `M2/` = `.../scratchpad/edx/market2/` and `GMS/` = `.../scratchpad/edx/gms/` (full prefix in the first section).

**Oxford Instruments**
- O1: https://nano.oxinst.com/products/aztec/aztectem
- O2: Northwestern NUANCE "AZtec Post-Processing Manual" (last modified 05/2026), https://nuance.northwestern.edu/documents/epic/aztec_post_processing_manual.pdf — local `M2/aztec_post_processing_manual_northwestern.pdf`, `M2/aztec_pp.txt`
- O3: Oxford "AutoPhaseMap 1" application note (OINA/AZtecEnergy/APM/AN001/Jan2013) — local `M2/oxinst_autophasemap_al_alloy.pdf`, `M2/apm_al.txt`
- O4: https://nano.oxinst.com/library/blog/m2t-more-thanjust-tem-quantification
- O5: AZtecTEM–Ultim Max brochure, https://nano.oxinst.com/assets/uploads/products/nanoanalysis/documents/Brochures/AZtecTEM%20-%20Ultim%20Max.pdf — local `M2/oxinst_aztectem_ultimmax_brochure.pdf`
- O6: https://www.oxinst.com/blogs/aztec-live-6.2
- O7: https://nano.oxinst.com/aztecflex; https://estore.oxinst.com/us/zidAZTECFLEX-0001; https://estore.oxinst.com/us/software/; https://estore.oxinst.com/uk/zidAZTECFLEX-0002

**Bruker**
- B1: https://www.bruker.com/en/products-and-solutions/elemental-analyzers/eds-wds-ebsd-SEM-Micro-XRF/quantax-eds-for-tem.html
- B2: …/quantax-eds-for-tem/element-quantification-stem-sample-varying-thickness.html
- B3: …/quantax-eds-for-tem/chemical-phase-analysis-of-a-layered-structure.html
- B4: QUANTAX EDS User Manual DOC-M82-EXX066 V2 (2017), https://www.dartmouth.edu/emlab/docs/quantax_eds_user_manual.pdf — local `M2/bruker_quantax_eds_user_manual_dartmouth.pdf`, `M2/quantax_manual.txt`
- B5: Nissen, Eggert, Berger, Gernert, BIO Web Conf 129 (2024) 06035, doi:10.1051/bioconf/202412906035 (metadata only)

**Thermo Fisher**
- T1: Velox datasheet DS0251-EN-01-2025, https://documents.thermofisher.com/TFS-Assets/MSD/Datasheets/velox-datasheet.pdf — local `M2/velox_datasheet.pdf`
- T2: UF Themis Z STEM-EDS SOP (Rudawski, 06/14/21), https://rsc2.aux.eng.ufl.edu/_files/documents/5740.pdf — local `M2/ufl_5740.pdf`
- T3: EMPAD G2 datasheet, https://documents.thermofisher.com/TFS-Assets/MSD/Datasheets/empad-g2-datasheet-en.pdf — local `M2/tfs_empad_g2_datasheet.pdf`
- T4: https://www.thermofisher.com/order/catalog/product/VELOX
- T5: ChemiPhase AN0227, https://assets.thermofisher.com/TFS-Assets/MSD/Application-Notes/distinguishing-unique-components-composites-an0227-en.pdf — local `M2/tfs_an0227.pdf`
- T6: https://www.thermofisher.com/ru/en/home/electron-microscopy/products/software-em-3d-vis/maps-software.html (search summary)

**Gatan / EDAX**
- G1: `GMS/ReleaseNotes.txt` (GMS 3.6.1 installer)
- G2: `GMS/Documentation/User Guides/1070.82001_REV02_Elite T User Manual.pdf` (text in `M2/elite_t_manual.txt`)
- G3: `GMS/Documentation/User Guides/1020.40004_V002_STEMx System User Manual.pdf` (text in `M2/stemx_manual.txt`)
- G4: S. Gorji (Gatan), "4D-STEM Unveiled", https://warwick.ac.uk/research/rtp/em/info/facility_open_day/saleh-gorji-gatan-4dstem-unveiled-capturing-diffraction-at-every-pixel.pdf — local `GMS/web/gorji-warwick.pdf`
- G5: `GMS/siviewer/Installation Instructions for Free GMS Software.pdf`
- G6: https://www.gatan.com/node/5022 (search snippet only; site behind a bot check)
- G8: https://www.lehigh.edu/~maw3/research/msamain.html and https://www.lehigh.edu/~maw3/research/xutilmain.html

**JEOL and Hitachi**
- J1: https://www.jeolusa.com/PRODUCTS/Elemental-Analysis/SDD-EDS-for-STEM
- J2: https://www.jeolusa.com/PRODUCTS/Elemental-Analysis/Embedded-EDS-for-SEM/Phase-Analysis-2
- J3: MRS Fall 2024 abstract 4151113 (search snippet only)
- H1: https://er-c.org/index.php/facilities-2/hitachi-hf-5000/ (search snippet)

**TESCAN**
- X1: TENSOR product flyer (09/04/2026), https://tescan.com/hubfs/Tescan-TENSOR_PF_26-04-09-print.pdf — local `M2/tescan_tensor_pf_2026.pdf`
- X2: https://tescan.com/applications/materials-science/analytical-stem-and-4d-stem-characterization
- X3: …/4d-stem-edx-phase-mapping
- X4: Hooley et al., MMC 2023, https://www.mmc-series.org.uk/abstract/1020-adding-another-dimension-to-4d-stem-with-edx-assisted-crystal-orientation-and-phase-mapping.html
- X5: https://er-c.org/index.php/facilities-2/material-science/tescan-tensor/
- X6: Clarke et al., Acta Cryst A80 e238 (2024) — local `M2/iucr_a63917.pdf`
- X7: …/open-api-custom-4d-stem-workflows
- X8: https://tescan.com/applications/semiconductors/package-metrology/phase-mapping-orientation-analysis-pcm

**NanoMegas, ePSIC and other entrants**
- N1: https://nanomegas.com/tem-orientation-imaging/ and https://nanomegas.com/all-in-one-topspin-platform-for-precession-advanced-analytical/
- E1: ePSIC 4DSTEM-EDX Manual (2025-11-06), https://github.com/ePSIC-DLS/User-Notebooks (`ePSIC_Standard_Notebooks/20251106_4DSTEM-EDX_Manual.pdf`) — local `M2/epsic_4dstem_edx_manual_20251106.pdf`
- E2: https://apmc-2025.m.asnevents.com.au/schedule/session/24402/abstract/114394
- E3: ePSIC-DLS/User-Notebooks file listing (via `gh api`)
- N2: arXiv:2504.19762 (St4DeM)
- N3: https://ceos-gmbh.de/en/produkte/ceos-panta-rhei
- N4: https://patents.google.com/patent/US11310438
- N5: https://dlab.dectris.com/article/dectris-cloud-for-electron-microscopy-to-launch-at-m-m (search)
- N6: https://quantumdetectors.com/our-products/

**GitHub issues**
- GH1: hyperspy/rosettasciio#97
- GH2: rosettasciio#17
- GH3: rosettasciio#239
- GH4: rosettasciio#516
- GH5: rosettasciio#541
- GH6: rosettasciio#484
- GH7: hyperspy#2534
- GH8: hyperspy#1850
- GH9: hyperspy/exspy#100 and PR #126 (closed, not merged)
- GH10: exspy#112
- GH11: exspy#116 and #117
- GH12: exspy#170
- GH13: hyperspy#2899
- GH14: rosettasciio#343

**Local code**
- L1: `.../scratchpad/edx/exspy/exspy/signals/_eds_tem.py` and `.../exspy/exspy/utils/eds/_quantification.py`
- L2: `.../scratchpad/edx/rsciio/rsciio/*/specifications.yaml`

**Literature**
- P1: Newbury 1998, Microsc. Microanal. 4 (https://www.nist.gov/node/760856)
- P2: Conconi et al. 2025, Ultramicroscopy 276:114201
- P3: Xu & LeBeau, arXiv:1708.04565
- P4: X. Hu, NUANCE tech talk 2021-10-21 — local `M2/northwestern_xiaobing_techtalk_2021.pdf`
- P5: Aughterson, Zaluzec & Lumpkin, APMC 2025 (https://apo.ansto.gov.au/handle/10238/16390)
- P6: NIST DTSA-II (NIST pages via search; platform list at https://www.lehigh.edu/~maw3/link/mssoft/spctsim.html)
- P7: NeXLSpectrum.jl (catalog.data.gov)
- P8: Sandia AXSIA publications