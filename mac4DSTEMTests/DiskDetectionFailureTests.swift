//
//  DiskDetectionFailureTests.swift
//  A kit error in disk detection is visible, never read as vacuum (D019): the per-pattern diagnostics carry the failure, a full
//  scan counts the failed positions and the scan summary warns. Also pins the multicorr upsample-factor <= 2 fallback.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// A cube held in memory, for a full scan without a file.
private actor CubeFixtureSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let cube: [Float]
    init(descriptor: DatasetDescriptor, cube: [Float]) { self.descriptor = descriptor; self.cube = cube }
    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { view.pattern(fromFullCube: cube, ry: ry, rx: rx) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { view.scanRow(fromFullCube: cube, ry: ry) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile { view.scanTile(fromFullCube: cube, yRange: yRange) }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class DiskDetectionFailureTests: XCTestCase {
    private let q = 64

    private func params() -> DiskDetectionParams {
        var p = DiskKitFixture.base()
        p.minPeakSpacing = 8; p.edgeBoundary = 4
        return p
    }

    private func detector() throws -> DiskDetector {
        try XCTUnwrap(DiskDetector(kernel: DiskKitFixture.kernel(q: q)))
    }

    /// A refused pattern says so. The kit's refusals reachable through this API are the invalid options (validated up front for a
    /// preview and a scan, so an unvalidated caller is the one that meets them); `nonFiniteRefinement` shares the same catch but
    /// was not reachable with finite Float input in any pattern tried (constant, delta, scaled 1e-40...1e38, phase correlation).
    /// Mutation: restore `try? ... ?? zero funnel` in `detectWithDiagnostics` -> detectionFailure is nil -> red.
    func testAThrownKitErrorIsRecordedInTheDiagnostics() throws {
        let det = try detector()
        let pattern = DiskKitFixture.pattern(q: q, seed: 1)
        var bad = params()
        bad.sigmaCC = -1
        let failed = det.detectWithDiagnostics(pattern: pattern, params: bad)
        XCTAssertTrue(failed.peaks.isEmpty)
        XCTAssertEqual(failed.diagnostics.acceptedCount, 0)
        XCTAssertTrue(try XCTUnwrap(failed.diagnostics.detectionFailure).contains("correlationSigma"), "the kit's reason is kept")
        let good = det.detectWithDiagnostics(pattern: pattern, params: params())
        XCTAssertNil(good.diagnostics.detectionFailure)
        XCTAssertFalse(good.peaks.isEmpty)
    }

    /// A clean full scan reports no failed position; vectors with failed positions make the scan summary warn first, naming the
    /// count, and the warning is not there for a clean run. Mutation: drop `failedPositionCount` from `warnings` -> red.
    func testAFullScanCountsFailedPositionsAndTheSummaryWarns() async throws {
        let good = DiskKitFixture.pattern(q: q, seed: 2)
        let cube = good + good
        let descriptor = DatasetDescriptor(filePath: "t", datasetPath: "t", shape: [1, 2, q, q], dtypeDescription: "float32", chunkShape: nil)
        let data = FourDArray(reader: CubeFixtureSource(descriptor: descriptor, cube: cube), descriptor: descriptor)
        let kernel = try DiskKitFixture.kernel(q: q)
        let scanned = try await DiskDetection.detectAll(data: data, descriptor: descriptor, kernel: kernel, params: params())
        let vectors = try XCTUnwrap(scanned)
        XCTAssertEqual(vectors.failedPatternCount, 0)
        let clean = DiskDetectionScanSummary(vectors: vectors, maximumPeaks: 70, parameters: params())
        XCTAssertEqual(clean.failedPositionCount, 0)
        XCTAssertFalse(clean.warnings.contains { $0.contains("Detection failed") })

        let failedVectors = BraggVectors(scanWidth: 2, scanHeight: 2, peaks: [[], [], [], []], failedPatternCount: 2)
        let summary = DiskDetectionScanSummary(vectors: failedVectors, maximumPeaks: 70, parameters: params())
        XCTAssertEqual(summary.failedPositionCount, 2)
        XCTAssertTrue(try XCTUnwrap(summary.warnings.first).contains("Detection failed at 2 of 4"))
    }

    /// The checked correlation reports the kit's refusal; the plain one keeps its zero-surface contract for validated callers.
    func testCorrelationCheckedThrowsWhereCorrelationReturnsZeros() throws {
        let det = try detector()
        var bad = params()
        bad.sigmaCC = -1
        let pattern = DiskKitFixture.pattern(q: q, seed: 4)
        XCTAssertThrowsError(try pattern.withUnsafeBufferPointer { try det.correlationChecked(pattern: $0.baseAddress!, params: bad) })
        let plain = pattern.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: bad) }
        XCTAssertEqual(plain.raw.max(), 0)
        let ok = try pattern.withUnsafeBufferPointer { try det.correlationChecked(pattern: $0.baseAddress!, params: params()) }
        XCTAssertGreaterThan(ok.raw.max() ?? 0, 0)
    }

    /// DEVIATION pinned: multicorr with an upsample factor of 2 or less is not refused by the facade (the kit would refuse it);
    /// it runs the parabolic refinement, so its peaks equal the 'Parabolic' ones exactly and differ from a real multicorr run.
    /// `validationIssues` refuses the combination for the UI and full scans. Mutation: pass `.multicorr` through at factor 2 ->
    /// the kit throws, detectionFailure is set and the peaks are empty -> red.
    func testMulticorrAtUpsampleFactorTwoRunsTheParabolicRefinement() throws {
        let det = try detector()
        let pattern = DiskKitFixture.pattern(q: q, seed: 5)
        var parabolic = params(); parabolic.subpixel = .poly
        var low = params(); low.subpixel = .multicorr; low.upsampleFactor = 2
        var real = params(); real.subpixel = .multicorr; real.upsampleFactor = 16
        let expected = det.detectWithDiagnostics(pattern: pattern, params: parabolic)
        let actual = det.detectWithDiagnostics(pattern: pattern, params: low)
        XCTAssertNil(actual.diagnostics.detectionFailure)
        XCTAssertFalse(actual.peaks.isEmpty)
        XCTAssertEqual(actual.peaks.map(\.x), expected.peaks.map(\.x))
        XCTAssertEqual(actual.peaks.map(\.y), expected.peaks.map(\.y))
        XCTAssertEqual(actual.peaks.map(\.intensity), expected.peaks.map(\.intensity))
        let full = det.detectWithDiagnostics(pattern: pattern, params: real)
        XCTAssertNotEqual(full.peaks.map(\.x), expected.peaks.map(\.x), "a real multicorr run moves the peaks off the parabolic positions")
        let context = DiskDetectionContext(qy: q, qx: q, probeRadius: 5)
        XCTAssertTrue(low.validationIssues(in: context).contains { $0.severity == .error }, "the UI path refuses factor <= 2")
    }
}
