REPORT: ownerdata. Inventory of the owner's own data for EDX and 4D-STEM + EDX work.

Abbreviations used below:
- SSD = `<owner-ssd>`
- NB = `<owner-backup>`
- SCR = `<scratch>/edx/ownerdata`

## 1. Headline findings

1. **There is no simultaneous 4D-STEM + EDX recording anywhere on the SSD.**
   - No `.dm4`, `.dm3` or `.emd` file mentions STEMx, EDS, EDX or X-ray in any tag. I searched the full tag tree of all 307 `.dm4` files for these words, plus the filename search (0 hits). No `.bcf`, `.spx`, `.pts`, `.rpl`, `.ser` or `.mib` files exist.
   - The owner's `.dm4` files hold two kinds of data. One is 4D-STEM "Diffraction SI" cubes. The other is EELS spectrum images (x, y, E), which are not EDX.
   - The owner has never recorded a STEMx file. The `.dm4` EDX layout therefore cannot be derived from his data.
2. **The 4D-STEM and the EDX come from the same instrument, but from different sessions.**
   - Both were recorded on the Talos F200X. The 4D-STEM goes through GMS with a Gatan Continuum GIF used as the camera. The EDX is Velox `.emd` from the 4-SDD Super-X.
   - The 4D-STEM tag `Session Info.Microscope` = "Talos F200X" and the Velox metadata `InstrumentModel` = "Talos F200X" (details in §3 and §4).
3. **The single closest pair is sample CA_DA_190330 on 2026-06-03.** The 4D cube is `051_STEM SI.dm4`.
   - It was recorded the same day and on the same lamella as three EDX spectrum images (SIs). It was not recorded at the same field or tilt, so it is not a registered pair (§5).
4. **The EDX is count-starved.** Measured from the file's own summed spectrum, the Al-Mg-Si SIs hold only about 11–19 X-ray counts per pixel in total (§7). That is far too few for pixel-level phase decisions.
5. **No working eXSpy environment exists on this Mac.**
   - The owner's notebooks ran HyperSpy 2.4.0 and eXSpy 0.3.2 in a conda env `hyperspy` (Python 3.11). That env is not in `~/miniconda3/envs`.
   - `temtemp` and `temtemp38` have HyperSpy 2.2.0 and RosettaSciIO 0.6, but no exspy. `thronsen` has HyperSpy 1.7.3.
   - I did not install anything.

## 2. Method and limits

- **Search coverage.** Full-volume `find` on SSD (minus system folders, the `__new_mac` backup tars and `Bilder`), plus the repo `References/`, `~/Downloads`, `~/Desktop` and `~/Documents`.
- **Extensions covered.** emd, bcf, spx, msa, emsa, pts, h5oina, dm3/dm4/dm5, rpl, raw, ser, emi, mib, blo, hspy, zspy, tia.
- **Name patterns.** EDS, EDX, STEMx, spectr, SI, 4D, xray.
- **Metadata read.** All 2149 `.emd` files and all 307 `.dm4` files were opened header-only.
  - `.emd`: HDF5 group structure and the small per-dataset JSON metadata.
  - `.dm4`: ncempy tag-tree parsing, which is lazy and memory-mapped. No large array was read.
  - A few small slices were read: images of at most 8 MB, 16 KB summed spectra, and `.ipynb` notebook text.
- **Tools.** Scripts used the conda env `py4dstem` (h5py 3.11, ncempy 1.11.1). Base conda has no h5py.
- **Writes.** Nothing was written, copied or moved outside SCR. `git status` on the repo is clean.
- **Not searched.**
  - `/Volumes/eXtendedGROUPS` is a university SMB share holding other groups' X-ray microscopy data. Only its top level was listed.
  - `<owner-ssd>/__new_mac/GitHub.tar` (old-Mac repo backup) was listed with `tar -tvf` only, not extracted. It has no `.emd` or `.dm4` entries.
- **Home folders.** `~/Downloads`, `~/Desktop` and `~/Documents` contain no EDX data. They hold only ESEM TIFFs, PDFs and PPTX files, one of them `GRK_LMW_LPBF_AlMgSi_results.pptx` (not opened).
- **Not executed or opened.** The installers in `NB/02_methods/Software/` (Velox 3.15 `.exe`, GMS 3.6.1 `.exe`, the GATAN free-offline zip) were not run, extracted or opened.
- **Documentation on the SSD.** Two PDFs may be useful to the other agents. I did not open them.
  - `NB/02_methods/TEM/Velox 2.12 User Manual.pdf`
  - `NB/02_methods/TEM/Talos F200X G1 Pre-Install Manual.pdf`

