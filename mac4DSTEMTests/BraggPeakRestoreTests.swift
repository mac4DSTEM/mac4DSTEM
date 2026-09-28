//
//  BraggPeakRestoreTests.swift
//  Restoring the detected Bragg disks from a session sidecar on open
//  (docs/archive/v4/bragg-restore-registration-2026-09-28.md). Three layers,
//  each broken on purpose before it was trusted:
//    - the file round trip (the read half `writePeakGrid` never had),
//    - the adoption checks, driven through a REAL `AppState.activate` — the
//      wiring, not just the pure decision — one refusal per test, each set up
//      so that ONLY the check under test can refuse,
//    - the staleness hole: with no probe kernel `currentReplaySignature(.disks)`
//      was nil and nil reads `.current`, so restored peaks looked valid merely
//      because nothing could compare them.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

// MARK: - Shared fixtures

private enum PeakRestoreFixture {
    static let classical = DetectorClass.classical.provenanceID

    /// Peaks with x ≠ y everywhere (so a dropped axis swap cannot pass),
    /// non-decimal Float values (so a precision loss cannot pass) and empty
    /// positions (so a mis-indexed empty cell cannot pass).
    static func vectors(
        scanWidth: Int, scanHeight: Int, provenance: [String: String]
    ) -> BraggVectors {
        var peaks = [[BraggPeak]](repeating: [], count: scanWidth * scanHeight)
        for y in 0..<scanHeight {
            for x in 0..<scanWidth {
                let index = y * scanWidth + x
                if (x + y) % 3 == 0 { continue }          // empty position
                peaks[index] = (0..<((x + y) % 4 + 1)).map { k in
                    BraggPeak(
                        x: 3.1 + Float(x) * 0.37 + Float(k) * 1.9,
                        y: 7.7 + Float(y) * 0.53 + Float(k) * 0.1,
                        intensity: 0.1 + Float(index) * 0.013 + Float(k)
                    )
                }
            }
        }
        return BraggVectors(scanWidth: scanWidth, scanHeight: scanHeight,
                            peaks: peaks, detectionProvenance: provenance)
    }

    static func params() -> DiskDetectionParams { DiskDetectionParams() }

    static func kernel(qy: Int, qx: Int) throws -> ProbeKernel {
        try XCTUnwrap(ProbeKernel.synthetic(radius: 4, qy: qy, qx: qx))
    }

    static func provenance(qy: Int, qx: Int) throws -> [String: String] {
        params().provenance(kernel: try kernel(qy: qy, qx: qx), qy: qy, qx: qx)
    }

    /// What a real `runDiskDetection` records for the same run.
    static func stepParameters(qy: Int, qx: Int) throws -> [String: String] {
        var parameters = params().replayParameters(kernel: try kernel(qy: qy, qx: qx))
        parameters["detector_class"] = classical
        return parameters
    }

    static func record(_ parameters: [String: String]?) -> SessionReplayRecord {
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector",
                      parameters: ["shape": "Circle", "center_x": "16", "center_y": "16",
                                   "inner": "0", "outer": "6"],
                      at: Date(timeIntervalSince1970: 1))
        if let parameters {
            record.record(kind: "disk_detection", parameters: parameters,
                          at: Date(timeIntervalSince1970: 1_790_000_000))
        }
        return record
    }
}

// MARK: - The file round trip

