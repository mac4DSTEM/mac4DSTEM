I could read the GMS 3.6.1 installer's PDFs, but not the DigitalMicrograph Help, which is the most detailed source on STEM SI and EDS. Most of what follows comes from those PDFs, from tag dumps of the owner's own `.dm4` files, and from public Gatan material. Every claim is marked VERIFIED, INFERRED or UNVERIFIED.

**Source abbreviations.** `SP` = `<scratch>/edx`. Text versions of the PDFs are under `SP/gms/txt/` (line numbers below refer to those); the PDFs themselves are under `SP/gms/`.
- [STEMx] `1020.40004_V002_STEMx System User Manual.txt`
- [EDSIG] `EDS Acquisition Installation Guide.txt` (the copies in `Documentation/` and `Support/EDSRemoteServer/` are byte-identical)
- [RN] `SP/gms/ReleaseNotes.txt`
- [PY] `Python.txt`
- [GS] `GMS - Getting Started.txt`
- [ELITE] `1070.82001_REV02_Elite T User Manual.txt`
- [DS3] `888.82001_REV05_DigiScan 3 User Manual.txt`
- [K2IS] `1010.40004_REV01.txt`
- [OWN] `SP/ownerdata/dm_scan.jsonl`, the sibling agent's ncempy header and tag scan of the owner's `.dm4` files. I only read it.
- [RSCIIO] `~/miniconda3/envs/temtemp38/lib/python3.8/site-packages/rsciio/digitalmicrograph/_api.py` (v0.6), checked against GitHub `main` by web fetch.
- [GORJI] Gatan's Warwick open-day talk, `https://warwick.ac.uk/research/rtp/em/info/facility_open_day/saleh-gorji-gatan-4dstem-unveiled-capturing-diffraction-at-every-pixel.pdf`; text at `SP/gms/web/gorji-warwick.txt`.

## 0. How the sources were obtained (deviations)

- **Extraction tool.** The installer is a RAR SFX. The Homebrew `7zz` has no RAR codec: it failed with "Unsupported Method" on all 14 entries, and `7zz i` lists no Rar codec. I therefore extracted with libarchive `bsdtar` (`~/miniconda3/bin/bsdtar`), which only reads the archive. This breaks the "7zz only" rule. No binary was executed.
- **DigitalMicrograph Help: not obtained.** [STEMx]:206-208 and :233 send readers to the "STEM Spectrum-Imaging" and "STEM Diffraction-Imaging" help sections. That help sits inside `Setup.exe` (1.53 GB, an InstallShield `ISSetupStream` with 18 entries). The one that matters is `GMS.msi` (1,526,893,594 bytes, stored encoded, flags=6).
  - Decoding that stream was denied by the auto-mode classifier, and I did not pursue it further.
  - The DM help is also not public on the web.
  - Two ways to get it, both the owner's call: open Help on a GMS PC and export the STEM SI, Diffraction-Imaging and EDS/Elemental Quantification pages; or approve an InstallShield-capable extraction.
- **gatan.com** returned HTTP 429 to every direct fetch. Statements from it below come from search-result snippets and are marked "web".
- **EDAX OEM API.zip** is only an installer (InstallShield, "EDAX OEM API V2.0.0018.0001", prerequisites, `data1.cab`, eDPPShell and OEMAPI setups). It contains no readable documentation.
- **Bruker HS IOS-Update.zip** is a scan-card firmware updater only (`IOScanUpdate.exe`, `.DXE`, `RTPCI.dll`).
- **Oxford_Extender_4_3.msi** was not opened.
- **GATAN_FREE…SI_Viewer zip** holds a free offline licence, `LicenseInstaller.exe` and a 2-page PDF. The PDF says it installs one offline GMS 3.x copy on a computer with no hardware attached, requires GMS ≥3.4.0 to combine with purchased licences, and that the main installer comes from gatan.com/GMS/download (`SP/gms/siviewer/sivi.txt`). The licence files were not read.

## 1. How GMS/STEMx acquires 4D-STEM with simultaneous EDS (and EELS)

### 1a. Hardware and software chain