## 3. 4D-STEM datasets (GMS `.dm4`, header-parsed)

All entries: Talos F200X, 200 kV, GMS "Spectrum Imaging" with `DigiScan (hardware-sync)` and a Gatan Continuum GIF as camera. The 4D axis order in the file is (kx, ky, rx, ry). Times are local, taken from the `.dm4` tags. Source: `SCR/dm_scan.jsonl` and `SCR/dm_summary.txt`.

| Cube | Path (copies listed) | Size | Acquired | Scan (rx×ry), step | Detector px | CL | Pixel time | Mag |
|---|---|---|---|---|---|---|---|---|
| 036_STEM SI | `SSD/4D_STEM_Datacubes/`, `NB/01_projects/LMN_MA_4DSTEM/unbinned_datacubes/` | 17.0 GB | 2023-10-22 20:17 | 106×153, 5.9 nm | 512² | 47 mm | 50 ms | 69 kx |
| COPL_Ni65Cu35_C_ROI6_240911 (Ni65Cu35 HPT) | `NB/01_projects/LMN_MA_4DSTEM/unbinned_datacubes/` | 41.95 GB | 2024-09-11 13:09–13:43 | 200×200, 3.0 nm | 512² | 35 mm | 50 ms | 35 kx |
| **051_STEM SI** (sample 190330) | `NB/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/4DSTEM_190330/Workspace 1/` | 17.18 GB | **2026-06-03 18:51–18:57** | 128×128, 10.03 nm | 512² | 77 mm | 20 ms | 49 kx |
| 055 (ROI_1, sample 170330) | `NB/00_inbox/4DSTEM_170330/ROI_1/raw/SI data (1)/` | 17.19 GB | 2026-06-30 17:39–17:51 | 256×256, 0.51 nm | 256² | 77 mm | 10 ms | 630 kx |
| 056 (ROI_2) | `.../ROI_2/raw/SI data (2)/` | 17.19 GB | 2026-06-30 18:05–18:17 | 256×256, 1.57 nm | 256² | 77 mm | 10 ms | 320 kx |
| 057 (ROI_3) | `.../ROI_3/raw/SI data (3)/` | 28.90 GB | 2026-06-30 18:33–18:52 | 334×330, 1.88 nm | 256² | 77 mm | 10 ms | 160 kx |
| 058 (ROI_4) | `.../ROI_4/raw/SI data (4)/` and `..._corrected/` | 28.56 GB each | 2026-06-30 19:10–19:29 | 330×330, 1.67 nm | 256² | 77 mm | 10 ms | 160 kx |
| **060 (ROI_5)** | `.../ROI_5/raw/SI data (7)/` | 28.56 GB | 2026-06-30 20:39–20:58 | 330×330, 1.53 nm | 256² | 60 mm | 10 ms | 225 kx |

Notes on this table:
- The `ROI_4/.../SI data (4)_corrected/` copy has the same size and header. It also has a `Peak y-shift.dm4` file. From the filename, that is a y-shift correction. I did not check the data.
- Rows 055–060 are all sample 170330 per their folder name.
- Each cube has companion files: `Signal Integral (Dynamic).dm4` and `(1) Diffraction of Diffraction SI.dm4`. `ROI_1/raw/` has ADF survey images `ADF_0960..0962.dm4`; `ROI_4/raw/Analytical (4)/` has `ADF_0967.dm4`.
- The tags show `Pixel iterator = DigiScan (hardware-sync)`, `Acquisition Mode = Parallel imaging`, device `GIF`, source model `Continuum`, 2D Array SI.
- Derived HDF5 cubes already exist: `NB/00_inbox/4DSTEM_Binned_Cubes/*bin_4*.h5` and `NB/00_inbox/4DSTEM_170330/ROI_*/*bin_4_20260712.h5` (1.07–1.81 GB; shape (rx, ry, 64, 64)).
  - Also `ROI_5/mac4dstem_subsampled/060_STEM_SI_stride3.h5` (3.17 GB).
  - For 190330, `Workspace 1/` holds `051_..._bin_4_20260629.h5` (268 MB, 128×128×64×64), `_bin_2` (4.3 GB), `_no_bin` (17.2 GB), `braggdisks_*.h5` and `probe_kernel.h5`.
