Velox 3.15 report: EDX handling, the .emd layout and 4D-STEM support, from the owner's installer

Sources are tagged as follows. All paths are under `<scratch>/edx/velox/`, written as `velox/...` below.
- [UM p.N]: `velox/files/app/docs/Velox/Velox 3.15 User Manual.pdf`. PN 1551926 Rev A, October 2024, 316 pages. The PDF page index equals the printed page number. Text copies are in `velox/txt/`.
- [RN p.N]: `velox/files/app/docs/Velox/Velox Release Notes 3.15.0.pdf`. PN 1551925.
- [JP p.N]: `Velox 2.12 User Manual-jp.pdf`. The 2020 manual, used only for history.
- [Tip X]: `velox/files/app/docs/velox/Tips/English/{Analytical,Imaging}/X.html`.
- [Q:file]: `velox/files/commonappdata/Thermo Scientific Velox/QuantificationParameters/Inactive/file`.
- [rsciio]: the locally installed RosettaSciIO 0.6, at `~/miniconda3/envs/temtemp/lib/python3.8/site-packages/rsciio/...`. This is not a Velox document.

## 0. What the installer actually contains

- **Wrong premise.** The .exe is not an Advanced-Installer/MSI wrapper. It is **Inno Setup 6.1.0 (unicode)**, with "Inno Setup Setup Data (6.1.0) (u)" in its header.
  - The embedded `2.msi` is a licence runtime (`{tmp}\Bergson B'Protected Runtime x64.msi`).
  - `3.exe` is the VC++ 14.36 redistributable.
  - All payload sits in one solid LZMA2 chunk of 495 MB.
- **How I extracted it.**
  - 7zz split out the parts.
  - Python only cut byte ranges. It wrapped the raw LZMA2 stream and the setup-0 header blocks in xz/lzma containers.
  - 7zz did all the decompression.
  - I parsed the Inno file and data tables to map names to offsets, then carved 110 files.
  - Nothing was executed, disassembled or decompiled. The name→offset map is `velox/filemap.json`.
- **Documentation present:**
  - User Manual 3.15 (316 pp).
  - Release Notes 3.15.0 (13 pp).
  - "What's new in 3.15" (6 slides, SmartCam/HDR only, nothing on EDS).
  - Velox 2.12 User Manual (Japanese, 209 pp).
  - 690 HTML "Tips" in 7 languages. I read the English ones: 28 Analytical, 40 Imaging.
- **Data files present:**
  - `EdgeEnergies_v1.csv` and `EdgeIntensities_v1.csv` (Z 1–99, IUPAC line names, plus `Ka_esc`/`Kb_esc` columns).
  - `K_Custom.csv`.
  - `Mac_Nist_LL.dat`.
  - `DetectorOverlayProperties.ini`.
  - A usage-telemetry schema (`DSAL_Config/VeloxInstrumentConfig.xml`).
  - COM side-by-side manifests (XML).
  - `Credits.txt`, which lists HDF5, Eigen, Qt, Qwt, zlib, libtiff, boost, pugixml and ffmpeg.
- **Absent, stated plainly:**
  - No EMD file-format specification.
  - No scripting/API documentation.
  - No CHM.
  - No Python.
- `ExternalControl.tlb` and the tools (BatchExport, BatchPrune, ExperimentConverter, SIConverter, EMDConverter, RemoteSI, VeloxConsole) are binaries only. I did not open them.

## 1. The Velox EDS workflow

### Acquisition [UM pp.199–224]

**Presets.** There are two fixed presets, View and Acquire [UM p.200]. Each records:
- Exposure time.
- Stop condition: Real time or Live time. Live time pauses during dead time; View is always Real time [UM p.201].
- Energy range. Spectra are **always 4096 channels**, so dispersion follows from the range; 20 and 40 keV are recommended [UM p.201].
- Shaping time: Optimized, High throughput or High resolution. Not available on Super-X G1 [UM p.201].
- "Blank beam when idle".

