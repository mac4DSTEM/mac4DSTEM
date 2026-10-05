# Second opinion on the two Fable EDX analyses (inputs and methods), 2026-10-05

## 0. How I checked

- **Keep-awake.** The two caffeinate holders (pid 4914 and pid 7722) are still active. `pmset -g assertions` shows `PreventUserIdleSystemSleep 1`.
- **Nothing written to the repo.** The repo is at `85920f91` with a clean tree.
- **New scratch files** are in `$S/critic2/`, where `$S` = `<scratch>/edx`:
  - `velox_owner_checks.py` and `velox_owner_checks-2026-10-05.log`: header and small-slice reads of 4 owner Velox files. Nothing larger than one 2048² frame or a 16 KB spectrum was read.
  - `ml_converge.py` / `ml_converge-2026-10-05.log`, `ml_irls.py` / `ml_irls-2026-10-05.log`, `absorb.py` / `absorb-2026-10-05.log`.
- **Repo files read:**
  - `DM4Reader.swift:704-830`
  - `H5Reader.swift:81,238-240,255-372,540-565,1125-1150`
  - `AppState+Open.swift:241-248`
  - `AppState.swift:1169`
  - `PhaseVectorMatching.swift:332-362`
  - `ResidentCube.swift:180-194`
  - `FourDArray.swift:408`
  - `Crystal.swift:267-285`
  - `ROADMAP.md:78-80,134-140`
  - `docs/status.md:31`
- **rsciio (`049e7d7`) lines checked:** `_emd_velox.py:145-155,325-340,354,633-646,874-876` and `utils/hdf5.py:170-173`. HyperSpy `_mva.py:1604-1680`, and exspy `material/xray_lines.json`.

## 1. Corrections of fact (verified unless marked)

