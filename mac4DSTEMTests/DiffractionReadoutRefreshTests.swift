import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The Diffraction readout's q must follow a Q-scale change under a pointer that has not moved (UI audit 2026-10-14: "q goes stale
/// after a Q-scale change until the pointer moves"). The q itself is `DiffractionPointerReadout`'s, unchanged and pinned by
/// `DiffractionPointerReadoutTests` (tier 1); this pins WHEN it is recomputed. Tier 2.
@MainActor
final class DiffractionReadoutRefreshTests: XCTestCase {
    typealias Readout = DiffractionPointerReadout

    private func calibration(q: Double?, units: String? = "nm⁻¹") -> Calibration {
        var c = Calibration()
        c.recordedOriginX = 64
        c.recordedOriginY = 64
        c.qPixelSize = q
        c.qPixelUnits = units
        return c
    }

    private func basis(_ calibration: Calibration, milliradians: Bool = false, mradPerPixel: Float? = nil) -> Readout.Basis {
        Readout.Basis(calibration: calibration, detectorQX: 128, detectorQY: 128, scanX: 0, scanY: 0, scanWidth: 1, scanHeight: 1,
                      singlePosition: true, apertureCentre: (10, 10), milliradians: milliradians, mradPerPixel: mradPerPixel)
    }

    private let pattern = DiffractionPattern(qy: 128, qx: 128, pixels: [Float](repeating: 1, count: 128 * 128))

    func testAQScaleChangeUnderARestingPointerIsReadWithoutAPointerEvent() throws {
        let model = DiffractionCursorModel()
        model.pixel = .init(x: 74, y: 64)                       // 10 px right of the origin
        model.refresh(pattern: pattern, basis: basis(calibration(q: 0.02)))
        XCTAssertEqual(try XCTUnwrap(model.sample?.reciprocal).value, 0.2, accuracy: 1e-9)

        // The Q scale is edited; the pointer does not move.
        model.refresh(pattern: pattern, basis: basis(calibration(q: 0.05)))
        XCTAssertEqual(try XCTUnwrap(model.sample?.reciprocal).value, 0.5, accuracy: 1e-9, "the old q (0.2) is stale")

        // Un-calibrated: the q goes away rather than lingering.
        model.refresh(pattern: pattern, basis: basis(calibration(q: nil, units: nil)))
        XCTAssertNil(model.sample?.reciprocal)
        XCTAssertNotNil(model.sample, "the pixel and its value stay")
    }

    func testNoPointerNothingToRefresh() {
        let model = DiffractionCursorModel()
        model.refresh(pattern: pattern, basis: basis(calibration(q: 0.02)))
        XCTAssertNil(model.sample)
    }

    func testTheBasisKeyChangesWithEverythingQDependsOnAndOnlyThen() {
        let base = basis(calibration(q: 0.02)).key
        XCTAssertEqual(base, basis(calibration(q: 0.02)).key, "same inputs, same key: no spurious refresh")
        XCTAssertNotEqual(base, basis(calibration(q: 0.03)).key, "Q scale")
        XCTAssertNotEqual(base, basis(calibration(q: 0.02, units: "Å⁻¹")).key, "Q unit")
        XCTAssertNotEqual(base, basis(calibration(q: 0.02), milliradians: true, mradPerPixel: 0.1).key, "mrad mode")
        var moved = calibration(q: 0.02); moved.recordedOriginX = 65
        XCTAssertNotEqual(base, basis(moved).key, "beam centre")
        var ellipse = calibration(q: 0.02); ellipse.ellipseA = 1.1; ellipse.ellipseB = 1.0; ellipse.ellipseTheta = 0.3
        XCTAssertNotEqual(base, basis(ellipse).key, "detector ellipse")
    }
}