**Detector segments** [UM p.202]:
- **Super-X G1:** segments are toggled in the Detector Layout panel.
- **Dual-X:** segments are set in the preset.
- **Super-X G2:** each segment is **recorded as a separate stream**, so a segment can be dropped in post-processing.

**Supported detectors** [RN p.9]:
- Super-X G1 (not on Windows-10 microscopes), G2 and G2Lite.
- Dual-X.
- Single-X 100 mm² and 30 mm² (the latter is a side-entry Bruker 30).
- Ultra-X.

The Detector Layout panel shows count rate and dead time per Super-X/Dual-X sensor [UM p.50].

**Spectrum Image (SI)** [UM pp.209–210]:
- STEM detectors and EDS are recorded simultaneously per pixel.
- Multi-frame acquisition is **time-resolved**.
- Velox builds "virtual EDS frames" from the stream and integrates them into the data cube that all processing uses.

**SI preset** [UM pp.215–217]:
- Image size comes from the scan size or a drawn SI area.
- Dwell time: "20 µs or longer" is recommended, and overhead dominates below 10 µs.
- Auto stop after N frames, or run continuously.
- Drift compensation.
- "Optimize for periodic images", which suppresses periodic FFT features so cross-correlation does not lock onto the lattice.
- A display-only Dose field.
- Blank beam, and Close column valves.

**Drift correction** [UM pp.216, 218–220]:
- Cross-correlation is done per frame, using either the STEM reference frames or a separate Drift Measurement Area.
- The Drift Measurement Area is scanned at 1 µs dwell between frames. Rule: high-contrast, non-periodic features, close to the SI area but not overlapping it.
- Cross-correlation images can be exported.
- The telemetry schema enumerates drift types None, LBDC and FBDC (line-based / frame-based) [`velox/files/app/DSAL_Config/VeloxInstrumentConfig.xml`, DriftType_enum].

**Live quantification during acquisition** is limited [UM pp.221–222]:
- Maps must be ≤512×512.
- Only "int" mode.
- Default settings.
- Background correction off.

**EELS alongside EDS** [UM pp.222–224; RN p.13 VEL-43027]:
- EELS runs in Gatan DM and is **not stored in the .emd**.
- dm3/dm4 files are "not compatible with Velox".
- Limits: 262,144 px, 1000 spectra/s at 100 µs dwell.

### Element identification [UM pp.56–60]

The Periodic Table side panel has:
- **Auto ID.** It matches peaks to lines and switches off as soon as an element is chosen by hand.
- **To Spectrum / To SI**, which copy the selection.
- Four-state colour coding: detectable, identified, included, **"Deconvolution only"**.
  - A deconvolution-only element is fitted, so its overlap is subtracted, but it is excluded from at%/wt%.
- Per-element right-click options: "Lines used for intensity maps", "Displayed lines", "Family for quantification".

The Position Marker in a plot lists candidate elements at that energy [UM pp.238–239].

### Background model [UM pp.61–62, 263]

- **"Empirical":** a single 3-parameter Bethe–Heitler function fitted across the whole spectrum.
- **"Multi-polynomial":**
  - Polynomials are fitted separately to the ranges inside the background windows and the ranges outside them.
  - Order is 0 flat, 1 sloped or 2 parabolic.
  - This model always uses the windows.
- **Background windows** are Auto or manual.
  - Auto computes one set of windows for the summed spectra and recomputes when an ROI changes ("significant processing").
  - The windows are shared, but **the background and peak fit run per pixel**.
- **Tuning rule:** the Residual should look like noise inside the background windows [UM p.263].

### Peak deconvolution [UM p.230]

- Cliff–Lorimer (k-factor) quantification with absorption correction.
- Deconvolution is a **maximum-likelihood fit with non-negativity constraints**.
- Each **line family is fitted as a whole**.
- Default SI quantification is a "least square (Empirical) fit without Background Correction", called the fastest and the most reliable for sparse data [UM p.262]. The manual does not reconcile "least square" here with "maximum-likelihood" above.
- "Use optimized spectrum fit" + "Re-measure" [UM pp.63, 266–269]:
  - Re-fits dispersion, offset and electronic noise (the peak-width model) from the current spectrum.
  - It is not updated automatically.
  - Tune it on a simple spectrum, then save it in a Quantification Settings file.

