import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Slot 4¾ lane D (pre-release review, 2026-10-02).
///
/// d1: a binned view's streaming tile is sized by the bytes the reader
/// ALLOCATES — the pre-bin read extent — not by the post-bin view. H5's
/// hyperslab and scan-fastest DM4's gather read the whole tile at the read
/// extent before `LoadView.binned` reduces it, so sizing from the binned
/// descriptor let the "bounded" transient grow by bin² (16× at bin 4).
@MainActor
final class ReviewTileBudgetTests: XCTestCase {

    /// The two bounds `FourDArray.scanTileRows` takes the minimum of.
    private var budget: Int {
        let gpu = max(1, Int(MetalEngine.shared.device.recommendedMaxWorkingSetSize) / 8)
        let host = max(1, Int(ProcessInfo.processInfo.physicalMemory) / 24)
        return min(gpu, host)
    }

    /// A source whose bin-1 row is 16 MiB and whose scan is far taller than
    /// any machine's tile, so no row count below is clamped at `ry`. Nothing
    /// is ever read: `scanTileRows` is arithmetic over the view.
    private func source(qy: Int = 256, qx: Int = 256) -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/nonexistent/review-tile-budget.h5", datasetPath: "/data",
                          shape: [1 << 20, 64, qy, qx], dtypeDescription: "uint16", chunkShape: nil)
    }

    private func rows(_ source: DatasetDescriptor, bin: Int, crop: AxisCrop? = nil,
                      maximumRows: Int? = nil) async throws -> (rows: Int, view: LoadView) {
        let view = try LoadView(source: source,
                                specification: LoadSpecification(detectorCrop: crop, detectorBin: bin))
        let array = FourDArray(reader: DemoFourDDataSource(), view: view)
        return (await array.scanTileRows(maximumRows: maximumRows), view)
    }

    /// Mutation: size `bytesPerRow` from the post-bin descriptor (HEAD's
    /// formula) — bin 4 then returns 16× the bin-1 rows and the pre-bin tile
    /// is 16× the budget.
    func testBinnedTileIsBudgetedAtTheReadExtent() async throws {
        let src = source()
        let one = try await rows(src, bin: 1)
        XCTAssertGreaterThan(one.rows, 1, "fixture must not sit at the ≥ 1 floor")
        XCTAssertLessThan(one.rows, src.ry, "fixture must not clamp at ry")
        for bin in [2, 4, 8] {
            let binned = try await rows(src, bin: bin)
            let readH = binned.view.readDetectorCrop?.height ?? src.qy
            let readW = binned.view.readDetectorCrop?.width ?? src.qx
            XCTAssertEqual(binned.rows, one.rows,
                           "bin \(bin) reads the same pre-bin extent as bin 1, so it gets the same rows")
            let preBinTileBytes = binned.rows * src.rx * readH * readW * MemoryLayout<Float>.stride
            XCTAssertLessThanOrEqual(preBinTileBytes, budget,
                                     "bin \(bin): the reader's pre-bin tile exceeds the per-tile budget")
        }
    }

    /// The edge remainder is trimmed before the read, so the budget uses the
    /// trimmed read extent: 250 → 248 at bin 4.
    func testRemainderTrimmedReadExtentSetsTheBudget() async throws {
        let src = source(qy: 250, qx: 250)
        let binned = try await rows(src, bin: 4)
        XCTAssertEqual(binned.view.readDetectorCrop?.height, 248)
        XCTAssertEqual(binned.rows, max(1, budget / (src.rx * 248 * 248 * MemoryLayout<Float>.stride)))
    }

    /// Bin 1 must be byte-identical to HEAD: the same rows, full extent and
    /// detector-cropped. Mutation: any bin² or read-extent term that also
    /// fires at bin 1 (e.g. reading `source.qy` when a bin-1 crop is set).
    func testBinOneRowsUnchanged() async throws {
        let src = source()
        let full = try await rows(src, bin: 1)
        XCTAssertEqual(full.rows, max(1, budget / (src.rx * src.qy * src.qx * MemoryLayout<Float>.stride)))
        let crop = AxisCrop(yOffset: 10, xOffset: 20, height: 100, width: 120)
        let cropped = try await rows(src, bin: 1, crop: crop)
        XCTAssertEqual(cropped.rows, max(1, budget / (src.rx * 100 * 120 * MemoryLayout<Float>.stride)))
    }

    /// `maximumRows` (parity tests' tiny tiles) is untouched by the budget.
    func testMaximumRowsStillWins() async throws {
        let binned = try await rows(source(), bin: 4, maximumRows: 3)
        XCTAssertEqual(binned.rows, 3)
    }

    // MARK: d4 — the keep-in-memory refusal names the bound that refused

    private let GB: UInt64 = 1_000_000_000

    /// The owner's M5 Pro (residency characterisation 2026-09-30: working set
    /// 55.7 GB, maxBufferLength 41.7 GB): a 45 GB view is refused by the
    /// single-buffer bound, and the caption says so with that bound's value.
    /// Mutation: `refusingBound` always returning `.workingSet(limitBytes)`
    /// (HEAD's caption named the working set for every refusal).
    func testRefusalBetweenTheBoundsNamesTheSingleBuffer() {
        let cube = Int(45 * GB), limit = 55_700_000_000 as UInt64, buffer = 41_700_000_000 as UInt64
        XCTAssertEqual(KeepInMemoryDecision.decide(cubeBytes: cube, limitBytes: limit,
                                                   maxBufferBytes: buffer, physicalMemory: 64 * GB), .refused)
        let bound = KeepInMemoryDecision.refusingBound(cubeBytes: cube, limitBytes: limit, maxBufferBytes: buffer)
        XCTAssertEqual(bound, .singleBuffer(buffer))
        let caption = KeepInMemoryDecision.refusalCaption(cubeBytes: cube, bound: bound)
        XCTAssertTrue(caption.contains("largest single GPU buffer"), caption)
        XCTAssertTrue(caption.contains(displayByteString(Int(buffer))), caption)
        XCTAssertFalse(caption.contains("working-set"), caption)
    }

    /// When the working set is the smaller ceiling it is the one named.
    /// Mutation: the comparison inverted (`maxBufferBytes > limitBytes`).
    func testRefusalBelowASmallerWorkingSetNamesTheWorkingSet() {
        let cube = Int(20 * GB), limit = 10 * GB, buffer = 16 * GB
        let bound = KeepInMemoryDecision.refusingBound(cubeBytes: cube, limitBytes: limit, maxBufferBytes: buffer)
        XCTAssertEqual(bound, .workingSet(limit))
        let caption = KeepInMemoryDecision.refusalCaption(cubeBytes: cube, bound: bound)
        XCTAssertTrue(caption.contains("GPU working-set limit"), caption)
        XCTAssertTrue(caption.contains(displayByteString(Int(limit))), caption)
    }

    /// `decide` refuses exactly when a bound is reported (one source of truth).
    /// Mutation: `refusingBound` using `>=` (the limit itself refused).
    func testRefusalAndBoundAgreeAtTheEdges() {
        let limit = 40 * GB, buffer = 1000 * GB
        for cube in [Int(limit) - 1, Int(limit), Int(limit) + 1] {
            let refused = KeepInMemoryDecision.decide(cubeBytes: cube, limitBytes: limit,
                                                      maxBufferBytes: buffer, physicalMemory: 64 * GB) == .refused
            let bound = KeepInMemoryDecision.refusingBound(cubeBytes: cube, limitBytes: limit, maxBufferBytes: buffer)
            XCTAssertEqual(refused, bound != nil, "cube \(cube)")
            XCTAssertEqual(refused, cube > Int(limit), "cube \(cube)")
        }
    }
}
