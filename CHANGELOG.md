# Changelog

## Unreleased (kit switches since v4.5.0, 2026-10-15 to 2026-10-21; not yet tagged)

- 2026-10-21 Fixture move: the known-wrong demo Q scale in `QCalibrationOriginGateTests` is 0.024440 Å⁻¹/px again (was 0.021001 under the max-pattern radius), because the stored probe radius is the mean pattern's.

- 2026-10-21 Re-calibrate Origin no longer overwrites a file's probe radius (the demo's 4.5 px was replaced by 9.56 px, the max pattern's estimate). The stored probe radius is now measured on the MEAN pattern, as py4DSTEM's `DataCube.get_probe_size` does, and only when no file, session or typed value (or vacuum-probe kernel) stands; the origin window keeps py4DSTEM's max-pattern radius (`get_origin`). A radius measured by Re-calibrate Origin on a file without one therefore moves from the max pattern's to the mean pattern's value (demo: 9.56 to 6.93 px). The lineage node records `origin_window_radius_px` and `probe_radius_mean_px`.

- 2026-10-21 Spectroscopy: wt% and at% map modes (offered after Quantify, typed k) from `EDXQuantification.quantifyMaps`; per-pixel, no σ, a failed pixel (e.g. negative net) drawn 0 and counted on the tile, badge `validation: none`. Runs without absorption correction and refuses computed k with a sentence until the kit exposes them. Not on screen yet (unverified).

- 2026-10-21 Patch re-pin: SpectroKit 0.8.1, FormatoKit 0.9.1, DiffractoKit 0.9.1, CuboKit 0.8.1, ImagoKit 0.6.1 (no source change, no public API change). Visible: `peak_local_max` accepts ±inf; CIF import is faster with identical results; kit test pins loosened to the Python tolerances. No migration.

- 2026-10-21 Re-pin onto the audited kits: SpectroKit 0.8.0, FormatoKit 0.9.0, DiffractoKit 0.9.0, CuboKit 0.8.0, ImagoKit 0.6.0 (no feature, no numerics). Migration (visible): a CIF that names its group by Hermann-Mauguin symbol alone and lists an incomplete operation set is now refused (`incompleteSymmetryOperationsForSymbol`; it imported before). Source change: `sameScanAs4DCube` is `sameScanAsCube`; the unit tests name `DSTEMCore.Calibration` because CuboCore now exports a `Calibration` too. The spectro goldens carry the renamed field.

- 2026-10-21 PCA projection onto CuboKit 0.7.1 (`PCA.project`; `DiffractionEmbedding.project` deleted; same vDSP calls, unit suite unchanged).

