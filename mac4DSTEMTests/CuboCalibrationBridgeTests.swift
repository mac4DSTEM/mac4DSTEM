// ROADMAP task 5, first step: the app's calibration as CuboKit's. Pins the frame convention of the bridge and, for a detector bin, where
// the kit's py4DSTEM-faithful rule and the app's own re-reference agree (pixel sizes) and where the app is stricter (it moves the
// origin, the probe radius and the ellipse with the pixels; the kit leaves them, as py4DSTEM does and its open items say).

import XCTest
import CuboCore
import DSTEMCore
@testable import mac4DSTEM

final class CuboCalibrationBridgeTests: XCTestCase {
    private func calibration() -> DSTEMCore.Calibration {
        var c = DSTEMCore.Calibration()
        // 4 rows x 3 columns scan; origin x (column) 4, 5, 6 and y (row) 5.25 ... 8.25 as in CalibrationReReferenceTests.
        var x: [Float] = [], y: [Float] = []
        for row in 0..<4 { for column in 0..<3 { x.append(Float(4 + column)); y.append(Float(5 + row) + 0.25) } }
        c.origin = OriginMaps(width: 3, height: 4, measuredX: x, measuredY: y, fittedX: x, fittedY: y)
        c.qPixelSize = 0.021; c.qPixelUnits = "Å⁻¹"
        c.rPixelSize = 0.5; c.rPixelUnits = "nm"
        c.rotationRad = 0.1; c.transposeQR = true
        c.probeRadius = 4.5
        c.ellipseA = 1.03; c.ellipseB = 0.97; c.ellipseTheta = 0.4
        return c
    }

    func testTheSharedFieldsCrossWithTheFrameConvention() throws {
        let kit = calibration().cuboCalibration()
        XCTAssertEqual(kit.detectorPixelSize, 0.021); XCTAssertEqual(kit.detectorUnits, .inverseAngstroms)
        XCTAssertEqual(kit.scanPixelSize, 0.5); XCTAssertEqual(kit.scanUnits, "nm")
        // The app's x is a detector column and y a row: scan position (row 2, column 1) holds x = 5, y = 7.25.
        let origin = try XCTUnwrap(kit.origin(row: 2, column: 1))
        XCTAssertEqual(origin.column, 5, accuracy: 1e-6); XCTAssertEqual(origin.row, 7.25, accuracy: 1e-6)
        XCTAssertEqual(kit.qrRotationRadians ?? 0, 0.1, accuracy: 1e-6); XCTAssertTrue(kit.qrFlip)
        XCTAssertEqual(kit.probeSemiangle, 4.5)
        XCTAssertEqual(kit.ellipse, EllipseCalibration(a: 1.03, b: 0.97, theta: 0.4))
    }

    func testAMeanOnlyOriginBecomesTheKitsMean() throws {
        var c = DSTEMCore.Calibration()
        c.origin = OriginMaps(width: 2, height: 1, measuredX: nil, measuredY: nil, fittedX: [10, 12], fittedY: [20, 22])
        let kit = c.cuboCalibration()
        XCTAssertEqual(try XCTUnwrap(kit.origin(row: 0, column: 1)).column, 12, accuracy: 1e-6)
    }

    /// Detector bin 2: the pixel sizes follow the same rule in both; the app additionally moves what is in detector pixels.
    func testADetectorBinAgreesOnPixelSizesAndTheAppAlsoMovesTheOrigin() throws {
        let source = DatasetDescriptor(filePath: "/tmp/s.h5", datasetPath: "/data", shape: [4, 3, 10, 8], dtypeDescription: "float32", chunkShape: nil)
        let view = try LoadView(source: source, specification: LoadSpecification(detectorBin: 2))
        let before = calibration()
        let app = CalibrationReReference.apply(view, to: before, provenance: CalibrationProvenance(), apertureCenter: nil).calibration
        let kit = try before.cuboCalibration().afterBinningDetector(by: 2)
        XCTAssertEqual(app.qPixelSize ?? 0, kit.detectorPixelSize, accuracy: 1e-12, "Q pixel size times the bin, in both")
        XCTAssertEqual(app.rPixelSize ?? 0, kit.scanPixelSize, "a detector bin leaves the R pixel size alone, in both")
        // Where they differ on purpose: the kit leaves the origin (py4DSTEM does), the app moves it with the pixels.
        let kitOrigin = try XCTUnwrap(kit.origin(row: 0, column: 0)), appBefore = try XCTUnwrap(before.origin)
        XCTAssertEqual(kitOrigin.column, Double(appBefore.fittedX[0]), accuracy: 1e-6, "the kit's origin stays in the old pixels")
        XCTAssertLessThan(Double(try XCTUnwrap(app.origin).fittedX[0]), Double(appBefore.fittedX[0]), "the app's origin is in binned pixels")
        XCTAssertEqual(Double(app.probeRadius ?? 0), 4.5 / 2, accuracy: 0.5, "the app halves the probe radius with the pixels (binned length)")
    }
}
