# EDX file formats for a Swift reader: what RosettaSciIO does, what the repo's readers already cover, and what GMS STEMx writes

**Date:** 2026-10-05.

**Scratch location:** `<scratch>/edx/` (written as `$S` below).

**Clone:** RosettaSciIO, shallow, at `$S/rsciio`, commit `049e7d7070e84779b499adaf3295beee9facb004` (2026-10-05). All `rsciio/...` line numbers refer to that commit.

**My scripts:** `$S/formats/` (`dmdump.py`, `velox_*.py`). I wrote nothing to the repo.

**Run checks:** these used another agent's scratch venv (`$S/venv`: rsciio 0.14.0, hyperspy 2.4.0, exspy 2.4.0). That venv has no `sparse` module, so I put a 4-line stub of my own in `$S/formats/stub`. It has no numba either, so rsciio ran its pure-Python fallback. The Velox code paths I relied on are the same in 0.14.0 and in main; I checked the matching lines in both.

**Download to disclose:** I fetched one public PDF with curl without asking first: a Gatan 4D-STEM talk (Gorji, Warwick open day), 4.4 MB, saved to `$S/formats/web/gorji.pdf` and only read. Gatan's own web pages (the dm5 documentation and the STEMx product page) answered HTTP 429 with a bot challenge, which I did not try to get past.

**Other agents' outputs I relied on:** the GMS 3.6.1 documentation they extracted (`$S/gms/txt/...`, `$S/gms/ReleaseNotes.txt`) and their header-only scan of the owner's drives (`$S/ownerdata/dm_summary.txt`, `edx_unique.tsv`). I treated both as data.

---

## 0. Bottom line

