//
//  TiledDiskDetectionErrorTests.swift
//  v2 S7 — error attribution in the out-of-core disk detection.
//
//  The defect: `detectAll(data:)` collapsed every failure into `nil`, and the
//  caller then reported all of them as "failed to initialize its FFT plan" —
//  so a NAS read error wore an FFT costume. The contract is now: nil means
//  cancelled and nothing else; every failure throws a `FullScanError` naming
//  what failed and, for tile reads, WHICH scan rows and the underlying error.
//

import XCTest
@testable import mac4DSTEM

/// A 4D source whose tile reads fail from a given scan row on — the shape of
/// a NAS that drops out mid-detection. Rows before `failFromRow` read as
/// zeros (no peaks, which is fine: these tests are about the error path).
private actor FailingTileSource: FourDDataSource {
    struct ReadFailure: LocalizedError {
        var errorDescription: String? { "synthetic I/O failure (the NAS unplugged)" }
    }

    let failFromRow: Int
    init(failFromRow: Int) { self.failFromRow = failFromRow }

    private let shape = [8, 4, 16, 16]
    private var qy: Int { shape[2] }
    private var qx: Int { shape[3] }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(
            filePath: "/synthetic/failing-source.h5", datasetPath: "/data",
            shape: shape, dtypeDescription: "float32", chunkShape: nil
        )
    }

    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        [Float](repeating: 0, count: qy * qx)
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        [Float](repeating: 0, count: view.descriptor.rx * qy * qx)
    }

    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        guard yRange.upperBound <= failFromRow else { throw ReadFailure() }
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: qy, detectorWidth: qx,
            pixels: [Float](repeating: 0,
                            count: yRange.count * view.descriptor.rx * qy * qx)
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class TiledDiskDetectionErrorTests: XCTestCase {

    private func makeData(failFromRow: Int) async throws
    -> (data: FourDArray, descriptor: DatasetDescriptor, kernel: ProbeKernel) {
        let source = FailingTileSource(failFromRow: failFromRow)
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        let kernel = try XCTUnwrap(
            ProbeKernel.synthetic(radius: 2, qy: descriptor.qy, qx: descriptor.qx)
        )
        return (data, descriptor, kernel)
    }

    /// Defaults sized for a real detector fail validation on the synthetic
    /// 16 px one (edge exclusion 20 > detector), which would turn every test
    /// here into an `invalidParameters` test. Pin a valid set explicitly.
    private var validParams: DiskDetectionParams {
        var params = DiskDetectionParams()
        params.edgeBoundary = 1
        params.minPeakSpacing = 2
        return params
    }

    /// The attribution itself: a read failure names the rows it failed on and
    /// carries the underlying error. Under the old contract this call
    /// returned nil and the test fails on "no error was thrown".
    func testTileReadFailureNamesTheRowsAndTheCause() async throws {
        let (data, descriptor, kernel) = try await makeData(failFromRow: 4)
        do {
            let result = try await DiskDetection.detectAll(
                data: data, descriptor: descriptor, kernel: kernel,
                params: validParams, maximumTileRows: 2
            )
            XCTFail("A failing tile read must throw, not return \(result == nil ? "nil" : "vectors")")
        } catch let error as DiskDetection.FullScanError {
            guard case .tileRead(let rows, let underlying) = error else {
                XCTFail("Wrong attribution: \(error)"); return
            }
            XCTAssertEqual(rows.lowerBound, 4,
                           "The failure must name the first UNREADABLE tile, not an earlier one")
            XCTAssertTrue("\(error)".contains("scan rows"),
                          "The message must say where: \(error)")
            XCTAssertTrue(underlying.localizedDescription.contains("NAS unplugged"),
                          "The underlying error must survive verbatim: \(underlying)")
            XCTAssertFalse("\(error)".contains("FFT"),
                           "An I/O failure must never wear the FFT costume again")
        }
    }

    /// nil still means cancelled — and ONLY cancelled.
    func testPreCancelledDetectionReturnsNilWithoutThrowing() async throws {
        let (data, descriptor, kernel) = try await makeData(failFromRow: 0)
        let token = AnalysisCancellationToken()
        token.cancel()
        let result = try await DiskDetection.detectAll(
            data: data, descriptor: descriptor, kernel: kernel,
            params: validParams, maximumTileRows: 2,
            cancellation: token
        )
        XCTAssertNil(result, "Cancellation is the one nil left in the contract")
    }

    /// Invalid parameters throw by name instead of returning nil — the tiled
    /// path validates against the same context as the resident one.
    func testInvalidParametersThrowByName() async throws {
        let (data, descriptor, kernel) = try await makeData(failFromRow: 8)
        var params = validParams
        params.edgeBoundary = -1
        do {
            _ = try await DiskDetection.detectAll(
                data: data, descriptor: descriptor, kernel: kernel,
                params: params, maximumTileRows: 2
            )
            XCTFail("Invalid parameters must refuse")
        } catch let error as DiskDetection.FullScanError {
            guard case .invalidParameters(let messages) = error else {
                XCTFail("Wrong attribution: \(error)"); return
            }
            XCTAssertFalse(messages.isEmpty, "The refusal must carry the validator's messages")
        }
    }

    /// The control for the whole family: a source that never fails detects to
    /// completion through the same path.
    func testHealthySourceStillDetects() async throws {
        let (data, descriptor, kernel) = try await makeData(failFromRow: 8)
        let vectors = try await DiskDetection.detectAll(
            data: data, descriptor: descriptor, kernel: kernel,
            params: validParams, maximumTileRows: 2
        )
        let unwrapped = try XCTUnwrap(vectors, "A healthy source must produce a result")
        XCTAssertEqual(unwrapped.peaks.count, descriptor.rx * descriptor.ry,
                       "One (possibly empty) peak list per scan position")
    }
}
