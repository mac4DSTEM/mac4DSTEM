# mac4DSTEM code metrics (static audit)

Generated 2026-09-16. Read-only audit: numbers only, no recommendations.
Scripts and raw logs live under the session scratchpad (`/private/tmp/claude-501/.../scratchpad`), not in the repo; they are not retained.

## A. File sizes and layers

Method: `git ls-files '*.swift' '*.metal' | xargs wc -l`, sorted descending; layer assigned by top-level path prefix (`mac4DSTEM/{App,Core,Session,Shaders,Support,UI}/`, `mac4DSTEMTests/`, `tools/`; `Package.swift` itself falls outside all of these and is tagged `Other`).

### A1. 20 largest source files

| path | lines | layer |
|---|---|---|
| mac4DSTEM/App/AppState.swift | 5461 | App |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift | 2890 | Core |
| mac4DSTEMTests/PhaseVectorMatchingTests.swift | 2023 | Tests |
| mac4DSTEM/Support/ResultExport.swift | 1939 | Support |
| tools/cif-symmetry-test/main.swift | 1268 | tools |
| mac4DSTEM/UI/ImagePanes.swift | 1248 | UI |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift | 1246 | Core |
| mac4DSTEM/Core/Analysis/DiskDetection.swift | 1187 | Core |
| tools/phase-map-probe/main.swift | 1143 | tools |
| mac4DSTEM/Core/Data/H5Reader.swift | 1128 | Core |
| mac4DSTEM/UI/MapSettings.swift | 1124 | UI |
| mac4DSTEMTests/ProductWorkflowTests.swift | 1109 | Tests |
| tools/training-dataset-campaign/main.swift | 1063 | tools |
| mac4DSTEMTests/PrecipitateTests.swift | 1041 | Tests |
| mac4DSTEM/UI/PaneOverlays.swift | 1036 | UI |
| mac4DSTEM/Core/Crystal/CIFImport.swift | 1017 | Core |
| tools/two-spec-analysis-test/main.swift | 1004 | tools |
| mac4DSTEM/UI/WorkspaceInspector.swift | 999 | UI |
| mac4DSTEM/Core/Data/Calibration.swift | 938 | Core |
| mac4DSTEMTests/CalibrationReReferenceTests.swift | 876 | Tests |

### A2. Lines and files per layer

| layer | lines | files |
|---|---|---|
| Core | 28897 | 62 |
| tools | 20439 | 66 |
| Tests | 17596 | 65 |
| UI | 10740 | 25 |
| App | 7524 | 9 |
| Session | 4544 | 22 |
| Support | 2099 | 2 |
| Shaders | 557 | 8 |
| Other | 66 | 1 |

## B. Unused-symbol candidates (static, periphery unavailable)

Method: declarations (`func`, `struct`, `class`, `enum`, `protocol`, `typealias`, `actor`, `static let/var`, and `let/var` at type scope) extracted from `mac4DSTEM/**/*.swift` by a line-based regex scanner with a brace-depth stack approximating "type scope" (not a real parser). For each declared name, a whole-word line-match count (equivalent to `grep -rw` without `-c`, summed as matching-line count, not raw occurrence count) is taken across all tracked `.swift`/`.metal` files in `mac4DSTEM/`, `mac4DSTEMTests/`, `tools/`, minus the declaring line. Excluded from consideration: Swift keywords; `body, init, deinit, main, description, hash, ==, <`; and a stoplist of ~40 generic single-word identifiers (`id, name, value, type, count, index, result, error, url, path, size, key, item, text, label, color, view, state, image, kind, min, max, sum, offset, scale, ...` — see script) that are common parameter/property names and would otherwise produce noise, not genuine dead code.

2715 raw declarations extracted; 2530 remain after exclusions; 12 have zero references elsewhere.

### B1. Zero-reference candidates

| path:line | symbol | kind | access | refs-elsewhere |
|---|---|---|---|---|
| mac4DSTEM/App/AppState.swift:493 | acomBackendSummary | var | none | 0 |
| mac4DSTEM/App/AppState.swift:5012 | availableComputedProducts | var | none | 0 |
| mac4DSTEM/App/Colormaps.swift:26 | shortDisplayName | var | none | 0 |
| mac4DSTEM/App/ProductWorkflow.swift:691 | recommendedNextArea | func | none | 0 |
| mac4DSTEM/Support/ResultExport.swift:647 | exportBraggPeaksCSV | func | none | 0 |
| mac4DSTEM/Support/ResultExport.swift:678 | exportBraggVectorsEMD | func | none | 0 |
| mac4DSTEM/UI/MetalImageView.swift:220 | mtkView | func | none | 0 |
| mac4DSTEM/UI/MetalImageView.swift:269 | makeNSView | func | none | 0 |
| mac4DSTEM/UI/MetalImageView.swift:270 | updateNSView | func | none | 0 |
| mac4DSTEM/UI/MetalImageView.swift:277 | makeUIView | func | none | 0 |
| mac4DSTEM/UI/MetalImageView.swift:278 | updateUIView | func | none | 0 |
| mac4DSTEM/UI/ZoomPan.swift:38 | isZoomedIn | var | none | 0 |

### B2. Summary by layer

| layer | declared symbols (post-exclusion) | 0-ref candidates |
|---|---|---|
| Core | 1045 | 0 |
| UI | 566 | 6 |
| App | 497 | 4 |
| Session | 364 | 0 |
| Support | 46 | 2 |

Method blind spots this approach cannot see through: SwiftUI `body`, `@main`, protocol requirements satisfied by name (5 of the 12 above — `mtkView`, `makeNSView`, `updateNSView`, `makeUIView`, `updateUIView` — are `NSViewRepresentable`/`UIViewRepresentable` requirements), Codable-synthesized keys, `#selector`, other string-based lookups, `@Test`/`test*` methods discovered by name, and Metal kernel names looked up by string via `makeFunction(name:)`.

Metal kernel-name check: all 8 `kernel void` functions declared under `mac4DSTEM/Shaders/*.metal` (`centerOfMass`, `acomCorrelationSpectrum`, `acomInverseArgmax`, `virtualDiffraction`, `virtualAperture`, `measureOrigin`, `dpStatistics`, `virtualMaskSum`) are referenced as string literals from `mac4DSTEM/Core/Compute/MetalEngine.swift` (6 direct `makeFunction(name: "...")` / `makeComputePipelineState` call sites) and `mac4DSTEM/Core/Crystal/OrientationMatcher.swift` (the 2 ACOM kernels); none appear in table B1 (kernel names are never candidates in the first place — table B only extracts declarations from `.swift`, not `.metal`).

## C. Duplicated helpers

Method: every `func` in `mac4DSTEM/` and `tools/` (`.swift`, excluding `mac4DSTEMTests/`) is located with a string/comment-aware tokenizer that finds the body span (`{`...matching `}`); `init` is never matched because Swift initializers don't use the `func` keyword, so it is excluded automatically. 1649 functions extracted with a resolvable body (protocol/abstract requirements with no body are skipped).

### C1. Same function name declared in >=2 files

132 names shared across >=2 files.