### Quantification [UM pp.62–63, 230, 264–266]

**k-factors** are derived from an **ionization cross-section model**:
- **Brown-Powell:** empirical, the default.
- **Bote-Salvat:** theoretical; underestimates light elements.
- **Schreiber-Wims:** a Brown-Powell variant; better for transition metals and oxides.

**Errors.** Fit errors and at%/wt% errors are reported in the Experiment Log. A rule-of-thumb **20 % error on k-factors** is assumed; K-lines alone do better [UM p.266].

**Absorption correction:**
- Inputs: a tick box, "Sample thickness", and "Density". If density is not given, Velox estimates it from the composition.
- It accounts for the actual Super-X geometry, including which of the 4 segments are used, for single or summed spectra.
- It models stage-tilt shadowing, with detailed shadow profiles for the **Double-Tilt Super-X holder**.
- It does **not** correct sample self-shadowing such as grid bars. The workaround is to disable or exclude segments [UM p.230].
- Its effect is very limited below 20 nm thickness.
- There is **no fluorescence correction** [UM pp.264–265].
- Experiment conditions shown: HT, plus alpha/beta tilt [UM p.61].

**Not found anywhere in the manual:** zeta-factor, detector efficiency or window model, numeric elevation/azimuth input, and any PCA/multivariate method.

**Unverified hints from data files, undocumented in the manual:**
- `K_Custom.csv` [Q:K_Custom.csv]:
  - Column schema: `Z1,family1,Z2,family2,energy,K,Kerror`.
  - Rows are k-factors relative to Si K at 1.2e5 or 2.0e5 (consistent with HT in eV), e.g. `13,K,14,K,2.00E+05,1.027…`.
  - It sits in an "Inactive" folder.
- The COM manifest names `MeasuredKfactor(s)` and `CalculatedKfactor` [`velox/files/app/Fei.Imaging.Tem.manifest`] suggest measured-k-factor support.
- `Mac_Nist_LL.dat`: 100 element blocks of (energy eV, value). The Al block jumps from about 329 to about 4038 at about 1.56 keV, consistent with a NIST μ/ρ in cm²/g. Exact source unverified.
- `EdgeEnergies_v1.csv`: has Si escape-peak columns (Cu `Ka_esc`=6307 = Kα − 1.74 keV). It lists Li K-L3 = 54 eV. Whether Li is selectable in the UI is unverified.

### Maps, ROI, line profiles and filters

**Maps.** The Image Browser has a thumbnail per element plus a ColorMix overlay with a colour per map. It switches between four modes [UM p.39; Tip A0002]:
- **int**: raw integrated counts.
- **net**: background-corrected fitted model.
- **wt%**.
- **at%**: the histogram runs in fractions 0–1.

The SI metadata example has "Intensity scale 1.000 kg/kg" [UM p.295].

**ROI** [UM pp.231–232, 243–245]:
- Spectrum Integration rectangle or polygon on the ColorMix gives an Integrated Spectra plot.
- Several ROIs are overlaid, and a **Counts/s** y-axis normalises for ROI size.
- Plot tools: Range Marker (window statistics), Position Marker, Background Window [UM pp.237–240].

**Line scans.**
- No separate line-scan acquisition is described.
- The **Intensity Profile** averages counts per perpendicular slice, with area weighting for partly covered pixels [UM p.234]. Tip 53967-4 says it "integrates", which is a docs inconsistency.
- **Extract spectrum profile** gives a Spectrum Profile experiment with *integrated* counts, the SI pre-filter, and re-quantification [UM pp.271–273].

**Filters** [UM pp.64–68, 249–258]:
- **Pre-filter** acts on spectra before quantification.
  - Average (kernel ±2 or any integer, even sizes allowed) or Gaussian (σ).
  - Counts are redistributed and the total is conserved.
