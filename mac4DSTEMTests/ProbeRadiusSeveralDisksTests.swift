import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// mac4DSTEM#203: on a spot pattern whose Bragg spots are as bright as the direct beam (saturated 8-bit SPED: the scan of
/// Zenodo 10.5281/zenodo.2652906), py4DSTEM's `get_probe_size` measures the summed area of all of them (15.39 px there, this
/// app 15.45 px, the spots about 2.5 px). The app stored that as the probe radius, "Measured in app", and the disk
/// detection then found nothing real. Now no radius is stored in that case and the user is asked for it.
///
/// The cube: a 4 × 4 scan of a 66 × 66 detector, every pattern the direct beam and eight spots (four at 19 px, four at
/// 27 px, the Al [001] pattern of that scan), all of radius 2.5 px and all at 255.
private actor SaturatedSpotPatternSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(filePath: "/synthetic/saturated-spots.h5", datasetPath: "/data",
                                              shape: [4, 4, 66, 66], dtypeDescription: "float32", chunkShape: nil)
    static let pattern: [Float] = {
        var dp = [Float](repeating: 30, count: 66 * 66)
        var centres: [(Double, Double)] = [(33, 33)]
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + 0.9
            centres.append((33 + 19 * cos(a), 33 + 19 * sin(a)))
            centres.append((33 + 27 * cos(a + .pi / 4), 33 + 27 * sin(a + .pi / 4)))
        }
        for (cx, cy) in centres { ProbeRadiusSeveralDisksTests.drawDisk(into: &dp, width: 66, cx: cx, cy: cy, radius: 2.5, value: 255) }
        return dp
    }()
    private let cube: [Float] = (0..<16).flatMap { _ in SaturatedSpotPatternSource.pattern }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { view.pattern(fromFullCube: cube, ry: ry, rx: rx) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] { view.scanRow(fromFullCube: cube, ry: ry) }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile { view.scanTile(fromFullCube: cube, yRange: yRange) }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class ProbeRadiusSeveralDisksTests: XCTestCase {
    static func drawDisk(into dp: inout [Float], width: Int, cx: Double, cy: Double, radius: Double, value: Float) {
        let height = dp.count / width
        for y in 0..<height { for x in 0..<width where hypot(Double(x) - cx, Double(y) - cy) <= radius { dp[y * width + x] = value } }
    }

    /// The count itself: one disk, a beam with weak spots, a ring, and the saturated spot pattern.
    func testTheCountOfComparableBrightDisks() {
        var one = [Float](repeating: 1, count: 64 * 64)
        Self.drawDisk(into: &one, width: 64, cx: 31.5, cy: 31.5, radius: 6, value: 100)
        XCTAssertEqual(OriginCalibration.comparableBrightDiskCount(dp: one, qy: 64, qx: 64), 1)

        var weak = one   // strong Bragg disks at 80 % of the beam: not at the beam's level, not counted
        for (x, y) in [(12.0, 12.0), (50, 12), (12, 50), (50, 50)] { Self.drawDisk(into: &weak, width: 64, cx: x, cy: y, radius: 6, value: 80) }
        XCTAssertEqual(OriginCalibration.comparableBrightDiskCount(dp: weak, qy: 64, qx: 64), 1)

        var speck = one  // a hot pixel pair as bright as the beam is not a disk
        speck[5 * 64 + 5] = 100; speck[5 * 64 + 6] = 100
        XCTAssertEqual(OriginCalibration.comparableBrightDiskCount(dp: speck, qy: 64, qx: 64), 1)

        var ring = [Float](repeating: 1, count: 64 * 64)   // a hollow beam is one blob
        Self.drawDisk(into: &ring, width: 64, cx: 31.5, cy: 31.5, radius: 10, value: 100)
        Self.drawDisk(into: &ring, width: 64, cx: 31.5, cy: 31.5, radius: 5, value: 1)
        XCTAssertEqual(OriginCalibration.comparableBrightDiskCount(dp: ring, qy: 64, qx: 64), 1)

        XCTAssertEqual(OriginCalibration.comparableBrightDiskCount(dp: SaturatedSpotPatternSource.pattern, qy: 66, qx: 66), 9)
        XCTAssertEqual(OriginCalibration.comparableBrightDiskCount(dp: [], qy: 0, qx: 0), 0)
    }

    /// The origin run on the saturated spot pattern: the port's number is the sum of nine disks, and no probe radius is stored.
    func testNoProbeRadiusIsStoredWhenThePatternHoldsSeveralDisksAsBrightAsTheBeam() async throws {
        let source = SaturatedSpotPatternSource()
        let d = try await source.discoverPrimaryDataset()
        let ported = try XCTUnwrap(OriginCalibration.probeSize(dp: SaturatedSpotPatternSource.pattern, qy: 66, qx: 66)).r
        XCTAssertGreaterThan(ported, 6, "fixture: get_probe_size must read the summed area here (one disk is 2.5 px), got \(ported)")
        let fit = try await OriginCalibration.tiledRun(data: FourDArray(reader: source, descriptor: d), descriptor: d, fitFunction: .plane)
        let result = try XCTUnwrap(fit)
        XCTAssertNil(result.meanProbeRadius, "the summed area of nine disks was stored as the probe radius")
    }

    /// What the user sees: the probe stays unset, never "Measured in app", and the status line says why and what to do.
    @MainActor
    func testTheAppLeavesTheProbeUnsetAndSaysWhatToDo() async throws {
        let source = SaturatedSpotPatternSource()
        let state = AppState()
        await state.activate(descriptor: try await source.discoverPrimaryDataset(), reader: source, runInitialAnalysis: false)
        await state.calibrateOrigin()
        XCTAssertNil(state.calibrationSession.calibration.probeRadius)
        XCTAssertNotEqual(state.calibrationSession.provenance.probe, .measuredInApp)
        let note = OriginCalibration.severalBrightDisksNote(count: 9)
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains(note) }, "the log does not say it; status: \(state.statusText)")
        XCTAssertLessThanOrEqual(note.count, 110, "the status line cuts a long note before its end")
        XCTAssertTrue(note.hasPrefix("Type the probe radius"), "the instruction comes first")
        // The row says it too, for as long as no radius is set (the status line is replaced by the next analysis).
        let row = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .originProbe })
        XCTAssertTrue(row.detail.contains("Probe: Not set (several disks are as bright as the beam"), row.detail)
        // A typed radius stands, and the next origin run does not touch it.
        await state.useProbeRadius(2.5)
        await state.calibrateOrigin()
        XCTAssertEqual(state.calibrationSession.calibration.probeRadius, 2.5)
        XCTAssertEqual(state.calibrationSession.provenance.probe, .manual)
        let after = try XCTUnwrap(state.calibrationSession.readiness.items.first { $0.kind == .originProbe })
        XCTAssertFalse(after.detail.contains("several disks"), after.detail)
    }
}