final class BraggPeakGridRoundTripTests: XCTestCase {

    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BraggPeakGrid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("grid.mac4dstem.h5")
    }

    func testEveryPositionComesBackBitForBitWithEmptiesAndTheAxisSwapUndone() throws {
        let provenance = try PeakRestoreFixture.provenance(qy: 24, qx: 40)
        let written = PeakRestoreFixture.vectors(scanWidth: 7, scanHeight: 5, provenance: provenance)
        XCTAssertTrue(written.peaks.contains { $0.isEmpty }, "The fixture must include empty positions")
        let url = try temporaryURL()
        try BraggVectorEMDWriter.write(
            vectors: written, qWidth: 40, qHeight: 24, calibration: PixelCalibration(), to: url
        )

        let grid = try XCTUnwrap(try BraggVectorEMDWriter.loadPeakGrid(from: url))
        XCTAssertEqual(grid.vectors.scanWidth, 7)
        XCTAssertEqual(grid.vectors.scanHeight, 5)
        XCTAssertEqual(grid.detectorWidth, 40)
        XCTAssertEqual(grid.detectorHeight, 24)
        XCTAssertEqual(grid.vectors.detectionProvenance, provenance)
        XCTAssertEqual(grid.vectors.peaks.count, written.peaks.count)
        for index in written.peaks.indices {
            let want = written.peaks[index], got = grid.vectors.peaks[index]
            XCTAssertEqual(got.count, want.count, "position \(index)")
            for (a, b) in zip(want, got) {
                // Bit patterns, not tolerances: the claim is exact.
                XCTAssertEqual(a.x.bitPattern, b.x.bitPattern, "x at position \(index)")
                XCTAssertEqual(a.y.bitPattern, b.y.bitPattern, "y at position \(index)")
                XCTAssertEqual(a.intensity.bitPattern, b.intensity.bitPattern,
                               "intensity at position \(index)")
            }
        }
    }

    func testASidecarWithoutPeaksReadsAsNoGrid() throws {
        let url = try temporaryURL()
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 16, qHeight: 16, to: url
        )
        XCTAssertNil(try BraggVectorEMDWriter.loadPeakGrid(from: url))
        XCTAssertNil(try BraggVectorEMDWriter.loadPeakGrid(
            from: url.deletingLastPathComponent().appendingPathComponent("absent.h5")))
    }

    func testAPeakGridSurvivesACalibrationRewriteOfTheSidecar() throws {
        // The app saves calibration long after it saved peaks; the writer
        // copies the braggvectors object across. The restore must read what
        // that copy carries.
        let provenance = try PeakRestoreFixture.provenance(qy: 24, qx: 24)
        let written = PeakRestoreFixture.vectors(scanWidth: 4, scanHeight: 4, provenance: provenance)
        let url = try temporaryURL()
        try BraggVectorEMDWriter.write(
            vectors: written, qWidth: 24, qHeight: 24, calibration: PixelCalibration(), to: url
        )
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 24, qHeight: 24, to: url,
            replayRecord: PeakRestoreFixture.record(nil)
        )
        let grid = try XCTUnwrap(try BraggVectorEMDWriter.loadPeakGrid(from: url))
        XCTAssertEqual(grid.vectors.totalPeakCount, written.totalPeakCount)
        XCTAssertEqual(grid.vectors.detectionProvenance, provenance)
    }
}

// MARK: - Provenance ↔ recorded step

final class DiskDetectionRecordMatchTests: XCTestCase {

    func testTheProvenanceOfARunMatchesTheStepThatRunRecords() throws {
        let provenance = try PeakRestoreFixture.provenance(qy: 32, qx: 32)
        let step = try PeakRestoreFixture.stepParameters(qy: 32, qx: 32)
        XCTAssertEqual(DiskDetectionRecordMatch.mismatches(
            provenance: provenance, stepParameters: step), [],
            "Both vocabularies come from the same DiskDetectionParams; the table must map every key")
    }

    func testAChangedSettingIsNamedAndAnEmptyProvenanceMatchesNothing() throws {
        let provenance = try PeakRestoreFixture.provenance(qy: 32, qx: 32)
        var step = try PeakRestoreFixture.stepParameters(qy: 32, qx: 32)
        step["edge_boundary"] = "21"
        XCTAssertEqual(DiskDetectionRecordMatch.mismatches(
            provenance: provenance, stepParameters: step), ["edge_boundary"])
        XCTAssertFalse(DiskDetectionRecordMatch.mismatches(
            provenance: [:],
            stepParameters: try PeakRestoreFixture.stepParameters(qy: 32, qx: 32)).isEmpty)
    }
}

// MARK: - Adoption on open (real AppState.activate)

@MainActor
final class BraggPeakRestoreOnOpenTests: XCTestCase {