- A **Counts indicator** compares recorded counts with the "optimal" counts, and a **recommended Average kernel** is applied with "Use". It may mislead when the ROI has large empty areas.
- **Post-filter** acts on maps only: Average (odd sizes only), Gaussian, or Radial Wiener (highest frequency, edge smoothing).
- Kernel-choice recipes: grow a 1×1 ROI until the spectrum or at% stabilises.
- No other denoising is described.

**Frames** [UM pp.81, 260–262; Tips 53967-14/15]:
- Start/End frame trimming, in **int** view only.
- "Reduce File Size" flattens the file, drops time resolution, and can keep the original.
- With G1, Dual-X and Single-X, the EDS can shift relative to the STEM reference.

### Reproducibility and output [UM pp.25–27, 83–87, 273–277; Tips A0005/A0006]

- Element and Quantification Settings files, kept in a fixed folder.
- "Export Quantification Details" writes 2 CSVs: composition, and line intensities.
- Licensed Batch Processing re-quantifies SI files from one settings file.
- Plot export: TXT, CSV, EMSA/MAS.
- Cube export: LiSPIX `.raw/.rpl` (spectra-per-pixel, image-per-energy-bin, Pathfinder), 16/32-bit TIFF, MRC2014.
- The MRC extended header carries EDX map fields: Element (16 chars), energy interval lower/higher (Float64), Method (Int32) [UM p.312].

## 2. What goes into .emd for EDX

**From the Velox docs.** They say only this much:
- .emd is a "proprietary container" holding data, processing results and the Experiment log [UM p.75].
- The tip says data are stored "in simple raw format inside emd" [Tip Imaging/i0004].
- HDF5 is a bundled library [`velox/files/app/Credits.txt`].
- Files from Velox ≥2.0 open; older ones are auto-converted with a `.bkp` copy; there is no forward compatibility [RN p.10].
- The SI properties list Dispersion, Offset (eV), Shaping time, per-segment Enabled/Azimuth, and input/output count rate. Stage tilt and holder type are listed too [UM pp.295–299].

The docs give **no** HDF5 groups, JSON keys or frame table.

**From RosettaSciIO 0.6** (reverse-engineered, not Thermo documentation):
- `/Version` holds a JSON `version` [rsciio/emd/_emd_velox.py:123].
- `/Data/{Image,Spectrum,SpectrumImage,SpectrumStream}/<UUID>/` holds `Data` plus a `Metadata` dataset. That dataset is a uint8 array, and column 0 is UTF-8 JSON [:172–186; rsciio/utils/hdf5.py:162–165].
- `/Displays`, `/Operations` (before v11), `/SharedProperties` (v11+) and `/Features` [:127–133].
- `/Presentation/Displays/ImageDisplay` (before v11), which maps map UUIDs to element labels [:494–518].

**The stream:**
- `AcquisitionSettings` JSON holds `bincount` and `StreamEncoding` [:894, 901].
- The data are uint16 events: `65535` means next pixel, and any other value is a channel count [:872–879; fei_stream_readers.py:55–107].
- The frame count comes from `SpectrumImageSettings.endFramePosition`, or else from counting 65535 markers [:545–546, 915].
- A `FrameLocationTable` exists but rsciio does not use it [:103].
- One stream per segment is consistent with G2; rsciio has `sum_EDS_detectors` [:578–595].

**Calibration and metadata keys:**
- `Detectors.Detector-N.{DetectorName, Dispersion, OffsetEnergy}` in eV [:700–708].
- `ElevationAngle`, `AzimuthAngle`, `LiveTime`, `RealTime`, `Gain`, `Offset` [:809–838].
- `Optics.AccelerationVoltage`, `Stage.AlphaTilt/BetaTilt` (radians), `BinaryResult.{PixelSize,Offset,PixelUnitX,DetectorIndex}` [:320, 476, 769–790].
- Selected elements: `SharedProperties.EDSSpectrumQuantificationSettings.elementSelection` (v11+), or `Operations.ImageQuantificationOperation` [:846–848].

