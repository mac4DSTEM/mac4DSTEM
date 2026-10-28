//
//  EllipseFitAnnulusTests.swift
//  Tier 2 (the overlay draws the inputs of a fit; it adds no number): the annulus Fit Ellipse samples, on the pattern.
//  UI audit 2026-10-14, "Fit annulus never drawn". What must hold is that the circles are the fit's own: the same centre, in the
//  same pixel frame, with the same radii, so the pixels between them are the pixels the fit reads.
//

import XCTest
import DSTEMCore
import DiffractoGeometry
// swiftlint:disable duplicate_imports
// swiftformat:disable:next duplicateImports
import struct DiffractoGeometry.DiffractionPattern   // the fit's three-field pattern, over DSTEMCore's display type
// swiftlint:enable duplicate_imports
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class EllipseFitAnnulusTests: XCTestCase {
    func testTheCirclesAreTheRadiiAroundThePixelCentreInViewPoints() throws {
        // 80 x 64 detector in a 160 x 128 box: 2 view points per pixel on both axes.
        let m = try XCTUnwrap(EllipseFitAnnulus.metrics(
            centerX: 30, centerY: 34, inner: 15, outer: 25, patternWidth: 80, patternHeight: 64,
            box: CGSize(width: 160, height: 128)))
        XCTAssertEqual(m.center, CGPoint(x: 61, y: 69), "pixel (30, 34)'s centre: (30.5, 34.5) pixels x 2")
        XCTAssertEqual(m.inner, 30)
        XCTAssertEqual(m.outer, 50)
    }

    func testNoCirclesForRadiiThatAreNotRadii() {
        let box = CGSize(width: 100, height: 100)
        func metrics(_ inner: Double, _ outer: Double) -> EllipseFitAnnulus.Metrics? {
            EllipseFitAnnulus.metrics(centerX: 5, centerY: 5, inner: inner, outer: outer,
                                      patternWidth: 10, patternHeight: 10, box: box)
        }
        XCTAssertNil(metrics(-1, 5))
        XCTAssertNil(metrics(.nan, 5))
        XCTAssertNil(metrics(2, .infinity))
        XCTAssertNil(metrics(0, 0))
        XCTAssertNotNil(metrics(0, 3), "an inner radius of 0 is a disc, still a fit region")
    }

    /// A ring of radius 20 at column 30, row 34 of an 80 x 64 detector, fitted the way `AppState.calibrateEllipse` fits it (the
    /// aperture centre is (x 30, y 34); the fit takes row, then column). The circles drawn for that aperture must hold the ring,
    /// and the fit's centre must be the drawn centre: a swapped axis or an off-by-half-pixel frame moves one of them.
    func testTheDrawnAnnulusHoldsTheRingTheFitFindsInTheSameFrame() throws {
        let width = 80, height = 64
        var pixels = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for col in 0..<width {
                let r = hypot(Double(col) - 30, Double(row) - 34)
                pixels[row * width + col] = Float(exp(-pow((r - 20) / 1.5, 2)))
            }
        }
        let pattern = DiffractionPattern(width: width, height: height, pixels: pixels)
        let aperture = Aperture(centerX: 30, centerY: 34, inner: 0, outer: 10)
        let fit = try EllipseCalibration.fit1D(
            pattern: pattern,
            centerQX: Double(aperture.centerY), centerQY: Double(aperture.centerX),   // AppState.calibrateEllipse's own lines
            innerRadius: 15, outerRadius: 25)
        XCTAssertEqual(fit.centerQX, 34, accuracy: 0.3, "the fit found the ring's row")
        XCTAssertEqual(fit.centerQY, 30, accuracy: 0.3, "and its column")

        let box = CGSize(width: 160, height: 128)
        let m = try XCTUnwrap(EllipseFitAnnulus.metrics(
            centerX: aperture.centerX, centerY: aperture.centerY, inner: 15, outer: 25,
            patternWidth: width, patternHeight: height, box: box))
        // The fit's centre, drawn, is the annulus centre.
        let fitCentre = PeakOverlayGeometry.center(x: Float(fit.centerQY), y: Float(fit.centerQX),
                                                   patternWidth: width, patternHeight: height, box: box)
        XCTAssertEqual(fitCentre.x, m.center.x, accuracy: 0.6)
        XCTAssertEqual(fitCentre.y, m.center.y, accuracy: 0.6)
        // The ring (radius 20 px = 40 points) lies between the circles (30 and 50 points).
        XCTAssertGreaterThan(CGFloat(fit.a) * 2, m.inner)
        XCTAssertLessThan(CGFloat(fit.a) * 2, m.outer)
        XCTAssertGreaterThan(CGFloat(fit.b) * 2, m.inner)
        XCTAssertLessThan(CGFloat(fit.b) * 2, m.outer)
        // Pixel by pixel: a pixel the ring lights (value > 0.5) is a pixel centre between the drawn circles.
        for row in 0..<height {
            for col in 0..<width where pixels[row * width + col] > 0.5 {
                let p = PeakOverlayGeometry.center(x: Float(col), y: Float(row),
                                                   patternWidth: width, patternHeight: height, box: box)
                let d = hypot(p.x - m.center.x, p.y - m.center.y)
                XCTAssertTrue(d > m.inner && d <= m.outer, "pixel (\(col), \(row)) at \(d) points")
            }
        }
    }

    /// The overlay's claim "the fit is centred on the aperture" is about code in another file; this keeps the two together. If
    /// `calibrateEllipse` ever takes another centre, the overlay must follow it, and this fails first.
    func testTheFitStillTakesTheApertureCentre() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("mac4DSTEM/App/AppState+Calibration.swift")
        guard let text = try? String(contentsOf: source, encoding: .utf8) else {
            throw XCTSkip("source tree not beside the tests: \(source.path)")
        }
        XCTAssertTrue(text.contains("let centerQX = Double(aperture.centerY)"), "the fit's row centre")
        XCTAssertTrue(text.contains("let centerQY = Double(aperture.centerX)"), "the fit's column centre")
    }

    func testItIsDrawnInPrepareWhileTheSectionIsOpenAndTheInspectorIsThere() {
        typealias A = EllipseFitAnnulus
        XCTAssertTrue(A.isShown(workspace: .prepare, sectionIsOpen: true, inspectorIsVisible: true))
        XCTAssertFalse(A.isShown(workspace: .prepare, sectionIsOpen: false, inspectorIsVisible: true), "section closed")
        XCTAssertFalse(A.isShown(workspace: .prepare, sectionIsOpen: true, inspectorIsVisible: false), "inspector hidden")
        for room in WorkspaceArea.allCases where room != .prepare {
            XCTAssertFalse(A.isShown(workspace: room, sectionIsOpen: true, inspectorIsVisible: true),
                           "\(room): the stored 'open' must not draw in another room")
        }
    }

    func testTheSectionKeyIsTheOneThePrepareInspectorStoresItsStateUnder() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("mac4DSTEM/UI/PrepareSettings.swift")
        guard let text = try? String(contentsOf: source, encoding: .utf8) else {
            throw XCTSkip("source tree not beside the tests: \(source.path)")
        }
        XCTAssertTrue(text.contains("@SceneStorage(EllipseFitAnnulus.sectionStorageKey)"),
                      "PrepareSettings and the pane must read one key")
        XCTAssertEqual(EllipseFitAnnulus.sectionStorageKey, "prepare.settings.ellipseCorrection.isExpanded",
                       "unchanged since before the conversion: a returning window keeps what it remembered")
    }

    func testTheSpokenValueNamesTheRadiiAndTheCentre() {
        let text = EllipseFitAnnulus.spoken(centerX: 30, centerY: 34.5, inner: 15, outer: 25)
        XCTAssertTrue(text.contains("Inner radius 15 pixels") && text.contains("outer radius 25 pixels"))
        XCTAssertTrue(text.contains("x 30") && text.contains("y 34"), text)
    }
}
