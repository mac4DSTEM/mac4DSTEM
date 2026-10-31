//
//  DiskDetectionCancellationTests.swift
//  The cooperative cancellation token, and a full disk-detection scan cancelled before it starts, cancelled after its first
//  tile, and left to finish. Moved from the cancellation-test harness into the unit suite.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// A cube held in memory, read through the app's `FourDArray` as a file would be.
private actor CancellationCubeSource: FourDDataSource {
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

private nonisolated final class TileCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class DiskDetectionCancellationTests: XCTestCase {
    private let qy = 16, qx = 16, ry = 128, rx = 1

    private func cube(rows: Int) -> [Float] {
        var cube = [Float](repeating: 0, count: rows * rx * qy * qx)
        for scan in 0..<rows { for y in 0..<qy { for x in 0..<qx {
            let dx = Float(x - (4 + scan % 8)), dy = Float(y - (4 + (scan / 8) % 8))
            cube[(scan * qy + y) * qx + x] = exp(-(dx * dx + dy * dy) / 5)
        } } }
        return cube
    }

    private func data(rows: Int) -> (FourDArray, DatasetDescriptor) {
        let descriptor = DatasetDescriptor(filePath: "synthetic", datasetPath: "/cube", shape: [rows, rx, qy, qx],
                                           dtypeDescription: "float32", chunkShape: nil)
        return (FourDArray(reader: CancellationCubeSource(descriptor: descriptor, cube: cube(rows: rows)), descriptor: descriptor),
                descriptor)
    }

    private var params: DiskDetectionParams {
        var params = DiskDetectionParams()
        params.sigmaCC = 0
        params.subpixel = .pixel
        params.edgeBoundary = 1
        params.minPeakSpacing = 0
        params.minRelativeIntensity = 0
        params.maxNumPeaks = 4
        return params
    }

    private func kernel() throws -> ProbeKernel {
        try XCTUnwrap(ProbeKernel.synthetic(radius: 2.5, width: 1.5, qy: qy, qx: qx))
    }

    func testTheTokenIsMonotonicIdempotentAndIndependentOfItsReplacement() {
        let basic = AnalysisCancellationToken()
        XCTAssertFalse(basic.isCancelled)
        basic.cancel()
        basic.cancel()
        XCTAssertTrue(basic.isCancelled)
        XCTAssertFalse(AnalysisCancellationToken().isCancelled, "an old cancellation never leaks into a new token")
    }

    func testACancelBeforeTheStartReturnsNoPartialResult() async throws {
        let (data, descriptor) = data(rows: ry)
        let token = AnalysisCancellationToken()
        token.cancel()
        let result = try await DiskDetection.detectAll(data: data, descriptor: descriptor, kernel: try kernel(), params: params,
                                                       maximumTileRows: 1, cancellation: token)
        XCTAssertNil(result)
    }

    /// One scan row per tile: the kit reports after each tile and polls the token before the next.
    func testACancelAfterTheFirstTileStopsTheScan() async throws {
        let (data, descriptor) = data(rows: ry)
        let token = AnalysisCancellationToken()
        let counter = TileCounter()
        let result = try await DiskDetection.detectAll(data: data, descriptor: descriptor, kernel: try kernel(), params: params,
                                                       maximumTileRows: 1, cancellation: token) { _ in
            if counter.increment() == 1 { token.cancel() }
        }
        XCTAssertNil(result, "mid-run cancellation returned a partial result")
        XCTAssertLessThan(counter.count, ry, "all rows completed after mid-run cancellation")
    }

    func testAnUncancelledScanReturnsEveryPositionAndLeavesItsTokenAlone() async throws {
        let (data, descriptor) = data(rows: 4)
        let token = AnalysisCancellationToken()
        let result = try await DiskDetection.detectAll(data: data, descriptor: descriptor, kernel: try kernel(), params: params,
                                                       maximumTileRows: 2, cancellation: token)
        XCTAssertEqual(result?.peaks.count, 4)
        XCTAssertFalse(token.isCancelled)
    }
}