- Other 4D files on the SSD are not owner Talos data or not EDX-relevant: `Si-SiGe.dm4` (K2-IS, 300 kV, 2018), `SPED_MgO`, `NP_data`, `calibrationData_*`, `twisted_bilayer_graphene`, `data_scan147`. None contains spectral data.

## 4. EDX data (Velox `.emd`, HDF5)

**Totals.** 2149 `.emd` files in total.
- 142 contain a `SpectrumStream` group. 134 of those have a populated stream with frame table.
- Those 134 are 104 unique acquisitions (de-duplicated by size and start time).
  - 66.7 GB unique, 91.4 GB with duplicates.
- 8 files have an empty or partial stream, or are single-spectrum files. Examples: `SI HAADF 0826.emd`, `1259.emd`, `1507.emd`.
- 10 `.emd` files are 800-byte stubs with no `Data` group.
- The other ~2000 are Velox image files (Ceta and STEM HAADF images, "Micro Camera" diffraction movies, etc.).
- All Velox SIs are Talos F200X except 2 from the KIT Themis at 300 kV.

**What an SI file contains.**
- `Data/SpectrumStream` is a sparse `uint16` event stream plus `FrameLocationTable`. The per-frame metadata is JSON, 28 columns for 28 frames.
- `Data/SpectrumImage` is a Velox-built cube.
- `Data/Spectrum` is a summed spectrum, 4096 channels at 20 eV/ch (some files 5 or 10 eV/ch).
- `Data/Image` holds a HAADF frame stack plus Velox element maps tagged detector `SuperXG1`.
- The 4 SDDs `SuperXG11..G14` are all enabled, per detector metadata. No Ceta frames appear in any SI file.

**Velox image shape.** Velox stores images as (width, height, frame), so they need a transpose to display.

**Verification of the energy axis.** On the 190330 SI I confirmed the axis `E = OffsetEnergy + ch×Dispersion` with `OffsetEnergy = −1932 eV`. The Al Kα maximum falls at 1.488 keV and the Cu Kα maximum at 8.028 keV.

**Quant settings stored in the file.** Under `Operations/SpectrumQuantificationOperation` Velox stores:
- an element selection;
- Brown-Powell ionisation cross-section;
- absorption correction off;
- a list of background windows;
- sample thickness 50 nm (the stored value `5e-8` is presumably metres; unverified).

I did not find a numeric Velox quantification result table. `Data/Text` is not human-readable text.

### 4a. Al-Mg-Si LPBF family (project `NB/01_projects/GRK_LMW_LPBF_AlMgSi/`; this is the app's own material)

Times are CEST, converted as epoch + 2 h. Stage values are Velox, in µm. Velox rate-based counts/px are in §7.

| Date, time | File (`CA_DA_*/emd_files/` unless noted) | Size | Scan, dwell, frames | FOV | Stage x, y, α |
|---|---|---|---|---|---|
| **190330** 06-03 10:06 | `SI HAADF 1006 65000 x 20260603` | 987 MB | 2048×682 rect, 6.25 µs, 120 | 1.55 µm | −365, −126, +7.3° |
| 06-03 10:38 | `SI HAADF 1038 91000 x 20260603` | 990 MB | same | 1.09 µm | −366, −126, +7.3° |
| 06-03 11:22 | `SI HAADF 1122 130 kx 20260603` | 976 MB | same | 0.77 µm | −366, −126, +7.3° |
| 06-05 10:52 | `SI HAADF 1052 33000 x 20260605` | 988 MB | same | 3.04 µm | −365, −44, +5.2° |
| 06-05 11:29 | `SI HAADF 1129 23000 x 20260605` | 1.78 GB | 2048², 8 µs, 83 | 4.3 µm | −366, −44, +4.4° |
| **170330** 05-08 | `SI HAADF 1312 11500 x 20260508` (also in `archive/170330_20260508_unthinned/`) | 455 MB | 2048², 3.12 µs, 28 | 8.6 µm | −343, +116 |
| 05-12 | `SI HAADF 1534 16500 x` | 933 MB | 2048², 2 µs, 104 | 6.1 µm | −133, −62, 0° |
| 05-12 | `SI HAADF 1549 11500 x` (= `NB/00_inbox/hyperspy_edx/CA_DA_170330_EDX_2.emd`) | 441 MB | 2048², 4 µs, 47 | 8.6 µm | −133, −61 |
| 05-12 | `SI HAADF 1606 130 kx` | 169 MB | 1024², 4 µs, 30 | 0.77 µm | −132, −63 |
| 05-12 | `SI HAADF 1623 91000 x` | 214 MB | 1024², 4 µs, 39 | 1.09 µm | −115, −56 |
| 05-12 | `SI HAADF 1633 46000 x` (= `NB/00_inbox/hyperspy_edx/CA_DA_170330_EDX.emd`) | **7.45 GB** | 2048², 2 µs, 480 | 2.19 µm | −115, −57 |
| 06-05 | `1402 23000 x` 1.2 GB (8 µs ×53); `1438 33000 x` 1.01 GB, `1509 65000 x` 1.00 GB, `1537 91000 x` 1.01 GB (2048×682, 6.25 µs ×120) | 1.0–1.2 GB | see left | 4.3 / 3.04 / 1.55 / 1.09 µm | −290, −47, +8.6° |
| **140330** 05-06 | `1840 23000 x` 913 MB, `1909 11500 x` 713 MB, `1949 91000 x` 1.04 GB | | 1024²/2048², 4–8 µs | | −284, −459 |
| 05-08 | `1339 65000 x` | 261 MB | 1024², 6.25 µs, 43 | 1.55 µm | +297, −32 |

