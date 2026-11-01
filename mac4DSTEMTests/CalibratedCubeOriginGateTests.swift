import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The calibrated-cube export carries the origin gate's fields (window pull, beam stop, Friedel fallback residual and
/// method) beside the origin maps it writes, and the opener reads them back: a calibration the gate refused reopens
/// refused, not trusted. The two lengths are in the exported file's pixels (divided by the export bin, as
/// `CalibrationReReference` does). A file without them (every export written before) reads unknown, as before.
final class CalibratedCubeOriginGateTests: XCTestCase {

    private var descriptor: DatasetDescriptor { VoltageFixtureSource.descriptor }   // [2, 3, 4, 6]

    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("calcube-origin-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// A view-frame calibration with origin maps on the fixture's 2 x 3 scan, inside its 4 x 6 detector.
    private func calibration(pull: Double?, stop: Bool?, fallback: Double?, friedel: Bool?) -> PixelCalibration {
        var c = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
        c.probeSemiangle = 2
        var maps = PixelOriginMaps(shape: [2, 3], fittedQX: Array(repeating: 1.5, count: 6),
                                   fittedQY: Array(repeating: 2.5, count: 6),
                                   measuredQX: Array(repeating: 1.5, count: 6),
                                   measuredQY: Array(repeating: 2.5, count: 6))
        maps.windowPullBoundPixels = pull
        maps.beamStopCoversBeam = stop
        maps.friedelFallbackResidualPixels = fallback
        maps.measuredByFriedel = friedel
        c.originMaps = maps
        return c
    }

    private func exportAndReopen(_ calibration: PixelCalibration, qBin: Int) async throws -> PixelCalibration {
        let url = try scratchDirectory().appendingPathComponent("cube.h5")
        let options = CalibratedDataCubeExportOptions(scanY: 0..<descriptor.ry, scanX: 0..<descriptor.rx, qBin: qBin)
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: VoltageFixtureSource(voltage: nil), view: LoadView(fullExtentOf: descriptor),
            calibration: calibration, options: options, to: url)
        let reader = try H5Reader(path: url.path)
        _ = try await reader.discoverPrimaryDataset()   // pixelCalibration() needs the dataset path
        let calibration = await reader.pixelCalibration()
        return try XCTUnwrap(calibration)
    }

    /// Break it by not copying the fields onto the exported maps, or by not writing or not reading the attributes: the
    /// reopened maps read nil, and the refused origin is trusted again.
    func testARefusedOriginExportedAtBinTwoReopensRefused() async throws {
        let reopened = try await exportAndReopen(
            calibration(pull: 6.5, stop: true, fallback: 1.5, friedel: false), qBin: 2)
        let maps = try XCTUnwrap(reopened.originMaps)
        XCTAssertEqual(maps.windowPullBoundPixels, 3.25, "a length: divided by the export bin")
        XCTAssertEqual(maps.beamStopCoversBeam, true)
        XCTAssertEqual(maps.friedelFallbackResidualPixels, 0.75, "a length: divided by the export bin")
        XCTAssertEqual(maps.measuredByFriedel, false)
        var gate = DSTEMCore.Calibration()
        gate.origin = try XCTUnwrap(maps.appOriginMaps(width: 3, height: 2))
        gate.probeRadius = 1
        XCTAssertFalse(gate.originBeamStopIsAcceptable)
        XCTAssertFalse(gate.originWindowPullIsAcceptable)
        XCTAssertFalse(gate.originFitIsSane, "the reopened origin must stay refused")
    }

    /// A Friedel run at bin 1 keeps its method and lengths as they are.
    func testAFriedelRunKeepsItsMethodAtBinOne() async throws {
        let reopened = try await exportAndReopen(
            calibration(pull: 0.2, stop: false, fallback: nil, friedel: true), qBin: 1)
        let maps = try XCTUnwrap(reopened.originMaps)
        XCTAssertEqual(maps.windowPullBoundPixels, 0.2)
        XCTAssertEqual(maps.beamStopCoversBeam, false)
        XCTAssertNil(maps.friedelFallbackResidualPixels)
        XCTAssertEqual(maps.measuredByFriedel, true)
    }

    /// A calibration without the fields (and so every cube exported before they were written) reopens unknown, which
    /// the gate does not refuse.
    func testAnExportWithoutTheFieldsReopensUnknown() async throws {
        let reopened = try await exportAndReopen(
            calibration(pull: nil, stop: nil, fallback: nil, friedel: nil), qBin: 1)
        let maps = try XCTUnwrap(reopened.originMaps)
        XCTAssertNil(maps.windowPullBoundPixels)
        XCTAssertNil(maps.beamStopCoversBeam)
        XCTAssertNil(maps.friedelFallbackResidualPixels)
        XCTAssertNil(maps.measuredByFriedel)
        var gate = DSTEMCore.Calibration()
        gate.origin = try XCTUnwrap(maps.appOriginMaps(width: 3, height: 2))
        gate.probeRadius = 1
        XCTAssertTrue(gate.originFitIsSane)
    }
}