    /// A scan crop that fits the demo cube; two of the same size at different
    /// offsets are how the load-specification check is isolated.
    private let cropA = LoadSpecification(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 6))
    private let cropB = LoadSpecification(scanCrop: AxisCrop(yOffset: 2, xOffset: 3, height: 6, width: 6))

    private struct Opened {
        var state: AppState
        var record: SessionReplayRecord
        var written: BraggVectors?
    }

    /// Write a sidecar, open the demo cube through the real `activate`.
    /// `loaded` is the view opened; `recorded` the specification the sidecar
    /// was written under; the peak grid is `gridScan` (default: the loaded
    /// view's scan) on a `gridDetector` detector.
    private func open(
        loaded: LoadSpecification = .fullExtent,
        recorded: LoadSpecification = .fullExtent,
        gridScan: (width: Int, height: Int)? = nil,
        gridDetectorDelta: Int = 0,
        stepParameters: [String: String]?? = nil,
        provenance: [String: String]? = nil
    ) async throws -> Opened {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let locator = SessionSidecarLocator(defaults: defaults)
        let source = DemoFourDDataSource()
        let sourceDescriptor = try await source.discoverPrimaryDataset()
        let view = try LoadView(source: sourceDescriptor, specification: loaded)
        let d = view.descriptor

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BraggPeakRestore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        locator.adopt(sidecar, for: sourceDescriptor)

        let scan = gridScan ?? (width: d.rx, height: d.ry)
        let recordedProvenance = try provenance
            ?? PeakRestoreFixture.provenance(qy: d.qy, qx: d.qx)
        var vectors: BraggVectors?
        if scan.width > 0 {
            vectors = PeakRestoreFixture.vectors(
                scanWidth: scan.width, scanHeight: scan.height, provenance: recordedProvenance
            )
            try BraggVectorEMDWriter.write(
                vectors: try XCTUnwrap(vectors), qWidth: d.qx + gridDetectorDelta, qHeight: d.qy,
                calibration: PixelCalibration(), to: sidecar
            )
        }
        let step: [String: String]?
        switch stepParameters {
        case .none: step = try PeakRestoreFixture.stepParameters(qy: d.qy, qx: d.qx)
        case .some(let explicit): step = explicit
        }
        let record = PeakRestoreFixture.record(step)
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: d.qx, qHeight: d.qy, to: sidecar,
            loadSpecification: recorded, replayRecord: record
        )

        let state = AppState(sessionSidecar: locator)
        state.beginDatasetLoading("Reopening source…")
        await state.activate(descriptor: sourceDescriptor, reader: source,
                             specification: loaded, runInitialAnalysis: false)
        state.finishDatasetLoading()
        return Opened(state: state, record: record, written: vectors)
    }

    func testEveryCheckPassingAdoptsTheStoredPeaksBitForBitAndSaysSo() async throws {
        let opened = try await open()
        let state = opened.state
        let restored = try XCTUnwrap(state.resultPresentation.braggVectors,
                                     "Every check passes: the peaks must be adopted")
        let written = try XCTUnwrap(opened.written)
        XCTAssertEqual(restored.totalPeakCount, written.totalPeakCount)
        XCTAssertEqual(state.resultPresentation.braggPeakCount, written.totalPeakCount)
        for index in written.peaks.indices {
            XCTAssertEqual(restored.peaks[index].map(\.x.bitPattern), written.peaks[index].map(\.x.bitPattern))
            XCTAssertEqual(restored.peaks[index].map(\.y.bitPattern), written.peaks[index].map(\.y.bitPattern))
        }
        XCTAssertTrue(state.statusText.hasPrefix("Disks restored from the session — \(written.totalPeakCount) peaks (detected "),
                      "Status was: \(state.statusText)")
        XCTAssertTrue(state.hasCurrentBraggVectors,
                      "Restored peaks that the recorded step vouches for are current")
    }

    func testRestoringLeavesTheReplayRecordAndTheLearnedDetectorRecordAlone() async throws {
        let opened = try await open()
        let state = opened.state
        XCTAssertNotNil(state.resultPresentation.braggVectors)
        XCTAssertEqual(state.replay.record, opened.record,
                       "Restoring a product must not record or rewrite a recipe step")
        XCTAssertNil(state.learnedDetection.lastClassical,
                     "The learned-detector record is for a completed run, not a restore")
        XCTAssertNil(state.learnedDetection.lastLearned)
        XCTAssertFalse(state.learnedDetection.canCompare)
    }

    func testAScanShapeMismatchLeavesThePeaksNil() async throws {
        let full = try await DemoFourDDataSource().discoverPrimaryDataset()
        let opened = try await open(gridScan: (width: full.rx - 1, height: full.ry))
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
        XCTAssertNil(opened.state.resultPresentation.braggPeakCount)
        XCTAssertTrue(opened.state.statusText.contains("Stored disks not used — they cover a"),
                      "Status was: \(opened.state.statusText)")
    }

    func testADetectorShapeMismatchLeavesThePeaksNil() async throws {
        let opened = try await open(gridDetectorDelta: 2)
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
        XCTAssertTrue(opened.state.statusText.contains("detector, not"),
                      "Status was: \(opened.state.statusText)")
    }

    func testADifferentLoadSpecificationLeavesThePeaksNil() async throws {
        // Same scan and detector shape on both views, so only the
        // specification check can refuse.
        let opened = try await open(loaded: cropA, recorded: cropB)
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
        XCTAssertTrue(opened.state.statusText.contains("different view"),
                      "Status was: \(opened.state.statusText)")
    }

    func testAMissingDiskDetectionStepLeavesThePeaksNil() async throws {
        let opened = try await open(stepParameters: .some(nil))
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
        XCTAssertTrue(opened.state.statusText.contains("no disk-detection step"),
                      "Status was: \(opened.state.statusText)")
    }

    func testProvenanceThatDisagreesWithTheStepLeavesThePeaksNil() async throws {
        let full = try await DemoFourDDataSource().discoverPrimaryDataset()
        var step = try PeakRestoreFixture.stepParameters(qy: full.qy, qx: full.qx)
        step["edge_boundary"] = "21"
        let opened = try await open(stepParameters: .some(step))
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
        XCTAssertTrue(opened.state.statusText.contains("edge_boundary"),
                      "Status was: \(opened.state.statusText)")
    }

    func testPeaksWithoutProvenanceAreNotAdopted() async throws {
        // A grid with no provenance cannot be vouched for by any step.
        let opened = try await open(provenance: [:])
        XCTAssertNil(opened.state.resultPresentation.braggVectors)
    }

    // MARK: - The staleness hole

    func testRestoredPeaksAreJudgedAgainstTheRecordedStepWhileNoKernelExists() async throws {
        let opened = try await open()
        let state = opened.state
        XCTAssertNil(state.probeKernel, "A fresh open has no kernel — the case that read `.current`")
        XCTAssertNotNil(state.resultPresentation.braggVectors)
        XCTAssertFalse(state.diskDetectionSettingsAreStale)

        // The recorded step moves on (another detection would do this): the
        // restored peaks are no longer what the recipe says produced them.
        var moved = try PeakRestoreFixture.stepParameters(qy: state.descriptor!.qy, qx: state.descriptor!.qx)
        moved["min_peak_spacing"] = "61.0"
        state.replay.adopt(PeakRestoreFixture.record(moved),
                           recordedOn: ReplayParameterFrame.of(nil))
        XCTAssertTrue(state.diskDetectionSettingsAreStale,
                      "With no kernel the verdict must still compare — it used to be `.current`")
        XCTAssertFalse(state.hasCurrentBraggVectors)

        // The step is gone entirely.
        state.replay.adopt(PeakRestoreFixture.record(nil), recordedOn: ReplayParameterFrame.of(nil))
        XCTAssertTrue(state.diskDetectionSettingsAreStale)
    }

    func testAKernelBuiltWithOtherSettingsMarksRestoredPeaksStale() async throws {
        let opened = try await open()
        let state = opened.state
        let d = try XCTUnwrap(state.descriptor)
        XCTAssertFalse(state.diskDetectionSettingsAreStale)

        // The same settings and kernel class: still current. (A fresh open
        // seeds the controls with the detector-adapted defaults, which need
        // not be the settings the stored run used; setting the run's own
        // settings back is what "the same settings" means here.)
        state.diskDetection.diskParams = PeakRestoreFixture.params()
        state.probeKernel = try PeakRestoreFixture.kernel(qy: d.qy, qx: d.qx)
        XCTAssertFalse(state.diskDetectionSettingsAreStale)

        // Other settings: the existing rule marks them stale.
        state.diskDetection.diskParams.edgeBoundary += 1
        XCTAssertTrue(state.diskDetectionSettingsAreStale)
    }

    func testTheNoKernelSignatureIsWhatThePeaksRecordAndNothingWithoutPeaks() throws {
        let d = (qy: 32, qx: 32)
        let provenance = try PeakRestoreFixture.provenance(qy: d.qy, qx: d.qx)
        let step = try PeakRestoreFixture.stepParameters(qy: d.qy, qx: d.qx)
        func signature(_ provenance: [String: String]?) -> [String: String]? {
            ProductWorkflow.currentReplaySignature(
                for: .disks, virtualDetectorShape: "annulus",
                aperture: Aperture(centerX: 0, centerY: 0, inner: 0, outer: 1),
                dpcOriginReference: "global center",
                diskKernel: nil, diskParams: DiskDetectionParams(),
                learnedDetectorParameters: [:], strainSignature: [:], acomSignature: nil,
                diskPeaksProvenance: provenance)
        }
        let recorded = SessionReplayRecord.Step(kind: "disk_detection", parameters: step, recorded: Date())
        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: recorded, currentSignature: signature(provenance), hasProduct: true),
            .current)
        var other = provenance
        other[DiskDetectionParameterID.edgeBoundary.rawValue] = "99"
        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: recorded, currentSignature: signature(other), hasProduct: true),
            .stale(changedKeys: ["edge_boundary"]))
        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: nil, currentSignature: signature(provenance), hasProduct: true),
            .stale(changedKeys: []))
        // Peaks that cannot say what made them (no provenance, or a key
        // missing) must read as changed — never as matching by silence.
        var partial = provenance
        partial.removeValue(forKey: "kernel_mode")
        XCTAssertEqual(ProductWorkflow.stalenessVerdict(
            recordedStep: recorded, currentSignature: signature(partial), hasProduct: true),
            .stale(changedKeys: ["kernel_mode"]))
        guard case .stale(let unverifiable) = ProductWorkflow.stalenessVerdict(
            recordedStep: recorded, currentSignature: signature([:]), hasProduct: true) else {
            return XCTFail("Peaks with no provenance must not read as current")
        }
        XCTAssertEqual(unverifiable.count, DiskDetectionRecordMatch.requiredKeys.count)
        XCTAssertNil(signature(nil), "No peaks and no kernel: nothing to compare, as before")
    }
}