- Velox element selections: Mg, Al, Si; plus Mn on the 05-12 files; plus C, O, Ar, Fe, Cu, Zr on the 190330 06-03 files (spectral peak-ID selection).
- The project README (`.../GRK_LMW_LPBF_AlMgSi/README.md`) states the intended EDX settings. For 79–160 kx: spot 5, C2 100 µm, CL 125 mm, 6.35 µs, 120 frames (21 min), rectangular 2048×682. Colouring: Si red, Mg yellow, Al grey.
- Duplicates: `CA_DA_170330_EDX.emd` is a copy of `SI HAADF 1633 46000 x` and `CA_DA_170330_EDX_2.emd` a copy of `1549`. Each exists three times, in `NB/00_inbox/hyperspy_edx/`, `NB/02_methods/Software/Hyperspy/hyperspy_edx/` and the project folder. The 7.4 GB file therefore occupies about 22 GB.
- Other Al-Mg-Si-like material:
  - `NB/01_projects/LMN_EM_General/KS_PL_AlSiMg_Training/SI HAADF 1425 16500 x.emd` (2025-03-07, 1.77 GB, 512², 6.25 µs, 1460 frames; elements Mg, Al, Si, Ca, Cu). I estimate about 45 counts/px (stream-length method, §7).
  - `.../for_Temesgen/.../` AlSi10Mg SIs from Oct 2024: `1637.emd` 3.7 GB, `1755.emd` 2.4 GB, `1708`, `1618`, plus `Spectrum EDS 1552.emd`.

### 4b. Other EDX families (full list: `SCR/edx_unique.tsv`)

