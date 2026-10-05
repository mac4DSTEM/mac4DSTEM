I closed 20 gaps this pass with header reads, small slices and a few web or API lookups. Four findings change the design.
- **Drift:** Velox already corrects drift while it acquires.
- **Counts:** the beam current at the 4D settings is about 7× lower than the EDX current.
- **Absorption:** refusing absorption correction on the owner's summed-detector data leaves the Mg/Si ratio biased by 3–19 %.
- **v4.5:** the shipped app would probably open every Velox `.emd` as a meaningless one-row datacube.

Nothing was written under the repo. Scratch scripts are in `$S/critic/`, where `$S` = `<scratch>/edx`. I read owner files read-only: headers, two HAADF frame blocks of 60 MB or less, and one 134 MB stream slice. I downloaded no data files; I only queried the Zenodo metadata API, ran web searches, and ran `pdftotext` on the owner's own Velox 2.12 and Talos pre-install manuals. Keep-awake: `pmset` shows `PreventUserIdleSystemSleep 1` from the caffeinate processes 4914 and 7722.

# A. Closed this pass (evidence = script or file in `$S/critic/`, or URL)

| # | Gap | Answer | Evidence |
|---|---|---|---|
| C1 | Velox version of the owner's files (Fable inputs: "unparsed") | Acquisition PC runs **Velox 2.15.0.45**, writing EMD **v9** (55 streams) and **v11** (79). Velox 3.13 appears only on the KIT Themis files (8 Super-X G2 streams, 4 per file). All 142 streams are uncompressed, chunks (8192,1). `FrameLocationTable` is present except in 3 single-spectrum files; 6 stub files error. EMD v9 has no public test file, so the owner's files are the only v9 fixture. | `stream_census.py`; `/Info` applicationVersion |
| C2 | Are Velox frames drift-shifted? (Fable inputs unverified #2) | **No: Velox corrects drift during acquisition.** `CustomProperties.Scan.ScanTransformation.A13/A23` change on every frame: up to −0.0029/+0.0068 in the 130 kx file, −0.0032/−0.0040 in the 7.4 GB file, not monotone. Yet 10-frame HAADF block sums at frames 0 vs 30/60/110 (and 0 vs 120/240/470 in the 7.4 GB file) agree within **≤1 px**. The correlation peak equals the odd/even self-noise peak, and a planted (+7,−5) shift is recovered exactly. The owner-version manual says the same: Velox 2.12 manual, extracted text lines 4555–4560 and 4799–4802 (from `NB/02_methods/TEM/Velox 2.12 User Manual.pdf`). **So drop the per-frame HAADF re-alignment step.** **Residual risk:** for Super-X G1, the SI data itself "can shift relative to the reference STEM image" (Velox 3.15 UM p.259, txt :8973). HAADF correlation cannot measure that. | `velox_series.py`, `velox_drift.py` |
| C3 | Probe current in metadata (Fable methods unverified; needed for zeta, K, dose) | Velox stores `Optics.ScreenCurrent` and `LastMeasuredScreenCurrent` per frame: 1.78 nA on the Al-Mg-Si SIs; 5.08→4.69 nA drift within the Rh file. Its accuracy as a flu-screen reading is unverified. GMS writes `Microscope Info.Probe Current (nA) = "0.0"` in every owner object (292× ImageList.2), so GMS data needs a typed current. | `velox_meta.py`; `ownerdata/dm_scan.jsonl` grep |
| C4 | Counts at 4D conditions (ownerdata/Fable: "~10²+ /px", same current assumed) | Same session as cube 051: the Velox HAADF at 18:41, 10 min before 051 at the same α −16.87°, was taken at spot 7, C2 70 µm, 2.1 mrad, **0.26 nA**. The EDX SIs ran at spot 5, C2 100 µm, 15 mrad, **1.78 nA**. The owner's SIs give 9.5–9.8 counts/(ms·nA) per pixel (12.8–13.1 counts at 0.75 ms × 1.8 nA). Estimates (thickness differs between fields):<br>• 051 at 20 ms: **~50 counts/px**, which is **0.5 counts/nm²** at its 10 nm step.<br>• 060 at 10 ms (current unknown, 0.26 nA assumed): ~25/px, 11 counts/nm².<br>• Existing Velox SIs: **22–92 counts/nm²**.<br>**Per object area, a simultaneous scan at the owner's 4D settings yields 2–180× fewer X-rays than his existing separate EDX SIs.** | `velox_series.py` on `STEM HAADF 1841…emd` |
| C5 | Zero-peak share ("82–100 %… overstates by an order of magnitude", formats) | In the owner's data only **1.1 %** of events fall below 150 eV (mid-stream 134 MB block of the 7.4 GB file), and 2.7 % in the 1006 summed spectrum (ownerdata §7). The 82–100 % holds for the public test files only. Keep the zero-peak side output; drop the warning for his data. | inline timing script |
| C6 | Decode throughput (Fable inputs #4) | `h5py` read **469 MB/s** from the external SSD (one 134 MB block, page-cache state unknown); numpy marker/event decode took 0.22 s. Extrapolated: **~7 s read + ~3 s decode ≈ 10 s** for the 3.2 GB stream. That sits exactly on Fable's "cache becomes required" threshold. | same |
| C7 | Detector geometry for absorption on the owner's summed Super-X G1 stream | Metadata has 4 detectors: azimuth 45/135/225/315°, elevation 22° (0.384 rad), 0.225 sr each, all enabled. Stage α and β are in rad; stage position is in **metres**; holder `FEI Double Tilt`. Whether Velox's shadow model for the "Double-Tilt Super-X holder" applies to this holder is unverified. A summed-geometry absorption model can be computed, so refusing it is a choice, not a necessity. | `velox_meta.py` |
| C8 | Size of the absorption bias the methods design would accept | Al μ/ρ (exspy FFAST): Mg Kα 593, Al Kα 372, **Si Kα 3302** cm²/g. With no correction, Si is under-reported, so Mg/Si reads high by **+3 % (30 nm) / +6–7 % (60 nm) / +10–12 % (100 nm) / +15–19 % (150 nm)** at a take-off angle of 18–22°. The bias grows with stage tilt per detector. | inline exspy run (venv) |
| C9 | Spectral artefacts specific to Al-Mg-Si (absent from every report) | **Al Kα sum peak 2.973 keV vs Ar Kα 2.958 keV.** They are 15 eV apart with FWHM ≈ 98 eV, so they cannot be separated. The owner's Velox element selection on the 190330 files includes **Ar**, which may be a misattribution (unverified). Al+Mg sum is 2.740 keV and Al+Si sum is 3.226 keV. **Si internal-fluorescence peak** from the detector dead layer adds spurious Si (≈0.15 % Si-equivalent per the web source; size for a windowless Super-X unverified). Line separations are only 3.0 FWHM (Mg–Al) and 3.3 FWHM (Al–Si). | computed; [Niigata repo](https://niigata-u.repo.nii.ac.jp/records/6858) |
| C10 | "Velox 3.20 broke HyperSpy" (market GH6, used as a failure mode by Fable inputs) | rosettasciio#484 was **closed as a user environment error** (HyperSpy 1.7.1 too old). It is not a format break. | `gh issue view 484` |
| C11 | Public GMS EDS-SI / simultaneous 4D+EDX files (formats: "no public GMS EDS SI file") | **They exist, as separate per-signal files:**<br>• Zenodo 10609594 (YAlO₃, CC BY 4.0): `EDS Spectrum Image.dm4` 39.5 MB, plus separate EELS and `HAADF Image (SI Survey).dm4`.<br>• Zenodo 8000141 (Mills et al., Acta Mater 2024): "Simultaneous 4D-STEM / EDX". `4DSTEM_EDS_scan_300kV_Diffraction SI.dm4` (5.3 GB) is GMS output; the EDX ships only as `.hspy` (0.79 MB) plus `…hits.hspy`. | Zenodo API |
| C12 | Kho 2025 truth (validation: "unverified whether labels ship") | Zenodo 14859606 holds only 2 `.hspy` files and 2 notebooks ("hyperparameters to reproduce"). **No truth file ships**; truth must be regenerated. | Zenodo API |
| C13 | Another acquisition route on the owner's microscope model | Duran 2023 recorded EDS and CBED simultaneously on a **Talos F200X + Super-X + Merlin Quad**, coordinated by the "STEM software trigger signal", at 2–25 ms dwell. This is Velox-scan-plus-external-camera, a route neither design lists. | `papers/duran2023.txt:133-144` |
| C14 | Can the Velox and GMS images be registered, and what transform kind? | On the 190330 pair (Velox 18:41 HAADF at 1.704 nm/px; GMS 051 ADF survey at 2.508 nm/px, 1024²): a unique correlation peak (peak/std **41.4** vs next 10.4, median 7.3) at **mirror + 90.0°**, i.e. an axis swap under the loaders used (h5py with `.T`; ncempy). Scale **1.00** from metadata alone (2 % grid). **Two consequences:** the registration record must allow a reflection or pin each vendor's axis convention, and metadata-seeded correlation works on this pair. The app readers' own conventions still need pinning (interacts with the open DM4 scan-pair item, `docs/open-items.md:183`). | `xreg.py` |
| C15 | No other formats on the owner's SSD | No `.mrc`, `.dm5`, `.rpl`, `.pts` or `.spd` anywhere, so no Velox (Ceta-2) 4D-STEM was ever recorded. Only EBSD `.ang/.ctf` from the thesis. | `find` |
| C16 | Licence compatibility | Repo is `GPL-3.0-or-later` (`CITATION.cff:21`); rsciio `GPL-3.0-or-later`; exspy GPLv3. Compatible. | files |
| C17 | exspy line-table provenance | Line energies come from **Chantler 2005 (NIST)**, weights from EPQ, EELS fields from the Gatan atlas (`exspy/material/_elements.py:1-11`). So the NIST data-rights question covers the **line table** too, not just FFAST. | file |
| C18 | Can the owner get k-factors from Velox? | The manual mentions k only as Cliff-Lorimer and the 20 % rule (txt :8087, :9200). No export is documented, so there is no k-factor source on day one. | grep |
| C19 | CI | Still red at HEAD (`gh run list`: 85920f91, 2026-10-04T19:22Z, failure). | gh |
| C20 | Velox `.emd` opened by the shipped v4.x app (repo report: "predicted, not reproduced") | **Emulated, not driven**: I applied `H5Reader.discoverPrimaryDataset`'s ordering (`H5Reader.swift:267-370`) in `h5pick.py`. Velox SI `/Data/Image/<uuid>/Data` (2048,682,120) uint16 opens as **[1, 2048, 682, 120]**; Ceta and STEM images open as **[1, 2048, 2048, 1]**. `.emd` is in the open panel (`ContentView.swift:40`) and is a registered Finder document type (`Info.plist:18+`). The owner has 2149 `.emd` files. A HyperSpy 1D spectrum gives a named refusal. | `h5pick.py` |

# B. Prioritised gap list

## P0: blocks the v5.0 decision

1. **The science question v5.0 must answer is not stated anywhere (decision not framed).** Candidates:
   - Mg/Si per precipitate class (β″ vs β′/U/B′);
   - Cu-bearing Q;
   - Si segregation at LPBF cell boundaries (chemistry without a diffraction boundary, the case where approach G fails);
   - solute depletion in matrix or PFZ.

   This choice picks S1 vs S2 and the acquisition route. Put it first on the sheet.
2. **Which acquisition route works on his Talos (not framed; costs unknown).**
   - **R1 – GMS STEMx + Gatan EDS driving Super-X.** The GMS guide's Super-X section assumes "FEI microscope control 4.5" + Esprit 1.9.4, an `ExternControl` licence, a replacement DigiScan DDC and rewiring at the FEI scan switch (ESS-X5/X7) (`gms/txt/EDS Acquisition Installation Guide.txt:724-869`). Whether this works on a Velox-2.15 Talos G1 is unverified.
   - **R2 – Velox 4D-STEM.** Needs Ceta-2 + the 4D-STEM option (Velox 2.12 manual, txt :3353-3356). Never used per C15.
   - **R3 – Velox scan triggering an external camera.** Duran (C13); the owner has no Merlin, and Continuum triggering is unverified.
   - **R4 – Sequential: GMS 4D, then a Velox EDX SI on the same field and tilt.** Possible today; registration works (C14) and it gives 2–180× more X-rays per object area (C4).

   **Owner action:** ask Thermo, Gatan and Bruker service about R1/R2 and their cost. Until then, path (i-a) "same `.dm4`" (3–6 days plus the `DMFile` split) is speculative and should be conditional, not step 7 of the build order.
3. **Zero usable joint pairs exist, so plain-SI windows (Fable M2′) are effectively required.** Without them v5.0 cannot run on any existing owner data until he re-acquires. Fable left this as optional ("owner's call"); the sheet should say it is the only path to day-one value.
4. **k-factor source on day one (not framed).** Fable methods puts theoretical k out of v5.0 and wants a user k-file, but none exists and Velox exports none (C18). Without k there is no at% on his data. Options:
   - (a) theoretical k from NIST EPQ data (public domain; validation §2 lists `SalvatXion/`);
   - (b) internal standard from a homogeneous solution-treated sample of the same alloy with known bulk composition (unverified that such a sample exists; as-built LPBF is not homogeneous);
   - (c) a measured thin-film standard;
   - (d) ship Mg/Si count ratios only, with no k.
5. **Absorption on summed Super-X G1 data.** Fable methods says refuse on summed data, which on his data means never correct. The geometry is in the metadata (C7), and refusing leaves the decisive Mg/Si ratio 3–19 % biased (C8). That is the same order as the gap between β″ composition models: Mg₅Si₆ Mg/Si = 0.83 vs atom-probe values of about 1.1 with ~20 at.% Al ([OSTI 644310](https://www.osti.gov/biblio/644310)). Put both options on the sheet:
   - refuse;
   - an equal-weight 4-detector summed model with the shadowing systematic shown.
6. **v4.5 remainder that the v4.5 report missed.**
   - (a) Opening a Velox `.emd` (C20) gives a nonsense cube. That is a shipped-feature defect under ADR 049 exit 3, and the owner is likely to hit it on his drive. Choose: named refusal now (reader change + discovery-test cases, Gate B) or a release note.
   - (b) CI is still red (C19).
   - (c) Sequencing: may v5 Core/reader work, ADRs and mocks start before v4.5 ships? ADR 049 must be reopened, and with what scope?
   - (d) ADR 051 says EDX is "v5 or v6"; the brief says v5.0. An ADR 007 amendment should fix EDX = 5.0.0.

## P1: shapes the design or its cost

7. **Super-X G1 EDS-vs-STEM shift (Velox UM p.259) is unmeasured.** It is now the only intra-file alignment risk (C2). Recipe: decode early and late frame ranges via `FrameLocationTable`, bin 8–16×, correlate total-count maps.
8. **Indistinguishability goes beyond Li.** Al inside a precipitate trades off against the projected fraction f of matrix Al, so EDX cannot separate Mg₅Si₆ from Al-containing β″ variants; only Mg/Si is robust. The Fable check covers only invisible elements. Add the C9 artefacts to the science-mode systematics: Si internal fluorescence biases Si exactly where Si is the signal, and the sum peaks.
9. **GMS file layout is not one file in public data (C11).** Same-acquisition identity must be provable across separate per-signal `.dm4` files (Experiment ID, survey Unique Image ID). The Fable inputs (i-b) frames separate files only as the K2 IS case.
10. **Registration transform kinds (C14).** Add reflection or axis swap, or pinned per-vendor conventions. Also record Velox `ScanRotation`: 3.09 rad on the 18:41 image, −0.21 rad on the 7.4 GB SI.
11. **Thickness input not framed.** The owner has a GIF Continuum, so an EELS low-loss t/λ map at the same field is cheap. It feeds absorption, the projection fraction f and the density goal. Also decide whether the "Spectroscopy" name brings EELS into scope (his drives already hold 13 GB EELS SIs) or EELS is explicitly excluded in v5.0.
12. **CSR cache decision is live:** decode ≈ 10 s (C6). Weigh against the lean-app directive: cache location, size (~0.25 GB) and purge policy.
13. **B\* is built on an unvalidated phase map** (T4 failed one metric, per memory). The badge policy for stacked unvalidated layers is not framed.
14. **Data rights.** The NIST SRD question covers Chantler line energies too (C17), not only FFAST; validation decision D1 and Fable M1/M2 should be widened.
15. **Session and token cost not priced** against the owner's token-conservation directive. Estimates: 24–34 sessions minimum, plus 5–7 for B/A/C/D, plus 6–10 for F/G (repo §6).

## P2: settle when convenient

16. Owner questions (all unverified):
   - GMS EDS (700.LS.707) and Hi-Speed SI licences;
   - GMS 3.62 upgrade plans (OIM, possible dm5 default);
   - Ceta model and 4D-STEM option on the Talos;
   - DM Help pages for EDS quantification, STEM SI and dm5 (export from a GMS PC);
   - whether `ScreenCurrent` reflects acquisition conditions.
17. Papers and products not used:
   - Al-alloy EDX literature: [Wenner et al. 2017, Micron 96:103](https://sintef.brage.unit.no/sintef-xmlui/handle/11250/2719567); β″ atom probe ([OSTI 644310](https://www.osti.gov/biblio/644310)); NTNU SPED precipitate statistics ([Sunde](https://ntnuopen.ntnu.no/ntnu-xmlui/handle/11250/2464152)).
   - Mills 2024 methods: the PDF exceeded the fetch limit, so microscope, camera, EDS software and dwell are unread.
   - TESCAN AA2099 app note (behind a personal-data form).
   - PSNMF and Potapov–Lubk details.
18. Kho 2025 does not count as a truth dataset unless the notebooks regenerate the labels (C12).
19. Minimum supported Mac (8 GB vs the owner's 64 GB) for EDX features is not stated.

# C. Data the owner must acquire or approve

**Acquire:**
- An EDX SI at a 4D field and at the 4D tilt. The 190330 051 field (α −16.87°) is the cheapest: the stage already matches. Keep the full stream: no Reduce File Size, no pruning.
- The screen current noted at 4D conditions every session, since GMS records 0.0.
- One test of whichever simultaneous route service confirms (R1/R2/R3), saved as `.dm4` (and `.dm5` if offered).
- A k-factor reference, per P0-4.
- An EELS low-loss thickness map at the same field.
- Two SIs at different currents, to test the Al-sum vs Ar question.

**Downloads that need the owner's permission** (all CC BY 4.0):
- YAlO₃ `EDS Spectrum Image.dm4`, 39.5 MB (Zenodo 10609594). It would settle the GMS EDS-SI tags, dtype, energy units and live-time questions now.
- A ranged read of the head and tail (a few MB) of Mills `4DSTEM_EDS_scan_300kV_Diffraction SI.dm4` (Zenodo 8000141), to see whether an EDS object is inside.
- Duran `dataset*_EDS.hspy`, 1.06 + 0.25 MB (Figshare 10.48420/21610977): a measured X-ray count at 2–25 ms on a Talos F200X with Super-X.

# D. Corrections to the prior reports

| Claim | Source report | Correction |
|---|---|---|
| Re-align Velox frames from the HAADF stack | Fable inputs §4 | Frames are already aligned (C2) |
| Velox 3.20 broke HyperSpy | Market GH6, Fable inputs failure modes | User environment error (C10) |
| Zero peak overstates counts tenfold | Formats | Public test files only (C5) |
| No public GMS EDS SI file | Formats | Two public sets exist (C11) |
| 10²-count pools at 4D dwell | Fable methods / ownerdata | Current-corrected and per-area (C4) |
| Absorption refusal costs nothing on his data | Fable methods | It costs a 3–19 % Mg/Si bias (C8) |
| Velox version unparsed | Fable inputs / ownerdata | Velox 2.15.0.45, EMD v9/v11 (C1) |
| One `.dm4` per acquisition | Fable inputs (i-a) | Not guaranteed (C11) |

Scripts:
- `$S/critic/velox_meta.py`
- `$S/critic/velox_series.py`
- `$S/critic/velox_drift.py`
- `$S/critic/stream_census.py`
- `$S/critic/h5pick.py`
- `$S/critic/xreg.py`

Text extracted from the owner's manuals: `$S/critic/velox212.txt`, `$S/critic/talos_preinstall.txt`.

Sources:
- [OSTI 644310 (β″ atom probe)](https://www.osti.gov/biblio/644310)
- [Wenner et al. 2017](https://sintef.brage.unit.no/sintef-xmlui/handle/11250/2719567)
- [NTNU SPED precipitate statistics](https://ntnuopen.ntnu.no/ntnu-xmlui/handle/11250/2464152)
- [NTNU hybrid precipitates SPED](https://ntnuopen.ntnu.no/ntnu-xmlui/handle/11250/2464135)
- [Si internal fluorescence (Niigata)](https://niigata-u.repo.nii.ac.jp/records/6858)
- [Mills et al. PDF](https://strobe.colorado.edu/wp-content/uploads/Elucidating-the-role-of-Cr-migration-in-Ni-Cr-exposed-to-molten-FLiNaK-via-multiscale-characterization.pdf)
- [Velox datasheet](https://qa1-assets.thermofisher.cn/TFS-Assets/MSD/Datasheets/velox-datasheet.pdf)
- [Zenodo 14859606](https://zenodo.org/records/14859606), [8000141](https://zenodo.org/records/8000141), [10609594](https://zenodo.org/records/10609594)