| # | Claim (who) | Finding | Evidence |
|---|---|---|---|
| C1 | Velox frames drift; the app must re-measure per-frame shifts from the HAADF stack and shift events (Inputs §1, §4). Unverified whether shifts are stored (Inputs §11.2). | **Velox corrects drift during acquisition by moving the scan, and stores the shifts.** Per-frame metadata columns carry `CustomProperties.Scan.ScanTransformation.A13/A23`. They are 0 at frame 0 and drift smoothly after that: 1606 reaches A13 −0.0041; 1122 reaches A23 +0.0066. Meanwhile the stored HAADF frames register to [0,0] in all 30 sampled frames of 3 SIs (1122, 1606, 1610). That check used 4×-binned px against the mean, so its resolution is about ±2 raw px, and the reference includes each frame. Direct frame 0 vs frame j tests also gave 0, except one (−3, 0) outlier at frame 1 of 1122. The manual says compensation keeps "the location on the specimen that corresponds to a recorded pixel … the same in each acquired frame" (velox/txt/Velox 3.15 User Manual.txt:7280-7281). Units of A13/A23 are unverified (probably a fraction of the scan field). | `critic2/velox_owner_checks-2026-10-05.log` |
| C2 | "82–100 % of events sit within ±150 eV of 0" is used as a design figure (Inputs §4). | **That fraction belongs to the public test files.** In the owner's files the zero peak is 2.00 % (1122), 3.04 % (1606) and 6.23 % (1610). This is the "a threshold is a property of the dataset" rule again. | same log |
| C3 | A joint scan gives "order 10² counts/px" (Methods §0, ownerdata §7). The brief says 0–10. | **Neither is right. My estimate is about 30–85 counts/px at the owner's 4D conditions.** The basis is the optics of Velox `STEM HAADF 1841` (10 min before cube 051, same stage and α −16.87°) compared with EDX SI 1122:<br>• 4D-side image (1841): C2 70 µm, 2.1 mrad, spot 7, ProbeMode 2, ScreenCurrent 0.26 nA.<br>• EDX SI 1122: C2 100 µm, 15 mrad, spot 5, ProbeMode 1, 1.78 nA.<br>The EDX runs at 48–60 % dead time: Live/Real 763.6/1463.0 s in 1122 and 71.9/181.0 s in 1606; input/output 23.4k/12.3k cps.<br>Scaling the input rate by current (×0.146) through the dead time fitted on 1122 gives about 3.0 kcps out, so about 30 (10 ms) to 60 (20 ms) counts/px. Using ownerdata's measured/rate ratio (13.1 vs 9.3) gives up to about 85.<br>Methods' ×13–27 dwell scaling ignores both the ~7× lower current and the dead time. Caveats, all unverified: ScreenCurrent ≈ probe current; 051 used the 18:41 optics; no holder shadowing at α −16.9° (that would lower the estimate). | same log; `ownerdata/emd_scan.jsonl` |
| C4 | "LS vs Poisson-ML on FePt: Pt Lα 14921 vs 15511 (4 %)", tagged [verified] (Methods §0, §1.1). | **15511 is an unconverged Nelder–Mead value.** The same optimizer started from the LS solution gives 15229.7. L-BFGS-B does not move; Powell returns NaN. Converged IRLS (8 iterations, NLL −300277.25, below LS −300250.47 and NM −300267.70) gives **Pt Lα 15351.6 and Fe Kα 2809.3: a 2.9 % gap, not 4 %**. HyperSpy's ML-poisson output depends on the optimizer and starting point, so it cannot be a parity pin. | `critic2/ml_converge-2026-10-05.log`, `critic2/ml_irls-2026-10-05.log` |
| C5 | The exspy line table has errors up to 9.6 %, so a second science table is needed (Methods M1). | **For the owner's lines, exspy agrees with Bearden to ≤ 0.022 %**: Mg/Al/Si/Cu Kα, O Kα and Cu Lα identical to 4 decimals, Zr Lα 2.0423. My reference values are from memory, unverified. The Ce Mβ error does not touch v5.0's system. Li is present in the table as an empty entry, with metadata "Am, Li, Np and Pu lines are missing". | `$S/exspy/exspy/material/xray_lines.json` |
| C6 | B* shows "for every candidate phase p the diffraction evidence … all existing" (Methods §2.1). | **Not existing.** `PhaseVectorResult` keeps the winner plus one runner-up phase only. Its `score` is "Mean \|u − v\| … Å⁻¹", a distance, not a likelihood. Per-phase best scores need a new, additive Core output. | `PhaseVectorMatching.swift:332-362` |
| C7 | "E works on his existing data for end-on needles at ~30 %"; stage (2) "cross-session registration on the 190330 pair" (Methods §2.0, §3). | **No existing EDX SI overlaps a 4D field.** The 190330 SIs are about 18 µm and 24° of tilt away. The matching 18:41 Velox file is HAADF-only. E needs a new acquisition, and stage (2) cannot run on existing data. | ownerdata §5; `emd_scan.jsonl` ("STEM HAADF 1841": Image only) |
| C8 | Velox probe current in metadata: unverified (Methods §5). | **Present per frame as `Optics.ScreenCurrent`** (1606: 2.229 → 2.242 nA across frames). It is a screen reading, and its calibration as probe current is unverified. GMS cubes 051 and 060 record `Probe Current (nA) "0.0"`. | log; `ownerdata/dm_scan.jsonl` |
| C9 | Refuse absorption correction on the owner's summed Super-X G1 stream (Methods §1.1). | **That leaves a systematic Si bias of about 9–15 %.** With exspy's own FFAST MACs, Al absorbs Si Kα at 3301.6 cm²/g and Mg Kα at 592.9. At 100 nm the factor x/(1−e^−x) is 1.09–1.15 for Si Kα (TOA 30–18°) against 1.02 for Mg Kα. The Mg:Si ratio is the quantity of interest. | `critic2/absorb-2026-10-05.log` |
| C10 | "Li has no line in any table" (Methods §0). | Velox's `EdgeEnergies_v1.csv` lists Li K-L3 at 54 eV (velox report, UI unverified). The correct statement is "no line in exspy/espm". | velox report §1 |
| C11 | "Three repo defects in shipped opening" (Inputs §0.5). | **Only one is a plausible defect, and it is unreproduced.**<br>• **Velox `.emd`:** `makeReader` routes it to H5Reader (`AppState+Open.swift:241-248`). Candidate sort prefers the lowercase `/data` suffix, which Velox's `/Data` misses. A rank-3 `/Data/Image/<uuid>/Data` is then promoted `[1,N,Qy,Qx]` (`H5Reader.swift:323-372,558-560`). `datacubeRejection` rejects only `_labels_`/legacy/RGBA (`:1132-1143`). Strongly supported by the code, but not observed. Reproduce on the public `velox_emd_version11` file before calling it a defect (CLAUDE.md: "defects whose mechanism a reproducing observation already proves").<br>• **DM 3D SI:** guarded twice, by the scan-shape tags *and* the exact blob-size check (`DM4Reader.swift:772-781`). It is not "only by accident".<br>• **Missing eV in `axisDomain`:** not a defect today. | repo lines cited |
| C12 | Velox images are "(width, height, frame)" (ownerdata §4). | Doubtful. In 1122 the dataset is (2048, 682, 120) and ScanArea gives x-extent 0.333×2048 = 682, y 0–1. So it is (y, x, frame), which is also how rsciio reads it (`_emd_velox.py:335,354`). This matters for registration handedness. | log; rsciio |
| C13 | HyperSpy Poisson scaling at `_mva.py:1648-1652` (Methods). | The content is right; the code is at `:1654-1680`. | venv hyperspy |
| C14 | Pooled CL error 0.1–1.7 wt % (Methods) vs 0.1–0.7 (validation). | **Methods is right**: 54.82/55.79/53.24/54.62/53.81/54.14 against 54.1. Each row is one realization with k = 1 by construction, so it checks arithmetic, not an error distribution. | `$S/lowcount-2026-10-05.log` |
| C15 | "Risk medium only because no fixture exists until the owner records one" (Inputs §3). | The validation report lists ePSIC YAlO₃ `EDS Spectrum Image.dm4` (Zenodo 10609594, 39.5 MB) as a dm4 EDS SI, which contradicts formats' "no public GMS EDS SI". Not downloaded by me; contents unverified. | validation §3 |
| C16 | Currie L_C ≈ 2.33σ_B, L_D ≈ 2.71 + 4.65σ_B (Methods §1.2). | These are the paired-blank constants with background scale s = 1. With exspy's window scale s, σ₀² = sB + s²B, so use L_C = z·σ₀. Below about 20 counts, use exact Poisson critical values. | standard Currie derivation (from memory) |