- 2026-10-21 Final kit switch (pins CuboKit 0.7.0, FormatoKit 0.8.0, DiffractoKit 0.8.1, ImagoKit 0.5.0; SpectroKit 0.7.1 stays). Core/ 23,172 -> 20,551 lines. Ptychography runs on CuboPtycho's Float32 engine (`PtychographyReconstructor`, was `SingleslicePtychography`, falling back to the kit's Double path where vDSP does not take the detector size; object and probe within 3e-7 of the old engine, agreed tolerance 1e-4). Parallax alignment shifts with `ParallaxFourierShifter` and estimates with `correlationShift`; `MatrixDFTCorrelation` is deleted; `ParallaxPreprocessor.run` calls the streamed `ParallaxPreprocessing.prepare(source:)` (stacks bit-identical on the demo cube). Per-position origins are `OriginMeasurement.measure(.iteratedWindow, .metal)` (the app's Metal kernel and shader deleted; 7.6e-6 px against the old kernel) and the window sensitivity is the kit's. The classical full-scan Bragg detection is `BraggDisks.detectAll(failurePolicy: .recordEmpty)` (peaks bit-identical; progress now ticks per scan tile). The strain fit, indexing and tensor rotation are CuboStrain's (`StrainMapper` adapts them to the app's Float map; strain within 2.3e-7), the known-crystal Q scale is `LinearScale.estimate` and the orientation-map read-outs are `OrientationMapAnalysis` (bit for bit).
  - Migration (visible): the alignment moved from Float to Double correlation, so group shifts at the finest levels can move by up to 0.17 px on noisy near-aligned stacks (against planted truth the new code is closer, 0.038 px against 0.053 px); `ParallaxGoldenTests` now compares within 5e-5 of each array's range (was bit for bit; measured worst 1.6e-5). A non-finite Bragg peak is refused by the sidecar writer. A sidecar's `version_major/minor` are int64. The odd compound dataset in the reader baseline now reports `datasetOpenFailed`.
  - Kept in the app: the learned detector (training and refine, ADR 071), lineage and marks records, the `small_datacube` rank-3 reshape, header-less MIB, selected-area diffraction (the kit's virtual diffraction is CPU-only), the Float façades and settings.
- 2026-10-21 HDF5 I/O onto FormatoKit 0.8.0, the app's own HDF5 code is gone. `H5Reader` lists links with `HDF5Reader.walk`, reads patterns through one `HDF5SlabReader` per dataset (file and dataset held open) and an h5py bool attribute through `attribute`; `HDF5LegacyProbe`, `HDF5LibraryCandidates`, `HDF5WriteLibrary` and `HDF5WritePrimitives` are deleted. The sidecar (`SessionSidecarWriting`), the scientific bundle and the preprocess datacube export are written with `HDF5NewFile.write`, `HDF5WriteSession` (`writeEMD*`, `writeBraggVectors(.appImageXY)`, `copyObject`) and `EMDDatacubeWriter`; the reduction, hot-pixel step, calibration re-reference and every `mac4dstem_*` attribute stay here. Core/ 24,026 -> about 22,750 lines. Checked against the former writer over h5py: every object, attribute, dtype, shape, chunk and value equal except `version_major`, `version_minor` and `_target_paths/length`, now int64 (were int32). A peak that is not finite is refused (it was written); the peak-grid progress is one step.

- 2026-10-21 Switches onto the pinned kits, no re-pin. `fitOriginTrimmed` is CuboKit 0.6.0's `OriginFit.fitTrimmed` (Double inside the kit; the app's Float copy of the trim loop, `fit2D` and `fitOrigin` are gone). The preset crystals are DiffractoKit's `CrystalPresets` (`Crystal.gold` etc. are `CrystalPresets.gold`; `Crystal.CubicStructure` is `CrystalPresets.CubicFamily`, `.sc` is `.simpleCubic`). The Metal ACOM backend is `ACOMMatcher.matchAll(backend: .metal)`: `MetalACOMMatcher`, the app's selection and preview expansion and `ACOMMatching.metal` are gone. The Metal virtual-image, mean/max and centre-of-mass one-shots (`MetalEngine.virtualDetector`, `virtualImage`, `dpStatistics`, `centerOfMass`, `VirtualDetector.run/image/diffraction`, the resident-cube `OriginCalibration.run`) and their four shaders are gone; those paths already ran on CuboKit's reducers. Core/ 24,026 -> 23,172 lines, four shaders and the ACOM shader removed. Migration: the Metal ACOM digests recorded on the app's own matcher moved (the kit's kernels differ in Float rounding; Metal now equals the CPU reference to 1e-5 in score with the same template on the synthetic scans, CPU digests unchanged), so those freeze tests compare against the CPU instead; the trimmed origin fit and the ACOM Metal scores are the kit's (within the kit's written tolerances, `docs/parity.md` P31 for ACOM).

- 2026-10-21 Clean slate: dead code from the kit switches removed, docs and ADRs brought to the pinned kits, open-items triaged into kit asks / app work / drop, ROADMAP rewritten. Core/ 24,027 -> 24,026 lines; app Swift 75,795 -> 75,727 lines (little was left: the switches had already removed the rest).

- Session 5 kit/app separation: pins SpectroKit 0.7.1, FormatoKit 0.7.0, DiffractoKit 0.7.1, CuboKit 0.6.0, ImagoKit 0.4.0; Core/ 26,227 -> 24,027 lines. Every copy that has a kit equivalent is deleted except what `docs/open-items.md` ("Kit asks") lists with its marker. Disk detection is CuboBragg `BraggDetector` (`.single` where the kit allows it; serial 5.4 -> 1.4 ms and 8 workers 1.26 -> 0.24 ms per 256x256 pattern, positions within 2.5e-5 px of the kit's Double definition, 4.6e-5 px from the former code). A kit error in a pattern is now a visible failure (diagnostics, scan summary warning), not an empty pattern. Parallax aberration correction, depth sectioning and position correction are the kit's (bit-identical on the pinned synthetic stack, fixture `pre-switch-outputs.json`); the ptychography probe is the kit's (up to 1.2e-7 from the Float build, one ulp). ACOM (cancel, progress, `result(scores:)`, `matchAll`) and the Materials Project import are DiffractoKit's (bit-pattern freeze tests). DM4 (and DM3), HDF5 chunk shape, float16, bool datasets, MIB and EMPAD reads are FormatoKit's, exact on every baseline file.
  - Migration (visible changes): embedding PCA components take the kit's sign (largest entry positive), so a saved embedding's maps and colours can flip against earlier runs; a disordered site in a centred primitive Materials Project cell lists its atoms species-major, which changes `revisionID` and `contentFingerprint` of that model only (an older restored model reads as different); multicorr with an upsample factor of 2 or less runs the parabolic refinement; a raw-only EMPAD file named `scan_xN_yN.raw` opens; a single-pattern HDF5 read is about 0.5 ms (was 0.05 ms; tile and row reads equal) until FormatoKit keeps the file open.
- Switches onto CuboKit 0.4.0 / DiffractoKit 0.5.0 (calibration re-reference geometry is `FrameTransform`; k-means is `KMeans.fitSeeded`; the non-finite feature path is `DiffractionFeatures.binnedVector`; cell standardisation is `CellStandardisation.standardise`). Moved or changed: (1) patterns holding NaN/Inf take the kit's row-wise cell sums, so finite cells of an -Inf-only pattern differ from the old loop by Float32 rounding (test now 1e-5 relative, NaN exact); finite patterns keep the vDSP path and are unchanged. (2) `DiffractionEmbedding.kMeans` now throws `invalidDataset` on non-finite coordinates (it returned a filler assignment); `compute` already refuses such data, so the app is unaffected. (3) Two new refusals in `CalibrationReReference.apply`, both named on the origin: a scan crop that does not fit the origin map's stored values, and fitted x/y maps of different lengths (neither occurs in files the app reads). (4) The Materials Project "already conventional" test reads the lattice matrix rows where it read the wire a, b, c, α, β, γ (equal for real payloads); a centred cell holding a site with no species or an unknown element is returned as served and refused by `crystalModel` per site, where it used to be transformed first. Refusal wording of standardisation comes from the kit. No other number moves.
- Parallax runs on CuboKit 0.4.0's CuboParallax: the aberration fit (`fitLowOrder`, `fitHigherOrder`, `gradientSamples`), the CTF correction (`highpass: .apply`), depth sectioning (`.fullFit` / `.defocusOnly`, one kit call per plane) and the KDE deposition and factor heuristic (`kernelDensity`, `upsampleLimits`); the alignment levels, preprocessing and the position-correction loop stay. No harness number or tolerance changed (parallax-aberration, -depth, -subpixel and -alignment pass against the py4DSTEM references). Differences from before: the stages compute in Double inside the kit, so their memory refusals count Double planes (the correction needs about 2.9x the bytes per padded pixel, 116 against 40; depth counts three Double planes per bright-field image and seven working planes; the KDE counts six Double output planes and the Double image stack) and a job that fit just under the budget can now be refused; a cancel lands before a kit call or between depth planes, not inside a plane or a KDE deposition; where sin(chi) is within rounding of zero the transfer sign is now taken from the Double phase, so it can differ from the old Float result at those few frequencies.
- Switches onto CuboKit 0.4.0 (CuboStrain, CuboPhase) and SpectroKit 0.7.0 (registration). No test tolerance changed.
  - Strain: the automatic basis (`chooseBasisConsensus`), the intensity-once local fit (`fitIntensityOnce`) and the MAD reference (`referenceMAD`) are CuboStrain's, Float32 as before; `compute`, the robust local fit, diagnostics and result types stay. A peak with a non-finite coordinate is left out before the kit sees it (the old search ignored it too); a NaN or infinite intensity skips that position's local fit (the kit refuses it) where the old normal equations ran on it; local-fit weights are divided by their largest when it exceeds 1, so a weight of 1e10 or more still indexes (the fit depends only on ratios). A kit refusal is kept: `StrainFitDiagnostics.refusedLocalFitCount` / `firstLocalFitRefusal`, and the "could not publish strain" message names a basis or reference refusal. `MAC4DSTEM_STRAIN_DEBUG` is removed with the inline search it printed from (the scheme entry is deleted). The basis search no longer checks cancellation inside the kit call (before and after only).
  - iDPC is CuboPhase's `IDPC.integrate` / `integratePhysical`, computed in Double instead of Float32 (rounding-level differences; `idpc-test` and `DPCProductTests` pass at their existing tolerances). `IDPCBoundary` (`.zeroPadded(factor: 2)`) and the kit's `IDPCPhysicalCalibration` (Double) replace the app's types; `integrateIDPC` loses `paddingFactor:`. `DPC.IDPCError` loses `dimensionOverflow` and `fftUnavailable` (every kit refusal arrives as `invalidInput`). A CoM field with a non-finite value is now refused instead of integrated.
  - Registration: `MaskTransport`, `TransportedLabels`, `MaskTransportReport`, `PoolBuilder`, `PooledSpectrum` and `GridRegistration` are SpectroCore's; `RegistrationRecordM2` stays (persistence) with an adapter. The kit throws where the app trapped (a label outside the class range, a mask on the wrong grid, an unknown class); `MaskTransport.region` and `PoolBuilder.pool(image:mask:...)` now throw. The singular-registration message is the kit's ("The registration is singular."), shown as a pool note.
  - `tools/lib/sources.manifest`: `kit_module` passes the module maps of the C targets the requested kit targets depend on (`-Xcc -fmodule-map-file=...`, as `spectrokit_module` does), so a harness can import CuboStrain or CuboEmbedding.
- Orientation maps and ACOM onto DiffractoKit 0.5.0 (two commits): `EulerAngles`, `ZoneAxisFrame`, `OrientationResult`, the cubic/hexagonal/monoclinic reduction, folding, samplers and `.native` IPF keys are `DiffractoOrientation`'s (`CrystalOrientationSymmetry`); the template library, the CPU matcher and its scan loop are `ACOMTemplateLibrary`, `ACOMMatcher.matchAll` and `ACOMScanSelection`. The app keeps `ACOMCrystalSymmetry` (a thin facade), `OrientationMap`, `OrientationPlan` (the kit library plus the model's symmetry), the Metal backend and the refusal messages. No pinned number moved (Metal output digest, KitSwitchFreeze digests, acom harness scores unchanged). Migration of behaviour: the kit validates the template settings, so a plan with invalid settings (for example a non-positive intensity power or sgWidth) is now nil where the app computed garbage; a non-positive beam wavelength now gives a flat Ewald sphere (it was an uncurved sphere before too, in effect); `.identity` has no plan (the UI already blocked it via `supportsOrientationMapping`); a cancellation token is honoured before and after a plan build, not inside it. `tools/harnesses/acom-convention-test/check_mutations.py` now mutates the kit sources in a scratch copy.

- The ring-probe hint (`ProbeRingHint.outerEdge`) is CuboKit 0.4.0's `CuboBragg.ProbeRingHint.outerEdge(of:)`; the app keeps its Float `Result` (the kit returns an `Int` radius bin and a Double dip, converted exactly). No number moves. Its offer threshold now compares against a max-based probe radius (see the probe-radius entry below).
- The probe radius of an origin calibration, and so the kernel radius and detector-adapted defaults of the disk detection that follows, is measured on the MAX pattern, py4DSTEM's `dp_max` default (`OriginCalibration.ProbeRadiusSource.maxPattern`; owner decision 2026-10-19). The mean-pattern radius the app used since 2026-09-01 stays as `.meanPattern`, with its DEVIATION note. The radius itself is `ProbeSize.estimate` (CuboKit, bit for bit with py4DSTEM's `get_probe_size`) on the max pattern; the kit's `OriginMeasurement` takes the same default. Moved fixtures, on purpose: `QCalibrationOriginGateTests` demo scale 0.024472 -> 0.021001 Å⁻¹/px (shell ratio 1.370); `OriginWindowSensitivityTests` fixture radii 6.5 -> 8.141 px (ringed) and 3.0 -> 3.785 px (compact); `ProbeSizeTests` now pins max as the default and mean as the option. Checked against py4DSTEM 0.14.19 `get_probe_size` on the max patterns of these fixtures (pinned venv): ringed 8.141409 vs 8.141408, compact 3.784992 vs 3.784992, demo 9.564626 vs 9.564626 (differences below 6e-7 px). Origin runs record the source in the lineage as `probe_radius_source` ("max" or "mean"); a manual or restored node with no fit behind it records "unknown", and a recording without the key predates the change (mean-era); `CalibrationSession.probeRadiusSource` selects the source (the mean option has no UI). Replay does not re-run origin calibration, so nothing is refused. Nothing else moves a number (the GPU measurement is unchanged).
- `H5Reader` reads through FormatoKit 0.5.0's `HDF5Reader` (the app's own libhdf5 symbol wrapper, link collector and typed readers deleted; 1146 -> 862 lines). Sidecar recognition, discovery, probe candidates, `DatasetDescriptor`, the calibration order and `H5Error` stay. Values are the same Float conversions (HDF5's native-float read became a Swift cast per stored type, rounding to nearest even). Kept as one marked shim, `HDF5LegacyProbe`, to delete when FormatoKit has them: the chunk shape of a dataset and h5py's bool-enum `QR_flip` (HDF5Reader refuses `enum`; HDF5Datacube refuses a file with a non-uniform dim vector, which the app accepts). Differences from the former reader: a float16 dataset or attribute of rank 2 or more is refused (read before), a non-UTF-8 string is refused (read with replacement characters before), and a link walk costs one file open per group and link. No pinned number moves.
- Spectro golden `velox-tiny.txt` gains four lines (`stageXMeters`, `stageYMeters`, `stageZMeters`, `instrumentClass = nil`): FormatoKit 0.3.1 and later add four optional `VeloxMetadata` fields, additive; no number moves. Updated on purpose.
- SpectroKit 0.6.0 -> 0.6.1 and FormatoKit 0.3.0 -> 0.4.0 (exact). libhdf5 is now FormatoKit's frameworks FormatoLibHDF5, FormatoLibSZ and FormatoLibAEC, embedded by Xcode in `Contents/Frameworks` and signed with the app's identity (the `FormatoKit_FormatoHDF5.bundle` resource folder of ad-hoc dylibs is gone); the harnesses point `MAC4DSTEM_HDF5_PATH` at the framework (`tools/lib/hdf5-dir.sh`). No number moves.
- SpectroKit 0.4.0 -> 0.6.0 and FormatoKit 0.0.3 -> 0.3.0, re-pinned together (exact). Nothing in either kit moves a number the app reads; SpectroCore 0.5.3+ now exports `MaskTransport`, `PoolBuilder` and `TransportedLabels`, so for a time the two files that imported both modules had to name the app's own (`DSTEMCore.`); those copies are deleted (see the registration switch above). SpectroKit 0.5.0 changed the CSV export's default title to the neutral "Spectroscopy quantification"; the app passes its own ("mac4DSTEM Spectroscopy quantification"), so exports and the golden hashes are unchanged. NOTICE: the redistributed libhdf5, libaec and libsz are FormatoKit's 0.2.1 rebuild (minos 15.0; new hashes and sizes), not the 2026-08-25 Homebrew builds.
- Reader switches onto the pinned kits (readers, hot-pixel filter, sidecar reads). Exact where it is data, written tolerance nowhere: no number moves.
  - `H5Reader` reads through FormatoKit 0.5.0's `HDF5Reader` for discovery, attributes and strings (the app's own libhdf5 symbol wrapper, link collector and typed readers deleted; 1146 -> about 900 lines): one libhdf5 loader in the process, and the writer and the shim below use the kit's candidate list (`FORMATO_HDF5_PATH` first, then the host's Frameworks, then the bundled framework); `MAC4DSTEM_HDF5_PATH` is no longer read by the app. Pixel slabs are read as before: one file handle held for the reader's life, `H5Dread` into `H5T_NATIVE_FLOAT` (the kit's per-call open measured 1.5-6x slower per pattern and 1.45x the peak memory on Au_sim.h5; with the handle: 0.011 s against 0.010 s for 300 patterns, 122 MB against 120 MB). Marked shims (`HDF5LegacyProbe`, `HDF5SlabFile`, "delete at FormatoKit 0.6.0"): that slab read, the chunk shape, py4DSTEM's bool-enum `QR_flip`, and float16 datasets (slabs, scalars, dim vectors and origin maps all read through libhdf5's conversion; tested). float16 attributes (scalar or one-dimensional) are read by the kit (tested). Behaviour changes, all for hostile or odd files: a string attribute or dataset that is not UTF-8 is refused (it was repaired); a one-element attribute of rank 2 or more, and an unsigned 64-bit attribute above Int64.max, now read as absent (they were read); a variable-length string dataset is capped at 4 MiB (it was unbounded; fixed-length strings keep the 4095-byte cap); the link walk of discovery and probes costs one file open per group and link and walks the links as `H5Lvisit2` did: in name order, a group entered the first time any hard link reaches it (object identity, so an alias or a cycle is listed and not entered again, and the listed path is the first in that order), a soft or external link listed and not followed (tested: a cube four `data` groups deep, a hard-link cycle, an alias that sorts first).
  - `MIBReader` reads through `FormatoMIB.MIBReader(.appScanXY)` and `EMPADReader` through `FormatoEMPAD` when its XML names the scan the way RosettaSciIO reads it. Kept in the app, marked "delete at FormatoKit 0.6.0": the former frame reads for a MIB the kit refuses (a header size other than 384 or 768, no width and height in the header, a detector that disagrees with its assembly; tested with a 512-byte header; the kit's reason is written to the activity log), and for EMPAD the XML with `scan_resolution_x/y` (the app's precedence over the kit's `pix_x/pix_y`, so a file with both is never transposed), a raw file the kit would resolve differently, and the raw-only square-scan fallback. The kit reads only an XML the app's parse cannot take; its disk watch is opened before it maps the file. The kit maps the files, so both readers run `MappingLiveness` before every read (`VendorRawError.volumeGone`). An EMPAD pixel calibration is still not imported.
  - The hot-pixel filter is CuboCore's `HotPixelFilter.mask` and `replacing` (the app's 96-line copy deleted); the Double-accumulated mean stays (the kit's `filter()` accumulates in Float32). The kit refuses a non-finite mean, threshold or pixel where the app computed with it: `WriterError.hotPixelFilterNeedsFinitePixels` says "Switch the hot-pixel filter off or crop away non-finite pixels" (tested with a NaN source). Replacing the pixels of 1024 patterns of 256x256 took 0.09-0.10 s against 0.035-0.054 s (each pattern is copied once); against the I/O of an export it is negligible.
  - Session sidecars are READ through `HDF5Reader` and, for the peak grid, `BraggVectorsEMD.read(.appImageXY)`. The refusals keep their wording. Restoring the stored peaks is stricter (FormatoKit's `BraggVectorsEMD.read`): the scan shape `Rshape` must be present and agree with the grid, and a non-scalar calibration entry refuses the grid (the session load refuses such a file by name anyway); a hostile `Qshape` (NaN, infinity, a huge number) is refused by name, tested. A refused open still says why, but in the system's words: "Permission denied", "Operation not permitted", libhdf5's "file signature not found" (the raw `errno = N` line of the HDF5 stack is gone; sidecar-error-detail-test checks the words). `BraggVectorEMDWriter.swift` (3191 lines) is split by concern (no behaviour change). The sidecar writes and `write(vectors:)` stay on the app's HDF5 binding (kit asks in `docs/open-items.md`).
  - Not switched: `DM4Reader` (FormatoDM's `DM4Datacube` was 7.6x slower on a float32 whole-scan tile, refuses DM3 and a declared data length of 0, and always maps non-local volumes); asks in `docs/open-items.md`.
- CI: the kit-module builds in `tools/lib/sources.manifest` use the swiftbuild backend explicitly (the runner's Swift 6.3.3 defaulted to the native one, which has no `out/Products/Release`), and the inventory job resolves the pins so the libhdf5 hash check runs.
- Kits re-pinned: SpectroKit 0.7.0, FormatoKit 0.5.0, DiffractoKit 0.5.0, CuboKit 0.4.0, ImagoKit 0.2.0 (the phase-2 switches follow). No number moves (unit 2404 / 0, scientific 0, inventory 0). `tools/lib/sources.manifest` keys kit objects by file name so two kit builds of the same ImagoKit modules do not link twice.
- Friedel origins and the beamstop mask are CuboKit 0.2.0's `FriedelOrigin` and `BeamstopMask` (the app's copies deleted), computed in Double instead of Float32. Measured on the friedel-origin-test fixture: clean origin (15.28615, 17.62265) -> (15.286150, 17.622649), masked (15.278842, 17.603392) -> (15.278841, 17.603392); the distance to py4DSTEM's origin fell from 1e-6 px to 2e-15 px; the beamstop mask stays pixel-identical (453 of 1024). No test tolerance changed. The kit refuses a beamstop mask with no pattern pixel (the app used to return an origin from noise). The app still fills non-finite pixels by their neighbour median before the kit sees them.
- `BeamstopMask.make` (CuboKit 0.2.0) refuses what the app's copy let through: a NaN pattern, a threshold index equal to N, and a cleaned mask with no pixel outside the pattern. The Friedel `tiledRun` therefore throws where it used to return a mask. The review-row-24 Friedel test moved with the switch and now runs the whole `tiledRun` path, asserting 0.05 px on the fitted origin (it asserted 1e-4 on `FriedelOrigin.origin`); a new test with a bar beamstop fails if the mask inversion (`!`) in `tiledRun` is dropped.
- The probe kernels are built by CuboKit's `CuboVirtual.ProbeKernel` (shift, normalisation, sine² trench, flat Fourier shift; Double) behind the app's `ProbeKernel` container, provenance and FFT, which stay. The app keeps the logistic disk of the synthetic kernel (pixel-centred; the kit's `SyntheticProbe` is half-pixel-centred for an odd detector side and changes sim_Au's candidate counts) and the cosine-shoulder mask of the measured sigmoid kernel (a recorded DEVIATION from py4DSTEM). Measured, Float -> Double rounding only (peak counts unchanged): disk-correlation-parity 128 x 128 intensity checksum 154.04683841811493 -> 154.0466591604054, correlation-maximum checksum 17.510809689760208 -> 17.510791689157486, position checksum 687538.0650752505 -> 687538.0648854703; 250 x 250 intensity 22.070654947310686 -> 22.070630181580782, correlation maximum 8.75485235452652 -> 8.75484350323677, position 144000.3197709527 -> 144000.31993879913 (baselines re-pinned on purpose: the old kernel normalised by a Float sum). No other pinned number moved.
- The least squares under `OriginCalibration.fitOrigin` / `fitOriginTrimmed` is CuboKit's `OriginFit.fit` (Householder QR in Double) in place of the app's normal equations; the trim (median + 3 MAD rounds), `TrimmedFit` and the Metal measurement stay. Two edge behaviours follow the kit: a non-finite included measurement is left out of the fit instead of turning every fitted value NaN, and a large enough but collinear included set is projected where the app averaged (a scan one position wide or fewer included positions than model terms still gives the included mean). No pinned number moved.
- ACOM's 1D FFT is ImagoKit 0.1.1's `ImagoFFT.FFT1D` (the app's copy deleted); ImagoKit re-pinned 0.1.0 -> 0.1.1 (now GPL-3.0). No number moves.

## v4.5.0 — 2026-10-05

**Requires macOS 27 on Apple Silicon**, as v4.0.0. Cut 2026-10-02 as 4.1.0 and never published; released as v4.5.0 as it stands (owner, 2026-10-05, ADR 052). This release finishes and removes more than it adds: the workspaces follow the data, the loose ends of v4.0.0 are closed, and several numbers moved (see "Science changes"). Every item passed the unit, core and inventory gates; "unverified on screen" means exactly that. Anything labelled unvalidated has not passed on a dataset with truth.

### Workspaces and data

- **Workspaces follow the data:** Prepare · Imaging · Bragg Disks · Crystal Maps · Reconstruction · Results.
- **Preprocess Raw Data… (File menu).** One sheet for a raw file or the open view: scan stride, detector crop and a port of py4DSTEM's hot-pixel filter, matched against py4DSTEM's own chain on one test cube. It refuses to write over the source, a link to it, or its sidecar.
- **Keep in memory** switch in the load configurator. The phase-contrast memory budget is the larger of 1 GiB and half the RAM minus the resident cube.
- **Results › Export Data…** writes the scalar product as an EMD RealSlice `.h5`.
- **Detected Bragg disks are restored** from the session sidecar. **Allow Access…** grants a sidecar the sandbox refused.
- **Lineage:** products name the run that made them, go stale when off the active path, and **Rewind to Here** restores a run's settings and marks later results stale. A calibration change marks strain, ACOM, phase and DPC results stale.
- DM4 files are memory-mapped on every local volume.

### Bragg disks

- **On-device training (MPSGraph).** Train a disk detector in the app; **Import Labels…** and **Export Labels…** (a Save panel). The Train Model… flow is unverified on screen.
- **The learned detector is back on the Neural Engine.** On a Mac without one it refuses rather than run elsewhere.
- Manual detector-ellipse field (a, b, θ). Ring-probe hint "Use N px". Origin-trim wash in Prepare.

### Crystal maps

- **ACOM mirror pass** (py4DSTEM's inversion symmetry) with a Mirrored Yes/No readout and a note saying the in-plane angle is relative to the matched template.
- **Phase mapping** (unvalidated): claimed-disks overlay, Al-Mg-Si preset, per-phase excitation slab, one structure at two zone axes, a known-variants evidence guard and precipitate objects.
- Add Phase marks an already-added CIF "(another zone axis)".

### Reconstruction

- Single-slice ptychography probe takes defocus, C12a/b and the parallax aberration fit, recorded in provenance and restored on replay. The ptychography harness is scored against a known object.

### Science changes (numbers can move)

- **Default disk-detection floor 0.5 % → 0.15 %**, a documented deviation from py4DSTEM (ADR 041).
- **R–Q rotation is shown and written in py4DSTEM's convention** (ADR 040). Exports made before 2026-09-28 say the sign is unrecorded.
- **Areal precipitate density is edge-corrected** (Miles–Lantuéjoul, ADR 045). The map is unvalidated.
- Parallax: the bin schedule repeats the finest bin; the aligned-BF vignette is fixed; the stack mean is summed in Double. Ptychography re-centres on the fitted origin, clamps |O| ≤ 1 by default, and loses its difference map and "Take higher-order terms".
- Strain: a circle ROI is centred; empty positions are out of the median; non-finite pixels are filled; central-beam-only positions no longer enter the strain basis.
- Learned detector above 256 px: seam margins and one dose scale. Odd-N DFT upsampling wrap fixed. Bin-2 aperture default.
- Virtual detector presets: BF 0…r and ADF 3r–6r from the measured beam.
- CIF import refuses a short symmetry list and a multi-structure file.
- Number entry: a period is no longer a thousands separator in comma locales.

### Fixes

- A launch crash at a 915-pt window and an abort when opening the then AI Analysis room. Disk-detection GPU memory is flat per tile. A bf16 pooling crash on M5 and a training step-loop leak.
- A map that finishes after a room switch keeps its own room's label (see "Results in the right place" below; other room-switch gaps are under Known limitations).
- The hexagonal IPF key names its corners the right way round (labels only; the v4.0.0 known issue). A radius-only aperture drag keeps the fitted origin. Single-slice ptychography exports carry the object sampling, not the scan pixel size. The ACOM plan is rebuilt after a CIF re-import or a voltage edit.
- Graphene real-space preview no longer black; parallax and ptychography colour maps.
- The strain line reads "Components along detector x/y — R–Q rotation not calibrated".
- Three code-review rounds: replay provenance, Q unit guard, label-import checks, two-window and candidate data safety, sidecar attribute guard, cancel token, reopen.
- Wording and accessibility-label polish across the rooms.

### Found by the pre-release review (2026-10-02)

A whole-app review before this release (six independent reviewers, each finding checked by a second model;
`../_archive/mac4DSTEM/docs/archive/v4/prerelease-review-2026-10-02/`) found these, all fixed with a test that fails without the fix:

- **Your data.** The dataset itself could be chosen as the destination of a first session save, Change Session
  Sidecar… or Export Bundle and be replaced; it is now refused. A session file that HDF5 could not open (for example
  held open by HDFView) was replaced by an empty one; it is now an error. Hand-clicked labels that were not restored
  on reopen are kept through the next save. Opening another dataset while a session save runs is refused. A dataset
  already open in another window is not opened twice (owner's choice), and a save that would relabel results computed
  on another view is refused (owner's choice). The refusal at macOS's Replace prompt is unverified on screen.
- **Results in the right place.** A Bragg vector map, diffraction-groups or phase map that finished after a room switch
  was labelled and saved with that room's frame and units; a probe kernel built for one dataset could land on the next
  and crash. A saved map whose shape does not fit the opened view is no longer restored onto it.
- **Memory.** A binned view read up to bin² more than its memory budget (16× at bin 4) in every streaming pass, the virtual image and parallax preprocessing included. On binned views the mean
  pattern can differ from 4.0 in its last float32 bits (up to ~1e-6 relative, one cube measured); the max pattern and
  every unbinned view are bit-identical. The phase-contrast budget now counts stages already held.
- **Science display.** The ptychography seed line printed the R–Q rotation in the opposite sign to Prepare; both now use
  py4DSTEM's sign (measured against py4DSTEM). An exported PNG of an unvalidated product says UNVALIDATED on its face;
  DPC exports name their frame.
- **First run.** ⌘R did nothing in some rooms without saying why; Add Phase could add the wrong phase after a refused
  CIF; an offline Materials Project fetch printed a raw error dump; the error alert's "Open Another…" (which replaced the
  open dataset) is gone; Settings' unused "Log verbosity" is gone.
- **Quit.** Quitting while a file read was in progress could crash at quit; quit now waits for the read in flight. Malformed values in a session file are refused by name instead of overrunning memory.
- **Repository.** SECURITY.md now states the one network request (Materials Project, started by you); CI says what it runs.

### Polish before release (2026-10-04)

Rough edges left after the review, each fixed with a test that fails without it and checked by a second model
(`../_archive/mac4DSTEM/docs/archive/v4/polish-plan-2026-10-02/`):

- The status strip shows the app's memory (Activity Monitor's Memory column), not the pages of a memory-mapped cube
  (it read 23.1 GB for a 15.8 GiB cube). Open Dataset… and Preprocess Raw Data… work with no dataset window open — they
  open one. The fit overlay's key stays in the diffraction pane's corner when you zoom; the annulus' inner handle no longer
  touches the centre handle at inner radius 0.
- Removing a saved result no longer clears an unsaved image on screen, or a different saved result you are viewing. A session
  file macOS will not let the app read is explained by what to do (Allow Access…), not by an HDF5 error; the raw error is in the Log.
- Preprocess Raw Data… writes the accelerating voltage (the session's, or the raw file's own) into the exported file, so a
  reopened export no longer reads "Not set" and DPC, parallax and ACOM run on it.
- Opening a dataset shows its virtual image whatever task was last used (it ran that task, e.g. a whole-scan DPC). Go to <room>
  and the shortcuts show that room's own result; Diffraction groups shows its map again when you return to it.
- A number field no longer rounds its value when you merely click into it or leave the room: a Defocus seeded by Use Parallax
  Fit kept only 0.1 Å, and leaving Orientation after dragging the exploratory scale discarded the ACOM map. Preprocess's Write
  uses the threshold you just typed (a mouse click on Write wrote the previous one).
- A DM4 cube whose disk is disconnected (an SSD pulled while the cube streams) no longer crashes the app on the next read: it says
  "<file> is no longer reachable: its disk was disconnected. Reconnect it and reopen." and keeps refusing until reopened.
- The SCAN navigator sits in the diffraction pane's corner, beside the pattern it drives, instead of over the Bragg vector map or
  a reconstruction, and keeps to a 118-pt box on non-square scans (a 17 × 77 scan drew it 534 pt tall over the pattern).
- Dataset › Ignore Session Sidecar… (and the inspector's Reopen Without This Session) asks first and says what is lost. The sidebar's
  session warnings show their whole headline and put the way out first, with the full explanation on hover.
- The bottom Lineage/Output area keeps at least 140 pt when open (about three rows), on drag and on reopen; a drag below 70 pt
  closes it. Imaging › Virtual detector no longer offers Compute Image (the image updates as you drag; Group Patterns keeps its
  button, ⌘R follows). The promote caption no longer claims the Mac is kept awake (that is a setting, off by default).

### Removed

- The Settings engine picker, the unwired image-segmentation path, the ptychography difference map and the higher-order toggle.

### Known limitations

- **Phase mapping and everything derived from it are unvalidated.** The first scored run failed one metric (θ′ edge-on speckle 7, bar 5); the quantity ships, not a verdict (ADR 048).
- Known-crystal Q reads the (200) ring as (111) on an Al [001] majority, 12.5–13.5 % low; the shell ratio is shown beside it.
- ACOM's in-plane map mixes the mirrored +π convention; the export has no per-pixel flag.
- A crash right after Compute Strain was seen once (a layout loop inside the toolbar) and not reproduced in 12,000 stress cycles; the cause is not established.
- `scan.dm4` and `scan.h5` in one folder share one session file (named from the stem), so opening one can adopt the other's calibration (owner's decision for this release).
- Unverified on screen: Train Model…. Room switches still have gaps: Imaging can keep showing another room's map (Go to Imaging can show the Bragg vector map), Strain or Orientation can read "No Result Yet" while their result is held, Imaging reads "No Result Yet" after another room cleared its image until an aperture edit, and the ptychography pane can be titled "Parallax aligned BF" before a run (seen 2026-10-04; deferred).
- **Velox `.emd` files are not supported** (EDX is v5.0, ADR 052): the reader opens a Velox file as a meaningless one-row cube built from its HAADF image stack (reproduced at the reader on 9 of 10 public Velox test files, 2026-10-05, not driven in the app; a single-spectrum file is refused).
- After a save that relabels a view, a reopen can restore stored Bragg disks from the earlier view at the new view's positions (same shape, other offset).
- A 2H-WS₂-type reference shell on a [0001] zone can pick an invisible (0002) ring, a predicted 2.26× Q mis-scale with no warning.
- Small: the ptychography seed line cuts at "defo…" (hover shows it); the ACOM Q read-out uses a decimal point beside comma fields; shrinking the window to its floor can collapse the sidebar for good.
- On a beam whose 3r reaches the detector edge (e.g. a ptychography cube) the ADF preset falls back to detector fractions without saying so.
- Export Data… dimensions read as pixels in py4DSTEM; the true sampling is in the file's attributes.
- Annulus with inner radius 0 excludes the centre pixel; py4DSTEM's convention is unchecked.
- Quitting waits for a file read in flight: seconds from an internal SSD, longer from a slow external drive.
- A disk disconnected at the very instant a DM4 read is in flight can still crash the app.
- Macs without a Neural Engine cannot run the learned detector. The Neural Engine return was measured on one Mac (M5 Pro, macOS 27.0.1).
- A Q edit still deletes the ACOM map instead of marking it stale, and Clear Calibration records no calibration node (open-items, 2026-09-30 register residuals).
- Preprocess deviations from py4DSTEM: the bin sum order is not bit-identical with numpy's float32, and the hot-pixel filter's mean is Double where numpy's is float32.

## v4.0.0 — 2026-09-23

**Requires macOS 27 on Apple Silicon.** The major version marks the system
requirement: v3.0.0 (macOS 14+) stays downloadable for older systems. This
release carries the v3.1 calibration foundation (on `main` since 2026-09-17)
and a rebuilt interface. Every item passed the unit, core and inventory
gates; "unverified on screen" means exactly that.

- **The interface, rebuilt on Apple's own guidance (2026-09-22 night).** A
  flat inspector — each section's title is its disclosure, labels on the
  left, controls and values at the edge, one button width, status colour on
  symbols only; the room's one prominent action is its toolbar verb. Image
  contrast (histogram, gamma, log) lives in each image's own popover;
  "Computed this session" in the Info tab; Bragg disks' probe kernel is one
  source picker and one Build button. The toolbar keeps the run verb and
  dataset menu as the window narrows; the window has a derived minimum
  (915 pt) so no pane is ever covered by the inspector. Driven and accepted
  by the owner on a real cube.

- **Known-variants phase classification (2026-09-21, experimental, unvalidated).** The rule from
  Thronsen et al.'s vector analysis — score every surviving vector against each phase's known
  variants, no floors — ships beside the search rule, off by default. Measuring it exposed that
  the T1 reference dropped its weak {014}/{214} reflections under the 5 % intensity floor; at
  floor 0 it scores 2.64 % on the published truth (search 3.77 %, was 4.21 %). Phase mapping
  gained a Classifier picker (Search / Known variants), and every map now feeds the class-map →
  objects bridge: object count, median length and areal density per precipitate phase in Results,
  density only when the scan is calibrated. Probe flags `--rule`, `--min-intensity`, `--dump-entry`,
  `--residual-detail`, `--survivor-detail`, `--slab`.

- **Materials Project importer (2026-09-21).** The default phase source: an API key entered once
  in Settings (Keychain), then any material by mp-id. `MaterialsProjectImport` decodes a
  `materials/summary` document, standardises a centred primitive cell to the conventional cell
  (F/I/C/A/B/R; refuses what its metric, volume and site guards cannot verify), classifies the
  family with the CIF importer's own function, and refuses a material whose formula matches but
  whose space group does not (mp-1185307 vs T1 is a test). Provenance keeps the mp-id, fetch
  date and cell note; `spaceGroupNumber` is also read from CIFs. Pickers now offer only
  "Materials Project…" and "Import CIF…"; presets stay resolvable for replay. The Keychain is read
  only when a view shows the key state, never when a window or a test builds `AppState` (the owner
  saw the access prompt storm from a test run, 2026-09-21, fixed). Unverified on screen.
- **Origin validity mask.** The robust origin fit now keeps the positions it
  excluded (`OriginMaps.originValidity`), and Prepare shows "N of M
  positions". No fitted number moved. The spatial overlay is still owed.
- **Beamstop-tolerant origin.** `get_origin_friedel` and `get_beamstop_mask`
  ported (parity ~1e-6 px; mask pixel-identical to scipy on the Au_ref cube),
  behind a Prepare "Origin method" picker — additive, the default is unchanged.
  Unverified on screen.
- **Vacuum probe from a separate scan.** MapSettings "Vacuum Scan…" imports a
  vacuum cube and builds the probe kernel from its mean pattern; refuses a
  detector mismatch. Unverified on screen.
- **Speed.** Friedel full-scan and the R–Q rotation solve run across cores;
  both proven bit-identical to the serial code.
- **Repository.** One branch, `main`; a pre-push hook that builds the app
  target; a size guard on tracked files; `SECURITY.md`.
- **AppState split, step one.** Calibration and phase-contrast orchestration
  moved verbatim into their own files (AppState.swift 5476 → 4699 lines);
  no logic changed, 17 members widened from `private` for the move.
- **AppState seams 1–4.** Phase contrast, ACOM, disk detection and DPC state
  moved to feature owners; their cross-owner orchestration moved to focused
  extensions. AppState.swift 4699 → 3676; details and gates are retained in
  `../_archive/mac4DSTEM/docs/archive/v4/appstate-seams-plan.md`. All four were later owner-driven with seam 5.
- **AppState seam 5: `ResultPresentation`.** Shared product/display state moved to one owner and cross-owner orchestration to `AppState+ResultPresentation.swift`; AppState.swift 3676 → 3240. Seven tests pin version bumps; unit 727/0/2 and rotation/strain-frame parity passed; the owner drove `sim_Au` normally.
- **AppState seam 6: `DatasetSession`.** Reader/array, datasets, preview, loading state and stale-publish epoch moved to one owner and lifecycle orchestration to `AppState+DatasetSession.swift`; AppState.swift 3240 → 3054. Five tests pin ownership/epoch; unit 732/0/2 passed; the owner drove open → switch dataset → reopen ignoring sidecar normally.
- **AppState seam 7: the load pipeline, and the seams plan is complete.** Configured-open split into `AppState+Open.swift`/`+Promote.swift`/`+Replay.swift`; the pending-load owner is `Session/PromotionRun`. AppState.swift 3054 → 1474 — no longer the repo's largest file. Caught and fixed a regression before commit: the moved `commitPendingLoad` cleared its owner before finishing the refusal guard, so a beam-excluding crop silently dropped the configurator's pending load; a new test (`PromotionCommitTests`) pins the correct behaviour. Unit 741/0/2=743 passed. All seven seams of `../_archive/mac4DSTEM/docs/archive/v4/appstate-seams-plan.md` are now landed; not yet driven on screen.

### Known limitations

- **Phase mapping and the known-variants rule are unvalidated** and badged so
  in the app until they pass on a dataset with truth.
- **Unverified on screen:** the Friedel origin method, the vacuum-scan probe,
  the Materials Project importer's first live fetch, light mode on a real cube.
- **Deferred to the next cut (owner, 2026-09-22):** the release-readiness
  Gate D items listed in `docs/status.md`.
- At the 915-pt minimum window width a long file name can push the toolbar's
  centre display out, and the toolbar's buttons then shift left.

## v3.0.0 — 2026-09-11

The first release with a machine-learned feature, and the first major version
since the SwiftUI rebuild. Everything below shipped through the repo's gates;
what is **not** verified is said so in "Known limitations" at the end of this
section rather than left for a user to discover.

### Learned disk detection on the Neural Engine — the first ML feature

- **Bragg disks can now be found by a trained model instead of template
  matching.** Disk detection gains a `Detector` picker (Classical / learned);
  the learned path runs as Core ML on the Apple Neural Engine. The model is a
  256-px detector, default confidence 0.7 (owner's decisions, 2026-09-08).
- **It earns its place on a frozen, hand-labelled test set**, never used for
  selection. **At the shipped default confidence of 0.7**, recall / precision is
  **0.768 / 0.712** against the classical detector's **0.487 / 0.485** on the
  same set. Raising the threshold to 0.9 trades recall for precision —
  **0.667 / 0.840** — and the whole sweep is in the evidence. Speed on the same
  cube is **1.44–1.64x** the classical path. Pre-registered before it was built,
  verdict recorded in `docs/decisions.md`; the evidence is
  `../_archive/mac4DSTEM/docs/archive/v3/learned-detector-2026-09-06.md`.
- **No third-party model weights are distributed.** The model spec ships in the
  repository and its asset tree is hashed by the `unit` gate
  (`LearnedDiskDetectorTests.testCommittedAssetHashMatchesItsRecordAndTheFixture`),
  so a clone reproduces the shipped model exactly.
- **The app ships the GNU GPL v3 text and `NOTICE` inside the bundle**, beside
  the HDF5 and libaec licences that were already there. Until now the README
  inside the app pointed at two files the download did not contain.

### Fixes and robustness

- **mac4DSTEM now appears in Finder's "Open With" for h5 / hdf5 / emd / dm4 /
  dm3 / mib**, ranked `Alternate` so it never takes a format away from whatever
  already owns it. **Double-clicking a dataset launches the app but does not yet
  load the file** — the document types are declared, the URL handler that would
  receive them is not written. Open from the app instead. Listed again under
  Known limitations, because a declaration without a handler is exactly the kind
  of half-feature a user discovers the hard way.
- **The first session sidecar is no longer named `.mac4dstem.h5.h5`.** The save
  panel appends the extension it requires, and it was being handed a name that
  already had one.
- **A disk-detection warning is no longer below the fold.** When the median
  pattern keeps at most one peak — the direct beam only, which is what a
  too-strict relative threshold looks like — the warning explaining it now
  renders above the peak counts instead of after them.
- **The Info tab no longer describes a button that is not on it**: the
  "Reloads the whole cube" cost sentence moved to the Reopen at Full Extent
  button in Settings, and `Size (f32)` now reads `Size as float32`.
- **The real-data acceptance goldens are re-pinned, and a fifth cube joins
  them.** `run-tests.sh all` had been red since 2026-09-08 on
  `downsample_Si_SiGe_exp` candidate counts. Gate D established the cause:
  the 2026-09-05 correction of the probe estimator's threshold-slope median to
  `np.median`'s even-count rule moved the measured radius on two cubes, and the
  goldens — reachable only from `all`, which had not run in three days — were
  stale. **No behaviour changed**; the app already matched py4DSTEM. The
  even-count rule is now pinned by a unit test rather than by one harness in
  one gate, and `calibrationData_bullseyeProbe.h5` is pinned in
  `expected.json`, having drifted invisibly because nothing compared it.
- **Labels that could misstate a number, from the 2026-09-04 UI review.** The
  inspector's pattern statistics say "Mean pattern", "Max pattern" or
  "ROI-sum pattern" when that is what is on screen; the A/B/A−B comparison
  panels carry a colorbar with range, units and a zero mark; the cursor
  readout prints four significant digits instead of a raw float; a strain or
  orientation map computed from Bragg disks whose settings have since
  changed is flagged in the sidebar and the inspector with the same words as
  the result pane; the scale bar never prints a unitless sampling as "px";
  and without a probe kernel detected peaks are marked with a cross rather
  than circled at an invented radius.
- **Pane headers compress instead of clipping**, with an overflow menu for
  the controls that no longer fit, and the diffraction/real-space divider
  keeps its position across loads, trips to Results and reopening.
- **3.0.0 ships as Apple Silicon only, which is what the app has always said it
  requires.** v2.5.1's executable was a universal binary — `lipo -archs` reports
  `x86_64 arm64` — while the three HDF5 libraries inside it are arm64-only and
  are loaded at runtime rather than linked. On an Intel Mac running macOS 14 or
  later that build launches, and DM4, MIB and EMPAD data still load, but every
  `.h5`/`.emd` open and every EMD export fails with "Could not load the bundled
  HDF5 library". **That behaviour is predicted, not observed: no mac4DSTEM build
  has ever been run on Intel hardware.** The cause was simply that the v2.5.1
  project file pinned no architecture at all, so Release fell through to
  `ARCHS_STANDARD`. 3.0.0's executable, all three embedded libraries and its
  dSYM are `arm64` alone, measured with `lipo` on the archive's own product —
  and the packaging gate now builds the way the release builds and measures the
  result, instead of trusting a build setting that was already saying `arm64`
  while the archive compiled Intel.
- **`NOTICE` gains a machine-learned-models section**: no third-party model
  weights are distributed; the AGPL `yolov8n.mlpackage` briefly in the Xcode
  project was never in a shipped build and left the tree on 2026-09-07.

### Science — measured numbers that moved

- **A flat measured kernel, and the file's own probe as a kernel source.**
  py4DSTEM's `Probe.get_kernel` recommends the FLAT mode — the probe
  normalised and shifted, nothing subtracted — "for bullseye or other
  structured probes"; the app's measured kernel could only subtract the
  sine² trench, which at the estimator's under-read radius (7.4 px for a
  ring that ends at ~10–12) leaves the beam never the brightest correlation
  peak on the bullseye probe — flat needs no radius. Map ▸ Bragg disks gains
  a measured-kernel mode (flat by default / sigmoid trench) and **Use File's
  Probe**, which reads py4DSTEM's probe from the file on the cube's detector
  grid in both layouts: legacy v0.12 `probe_template` (Qx, Qy, N) and the
  modern `Probe` node (2, Qx, Qy), slice 0 either way. On
  `calibrationData_bullseyeProbe` the app's flat file-probe kernel
  reproduces py4DSTEM's flat route peak for peak — 878 of 878 within
  0.0013 px and 164 of 164 exactly at two thresholds, both sides pinned to
  the template's centre (125, 125), poly subpixel, 90 positions — and the
  kernel built at the app's own probe centre matches to 3e-6. Provenance
  records `kernel_mode` and `kernel_probe_path`; a file-probe kernel refuses
  to replay rather than substitute (the recipe names the path; rebuilding it
  is owed). Unverified on screen. The probe-size estimator still reads a
  ring-shaped probe small — open item.
- **The one-peak-per-pattern warning names the threshold.** When full-scan
  detection keeps at most one peak in the median pattern, the Bragg panel
  used to say "spacing or thresholds may be too restrictive". It now names
  Min relative intensity with its value, says that with Relative to peak 0
  the reference is the brightest peak — the central beam when it is in the
  pattern — and offers the two remedies. WS₂ is the case: its disks are
  ~0.2 % of the beam and the shipped 0.5 % rejects every one. Unverified on
  screen. The default itself is unchanged: measured on six training cubes,
  moving the reference to the brightest disk floods noise (WS₂ 1 → 45 peaks
  per position where ~13 are disks; sim_Au and MgO saturate the 70-peak cap),
  so the remedy stays a lower threshold per dataset
  (`../_archive/mac4DSTEM/docs/archive/closed-items-2026-09.md`).
- **The diffraction origin is measured where the beam is.** The per-pattern
  centre of mass took one pass in a window of 1.2 × the probe radius around a
  coarse block centre; on a small beam the window could not reach it and
  every position read 0.25 px toward the block (WS₂: 63.99 for a beam at
  63.74, which every radius, Q scale and strain number then carried). The
  window now recentres on its own estimate and is never smaller than the
  probe radius plus 1.5 px, so the beam's soft edge is inside it (Gate D
  and Gate B, `../_archive/mac4DSTEM/docs/q-calibration-design.md` §9). How far an origin moves
  depends on where the beam sat in the coarse block grid, not on the disk
  size: across ten training cubes the mean origin shifts between 0.001 px
  and 0.77 px, single patterns by up to 1.3 px, and the new values track an
  independent wide-window reference within 0.02 px on every clean cube.
  Translating a pattern now moves the measured origin by exactly the
  translation (it was off by up to 0.65 px).
- **A legacy py4DSTEM v0.12 `realslices` stack is refused as a datacube.**
  The string-label rule applied only to `diffractionslices`, so a strain
  stack stored (R, R, 4) with label strings in `dim3` opened as a cube with a
  four-pixel detector. The check pinning this had been committed red on
  2026-09-05 and no gate ran after it; the `peak-overlay-test` harness had
  also stopped compiling the same day. Both fixed, the gate rerun in full.
- **Q calibration from a known crystal averages the innermost shell's
  equivalents instead of taking the smallest.** The smallest radius was the
  same spoke almost everywhere — a small origin offset makes one side of the
  ring read short — so the pixel size came out 2.1 % high on the WS₂ training
  set; the cluster mean cancels the offset for a symmetric set and agrees
  with the file's second shell to 0.001 px (Gate D and B,
  `../_archive/mac4DSTEM/docs/q-calibration-design.md` §8). The estimate reports how many peaks it
  averaged. Known limit: on a single crystal whose Friedel pairs differ in
  radius the band can truncate the cluster (recorded).
- **A recipe cannot replay against the wrong CIF.** Imported phase models are
  identified by their file stem, so two different CIFs named alike shared an
  id and a saved recipe resolved either. The ACOM step now records a content
  fingerprint of the cell, symmetry and atomic basis, and replay refuses by
  name when the session's same-named import differs; older recipes without
  the key still resolve as before.
- **Origin calibration refuses instead of inventing a probe.** A mean pattern
  with no intensity above zero used to yield a 1 px probe at the detector's
  geometric centre, stored with "measured" provenance, and the calibration
  carried on against it. `probeSize` now reports nothing to measure, both
  calibration entry points refuse with a sentence, and a NaN or infinite pixel
  is one dead pixel rather than a poisoned maximum or a NaN centre (py4DSTEM's
  `np.max` would void the measurement; inline DEVIATION). The threshold-slope
  median now matches `np.median` for an even count — the port took the upper
  middle value alone, a Gate B finding; the probe radius can move by a
  fraction of a pixel on some patterns.
- **ACOM bundles carry the origin they were computed against.** The origin
  reference, fit residual and excluded fraction are snapshotted when the map
  is computed, as the strain bundle already did, instead of being omitted.
- **Selected-area diffraction's tile masks are pinned** by a ground-truth
  case whose region excludes whole scan rows; the mutation that survived every
  harness on 2026-08-27 now fails it.
- **Gatan STEM-SI DM4 files open with their axes in the calibrated roles.**
  Empty DM tag labels are resolved by physical sibling position (ncempy's
  rule), so the included `Si-SiGe.dm4` is discovered at all. Its calibration
  units name the leading pair real space and the trailing pair diffraction
  space, and the reader now uses that, so the file loads as a 77 × 17 scan of
  448 × 480 patterns with 2 nm and 0.062 nm⁻¹ pixels; before, the previews
  showed diffraction spots under "Scan" and the scan under "Diffraction", and
  py4DSTEM's reader loads the same file swapped, with pixel units (inline
  `DEVIATION`). **Whether the pattern's x and y are the right way round for
  this layout is not yet established** — the tags' x-first convention says
  448 wide, the reader currently says 480 wide — and is a Gate D item in
  `docs/open-items.md` awaiting the owner's GMS observation. A full-cube read
  of that file went from 19 s to under a second (a blocked transpose replaced
  the pattern-at-a-time gather). A DM4 whose four axis units cannot name one
  real and one reciprocal pair opens in the legacy layout with NO pixel
  sizes and a logged reason, instead of being refused. Ordinary
  detector-fastest DM4 files report their scan-crop pushdown again.
- **Manual Q and R pixel scales stay editable.** The field no longer vanishes
  when its row turns green: R is always editable, and Q is editable for every
  provenance except a value measured in the app from a known crystal, with
  the hover text saying which value an entry replaces. Both Prepare and the
  export sheet share the rule (`PrepareSettings.shouldShowManualScaleEditor`).
- **Discovery no longer takes any rank-3 array for a datacube.** py4DSTEM
  stacks (a strain map, a probe stack, any `_labels_` array) and this app's
  saved RGBA maps are refused by their own labels wherever they sit, and a
  genuine 4D cube anywhere in a file now outranks a rank-3 array anywhere —
  before, a shallow rank-3 sibling could be returned AS the data, and the
  pinned real files escaped only by where their nodes sorted alphabetically.
  Legacy py4DSTEM v0.12 slice stacks are refused too, by the string-typed
  label vector that format keeps. A file whose best node is an unlabelled
  rank-3 array still opens as one scan row, as before, and the v2.5.1 sidecar
  location guard stays. Gated by the new `tools/harnesses/datacube-discovery-test`
  harness (27 fixtures) and five unit tests. The unit gate passed with
  463/0/1 and the scientific gate passed all 43 harnesses on 2026-09-05;
  the closed item is recorded in `../_archive/mac4DSTEM/docs/archive/closed-items-2026-09.md`.
- **A rank-3 EMD file's pixel sizes were read from the wrong axes.** For a
  file stored as (N, Qy, Qx) the reader took the detector spacing as the
  real-space pixel size and found no Q size; it now reads the scan axis and the
  detector axis. Found by the Gate B refuter on the change above; only files
  with rank-3 data and EMD dim vectors are affected.

### Known limitations at 3.0.0

Stated here because a user should not have to find them.

- **Parallax and single-slice ptychography are untested on real data.** Both
  are marked `Advanced`. On the owner's machine they refuse a 268 MB cube,
  asking for 8.2 GB and 11.6 GB of working set against a 1.07 GB limit — the
  refusal is correct and names its remedy (crop or bin first), but whether
  those estimates are right has not been established, and no run on a machine
  with more memory has happened. `docs/open-items.md`.
- **VoiceOver is not supported.** Resolving an accessibility label crashes the
  app (a stack overflow inside SwiftUI's own label resolution). It affects any
  client that reads the accessibility tree, including UI automation. Deferred
  by the owner's decision of 2026-09-11, recorded in `docs/decisions.md`.
- **Session sidecars written before 2026-09-11 keep the quantitative badge they
  were saved with.** The origin verdict that badge should depend on was not
  recorded before then and cannot be reconstructed, so older results are left
  as they are rather than re-judged on a guess.
- **The `Quantitative` badge does not check the origin a result was computed
  from.** It is decided from the product's kind and units alone, so a strain,
  DPC or iDPC map can read `Quantitative` even when the beam centre it was
  computed against was never measured — including on the same screen where
  Prepare reports that origin as `Not quantitative`. The provenance shipped
  beside every result is honest about this: check `origin_reference` and
  `origin_reference_is_measured` in the Info panel or the exported keys before
  relying on the badge. A fix was written for 3.0.0 and **rejected by the
  project's own adversarial review** — it changed no behaviour — so it was
  reverted rather than shipped looking like a fix
  (`../_archive/mac4DSTEM/docs/archive/2026-09-11-drive/quantitative-badge-gate-b.md`).
- **macOS 14–25 is compile-verified, never executed.** Every machine here runs
  26. The first report from an older system is the test.
- **Opening a dataset by double-click is new and has not been driven on screen.**
  The URL handler landed with this release and is covered by the build, not by a
  human opening a file from Finder. If it misbehaves, File ▸ Open Dataset is the
  path every other release used.
- **Only one dataset can be loading at a time, and one window is the supported
  way to work.** The bundled HDF5 is built without thread safety, so the app now
  refuses a second open while one is in flight and disables "New Dataset Window"
  during a load. That removes the gesture that reached the hazard fastest; it
  does **not** make concurrent HDF5 safe. Two windows both computing can still
  abort the process. There is no autosave behind that, so save to a sidecar
  before starting a long run.
- **The hexagonal IPF colour key may be labelled the wrong way round.** The
  orientation *maps* are not in question; the small colour triangle beside them
  prints `11-20` and `10-10`, and the colour function makes green maximal along
  a₁ and blue along the 30° direction, which reads as the opposite assignment.
  Until it is settled against the convention, do not take crystal directions off
  the key — read them from the exported orientation data.
- **Single-slice ptychography's scale bar may report the scan step instead of
  the object sampling**, and its reconstruction parameters may be missing from
  the export. The two are physically independent. Treat a phase image's scale as
  unverified until this is resolved; the reconstruction itself is unaffected.
- **Intel Macs are not supported, and v2.5.1 offered them a slice by accident.**
  3.0.0 and later are arm64-only and will not launch on Intel hardware.
  mac4DSTEM has required Apple Silicon since v1.0.0 (`README.md`); if you are on
  an Intel Mac, v2.5.1 is the last build that starts at all, and HDF5 does not
  work in it. No one has reported hitting this.

## v2.5.1 — 2026-09-04

Lowers the system requirement and fixes a reader defect found by the gate on
release night.

- **macOS 14 or later**, down from 26. Exactly two symbols stood above the old
  floor, both cosmetic and both now behind an availability check: the toolbar's
  flexible spacer and the pane divider's resize cursor. Below macOS 15 the
  divider still drags, it just does not change the pointer. macOS 13 is not
  reachable — `@Observable` is macOS 14 and the application's state layer rests
  on it. **v2.5.0 cannot launch below macOS 26**; only this build reaches older
  systems. Development and testing are on macOS 26, and 14–25 has not been
  exercised on hardware, so a report naming your macOS version is useful.
- **A saved result is no longer mistaken for a datacube.** Opening a session
  sidecar directly — easy to do, since it sorts next to the dataset in the open
  panel — could return a saved RGBA orientation map as though it were the data,
  with a four-pixel detector, instead of saying what the file is. It now names
  the file and points at its dataset. The wider class behind this is recorded
  in `docs/open-items.md` and is not yet fixed: discovery still accepts any
  rank-3 array as a datacube.

### Verified by

- `tools/run-tests.sh all` — **exit 0**: 458 passed / 0 failed / 0 skipped,
  44 harnesses including `real-data-acceptance` and `package-test`, read from
  the gate's own exit line. This is the aggregate v2.5.0 could not claim.
- Gate B: four independent refuters, each building its own fixtures. They
  rejected the first version of the reader fix; what shipped is the reworked
  one, and what they left open is filed rather than quietly closed.
- **The shipped artefact.** Built from `a9a0437`, Developer ID archive,
  notarized twice as the procedure requires — the app
  (`fb693c50-c3c2-49a3-a851-b6da20668cff`, Accepted) and then the disk image
  built from that stapled app (`f3d05e79-0ede-4912-a52f-b35ad367db2c`,
  Accepted). Both stapled and validated; `spctl` on the DMG returns `accepted`,
  `source=Notarized Developer ID`. The app inside the shipped image declares
  `LSMinimumSystemVersion 14.0` — checked by mounting it, because that is the
  whole point of this release. `mac4DSTEM-2.5.1.dmg`, 6 157 051 bytes, SHA-256
  `302822063df22399d0fc4a8810fca6a55e53379df34ec4a37a0e0a738b8031af`.

## v2.5.0 — 2026-09-04

Rehearse an analysis on a cropped or binned view, then promote it to the
full cube unattended. Validated against py4DSTEM 0.14.19. (v2.0.0 was named
2026-09-02 and never built; this release supersedes it.)

### What is new

- **Load pipeline.** Open with options (scan crop, detector crop, detector
  bin), streaming residency for cubes larger than memory, and a promote run
  that replays the rehearsed recipe on the full cube, re-referencing
  detector-pixel parameters into the full frame. Reduced-file export carries
  the recipe.
- **Sidecar format.** Every session sidecar now names the oldest reader that
  interprets it without misreading. A v1.0.0 build silently restores
  reduced-view results against the full extent, which is why this is a major
  version, not 1.1.
- **Calibration honesty.** Q calibration from a known crystal, ellipse
  distortion, R–Q rotation; a fit that fails its gate reports "not
  quantitative" rather than a number. Probe radius is measured on the mean
  pattern. The DPC angle's 2π unit error is fixed and legacy sidecars migrate.
- **Refusals over guesses.** CIF import refuses what it cannot expand or was
  cut mid-row; ACOM replay refuses a phase model it cannot resolve by id and
  lattice constant; session calibration from a different frame is
  re-referenced or refused, never applied twice.
- **Workflow.** Prepare / Imaging / Strain & ACOM / Phase / Results, a system
  inspector column, a permanent status footer, colormaps on each pane's
  colorbar chip, detached long runs with live progress and Cancel.
- **Speed.** An exact Bluestein FFT for any detector size: Detect All Disks
  on a 250-px cube went from 14 min to under 15 s in Release, same peaks.
- **Consolidation (v2.5, 2026-09-02/03).** `Core/` and `Session/` are Swift
  packages; one product value carries pixels, units, frame, validity and
  provenance from compute to export; calibration, readiness, strain and ACOM
  state have single owners; the Phase workspace lists DPC & iDPC, Parallax and
  Single-slice ptychography as independent tasks with revisitable stages; each
  workspace has its own sidebar; the IPF map is confidence-gated with a slider
  on the colorbar chip. No scientific number changed. *(Amended 2026-09-04: the
  pane-focus routing described here — "the inspector follows the pane with the
  focus ring" — was deleted with the AppKit window. The rebuilt inspector has
  two tabs, Settings and Info, and renders both unconditionally.)*
- **The window is SwiftUI, and the AppKit one is gone (2026-09-04).** The
  hosted AppKit window's 32 files are deleted; `UI/` IS the rebuild, a
  `NavigationSplitView` with the native `.inspector` and no flag selecting
  between them. The inspector has two tabs, Settings and Info. The
  saved-session sidecar's contents — Calibration, BraggVectors, the saved
  results and the actions on them — moved out of Info into the left sidebar's
  Session section, so what came with a dataset is on the left where the
  dataset is; Info keeps the explanations for a sidecar that could not be read
  or did not fit. The status bar gained elapsed / throughput / ETA in a
  reserved fixed-width slot, and the output log moved off `AppState`.

- **Split view.** ~~The sidebar and inspector are AppKit split-view columns~~
  *(superseded 2026-09-04: the AppKit shell was deleted in `d5786e2` and the
  window is a SwiftUI `NavigationSplitView` with the native `.inspector`. The
  behaviour below described the retired columns.)* drag far, collapse past the
  minimum, reopen at the last width, the inspector gives way first, the
  sidebar may be up to 600 pt wide. Fixes the constraint-loop crash on a
  sidebar drag (SwiftUI's split view let the divider violate its own
  content minimum).

### Verified by

- **The full gate was attempted and did NOT pass, and this release does not
  claim it.** `tools/run-tests.sh all` ran on the release tree (2026-09-04,
  retained log) and **exited 1**: unit and 42 scientific harnesses green, then
  a failure in `real-data-acceptance` on a session-sidecar file — a defect that
  predates this release and is recorded, undiagnosed, in `docs/open-items.md`.
  `tools/harnesses/package-test/run.sh` is sequenced after that step and did not run in
  that pass.
- **What this release IS gated on**, both re-run on the final tree and each
  exit code read on its own line: `tools/run-tests.sh unit` — **457 passed /
  0 failed / 0 skipped, exit 0** across 63 suites (counted by `Suite.method`;
  one log line was chopped mid-name by an interleaved xcodebuild timestamp and
  was reconciled against the source file's 8 test methods, not assumed) — and
  `tools/harnesses/package-test/run.sh` — **exit 0**, which clean-builds a hardened
  Release and audits the artefact itself: nested signatures, sandbox and
  bookmark entitlements, no `get-task-allow`, no Homebrew dylib paths, the
  embedded HDF5 2.1.1 opening a checked-in fixture, and identity/version
  `2.5 (4)` with the macOS 26 floor as the project declares them.
- On screen: the owner drove the rebuilt SwiftUI app on 2026-09-04. A
  full-scan Bragg detection on `sim_Au_data_all_binned.h5` confirmed the status
  bar's live elapsed / throughput / ETA and the output log still updating after
  `ActivityLog` took it off `AppState`; the sidecar contents were checked in
  their new home in the left sidebar. Two things remain unverified on screen —
  a cropped save → quit → reopen, and every divider, which no gate can measure.
- **The shipped artefact.** Built from `3c0a3eb`, Developer ID archive, then
  notarized TWICE as the procedure requires — the app
  (`af7cc0f4-d354-4c7a-bcb9-d245deda5ea1`, Accepted) and then the disk image
  built from that stapled app (`f4aa1d12-91a4-412d-8ad9-979289aede6c`,
  Accepted), because Gatekeeper assesses the thing the user opens. Both stapled
  and validated; `spctl` on the DMG returns `accepted`,
  `source=Notarized Developer ID`. `mac4DSTEM-2.5.dmg`, 6 074 038 bytes,
  SHA-256 `d55821a11dde44b6fc2d1337f43b5eb3ec2342fe6374d0dcc3f72d13ee234c75`.
- Superseded and never released: builds from `df80e8e`, `b026cd7` and `749dbb2`
  (2026-09-03). The first was notarized but carried the AppKit UI retired the
  next day in `d5786e2`. Their provenance is in `../_archive/mac4DSTEM/docs/archive/v2/`.
  Known issues ship listed in `docs/open-items.md`.

## v1.0.0 — 2026-08-06

Native macOS 4D-STEM analysis for Apple Silicon, validated against
[py4DSTEM](https://github.com/py4dstem/py4DSTEM) 0.14.19.

First tagged release.

### The workflow

A frozen five-stage product workflow — **Prepare → Image / Map / Reconstruct →
Results** — with task-scoped controls and per-task readiness. Every result
carries its model, scale, units and validity through display, export and
reopen.

### Analysis

- **Calibration** — origin/probe fitting, detector-ellipse correction, R–Q
  rotation, Q and R pixel scales, each with explicit provenance and a stated
  consequence when missing. No missing value is ever synthesized.
- **Virtual imaging** — BF/ADF/HAADF and custom annular, rectangular and point
  detectors, dragged live on the diffraction pane.
- **DPC / iDPC** — beam-deflection mapping and integrated projected phase,
  measured against fitted per-position origins.
- **Bragg disk detection** — cross-correlation (on the CPU; "GPU" here was never true — corrected 2026-09-07) with parabolic, pixel and
  Fourier (multicorr) subpixel refinement.
- **Strain mapping** — reference region or whole-scan mean, automatic or manual
  g₁/g₂ basis, with basis consensus, fit residual, indexed fraction and
  reference-inlier diagnostics published alongside every map.
- **ACOM orientation** — template matching against a built-in crystal library
  or an imported CIF, with symmetry expansion, IPF·Z colouring and a
  reliability read-out.
- **Parallax / ptychography** — coarse-to-fine bright-field alignment,
  aberration fitting, phase correction, depth sectioning, and single-slice
  iterative object/probe recovery.

### Data

- HDF5/EMD, DM4/DM3, MIB, RAW and vendor XML readers.
- EMD export of Bragg vectors, calibrated datacubes and preprocessed products,
  published atomically via a same-volume scratch directory so a sandboxed save
  cannot leave a partial file.
- Publication figures burn in scale bar, colorbar and caption — including the
  display orientation when one is applied, because an applied-but-unrecorded
  rotation is not acceptable.

### Verification

`tools/run-tests.sh all` — **exit 0, 30 harnesses**: 105 unit tests, 28
scientific parity harnesses, real-data acceptance, and packaging. *(Those are
v1.0.0's numbers, measured at the tag on 2026-08-06, and they are left as the
record of what this release was verified by. The gate has grown since; the
current reproducible figures are in [`README.md`](README.md).)* Parity is
measured against py4DSTEM 0.14.19 on a four-dataset training set, with records
in `References/parity_records/`.

A separate on-screen QC playthrough (the `ui-qc-playthrough` tool, retired 2026-08-17, since
removed) drove the real app through the canonical py4DSTEM pipelines and logs every number it
reads from the app's own controls. Its last full run was green on all four
datasets.

**What this release was *not* verified by, stated plainly:** no visual QC
baseline exists. Every playthrough run to date used `--no-screenshots`, so the
acceptance evidence for v1.0.0 is numeric only — the numbers the app reports
through its own controls, not what it draws. Creating that baseline needs
Screen Recording granted to the ad-hoc-signed test runner; it was deliberately
deferred rather than faked, and it is the first entry in
[`docs/open-items.md`](docs/open-items.md).

### Fixed at the close of the phase (2026-08-06)

- **Q calibration could be stamped "Measured in app" from an origin the app had
  already flagged as unusable.** On one training dataset that produced a Q pixel
  size 2.56× too large, and the label — not the warning — is what travelled into
  export, reopen and the QC log. `calibrateQFromCrystal` now refuses on the same
  predicate the Prepare readiness row uses, so the badge, the app's behaviour
  and the parity records cannot disagree. The underlying estimator is *not*
  fixed and is fragile to origin error well below that threshold — recorded in
  [`../_archive/mac4DSTEM/docs/archive/v2/post-v1-ideas.md`](../_archive/mac4DSTEM/docs/archive/v2/post-v1-ideas.md) as a deliberate scope
  decision, not an oversight.
- **The Result colormap was unreachable from the Results workspace**, the one
  screen built for looking at results.
- **The readiness row called a measured origin "Missing"** directly above a
  detail line reporting it as measured. It now reads "Not quantitative".
- **Split-view height regression (#16/#22)** — a single `fixedSize` propagated a
  minimum height past the window's own, making the sidebar's top rows inert.

### Distribution

Hardened runtime, sandboxed, self-contained, no Homebrew dylib dependency,
macOS 14 floor — **declared, never tested below macOS 26** (corrected 2026-08-28; the clean-account launch was on macOS 27 only). The supported floor is now macOS 26, stated in `README.md`. Developer ID signing, notarization and a clean-account launch
remain release-owner actions.

### Deliberately out of scope

Cropping and partial/binned loading, multi-slice ptychography, and a WS₂ crystal
model. See [`../_archive/mac4DSTEM/docs/archive/v2/post-v1-ideas.md`](../_archive/mac4DSTEM/docs/archive/v2/post-v1-ideas.md).

---

## Working notes

The v1.0 development phase's item-level record — 46 numbered findings, the
design passes, and the QC-evaluation prompts — is archived under
[`../_archive/mac4DSTEM/docs/archive/v1.0/`](../_archive/mac4DSTEM/docs/archive/v1.0/). It is history, not guidance; nothing
in the current docs points into it. `docs/open-items.md` carries forward only
what is still live.