| Family | Files and notes |
|---|---|
| NiCu high-pressure-torsion (Ni65Cu35, thesis) | `NB/01_projects/LMN_MA_4DSTEM/images/high_pressure_torsion/lamB/emd_files/SI HAADF 1352.emd` (280 MB, 2024-12-04) and `1410.emd` (131 MB, same folder). `.../lamC/emd_files/20240612 SI HAADF 1624 185 kx.emd` (272 MB). `.../images/transfer/PL_MA_NiCu_HPT/SI HAADF 1239.emd` (6.0 MB) and `1555.emd` (2.9 GB, 2048², 2 µs, 171 frames, 2024-12-20). Velox elements: O, Si, Ni, Cu. The thesis text says EDX showed no composition variation between grains (`NB/06_academia/PL_Master_Thesis/mastersthesis_latex/master-s-thesis/ResultsDiscussion/Results.tex:270`). |
| Gold reference | `NB/01_projects/LMN_MA_4DSTEM/images/gold_ref/emd_files/SI HAADF 1432.emd` (124 MB, 2024-10-23). `NB/01_projects/LMN_MA_4DSTEM/images/transfer/20241213/PL_MA_Au_ref/SI HAADF 1143.emd` (4.2 MB, 1 frame). |
| FeO nanoparticles | `NB/00_inbox/hyperspy_edx/SI HAADF 1610.emd` (143.5 MB, 1024², 4 µs, 27 frames, 2026-02-11). Also `NB/01_projects/CSnM_BS_FeO_NPs/BS_PL_FeO_NPs/SI HAADF 1615.emd` (145 MB). |
| Rh/SiO₂ catalyst | `NB/01_projects/AGBeine_Katalyse/LR_PL_Rh_SiO_10M_EtOH/emd_files/`: four SIs (54–157 MB) plus `Rh_SiO_10M_EtOH Spectrum EDS 16500 x 20260311 1429.emd` (0.6 MB single spectrum). |
| Other Velox SIs | Glassy carbon lamella (`NB/00_inbox/EW_BS_PL_Glassy_Carbon_TEM/.../SI HAADF 1134 16500 x 20260626.emd`, 2.3 GB). Sensor and HQE materials, TiNbN HP087, SiGe/MDW, rock wool, zirconia nanotubes, CEITEC sample 699. Two KIT Themis Pd-nanoparticle SIs. |
| Single spectra | `.../for_Flamur/20241024_rock_wool/Spectrum EDS 1136 0001.emd` (0.3 MB), `.../for_Temesgen/20242024_AlSi10Mg/Spectrum EDS 1552.emd` (0.7 MB). `NB/01_projects/LMN_EM_General/for_MDW/MDW_PL_Maurice/SiGe_Spektrum-Spectra from Area #4-Spectrum.msa` (20 KB, the only `.msa`). |
| SEM EDX (Oxford AZtec) | `NB/01_projects/GRK_IME_Ni660_Tiegel/IME_LMN_NiCr_EDX/Sample_2.1.4_EDX/h5oina/`: 8 `.h5oina` files, 46 MB–1.9 GB. Dense per-pixel spectra `(N, 1024 or 2048)` `int32`, 20 kV. Smallest: "Live Map 4", 512×352 px × 1024 channels at 20 eV. Also 8 `.oipx` projects, e.g. `GRK_LMW_LPBF_AlMgSi/4383PM_AB/EDX_4383PM_AB/` (1.4 GB of `.dat`, proprietary). |

### 4c. Adjacent, not EDX: EELS spectrum images (x, y, E)

- `.dm4` EELS SIs are in `NB/01_projects/LMN_EM_General/EELS_TiO_2_ref_20250325/` (13.1 GB, 12.98 GB and 1.15 GB), `LMN_NOVA_EELS/`, `LOT_Quadrature_Project/HP087/20250415*/` and `for_Flamur/Paderborn_backup/...`.
- Shape (x, y, 1963–2048 channels), 0.3 or 0.75 eV/ch, Continuum GIF.
- They show how GMS writes a 3D SI object (`ImageList` entries "EELS LL SI" and "EELS HL SI"). A GMS EDX SI would presumably be analogous. This is unverified without a real STEMx file.

### 4d. The owner's earlier HyperSpy EDX work

- `NB/00_inbox/hyperspy_edx/hyperspy_edx_170330.ipynb`, `hyperspy_edx.ipynb`, `hyperspy_edx_WIP.ipynb` (plus `archive/` and the `Software/Hyperspy/` copy). These ran HyperSpy 2.4.0 and eXSpy 0.3.2.
- Workflow (cell sources read directly): `hs.load` of the Velox EMD → `signals[5]` → `set_signal_type("EDS_TEM")` → `set_microscope_parameters(energy_resolution_MnKa=130)` → `set_elements` / `set_lines` → `estimate_background_windows(line_width=[5.0, 2.0])` → `get_lines_intensity` → `quantification(method="CL")`.
- **They are not calibrated truth.** The k-factors are placeholders (1.0 for Al/Mg/Si; [19, 1.5, 18] for C/Fe/O "assumed only so the workflow runs"). Only figure outputs are embedded. `CA_DA_170330_EDX_2_output/` is empty.
- Printed signal shapes show how RosettaSciIO exposes these files: `signals[5]` = EDS (828, 1692 | 4096) for the 05-12 4 µs file; the FeO file gives (1024, 1024 | 4096). X-ray energy axis: offset −1.9 keV, scale 0.02 keV.

## 5. Pairing analysis: is anything simultaneous?

No. Of all the EDX acquisition dates, the only calendar day that also has a GMS 4D-STEM acquisition is 2026-06-03, for sample 190330.

