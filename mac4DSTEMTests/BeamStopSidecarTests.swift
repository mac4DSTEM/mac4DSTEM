import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The origin gate's beam-stop test (`OriginMaps.beamStopCoversBeam`, `friedelFallbackResidualPixels`) travels with the
/// session: a centre-of-mass origin refused under a stop stays refused after save and reopen. A session saved without
/// the values reads them as unknown. Additive: the minimum-reader marker does not move.
final class BeamStopSidecarTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeamStopSidecarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func calibration(stop: Bool?, fallback: Double?) -> PixelCalibration {
        var c = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
        c.probeSemiangle = 4
        var maps = PixelOriginMaps(shape: [2, 2], fittedQX: [16, 16, 16, 16], fittedQY: [16, 16, 16, 16],
                                   measuredQX: [16, 16, 16, 16], measuredQY: [16, 16, 16, 16])
        maps.beamStopCoversBeam = stop
        maps.friedelFallbackResidualPixels = fallback
        c.originMaps = maps
        return c
    }

    private func roundTrip(_ saved: PixelCalibration, name: String) throws -> PixelCalibration {
        let url = workDirectory.appendingPathComponent("\(name).mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(saved, qWidth: 32, qHeight: 32, to: url,
                                                  loadSpecification: nil, replayRecord: nil)
        return try XCTUnwrap(BraggVectorEMDWriter.loadSession(from: url).calibration)
    }

    /// Break it by not writing the attributes (or not reading them): the reopened maps read nil and the centre-of-mass
    /// origin under the stop is trusted again.
    func testTheStopSurvivesSaveAndReopenAndKeepsTheRefusal() throws {
        let read = try roundTrip(calibration(stop: true, fallback: 0.25), name: "stop")
        XCTAssertEqual(read.originMaps?.beamStopCoversBeam, true)
        XCTAssertEqual(read.originMaps?.friedelFallbackResidualPixels, 0.25)
        let translated = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: read, policy: .identity, view: nil,
            descriptor: DatasetDescriptor(filePath: "/tmp/x.h5", datasetPath: "/d", shape: [2, 2, 32, 32],
                                          dtypeDescription: "float32", chunkShape: nil)))
        XCTAssertEqual(translated.calibration.origin?.beamStopCoversBeam, true)
        XCTAssertFalse(translated.calibration.originFitIsSane, "the reopened fit must stay refused")
        XCTAssertTrue(translated.calibration.friedelFallbackIsTrusted)
    }

    /// The method travels too: a Friedel run reopened is still held to the 1 px limit. Break it by not writing (or not
    /// reading) `originMethodAttribute`: the reopened 1.5 px Friedel fit is trusted again.
    func testTheFriedelMethodSurvivesSaveAndReopen() throws {
        for friedel in [true, false] {
            var c = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
            c.probeSemiangle = 4
            var maps = PixelOriginMaps(shape: [1, 2], fittedQX: [16, 16], fittedQY: [16, 16],
                                       measuredQX: [16, 16], measuredQY: [17.5, 14.5])
            maps.measuredByFriedel = friedel
            c.originMaps = maps
            let read = try roundTrip(c, name: "method-\(friedel)")
            XCTAssertEqual(read.originMaps?.measuredByFriedel, friedel)
            let app = try XCTUnwrap(read.originMaps?.appOriginMaps(width: 2, height: 1))
            var calibration = DSTEMCore.Calibration()
            calibration.origin = app
            calibration.probeRadius = 4
            XCTAssertEqual(calibration.originFitIsSane, !friedel)
        }
        let older = try roundTrip(calibration(stop: nil, fallback: nil), name: "older-method")
        XCTAssertNil(older.originMaps?.measuredByFriedel)
    }

    /// No stop round-trips as no stop; a session without the values reads unknown, which the gate does not refuse.
    func testNoStopAndUnknownRoundTrip() throws {
        let clear = try roundTrip(calibration(stop: false, fallback: nil), name: "clear")
        XCTAssertEqual(clear.originMaps?.beamStopCoversBeam, false)
        XCTAssertNil(clear.originMaps?.friedelFallbackResidualPixels)
        let older = try roundTrip(calibration(stop: nil, fallback: nil), name: "older")
        XCTAssertNil(older.originMaps?.beamStopCoversBeam)
        let maps = try XCTUnwrap(older.originMaps?.appOriginMaps(width: 2, height: 2))
        var c = DSTEMCore.Calibration()
        c.origin = maps
        c.probeRadius = 4
        XCTAssertTrue(c.originFitIsSane)
    }
}
