import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// C5's first extraction (2026-09-07): the fit-verification overlays left
/// `AppState` as a value over a snapshot. These pin what the move must not
/// change — the geometry is Core's, the gating is the value's, and a
/// calibration restored from a sidecar draws what the live one drew.
final class FitOverlayPresentationTests: XCTestCase {

    /// A 3-wide, 2-high scan on a 128 px detector: the shape of
    /// `StrainFrameTests.syntheticStrainMap()` (origin 64, 64).
    private let descriptor = DatasetDescriptor(
        filePath: "/tmp/fit.h5", datasetPath: "/data",
        shape: [2, 3, 128, 128], dtypeDescription: "float32", chunkShape: nil
    )

    private func snapshot(
        enabled: Bool = true, analysis: FitOverlayPresentation.Analysis = .other,
        inPrepare: Bool = false, current: Bool = true, point: Bool = true,
        x: Int = 2, y: Int = 0, calibration: Calibration = Calibration(),
        ellipseFit: EllipseCalibrationFit? = nil, strainMap: StrainMap? = nil,
        bragg: BraggVectors? = nil
    ) -> FitOverlayPresentation {
        FitOverlayPresentation(
            enabled: enabled, analysis: analysis, inPrepare: inPrepare,
            showsCurrentPattern: current, pointSelection: point,
            descriptor: descriptor, selectedX: x, selectedY: y,
            calibration: calibration, ellipseFit: ellipseFit,
            braggVectors: bragg, strainMap: strainMap
        )
    }

    /// Six fitted origins, none equal to the mean, so a per-position origin
    /// is distinguishable from the mean origin.
    private func fittedOrigins() -> OriginMaps {
        OriginMaps(width: 3, height: 2, measuredX: nil, measuredY: nil,
                   fittedX: [60, 61, 62, 63, 64, 65],
                   fittedY: [70, 71, 72, 73, 74, 75])
    }

    // MARK: Strain — the value hands Core the same call AppState made

    func testTheStrainOverlayIsCoresOverlayForTheSelectedPosition() throws {
        let map = try XCTUnwrap(StrainFrameTests.syntheticStrainMap())
        let fit = try XCTUnwrap(snapshot(analysis: .strain, strainMap: map).strain,
                                "the tension position must draw a local lattice")
        let direct = try XCTUnwrap(FitOverlays.strainOverlay(
            map: map, scanIndex: 2, calibration: Calibration(),
            referenceOrigin: (x: 64, y: 64), patternWidth: 128, patternHeight: 128
        ))
        XCTAssertEqual(fit.originX, direct.originX)
        XCTAssertEqual(fit.originY, direct.originY)
        XCTAssertEqual(fit.predicted.map(\.x), direct.predicted.map(\.x))
        XCTAssertEqual(fit.predicted.map(\.y), direct.predicted.map(\.y))
        XCTAssertEqual(fit.localResidualPixels, direct.localResidualPixels)
        XCTAssertFalse(fit.predicted.isEmpty)
    }

    func testAnOverlayOnlyDrawsOnTheSinglePatternItWasMeasuredFrom() throws {
        let map = try XCTUnwrap(StrainFrameTests.syntheticStrainMap())
        XCTAssertNotNil(snapshot(analysis: .strain, strainMap: map).strain)
        XCTAssertNil(snapshot(analysis: .strain, current: false, strainMap: map).strain,
                     "the mean/max pattern is described by no per-position vector")
        XCTAssertNil(snapshot(analysis: .strain, point: false, strainMap: map).strain,
                     "an ROI-summed pattern is not the selected position")
        XCTAssertNil(snapshot(enabled: false, analysis: .strain, strainMap: map).strain,
                     "the toggle is the user's")
        XCTAssertNil(snapshot(analysis: .other, strainMap: map).strain,
                     "a strain lattice belongs to the strain mode")
        // Availability is about the mode, not the pattern: the toggle still
        // shows on the mean pattern so the user can turn it back on.
        XCTAssertTrue(snapshot(analysis: .strain, current: false, strainMap: map).isAvailable)
        XCTAssertFalse(snapshot(analysis: .strain).isAvailable)
        XCTAssertFalse(snapshot(analysis: .acom, strainMap: map).isAvailable)
    }

    func testStoredPeaksComeFromTheSelectedPositionOnly() {
        let peaks = [[BraggPeak(x: 1, y: 1, intensity: 1)], [], [BraggPeak(x: 9, y: 8, intensity: 2)],
                     [], [BraggPeak(x: 5, y: 5, intensity: 3)], []]
        let bragg = BraggVectors(scanWidth: 3, scanHeight: 2, peaks: peaks)
        XCTAssertEqual(snapshot(x: 2, y: 0, bragg: bragg).storedPeaksAtSelection.map(\.x), [9])
        XCTAssertEqual(snapshot(x: 0, y: 0, bragg: bragg).storedPeaksAtSelection.map(\.x), [1])
        XCTAssertEqual(snapshot(x: 1, y: 1, bragg: bragg).storedPeaksAtSelection.map(\.x), [5],
                       "row-major over the scan WIDTH: (1, 1) is index 4, not 3")
        XCTAssertTrue(snapshot(current: false, x: 2, y: 0, bragg: bragg).storedPeaksAtSelection.isEmpty)
        let wrongScan = BraggVectors(scanWidth: 2, scanHeight: 3, peaks: peaks)
        XCTAssertTrue(snapshot(bragg: wrongScan).storedPeaksAtSelection.isEmpty,
                      "vectors from another scan shape describe nothing here")
    }