## 2. Fable "Input paths"

**Agreements**

- **M2 (two signals plus a registration record).** It is the right model. M1 cannot hold different grids, and M3 bakes registration in at import.
- **Sparse decode of the Velox stream** with shape taken from ScanSize × ScanArea, UInt32 accumulation, a per-pixel frame count, content-based Velox detection, and no dense decode.
- **Registering against the 4D source grid** and composing with `LoadView` and `DataCubeDerivation` at the point of use.
- **The sidecar plan:** a child group, rank-1 spectra only, lineage-only kinds.
- **A combined residency budget.** Today `shouldAdmit` checks only `maximumBufferLength`, not RAM (`ResidentCube.swift:185-187`).
- **The memory arithmetic** checks out: CSR ≈ 0.24 GB, dense 26.5 GB, 1.07/1.78 GB on the 256²/330² grids.

**Disagreements**

1. **Intra-file frame alignment (`FrameAlignment`, HAADF re-correlation, parity vs science shifts).** Drop it; see C1.
   - Velox already applied the shifts. Re-correlating would at best measure the residual. A naive implementation that reads the drift trajectory as shifts still to apply would double-correct.
   - Replace it with:
     - reading A13/A23 per frame as provenance and a drift diagnostic;
     - an optional residual check (frame-to-mean correlation) shown as a number.
   - This also removes an item from Inputs' list of things to settle first.
   - **Strongest counter-argument:** files acquired with drift compensation off. Read the flag if one exists (not found yet), or show the A13/A23 trajectory and the residual check together.
2. **Where pooling happens.** Pooling should not go through a dense spectrum cube on the 4D grid.
   - For E, move the pool *masks* onto the spectrum's native grid (inverse transform, area-majority) and sum integer events there. That keeps exact Poisson counts and needs no 1.8 GB cube.
   - Resampling counts onto the 4D grid is right only when the spectrum grid is finer. For per-pixel joint methods (D, G), resample toward the coarser grid.
   - The owner's Velox pixels are 0.75–4 nm, while the 4D grid is 1.5–10 nm.