| name | kind | locations (path:line(lines=body)) |
|---|---|---|
| add | free func/method | mac4DSTEM/Core/Crystal/CrystalModel.swift:35(lines=3); mac4DSTEM/Session/DiskCentreLabels.swift:136(lines=4); mac4DSTEM/UI/PhaseMappingSettings.swift:393(lines=7) |
| admits | method | mac4DSTEM/Core/Analysis/TiledDiskDetection.swift:16(lines=8); mac4DSTEM/Core/Data/ResidentCube.swift:148(lines=6); mac4DSTEM/Core/ML/LearnedDiskDetection.swift:173(lines=8) |
| adopt | method | mac4DSTEM/Session/SessionReplay.swift:67(lines=5); mac4DSTEM/Session/SessionSidecarLocator.swift:215(lines=3); mac4DSTEM/Session/SessionSidecarLocator.swift:219(lines=7) |
| apply | method | mac4DSTEM/Core/Crystal/CIFImport.swift:533(lines=7); mac4DSTEM/Core/Data/CalibrationReReference.swift:148(lines=203) |
| applyRotation | method | mac4DSTEM/Core/Analysis/DPC.swift:53(lines=11); mac4DSTEM/Session/CalibrationSession.swift:50(lines=7) |
| approx | free func | tools/fit-overlay-test/main.swift:14(lines=3); tools/ws2-crystal-test/main.swift:29(lines=3) |
| axisDelta | free func/method | mac4DSTEM/Core/Crystal/CIFImport.swift:742(lines=5); mac4DSTEM/Core/Crystal/CrystalModel.swift:165(lines=5) |
| begin | method | mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:37(lines=8); mac4DSTEM/Session/OperationCenter.swift:34(lines=6); mac4DSTEM/Session/ReplayRun.swift:125(lines=10) |
| body | method | mac4DSTEM/UI/ImagePanes.swift:1220(lines=6); mac4DSTEM/UI/WorkspaceView.swift:797(lines=7); mac4DSTEM/UI/ZoomPan.swift:65(lines=47) |
| byteString | free func/method | mac4DSTEM/Session/SystemMonitor.swift:34(lines=4); tools/residency-sweep/main.swift:68(lines=5) |
| cancel | method | mac4DSTEM/Core/Analysis/VirtualDetector.swift:157(lines=1); mac4DSTEM/Core/Analysis/VirtualDetector.swift:237(lines=1); mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift:19(lines=5); mac4DSTEM/Session/OperationCenter.swift:61(lines=1) |
| candidateLibraryPaths | method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2881(lines=9); mac4DSTEM/Core/Data/H5Reader.swift:242(lines=10) |
| cartesianZoneAxis | free func/method | mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:431(lines=8); tools/demo-dataset/export_reflections.swift:45(lines=8) |
| check | free func/method | tools/calibration-test/main.swift:12(lines=3); tools/load-spec-calibration/main.swift:70(lines=3); tools/load-spec-roundtrip/main.swift:25(lines=3); tools/load-spec-test/main.swift:29(lines=3); tools/phase-vector-matching/main.swift:64(lines=5); tools/preprocess-crop-bin-test/main.swift:34(lines=3); tools/sidecar-error-detail-test/main.swift:97(lines=34); tools/strain-frame-test/main.swift:35(lines=3); tools/two-spec-analysis-test/main.swift:134(lines=4) |
| checkCancellation | method | mac4DSTEM/Core/Analysis/ParallaxAberrationCorrection.swift:233(lines=3); mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:671(lines=3); mac4DSTEM/Core/Analysis/ParallaxDepthSectioning.swift:227(lines=3); mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:484(lines=3); mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:599(lines=5); mac4DSTEM/Core/Analysis/PtychographyPreparation.swift:311(lines=5); mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:729(lines=3); mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1375(lines=3) |
| checkedProduct | method | mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:490(lines=5); mac4DSTEM/Core/Data/VendorRawReaders.swift:199(lines=9) |
| classify | method | mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:761(lines=173); mac4DSTEM/Session/SessionSidecarLocator.swift:286(lines=4); mac4DSTEM/Session/StrainProduct.swift:46(lines=5) |
| clear | method | mac4DSTEM/Session/CalibrationSession.swift:94(lines=6); mac4DSTEM/Session/DiffractionGroupsProduct.swift:94(lines=5); mac4DSTEM/Session/DiskCentreLabels.swift:165(lines=4); mac4DSTEM/Session/LearnedDetection.swift:99(lines=5); mac4DSTEM/Session/PhaseMappingProduct.swift:283(lines=5); mac4DSTEM/Session/QCalibrationRun.swift:94(lines=4); mac4DSTEM/Session/StrainProduct.swift:149(lines=4) |
| compare | free func | tools/disk-correlation-parity/main.swift:122(lines=7); tools/virtual-detector-test/main.swift:76(lines=16) |
| component | method | mac4DSTEM/Core/Analysis/StrainFrame.swift:103(lines=13); mac4DSTEM/Core/Analysis/StrainMapping.swift:66(lines=18) |
| compute | method | mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:164(lines=226); mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:459(lines=14); mac4DSTEM/Core/Analysis/StrainMapping.swift:150(lines=153) |
| count | method | mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:311(lines=3); mac4DSTEM/Session/SystemMonitor.swift:46(lines=3) |
| crop | method | mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:558(lines=17); mac4DSTEM/Core/Data/LoadConfiguration.swift:130(lines=45) |
| cropped | free func/method | mac4DSTEM/Core/Analysis/DiskDetection.swift:744(lines=6); mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1453(lines=19); mac4DSTEM/Core/Data/CalibrationReReference.swift:360(lines=18) |
| currentReplaySignature | method | mac4DSTEM/App/AppState.swift:1017(lines=9); mac4DSTEM/App/ProductWorkflow.swift:444(lines=31) |
| decode | method | mac4DSTEM/Core/Data/DM4Reader.swift:392(lines=5); mac4DSTEM/Core/Data/DM4Reader.swift:400(lines=25); mac4DSTEM/Session/DiskCentreLabels.swift:241(lines=10); mac4DSTEM/Session/WorkspaceRecovery.swift:227(lines=4) |
| describe | free func/method | mac4DSTEM/Core/Data/H5Reader.swift:536(lines=51); mac4DSTEM/Session/SessionCalibrationFramePolicy.swift:32(lines=4); tools/two-spec-analysis-test/main.swift:215(lines=3) |
| detect | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:670(lines=3); mac4DSTEM/Core/Analysis/DiskDetection.swift:708(lines=4); mac4DSTEM/Core/ML/LearnedDiskDetector.swift:317(lines=9) |
| detectAll | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:1106(lines=76); mac4DSTEM/Core/Analysis/TiledDiskDetection.swift:72(lines=95); mac4DSTEM/Core/ML/LearnedDiskDetection.swift:216(lines=88); mac4DSTEM/Core/ML/LearnedDiskDetector.swift:348(lines=130) |
| detectorBasis | method | mac4DSTEM/Core/Analysis/OrientationResult.swift:91(lines=6); tools/demo-dataset/export_reflections.swift:35(lines=6) |
| discoverPrimaryDataset | method | mac4DSTEM/Core/Data/DM4Reader.swift:108(lines=4); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:22(lines=1); mac4DSTEM/Core/Data/FourDDataSource.swift:147(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:292(lines=97); mac4DSTEM/Core/Data/VendorRawReaders.swift:74(lines=5); mac4DSTEM/Core/Data/VendorRawReaders.swift:292(lines=5); tools/embedding-pca-parity/main.swift:33(lines=6); tools/load-spec-calibration/main.swift:126(lines=1); tools/parallax-preprocessing-test/main.swift:35(lines=1); tools/performance-baseline/main.swift:17(lines=1); tools/preprocessing-export-test/main.swift:9(lines=1); tools/reduced-export-test/main.swift:39(lines=1); tools/resident-cropped-view/main.swift:128(lines=1); tools/virtual-detector-residency/main.swift:50(lines=1); tools/virtual-detector-test/main.swift:17(lines=1) |
| distinctShells | free func | tools/origin-fit-diagnostics/shell-check.swift:42(lines=7); tools/ws2-crystal-test/main.swift:102(lines=8) |
| draw | method | mac4DSTEM/UI/HistogramView.swift:168(lines=30); mac4DSTEM/UI/MetalImageView.swift:222(lines=41) |
| electronWavelengthAngstrom | method | mac4DSTEM/Core/Analysis/DPC.swift:79(lines=5); mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:236(lines=11) |
| encode | method | mac4DSTEM/Session/DiskCentreLabels.swift:57(lines=5); mac4DSTEM/Session/WorkspaceRecovery.swift:223(lines=3) |
| expectIdentical | free func | tools/resident-cropped-view/main.swift:38(lines=9); tools/virtual-detector-residency/main.swift:84(lines=9) |
| fail | free func/method | tools/acom-matching-test/main.swift:3(lines=4); tools/acom-orientation-test/main.swift:21(lines=4); tools/bragg-export-test/main.swift:3(lines=4); tools/cancellation-test/main.swift:4(lines=4); tools/datacube-discovery-test/main.swift:8(lines=4); tools/disk-correlation-parity/main.swift:145(lines=4); tools/disk-detection-test/main.swift:46(lines=4); tools/disk-detector/scan-bench/main.swift:14(lines=1); tools/dm4-robustness-test/main.swift:3(lines=4); tools/ellipse-calibration-test/main.swift:64(lines=4); tools/fit-overlay-test/main.swift:9(lines=4); tools/idpc-test/main.swift:20(lines=4); tools/load-spec-calibration/main.swift:74(lines=4); tools/load-spec-roundtrip/main.swift:29(lines=4); tools/load-spec-test/main.swift:33(lines=4); tools/peak-overlay-test/main.swift:4(lines=4); tools/performance-baseline/main.swift:68(lines=4); tools/preprocess-crop-bin-test/main.swift:38(lines=4); tools/real-acom-benchmark/main.swift:31(lines=4); tools/real-data-acceptance/main.swift:25(lines=3); tools/residency-sweep/main.swift:48(lines=4); tools/resident-cropped-view/main.swift:32(lines=4); tools/sidecar-result-test/main.swift:3(lines=4); tools/strain-frame-test/main.swift:30(lines=4); tools/strain-test/main.swift:3(lines=4); tools/two-spec-analysis-test/main.swift:139(lines=4); tools/vendor-reader-test/main.swift:3(lines=4); tools/virtual-detector-residency/main.swift:74(lines=4); tools/virtual-detector-test/main.swift:71(lines=4); tools/ws2-crystal-test/main.swift:24(lines=4) |
| fileSize | free func/method | mac4DSTEM/Core/Data/VendorRawReaders.swift:192(lines=6); tools/training-dataset-campaign/main.swift:172(lines=4) |
| finish | free func/method | mac4DSTEM/Core/ML/LearnedDiskDetector.swift:423(lines=13); mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:49(lines=5); mac4DSTEM/Session/OperationCenter.swift:43(lines=6); mac4DSTEM/Session/ReplayRun.swift:149(lines=12) |
| finiteDouble | method | mac4DSTEM/Core/Data/ResultPresentation.swift:257(lines=4); mac4DSTEM/Session/ReplayPlan.swift:860(lines=4) |
| format | method | mac4DSTEM/Core/Data/CalibrationReReference.swift:478(lines=3); mac4DSTEM/UI/PaneOverlays.swift:138(lines=5); mac4DSTEM/UI/PaneOverlays.swift:239(lines=9) |
| gaussianBlur | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:1028(lines=69); mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift:398(lines=42) |
| global | free func | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2810(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:185(lines=6) |
| image | method | mac4DSTEM/Core/Analysis/VirtualDetector.swift:548(lines=7); mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:91(lines=28) |
| intBinding | free func | mac4DSTEM/UI/DiffractionGroupsSettings.swift:165(lines=10); mac4DSTEM/UI/MapSettings.swift:1052(lines=10) |
| isCurrent | method | mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:55(lines=3); mac4DSTEM/Session/OperationCenter.swift:50(lines=1) |
| label | free func/method | mac4DSTEM/Session/WorkspaceRecovery.swift:59(lines=16); tools/phase-map-probe/main.swift:729(lines=8); tools/phase-map-probe/thronsen.swift:130(lines=14) |
| load | method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2788(lines=92); mac4DSTEM/Core/Data/DM4Reader.swift:850(lines=9); mac4DSTEM/Core/Data/H5Reader.swift:160(lines=81); mac4DSTEM/Core/ML/LearnedDiskDetector.swift:71(lines=23); mac4DSTEM/Session/DiskCentreLabels.swift:260(lines=11) |
| loadPushdown | method | mac4DSTEM/Core/Data/DM4Reader.swift:120(lines=3); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:28(lines=1); mac4DSTEM/Core/Data/FourDDataSource.swift:166(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:607(lines=8); mac4DSTEM/Core/Data/VendorRawReaders.swift:84(lines=1); mac4DSTEM/Core/Data/VendorRawReaders.swift:301(lines=1); tools/embedding-pca-parity/main.swift:40(lines=1); tools/load-spec-calibration/main.swift:127(lines=1); tools/parallax-preprocessing-test/main.swift:37(lines=1); tools/performance-baseline/main.swift:19(lines=1); tools/preprocessing-export-test/main.swift:11(lines=1); tools/reduced-export-test/main.swift:40(lines=1); tools/resident-cropped-view/main.swift:129(lines=1); tools/virtual-detector-residency/main.swift:52(lines=1); tools/virtual-detector-test/main.swift:18(lines=1) |
| main | method | tools/acom-groundtruth/main.swift:119(lines=147); tools/bragg-spacing-probe/bullseye-parity-probe.swift:9(lines=37); tools/bragg-spacing-probe/detection-threshold-probe.swift:28(lines=72); tools/bragg-spacing-probe/main.swift:10(lines=136); tools/calibration-readiness-test/main.swift:37(lines=228); tools/cif-symmetry-test/main.swift:1159(lines=109); tools/datacube-discovery-test/main.swift:14(lines=234); tools/demo-dataset/export_reflections.swift:93(lines=27); tools/dm4-robustness-test/main.swift:572(lines=15); tools/embedding-pca-parity/main.swift:82(lines=92); tools/hdf5-race-probe/main.swift:49(lines=91); tools/load-spec-calibration/main.swift:190(lines=163); tools/load-spec-roundtrip/main.swift:58(lines=164); tools/load-spec-test/main.swift:376(lines=192); tools/origin-fit-diagnostics/coarse-cost.swift:8(lines=113); tools/origin-fit-diagnostics/probe-size.swift:27(lines=51); tools/origin-fit-diagnostics/residuals.swift:50(lines=111); tools/origin-fit-diagnostics/shell-check.swift:52(lines=171); tools/origin-fit-diagnostics/trim-sweep.swift:31(lines=164); tools/parallax-aberration-test/main.swift:118(lines=180); tools/parallax-alignment-test/main.swift:80(lines=208); tools/parallax-depth-test/main.swift:40(lines=117); tools/parallax-preprocessing-test/main.swift:80(lines=143); tools/parallax-subpixel-test/main.swift:91(lines=133); tools/performance-baseline/main.swift:695(lines=128); tools/phase-discrimination-probe/main.swift:40(lines=209); tools/phase-map-probe/main.swift:76(lines=1067); tools/phase-vector-matching/main.swift:167(lines=693); tools/preprocess-crop-bin-test/main.swift:61(lines=167); tools/preprocessing-export-test/main.swift:69(lines=138); tools/q-calibration-gate-test/main.swift:50(lines=774); tools/real-acom-benchmark/main.swift:42(lines=142); tools/real-data-acceptance/main.swift:30(lines=175); tools/reduced-export-test/main.swift:182(lines=144); tools/scientific-bundle-test/main.swift:10(lines=54); tools/sidecar-result-test/preserve_unknown.swift:5(lines=26); tools/singleslice-ptychography-test/main.swift:79(lines=282); tools/strain-frame-test/main.swift:178(lines=159); tools/training-dataset-campaign/main.swift:1022(lines=41); tools/two-spec-analysis-test/main.swift:223(lines=31); tools/vendor-reader-test/main.swift:9(lines=45); tools/ws2-crystal-test/main.swift:43(lines=217) |
| make | method | mac4DSTEM/Core/Analysis/DatasetPreview.swift:145(lines=50); mac4DSTEM/Core/Data/Calibration.swift:283(lines=131); mac4DSTEM/Core/Data/ResultPresentation.swift:32(lines=30) |
| manualScaleRows | method | mac4DSTEM/UI/ExportSheet.swift:391(lines=18); mac4DSTEM/UI/PrepareSettings.swift:520(lines=18) |
| map | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:607(lines=18); mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:1142(lines=90); mac4DSTEM/Session/ReplayPlan.swift:279(lines=45) |
| matrix | free func/method | mac4DSTEM/Core/Analysis/OrientationResult.swift:99(lines=7); tools/acom-orientation-test/main.swift:26(lines=10) |
| maximumDifference | free func | tools/singleslice-ptychography-test/main.swift:260(lines=3); tools/two-spec-analysis-test/main.swift:145(lines=8) |
| maximumError | free func | tools/acom-orientation-test/main.swift:37(lines=7); tools/idpc-test/main.swift:25(lines=4); tools/parallax-aberration-test/main.swift:63(lines=4); tools/parallax-alignment-test/main.swift:73(lines=4); tools/parallax-depth-test/main.swift:33(lines=4); tools/parallax-preprocessing-test/main.swift:73(lines=4); tools/parallax-subpixel-test/main.swift:41(lines=4); tools/singleslice-ptychography-test/main.swift:60(lines=4) |
| measure | free func | tools/disk-correlation-parity/main.swift:225(lines=69); tools/origin-fit-diagnostics/trim-sweep.swift:56(lines=84); tools/performance-baseline/main.swift:108(lines=9); tools/performance-baseline/main.swift:125(lines=11); tools/phase-vector-matching/main.swift:70(lines=3) |
| median | free func/method | mac4DSTEM/Core/Analysis/EllipseCalibration.swift:664(lines=7); mac4DSTEM/Core/Analysis/OriginCalibration.swift:363(lines=8); mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:662(lines=8); mac4DSTEM/Core/Analysis/QCalibration.swift:238(lines=7); mac4DSTEM/Core/Analysis/StrainMapping.swift:732(lines=9); tools/acom-convention-test/main.swift:10(lines=5); tools/acom-matching-test/main.swift:218(lines=7); tools/disk-detector/scan-bench/main.swift:16(lines=1); tools/residency-sweep/main.swift:59(lines=8) |
| medianOf | free func/method | mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift:327(lines=6); tools/origin-fit-diagnostics/residuals.swift:11(lines=4) |
| metrics | method | mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:73(lines=15); mac4DSTEM/Session/OperationCenter.swift:63(lines=3) |
| next | method | mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:550(lines=7); tools/disk-correlation-parity/main.swift:28(lines=4); tools/origin-fit-diagnostics/shell-check.swift:23(lines=4); tools/origin-fit-diagnostics/trim-sweep.swift:23(lines=4); tools/phase-vector-matching/main.swift:80(lines=4) |
| nextPow2 | method | mac4DSTEM/Core/Compute/FFT1D.swift:43(lines=5); mac4DSTEM/Core/Compute/FFT2D.swift:645(lines=5) |
| nextUnit | free func/method | mac4DSTEM/Core/Analysis/RotationCalibration.swift:261(lines=4); tools/rotation-null-probe/main.swift:39(lines=3) |
| normal | method | tools/origin-fit-diagnostics/shell-check.swift:27(lines=4); tools/q-calibration-gate-test/main.swift:465(lines=4) |
| normalized | method | mac4DSTEM/Core/Data/Calibration.swift:106(lines=8); mac4DSTEM/Core/Data/DiffractionPattern.swift:32(lines=15); mac4DSTEM/Core/Data/DiffractionPattern.swift:78(lines=4) |
| ordinal | method | mac4DSTEM/Core/Analysis/DatasetPreview.swift:74(lines=8); mac4DSTEM/Core/Analysis/DiskDetection.swift:316(lines=7) |
| pad | free func | mac4DSTEM/Core/Analysis/DPC.swift:320(lines=9); tools/residency-sweep/main.swift:226(lines=3) |
| parse | method | mac4DSTEM/Core/Crystal/CIFImport.swift:176(lines=186); mac4DSTEM/Core/Data/DM4Reader.swift:455(lines=11); mac4DSTEM/Core/Data/ResultPresentation.swift:190(lines=64); mac4DSTEM/Core/Data/SessionReplayRecord.swift:101(lines=6); mac4DSTEM/Session/ReplayPlan.swift:674(lines=173) |
| pass | free func | tools/resident-cropped-view/main.swift:36(lines=1); tools/virtual-detector-residency/main.swift:79(lines=3) |
| pattern | free func/method | mac4DSTEM/Core/Data/DM4Reader.swift:132(lines=23); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:110(lines=35); mac4DSTEM/Core/Data/FourDArray.swift:50(lines=31); mac4DSTEM/Core/Data/FourDArray.swift:336(lines=11); mac4DSTEM/Core/Data/LoadSpecification.swift:474(lines=6); tools/two-spec-analysis-test/main.swift:930(lines=12) |
| pct | free func | tools/bragg-spacing-probe/main.swift:113(lines=5); tools/origin-fit-diagnostics/residuals.swift:6(lines=5) |
| peaks | free func | tools/phase-discrimination-probe/main.swift:66(lines=8); tools/phase-vector-matching/main.swift:153(lines=10); tools/two-spec-analysis-test/main.swift:205(lines=7) |
| pixelCalibration | free func/method | mac4DSTEM/Core/Data/DM4Reader.swift:384(lines=5); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:91(lines=18); mac4DSTEM/Core/Data/FourDDataSource.swift:187(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:778(lines=90); mac4DSTEM/Core/Data/VendorRawReaders.swift:149(lines=1); mac4DSTEM/Core/Data/VendorRawReaders.swift:364(lines=1); tools/embedding-pca-parity/main.swift:66(lines=1); tools/load-spec-calibration/main.swift:139(lines=1); tools/parallax-preprocessing-test/main.swift:61(lines=1); tools/performance-baseline/main.swift:36(lines=1); tools/preprocessing-export-test/main.swift:58(lines=1); tools/reduced-export-test/main.swift:97(lines=1); tools/resident-cropped-view/main.swift:153(lines=1); tools/training-dataset-campaign/main.swift:183(lines=20); tools/virtual-detector-residency/main.swift:71(lines=1); tools/virtual-detector-test/main.swift:31(lines=1) |
| point | method | mac4DSTEM/Core/Data/ResultPresentation.swift:67(lines=4); mac4DSTEM/UI/PaneOverlays.swift:519(lines=9); mac4DSTEM/UI/PaneOverlays.swift:775(lines=6) |
| positiveModulo | method | mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:599(lines=4); mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:652(lines=4); mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:657(lines=4); mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift:200(lines=4) |
| prepare | free func/method | mac4DSTEM/Core/Analysis/PtychographyPreparation.swift:17(lines=280); mac4DSTEM/Core/ML/LearnedDiskDetector.swift:402(lines=21); mac4DSTEM/Session/LearnedDetection.swift:133(lines=15) |
| probeCandidates | method | mac4DSTEM/Core/Data/FourDDataSource.swift:139(lines=6); mac4DSTEM/Core/Data/FourDDataSource.swift:191(lines=1); mac4DSTEM/Core/Data/H5Reader.swift:455(lines=27) |
| provenance | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:476(lines=26); mac4DSTEM/Core/Data/ResultPresentation.swift:89(lines=34); mac4DSTEM/Core/ML/LearnedDiskDetection.swift:62(lines=14) |
| publish | method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1326(lines=37); mac4DSTEM/Session/DiffractionGroupsProduct.swift:70(lines=9); mac4DSTEM/Session/LoadedView.swift:79(lines=9); mac4DSTEM/Session/PhaseMappingProduct.swift:264(lines=4); mac4DSTEM/Session/StrainProduct.swift:131(lines=9) |
| q | free func | mac4DSTEM/Core/Analysis/StrainMapping.swift:481(lines=1); tools/bragg-spacing-probe/detection-threshold-probe.swift:22(lines=1); tools/phase-map-probe/main.swift:840(lines=4); tools/phase-map-probe/main.swift:871(lines=3); tools/phase-map-probe/main.swift:904(lines=4) |
| raw | free func/method | mac4DSTEM/Core/Analysis/FitOverlays.swift:149(lines=4); tools/dm4-robustness-test/main.swift:68(lines=1) |
| read | method | mac4DSTEM/Core/Data/H5Reader.swift:690(lines=41); mac4DSTEM/Core/Data/VendorRawReaders.swift:209(lines=10) |
| readDoubleAttribute | method | mac4DSTEM/Core/Data/DM4Reader.swift:376(lines=7); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:87(lines=3); mac4DSTEM/Core/Data/FourDDataSource.swift:185(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:1032(lines=18); mac4DSTEM/Core/Data/VendorRawReaders.swift:148(lines=1); mac4DSTEM/Core/Data/VendorRawReaders.swift:363(lines=1); tools/embedding-pca-parity/main.swift:65(lines=1); tools/load-spec-calibration/main.swift:138(lines=1); tools/parallax-preprocessing-test/main.swift:60(lines=1); tools/performance-baseline/main.swift:35(lines=1); tools/preprocessing-export-test/main.swift:57(lines=1); tools/reduced-export-test/main.swift:96(lines=1); tools/resident-cropped-view/main.swift:152(lines=1); tools/virtual-detector-residency/main.swift:70(lines=1); tools/virtual-detector-test/main.swift:30(lines=1) |
| readDoubleMatrix | method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1083(lines=24); mac4DSTEM/Core/Data/H5Reader.swift:920(lines=21) |
| readPattern | method | mac4DSTEM/Core/Data/DM4Reader.swift:285(lines=9); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:30(lines=14); mac4DSTEM/Core/Data/FourDDataSource.swift:177(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:734(lines=8); mac4DSTEM/Core/Data/VendorRawReaders.swift:86(lines=29); mac4DSTEM/Core/Data/VendorRawReaders.swift:303(lines=29); tools/embedding-pca-parity/main.swift:42(lines=3); tools/load-spec-calibration/main.swift:129(lines=3); tools/parallax-preprocessing-test/main.swift:39(lines=3); tools/performance-baseline/main.swift:21(lines=3); tools/preprocessing-export-test/main.swift:13(lines=6); tools/reduced-export-test/main.swift:48(lines=6); tools/resident-cropped-view/main.swift:131(lines=4); tools/virtual-detector-residency/main.swift:54(lines=4); tools/virtual-detector-test/main.swift:19(lines=3) |
| readProbe | method | mac4DSTEM/Core/Data/FourDDataSource.swift:143(lines=6); mac4DSTEM/Core/Data/FourDDataSource.swift:192(lines=3); mac4DSTEM/Core/Data/H5Reader.swift:486(lines=33) |
| readScanRow | method | mac4DSTEM/Core/Data/DM4Reader.swift:295(lines=5); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:47(lines=10); mac4DSTEM/Core/Data/FourDDataSource.swift:179(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:746(lines=8); mac4DSTEM/Core/Data/VendorRawReaders.swift:116(lines=15); mac4DSTEM/Core/Data/VendorRawReaders.swift:333(lines=13); tools/embedding-pca-parity/main.swift:46(lines=8); tools/load-spec-calibration/main.swift:132(lines=3); tools/parallax-preprocessing-test/main.swift:43(lines=3); tools/performance-baseline/main.swift:25(lines=3); tools/preprocessing-export-test/main.swift:20(lines=3); tools/reduced-export-test/main.swift:55(lines=3); tools/resident-cropped-view/main.swift:135(lines=7); tools/virtual-detector-residency/main.swift:59(lines=3); tools/virtual-detector-test/main.swift:22(lines=3) |
| readScanTile | method | mac4DSTEM/Core/Data/DM4Reader.swift:340(lines=34); mac4DSTEM/Core/Data/DemoFourDDataSource.swift:58(lines=16); mac4DSTEM/Core/Data/FourDDataSource.swift:182(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:755(lines=14); mac4DSTEM/Core/Data/VendorRawReaders.swift:132(lines=15); mac4DSTEM/Core/Data/VendorRawReaders.swift:347(lines=15); tools/embedding-pca-parity/main.swift:55(lines=9); tools/load-spec-calibration/main.swift:135(lines=3); tools/parallax-preprocessing-test/main.swift:47(lines=3); tools/performance-baseline/main.swift:29(lines=3); tools/preprocessing-export-test/main.swift:24(lines=3); tools/reduced-export-test/main.swift:59(lines=21); tools/resident-cropped-view/main.swift:142(lines=10); tools/virtual-detector-residency/main.swift:63(lines=5); tools/virtual-detector-test/main.swift:25(lines=4) |
| readStringAttribute | method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2585(lines=16); mac4DSTEM/Core/Data/H5Reader.swift:992(lines=14) |
| readStringDataset | method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1063(lines=17); mac4DSTEM/Core/Data/H5Reader.swift:944(lines=13) |
| readinessAction | method | mac4DSTEM/UI/ExportSheet.swift:276(lines=66); mac4DSTEM/UI/PrepareSettings.swift:374(lines=66) |
| readinessRow | method | mac4DSTEM/UI/ExportSheet.swift:232(lines=42); mac4DSTEM/UI/PrepareSettings.swift:326(lines=46) |
| reconstruct | method | mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:89(lines=238); mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:262(lines=354) |
| record | method | mac4DSTEM/App/ActivityLog.swift:80(lines=11); mac4DSTEM/Core/Data/SessionReplayRecord.swift:67(lines=11); mac4DSTEM/Session/LearnedDetection.swift:87(lines=6); mac4DSTEM/Session/QCalibrationRun.swift:80(lines=4); mac4DSTEM/Session/QCalibrationRun.swift:85(lines=4); mac4DSTEM/Session/SessionReplay.swift:48(lines=9) |
| recordedReplayStep | method | mac4DSTEM/App/AppState.swift:1013(lines=3); mac4DSTEM/App/ProductWorkflow.swift:433(lines=4) |
| rectangle | method | mac4DSTEM/UI/LoadConfigurator.swift:353(lines=13); mac4DSTEM/UI/PaneOverlays.swift:495(lines=22) |
| refine | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:776(lines=46); mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift:71(lines=51) |
| reflected | free func/method | mac4DSTEM/Core/Analysis/DiskDetection.swift:1050(lines=7); mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:584(lines=8); mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift:410(lines=7) |
| release | method | mac4DSTEM/Core/Data/HDF5Types.swift:101(lines=1); mac4DSTEM/Session/DatasetResidency.swift:176(lines=5); mac4DSTEM/Session/SessionSidecarLocator.swift:245(lines=6) |
| remember | method | mac4DSTEM/Session/RecentDatasets.swift:59(lines=8); mac4DSTEM/Session/SessionSidecarLocator.swift:231(lines=3); mac4DSTEM/Session/SessionSidecarLocator.swift:235(lines=8) |
| replayParameters | method | mac4DSTEM/Core/Analysis/DiskDetection.swift:507(lines=25); mac4DSTEM/Core/Analysis/VirtualDetector.swift:42(lines=7); mac4DSTEM/Session/LearnedDetection.swift:197(lines=8) |
| replayRefusal | method | mac4DSTEM/App/AppState.swift:1841(lines=7); mac4DSTEM/Session/LearnedDetection.swift:212(lines=22) |
| require | free func | tools/acom-convention-test/main.swift:6(lines=3); tools/calibration-readiness-test/main.swift:3(lines=8); tools/parallax-aberration-test/main.swift:54(lines=8); tools/parallax-alignment-test/main.swift:64(lines=8); tools/parallax-depth-test/main.swift:26(lines=6); tools/parallax-preprocessing-test/main.swift:64(lines=8); tools/parallax-subpixel-test/main.swift:34(lines=6); tools/preprocessing-export-test/main.swift:62(lines=4); tools/q-calibration-gate-test/main.swift:34(lines=7); tools/reduced-export-test/main.swift:100(lines=4); tools/result-presentation-test/main.swift:3(lines=6); tools/scientific-bundle-test/main.swift:3(lines=4); tools/singleslice-ptychography-test/main.swift:53(lines=6) |
| reset | method | mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:68(lines=4); mac4DSTEM/Session/DatasetResidency.swift:87(lines=8); mac4DSTEM/Session/DiskCentreLabels.swift:173(lines=7); mac4DSTEM/Session/LoadedView.swift:96(lines=9); mac4DSTEM/Session/OperationCenter.swift:72(lines=5); mac4DSTEM/Session/SessionReplay.swift:74(lines=4); mac4DSTEM/UI/ZoomPan.swift:40(lines=1) |
| resolve | method | mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:43(lines=56); mac4DSTEM/Core/Analysis/StrainFrame.swift:63(lines=4); mac4DSTEM/Session/WorkspaceRecovery.swift:181(lines=17) |
| rms | free func | mac4DSTEM/Core/Analysis/OriginCalibration.swift:352(lines=5); tools/origin-fit-diagnostics/residuals.swift:15(lines=5); tools/origin-fit-diagnostics/trim-sweep.swift:179(lines=8) |
| rotate | method | mac4DSTEM/Core/Analysis/StrainFrame.swift:157(lines=18); mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:517(lines=9) |
| run | free func/method | mac4DSTEM/Core/Analysis/OriginCalibration.swift:557(lines=40); mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:248(lines=198); mac4DSTEM/Core/Analysis/VirtualDetector.swift:532(lines=10); mac4DSTEM/Core/Compute/MetalEngine.swift:362(lines=13); mac4DSTEM/Core/Data/HDF5Types.swift:93(lines=4); tools/origin-fit-diagnostics/shell-check.swift:141(lines=30) |
| sample | method | mac4DSTEM/App/Colormaps.swift:55(lines=27); mac4DSTEM/Core/Data/DisplayedProduct.swift:129(lines=21) |
| scale | free func | mac4DSTEM/Core/Data/CalibrationReReference.swift:414(lines=3); mac4DSTEM/Core/Data/DM4Reader.swift:754(lines=1) |
| scanRow | method | mac4DSTEM/Core/Data/DM4Reader.swift:310(lines=29); mac4DSTEM/Core/Data/LoadSpecification.swift:481(lines=8) |
| scanTile | method | mac4DSTEM/Core/Data/FourDArray.swift:87(lines=31); mac4DSTEM/Core/Data/LoadSpecification.swift:490(lines=14) |
| solve | method | mac4DSTEM/Core/Analysis/EllipseCalibration.swift:697(lines=23); mac4DSTEM/Core/Analysis/OriginCalibration.swift:445(lines=30); mac4DSTEM/Core/Analysis/RotationCalibration.swift:127(lines=185) |
| sourcePattern | method | mac4DSTEM/Core/Data/DemoFourDDataSource.swift:79(lines=7); tools/reduced-export-test/main.swift:82(lines=12) |
| string | free func/method | mac4DSTEM/Core/Data/DM4Reader.swift:826(lines=3); mac4DSTEM/Core/Data/H5Reader.swift:796(lines=4) |
| swatch | method | mac4DSTEM/App/Colormaps.swift:129(lines=19); mac4DSTEM/UI/PaneOverlays.swift:380(lines=9); mac4DSTEM/UI/PhaseMappingSettings.swift:333(lines=15) |
| symbol | free func/method | mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2804(lines=6); mac4DSTEM/Core/Data/H5Reader.swift:178(lines=6); mac4DSTEM/UI/ImagingSettings.swift:117(lines=8); mac4DSTEM/UI/ImagingSettings.swift:126(lines=7); mac4DSTEM/UI/ImagingSettings.swift:136(lines=8); mac4DSTEM/UI/WorkspaceInspector.swift:808(lines=10) |
| tile | method | mac4DSTEM/Core/Analysis/VirtualDetector.swift:137(lines=14); mac4DSTEM/Core/Data/FourDArray.swift:348(lines=15); tools/parallax-preprocessing-test/main.swift:53(lines=4) |
| tiledRun | method | mac4DSTEM/Core/Analysis/OriginCalibration.swift:481(lines=58); mac4DSTEM/Core/Analysis/VirtualDetector.swift:265(lines=5) |
| transform | method | mac4DSTEM/Core/Compute/FFT1D.swift:32(lines=10); mac4DSTEM/Core/Compute/FFT2D.swift:356(lines=87) |
| u16be | method | mac4DSTEM/Core/Data/DM4Reader.swift:807(lines=1); tools/dm4-robustness-test/main.swift:17(lines=4) |
| u16le | method | mac4DSTEM/Core/Data/DM4Reader.swift:808(lines=1); tools/dm4-robustness-test/main.swift:46(lines=4) |
| u32be | method | mac4DSTEM/Core/Data/DM4Reader.swift:809(lines=1); tools/dm4-robustness-test/main.swift:22(lines=6) |
| u64be | method | mac4DSTEM/Core/Data/DM4Reader.swift:810(lines=1); tools/dm4-robustness-test/main.swift:29(lines=10) |
| u8 | method | mac4DSTEM/Core/Data/DM4Reader.swift:802(lines=4); tools/dm4-robustness-test/main.swift:15(lines=1) |
| uniform | method | tools/phase-vector-matching/main.swift:84(lines=1); tools/q-calibration-gate-test/main.swift:461(lines=4) |
| unit | method | mac4DSTEM/Core/Analysis/OrientationResult.swift:324(lines=4); tools/disk-correlation-parity/main.swift:33(lines=1) |
| validate | method | mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:472(lines=9); mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1316(lines=9) |
| value | free func/method | mac4DSTEM/Core/Data/DM4Reader.swift:831(lines=16); tools/dm4-robustness-test/main.swift:381(lines=3) |
| virtualImage | free func/method | mac4DSTEM/Core/Compute/MetalEngine.swift:222(lines=19); tools/two-spec-analysis-test/main.swift:192(lines=5) |
| warning | free func/method | mac4DSTEM/Core/Analysis/DiskDetection.swift:426(lines=3); mac4DSTEM/UI/WorkspaceSidebar.swift:300(lines=14) |
| wrapped | free func/method | mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:579(lines=4); mac4DSTEM/Core/Analysis/ProbeKernel.swift:179(lines=1); mac4DSTEM/Core/Analysis/PtychographyPreparation.swift:306(lines=4); mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:724(lines=4) |

### C2. Near-identical bodies (normalised-text SHA1 groups, >=2 members, bodies with normalised length >=20 chars to exclude trivial one-liners)

30 identical-body groups (comments stripped, whitespace collapsed, byte-identical after normalisation).

| hash | members (path:line:name) | body lines |
|---|---|---|
| a2aa69c5444b0524 | tools/acom-matching-test/main.swift:3:fail; tools/acom-orientation-test/main.swift:21:fail; tools/bragg-export-test/main.swift:3:fail; tools/cancellation-test/main.swift:4:fail; tools/datacube-discovery-test/main.swift:8:fail; tools/disk-correlation-parity/main.swift:145:fail; tools/disk-detection-test/main.swift:46:fail; tools/dm4-robustness-test/main.swift:3:fail; tools/ellipse-calibration-test/main.swift:64:fail; tools/fit-overlay-test/main.swift:9:fail; tools/idpc-test/main.swift:20:fail; tools/load-spec-calibration/main.swift:74:fail; tools/load-spec-roundtrip/main.swift:29:fail; tools/load-spec-test/main.swift:33:fail; tools/peak-overlay-test/main.swift:4:fail; tools/performance-baseline/main.swift:68:fail; tools/preprocess-crop-bin-test/main.swift:38:fail; tools/real-acom-benchmark/main.swift:31:fail; tools/resident-cropped-view/main.swift:32:fail; tools/sidecar-result-test/main.swift:3:fail; tools/strain-test/main.swift:3:fail; tools/two-spec-analysis-test/main.swift:139:fail; tools/vendor-reader-test/main.swift:3:fail; tools/virtual-detector-residency/main.swift:74:fail; tools/virtual-detector-test/main.swift:71:fail; tools/ws2-crystal-test/main.swift:24:fail | 4 |
| 90a8347da5a509cd | mac4DSTEM/Core/Data/FourDDataSource.swift:139:probeCandidates; mac4DSTEM/Core/Data/FourDDataSource.swift:143:readProbe; mac4DSTEM/Core/Data/FourDDataSource.swift:147:discoverPrimaryDataset; mac4DSTEM/Core/Data/FourDDataSource.swift:166:loadPushdown; mac4DSTEM/Core/Data/FourDDataSource.swift:177:readPattern; mac4DSTEM/Core/Data/FourDDataSource.swift:179:readScanRow; mac4DSTEM/Core/Data/FourDDataSource.swift:182:readScanTile; mac4DSTEM/Core/Data/FourDDataSource.swift:185:readDoubleAttribute; mac4DSTEM/Core/Data/FourDDataSource.swift:187:pixelCalibration | 6 |
| 60fd548a1d8cdae8 | tools/parallax-aberration-test/main.swift:63:maximumError; tools/parallax-alignment-test/main.swift:73:maximumError; tools/parallax-depth-test/main.swift:33:maximumError; tools/parallax-preprocessing-test/main.swift:73:maximumError; tools/parallax-subpixel-test/main.swift:41:maximumError; tools/singleslice-ptychography-test/main.swift:60:maximumError | 4 |
| 502067654ff4acdf | tools/load-spec-calibration/main.swift:70:check; tools/load-spec-roundtrip/main.swift:25:check; tools/load-spec-test/main.swift:29:check; tools/preprocess-crop-bin-test/main.swift:34:check | 3 |
| e3b93880c897f289 | tools/load-spec-calibration/main.swift:129:readPattern; tools/parallax-preprocessing-test/main.swift:39:readPattern; tools/performance-baseline/main.swift:21:readPattern; tools/virtual-detector-test/main.swift:19:readPattern | 3 |
| c634a0d8b2d3cc02 | tools/load-spec-calibration/main.swift:132:readScanRow; tools/performance-baseline/main.swift:25:readScanRow; tools/virtual-detector-residency/main.swift:59:readScanRow; tools/virtual-detector-test/main.swift:22:readScanRow | 3 |
| 17a84d9addac07a2 | mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:579:wrapped; mac4DSTEM/Core/Analysis/PtychographyPreparation.swift:306:wrapped; mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:724:wrapped | 4 |
| 3c87b3bdb59502fe | mac4DSTEM/Core/Analysis/DatasetPreview.swift:206:formattedCount; mac4DSTEM/Session/SystemMonitor.swift:46:count | 3 |
| 8194ba7ca9e4917e | mac4DSTEM/Core/Analysis/OrientationResult.swift:91:detectorBasis; tools/demo-dataset/export_reflections.swift:35:detectorBasis | 6 |
| ed4fa09c65ba8815 | mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:599:positiveModulo; mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:657:positiveModulo | 4 |
| ab1b4b49e3aaadff | mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:652:positiveModulo; mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift:200:positiveModulo | 4 |
| 39b8f578ece138e5 | mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:599:checkCancellation; mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:729:checkCancellation | 5 |
| 16e5823150c88fbf | mac4DSTEM/Core/Analysis/TiledDiskDetection.swift:16:admits; mac4DSTEM/Core/ML/LearnedDiskDetection.swift:173:admits | 8 |
| a1982aec53e97eb0 | mac4DSTEM/Core/Compute/FFT1D.swift:43:nextPow2; mac4DSTEM/Core/Compute/FFT2D.swift:645:nextPow2 | 5 |
| 1265c5c204dbb288 | mac4DSTEM/Core/Crystal/CIFImport.swift:742:axisDelta; mac4DSTEM/Core/Crystal/CrystalModel.swift:165:axisDelta | 5 |
| 86b4423ecff5d093 | mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:431:cartesianZoneAxis; tools/demo-dataset/export_reflections.swift:45:cartesianZoneAxis | 8 |
| 3c28ff8b8399b421 | mac4DSTEM/Core/Data/ResultPresentation.swift:257:finiteDouble; mac4DSTEM/Session/ReplayPlan.swift:860:finiteDouble | 4 |
| 5c3167b5a48f54b6 | mac4DSTEM/Support/ResultExport.swift:521:field; mac4DSTEM/Support/ResultExport.swift:567:field | 8 |
| f3d4c64b0f1a69d9 | mac4DSTEM/UI/ExportSheet.swift:276:readinessAction; mac4DSTEM/UI/PrepareSettings.swift:374:readinessAction | 66 |
| bc76a27db0c3e515 | mac4DSTEM/UI/ExportSheet.swift:391:manualScaleRows; mac4DSTEM/UI/PrepareSettings.swift:520:manualScaleRows | 18 |
| 3ff41a216d93eb2a | mac4DSTEM/UI/MapSettings.swift:1023:floatBinding; mac4DSTEM/UI/MapSettings.swift:1052:intBinding | 10 |
| 27c7c86d73a780af | mac4DSTEM/UI/MetalImageView.swift:269:makeNSView; mac4DSTEM/UI/MetalImageView.swift:277:makeUIView | 1 |
| 805d99e4e645f45d | mac4DSTEM/UI/MetalImageView.swift:270:updateNSView; mac4DSTEM/UI/MetalImageView.swift:278:updateUIView | 3 |
| 613254b441513678 | tools/cif-symmetry-test/main.swift:221:round; tools/cif-symmetry-test/main.swift:393:r | 3 |
| 058489f774c00512 | tools/datacube-discovery-test/main.swift:51:expect; tools/strain-frame-test/main.swift:35:check | 1 |
| 017c4af05373031c | tools/load-spec-calibration/main.swift:135:readScanTile; tools/performance-baseline/main.swift:29:readScanTile | 3 |
| 712fa989d8857cc7 | tools/origin-fit-diagnostics/shell-check.swift:23:next; tools/q-calibration-gate-test/main.swift:461:uniform | 4 |
| de850a57853ffa70 | tools/phase-vector-matching/main.swift:85:gaussian; tools/q-calibration-gate-test/main.swift:465:normal | 4 |
| 94b9b1c558566ec6 | tools/preprocessing-export-test/main.swift:13:readPattern; tools/reduced-export-test/main.swift:48:readPattern | 6 |
| c76f07f346db72ff | tools/resident-cropped-view/main.swift:36:pass; tools/virtual-detector-residency/main.swift:79:pass | 1 |

### C3. Grep-based known candidates

Two sub-methods: (i) named-helper definitions, taken from the C1/C2 function-body extraction filtered by name pattern, cross-referenced against the C2 hash groups for same-body/different-body; (ii) idiom/API usage-site counts (`grep -c`) for patterns that are call sites rather than repeated helper definitions.

| name | definitions found | notes |
|---|---|---|
| clamp/clamped | 1 definition: mac4DSTEM/App/Colormaps.swift:118 | single definition; no duplication |
| median | 9 definitions: mac4DSTEM/Core/Analysis/{EllipseCalibration.swift:664, OriginCalibration.swift:363, ParallaxAlignment.swift:662, QCalibration.swift:238, StrainMapping.swift:732}; tools/{acom-convention-test/main.swift:10, acom-matching-test/main.swift:218, disk-detector/scan-bench/main.swift:16, residency-sweep/main.swift:59} | different body (9 distinct hashes) |
| percentile(s) | 1 definition: tools/phase-map-probe/main.swift:1034 (`percentiles`) | single definition |
| gaussian* | 5 definitions: mac4DSTEM/Core/Analysis/{DiskDetection.swift:1028 gaussianBlur, ParallaxSubpixelReconstruction.swift:516 gaussianFilter, Precipitates/PrecipitateSegmentation.swift:398 gaussianBlur}; tools/{phase-vector-matching/main.swift:85 gaussian, rotation-null-probe/main.swift:43 nextGaussian} | different body (5 distinct hashes; DiskDetection.gaussianBlur and PrecipitateSegmentation.gaussianBlur share a name but not a body) |
| bilinear* | 1 definition: mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:479 (`bilinearSample`) | single definition |
| centerOfMass/centreOfMass | 1 Swift-side helper: mac4DSTEM/Core/Compute/MetalEngine.swift:329 (`centerOfMass`, dispatches the Metal kernel of the same name) | single definition |
| formatBytes/ByteCountFormatter | 3 definitions: mac4DSTEM/Session/SystemMonitor.swift:34 (`byteString`), mac4DSTEM/UI/LayoutPolicy.swift:230 (`displayByteString`), tools/residency-sweep/main.swift:68 (`byteString`) | different body, different names for the same concept across App/tools |
| pixelSize | 3 definitions: mac4DSTEM/App/AppState.swift:3168 (`setManualQPixelSize`), :3199 (`setManualRPixelSize`), mac4DSTEM/Core/Data/DM4Reader.swift:427 (`pixelSize`) | different body (different purposes: setters vs. a reader accessor) |
| isPowerOfTwo/nextPowerOfTwo | 2 definitions: mac4DSTEM/Core/Compute/FFT1D.swift:43, FFT2D.swift:645 (both `nextPow2`) | same body (identical hash a1982aec53e97eb0) |
| sigmoid | 0 function definitions matching `^sigmoid$`; 7 usage lines, all in mac4DSTEM/Core/Analysis/ProbeKernel.swift | n/a — used, not redefined |
| softmax | 0 matches anywhere | not present in this codebase |
| normalize/normalise | 3 definitions matching `^normali[sz]ed?$`: mac4DSTEM/Core/Data/Calibration.swift:106, mac4DSTEM/Core/Data/DiffractionPattern.swift:32 and :78 (two overloads, same file) | different body (3 distinct hashes) |
| pretty*/format(duration) | 0 matches for `pretty\w*` or duration-formatting names | not present under these names |

| pattern | usage sites |
|---|---|
| clamp (all usages incl. `.clamped(to:)`, min/max-style clamps) | 52 lines / 25 files (App, Core, Shaders, UI, tools) |
| median (all usages) | 163 lines / 36 files |
| percentile (all usages) | 8 lines / 6 files |
| gaussian (all usages) | 31 lines / 12 files |
| bilinear (all usages) | 9 lines / 6 files |
| centerOfMass/centreOfMass (all usages) | 10 lines / 4 files (VirtualDetector.swift, MetalEngine.swift, CenterOfMass.metal, tools/virtual-detector-test) |
| pixelSize / "pixel size" (all usages) | 39 lines / 19 files |
| vDSP_DFT / vDSP_fft | 26 lines / 3 files: mac4DSTEM/Core/Compute/{FFT1D.swift, FFT2D.swift}, tools/disk-correlation-parity/main.swift |
| Task.detached | 38 lines / 10 files |
| FileHandle / mmap( | 69 lines / 39 files (mostly tools/ harness data readers) |
| withCheckedThrowingContinuation | 0 matches |

## D. Non-private functions without a test reference

Method: for every `func` in mac4DSTEM/{App,Core,Session,Support} whose access is not `private`/`fileprivate` (from table B's declaration extraction), a whole-word line-match count is taken separately across `mac4DSTEMTests/**/*.swift` and `tools/**/*.swift`. This is name-reference coverage, not execution coverage: a method exercised only through a caller with a different name (e.g. called from `AppState`, itself untested by name) is counted as untested here even if it runs under the XCTest suite indirectly.

### D1. Per layer

| layer | non-private funcs | referenced by mac4DSTEMTests | referenced only by tools/ | referenced by neither | % by neither |
|---|---|---|---|---|---|
| App | 122 | 57 | 1 | 64 | 52.5 |
| Core | 384 | 272 | 65 | 47 | 12.2 |
| Session | 117 | 98 | 0 | 19 | 16.2 |
| Support | 27 | 15 | 0 | 12 | 44.4 |

### D2. Per file, Core/ and Session/

| file | non-private funcs | untested (neither) | untested func names (cap 12) |
|---|---|---|---|
| mac4DSTEM/Core/Analysis/DPC.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/DatasetPreview.swift | 4 | 2 | sourcePosition, sampledRowCount |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift | 11 | 3 | groupMap, pointAsDouble, squaredDistance |
| mac4DSTEM/Core/Analysis/DiskDetection.swift | 15 | 1 | reflected |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift | 7 | 3 | costAndNormal, fitAmorphousRing, optimize |
| mac4DSTEM/Core/Analysis/FitOverlays.swift | 7 | 1 | rawPoint |
| mac4DSTEM/Core/Analysis/OrientationResult.swift | 17 | 2 | reduceDirection, reduceDirection |
| mac4DSTEM/Core/Analysis/OriginCalibration.swift | 3 | 1 | fillBasis |
| mac4DSTEM/Core/Analysis/ParallaxAberrationCorrection.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift | 5 | 1 | defaultTerms |
| mac4DSTEM/Core/Analysis/ParallaxAlignment.swift | 4 | 0 |  |
| mac4DSTEM/Core/Analysis/ParallaxDepthSectioning.swift | 2 | 0 |  |
| mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift | 3 | 0 |  |
| mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/Precipitates/PrecipitateReflections.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift | 2 | 1 | reflected |
| mac4DSTEM/Core/Analysis/ProbeKernel.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/PtychographyPreparation.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/QCalibration.swift | 2 | 1 | shellMean |
| mac4DSTEM/Core/Analysis/RotationCalibration.swift | 5 | 0 |  |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift | 6 | 0 |  |
| mac4DSTEM/Core/Analysis/StrainFrame.swift | 3 | 0 |  |
| mac4DSTEM/Core/Analysis/StrainMapping.swift | 5 | 2 | debugPrint, qn |
| mac4DSTEM/Core/Analysis/TiledDiskDetection.swift | 1 | 0 |  |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift | 12 | 1 | realSpaceRegion |
| mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift | 1 | 0 |  |
| mac4DSTEM/Core/Compute/FFT1D.swift | 2 | 0 |  |
| mac4DSTEM/Core/Compute/FFT2D.swift | 5 | 0 |  |
| mac4DSTEM/Core/Compute/MTLTexture+Float.swift | 3 | 3 | makeFloatTexture, makeRGBATexture, makeLUTTexture |
| mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift | 2 | 1 | refinedPeak |
| mac4DSTEM/Core/Compute/MetalEngine.swift | 7 | 2 | virtualDiffraction, dpStatistics |
| mac4DSTEM/Core/Crystal/CIFImport.swift | 11 | 8 | isTag, isLoop, isDataBlock, requiredNumber, wholeNumber, nonNull, wrapAxis, lengthsMatch |
| mac4DSTEM/Core/Crystal/Crystal.swift | 9 | 1 | fourI |
| mac4DSTEM/Core/Crystal/CrystalModel.swift | 6 | 1 | axisDelta |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift | 8 | 1 | experimentalFFT |
| mac4DSTEM/Core/Crystal/OrientationPlan.swift | 5 | 0 |  |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift | 10 | 0 |  |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift | 7 | 0 |  |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift | 16 | 1 | fitMatrixOrientation |
| mac4DSTEM/Core/Crystal/ScatteringFactors.swift | 2 | 1 | isSupported |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift | 24 | 1 | linearDimension |
| mac4DSTEM/Core/Data/Calibration.swift | 9 | 4 | canonicalEditableRealUnit, reciprocalInvAngstromPerPixel, canonicalEditableReciprocalUnit, isPixelUnit |
| mac4DSTEM/Core/Data/CalibrationReReference.swift | 5 | 0 |  |
| mac4DSTEM/Core/Data/DM4Reader.swift | 21 | 1 | pairDomain |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift | 6 | 0 |  |
| mac4DSTEM/Core/Data/DisplayedProduct.swift | 4 | 1 | provenanceDifferences |
| mac4DSTEM/Core/Data/FourDArray.swift | 9 | 0 |  |
| mac4DSTEM/Core/Data/FourDDataSource.swift | 10 | 0 |  |
| mac4DSTEM/Core/Data/H5Reader.swift | 15 | 0 |  |
| mac4DSTEM/Core/Data/HDF5Types.swift | 4 | 1 | acquire |
| mac4DSTEM/Core/Data/LoadConfiguration.swift | 3 | 0 |  |
| mac4DSTEM/Core/Data/LoadSpecification.swift | 10 | 1 | requireSource |
| mac4DSTEM/Core/Data/ResidentCube.swift | 3 | 0 |  |
| mac4DSTEM/Core/Data/ResultPresentation.swift | 6 | 0 |  |
| mac4DSTEM/Core/Data/SessionReplayRecord.swift | 2 | 0 |  |
| mac4DSTEM/Core/Data/VendorRawReaders.swift | 13 | 0 |  |
| mac4DSTEM/Core/ML/LearnedDiskDetection.swift | 5 | 0 |  |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift | 15 | 0 |  |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift | 6 | 0 |  |
| mac4DSTEM/Session/ACOMSession.swift | 3 | 3 | invalidatePlan, resetForDataset, invalidateResult |
| mac4DSTEM/Session/ACOMWorkflow.swift | 1 | 0 |  |
| mac4DSTEM/Session/CalibrationSession.swift | 4 | 0 |  |
| mac4DSTEM/Session/DatasetResidency.swift | 4 | 0 |  |
| mac4DSTEM/Session/DiffractionGroupsProduct.swift | 2 | 0 |  |
| mac4DSTEM/Session/DiskCentreLabels.swift | 10 | 0 |  |
| mac4DSTEM/Session/LearnedDetection.swift | 8 | 2 | prepareForRun, livePeaks |
| mac4DSTEM/Session/LoadedView.swift | 3 | 1 | appendInvalidated |
| mac4DSTEM/Session/OperationCenter.swift | 8 | 1 | setBusy |
| mac4DSTEM/Session/PhaseMappingProduct.swift | 4 | 0 |  |
| mac4DSTEM/Session/QCalibrationRun.swift | 3 | 0 |  |
| mac4DSTEM/Session/RecentDatasets.swift | 4 | 0 |  |
| mac4DSTEM/Session/ReplayPlan.swift | 17 | 4 | positionX, positionY, perPixelScale, lengthInt |
| mac4DSTEM/Session/ReplayRun.swift | 5 | 0 |  |
| mac4DSTEM/Session/SessionCalibrationFramePolicy.swift | 3 | 0 |  |
| mac4DSTEM/Session/SessionGates.swift | 6 | 1 | isDataSourceFailure |
| mac4DSTEM/Session/SessionReplay.swift | 3 | 0 |  |
| mac4DSTEM/Session/SessionSidecarLocator.swift | 13 | 1 | noteUnreadable |
| mac4DSTEM/Session/StrainProduct.swift | 4 | 0 |  |
| mac4DSTEM/Session/SystemMonitor.swift | 1 | 1 | residentMemoryMB |
| mac4DSTEM/Session/WorkspaceRecovery.swift | 11 | 5 | volumeName, recent, saveRecent, saveRecovery, clearRecovery |

### D3. Full list, Core/ only

384 non-private Core/ funcs.

| path:line | func | refs in mac4DSTEMTests | refs in tools/ |
|---|---|---|---|
| mac4DSTEM/Core/Analysis/DPC.swift:320 | pad | 3 | 7 |
| mac4DSTEM/Core/Analysis/DatasetPreview.swift:70 | sourcePosition | 0 | 0 |
| mac4DSTEM/Core/Analysis/DatasetPreview.swift:111 | stride | 24 | 54 |
| mac4DSTEM/Core/Analysis/DatasetPreview.swift:133 | sampledRowCount | 0 | 0 |
| mac4DSTEM/Core/Analysis/DatasetPreview.swift:145 | make | 23 | 41 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:164 | compute | 28 | 29 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:404 | similarity | 9 | 0 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:437 | groupMap | 0 | 0 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:459 | compute | 28 | 29 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:460 | axis | 68 | 60 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:485 | embed | 3 | 2 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:550 | next | 23 | 18 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:586 | symmetricEigenTop | 1 | 2 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:651 | kMeans | 6 | 0 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:659 | pointAsDouble | 0 | 0 |
| mac4DSTEM/Core/Analysis/DiffractionEmbedding.swift:663 | squaredDistance | 0 | 0 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:397 | detectorAdapted | 13 | 6 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:421 | validationIssues | 7 | 6 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:423 | error | 108 | 132 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:426 | warning | 13 | 0 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:476 | provenance | 93 | 93 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:507 | replayParameters | 6 | 0 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:607 | map | 362 | 375 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:670 | detect | 4 | 10 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:676 | detectWithDiagnostics | 0 | 4 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:708 | detect | 4 | 10 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:713 | detectWithDiagnostics | 0 | 4 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:734 | correlation | 29 | 26 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:744 | cropped | 25 | 70 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:776 | refine | 11 | 0 |
| mac4DSTEM/Core/Analysis/DiskDetection.swift:1050 | reflected | 0 | 0 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:121 | fit1D | 1 | 5 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:246 | costAndNormal | 0 | 0 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:379 | fitBestAvailable | 0 | 6 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:426 | fitAmorphousRing | 0 | 0 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:495 | bounded | 1 | 2 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:516 | predictions | 0 | 1 |
| mac4DSTEM/Core/Analysis/EllipseCalibration.swift:541 | optimize | 0 | 0 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:102 | localOrigin | 1 | 5 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:119 | rawPoint | 0 | 0 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:135 | strainOverlay | 1 | 2 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:149 | raw | 20 | 57 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:153 | vector | 42 | 35 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:200 | acomTemplateOverlay | 0 | 1 |
| mac4DSTEM/Core/Analysis/FitOverlays.swift:251 | ellipsePolyline | 2 | 2 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:91 | detectorBasis | 4 | 10 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:99 | matrix | 135 | 120 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:139 | reduce | 16 | 60 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:158 | reduceDirection | 0 | 0 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:169 | sampleFundamentalZone | 0 | 2 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:213 | ipfColor | 2 | 6 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:393 | reduce | 16 | 60 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:415 | reduceDirection | 0 | 0 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:429 | sampleFundamentalZone | 0 | 2 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:471 | ipfColor | 2 | 6 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:503 | reduce | 16 | 60 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:518 | sampleFundamentalZone | 0 | 2 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:534 | ipfColor | 2 | 6 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:629 | eulerText | 6 | 0 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:673 | reliabilityThreshold | 8 | 0 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:681 | fractionOfMatchedPositions | 1 | 0 |
| mac4DSTEM/Core/Analysis/OrientationResult.swift:691 | ipfZImage | 2 | 0 |
| mac4DSTEM/Core/Analysis/OriginCalibration.swift:284 | residuals | 2 | 1 |
| mac4DSTEM/Core/Analysis/OriginCalibration.swift:352 | rms | 0 | 13 |
| mac4DSTEM/Core/Analysis/OriginCalibration.swift:387 | fillBasis | 0 | 0 |
| mac4DSTEM/Core/Analysis/ParallaxAberrationCorrection.swift:71 | correct | 10 | 23 |
| mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:129 | fitLowOrder | 0 | 3 |
| mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:233 | defaultTerms | 0 | 0 |
| mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:265 | fitHigherOrder | 0 | 2 |
| mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:375 | gradientSamples | 0 | 1 |
| mac4DSTEM/Core/Analysis/ParallaxAberrationFitting.swift:517 | scaled | 22 | 5 |
| mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:153 | defaultBinSchedule | 0 | 1 |
| mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:168 | groups | 13 | 20 |
| mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:202 | alignOneLevel | 0 | 3 |
| mac4DSTEM/Core/Analysis/ParallaxAlignment.swift:224 | alignNextLevel | 0 | 5 |
| mac4DSTEM/Core/Analysis/ParallaxDepthSectioning.swift:35 | croppedPlane | 0 | 2 |
| mac4DSTEM/Core/Analysis/ParallaxDepthSectioning.swift:87 | section | 3 | 5 |
| mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:43 | resolve | 11 | 7 |
| mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:236 | electronWavelengthAngstrom | 0 | 5 |
| mac4DSTEM/Core/Analysis/ParallaxPreprocessing.swift:248 | run | 149 | 94 |
| mac4DSTEM/Core/Analysis/ParallaxSubpixelReconstruction.swift:89 | reconstruct | 6 | 19 |
| mac4DSTEM/Core/Analysis/Precipitates/PrecipitateReflections.swift:151 | onLattice | 1 | 0 |
| mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift:371 | at | 321 | 315 |
| mac4DSTEM/Core/Analysis/Precipitates/PrecipitateSegmentation.swift:410 | reflected | 0 | 0 |
| mac4DSTEM/Core/Analysis/ProbeKernel.swift:179 | wrapped | 2 | 3 |
| mac4DSTEM/Core/Analysis/PtychographyPreparation.swift:17 | prepare | 7 | 3 |
| mac4DSTEM/Core/Analysis/QCalibration.swift:130 | estimate | 8 | 35 |
| mac4DSTEM/Core/Analysis/QCalibration.swift:172 | shellMean | 0 | 0 |
| mac4DSTEM/Core/Analysis/RotationCalibration.swift:144 | objective | 1 | 3 |
| mac4DSTEM/Core/Analysis/RotationCalibration.swift:186 | best | 13 | 33 |
| mac4DSTEM/Core/Analysis/RotationCalibration.swift:254 | depth | 19 | 24 |
| mac4DSTEM/Core/Analysis/RotationCalibration.swift:261 | nextUnit | 0 | 3 |
| mac4DSTEM/Core/Analysis/RotationCalibration.swift:273 | surrogate | 3 | 0 |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:105 | objectPhase | 0 | 2 |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:109 | objectAmplitude | 0 | 2 |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:113 | probePhase | 0 | 1 |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:117 | probeAmplitude | 0 | 1 |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:253 | factor | 8 | 36 |
| mac4DSTEM/Core/Analysis/SingleslicePtychography.swift:262 | reconstruct | 6 | 19 |
| mac4DSTEM/Core/Analysis/StrainFrame.swift:63 | resolve | 11 | 7 |
| mac4DSTEM/Core/Analysis/StrainFrame.swift:103 | component | 28 | 9 |
| mac4DSTEM/Core/Analysis/StrainFrame.swift:157 | rotate | 14 | 16 |
| mac4DSTEM/Core/Analysis/StrainMapping.swift:66 | component | 28 | 9 |
| mac4DSTEM/Core/Analysis/StrainMapping.swift:393 | cell | 22 | 37 |
| mac4DSTEM/Core/Analysis/StrainMapping.swift:462 | debugPrint | 0 | 0 |
| mac4DSTEM/Core/Analysis/StrainMapping.swift:481 | q | 103 | 66 |
| mac4DSTEM/Core/Analysis/StrainMapping.swift:487 | qn | 0 | 0 |
| mac4DSTEM/Core/Analysis/TiledDiskDetection.swift:16 | admits | 3 | 10 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:82 | realSpaceRegion | 0 | 0 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:113 | radii | 7 | 20 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:137 | tile | 14 | 110 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:157 | cancel | 11 | 45 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:209 | binding | 1 | 11 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:237 | cancel | 11 | 45 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:252 | tiledImage | 1 | 29 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:265 | tiledRun | 8 | 12 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:352 | tiledDPStatistics | 0 | 7 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:402 | tiledDiffraction | 0 | 9 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:442 | tiledMeasuredOrigins | 0 | 7 |
| mac4DSTEM/Core/Analysis/VirtualDetector.swift:483 | tiledCenterOfMass | 0 | 6 |
| mac4DSTEM/Core/Compute/AnalysisCancellationToken.swift:19 | cancel | 11 | 45 |
| mac4DSTEM/Core/Compute/FFT1D.swift:32 | transform | 20 | 21 |
| mac4DSTEM/Core/Compute/FFT1D.swift:43 | nextPow2 | 1 | 0 |
| mac4DSTEM/Core/Compute/FFT2D.swift:145 | filter | 35 | 45 |
| mac4DSTEM/Core/Compute/FFT2D.swift:177 | execute | 1 | 0 |
| mac4DSTEM/Core/Compute/FFT2D.swift:356 | transform | 20 | 21 |
| mac4DSTEM/Core/Compute/FFT2D.swift:645 | nextPow2 | 1 | 0 |
| mac4DSTEM/Core/Compute/FFT2D.swift:652 | fftfreq | 0 | 1 |
| mac4DSTEM/Core/Compute/MTLTexture+Float.swift:14 | makeFloatTexture | 0 | 0 |
| mac4DSTEM/Core/Compute/MTLTexture+Float.swift:31 | makeRGBATexture | 0 | 0 |
| mac4DSTEM/Core/Compute/MTLTexture+Float.swift:47 | makeLUTTexture | 0 | 0 |
| mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift:25 | refinedPeak | 0 | 0 |
| mac4DSTEM/Core/Compute/MatrixDFTCorrelation.swift:71 | refine | 11 | 0 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:180 | display | 25 | 1 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:204 | virtualDetector | 16 | 0 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:222 | virtualImage | 0 | 17 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:262 | virtualDiffraction | 0 | 0 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:287 | dpStatistics | 0 | 0 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:309 | measureOrigins | 0 | 7 |
| mac4DSTEM/Core/Compute/MetalEngine.swift:329 | centerOfMass | 0 | 1 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:109 | crystalModel | 17 | 1 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:185 | isTag | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:186 | isLoop | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:187 | isDataBlock | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:266 | requiredNumber | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:533 | apply | 32 | 14 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:619 | wholeNumber | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:639 | nonNull | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:768 | wrapAxis | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:791 | lengthsMatch | 0 | 0 |
| mac4DSTEM/Core/Crystal/CIFImport.swift:794 | angleMatches | 0 | 3 |
| mac4DSTEM/Core/Crystal/Crystal.swift:112 | reflections | 26 | 58 |
| mac4DSTEM/Core/Crystal/Crystal.swift:173 | fcc | 19 | 11 |
| mac4DSTEM/Core/Crystal/Crystal.swift:183 | bcc | 1 | 0 |
| mac4DSTEM/Core/Crystal/Crystal.swift:191 | sc | 2 | 9 |
| mac4DSTEM/Core/Crystal/Crystal.swift:196 | diamond | 1 | 2 |
| mac4DSTEM/Core/Crystal/Crystal.swift:204 | hcp | 0 | 1 |
| mac4DSTEM/Core/Crystal/Crystal.swift:234 | cubic | 22 | 56 |
| mac4DSTEM/Core/Crystal/Crystal.swift:283 | fourI | 0 | 0 |
| mac4DSTEM/Core/Crystal/Crystal.swift:356 | row | 163 | 186 |
| mac4DSTEM/Core/Crystal/CrystalModel.swift:35 | add | 19 | 0 |
| mac4DSTEM/Core/Crystal/CrystalModel.swift:91 | approximately | 0 | 2 |
| mac4DSTEM/Core/Crystal/CrystalModel.swift:152 | cross | 6 | 10 |
| mac4DSTEM/Core/Crystal/CrystalModel.swift:165 | axisDelta | 0 | 0 |
| mac4DSTEM/Core/Crystal/CrystalModel.swift:335 | model | 98 | 60 |
| mac4DSTEM/Core/Crystal/CrystalModel.swift:339 | customCubic | 16 | 0 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:36 | sourceIndices | 3 | 2 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:67 | positionCount | 2 | 4 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:71 | expandedPreview | 1 | 0 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:123 | match | 53 | 49 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:224 | experimentalPolarImage | 0 | 1 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:249 | templateScores | 0 | 4 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:281 | experimentalFFT | 0 | 0 |
| mac4DSTEM/Core/Crystal/OrientationMatcher.swift:455 | matchAll | 1 | 10 |
| mac4DSTEM/Core/Crystal/OrientationPlan.swift:100 | generate | 2 | 22 |
| mac4DSTEM/Core/Crystal/OrientationPlan.swift:187 | project | 3 | 8 |
| mac4DSTEM/Core/Crystal/OrientationPlan.swift:247 | buildPolar | 0 | 1 |
| mac4DSTEM/Core/Crystal/OrientationPlan.swift:289 | ringFFTs | 0 | 1 |
| mac4DSTEM/Core/Crystal/OrientationPlan.swift:331 | normalizeUnit | 0 | 2 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:49 | explainedFraction | 9 | 0 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:69 | medianMatrixExplainedFraction | 2 | 0 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:80 | color | 6 | 11 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:91 | image | 121 | 66 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:124 | distanceImage | 2 | 0 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:130 | distanceValidity | 1 | 0 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:143 | legend | 9 | 2 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:178 | diagnosis | 11 | 1 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:228 | evidenceLine | 3 | 0 |
| mac4DSTEM/Core/Crystal/PhaseMapPresentation.swift:229 | name | 100 | 328 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:92 | chanceMatchFraction | 7 | 5 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:146 | cartesian | 8 | 0 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:348 | build | 21 | 11 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:416 | inPlaneSteps | 4 | 1 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:431 | cartesianZoneAxis | 6 | 3 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:443 | projectedVectors | 9 | 3 |
| mac4DSTEM/Core/Crystal/PhaseReferenceLibrary.swift:517 | rotate | 14 | 16 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:216 | scaledToDetector | 4 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:311 | count | 343 | 665 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:340 | experimentalVectors | 2 | 5 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:367 | nearest | 20 | 21 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:408 | score | 42 | 73 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:436 | containsFriedelPair | 2 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:526 | isInformative | 3 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:539 | isAboveChance | 6 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:563 | fitZoneAxis | 7 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:701 | fitMatrixOrientation | 0 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:761 | classify | 28 | 3 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:946 | matrixChallengeBases | 3 | 2 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:995 | challengeByMatrix | 5 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:1075 | projectedAzimuth | 11 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:1106 | orientationConsistent | 14 | 0 |
| mac4DSTEM/Core/Crystal/PhaseVectorMatching.swift:1142 | map | 362 | 375 |
| mac4DSTEM/Core/Crystal/ScatteringFactors.swift:236 | isSupported | 0 | 0 |
| mac4DSTEM/Core/Crystal/ScatteringFactors.swift:240 | electronScatteringFactor | 0 | 1 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:240 | compose | 1 | 1 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:330 | minimumReaderSchema | 4 | 0 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:402 | writeScientificBundle | 0 | 3 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:472 | sessionSidecarURL | 2 | 0 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:481 | write | 38 | 83 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:501 | writeCalibratedDataCube | 0 | 6 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:595 | mergeResultMap | 2 | 10 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:633 | mergeRGBAResultMap | 1 | 1 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:666 | mergeCalibration | 21 | 4 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:704 | removeResult | 0 | 1 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:758 | loadSession | 12 | 13 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:848 | loadInventory | 0 | 4 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:852 | loadResultMap | 2 | 10 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:856 | loadResultMap | 2 | 10 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:881 | loadRGBAResultMap | 2 | 4 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:913 | loadDiskCentreLabelsJSON | 5 | 0 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:931 | resultNodeName | 1 | 6 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1453 | cropped | 25 | 70 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1499 | inside | 45 | 27 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:1604 | linearDimension | 0 | 0 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2752 | currentErrorStack | 0 | 1 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2788 | load | 50 | 31 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2804 | symbol | 4 | 5 |
| mac4DSTEM/Core/Data/BraggVectorEMDWriter.swift:2810 | global | 11 | 2 |
| mac4DSTEM/Core/Data/Calibration.swift:106 | normalized | 3 | 14 |
| mac4DSTEM/Core/Data/Calibration.swift:115 | realAngstromPerPixel | 0 | 1 |
| mac4DSTEM/Core/Data/Calibration.swift:129 | canonicalEditableRealUnit | 0 | 0 |
| mac4DSTEM/Core/Data/Calibration.swift:142 | reciprocalInvAngstromPerPixel | 0 | 0 |
| mac4DSTEM/Core/Data/Calibration.swift:162 | canonicalEditableReciprocalUnit | 0 | 0 |
| mac4DSTEM/Core/Data/Calibration.swift:177 | isPhysicalReciprocalUnit | 0 | 1 |
| mac4DSTEM/Core/Data/Calibration.swift:182 | isPixelUnit | 0 | 0 |
| mac4DSTEM/Core/Data/Calibration.swift:283 | make | 23 | 41 |
| mac4DSTEM/Core/Data/Calibration.swift:667 | originSupportsReciprocalMetrology | 0 | 5 |
| mac4DSTEM/Core/Data/CalibrationReReference.swift:148 | apply | 32 | 14 |
| mac4DSTEM/Core/Data/CalibrationReReference.swift:361 | select | 2 | 1 |
| mac4DSTEM/Core/Data/CalibrationReReference.swift:394 | binnedCoordinate | 6 | 1 |
| mac4DSTEM/Core/Data/CalibrationReReference.swift:407 | sourceCoordinate | 2 | 0 |
| mac4DSTEM/Core/Data/CalibrationReReference.swift:414 | scale | 103 | 59 |
| mac4DSTEM/Core/Data/DM4Reader.swift:108 | discoverPrimaryDataset | 25 | 51 |
| mac4DSTEM/Core/Data/DM4Reader.swift:217 | sweep | 21 | 27 |
| mac4DSTEM/Core/Data/DM4Reader.swift:233 | transpose | 15 | 24 |
| mac4DSTEM/Core/Data/DM4Reader.swift:285 | readPattern | 6 | 43 |
| mac4DSTEM/Core/Data/DM4Reader.swift:295 | readScanRow | 8 | 29 |
| mac4DSTEM/Core/Data/DM4Reader.swift:340 | readScanTile | 6 | 35 |
| mac4DSTEM/Core/Data/DM4Reader.swift:376 | readDoubleAttribute | 6 | 10 |
| mac4DSTEM/Core/Data/DM4Reader.swift:384 | pixelCalibration | 6 | 25 |
| mac4DSTEM/Core/Data/DM4Reader.swift:722 | pairDomain | 0 | 0 |
| mac4DSTEM/Core/Data/DM4Reader.swift:754 | scale | 103 | 59 |
| mac4DSTEM/Core/Data/DM4Reader.swift:755 | units | 31 | 40 |
| mac4DSTEM/Core/Data/DM4Reader.swift:802 | u8 | 0 | 6 |
| mac4DSTEM/Core/Data/DM4Reader.swift:807 | u16be | 0 | 5 |
| mac4DSTEM/Core/Data/DM4Reader.swift:808 | u16le | 0 | 4 |
| mac4DSTEM/Core/Data/DM4Reader.swift:809 | u32be | 0 | 3 |
| mac4DSTEM/Core/Data/DM4Reader.swift:810 | u64be | 0 | 16 |
| mac4DSTEM/Core/Data/DM4Reader.swift:812 | special | 1 | 4 |
| mac4DSTEM/Core/Data/DM4Reader.swift:816 | bytes | 43 | 77 |
| mac4DSTEM/Core/Data/DM4Reader.swift:826 | string | 16 | 9 |
| mac4DSTEM/Core/Data/DM4Reader.swift:831 | value | 73 | 86 |
| mac4DSTEM/Core/Data/DM4Reader.swift:848 | seek | 0 | 2 |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift:22 | discoverPrimaryDataset | 25 | 51 |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift:30 | readPattern | 6 | 43 |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift:47 | readScanRow | 8 | 29 |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift:58 | readScanTile | 6 | 35 |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift:87 | readDoubleAttribute | 6 | 10 |
| mac4DSTEM/Core/Data/DemoFourDDataSource.swift:91 | pixelCalibration | 6 | 25 |
| mac4DSTEM/Core/Data/DisplayedProduct.swift:129 | sample | 15 | 13 |
| mac4DSTEM/Core/Data/DisplayedProduct.swift:184 | compatibility | 1 | 1 |
| mac4DSTEM/Core/Data/DisplayedProduct.swift:207 | difference | 14 | 17 |
| mac4DSTEM/Core/Data/DisplayedProduct.swift:229 | provenanceDifferences | 0 | 0 |
| mac4DSTEM/Core/Data/FourDArray.swift:50 | pattern | 104 | 200 |
| mac4DSTEM/Core/Data/FourDArray.swift:82 | clearCache | 0 | 2 |
| mac4DSTEM/Core/Data/FourDArray.swift:87 | scanTile | 3 | 17 |
| mac4DSTEM/Core/Data/FourDArray.swift:133 | resident | 27 | 134 |
| mac4DSTEM/Core/Data/FourDArray.swift:151 | resident | 27 | 134 |
| mac4DSTEM/Core/Data/FourDArray.swift:224 | setResidencyRequest | 2 | 9 |
| mac4DSTEM/Core/Data/FourDArray.swift:252 | makeResident | 4 | 11 |
| mac4DSTEM/Core/Data/FourDArray.swift:322 | releaseResident | 2 | 3 |
| mac4DSTEM/Core/Data/FourDArray.swift:369 | scanTileRows | 0 | 2 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:139 | probeCandidates | 0 | 5 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:143 | readProbe | 0 | 4 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:147 | discoverPrimaryDataset | 25 | 51 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:177 | readPattern | 6 | 43 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:179 | readScanRow | 8 | 29 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:182 | readScanTile | 6 | 35 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:185 | readDoubleAttribute | 6 | 10 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:187 | pixelCalibration | 6 | 25 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:191 | probeCandidates | 0 | 5 |
| mac4DSTEM/Core/Data/FourDDataSource.swift:192 | readProbe | 0 | 4 |
| mac4DSTEM/Core/Data/H5Reader.swift:160 | load | 50 | 31 |
| mac4DSTEM/Core/Data/H5Reader.swift:178 | symbol | 4 | 5 |
| mac4DSTEM/Core/Data/H5Reader.swift:185 | global | 11 | 2 |
| mac4DSTEM/Core/Data/H5Reader.swift:292 | discoverPrimaryDataset | 25 | 51 |
| mac4DSTEM/Core/Data/H5Reader.swift:455 | probeCandidates | 0 | 5 |
| mac4DSTEM/Core/Data/H5Reader.swift:486 | readProbe | 0 | 4 |
| mac4DSTEM/Core/Data/H5Reader.swift:536 | describe | 8 | 8 |
| mac4DSTEM/Core/Data/H5Reader.swift:734 | readPattern | 6 | 43 |
| mac4DSTEM/Core/Data/H5Reader.swift:746 | readScanRow | 8 | 29 |
| mac4DSTEM/Core/Data/H5Reader.swift:755 | readScanTile | 6 | 35 |
| mac4DSTEM/Core/Data/H5Reader.swift:778 | pixelCalibration | 6 | 25 |
| mac4DSTEM/Core/Data/H5Reader.swift:792 | scalar | 26 | 16 |
| mac4DSTEM/Core/Data/H5Reader.swift:796 | string | 16 | 9 |
| mac4DSTEM/Core/Data/H5Reader.swift:852 | dim | 7 | 1 |
| mac4DSTEM/Core/Data/H5Reader.swift:1032 | readDoubleAttribute | 6 | 10 |
| mac4DSTEM/Core/Data/HDF5Types.swift:39 | savePanelSeedName | 3 | 0 |
| mac4DSTEM/Core/Data/HDF5Types.swift:93 | run | 149 | 94 |
| mac4DSTEM/Core/Data/HDF5Types.swift:100 | acquire | 0 | 0 |
| mac4DSTEM/Core/Data/HDF5Types.swift:101 | release | 19 | 8 |
| mac4DSTEM/Core/Data/LoadConfiguration.swift:101 | scanCrop | 22 | 43 |
| mac4DSTEM/Core/Data/LoadConfiguration.swift:114 | detectorCrop | 36 | 72 |
| mac4DSTEM/Core/Data/LoadConfiguration.swift:220 | fitsResident | 1 | 0 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:151 | fits | 20 | 4 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:368 | sourceScanY | 0 | 5 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:370 | sourceScanX | 0 | 5 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:384 | detectorView | 0 | 1 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:421 | binned | 31 | 36 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:450 | requireSource | 0 | 0 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:474 | pattern | 104 | 200 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:481 | scanRow | 3 | 5 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:490 | scanTile | 3 | 17 |
| mac4DSTEM/Core/Data/LoadSpecification.swift:543 | decoded | 20 | 11 |
| mac4DSTEM/Core/Data/ResidentCube.swift:100 | matches | 4 | 18 |
| mac4DSTEM/Core/Data/ResidentCube.swift:148 | admits | 3 | 10 |
| mac4DSTEM/Core/Data/ResidentCube.swift:180 | shouldAdmit | 0 | 4 |
| mac4DSTEM/Core/Data/ResultPresentation.swift:32 | make | 23 | 41 |
| mac4DSTEM/Core/Data/ResultPresentation.swift:63 | nearestIndex | 1 | 3 |
| mac4DSTEM/Core/Data/ResultPresentation.swift:67 | point | 39 | 31 |
| mac4DSTEM/Core/Data/ResultPresentation.swift:82 | sampling | 14 | 17 |
| mac4DSTEM/Core/Data/ResultPresentation.swift:89 | provenance | 93 | 93 |
| mac4DSTEM/Core/Data/ResultPresentation.swift:190 | parse | 62 | 11 |
| mac4DSTEM/Core/Data/SessionReplayRecord.swift:67 | record | 180 | 26 |
| mac4DSTEM/Core/Data/SessionReplayRecord.swift:101 | parse | 62 | 11 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:74 | discoverPrimaryDataset | 25 | 51 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:86 | readPattern | 6 | 43 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:116 | readScanRow | 8 | 29 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:132 | readScanTile | 6 | 35 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:148 | readDoubleAttribute | 6 | 10 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:149 | pixelCalibration | 6 | 25 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:156 | element | 4 | 14 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:292 | discoverPrimaryDataset | 25 | 51 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:303 | readPattern | 6 | 43 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:333 | readScanRow | 8 | 29 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:347 | readScanTile | 6 | 35 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:363 | readDoubleAttribute | 6 | 10 |
| mac4DSTEM/Core/Data/VendorRawReaders.swift:364 | pixelCalibration | 6 | 25 |
| mac4DSTEM/Core/ML/LearnedDiskDetection.swift:62 | provenance | 93 | 93 |
| mac4DSTEM/Core/ML/LearnedDiskDetection.swift:88 | positionMatchedMap | 9 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetection.swift:137 | pair | 37 | 35 |
| mac4DSTEM/Core/ML/LearnedDiskDetection.swift:173 | admits | 3 | 10 |
| mac4DSTEM/Core/ML/LearnedDiskDetection.swift:316 | bundledAssetURL | 1 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:71 | load | 50 | 31 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:97 | sha256 | 8 | 1 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:130 | toCounts | 3 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:140 | modelInputs | 5 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:159 | pickPeaks | 4 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:189 | fitOffset | 7 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:198 | window | 56 | 16 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:219 | windowOverlap | 5 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:232 | windowOrigins | 15 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:254 | mergeWindows | 5 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:273 | heatmaps | 7 | 0 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:317 | detect | 4 | 10 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:348 | detectAll | 19 | 18 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:402 | prepare | 7 | 3 |
| mac4DSTEM/Core/ML/LearnedDiskDetector.swift:423 | finish | 16 | 0 |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:37 | begin | 15 | 0 |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:49 | finish | 16 | 0 |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:55 | isCurrent | 3 | 0 |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:60 | cancelCurrent | 2 | 0 |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:68 | reset | 31 | 3 |
| mac4DSTEM/Core/Workflow/AnalysisOperationController.swift:73 | metrics | 6 | 17 |
## E. Build time per target

Machine: Apple M3, 8 GB RAM. Xcode 27.0 (Build 27A5209h), active toolchain `/Applications/Xcode-beta.app`. Swift: `Apple Swift version 6.4 (swiftlang-6.4.0.23.5 clang-2100.3.23.3)`, target `arm64-apple-macosx27.0.0`.

Method: each build redirected to its own log under the scratchpad, exit code read from `echo $?` on its own line (never through a pipe), wall time from `date +%s` deltas around the command. `E1`/`E2` use `swift build --scratch-path $S/spm`; `E3`/`E4` use `xcodebuild -derivedDataPath $S/dd -showBuildTimingSummary`. E2 cold runs immediately after E1 (E1's product is a dependency of DSTEMSession, so this is "cold for DSTEMSession, warm for DSTEMCore"). E3 warm is a second `build` invocation with zero source changes. E4 (`build-for-testing`, `CODE_SIGNING_ALLOWED=NO`, nothing launched) runs after E3 so the app target is already built; its cost is the increment to compile+link `mac4DSTEMTests`.

| target | wall seconds | (cold/warm shown as separate rows) | warnings (grep -c 'warning:') | errors | log name |
|---|---|---|---|---|---|
| DSTEMCore (SPM) — cold | 25 | - | 0 | 0 | E1_cold.log |
| DSTEMCore (SPM) — warm | 2 | - | 0 | 0 | E1_warm.log |
| DSTEMSession (SPM) — cold-after-E1 | 9 | - | 0 | 0 | E2_cold.log |
| DSTEMSession (SPM) — warm | 1 | - | 0 | 0 | E2_warm.log |
| mac4DSTEM app (xcodebuild build) — cold | 59 | - | 11 (5 distinct compiler diagnostics + duplicate caret lines + 1 non-compiler appintentsmetadataprocessor note) | 0 | E3_cold.log |
| mac4DSTEM app (xcodebuild build) — warm (no changes) | 4 | - | 0 | 0 | E3_warm.log |
| mac4DSTEMTests (build-for-testing, warm-after-E3, increment only) | 19 | - | 2 (both non-compiler appintentsmetadataprocessor notes) | 0 | E4.log |

Tool-reported build durations (from each log's own "Build complete!" / timing summary, for cross-check against the wall-clock column above): DSTEMCore cold 19.79s, DSTEMCore warm 0.78s, DSTEMSession cold 8.29s, DSTEMSession warm 0.33s. xcodebuild does not print a single scalar duration; its per-phase Build Timing Summary is below.

### Top 5 phases by time, mac4DSTEM app build (E3 cold, `-showBuildTimingSummary`)

| phase | tasks | seconds (summed across parallel tasks; wall time was 59 s) |
|---|---|---|
| SwiftCompile | 24 | 207.400 |
| CompileMetalFile | 8 | 20.275 |
| SwiftEmitModule | 3 | 11.606 |
| CompileAssetCatalogVariant | 1 | 3.809 |
| SwiftDriver | 3 | 2.945 |

E3 warm produced no Build Timing Summary entries (nothing to rebuild).

### Top 5 phases by time, mac4DSTEMTests build-for-testing (E4)

| phase | tasks | seconds |
|---|---|---|
| SwiftCompile | 8 | 45.035 |
| SwiftDriver | 1 | 2.078 |
| SwiftEmitModule | 1 | 1.527 |
| Ld | 2 | 1.354 |
| Copy | 7 | 0.301 |

### Disk before/after each build (`df -g /` / `df -k /`, Available column)

| step | before | after |
|---|---|---|
| baseline (session start) | 6 GB (rounded) | - |
| E1 cold | 6 GB (rounded) | 6 GB (rounded) |
| E1 warm | 6 GB (rounded) | 6 GB (rounded) |
| E2 cold | 6 GB (rounded) | 6 GB (rounded) |
| E2 warm | 6.10 GB (6400396 KB) | 6.10 GB (unchanged) |
| E3 cold | 5.70 GB (5976432 KB) | 5.70 GB (5976432 KB, i.e. E3 cold's own before/after both landed at this reading) |
| E3 warm | 5.69 GB (5960724 KB) | 5.68 GB (5960108 KB) |
| E4 | 5.68 GB (5959556 KB) | 5.55 GB (5818860 KB) |

Never below the 3 GB floor at any point; net consumption across all of E was roughly 0.5-0.6 GB (DerivedData at `$S/dd` measured 405 MB after E3 cold; SPM scratch at `$S/spm` measured 271 MB after E1+E2). Both scratch directories were deleted at the end of this audit.

## F. Test inventory

### F1. Per file, mac4DSTEMTests/

Method: `func test` counts a top-level `func test...(` declaration (regex anchored per line); "files referenced by type name" counts distinct `mac4DSTEM/` source files whose declared type (class/struct/enum/actor/protocol, from table B's extraction) appears as a whole word in the test file — this is a name-overlap heuristic, not an import/compile-graph analysis.

| file | lines | func test count | XCTSkip count | throw XCTSkip count | mac4DSTEM/ files referenced by type name |
|---|---|---|---|---|---|
| mac4DSTEMTests/ACOMScanSelectionTests.swift | 160 | 8 | 0 | 0 | 1 |
| mac4DSTEMTests/ACOMSessionTests.swift | 106 | 6 | 0 | 0 | 3 |
| mac4DSTEMTests/ActivityLogTests.swift | 195 | 8 | 0 | 0 | 5 |
| mac4DSTEMTests/AnalysisOperationControllerTests.swift | 57 | 3 | 0 | 0 | 1 |
| mac4DSTEMTests/CIFImportAppStateTests.swift | 193 | 6 | 0 | 0 | 1 |
| mac4DSTEMTests/CIFImportTests.swift | 563 | 21 | 0 | 0 | 1 |
| mac4DSTEMTests/CalibrationDisclosureTests.swift | 134 | 4 | 0 | 0 | 4 |
| mac4DSTEMTests/CalibrationReReferenceTests.swift | 876 | 38 | 0 | 0 | 9 |
| mac4DSTEMTests/CalibrationReadinessFilenameTests.swift | 78 | 8 | 0 | 0 | 1 |
| mac4DSTEMTests/ComparisonPanelVersionTests.swift | 189 | 11 | 0 | 0 | 3 |
| mac4DSTEMTests/DatacubeDiscoveryTests.swift | 71 | 5 | 0 | 0 | 1 |
| mac4DSTEMTests/DatasetLoadCancellationTests.swift | 176 | 8 | 0 | 0 | 1 |
| mac4DSTEMTests/DatasetLoadingProgressTests.swift | 175 | 7 | 0 | 0 | 4 |
| mac4DSTEMTests/DatasetPreviewTests.swift | 169 | 9 | 0 | 0 | 3 |
| mac4DSTEMTests/DatasetResidencyTests.swift | 307 | 10 | 0 | 0 | 5 |
| mac4DSTEMTests/DemoWorkflowTests.swift | 79 | 2 | 0 | 0 | 4 |
| mac4DSTEMTests/DiffractionEmbeddingTests.swift | 706 | 10 | 0 | 0 | 4 |
| mac4DSTEMTests/DiskCentreLabelTests.swift | 334 | 22 | 0 | 0 | 2 |
| mac4DSTEMTests/DiskDetectionContractTests.swift | 228 | 8 | 0 | 0 | 0 |
| mac4DSTEMTests/ErrorRoutingTests.swift | 115 | 7 | 0 | 0 | 4 |
| mac4DSTEMTests/ExportProvenanceTests.swift | 132 | 3 | 0 | 0 | 1 |
| mac4DSTEMTests/FFT2DArbitraryLengthTests.swift | 278 | 8 | 0 | 0 | 2 |
| mac4DSTEMTests/FitOverlayPresentationTests.swift | 171 | 6 | 0 | 0 | 2 |
| mac4DSTEMTests/ImageContentVersionTests.swift | 68 | 5 | 0 | 0 | 2 |
| mac4DSTEMTests/LearnedDetectionSessionTests.swift | 181 | 10 | 2 | 2 | 2 |
| mac4DSTEMTests/LearnedDiskDetectionScanTests.swift | 333 | 8 | 0 | 0 | 5 |
| mac4DSTEMTests/LearnedDiskDetectorGateBTests.swift | 340 | 9 | 0 | 0 | 1 |
| mac4DSTEMTests/LearnedDiskDetectorTests.swift | 304 | 8 | 2 | 2 | 1 |
| mac4DSTEMTests/LoadConfigurationTests.swift | 252 | 15 | 0 | 0 | 0 |
| mac4DSTEMTests/MetalLayerScaleTests.swift | 100 | 2 | 0 | 0 | 1 |
| mac4DSTEMTests/NavigationSeamTests.swift | 91 | 4 | 0 | 0 | 3 |
| mac4DSTEMTests/OverlayGeometryTests.swift | 158 | 8 | 0 | 0 | 5 |
| mac4DSTEMTests/PendingLoadConfiguratorTests.swift | 186 | 13 | 0 | 0 | 1 |
| mac4DSTEMTests/PhaseVectorMatchingTests.swift | 2023 | 49 | 0 | 0 | 5 |
| mac4DSTEMTests/PrecipitateTests.swift | 1041 | 17 | 0 | 0 | 3 |
| mac4DSTEMTests/ProbeKernelFlatTests.swift | 158 | 6 | 0 | 0 | 1 |
| mac4DSTEMTests/ProbeSizeTests.swift | 302 | 7 | 0 | 0 | 3 |
| mac4DSTEMTests/ProductWorkflowTests.swift | 1109 | 46 | 0 | 0 | 13 |
| mac4DSTEMTests/PromoteToFullExtentTests.swift | 71 | 2 | 0 | 0 | 2 |
| mac4DSTEMTests/QCalibrationOriginGateTests.swift | 358 | 7 | 0 | 0 | 3 |
| mac4DSTEMTests/RealSpacePointerPolicyTests.swift | 129 | 9 | 0 | 0 | 4 |
| mac4DSTEMTests/RecentDatasetLocationTests.swift | 97 | 9 | 0 | 0 | 0 |
| mac4DSTEMTests/RecentDatasetsTests.swift | 113 | 7 | 0 | 0 | 2 |
| mac4DSTEMTests/ReplayExecutionTests.swift | 249 | 7 | 0 | 0 | 3 |
| mac4DSTEMTests/ReplayPlanTests.swift | 865 | 60 | 0 | 0 | 5 |
| mac4DSTEMTests/ReplayRunTests.swift | 156 | 9 | 0 | 0 | 2 |
| mac4DSTEMTests/ResultOrientationTests.swift | 219 | 11 | 0 | 0 | 2 |
| mac4DSTEMTests/ResultPresentationTests.swift | 107 | 6 | 0 | 0 | 1 |
| mac4DSTEMTests/S22ePolishTests.swift | 99 | 3 | 0 | 0 | 3 |
| mac4DSTEMTests/SessionCalibrationFramePolicyTests.swift | 61 | 4 | 0 | 0 | 0 |
| mac4DSTEMTests/SessionCalibrationTranslationTests.swift | 232 | 11 | 1 | 1 | 4 |
| mac4DSTEMTests/SessionGatesTests.swift | 369 | 9 | 0 | 0 | 5 |
| mac4DSTEMTests/SessionReplayAppStateTests.swift | 104 | 3 | 0 | 0 | 3 |
| mac4DSTEMTests/SessionReplayTests.swift | 365 | 19 | 0 | 0 | 2 |
| mac4DSTEMTests/SessionSidecarLocatorTests.swift | 355 | 14 | 0 | 0 | 2 |
| mac4DSTEMTests/SidecarRecognitionTests.swift | 213 | 6 | 0 | 0 | 1 |
| mac4DSTEMTests/SidecarRelocationTests.swift | 101 | 6 | 0 | 0 | 1 |
| mac4DSTEMTests/StatusBarMetricsTests.swift | 143 | 4 | 0 | 0 | 2 |
| mac4DSTEMTests/StrainFailureCauseTests.swift | 90 | 4 | 0 | 0 | 2 |
| mac4DSTEMTests/StrainFrameTests.swift | 406 | 15 | 0 | 0 | 2 |
| mac4DSTEMTests/StrainProductTests.swift | 139 | 8 | 0 | 0 | 2 |
| mac4DSTEMTests/TB1StallProbeTests.swift | 151 | 4 | 0 | 0 | 1 |
| mac4DSTEMTests/TiledDiskDetectionErrorTests.swift | 189 | 5 | 0 | 0 | 4 |
| mac4DSTEMTests/WorkspaceRecoveryTests.swift | 28 | 2 | 0 | 0 | 0 |
| mac4DSTEMTests/ZoomPanClampTests.swift | 49 | 3 | 0 | 0 | 2 |
| TOTAL | 17596 | 672 | 5 | 5 | 168 |

### F2. tools/ harnesses

Method: 67 directories exist directly under `tools/`; 62 have a `main.swift` (at depth <=2) or a `run.sh`. The 5 excluded from this table (`tools/crystal-structures`, `tools/lib`, `tools/precipitate-handcount`, `tools/release`, `tools/review-record-check`) have neither and are data/support directories, not runnable harnesses (`precipitate-handcount` and `review-record-check` are nonetheless named in `run-tests.sh`'s `diagnostic` classification array). "in run-tests.sh" = the directory name appears as a whole word anywhere in `tools/run-tests.sh` (its `scientific`/`campaign`/`diagnostic`/`support` arrays, or a direct `run_harnesses` call). "in ci.yml" = the directory name is a member of `run-tests.sh`'s `scientific` array, since `.github/workflows/ci.yml` only ever invokes `tools/run-tests.sh {unit,scientific,inventory,core}` and never names an individual tools/ directory itself; the `scientific` job is therefore the only CI job that runs any of these harnesses, and it runs exactly the `scientific` array (46 of the 62).

| tool | in run-tests.sh | in ci.yml (scientific array) | lines (swift+metal) |
|---|---|---|---|
| acom-convention-test | yes | yes | 198 |
| acom-groundtruth | yes | no | 266 |
| acom-matching-test | yes | yes | 355 |
| acom-orientation-test | yes | yes | 227 |
| bragg-export-test | yes | yes | 78 |
| bragg-spacing-probe | yes | no | 292 |
| calibration-readiness-test | yes | yes | 265 |
| calibration-test | yes | yes | 98 |
| cancellation-test | yes | yes | 101 |
| cif-symmetry-test | yes | yes | 1268 |
| comparator-test | yes | yes | 0 |
| datacube-discovery-test | yes | yes | 248 |
| demo-dataset | yes | no | 120 |
| disk-correlation-parity | yes | yes | 360 |
| disk-detection-test | yes | yes | 328 |
| disk-detector | yes | yes | 83 |
| dm4-robustness-test | yes | yes | 587 |
| ellipse-calibration-test | yes | yes | 312 |
| embedding-pca-parity | yes | yes | 174 |
| fit-overlay-test | yes | yes | 264 |
| hdf5-race-probe | yes | no | 140 |
| idpc-test | yes | yes | 177 |
| load-spec-calibration | yes | yes | 353 |
| load-spec-roundtrip | yes | yes | 222 |
| load-spec-test | yes | yes | 568 |
| origin-fit-diagnostics | yes | no | 778 |
| package-test | yes | no | 0 |
| parallax-aberration-test | yes | yes | 298 |
| parallax-alignment-test | yes | yes | 288 |
| parallax-depth-test | yes | yes | 157 |
| parallax-preprocessing-test | yes | yes | 223 |
| parallax-subpixel-test | yes | yes | 224 |
| parity-metric-test | yes | yes | 0 |
| peak-overlay-test | yes | yes | 56 |
| performance-baseline | yes | no | 823 |
| phase-discrimination-probe | yes | no | 249 |
| phase-map-probe | yes | no | 1287 |
| phase-vector-matching | yes | yes | 860 |
| preprocess-crop-bin-test | yes | yes | 228 |
| preprocessing-export-test | yes | yes | 207 |
| q-calibration-gate-test | yes | yes | 824 |
| real-acom-benchmark | yes | no | 184 |
| real-data-acceptance | yes | no | 205 |
| reduced-export-test | yes | yes | 326 |
| residency-sweep | yes | no | 350 |
| resident-cropped-view | yes | yes | 291 |
| result-presentation-test | yes | yes | 106 |
| rotation-null-probe | yes | no | 346 |
| scientific-bundle-test | yes | yes | 64 |
| sidecar-error-detail-test | yes | yes | 155 |
| sidecar-result-test | yes | yes | 475 |
| singleslice-ptychography-test | yes | yes | 361 |
| strain-frame-test | yes | yes | 346 |
| strain-test | yes | yes | 189 |
| thronsen-dataset | yes | no | 0 |
| training-dataset-campaign | yes | no | 1063 |
| two-spec-analysis-test | yes | yes | 1004 |
| vendor-reader-test | yes | yes | 54 |
| virtual-detector-residency | yes | yes | 656 |
| virtual-detector-test | yes | yes | 354 |
| volume-mmap-probe | yes | no | 64 |
| ws2-crystal-test | yes | yes | 260 |

Totals: 62 candidate harnesses; 62 in run-tests.sh; 46 in ci.yml (scientific array); 0 in neither.

## G. Marker counts

Method: `grep -ohE` for each marker as a whole word across all tracked `.swift`/`.metal` files under `mac4DSTEM/` (not `mac4DSTEMTests/` or `tools/`).

| marker | count | top files (count) |
|---|---|---|
| DEVIATION | 36 | OriginCalibration.swift (5), LoadSpecification.swift (3), PhaseVectorMatching.swift (3), OriginMeasure.metal (2), DM4Reader.swift (2) |
| TODO | 0 | - |
| FIXME | 0 | - |
| XXX | 0 | - |
| HACK | 0 | - |
| deprecated | 2 | ImagePanes.swift (1), DiffractionEmbedding.swift (1) |
| @available(*, deprecated | 0 | - |

### AppState

`mac4DSTEM/App/AppState.swift` declares `final class AppState` at line 88 (body runs to line 5461, 5374 lines). Counting `var`/`let` directly inside that class body only (excluding the several small sibling types declared earlier in the same file, and excluding anything nested inside a method/closure/computed-property body or a nested type within `AppState`):

| metric | value |
|---|---|
| AppState direct member vars/lets | 209 |
| extension AppState blocks | 6 |
| files holding an `extension AppState` | 6 (UI/WorkspaceRoute.swift, App/ActivityLog.swift, Support/ResultMetadata.swift, App/AppState+PhaseMapping.swift, App/AppState+DiffractionGroups.swift, Support/ResultExport.swift) |
| files referencing `AppState` (word match, mac4DSTEM/ + mac4DSTEMTests/ + tools/) | 101 |

## H. Metal struct parity

Method: every top-level `struct` in `mac4DSTEM/Shaders/*.metal`, matched by name against a same-named Swift struct. 4 of the 5 parameter structs are declared in `mac4DSTEM/Core/Compute/MetalEngine.swift`; the 5th (`ACOMParams`) has no same-named Swift struct — its byte-identical counterpart is named `ACOMMetalParams` and lives in `mac4DSTEM/Core/Crystal/OrientationMatcher.swift:389`. `VOut` (Colormaps.metal) is a vertex-stage output struct with no Swift-side counterpart (it never crosses the Swift/Metal boundary as a parameter buffer, so it is out of scope for this parity check).

| name | metal fields | swift fields | field-count match y/n |
|---|---|---|---|
| CubeDims | 4 (declared identically in DPStatistics.metal, VirtualMask.metal, VirtualDiffraction.metal) | 4 (MetalEngine.swift) | y |
| ApertureParams | 8 | 8 (MetalEngine.swift) | y |
| CoMParams | 7 | 7 (MetalEngine.swift) | y |
| OriginParams | 6 | 6 (MetalEngine.swift) | y |
| ACOMParams | 4 | 4 (as `ACOMMetalParams`, OrientationMatcher.swift:389, not MetalEngine.swift) | y |
| VOut | 2 (float4 position, float2 uv) | n/a (no Swift-side struct) | n/a |