**4D-STEM (STEMx)**
- The STEMx box synchronises DigiScan with Gatan in-situ cameras in hardware: the camera reports a finished pattern and the DigiScan steps the probe ([STEMx]:113-115, :209-218).
- Rates: up to 300 fps (OneView IS) and 1600 fps (K2 IS) ([STEMx]:219-220).
- A GIF camera can also be the diffraction detector, switched automatically against the in-situ camera ([STEMx]:274-277). VERIFIED.
- Later camera manuals add Metro, Stela, K3 IS and Rio IS (Metro manual :1695-1697; K3 IS manual :2329-2331). VERIFIED.
- DigiScan 3 is "the core component of eaSI"; it accepts up to 20 signals and scans up to 32k×32k ([DS3]:109, :140-141). VERIFIED.

**EDS**
- Needs licence 700.LS.707.11.64.1 ([EDSIG]:126-136).
- The **Gatan EDS Remote Server** is mandatory for every GMS 3 EDS install. It runs on the OEM's EDS PC, or on the Gatan PC; DigitalMicrograph asks at startup for "This PC" or "Remote PC + IP" ([EDSIG]:157-205, :891-945). VERIFIED.
- Supported systems (all VERIFIED):

| Vendor | Systems / requirements | Source |
|---|---|---|
| JEOL | splitter PCI card; HS via an NI PCIe card | [EDSIG]:221-291 |
| EDAX | OEM API (default since GMS 3.4.3), Apollo XLT/TEAM, Genesis 3.6/4.5; Phoenix not supported | [EDSIG]:298-442 |
| Bruker Esprit | ≥1.8; needs Bruker "ESPRIT API" and the licence option `ExternControl` | [EDSIG]:452-477 |
| Thermo Noran | Pathfinder / NSS, with PF-GATAN / NSS-GATAN licences | [EDSIG]:517-587 |
| Oxford | AZtec 3.0-4.3 (licence IDs #28 and #29), INCA | [EDSIG]:680-719 |
| FEI Super-X | see below | [EDSIG]:724-883 |

- **Super-X** (relevant: the owner's microscope is a Talos F200X) needs a second Esprit 1.9.4 installation on the FEI PC with its own communication-server port, an `ExternControl` licence, a Bruker IO-card firmware update to 6.0.1, and a replacement DigiScan DDC with a timing cable into the Bruker interface card. Expected rate is about 1000 pixels/s for dwell times under 1 ms ([EDSIG]:724-869). VERIFIED.

**Hardware-synchronised ("high-speed") EDS SI**
- Needs the Hi-Speed SI licence 700.LS.777.U3.64.1 plus a DigiScan clock-out cable into the OEM hardware: Bruker IO card, Noran DPP through a TTL→LVDS converter, Oxford detector, JEOL NI card, or the EDAX sync kit ([EDSIG]:273-278, :380-407, :487-512, :590-600, :689-690). VERIFIED.

**Gatan's own EDS detector**
- "EDAX EDS Powered by Gatan" (Elite T, models 1070-1072): windowless SDD down to 77 eV, controlled through the EDS Remote Server, needs DM ≥3.5.0 ([ELITE]:105-196). VERIFIED.

### 1b. Acquisition steps (from the PDFs; finer detail lives in the missing help)

1. **Set up the pattern.** Position the probe in DigiScan spot mode, insert the camera and set up the pattern in the camera UI ([STEMx]:226-230).
2. **Select signals on the STEM SI palette.** Pick ADF/HAADF (DigiScan), the **CBED** button (diffraction image; this expands the camera panel) and EDS ([STEMx]:231-247). The palette tooltip shows the memory needed, and DM warns at start if it exceeds what is available ([STEMx]:234-236).
3. **Gear/setup → CBED page.** Choose the camera and software reduction (binning). With STEMx licences, hardware sync is the default; "Force software synchronization" exists for OneView IS ([STEMx]:263-273).
4. **EDS settings.** Channels ("data size"), dispersion and time constant are set in the EDS Acquisition Setup dialog ([ELITE]:286-291). Whether the SI setup has its own EDS page is UNVERIFIED.
5. **Acquire.** Use the "normal STEM spectrum imaging procedure" ([STEMx]:292-295): survey image, SI rectangle, then options seen in the owner's tags (§2d) — spatial-drift ROI and periodicity, sub-pixel scan, number of cycles, end-of-SI actions.
6. **K2 IS caveat.** Patterns stream to Linux capture PCs as raw binary; DM shows a subsampled preview, and the 4D cube is extracted later with the Data Manager (ROI crop, real-space sampling interval, diffraction binning) ([STEMx]:296-301, :327-352; [K2IS]:228-229, :1273-1302). OneView IS and GIF data arrive directly as a DM 4D cube ([STEMx]:327-329). VERIFIED.

### 1c. Which signals can be simultaneous

- "Only one signal… that intercepts the primary beam" can be selected; "EELS and CBED cannot be acquired simultaneously" ([STEMx]:243-245). VERIFIED.
- EDS does not intercept the beam. Gatan states that eaSI "enables simultaneous 4D STEM + EDS and sequential 4D STEM + EELS" ([GORJI], slide "eaSI: STEM experiments combined, linked, and synced"). Web, VERIFIED as Gatan's claim.
- In simultaneous mode the frame rate is set by the camera (≤300 / 1600 fps, or the 100 fps the owner used) and the EDS system follows the DigiScan clock. INFERRED.

### 1d. The owner's actual set-up (VERIFIED from [OWN])

- **Microscope and camera.** Talos F200X, "FEI Tecnai Remote TCPIP". The 4D patterns come from the **GIF Continuum** camera: `Acquisition.Device.Source Model = Continuum`, `Location = filter`, 2048² sensor, binned 4×4 in hardware then 2×2 in software to 256².
- **4D acquisition.** `SI.Acquisition.Pixel iterator = DigiScan (hardware-sync)`, `Pixel time (s) = 0.01`, 330×330 scan.
- **EELS.** The spectrometer is "GIF Continuum ER" (DualEELS).
- **No EDS data in the owner's `.dm4` files.** The sibling scan found no `Meta Data.Signal = X-ray` anywhere. Whether the lab's GMS has the EDS Acquisition and Hi-Speed SI licences and an Esprit `ExternControl` path to its Super-X is UNVERIFIED and needs to be asked.
- **Talos generation.** [EDSIG]'s Super-X section names Esprit build 1.9.4.3337 "with FEI microscope control 4.5". Whether that matches a Velox-era Talos G1 is UNVERIFIED. The owner keeps a "Talos F200X G1 Pre-Install Manual" in `NAS_Backup/02_methods/TEM/`.

## 2. Files written

### 2a. One `.dm4` per SI experiment holding every signal — VERIFIED for EELS and 4D, INFERRED for EDS

The owner's GMS SI saves are single documents named `NNN_STEM SI.dm4`, each with several image objects ([OWN]):

- **4D example** (`NAS_Backup/00_inbox/4DSTEM_170330/ROI_5/raw/SI data (7)/060_STEM SI.dm4`, 28.6 GB): thumbnail (DataType 23), `ADF Image (SI Survey)` 2048², `Diffraction SI` with dims [256,256,330,330], DataType 2 (float32), units [1/nm, 1/nm, µm, µm].
- **EELS example** (`NAS_Backup/01_projects/LMN_EM_General/EELS_TiO_2_ref_20250325/134_STEM SI.dm4`): thumbnail, `HAADF Image (SI Survey)`, `HAADF Image` [206,337], `EELS LL SI` [206,337,2048], `EELS HL SI` [206,337,2048], all float32, energy axis in eV.
- **EDS by analogy.** A simultaneous 4D+EDS run would add an EDS SI object [x, y, channels] in keV to the same document. INFERRED; no such file exists to check.
- **Derived products** are separate files, for example `(1) Diffraction of Diffraction SI.dm4` (Format "Diffraction"), and processed or MSA results (`Signal SI denoised…`, `PCA Analysis (100).dm4` holding Scores, Loadings and Eigenvalues) ([OWN]).
- **K2 IS** produces a separate extracted 4D file ([STEMx]:332-352). Linking that back to the EDS SI is UNVERIFIED.
- Gatan's own wording: "One sample, one microscope session, one data format" ([GORJI]).

### 2b. Data layout

- **Spectrum images** are stored [X, Y, E] with energy as the slowest dimension (dim 2), i.e. one energy plane after another. Evidence: the DM-script NMF example reads `nCh = StemSI.ImageGetDimensionSize(2)` ([PY]:2286), and the Python example says the NumPy view has shape (Z, Y, X), so a spectrum is `data[:, y, x]` ([PY]:1204-1237). NumPy sees DM dimensions reversed ([PY]:685-698). VERIFIED.
- **4D cubes.** The owner's 2023-2026 GMS files list the detector pair first and carry `Meta Data.Data Order Swapped = 1`. The 2018 `Si-SiGe.dm4` lists the scan pair first and has no such tag. This is the repo's own open item: `docs/dm4-format.md` §3.3 and `docs/open-items.md:183`. VERIFIED.

### 2c. `.dm4` versus `.dm5`

- dm5 support arrived with GMS 3.5.0 ([RN]:159). VERIFIED.
- dm5 is HDF5-based and "completely different from any other DM format" (NTU DM-format page, web). Gatan publishes a dm5 page (gatan.com/node/5170), which I could not fetch (429).
- RosettaSciIO reads only `.dm3`/`.dm4` and ignores `Data Order Swapped` (its docs plus GitHub `main` `_api.py`, web). VERIFIED.
- DM4 uses 8-byte lengths, so files beyond 2 GB are fine (NTU page, web; also `docs/dm4-format.md` §1.1).

### 2d. Tag groups that matter for a 4D+EDS importer

Paths are relative to `ImageList.N.ImageTags`. Status codes: **O** = seen in the owner's files ([OWN]); **R** = mapped by RosettaSciIO from real GMS EDS files ([RSCIIO]:600-611 and :1052-1080; same on GitHub `main`); **U** = unverified.

| Purpose | Tag | Status |
|---|---|---|
| Link all signals of one run | `Meta Data.Experiment keywords.1.Experiment ID` (e.g. `Spectrum Imaging_3/25/2025_4:33:23 PM`) is identical across the HAADF, EELS LL and EELS HL objects | O |
| Signal role | `Meta Data.Experiment keywords.2.Label` ∈ {Survey, Scan Signal, EELS, Diffraction}; EDS label U | O |
| Kind | `Meta Data.Format` ∈ {Image, Spectrum image, Diffraction image, Diffraction, PCA …}; `Meta Data.Signal` ∈ {DigiScan, EELS}; EDS = **`X-ray`** | O / R |
| Same grid for every signal | `SI.Acquisition.Spatial Sampling.{Width,Height} (pixels)`, `SI.Acquisition.Last pixel` (= W×H when complete; 108900 = 330² in file 060), `Start time`, `End time`, `Date` | O |
| Registration to survey | `SI.Acquisition.Survey Image.Unique Image ID` (4×uint32) plus `Spectrum Image Rect` (top, left, bottom, right in survey pixels) | O |
| Dwell | `SI.Acquisition.Pixel time (s)` | O |
| Sync mode | `SI.Acquisition.Pixel iterator` = `DigiScan (hardware-sync)` (58 objects) or `(software-sync)` (12) | O |
| Scan options | `SI.Acquisition.Scan Options.Scan sub-pixel` (0/1; 9 objects =1), `Continuous scan`, `Number of cycles`, `SI Application Mode.Name = 2D Array` | O |
| Drift-correction log | `SI.Acquisition.Artefact Correction.Spatial Drift.Drifts.k = "<pixel index>: (dx, dy)"`, `Periodicity` (10), `Units` ("row(s)") | O |
| Energy axis | `ImageData.Calibrations.Dimension.3.{Origin, Scale, Units}`; calibrated value = (i − Origin)·Scale, so offset = −Origin·Scale ([RSCIIO]:470-474). Owner EELS: LL Origin 200, Scale 0.3 eV → starts at −60 eV. EDS units `keV` ([RSCIIO]:506-508) | O / R |
| EDS detector | `EDS.Detector Info.Azimuthal angle`, `EDS.Detector Info.Elevation angle`, `EDS.Solid angle` | R |
| EDS timing | `EDS.Live time`, `EDS.Real time`, `EDS.Acquisition.Date` / `Start time`. Whether per-pixel live time exists is **U**. GMS does store per-pixel side arrays elsewhere, e.g. `EELS.Acquisition.Saturation fraction` (69,422 float32 values) | R / U / O |
| Take-off geometry | `Microscope Info.Stage Position.Stage Alpha/Beta` (e.g. α = 18.12° in file 060), `Microscope Info.Voltage` | O |
| Dual-EELS pairing | `EELS.Acquisition.Dual acquire sibling.Unique Image ID` | O |
| Channels, dispersion, time constant, detector type and window for EDS | exact tag names | U |

### 2e. Reader caveats

- **Data type.** Diffraction SI and EELS SI are written as float32, which costs 2-4× the space of raw counts ([OWN]).
- **Binning.** RosettaSciIO's docs warn that in some DM versions binned data store *averages*, not sums. For Poisson methods (espm/NMF), check that EDS counts are integers. Web, VERIFIED as RosettaSciIO's statement.
- **mac4DSTEM's `DM4Reader`.** `DM4Reader.swift:704-760` picks the first object with more than 2 non-singleton dimensions. A 3D object is accepted only if `Scan shape X/Y` tags exist (TitanX layout). So in a 4D+EDS document, an EDS or EELS SI should be skipped and the 4D cube chosen. INFERRED from reading the code; untested on such a file.

## 3. What GMS itself does with EDS, SI and 4D data

**EDS**
- GMS 3.0 rewrote EDS analysis: a new quantification engine, "MLLS peak-family fitting (peak deconvolution)", full background modelling, faster SI maps, and the same UI as EELS quantification ([RN]:422-427; [GS]:167-176). VERIFIED.
- The detector setup dialog holds the detector type and geometry (elevation from the detector's spec sheet), which quantification uses to model the spectrum and background. The Elemental Quantification palette produces quantitative results and **quantitative maps from SI**; more functions sit on the spectrum's right-click menu ([ELITE]:250-312). VERIFIED.
- Which quantification method (Cliff-Lorimer, k-factors, ζ, cross-sections) and whether there is an absorption or thickness correction: UNVERIFIED (help only).
- GMS 3.6.0 added "EDS Acquisition and Analysis – EDAX SEM Suite (470)" ([RN]:102). Web snippets put EDAX eZAF standardless quantification and Li-related palettes in DM 3.6. These appear to be SEM features. Web, UNVERIFIED for TEM.

**MSA**
- GMS 3.4 added a multivariate statistical analysis tool: one-click denoise, PCA, varimax (web snippet, gatan.com/node/4013).
- The owner's lab already uses it on EELS SI (PCA Scores, Loadings, Eigenvalues and "Varimax-recombined" files in [OWN]).
- Python NMF examples for EELS/EDS SIs ship in the manual ([PY]:1828ff, :2280ff).

**SI tools**
- Align SI By Peak, which aligns the direct beam in 4D ([STEMx]:302-306).
- Diffraction calibration from DigiScan and camera calibrations, with the default centre at [127,127] for a 256² pattern, refinable ([STEMx]:307-317).

**4D tools**
- "4D STEM Analysis" under Data Analysis ([STEMx]:175, :392).
- 2D strain mapping: U tool to mark the reference region, centre/u/v circles, disk template, sampling interval; outputs εuu, εvv, shear and rotation maps ([STEMx]:370-463). Strain mapping since GMS 3.2.0 ([RN]:323-325).
- Volume tools to extract from and rebin 4D data ([RN]:341-342; [STEMx]:466-470).
- DPC in STEMx Analysis since GMS 3.5.0 ([RN]:160).
- Virtual apertures and COM / cross-correlation / virtual-segment DPC ([GORJI]).
- **DM 3.62** (newer than the owner's 3.6.1, build 4719, 2024-09-03, [RN]:72) adds (web):
  - STEMx OIM template-matching orientation and phase maps (multiphase; image-quality, confidence and similarity maps; `.ang` export to EDAX OIM Analysis);
  - Survey Mapping, with live virtual aperture, DPC and EELS thickness;
  - Custom/sparse scan patterns;
  - STEMx Precession, listed as "under development" in [GORJI].

**Joint diffraction + EDS (web, [GORJI])**
- Gatan's only demonstrated joint use: linked EDS and 4D data where "orientation maps can be masked based on elemental mapping data" (an Au/SiO₂ example).
- For EELS + 4D (sequential), the 4D analysis finds crystallites and linked tools pull EELS from the same positions.
- No classification rule that uses EDS during indexing is described.

**Other**
- `Support/FEIGSI/SIAcquisition.tlb`, a COM type library. Its symbol names (listed with `strings`, nothing decompiled) suggest an `ISpectrumImaging` interface with EELS/EDS signals, SW/HW sync, frame cycles, `GetSpectrumArray(cube, pixel, n)`, `GetSIDimensionCalibration`, overscan and interrupt. Purpose (Thermo control of a Gatan SI) is UNVERIFIED.

## 4. Scripting access and export

**Python inside GMS**
- Embedded Python (Miniconda, venv `GMS_VENV_PYTHON`); GMS 3.6 uses Python 3.10 and NumPy 1.23.5 with OpenBLAS ([RN]:105; [PY]:147-163). Extra packages via `pip` into that venv; scikit-learn is the documented example ([PY]:378-418); the Metro manual mentions "Spectral analysis with HyperSpy" (:1743).
- `Py_Image.GetNumArray()` maps a NumPy view onto the image memory with dimensions reversed and C order required; `Py_TagGroup` behaves as a dict or list; the classes are Image, ImageDocument, Display, ROI, TagGroup, Camera, Microscope and DigiScan (`DS_CreateParameters` …); `DM.ExecuteScriptString` runs hybrid DM-script ([PY]:674-760, :882, :1705, :2400-2420). VERIFIED.

**Can the owner export cleanly?** Yes, in two ways.
1. The cleanest is to save SIs as **`.dm4`, not `.dm5`**. The file is already readable by ncempy, RosettaSciIO and mac4DSTEM's DM4Reader, and every linkage tag in §2d survives.
2. Alternatively, a short DM-Python script can write each SI object's `GetNumArray()` plus its `GetTagGroup()` dict to HDF5. This needs `h5py` installed into the venv, since only NumPy is preinstalled ([PY]:378-382). UNVERIFIED in practice.

Either route should keep EDS counts raw: no DM binning, given the averaging caveat in §2e.

## 5. Limitations, and ideas for the Spectroscopy room

**Limitations**
- **EELS needs a second pass.** EELS and 4D are mutually exclusive; only EDS can ride along with a 4D scan.
- **Licences and service work.** Hardware-synced EDS needs extra licences, cables and, for Super-X, a service-level install.
- **K2 IS splits the data.** The 4D cube lands on capture PCs and is extracted separately.
- **Files are large.** Float32 cubes run to tens of GB per scan.
- **Documentation.** The DM help and the dm5 specification are not public.
- **No published fusion.** GMS publishes nothing beyond masking and position-linked extraction.
- **Version.** The owner's 3.6.1 probably lacks the 3.62 tools (OIM, Survey Mapping). INFERRED from version numbers.

**Room ideas, each grounded in what GMS actually writes**
1. **Open a GMS `STEM SI` file as one experiment.** Group objects by `Experiment ID`; list survey, scan signals, Diffraction SI and EDS SI with roles taken from `Experiment keywords.2.Label`.
2. **Integrity line before analysis.** Show the grid match, `Last pixel` = W×H (flags an aborted scan), hardware vs software sync, sub-pixel on/off, cycles, and the drift log, which can be offered as a correction or at least shown.
3. **EDS metadata gate.** Elevation, azimuth, solid angle, live/real time, beam energy and stage tilt, read from tags. Anything missing is asked for, as GMS's detector setup dialog does, never defaulted silently.
4. **One linked cursor.** A probe pixel shows the diffraction pattern, the spectrum, and its position on the survey image (from `Spectrum Image Rect`).
5. **Masks both ways.** EDS map to orientation/phase-map mask (Gatan's demonstrated case), and 4D phase/grain/precipitate mask to a live-time-weighted pooled spectrum (approach E).
6. **Counts reality panel.** A histogram of counts per pixel, since a 10 ms 4D dwell typically gives about 0-10 X-ray counts.
7. **Sequential EELS runs.** Register them to the 4D run through the survey `Unique Image ID`, rect and drift log, not by assuming identical grids.

## 6. Unverified items to put to the owner

- Does the lab's GMS hold licences 700.LS.707.11.64.1 (EDS) and 700.LS.777.U3.64.1 (Hi-Speed SI), plus an Esprit `ExternControl` link to the Talos Super-X? Is the DigiScan clock cabled to the Bruker card?
- The exact EDS SI object name, data type, channel and dispersion tags, and whether per-pixel live time exists. The fastest way to settle all of these is one small 4D+EDS test acquisition saved as `.dm4`.
- Whether GMS can drive Super-X on a Talos G1 at all, and whether the lab will move to DM 3.62.