import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The origin gate's window pull (`OriginMaps.windowPullBoundPixels`, 2026-10-31) travels with the session: a refused
/// fit must stay refused after save and reopen, and after a crop or bin re-reference. A session saved before the value
/// existed reads it as unknown, which the gate does not refuse. Additive: the minimum-reader marker does not move.
final class OriginWindowPullSidecarTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginWindowPullSidecarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func calibration(pull: Double?) -> PixelCalibration {
        var c = PixelCalibration(rSize: 1.0, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: false)
        c.probeSemiangle = 4
        var maps = PixelOriginMaps(shape: [2, 2], fittedQX: [16, 16, 16, 16], fittedQY: [16, 16, 16, 16],
                                   measuredQX: [16, 16, 16, 16], measuredQY: [16, 16, 16, 16])
        maps.windowPullBoundPixels = pull
        c.originMaps = maps
        return c
    }

    private func roundTrip(_ saved: PixelCalibration, name: String) throws -> (PixelCalibration, URL) {
        let url = workDirectory.appendingPathComponent("\(name).mac4dstem.h5")
        try BraggVectorEMDWriter.mergeCalibration(saved, qWidth: 32, qHeight: 32, to: url,
                                                  loadSpecification: nil, replayRecord: nil)
        let snapshot = try BraggVectorEMDWriter.loadSession(from: url)
        return (try XCTUnwrap(snapshot.calibration), url)
    }

    /// Break it by not writing the attribute (or not reading it): the reopened maps read nil and the refused fit is
    /// trusted again.
    func testThePullSurvivesSaveAndReopenAndKeepsTheRefusal() throws {
        let (read, url) = try roundTrip(calibration(pull: 6.5), name: "refused")
        XCTAssertEqual(read.originMaps?.windowPullBoundPixels, 6.5)
        let translated = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: read, policy: .identity, view: nil,
            descriptor: DatasetDescriptor(filePath: "/tmp/x.h5", datasetPath: "/d", shape: [2, 2, 32, 32],
                                          dtypeDescription: "float32", chunkShape: nil)))
        XCTAssertEqual(translated.calibration.origin?.windowPullBoundPixels, 6.5)
        XCTAssertFalse(translated.calibration.originFitIsSane, "the reopened fit must stay refused")
        // A value that is not a finite, non-negative number reads as unknown, never as a refusal or a pass.
        try SidecarPatcher.write(.variableString("nan"), named: SessionSidecarFormat.originWindowPullAttribute, into: url)
        XCTAssertNil(try BraggVectorEMDWriter.loadSession(from: url).calibration?.originMaps?.windowPullBoundPixels)
    }

    /// A save whose calibration carries no pull, over a file that has one, leaves none: a stale value must not describe
    /// a different fit.
    func testAResaveWithoutThePullDropsTheOldOne() throws {
        let (_, url) = try roundTrip(calibration(pull: 6.5), name: "resave")
        try BraggVectorEMDWriter.mergeCalibration(calibration(pull: nil), qWidth: 32, qHeight: 32, to: url,
                                                  loadSpecification: nil, replayRecord: nil)
        XCTAssertNil(try BraggVectorEMDWriter.loadSession(from: url).calibration?.originMaps?.windowPullBoundPixels)
    }

    /// An older session (no attribute) reads unknown, and the gate falls back to the residual alone.
    func testASessionWithoutThePullReadsUnknown() throws {
        let (read, _) = try roundTrip(calibration(pull: nil), name: "older")
        XCTAssertNotNil(read.originMaps)
        XCTAssertNil(read.originMaps?.windowPullBoundPixels)
        let maps = try XCTUnwrap(read.originMaps?.appOriginMaps(width: 2, height: 2))
        var c = DSTEMCore.Calibration()
        c.origin = maps
        c.probeRadius = 4
        XCTAssertTrue(c.originFitIsSane)
    }
}