**Pruned or Reduce-File-Size files** keep an empty `SpectrumStream`, and the cube sits in a **proprietary compressed `SpectrumImage` that rsciio cannot read** [:61–70, 562–573].
- The `ICompressedSpectrumImage` interface name appears in [`velox/files/app/Fei.Imaging.Tem.manifest`].
- **Practical consequence:** ask users not to prune if the data are for us.
- Also present in the installer: `SpectrumBcfWriter` and `BrukerDataGeneration64.dll`. These are names only; a Bruker .bcf writer is unverified.

## 3. 4D-STEM and 4D-STEM + EDX

**Requirements** [UM pp.225–229, 147]:
- 4D-STEM is a licensed extension of SI.
- It needs a **Ceta camera with Speed Enhancement (Ceta-2)** and a hardware sync link.
- EDS is optional. In 2.12 it was required [JP p.149].
- SI dwell time overrides camera exposure, and the camera acquisition (sub-)area sets the minimum dwell.
- Line-based drift compensation needs Panther STEM BF-S/DF-S + CAB/A scan engine + recent TEM server [UM p.228].

**Storage, per acquisition** [UM p.229; JP pp.149–150]:
- STEM reference image → .emd.
- **Diffraction patterns → one `.mrc` stack on the Storage Server / Offloading PC.**
  - MRC2014 with FEI1/FEI2 per-frame extended header [UM pp.301–316].
  - That header includes scan rotation, diffraction-pattern rotation, scan mode (raster/serpentine) and beam-centre pixel.
  - Ceta-2 data are 16-bit signed integers [UM p.316].
- EDS → a **single-frame SI in the .emd**.

**Correlation is not done for you.** Acquisition is synchronised, but stored SI and patterns are "not time resolved", and correlating them is left to the user as a manual task [UM p.229]. The release notes list "EDS + 4D-STEM" as a feature [RN p.11].

**Virtual detectors** [UM pp.152–154]:
- Up to 8 annular or circular detectors on Ceta-2, defined in px or mrad.
- Their outputs and definitions are stored in the EMD.

**Linked MRC paths** (High-Speed Series): the .emd stores the full path, which cannot be updated if the files move [UM p.102]. Whether this also applies to 4D-STEM .mrc stacks is unverified.

**Other detectors:**
- **EMPAD: not mentioned anywhere.**
- Panther is only the segmented STEM BF-S/DF-S detectors.
- Falcon is not supported in STEM [UM p.147].
- Velox can open .mrc files [UM p.75].

## 4. UI patterns worth learning, and stated limitations

**UI patterns:**
- Spectrum, Background, Modeled and Residual graphs, toggled from the legend. The residual is the diagnostic for both the background and the fit.
- The four-state periodic table, including "deconvolution only".
- int / net / wt% / at% mode switch on the map thumbnails, plus the ColorMix.
- ROI spectra in counts/s.
- A count-based recommended pre-filter kernel, applied with a single "Use" button.
- Tuning on a spectrum, then "Apply to SI".
- Settings files and batch re-quantification.
- A frame-range trim backed by time-resolved streams.
- A per-segment spectra plot with segment exclusion.
- An Experiment Log carrying fit errors.

**Stated limitations:**
- Data-quality warnings are explicitly "not proof of quality" [UM p.65].
- Absorption correction ignores self-shadowing and fluorescence.
- 20 % k-factor uncertainty.
- Bote-Salvat bias for light elements.
- Auto background is costly; large pre-filter kernels are costly.
- No frame trim after Reduce File Size.
- EELS is not in the .emd.
- 4D-STEM correlation is manual.
- Windows only (Offline needs Windows 10/11, 16 GB RAM) [RN p.3].
- Open known issues [RN pp.12–13]:
  - 16-bit TIFF export of maps is broken (VEL-46411).
  - Radial Wiener uses the wrong frequencies on rectangular maps (VEL-44517).
  - SI dose can be wrong when STEM frames drop (VEL-44932).

**Docs contradict themselves:**
- Which reference frame is displayed: the last (Tip 53967-14; UM p.260) or the first virtual EDS frame (Tip 53967-15).
- "Least square" vs "maximum likelihood" fitting.

Other scratch outputs: carved files are in `velox/files/`; the raw blob is `velox/blob/inno-data` (495 MB, kept for further carving).