//
//  DiffractionPointerReadoutTests.swift
//  Tier 1 (a new number on screen). Registration: docs/archive/v5/diffraction-readout-2026-10-14.md, predictions P1-P7.
//  The oracles are independent of the code under test: the ellipse that maps onto a circle of radius b (P3), the app's own
//  `BraggVectors.calibrated(with:referenceOrigin:)` (P4), `PeakOverlayGeometry.center` and `RealSpacePointerPolicy` (P1).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class DiffractionPointerReadoutTests: XCTestCase {
    typealias Readout = DiffractionPointerReadout

    // MARK: Fixtures

    /// A calibration whose origin is the file's recorded beam centre (a measured one) and whose Q scale is physical.
    private func calibration(
        origin: (x: Float, y: Float) = (64, 64), q: Double? = 0.02, units: String? = "nm⁻¹",
        ellipse: (a: Double, b: Double, theta: Double)? = nil
    ) -> Calibration {
        var c = Calibration()
        c.recordedOriginX = origin.x
        c.recordedOriginY = origin.y
        c.qPixelSize = q
        c.qPixelUnits = units
        if let ellipse {
            c.ellipseA = ellipse.a; c.ellipseB = ellipse.b; c.ellipseTheta = ellipse.theta
        }
        return c
    }

    private func basis(
        _ calibration: Calibration, scan: (x: Int, y: Int) = (0, 0), scanSize: (w: Int, h: Int) = (1, 1),
        single: Bool = true, aperture: (x: Float, y: Float)? = (10, 10),
        milliradians: Bool = false, mradPerPixel: Float? = nil
    ) -> Readout.Basis {
        Readout.Basis(
            calibration: calibration, detectorQX: 128, detectorQY: 128,
            scanX: scan.x, scanY: scan.y, scanWidth: scanSize.w, scanHeight: scanSize.h,
            singlePosition: single, apertureCentre: aperture,
            milliradians: milliradians, mradPerPixel: mradPerPixel)
    }

    private let pattern128 = DiffractionPattern(qy: 128, qx: 128, pixels: [Float](repeating: 1, count: 128 * 128))

    private func q(_ x: Int, _ y: Int, _ b: Readout.Basis) throws -> Double {
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: x, y: y), in: pattern128, basis: b))
        return try XCTUnwrap(sample.reciprocal, "no q at (\(x), \(y))").value
    }

    // MARK: P1 pixel

    func testEveryCellCentreAndTopLeftCornerReadsItsOwnPixel() {
        let box = CGSize(width: 140, height: 100)     // 7 x 5 detector: 20 x 20 pt cells
        for y in 0..<5 {
            for x in 0..<7 {
                let centre = CGPoint(x: (CGFloat(x) + 0.5) * 20, y: (CGFloat(y) + 0.5) * 20)
                let corner = CGPoint(x: CGFloat(x) * 20, y: CGFloat(y) * 20)
                let inside = CGPoint(x: CGFloat(x + 1) * 20 - 0.001, y: CGFloat(y + 1) * 20 - 0.001)
                for point in [centre, corner, inside] {
                    XCTAssertEqual(Readout.pixel(at: point, patternWidth: 7, patternHeight: 5, box: box),
                                   .init(x: x, y: y), "\(point)")
                }
            }
        }
    }

    func testOutsideTheBoxAndTheFarEdgeReadNothing() {
        let box = CGSize(width: 140, height: 100)
        for point in [CGPoint(x: 140, y: 50), CGPoint(x: 10, y: 100), CGPoint(x: -0.1, y: 5), CGPoint(x: 5, y: -0.1)] {
            XCTAssertNil(Readout.pixel(at: point, patternWidth: 7, patternHeight: 5, box: box), "\(point)")
        }
        XCTAssertNil(Readout.pixel(at: .zero, patternWidth: 0, patternHeight: 5, box: box))
    }

    func testAPeakDrawnAtItsPixelCentreReadsBackAsThatPixel() {
        let box = CGSize(width: 140, height: 100)
        for y in 0..<5 {
            for x in 0..<7 {
                let drawn = PeakOverlayGeometry.center(x: Float(x), y: Float(y), patternWidth: 7, patternHeight: 5, box: box)
                XCTAssertEqual(Readout.pixel(at: drawn, patternWidth: 7, patternHeight: 5, box: box), .init(x: x, y: y))
            }
        }
    }

    func testSameFloorAsTheRealSpaceReadout() {
        let box = CGSize(width: 130, height: 90)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let point = CGPoint(x: CGFloat.random(in: 0..<130, using: &rng), y: CGFloat.random(in: 0..<90, using: &rng))
            let scan = RealSpacePointerPolicy.scanPosition(at: point, imageWidth: 13, imageHeight: 9, box: box)
            XCTAssertEqual(Readout.pixel(at: point, patternWidth: 13, patternHeight: 9, box: box),
                           .init(x: scan.x, y: scan.y), "\(point)")
        }
    }

    // MARK: P2 value

    func testTheValueIsTheStoredPixelAndNotItsTransposeOrItsNeighbour() throws {
        let pixels = (0..<35).map { Float($0) * 1.5 + 1 }          // 7 columns x 5 rows, every value distinct
        let pattern = DiffractionPattern(qy: 5, qx: 7, pixels: pixels)
        let b = basis(calibration())
        for (x, y) in [(3, 2), (6, 0), (0, 4), (6, 4)] {
            let sample = try XCTUnwrap(Readout.sample(at: .init(x: x, y: y), in: pattern, basis: b))
            XCTAssertEqual(sample.value, pixels[y * 7 + x], "(\(x), \(y))")
        }
        XCTAssertNil(Readout.sample(at: .init(x: 7, y: 0), in: pattern, basis: b), "one past the last column")
        XCTAssertNil(Readout.sample(at: .init(x: 0, y: 5), in: pattern, basis: b), "one past the last row")
    }

    func testANonFinitePixelReadsNoValueButKeepsItsPlace() throws {
        var pixels = [Float](repeating: 2, count: 4)
        pixels[3] = .nan
        let pattern = DiffractionPattern(qy: 2, qx: 2, pixels: pixels)
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: 1, y: 1), in: pattern, basis: basis(calibration())))
        XCTAssertNil(sample.value)
        XCTAssertEqual(sample.lines(locale: Locale(identifier: "en_US_POSIX")).minimal, "Qx 1 Qy 1 I \u{2014}")
    }

    // MARK: P3 the ellipse oracle

    /// a = 10 along the columns, b = 5: the lattice points on x²/100 + y²/25 = 1 map onto the circle of radius b.
    func testPixelsOnTheEllipseAllReadTheMinorSemiAxis() throws {
        let b = basis(calibration(ellipse: (a: 10, b: 5, theta: .pi / 2)))
        for (dx, dy) in [(10, 0), (0, 5), (6, 4), (8, 3), (-6, 4), (-10, 0), (8, -3)] {
            XCTAssertEqual(try q(64 + dx, 64 + dy, b), 5 * 0.02, accuracy: 1e-6, "(\(dx), \(dy))")
        }
    }

    func testWithoutAnEllipseTheDistanceIsPlainEuclidean() throws {
        let b = basis(calibration())
        XCTAssertEqual(try q(74, 64, b), 10 * 0.02, accuracy: 1e-6)
        XCTAssertEqual(try q(64, 69, b), 5 * 0.02, accuracy: 1e-6)
        XCTAssertEqual(try q(70, 68, b), (52.0).squareRoot() * 0.02, accuracy: 1e-6)
        XCTAssertEqual(try q(64, 64, b), 0, accuracy: 1e-9, "the origin pixel is q = 0")
    }

    // MARK: P4 against the app's own pipeline

    func testAgreesWithBraggVectorsCalibratedForAPeakAtThatPixel() throws {
        var c = calibration(ellipse: (a: 1.1, b: 1.0, theta: 0.7))
        // Two scan positions with different fitted origins, so the per-position rule is exercised too.
        c.recordedOriginX = nil; c.recordedOriginY = nil
        c.origin = OriginMaps(width: 2, height: 1, measuredX: nil, measuredY: nil,
                              fittedX: [60, 66], fittedY: [60, 62])
        let mean = try XCTUnwrap(c.meanOrigin)
        for scan in 0..<2 {
            var peaks: [[BraggPeak]] = [[], []]
            let raw: [(Int, Int)] = [(80, 70), (50, 90), (64, 40), (100, 100)]
            peaks[scan] = raw.map { BraggPeak(x: Float($0.0), y: Float($0.1), intensity: 1) }
            let calibrated = BraggVectors(scanWidth: 2, scanHeight: 1, peaks: peaks)
                .calibrated(with: c, referenceOrigin: mean)
            let b = basis(c, scan: (scan, 0), scanSize: (2, 1), single: true)
            for (i, p) in raw.enumerated() {
                let peak = calibrated.peaks[scan][i]
                let expected = 0.02 * Double(hypot(peak.x - mean.x, peak.y - mean.y))
                XCTAssertEqual(try q(p.0, p.1, b), expected, accuracy: 1e-5 * max(1, expected), "scan \(scan) pixel \(p)")
            }
        }
    }

    // MARK: P5 the gates

    func testNoQWithoutAPhysicalQScaleButThePixelAndValueRemain() throws {
        for c in [calibration(q: nil, units: nil), calibration(q: 0.02, units: "px"), calibration(q: 0.02, units: nil),
                  calibration(q: 0, units: "nm⁻¹")] {
            let sample = try XCTUnwrap(Readout.sample(at: .init(x: 70, y: 64), in: pattern128, basis: basis(c)))
            XCTAssertNil(sample.reciprocal)
            XCTAssertEqual(sample.pixel, .init(x: 70, y: 64))
            XCTAssertEqual(sample.value, 1)
        }
        XCTAssertEqual(try q(70, 64, basis(calibration())), 6 * 0.02, accuracy: 1e-6, "the same pixel with a valid scale")
    }

    func testNoQFromAStandInOrigin() throws {
        var apertureOnly = calibration()
        apertureOnly.recordedOriginX = nil; apertureOnly.recordedOriginY = nil
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: 70, y: 64), in: pattern128,
                                                  basis: basis(apertureOnly, aperture: (64, 64))))
        XCTAssertNil(sample.reciprocal, "an aperture centre is a placement, not a measured beam centre")
        let middle = try XCTUnwrap(Readout.sample(at: .init(x: 70, y: 64), in: pattern128,
                                                  basis: basis(apertureOnly, aperture: nil)))
        XCTAssertNil(middle.reciprocal, "the detector's middle is a stand-in")
    }

    func testNoQWhenTheOriginFitExceedsTheProbeRadius() throws {
        var c = calibration()
        c.recordedOriginX = nil; c.recordedOriginY = nil
        c.probeRadius = 5
        c.origin = OriginMaps(width: 1, height: 1, measuredX: [84], measuredY: [64], fittedX: [64], fittedY: [64])
        XCTAssertGreaterThan(try XCTUnwrap(c.origin?.rmsResidual), 5)
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: 70, y: 64), in: pattern128, basis: basis(c)))
        XCTAssertNil(sample.reciprocal)
        c.probeRadius = 30
        XCTAssertNotNil(try XCTUnwrap(Readout.sample(at: .init(x: 70, y: 64), in: pattern128, basis: basis(c))).reciprocal)
    }

    // MARK: P6 per-position origin

    func testTheSinglePositionPatternUsesItsOwnOriginAndTheOthersUseTheMean() throws {
        var c = calibration()
        c.recordedOriginX = nil; c.recordedOriginY = nil
        c.origin = OriginMaps(width: 2, height: 1, measuredX: nil, measuredY: nil,
                              fittedX: [60, 66], fittedY: [60, 62])                // mean (63, 61)
        // Pixel (70, 62): from (66, 62) it is 4 px; from the mean (63, 61) hypot(7, 1); from (60, 60) hypot(10, 2).
        let own = try q(70, 62, basis(c, scan: (1, 0), scanSize: (2, 1), single: true))
        XCTAssertEqual(own, 4 * 0.02, accuracy: 1e-6)
        let first = try q(70, 62, basis(c, scan: (0, 0), scanSize: (2, 1), single: true))
        XCTAssertEqual(first, 0.02 * (104.0).squareRoot(), accuracy: 1e-6)
        let mean = try q(70, 62, basis(c, scan: (1, 0), scanSize: (2, 1), single: false))
        XCTAssertEqual(mean, 0.02 * (50.0).squareRoot(), accuracy: 1e-6, "mean, max and ROI-sum patterns use the mean origin")
    }

    // MARK: P7 mrad

    func testInMilliradianModeQIsTheAngleInMrad() throws {
        let b = basis(calibration(), milliradians: true, mradPerPixel: 0.5)
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: 74, y: 64), in: pattern128, basis: b))
        let reciprocal = try XCTUnwrap(sample.reciprocal)
        XCTAssertEqual(reciprocal.value, 10 * 0.5, accuracy: 1e-6)
        XCTAssertEqual(reciprocal.scale.unit, "mrad")
        XCTAssertTrue(reciprocal.scale.isAngle)
        XCTAssertEqual(sample.lines(locale: Locale(identifier: "en_US_POSIX")).full, "Qx 74 \u{00B7} Qy 64 \u{00B7} I 1 \u{00B7} \u{03B8} 5 mrad",
                       "an angle is a theta, a reciprocal distance a q")
        // Without the mrad scale (no voltage) the pane falls back to the calibrated unit, as the footer scale bar does.
        let fallback = try XCTUnwrap(Readout.sample(at: .init(x: 74, y: 64), in: pattern128,
                                                    basis: basis(calibration(), milliradians: true, mradPerPixel: nil)))
        XCTAssertEqual(fallback.reciprocal?.scale.unit, "nm⁻¹")
        XCTAssertEqual(fallback.reciprocal?.scale.isAngle, false)
    }

    // MARK: The session's side of the Basis (S1: the pane's wiring, as a pure function)

    private let descriptor = DatasetDescriptor(                // Ry 3, Rx 4, Qy 5, Qx 6
        filePath: "/x.h5", datasetPath: "/d", shape: [3, 4, 5, 6], dtypeDescription: "float32", chunkShape: nil)

    private func session(
        _ mode: PatternDisplayMode = .current, _ shape: RegionShape = .point, _ unit: PatternScaleUnit = .reciprocal,
        mrad: Float? = nil, scan: ScanPos = ScanPos(x: 2, y: 1), calibration: Calibration = Calibration()
    ) -> Readout.Basis {
        .make(calibration: calibration, descriptor: descriptor, selectedScan: scan, patternMode: mode, regionShape: shape,
              aperture: Aperture(centerX: 11, centerY: 22, inner: 0, outer: 5), scaleUnit: unit, mradPerPixel: mrad)
    }

    func testTheBasisTakesTheDescriptorsExtentsInTheirOrderAndTheAperturesCentreAsXThenY() {
        let b = session()
        XCTAssertEqual([b.scanWidth, b.scanHeight], [4, 3], "Rx, then Ry")
        XCTAssertEqual([b.detectorQX, b.detectorQY], [6, 5], "Qx (columns), then Qy (rows)")
        XCTAssertEqual([b.scanX, b.scanY], [2, 1])
        XCTAssertEqual(b.apertureCentre?.x, 11, "the column")
        XCTAssertEqual(b.apertureCentre?.y, 22, "the row")
    }

    func testOnlyTheCurrentPatternOfAPointSelectionIsTheSinglePosition() {
        for mode in PatternDisplayMode.allCases {
            for shape in RegionShape.allCases {
                XCTAssertEqual(session(mode, shape).singlePosition, mode == .current && shape == .point, "\(mode) \(shape)")
            }
        }
    }

    func testOnlyTheMilliradianModeAsksForMilliradians() {
        XCTAssertFalse(session(.current, .point, .reciprocal, mrad: 0.5).milliradians)
        XCTAssertTrue(session(.current, .point, .milliradians, mrad: 0.5).milliradians)
        XCTAssertEqual(session(.current, .point, .milliradians, mrad: 0.5).mradPerPixel, 0.5)
        XCTAssertNil(session(.current, .point, .milliradians, mrad: nil).mradPerPixel)
    }

    /// The wiring through to a number: a 4 x 3 scan with a different fitted origin at each position. Swapping Rx and Ry, or
    /// treating a mean pattern as the single position, moves q.
    func testThePaneFeedsTheReadoutThePositionsOwnOriginAndTheMeanOtherwise() throws {
        var c = calibration()
        c.recordedOriginX = nil; c.recordedOriginY = nil
        let x: [Float] = (0..<12).map { Float($0) }                 // origin x = 0 ... 11 by scan index
        c.origin = OriginMaps(width: 4, height: 3, measuredX: nil, measuredY: nil, fittedX: x, fittedY: [Float](repeating: 2, count: 12))
        let pattern = DiffractionPattern(qy: 5, qx: 6, pixels: [Float](repeating: 1, count: 30))
        let pixel = Readout.Pixel(x: 5, y: 2)
        // Scan (2, 1) is index 1 * 4 + 2 = 6: origin (6, 2), so the pixel (5, 2) is 1 px away. The mean origin is (5.5, 2): 0.5 px.
        let own = try XCTUnwrap(Readout.sample(at: pixel, in: pattern, basis: session(calibration: c))?.reciprocal)
        XCTAssertEqual(own.value, 1 * 0.02, accuracy: 1e-6)
        let mean = try XCTUnwrap(Readout.sample(at: pixel, in: pattern, basis: session(.mean, calibration: c))?.reciprocal)
        XCTAssertEqual(mean.value, 0.5 * 0.02, accuracy: 1e-6)
        let region = try XCTUnwrap(Readout.sample(at: pixel, in: pattern, basis: session(.current, .circle, calibration: c))?.reciprocal)
        XCTAssertEqual(region.value, 0.5 * 0.02, accuracy: 1e-6, "a summed region is not one position")
    }

    // MARK: Text

    /// F1 (tier-1 refuter, 2026-10-14): I is the STORED value. It was formatted at four significant digits, which rounds integer
    /// digits too: a stored 12345 read "I 12340" and a saturated 16-bit 65535 read "I 65540". All integer digits are shown, and
    /// a fraction at the seven significant digits a Float carries.
    func testTheStoredValueIsShownWithAllItsDigits() throws {
        func check(_ value: Float, _ locale: String, endsWith expected: String, _ note: String = "",
                   file: StaticString = #filePath, line: UInt = #line) throws {
            let pattern = DiffractionPattern(qy: 1, qx: 1, pixels: [value])
            let sample = try XCTUnwrap(Readout.sample(at: .init(x: 0, y: 0), in: pattern, basis: basis(calibration())),
                                       file: file, line: line)
            let text = sample.lines(locale: Locale(identifier: locale)).minimal
            XCTAssertTrue(text.hasSuffix(expected), "\(value) in \(locale) read '\(text)', not '...\(expected)' \(note)",
                          file: file, line: line)
        }
        for locale in ["en_US_POSIX", "de_DE"] {
            try check(12345, locale, endsWith: " 12345")
            try check(65535, locale, endsWith: " 65535", "(a saturated 16-bit pixel)")
            try check(123456, locale, endsWith: " 123456")
            try check(4_213_567, locale, endsWith: " 4213567")
            try check(-12345, locale, endsWith: " -12345")
            try check(10000, locale, endsWith: " 10000")
            try check(0, locale, endsWith: " 0")
        }
        try check(12345.5, "en_US_POSIX", endsWith: " 12345.5", "(a fraction keeps what the Float holds)")
        try check(12345.5, "de_DE", endsWith: " 12345,5")
        try check(1234.5678, "en_US_POSIX", endsWith: " 1234.568", "(seven significant digits)")
        try check(0.1, "en_US_POSIX", endsWith: " 0.1", "(the Float 0.1 is not 0.10000000149)")
        try check(0.0275, "en_US_POSIX", endsWith: " 0.0275")
        // VoiceOver is told the same number.
        let pattern = DiffractionPattern(qy: 1, qx: 1, pixels: [65535])
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: 0, y: 0), in: pattern, basis: basis(calibration())))
        XCTAssertTrue(sample.spoken(locale: Locale(identifier: "en_US_POSIX")).contains("intensity 65535"))
    }

    func testTheTextKeepsEachNumbersMeaningAndDropsQLast() throws {
        let posix = Locale(identifier: "en_US_POSIX")
        let sample = try XCTUnwrap(Readout.sample(at: .init(x: 74, y: 64), in: pattern128, basis: basis(calibration())))
        let lines = sample.lines(locale: posix)
        XCTAssertEqual(lines.full, "Qx 74 \u{00B7} Qy 64 \u{00B7} I 1 \u{00B7} q 0.2 nm⁻¹")
        XCTAssertEqual(lines.short, "Qx 74 Qy 64 I 1 q 0.2 nm⁻¹", "the separators go first: the names stay (S2)")
        XCTAssertEqual(lines.minimal, "Qx 74 Qy 64 I 1", "then q; never a bare (74, 64)")
        XCTAssertEqual(sample.spoken(locale: posix), "Detector pixel Qx 74, Qy 64, intensity 1, q 0.2 nm⁻¹")
        let uncalibrated = try XCTUnwrap(Readout.sample(at: .init(x: 74, y: 64), in: pattern128,
                                                        basis: basis(calibration(q: nil, units: nil))))
        XCTAssertEqual(uncalibrated.lines(locale: posix).full, "Qx 74 \u{00B7} Qy 64 \u{00B7} I 1")
        XCTAssertEqual(uncalibrated.spoken(locale: posix), "Detector pixel Qx 74, Qy 64, intensity 1")
    }
}