**Same-session evidence for 190330, 2026-06-03.**
- EDX SIs at 10:06, 10:38 and 11:22 at stage (x, y, α) = (−366, −126, **+7.3°**).
- Velox `STEM HAADF 1841 28500 x 20260603.emd` (`NB/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/emd_files/`, 8.7 MB) at 18:41 at (−385.0, −125.7, **−16.87°**), FOV 3.49 µm.
- 4D-STEM `051_STEM SI.dm4` at 18:51 at GMS stage X −384.06, Y −125.00, α −16.87°. This matches the 18:41 HAADF image to about 1 µm. The Velox and GMS stage coordinates are consistent in this session.
- Side-by-side look at `SCR/cmp_190330_1841.png`: the 18:41 HAADF and the `051` ADF survey show the same kind of small dark elongated features at similar contrast. This is a visual comparison, not a registration.
- The three EDX SIs are about 18 µm away in x and about 24° different in tilt from the 4D region. Their fields do not look like the 4D survey (`SCR/cmp_190330.png`).
- Scan sizes do not match: EDX is 2048×682 rectangular, 4D is 128×128.
- **Result:** same lamella (y within ~1 µm), same day, almost certainly the same holder insertion (unverified); EDX at a different position and tilt. The precipitate-visible zone-axis tilt, which the project README says is "super important", was not used for EDX.