    // MARK: Origin and ellipse — Prepare's evidence

    func testTheOriginPointFollowsTheDisplayedPattern() throws {
        var calibration = Calibration()
        calibration.origin = fittedOrigins()
        let mean = try XCTUnwrap(calibration.meanOrigin)
        let local = FitOverlays.localOrigin(
            calibration: calibration, referenceOrigin: mean,
            scanIndex: 2, scanWidth: 3, scanHeight: 2
        )
        let current = try XCTUnwrap(snapshot(inPrepare: true, calibration: calibration).originPoint)
        XCTAssertEqual(current.x, local.x); XCTAssertEqual(current.y, local.y)
        XCTAssertNotEqual(current.x, mean.x, "the current pattern shows ITS origin, not the mean")
        let onMean = try XCTUnwrap(snapshot(inPrepare: true, current: false, calibration: calibration).originPoint)
        XCTAssertEqual(onMean.x, mean.x); XCTAssertEqual(onMean.y, mean.y)
        XCTAssertNil(snapshot(inPrepare: false, calibration: calibration).originPoint,
                     "the origin is judged in Prepare")
        XCTAssertNil(snapshot(inPrepare: true, point: false, calibration: calibration).originPoint)
        XCTAssertNil(snapshot(inPrepare: true).originPoint, "no fitted origin, nothing to draw")
        XCTAssertTrue(snapshot(inPrepare: true, calibration: calibration).isAvailable)
        XCTAssertFalse(snapshot(inPrepare: false, calibration: calibration).isAvailable)
    }

    func testTheEllipsePrefersTheInAppFitAndItsOwnCentre() throws {
        // Core's fit names its centre in py4DSTEM's (qx = row, qy = column)
        // order; the pane draws x = column. The overlay must swap them.
        let fit = EllipseCalibrationFit(
            centerQX: 10, centerQY: 20, a: 30, b: 25, theta: 0.3,
            normalizedResidual: 0, conicResidual: 0, sampleCount: 100,
            occupiedAngularBins: 36, model: .conic, profile: nil, profileFallbackReason: nil
        )
        var calibration = Calibration()
        calibration.origin = fittedOrigins()
        calibration.ellipseA = 50; calibration.ellipseB = 40; calibration.ellipseTheta = 1.0
        let fromFit = snapshot(inPrepare: true, calibration: calibration, ellipseFit: fit).ellipse
        let expected = FitOverlays.ellipsePolyline(centerX: 20, centerY: 10, a: 30, b: 25, theta: 0.3)
        XCTAssertEqual(fromFit.map(\.x), expected.map(\.x))
        XCTAssertEqual(fromFit.map(\.y), expected.map(\.y))
        let mean = try XCTUnwrap(calibration.meanOrigin)
        let fromSession = snapshot(inPrepare: true, calibration: calibration).ellipse
        let aroundMean = FitOverlays.ellipsePolyline(centerX: mean.x, centerY: mean.y, a: 50, b: 40, theta: 1.0)
        XCTAssertEqual(fromSession.map(\.x), aroundMean.map(\.x))
        XCTAssertEqual(fromSession.map(\.y), aroundMean.map(\.y))
        XCTAssertTrue(snapshot(inPrepare: true).ellipse.isEmpty)
        XCTAssertTrue(snapshot(inPrepare: false, calibration: calibration, ellipseFit: fit).ellipse.isEmpty)
        XCTAssertTrue(snapshot(enabled: false, inPrepare: true, calibration: calibration, ellipseFit: fit).ellipse.isEmpty)
    }

    // MARK: Reopen — a restored calibration draws what the live one drew

    func testACalibrationRestoredFromASidecarDrawsTheSameOriginAndEllipse() throws {
        var saved = PixelCalibration()
        saved.originMaps = PixelOriginMaps(
            shape: [2, 3],
            fittedQX: [70, 71, 72, 73, 74, 75], fittedQY: [60, 61, 62, 63, 64, 65]
        )
        saved.ellipseA = 50; saved.ellipseB = 40; saved.ellipseTheta = 1.0
        let restored = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: saved, policy: .identity, view: nil, descriptor: descriptor
        )).calibration
        XCTAssertTrue(restored.hasFittedOrigin, "the identity restore keeps the fitted maps")

        var live = Calibration()
        live.origin = try XCTUnwrap(saved.originMaps?.appOriginMaps(width: 3, height: 2))
        live.ellipseA = 50; live.ellipseB = 40; live.ellipseTheta = 1.0

        for (current, label) in [(true, "current pattern"), (false, "mean pattern")] {
            let after = snapshot(inPrepare: true, current: current, calibration: restored)
            let before = snapshot(inPrepare: true, current: current, calibration: live)
            let a = try XCTUnwrap(after.originPoint, label)
            let b = try XCTUnwrap(before.originPoint, label)
            XCTAssertEqual(a.x, b.x, label); XCTAssertEqual(a.y, b.y, label)
            XCTAssertEqual(after.ellipse.map(\.x), before.ellipse.map(\.x), label)
            XCTAssertEqual(after.ellipse.map(\.y), before.ellipse.map(\.y), label)
            XCTAssertFalse(after.ellipse.isEmpty, label)
        }
        XCTAssertTrue(snapshot(inPrepare: true, calibration: restored).isAvailable)
    }
}