1. **GMS STEMx 4D-STEM plus synchronous EDS most likely lands in one `NNN_STEM SI.dm4`.** That file would hold several image objects: the survey image, an ADF image, the 4D "Diffraction SI", and a 3D EDS spectrum image. This is **inferred, not seen**: no public or owner file with both signals exists.
   - What supports it:
     - The owner's own GMS SI files already bundle every SI signal into one `.dm4`: survey, "Diffraction SI", and for EELS also the HAADF image plus "EELS LL SI" and "EELS HL SI" (`$S/ownerdata/dm_summary.txt`).
     - Gatan's STEMx manual says diffraction imaging is one signal of the STEM SI tool. Signals that do not block the beam (EDS does not) can be recorded at the same time, and EELS and CBED cannot (`$S/gms/txt/1020.40004_V002_STEMx System User Manual.txt`, lines ~131 and 240–244).
     - Gatan's talk says the tool does simultaneous 4D STEM + EDS but only sequential 4D STEM + EELS (`$S/formats/web/gorji.txt`, ~473–497).
   - Exceptions:
     - `.dm5` (HDF5-based) is an alternative save format in GMS ≥ 3.5.0 (`$S/gms/ReleaseNotes.txt:148-159`).
     - K2 IS / K3 IS data are written as raw binary on the capture PC and must be extracted. In-situ K3 data are a `.dm5` "director" file plus `.raw`, `.raw_1`, … files (`epsic_tools/toolbox/load_k3_data.py`; rsciio issue #255).
   - **To settle it:** one short 4D + EDS test acquisition on the owner's GMS microscope, saved once as `.dm4` and once as `.dm5`.
2. **The owner's existing EDX data are Velox `.emd` files from a Talos F200X** (104 of 110 files in `edx_unique.tsv`). His 4D-STEM data are GMS `.dm4` from a "FEI Tecnai Remote TCPIP" microscope with `Acquisition.Device.Name = GIF`.
   - So today's 4D + EDX pairs (for example sample CA_DA_170330) are **two instruments and two sessions**. Joint analysis means registration, as ROADMAP.md:78-80 already anticipates, not a shared scan grid.
3. **The format the owner actually has (Velox SpectrumStream) has five reader-level traps in rsciio, four confirmed by running it:**
   - **Wrong shape:** the SI shape is taken from whichever image was read last. In `example_velox_EELS_EDS.emd` the 16×20 SI comes out as 128×128 with all counts in rows 0–2.
   - **Detector metadata never loaded:** for any SI or spectrum, elevation, azimuth and live/real time are not read. exspy's defaults (35°, 0°, None) are used instead; the file says 18°.
   - **Zero-energy events not separated:** 82–100 % of all stream events in the public test files sit within ±150 eV of 0 eV.
   - **Last partial frame not flagged:** a stopped acquisition leaves its first pixels with one extra frame of dose.
   - **Live-time column ambiguity** (from reading the code and the metadata, not run): only metadata column 0 is read.
4. **What the repo readers already give:**
   - `DM4Reader` already has the DM tag walk, the mmap, and the disk-liveness guard.
   - `H5Reader` already has the dlopen'd HDF5, the link walk, and string-dataset reads.
   - Missing: a spectrum-cube protocol (not `FourDDataSource`), choosing an object by its `Meta Data` tags rather than by rank, energy-slowest layout handling, the Velox event-stream decoder, a sparse store, and a few HDF5 native types.
   - **Estimate for a first usable reader set (MSA + `.hspy` + DM EDS + Velox stream): about 8–13 days.**

---

## 1. GMS STEMx 4D-STEM with synchronous EDS

| Question | Finding | Status |
|---|---|---|
| How is it acquired? | Through the STEM SI palette. CBED is one SI signal. "Only one signal that intercepts the primary beam", so EELS and CBED are mutually exclusive and EDS can run alongside (STEMx manual, lines ~234–244, 294) | documented |
| Simultaneous or sequential? | 4D + EDS simultaneous; 4D + EELS sequential (Gatan talk, `gorji.txt` ~473–481). Gatan also shows orientation maps masked by EDS maps (~494–497), which is approach "A/B-lite" | documented (marketing slides) |
| One file or two? | Owner's GMS SIs: one `.dm4` per SI with all signals as separate ImageList objects. Example: `134_STEM SI.dm4` holds survey, HAADF Image, EELS LL SI and EELS HL SI; `055_STEM SI.dm4` holds survey and a 256×256×256×256 float32 Diffraction SI (`dm_summary.txt`) | measured on owner files; **4D + EDS in one file is inferred, unverified** |
| `.dm4`, `.dm5` or raw? | OneView IS / GIF: cube held in memory, saved in DM format (manual 3.1–3.2, with memory warnings at ~234). K2 IS: binary on the capture PC, extracted to a DM 4D cube through the Data Manager (~325–352). `.dm5` exists from GMS 3.5.0 (ReleaseNotes 148–159). K3 IS in-situ: dm5 director + `.raw`, `.raw_N` (epsic_tools, written with Liam Spillane of Gatan). GIF Continuum multi-frame: `.dm4` + linked `.RAW` files capped at about 10 GB (rsciio #255) | documented; the owner uses single `.dm4` files of 17–29 GB |
| Owner's 4D object tags | `Meta Data.Format = "Diffraction image"`, `Meta Data.Data Order Swapped = 1`, device GIF, pixel times 0.01–0.05 s (`dm_summary.txt` / `dm_scan.jsonl`) | measured, header-only |
| EDS vendors GMS can drive | JEOL, EDAX (OEM API from GMS 3.4.3), Bruker Esprit, Thermo Noran, Oxford (`$S/gms/txt/EDS Acquisition Installation Guide.txt:70-91, 296-301`). The vendor's own header can be embedded: the rsciio EDS `.dm3` carries a Bruker `TRTSpectrum` XML blob in `ImageTags.EDS.Spectrometer Meta Data.Data` (dumped in `$S/formats/eds_spectrum_dm3_tags.txt`) | documented; **which EDS the owner's Tecnai has, and whether it is integrated into GMS: unverified** |
| Public 4D + EDS sample files | **None in vendor format.** Closest: Zenodo 14859606, "Correlative 4D-STEM & STEM-EDS clustering workflow" (CC-BY-4.0, 2025): `SEND.hspy` 102.8 MB + `EDS-100.0_electrons_per_pixel.hspy` 0.6 MB (HyperSpy HDF5, probably simulated; unverified). St4DeM (Zenodo 7521571 / 12699952) records EDS **after** the 4D scan over the same ROI (arXiv 2504.19762), in a 38 GB rar | Zenodo API, 2026-10-05 |

---

## 2. Per format

### 2.1 Gatan DM3/DM4: EDS spectrum and spectrum image (priority: high)

**Structure** (rsciio `digitalmicrograph/_api.py`; the repo's `docs/dm4-format.md`)
- Header is big-endian:
  - version (3 or 4; anything else is refused at `:75-92`),
  - root length (4 bytes in DM3, 8 in DM4),
  - byte-order flag.
- Tag values use the file's byte order.
- Tag tree: group or data entries; data entries carry a `%%%%` marker, an info array, then the payload. Types: simple, string (18), struct (15), array (20), and arrays of structs, strings or arrays (`:94-207`).
- Images sit under `ImageList.<n>`. Thumbnails are listed under `Thumbnails.<k>.ImageIndex` and are excluded (`:425-447`).
- Each image has:
  - `ImageData`: `Data` (the blob), `DataType`, `Dimensions.<k>` (fastest first), `Calibrations.Dimension.<k>.{Origin, Scale, Units}`,
  - `ImageTags`.

**How rsciio recognises an EDS spectrum image**
- **Type:** `ImageTags.Meta Data.Signal == "X-ray"` → `EDS_TEM` (`:600-614`).
- **SI:** `Meta Data.Format == "Spectrum image"`, or an Orsay `ImageTags.spim` group, with more than 2 dimensions → converted to a spectrum signal (`:543-554`).
- **Axis names:** the energy axis is named "Energy" only when its units are "keV" (`:507-509`).
- **Calibration:** the numpy shape is the DM `Dimensions` reversed (`:456-460`). Axis offset = −Origin × Scale, because Origin is a channel index, not keV (`:469-475`).
  - Measured on `test-EDS_spectrum.dm3`: Origin 95.6, Scale 0.005 keV → offset −0.478 keV (HyperSpy run, 2026-10-05).

**EDS tags** (actual tag names from `$S/formats/eds_spectrum_dm3_tags.txt`)
- Acquisition:
  - `EDS.Live time` 3.806 and `EDS.Real time` 4.233,
  - `EDS.Acquisition.{Date, Start time, End time, Exposure (s), Dispersion (eV), Channels, Continuous Mode, LiveTime multiplier}`.
- `EDS.Detector Info.{Azimuthal angle 45, Elevation angle 18, Solid angle 0.7, Incidence angle, Stage tilt, Detector type "SIUTW", Active layer, Dead layer, Gold layer, Window thickness, Window type, Fano 0.1, Zero fwhm 0.08}`.
- `Microscope Info.Voltage` (in V), `Meta Data.{Format, Signal, Acquisition Mode}`.
- `EDS.Spectrometer Meta Data.Data`: a byte array holding the vendor XML.
- rsciio maps live time, real time, azimuth and elevation (`:1073-1105`).
- **rsciio misses the solid angle:** it looks for `EDS.Solid_angle` while the file has `EDS.Detector Info.Solid angle`. The HyperSpy run confirms it is not loaded; it matters for ζ-factor and cross-section quantification.
- `energy_resolution_MnKa = 130` is exspy's default, not a value from the file.
- **Live-time meaning differs by vendor.** GMS and AZtec: per SI; Velox: per frame. The value can also be nonsense per pixel (hyperspy issues #2362 and #2534; comments by ericpre and TomSlater, 2020).

**Data layout of a 3D SI**
- Dimensions are `[x, y, E]`, fastest first, so **energy is the slowest axis**: each energy channel is one contiguous x·y plane.
  - Measured on `EELS_SI.dm4` (2×2×2048 float32): the mean absolute difference between neighbouring values drops at lag 4 = nx·ny (46 against about 82) and again at lag 8.
  - LiberTEM's DM reader agrees: it treats 3D SIs as "F-ordered" (`dm_single.py:266-272`).
- The owner's EELS SIs show the same pattern (`[206, 337, 2048]` …).
- DM5 readers reverse the dimensions the same way (Nion `DM5IOHandler.py:55-110`).
- **Assumed, not seen, for EDS SIs.**

**Decoding in plain words**
1. Walk the tag tree.
2. For every ImageList object that is not a thumbnail, read `Meta Data.Format` and `Signal`:
   - Format = "Diffraction image" → the 4D cube.
   - Format = "Spectrum image" with Signal = "X-ray" → the EDS SI.
3. Memory-map the `Data` blob at its offset, with dtype from `DataType`.
4. A spectrum is a strided gather with stride nx·ny·element size. An energy-window map is a contiguous sum over planes, which makes elemental maps cheap.
5. For per-pixel work (fitting, PCA/NMF), do a blocked transpose once into pixel-major order.
6. **Optional, recommended:** at low counts (0–10 per pixel), convert to a sparse per-pixel CSR form in a single pass.

**Edge cases**
- **Selecting by rank is wrong.** `DM4Reader.locateDatacube` takes the first data array with more than 2 non-singleton dimensions (`DM4Reader.swift:707-797`). A 3D EDS SI only passes if some tag anywhere contains "Scan shape X/Y": `scanShape` searches the whole file, not the object (`:878-881`). It would then be misread as a TitanX 3D stack. Select by `Meta Data` instead.
- `Data Order Swapped` is present in the owner's 4D files and not honoured (an open item, `docs/dm4-format.md:206`). Its meaning for SIs is unknown, so refuse when it is set on an SI until it has been measured.
- Units may be "eV" rather than "keV"; normalise to keV.
- Possible differences between the EDS SI and the 4D cube: binning, cropping, drift correction (`SI.Acquisition.Artefact Correction…`), sub-pixel scanning. Check that (x, y) shape and calibration are identical before treating the grids as the same.
- Some GMS versions store the **average** of binned channels or pixels instead of the sum (rsciio `digitalmicrograph.rst:19-27`), which breaks Poisson statistics.
- `DataType` 4 is unsupported in both readers; big-endian files are refused by `DM4Reader` and accepted by rsciio.
- **Timing between EDS and camera pixels:** a pixel offset between the EDS pixel stream and the camera frames is possible. Unverified; test on a sharp edge.

**Test files** (rsciio `tests/data/digitalmicrograph/`, present in the clone; hashes in `tests/registry.txt`)

| File | Size (bytes) | Content |
|---|---|---|
| `1D/test-EDS_spectrum.dm3` | 350,908 | EDS spectrum, Bruker XML blob |
| `3D/EELS_SI.dm4` | 340,075 | 3D SI |
| `2D/test-MonoCL_spectrum-SI.dm4` | 412,775 | CL SI |
| `2D/test-MonarcCL_spectrum-SI.dm4` | 273,314 | CL SI |
| `2D/multi_signal.dm3` | 689,992 | several signals in one file |

- **There is no public GMS EDS SI file.** Zenodo 8403583 (CC-BY) has dm4 EELS SIs (5–56 MB) and Bruker `.bcf` EDS maps.

**Effort:** 2–4 days for the EDS SI and spectrum path, plus 1–2 days for the multi-object API (4D + EDS from one file, grid-identity check). **Risk:** medium, because there is no real EDS SI fixture until the owner records one.

### 2.2 Thermo Fisher Velox EMD: EDS SpectrumStream (priority: highest, it is the owner's data)

**Structure**
- HDF5 file whose root dataset `Version` is a variable-length JSON string `{"version": "4"…"13", "format": "Velox"}` (`emd/_api.py:76-106`).
- Groups under `Data/`: `Image/<uuid>`, `Spectrum/<uuid>`, `SpectrumImage/<uuid>`, `SpectrumStream/<uuid>`, `EelsSpectrumImage/<uuid>`, `Text`.
- Every dataset group has a `Metadata` dataset of shape (60000, nFrames) uint8, holding NUL-padded UTF-8 JSON with **one column per frame**. rsciio only reads column 0 (`utils/hdf5.py:170-174`).
- Measured layouts, my dumps (`$S/formats/velox_tree.py`, `velox_flt.py`):
  - `SpectrumStream/<uuid>/Data`: (N, 1) uint16, chunked (8192, 1), uncompressed in every test file.
  - `.../AcquisitionSettings`: variable-length JSON with `bincount` "4096", `StreamEncoding` "uint16", `RasterScanDefinition`.
  - `.../FrameLocationTable`: (nFrames, 1) uint64, in files of version ≥ 6.
  - `SpectrumImage/<uuid>/SpectrumImageSettings`: JSON with `startFramePosition` and `endFramePosition`.
  - `SpectrumImage/<uuid>/Data`: uint8 bytes of a proprietary compressed cube. Unreadable: FEI described it as not easy to decode (`_emd_velox.py:1046-1053`), and "pruned" files contain only this (`:109-118`).
  - `Image/<uuid>/Data`: (y, x, frames), one chunk per frame.
  - `Spectrum/<uuid>/Data`: (4096, 1) uint32, one per detector.

**Stream encoding in plain words** (`utils/_fei_stream_readers.py:264-317`)
1. The stream is a list of uint16 values. Each value below 65535 is one detected X-ray: it adds 1 to that energy channel of the current pixel.
2. 65535 means the current pixel is finished; move to the next pixel in row-major raster order.
3. Frames are implicit: after ny·nx markers the next value starts the next frame.
4. **FrameLocationTable[j]** is the stream index where frame j starts. I verified this: it equals the position just after the (ny·nx·j)-th marker in the "Test SI 16x16" v11 file and the "4detectors_2frames" v6 file. It allows reading frames i..j directly; rsciio does not use it (TODO at `:151`).
5. Energy of channel k: OffsetEnergy + k × Dispersion, both in eV, taken from the per-stream `Metadata` → `Detectors[*]` entry whose `DetectorName` contains `BinaryResult.Detector` (`:866-881`).
   - Test files: 10 eV/ch with −250 eV, or 5 eV/ch with −1000 eV, or 2 eV/ch.
6. Super-X gives 4 streams (SuperXG21–24) and UltraX gives 6 (UltraX1–6). rsciio adds them channel by channel and never checks that their calibrations match (`:637-655`).
7. Total counts = stream length − markers. For the 4-detector file, 865,748 − 512 = 865,236, which matches rsciio's asserted per-detector sum.

**Edge cases** (all measured on the 7 public files unless marked)
- **SI shape.** The scan size `RasterScanDefinition`/`ScanSize` (128×128) is the full raster, not the SI. The true SI shape is ScanSize × (`ScanArea` right−left, bottom−top): 16×16, 16×20, 50×10 all reproduce.
  - rsciio instead takes the shape from the **last image read** (`_emd_velox.py:335`).
  - **Confirmed by running:** `example_velox_EELS_EDS.emd` loads as (128, 128, 4096) with counts only in rows 0–2. The stream really holds 320 pixels (319 markers, ScanArea → 16×20). The rsciio test `test_velox_load_EELS_EDS` asserts the 128×128 shape, so the mistake is built into the test.
- **The trailing marker varies.** v6/v11 streams end with 65535. Some v4 streams have trailing values after the last expected marker: 72 values in the 10×50 file, which rsciio drops.
  - **Incomplete last frame:** `fei_emd_si.emd` has 1273 markers against 5×256 = 1280. Pixels 0–248 got 5 frames and the rest 4. rsciio sums them without flagging it: mean counts per pixel 25.7 vs 22.0, ratio 1.17 on only 6 pixels, which fits 5/4 but does not prove it.
  - **Swift should return a per-pixel frame count, or drop partial frames by default.**
- **Zero-energy events:** 82–100 % of all events lie within ±150 eV of 0 eV (`velox_zeropeak.py`: 99.5 % in Test SI, 92.5 % in the 4-detector file, 82 % in the 10×50 file).
  - That is presumably the detector's zero/strobe reference peak; interpretation unverified.
  - Event-count statistics therefore **overstate real X-rays by up to an order of magnitude**.
  - Keep a separate per-pixel zero-peak count; it may also serve as a per-pixel live-time proxy, which sem-geologist proposed for Bruker in hyperspy #2534. Unverified.
- **Detector metadata is not loaded at all for spectra or SIs** (confirmed by running): `DetectorMetadata` is only attached to images (`:447-450`). Result: `elevation_angle` 35.0 and `azimuth_angle` 0.0 (exspy defaults), `live_time`/`real_time` None.
  - The file has ElevationAngle 0.314 rad = 18° and per-detector AzimuthAngle 45°, 135°, 225°, 315° in radians.
  - Even where the mapping does run, elevation is copied without converting radians to degrees, while azimuth is converted (`:978-981` vs `:996-999`).
  - A port must read these itself and convert units.
- **Per-frame metadata columns mean different things in different files.**
  - Test SI v11: cumulative (RealTime 0.256 → 0.512 s = 2 × 256 px × 1 ms).
  - 4-detector v6: column 0 = 0.031 s and the last column = 32.768 s = 2 × FrameTime.
  - `fei_emd_si` v4: roughly per-frame values that do not match dwell × pixels.
  - **Never treat column 0 as the total.** Compute real time = dwell × pixels × frames and report what the file says next to it.
- **Possible overflow:** rsciio's dense array uses `StreamEncoding` uint16, so summing frames and detectors can wrap past 65535 in a single pixel and channel. This follows from the code; I did not trigger it on real data. **Accumulate in UInt32.**

**Memory and time cost in rsciio**
- The whole stream is read into RAM even when `lazy=True` (`:1081`). Its documentation admits that SIs larger than RAM cannot be read (`emd.rst:74-78`).
- The dense result is ny × nx × 4096 × 2 bytes, times the frame count if frames are kept separate.
- Owner's largest files, from the scan's stream lengths (one detector stream each, header-only):
  - `CA_DA_170330_EDX.emd`: 1800×1800 pixels, 480 frames, stream 1.59 G values (3.2 GB). Markers 1.555 G, events about 35 M. Dense cube 26.5 GB in uint16.
  - `SI HAADF 1555.emd`: 8.6 M events among 667 M stream values (1.3 %).
- Across 103 of the owner's streams the median is about 11 events per pixel per stream and about 0.13 per pixel per frame, **zero peak included**. Real X-rays are probably far fewer.
- **For Swift:** decode in blocks (for example 64 M values) with a state machine that carries pixel index and frame number across blocks, into a CSR store: per-pixel offsets (UInt64), channel (UInt16), count (UInt32).
  - Store size is bounded by the event count, e.g. ≤ 35 M entries instead of 26.5 GB dense.
  - Decode should be I/O-bound at a few seconds for 3 GB. **Estimate, not measured.**

**Test files**
- In the rsciio clone, `tests/data/emd/`:
  - `fei_emd_files.zip` (9.09 MB): v4 SIs 16×16×5 frames and 10×50×10/20 frames, the 2-frame 4-detector v6 file, and reference `.npy` arrays of unknown origin.
  - `velox_emd_version11.zip` (0.15 MB): 16×16, 2 frames, 4 detectors, plus a pruned "ReducedData" file.
  - `velox_emd_v11_elementSelection.zip` (68 KB).
  - `velox_EELS_EDS.zip` (1.5 MB): v13, UltraX with 6 streams, plus 3 EELS SIs.
- Owner: 107 of 110 Velox files have a stream, according to the other agent's scan.

**Effort:** 4–7 days. That covers moving `HDF5Library` out of its private scope, adding native uint8/uint16/uint64 types, column hyperslab reads of the JSON metadata, the decoder, frame selection through the FrameLocationTable, per-detector and summed outputs, the zero-peak map, and metadata with radian conversion. **Risk:** medium. The vendor does not document the format, but the decoding rule is simple and verifiable against both the public files and the owner's 107 streams.

### 2.3 Gatan DM5 (HDF5): only if a test acquisition shows GMS writes it (priority: conditional)

**Structure** (rsciio PR #315, open and unmerged, `CSSFrancis/rosettasciio@06ea3141`, copy in `$S/formats/dm5pr/`; Nion `DM5IOHandler.py`, Apache-2.0; ePSIC `load_k3_data.py`)
- Root groups: `ImageList/[i]`, `DocumentObjectList/[0]`, `ImageSourceList/[k]`, `Thumbnails`, `Image Behavior`.
- Each image: `ImageList/[i]/ImageData/Data` (a dataset whose dimensions are the DM dimensions reversed, so the same memory layout as DM4), `Dimensions` stored as attributes `[k]`, `Calibrations/Dimension/[k]` attributes `Origin`/`Scale`/`Units`, and `ImageTags` as nested groups whose leaf values are **attributes**.
- Which image is shown is found from `DocumentObjectList/[0].ImageSource` → `ImageSourceList/[n].ImageRef`, with `ClassName` values such as `ImageSource:4DSummed` or `:Summed`.

**Edge cases**
- Attributes are sometimes fixed-length NUL-terminated ASCII and sometimes empty (mkuehbach, rsciio #315, 2025-11-25).
- `Origin` is used directly as the offset in the PR but as −Origin × Scale in DM4. Unverified which is right.
- Possible blosc compression: the PR imports `hdf5plugin`. Unverified.
- In-situ K3 data put the frames in external `.raw` files.

**Test files:** none public that I could find. The owner has 0 `.dm5` files (`find_names.txt`).

**Effort:** 2–4 days. Needs attribute iteration (`H5Aiterate2`) and attribute type handling. **Risk:** medium-high: Gatan's specification page (gatan.com/node/5170) could not be fetched, and the readers available are third-party.

### 2.4 Bruker BCF, briefly (priority: low; the owner has none)

**Structure** (`bruker/_api.py`)
- Container: AidAim SFS. Magic `AAMVHFSS` (`:309`); version float and chunk size at 0x124; file tree at 0x140; 0x200-byte tree items; per-file pointer tables chained across chunks.
- Optional zlib per file, marked by an `AACS` header (`:223`), with blocks of 16-byte header + deflate data.
- `EDSDatabase/HeaderData`: XML (`TRTSpectrumDatabase`: image size, DSP settings, `CalibAbs`/`CalibLin`, `PrimaryEnergy`, `ElevationAngle`).
- `EDSDatabase/SpectrumData<i>`: the hypermap.

**Hypermap decoding in plain words** (`:1084-1250`, pure-Python reference implementation)
1. Skip 0x1A0 bytes.
2. For each image row, read a pixel count; each pixel has a 22-byte header: x index, total channels, pixel channels, flag, sizes, pulse count.
3. The flag selects the payload format:
   - 0: a list of 16-bit pulse channel values (bincount them),
   - 1: 12-bit packed pulses,
   - greater than 1: "instructively packed" channel runs with a gain and 1/2/4/8-byte deltas (nibble-swapped for size 1), then extra 16-bit pulses.
- Downsampling sums pixels.
- **Swift trap:** Apple's Compression framework's ZLIB is raw deflate, so strip the 2-byte zlib header, or link the system libz.

**Live time:** not loaded by rsciio (rsciio #239). It can be recomputed from the 0-eV strobe (hyperspy #2534).

**Test files** (sizes in bytes): `bruker/16x16_12bit_packed_8bit.bcf` 135,448; `30x30_instructively_packed_16bit_compressed.bcf` 954,648; `bcf_v2_50x50px.bcf` 2,687,256; `over16bit.bcf` 69,912; `test_TEM.bcf` 332,056; `bcf-edx-ebsd.bcf` 1,203,433. Zenodo 8403583 has three TEM `.bcf` files of 5–11 MB.

**Effort:** 3–5 days. **Risk:** medium-high.

### 2.5 EMSA/MSA, ISO 22029 (priority: high, cheap)

**Structure:** text. Lines of the form `#KEYWORD[-units] : value` until `#SPECTRUM`, then the data as `Y` or `XY` with `NCOLUMNS` 1–5, ending at `#ENDOFDATA` (`msa/_api.py:164-330`; the keyword table at `:62-160` includes `XPERCHAN`, `OFFSET`, `BEAMKV`, `LIVETIME`, `REALTIME`, `ELEVANGLE`, `AZIMANGLE`, `SOLIDANGLE`, `FWHMMNKA`, window and layer thicknesses, `EDSDET`).

**Edge cases**
- `TITLE` and `COMMENT` may span several lines.
- Units may be attached to the keyword (`#AZIMANGLE-dg`).
- Scientific notation may contain a space (`2.0 E-06`), and a value field may hold two numbers.
- Commas are separators.
- `XUNITS` may be eV: normalise to keV.
- **Parse with the POSIX locale** (the German-locale trap in the memory index).

**Test files:** 11 files of 0.4–2 KB in `tests/data/msa/`, including the `ISO_22029_2022_compliance*` set. eXSpy's `EDS_SEM_TM002.hspy` originated as an `.msa` file (its `original_filename` attribute).

**Effort:** 0.5–1 day. **Risk:** low.

### 2.6 HyperSpy `.hspy`, needed for parity fixtures (priority: high)

The eXSpy reference numbers are pinned on `.hspy` files: `exspy/data/EDS_SEM_TM002.hspy` and `EDS_TEM_FePt_nanoparticles.hspy` in the other agent's clone. Their layout is:
- `Experiments/<title>/data` (gzip-compressed),
- `axis-k` attributes `offset`, `scale`, `size`, `units`, `navigate`,
- `metadata/...` groups with attributes, e.g. `Acquisition_instrument/SEM/Detector/EDS {azimuth_angle 0, elevation_angle 37, live_time 19.997, real_time 39.594, energy_resolution_MnKa 130}`.

Zenodo 14859606 (4D + EDS) is also `.hspy`.

**Effort:** about 1 day with the existing `H5Reader`. **Risk:** low.

---

## 3. What the repo's readers give, and what is missing

**Reusable**
- **`DM4Reader.swift`:**
  - the tag walk with the 1-based naming of unnamed entries (`:602-692`),
  - the `numbers` and `strings` maps (strings only for uint16 arrays under 1000 bytes, which covers `Meta Data.*`, units, EDS detector type and dates),
  - recording of `Data` blob offsets,
  - `.alwaysMapped` mmap plus the `MappingLiveness` latch (`:53-96`, `:225-229`),
  - per-type decode to Float (`:527-560`),
  - the blocked-transpose pattern (`scanFastestGather`, `:304-398`), which is exactly what an energy-slowest SI needs to give per-pixel spectra.
- **`H5Reader.swift`:**
  - dlopen of the bundled libhdf5 and symbol tables (`:155-271`),
  - `H5Lvisit2` path collection (`:13-24`, `:321-323`),
  - hyperslab reads (`:627-735`),
  - variable- and fixed-length string datasets and attributes (`:959-1046`),
  - `HDF5Serial` locking (`HDF5Types.swift:98-121`),
  - gzip-chunked reads already used for py4DSTEM files.

**Missing**
1. **A `SpectrumCubeSource` protocol.** `FourDDataSource` and `DatasetDescriptor` assume [Ry, Rx, Qy, Qx] (`DatasetDescriptor.swift:37-42`). The new protocol needs:
   - `readSpectrum(y:x:)` and `readEnergyWindowMap(range)`,
   - `sumSpectrum`,
   - per-pixel frame count and zero-peak map,
   - `energyCalibration` (offset, dispersion, units),
   - detector geometry (elevation, azimuth per detector, solid angle) and times with their declared meaning,
   - a sparse CSR export.
2. **DM:** selection of objects by `Meta Data.Format`/`Signal`; a multi-object index so the 4D cube and the EDS SI can come from one file; the energy-slowest layout; −Origin × Scale; EDS tag mapping including `Detector Info.Solid angle`; keeping the `Spectrometer Meta Data` blob; and honouring or refusing `Data Order Swapped`.
3. **HDF5:** `HDF5Library` is `private` to `H5Reader.swift`; move it to shared scope. Add `H5T_NATIVE_UCHAR_g`, `_USHORT_g` and `_ULLONG_g` (only float, double, int and C_S1 are loaded today), raw-byte column reads for the Velox JSON, block reads of 1-D uint16, and `H5Aiterate2` for DM5.
4. **JSON:** Velox stores numbers as strings ("10", "-250"); parse them with the POSIX locale.

---

## 4. Effort and order

| # | Item | Days | Risk | Why this position |
|---|---|---|---|---|
| 1 | MSA + `.hspy` readers | 1.5–2 | low | Parity fixtures for eXSpy (TM002 values) |
| 2 | Velox SpectrumStream → CSR, shape from ScanArea, frame and zero-peak maps, metadata in radians | 4–7 | medium | The owner's actual EDX data (107 streams) |
| 3 | DM EDS spectrum + SI, choosing objects by Meta Data, energy-slowest layout | 2–4 | medium | The owner's future GMS 4D + EDS |
| 4 | DM 4D + EDS in one file (multi-object, grid identity) | 1–2 | medium | Needs one owner test acquisition |
| 5 | DM5 | 2–4 | medium-high | Only if the test acquisition shows GMS writes it |
| 6 | Bruker BCF | 3–5 | medium-high | Others' data only |

Items 1–4 add up to **about 8.5–15 days**; a minimal Velox + DM SI + MSA/hspy subset is about 8–13. **These are estimates, not measured.**

---

## 5. Things I could not verify

- The actual object names, tags, dtype and per-pixel live-time storage of a GMS EDS SI, and whether 4D + EDS lands in one file.
- Whether real Velox streams are ever compressed (all public ones are not).
- The semantics of Velox per-frame times across versions.
- Whether the zero peak is a strobe reference.
- The origin of rsciio's reference `.npy` arrays.
- Swift decode throughput.
- The DM5 origin convention and compression.

---

## 6. Sources

**Code (RosettaSciIO, clone `049e7d70`)**
- `rsciio/digitalmicrograph/_api.py`
- `rsciio/emd/_emd_velox.py`, `rsciio/emd/_api.py`
- `rsciio/utils/_fei_stream_readers.py`, `rsciio/utils/hdf5.py`
- `rsciio/bruker/_api.py`, `rsciio/msa/_api.py`
- `doc/supported_formats/{emd,digitalmicrograph}.rst`
- `tests/test_emd_velox.py`, `tests/registry.txt`

**Repo files**
- `mac4DSTEM/Core/Data/DM4Reader.swift`, `H5Reader.swift`, `FourDDataSource.swift`, `DatasetDescriptor.swift`, `HDF5Types.swift`
- `docs/dm4-format.md:195-213`, `ROADMAP.md:78-80`

**Issues and PRs**
- [rsciio #315 (DM5 PR)](https://github.com/hyperspy/rosettasciio/pull/315)
- [rsciio #255 (Continuum dm4 + RAW)](https://github.com/hyperspy/rosettasciio/issues/255)
- [rsciio #216 (event-based data, CSR)](https://github.com/hyperspy/rosettasciio/issues/216)
- [rsciio #239 (bcf live time)](https://github.com/hyperspy/rosettasciio/issues/239)
- [hyperspy #2362](https://github.com/hyperspy/hyperspy/issues/2362) and [hyperspy #2534 (live/real time)](https://github.com/hyperspy/hyperspy/issues/2534)

**Other readers**
- [LiberTEM `dm_single.py`](https://github.com/LiberTEM/LiberTEM/blob/master/src/libertem/io/dataset/dm_single.py)
- [Nion `DM5IOHandler.py`](https://github.com/nion-software/nionswift-io/blob/master/nion/io/DM_IO/DM5IOHandler.py)
- [ePSIC `load_k3_data.py`](https://github.com/ePSIC-DLS/epsic_tools/blob/master/epsic_tools/toolbox/load_k3_data.py)

**Gatan documentation and web**
- From the GMS 3.6.1 installer, extracted by another agent: `$S/gms/txt/1020.40004_V002_STEMx System User Manual.txt`, `EDS Acquisition Installation Guide.txt`, `$S/gms/ReleaseNotes.txt`
- [Gatan 4D-STEM talk, Warwick (Gorji)](https://warwick.ac.uk/research/rtp/em/info/facility_open_day/saleh-gorji-gatan-4dstem-unveiled-capturing-diffraction-at-every-pixel.pdf)
- [STEMx page (Wayback copy, 2026-05-12)](http://web.archive.org/web/20260512013907/https://www.gatan.com/products/tem-imaging-spectroscopy/stemx-system)
- [Gatan dm5 documentation](https://www.gatan.com/node/5170): search snippet only, the page returned HTTP 429
- [DM format summary (NTU)](https://personal.ntu.edu.sg/cbb/info/dmformat/index.html)
- [St4DeM paper, arXiv 2504.19762](https://arxiv.org/html/2504.19762)

**Datasets (Zenodo)**
- [14859606](https://zenodo.org/records/14859606), [8403583](https://zenodo.org/records/8403583), [7521571](https://zenodo.org/records/7521571), [12699952](https://zenodo.org/records/12699952), [21632101](https://zenodo.org/records/21632101), [5256066](https://zenodo.org/records/5256066)

**Owner data:** header-only scan by another agent, `$S/ownerdata/dm_summary.txt` and `$S/ownerdata/edx_unique.tsv`.