**Sample 170330 (the app's Al-Mg-Si cube family).**
- 4D-STEM ROI_1–5 on 2026-06-30.
- EDX on 05-08, 05-12 and 06-05. The 170330 emd folder has no Velox acquisition on 06-30.
- Stage coordinates differ greatly (4D x ≈ −55, y ≈ −72; EDX 06-05 x ≈ −290, y ≈ −47), consistent with a different holder session.
- One montage (`SCR/cmp_170330.png`) shows ROI_3 and ROI_4 ADF surveys with dark elongated features resembling the 06-05 HAADF images. Overlap is plausible but unverified; no registration was attempted.

**Thesis material (2024).**
- NiCu HPT: 4D cubes are dated Sep 11 (lamC), Nov 19 (lamB, from the filename) and Nov 22 (lamD, from the filename). EDX on lamB was Dec 4 and on 1555 on Dec 20.
- Gold reference: Velox `SI HAADF 1143` is dated 2024-12-13, the same session as nearby ADF surveys. The 4D `Au_ref_ROI15` cube's acquisition date is not recorded in the HDF5 (unverified).

**Joint-method truth.** None exists with real data. See §6.

## 6. Fixture and truth candidates

### Small fixtures (read-only copies, cropping or subsampling later)

Plain EDX spectrum images, Velox `.emd`:

| Path | Size | Content |
|---|---|---|
| `NB/01_projects/AGBeine_Katalyse/.../emd_files/Rh_SiO_10M_EtOH SI HAADF 33000 x 20260311 1456 0001.emd` | 54 MB | 858×555 image, 14 frames, 12.5 µs. Summed spectrum 2.96 M counts ≈ 6.2 counts/px (checked). Rh/Si/O/C. Best small, count-rich file. |
| `NB/00_inbox/hyperspy_edx/SI HAADF 1610.emd` | 143.5 MB | FeO nanoparticles, 554 k counts ≈ 0.5/px (checked). Owner's HyperSpy notebook baseline exists. |
| `.../CA_DA_170330/emd_files/SI HAADF 1606 130 kx 20260512.emd` | 169 MB | Al-Mg-Si |
| `.../CA_DA_170330/emd_files/SI HAADF 1623 91000 x 20260512.emd` | 214 MB | Al-Mg-Si |
| `.../CA_DA_140330/emd_files/SI HAADF 1339 65000 x 20260508.emd` | 261 MB | Al-Mg-Si |
| `NB/00_inbox/hyperspy_edx/CA_DA_170330_EDX_2.emd` | 441 MB | Al-Mg-Si. Owner's notebook baseline. |
| `.../for_MDW/MDW_PL_Maurice/SI HAADF 0828.emd` | 6.6 MB | SiGe/MDW, 10 frames, very low counts |
| `NB/01_projects/LMN_MA_4DSTEM/images/transfer/20241213/PL_MA_Au_ref/SI HAADF 1143.emd` | 4.2 MB | Au reference, 1 frame, very low counts |
| `.../PL_MA_NiCu_HPT/SI HAADF 1239.emd` | 6.0 MB | NiCu HPT, tiny SI |

Single-spectrum files, for spectrum-level processing and format tests:
- The three `Spectrum EDS *.emd` files (0.3–0.7 MB).
- The `.msa` file (20 KB).

Dense SEM format:
- `.../Sample_2.1.4_EDX/h5oina/...Live Map 4.h5oina` (46 MB). SEM, thick specimen: not TEM physics, but a valid dense-spectra and peak-fitting test.

4D side (already small):
- `NB/01_projects/GRK_LMW_LPBF_AlMgSi/CA_DA_190330/4DSTEM_190330/Workspace 1/051_STEM SI_preprocessed_unfiltered_bin_4_20260629.h5` (268 MB, 128×128×64×64).
- `NB/00_inbox/4DSTEM_Binned_Cubes/COPL_Ni65Cu35_C_ROI6_...bin_4_20240912.h5` (164 MB).

### Truth and reference candidates (with caveats)

- **Owner's HyperSpy 2.4.0 / eXSpy 0.3.2 notebook runs** on `CA_DA_170330_EDX_2.emd` and `SI HAADF 1610.emd`. Pipeline reference only. Placeholder k-factors, figures only.
- **Velox's own element maps and quant settings**, stored in every SI file: Brown-Powell cross-section, background windows, element selection. These are an independent vendor reference for net-intensity maps. Its equivalence to the eXSpy method is unverified.
- **Known or nominal compositions** (nominal values unverified):
  - AlSi10Mg: Temesgen SIs 1637, 1755, 1708 and `Spectrum EDS 1552`.
  - Ni65Cu35 (the filenames say Ni65Cu35; wt% vs at% unverified). The thesis states EDX shows no grain-to-grain composition variation, so it is a homogeneous control.
  - FeO, Au, SiGe (MDW, composition unknown), TiNbN (HP087/HP105; N Kα and Ti L overlap).
  - Highest-count candidates for statistics: `SI HAADF 1102.emd` (HP087, 1.1 GB, ~545 counts/px, stream-estimate) and `SI HAADF 1448.emd` (rock wool, 2.3 GB, ~470 counts/px).
- **Joint 4D-STEM + EDX truth:** none from real data.
  - Thronsen A has a truth phase map but no EDX (none in `References/`).
  - The app's synthetic AlMgSi demo has `truth.json` but no EDX.
  - EDX counts could be simulated from those truth labels, my inference, not in the data.

## 7. Statistics relevant to method choice

- **Counts per pixel, measured from the file's stored summed spectrum.**

| Sample / file | Counts/px |
|---|---|
| 190330 06-03, three SIs | 12.8, 13.3, 13.1 |
| 170330 06-05 `1537` | 18.7 |
| 170330 05-12 `1633` (7.4 GB) | 10.8 |

  - In the 190330 `1006` file, 17.39 M of the 17.88 M counts lie between 0.15 and 20 keV. 12.46 M of those fall in a 1.40–1.58 keV window around Al Kα, about 70 % of all counts.
  - The raw window sums at Mg Kα (0.55 M) and Si Kα (0.35 M) are unsubtracted background plus tails. The net Mg and Si counts per pixel are therefore well below 1 for an Al matrix.
- **Estimation method.** I estimated counts/px for other files from stream length: `events ≈ (words / (pixels × frames) − 1) × frames`, assuming one end-of-pixel marker word per pixel-frame.
  - This agreed with the stored summed spectrum on 7 files: 190330 ×3, 170330 0605, the 7.4 GB file, FeO 1610 and Rh 1456.
  - It is not valid where the stored `Data/Spectrum` covers only a region. For `EDX_2`, AlSi10Mg 1637 and NiCu lamB 1352 the summed spectrum is far smaller than the stream implies, so I treat those counts as unreliable.
- **Dwell comparison.** Velox Al-Mg-Si SIs: 6.25 µs × 120 frames = 0.75 ms total dwell per pixel. GMS 4D-STEM: 10–20 ms per pixel, about 13–27× longer.
  - With the same beam current and detector, a simultaneous 4D-STEM + EDX would accumulate on the order of 10²+ counts/px (Velox output rates of 12–22 kcps × 10 ms ≈ 120–220).
  - This is a back-of-envelope inference. Beam current and CL differ between the two modes, so it is unverified.
  - It differs from the survey note's "about 0–10 counts/pixel" because that figure presumably assumes a fast pixelated detector.
- **Velox detector facts.** Four SDDs `SuperXG11..G14`, 20 eV/ch, collection angle 0.225 sr, elevation 22° (0.384 rad), begin energy 150 eV. Energy resolution is not stored; the owner's notebook assumes 130 eV.

## 8. Datasets the app already uses (`<repo>/References/`)

- `thronsen-datasetA/`: `datasetA_stride3.h5` (513 MB), `datasetA_stride3.mac4dstem.h5` (21 MB), `truth_stride3.json`, and `published/*.hspy` (Thronsen's ground truth and phase maps, HyperSpy format). Public, CC BY 4.0, per `docs/v3-features.md`.
- `demo-dataset/`: `AlMgSi_demo.h5` (177 MB, synthetic), `truth.json` (225 KB), `reflections.json`, `truth.png`.
- `training_dataset/`:
  - The owner's 4D-STEM Al-Mg-Si cube. It is `Al_Mg_Si_060_STEM SI_preprocessed_unfiltered_bin_4_20260712.h5` (1.7 G, shape (330, 330, 64, 64), float32) = **ROI_5 `060_STEM SI`, sample 170330, 2026-06-30**. Plus `.mac4dstem.h5` (32 M) and `..._ellipse-20260925.h5` (1.7 G).
  - Also `Au_ref_ROI15_..._bin_4_20241214.h5`, `Particle_1_Stack_1_45x90_ss30nm_..._300kV_bin8.h5` (300 kV, CL 600 mm; probably not Talos, source unverified), `Si-SiGe_calibrated.h5`, `calibrationData_bullseyeProbe.h5`, `downsample_Si_SiGe_exp.h5`, `polycrystal_2D_WS2.h5`, `sim_Au_data_all_binned.h5`.
- No EDX data in `References/`. `ROADMAP.md` line 78 and `docs/decisions.md` (ADR 051) say EDX correlation is the owner's next feature after a stable product (v5/v6).

## 9. Gaps (observations, not decisions)

- A true 4D + EDX recording does not exist. The `.dm4` STEMx layout is undocumented in the owner's data and must come from a real file or from RosettaSciIO/DM documentation (unverified).
- The lab's GMS version and whether STEMx is licensed on the Talos acquisition PC are unknown. The installer `NB/02_methods/Software/GMS/GMS_3_6_1_64-Bit.exe` suggests GMS 3.6.1 (unverified).
- For a registered pair, the 190330 session is nearly there: Velox HAADF and the 4D survey are already matched in stage and tilt. EDX at that position and tilt (α ≈ −16.9°) is what is missing.
- Re-acquiring EDX at a 4D field would also give truth for the diffraction-based phase maps (Mg/Si pooled over β″ needle objects).
- Mismatch of conventions to remember:
  - Velox stage in metres, GMS in µm. They agree in the 190330 session; GMS time is local, Velox epoch is UTC.
  - Velox images are (x, y, frame).
  - Duplicates: the same acquisition often exists in 2–3 folders.

## 10. Unverified items

- Same-lamella status of 170330 4D vs EDX (the montage is visual, and the stage differs by ~235 µm).
- Any registration of the 18:41 HAADF to the 4D ADF survey.
- Nominal compositions (AlSi10Mg, Ni65Cu35 units, SiGe).
- Velox software version in the file (not parsed).
- Whether any 4D cube other than 190330 `051` is on the same lamella as an EDX SI.
- Readability of the Oxford `.dat` files without AZtec.
- Acquisition date of `Au_ref_ROI15`.

## 11. Scratch outputs

All in `SCR/`.
- `find_ext.txt`, `find_names.txt`: raw find results.
- `emd_scan.jsonl`: per-`.emd` header scan.
- `dm_scan.jsonl`, `dm_summary.txt`: per-`.dm4` header scan and the 4D/EELS dimension summary.
- `edx_unique.tsv`: 104 unique EDX acquisitions with start time, scan, dwell, frames, FOV and duplicates.
- `rates.json`: rate- and stream-based counts.
- `elems.json`: Velox element selections.
- `sumspec.py`: summed-spectrum check.
- `cmp_190330.png`, `cmp_190330_1841.png`, `cmp_170330.png`: field comparison montages.

A `caffeinate -dimsu -t 7200` (PID 7722) was started for the 2-hour "keep awake" request. A 24-hour caffeinate (PID 4914) already existed.