3. **Velox↔GMS refinement through a virtual ADF from the cube is weak.**
   - At CL 77 mm on a 256²-binned GIF detector, a virtual "ADF" will probably not reach HAADF angles (47–200 mrad in the owner's Velox metadata).
   - Mg, Al and Si are adjacent in Z, so the needles have little Z-contrast in either image.
   - Better: register the Velox HAADF to the GMS **SI survey ADF** (2048², a real detector), then chain through the `Spectrum Image Rect` tag to the cube grid. That tag is verified in the owner's files.
4. **The registration kinds omit reflections.** identity, integerBin, similarity and affine all assume known handedness. DigiScan and the Velox scan engine are different scan generators, and the repo has a history with mirroring ("Mirrored Yes", ACOM +π). The record should say det < 0 is allowed, and metadata seeding should test both handednesses.
5. **"Identity proven by tags" proves only that the grids are the same, not that the pixels were taken at the same time.** EDS and camera pixel streams can be offset (formats §2.1). ePSIC's synchronous set-up shows flyback columns and spike pixels. Identity should also be checked by correlating the X-ray total map with a virtual image at sub-pixel precision.
6. **M2′ (a window with only a spectrum image, no cube) cannot wait for a later slot.**
   - Every EDX file the owner has is a plain spectrum image.
   - Methods' stage 1 ("plain EDX on the owner's Velox files") needs that window.
   - "Attach" today means opening a 1–29 GB cube first just to look at a spectrum.
   - The window structure belongs in the room mock now. ADR 035 makes frozen-shell decisions expensive to revisit.
7. **The GMS same-file path is speculative for this lab.**
   - Super-X under GMS needs a second Esprit install, an `ExternControl` licence, IO-card firmware and a DDC swap (GMS report, EDSIG:724-869).
   - The likely real path is **sequential**: GMS 4D, then a Velox SI at the same field and tilt. That makes cross-file registration the main path, which Inputs' design handles.
   - Overlooked: a Velox-native 4D + EDS path, with a Ceta MRC2014 stack (FEI1/FEI2 header, raster/serpentine flag) beside a single-frame `.emd` SI. The repo has no MRC reader. The owner's files list `BM-Ceta`, but whether it is a speed-enhanced Ceta-2 with a 4D licence is unverified.
8. **Fingerprinting a 7–29 GB file.** Hashing the stream bytes during the one-pass decode costs almost nothing, versus a separate streamed hash. That partly dissolves the owner decision in Inputs §11.6.

**Order of work.** Mostly agree. Two changes:

- Move the room mock (including a spectrum-only window) before the types, because it gates frozen-file edits.
- Reproduce before step (1); see C11.

## 3. Fable "Methods"

**Agreements**

- Pooling is the estimator; per-pixel numbers are for display only.
- Statistics as a Swift-native layer, with counting and k terms reported separately.
- Refuse the vacuum mask and the single-line "100 %" defaults, and show them instead.
- **The diffraction-defined matrix pool as an empirical blank.** This is the strongest idea in either analysis. Besides the Al Kα tail, it absorbs the Si-detector internal-fluorescence peak (not mentioned anywhere), which sits right on Si Kα.
- The indistinguishability check as a standing refusal.
- B* as a table only, with no combined posterior.
- G, F and the CNN deferred.
- I (channelling angle) and H (masking).

**Disagreements**

1. **"Two named modes, the user sees which mode produced a number."** As a user-facing switch, this goes against repo practice. The repo has 69 `DEVIATION` notes and no user-visible py4DSTEM-parity toggle (grep of `mac4DSTEM/UI`), and it goes against the owner's "no filler" rule.
   - Better: Core functions take explicit parameters (loss, background, thresholds). The parity harness calls them with exspy's values; the app uses one science default with inline DEVIATIONs; provenance names the estimator.
   - **Strongest counter-argument:** users comparing against exspy notebooks. A provenance line covers that.
2. **M3 (loss function).** Choose Poisson-ML, but implement it as IRLS or multiplicative EM on the fixed design. Pin parity on LS only (C4). An ML parity pin against HyperSpy is unusable.
3. **Absorption refusal on the summed stream** (C9). Velox metadata carries per-detector azimuth, elevation and stage α/β. A tilt-dependent four-quadrant geometric average is computable from a summed stream; summing hides only the per-quadrant *shadowing*. Ship the corrected value, badged, with the per-quadrant TOA spread and thickness σ propagated. Refuse only when tilt or holder geometry is unknown.
4. **Theoretical k-factors "out of v5.0".**
   - The owner has no standards and only placeholder k-factors (ownerdata §4d). As written, S1 yields no at% on any of his data.
   - Make the primary v5.0 outputs **free of k-factors**: net counts, Mg/Si count ratios, enrichment over the matrix blank, all with intervals.
   - Allow a typed k with its source shown, for example read from Velox's settings or log.
   - Decide theoretical k separately. EPQ ships Bote-Salvat data under a public-domain notice (validation §2; third-party rights inside EPQ unverified).
   - This is a missing owner decision (M9 below).
5. **E as specified.**
   - It cannot run on existing data (C7).
   - **Per-object pooling on sequential pairs is limited by registration.** Needles are about 4 nm against 1.5–10 nm 4D pixels. In-session Velox drift alone reaches A23 ≈ 0.0066 of the field over 24 min in 1122; at 0.77 µm FOV that is about 5 nm, with units unverified. Eroding by a residual of that size deletes the object.
   - Per-object E should run only on simultaneous data or when the measured residual is below the object half-width. Otherwise pool per phase or region.
   - The projection model f = h/t ignores beam broadening, which validation estimates at about 4 nm in 100 nm Al, comparable to needle width. f must come from a footprint ⊗ broadening forward model.
   - Pools inherit their source's badge. Phase mapping is unvalidated (CLAUDE.md), so phase-verdict pools are too.
   - Sequential order matters for physics: a 4D scan at 10–20 ms dose and contamination comes before the EDX.
6. **B*'s scientific reach is narrower than presented.**
   - The built-in β″ is Mg₅Si₆ (`Crystal.swift:267-285`, Andersen 1998). Later structure models (Mg₅Al₂Si₄, Mg₄Al₃Si₄; from memory, unverified) differ.
   - Al in a thin needle cannot be measured through an Al matrix.
   - k uncertainty is about 20 %.
   - So β″, U2 and B′ are probably inseparable by EDX; β′ (Mg:Si ≈ 1.8) and Q (Cu) probably separable.
   - Before building B*, compute a **separability matrix** from the CIFs with k ± σ and stoichiometry-model spread. Without that, "EDX arbitrates" could relabel real β″ needles. B* also needs per-phase score retention (C6), and its score is a distance.
7. **D at C3's counts.** At 30–85 counts/px, binned 2×2, the EDX block is not pure noise. D's case is somewhat better than Methods assumes; keep the exploratory badge.
8. **Coverage test.** Exact Garwood intervals over-cover discrete Poisson by construction. Require a band (for example 68–80 % nominal-68), not "about 68 %". Otherwise a correct implementation fails, or a too-wide one passes.
9. **On-zone tilt.** End-on needles are imaged on-zone, so joint EDX is channelled by design. I's angle will flag most pools. The matrix-relative quantities partly cancel this, but not exactly, because the precipitate structure differs from the matrix.

## 4. Where the two analyses contradict each other

- Methods' stage 1 needs plain-SI windows (M2′); Inputs defers M2′ to a later slot that is "the owner's call".
- Methods treats registration as solved by the record. Inputs' refinement path (virtual ADF) is the weak link (§2, item 3).
- Inputs designs intra-file alignment. Methods assumes Velox frames are usable for a first-vs-last check. C1 settles it in Methods' favour.

## 5. Repo-rule lens

- **Frozen shell.** A seventh room changes `UI/WorkspaceView.swift` through exhaustive switches regardless of the input path. The mock and ADR must come first.
- **Drive before more surface.** `docs/status.md:31` is non-empty today (Replace prompt, Train Model…), so no room UI can land yet.
- **Gate D.**
  - Any candidate pruning (A/C) is Gate D.
  - Adding per-phase score retention for B* must be shown not to move any number in the phase map: an additive output, under Gate B with a refuter.
  - E is a new science number, so it is pre-registered per `ROADMAP.md:134-140`, not just Gate B.
- **Parity pins.** exspy integer and closed-form pins plus LS fits only (C4).
- **Thresholds are dataset properties:** the zero-peak fraction (C2), the vacuum mask, dead time.
- **Unvalidated labels propagate** from phase map and segmentation pools.

## 6. My recommendation per decision

| Decision | Fable | Mine | Would change if |
|---|---|---|---|
| Data model | M2 + M3 cache | **M2**. Pool on the native spectrum grid via mask transport. No dense cube until a per-pixel method needs one. | A per-pixel joint method ships in v5.0 |
| Plain-SI window (M2′) | Later slot, owner's call | **Decide at the room mock, now.** All owner data are plain spectrum images. | The owner says EDX only ever attaches to a cube |
| Velox frame alignment | Re-correlate HAADF, store shifts | **Drop it.** Record A13/A23 as provenance and show a residual check. | A file shows non-zero frame offsets, or compensation was off |
| Registration refinement | Virtual ADF ↔ Velox HAADF | **GMS survey ADF ↔ Velox HAADF, chained via `Spectrum Image Rect`.** Allow det < 0. Check pixel lag for identity. | The survey's drift relative to the SI exceeds what the virtual-ADF route achieves |
| Input-path priority | Velox, then the GMS DMFile split | **Velox + MSA/hspy, then cross-file registration.** GMS same-file stays conditional on a licence and service check. Note the Velox-native MRC path as a gap. | The test acquisition shows GMS STEMx + Super-X works on the Talos |
| Repo "defects" | Fix 3 | **Reproduce the Velox/hspy case first.** The other two are hardening. | Reproduction fails |
| M1 line table | exspy plus a corrected table | **exspy verbatim.** A per-line DEVIATION only for a used line shown wrong (C5). | Ce/U/M-lines enter scope |
| M2 MAC source | EPQ FFastMAC | Agree (licence chain) | — |
| M3 loss | Poisson-ML | **Poisson-ML via IRLS/EM. Parity on LS only.** | — |
| M4 exspy dataset defaults | Refuse and show | Agree | — |
| Absorption on the summed stream | Refuse | **Four-quadrant geometric correction, badged.** Refuse only when geometry is unknown. | Shadowing at tilt is shown to dominate |
| k-factors (new **M9**) | Typed, with source; theoretical out | **v5.0 outputs free of k-factors as primary; typed k with source optional;** theoretical-k sheet in v5.x | The owner measures k on a standard |
| M5 CIFs | Import the Al-Mg-Si set | Agree, **plus a separability matrix before B***, including stoichiometry-model spread | — |
| M6 probe current | Typed, or defer ζ | Read Velox `ScreenCurrent` (C8), labelled as an uncalibrated screen reading; defer ζ | A Faraday-cup calibration exists |
| M7 B* | Table only | Table only, **after** per-phase score retention and the separability matrix | — |
| M8 first real truth | YAlO₃ | Agree. It is also a dm4 EDS-SI reader fixture (C15, unverified). | — |
| Strategy | S1 + B* table + D | **S1 re-sequenced:**<br>(1) plain-SI baseline (outputs free of k-factors, absorption, statistics);<br>(2) the owner acquires the first joint field: sequential at the 4D field and tilt, or a STEMx test;<br>(3) registration, then E per phase or region;<br>(4) per-object E only on simultaneous or sub-object-registered data;<br>(5) B* table if the matrix shows a separable pair;<br>(6) D exploratory. | A real joint scan with sub-nm registration |

## 7. Still unverified

- The units of A13/A23.
- Whether drift compensation was on for every owner file.
- ScreenCurrent as probe current, and whether 051 actually used the 18:41 optics.
- Holder shadowing at α −16.9°.
- The contents of ePSIC YAlO₃.
- The β″ composition literature, which I recalled from memory.
- Whether the Velox `.emd` open defect reproduces in the app.
- Whether the Talos has a speed-enhanced Ceta-2 and a 4D licence.