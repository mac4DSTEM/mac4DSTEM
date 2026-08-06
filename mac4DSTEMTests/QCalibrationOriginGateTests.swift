import XCTest
@testable import mac4DSTEM

/// Backlog #46. `calibrateQFromCrystal` derived a Q pixel size from an origin
/// the app had *already* declared unfit — the Origin row read "exceeds probe
/// radius; recalibrate before quantitative use" while the Q row, derived from
/// that same origin, read "Measured in app". On `downsample_Si_SiGe_exp` the
/// resulting scale was 2.56× too large, and it was the label rather than the
/// warning that travelled into export, reopen and the QC log.
///
/// The pair that matters is `testUnusableOrigin…` against
/// `testAcceptableOrigin…`: **same dataset, same peaks, same phase model, one
/// number different** — the origin fit residual. One refuses and leaves no
/// value; the other calibrates to the demo's own scale and stamps
/// `.measuredInApp`. Either test alone proves nothing, because a gate that
/// refuses everything would also pass the first. Both run the app's real
/// detection path so `braggVectors` is genuinely present; a gate placed after
/// the input guards would look identical to a test that never got that far.
///
/// **What this file does NOT establish.** The gate's threshold is
/// `residual <= probeRadius`, inherited from the readiness badge. Adversarial
/// review on 2026-08-06 showed the estimator's own failure onset is far lower —
/// `KnownCrystalQCalibration.estimate` drops peaks inside
/// `minimumRadiusPixels` (default 2, never overridden), so once a per-position
/// residual exceeds ~2 px the direct beam survives that filter and becomes the
/// "innermost reflection". Residuals in `(2 px, probeRadius]` therefore still
/// calibrate and are still stamped `.measuredInApp`. That is recorded as a
/// separate open item; this file deliberately does not pin behaviour in that
/// band, because nothing here has established what it should be.
///
/// The judgement itself — every origin state, and that Prepare's badge and this
/// refusal are one predicate — is covered by `tools/calibration-readiness-test`.
@MainActor
final class QCalibrationOriginGateTests: XCTestCase {

    private static let probeRadius: Float = 4.5

    /// Demo cube + full-scan disk detection + a gold phase model, i.e. every
    /// prerequisite `calibrateQFromCrystal` checks *except* the origin. The
    /// demo is loaded uncalibrated so a Q pixel size can only appear if this
    /// call put it there.
    private func stateReadyToCalibrateQ() async throws -> AppState {
        let state = AppState()
        await state.openDemoFixture(calibrated: false)
        state.analysisMode = .disks
        await state.runDiskDetection()

        let vectors = try XCTUnwrap(state.braggVectors,
                                    "Demo disk detection published no Bragg vectors")
        XCTAssertGreaterThan(vectors.totalPeakCount, 0)
        XCTAssertNil(state.calibration.qPixelSize,
                     "The uncalibrated demo must not arrive with a Q pixel size")

        state.acomModelSelection = .library("au_fcc")
        XCTAssertNotNil(state.resolvedACOMModel, "Gold phase model did not resolve")
        return state
    }

    /// Origin maps whose measured points sit `residual` px from the fit, so
    /// `OriginMaps.rmsResidual` is exactly `residual`, and whose *fitted*
    /// origin is the true beam centre.
    ///
    /// The dimensions must match the scan exactly. `BraggVectors.calibrated`
    /// gates re-centring on `origins.width == scanWidth && origins.height ==
    /// scanHeight` (`DiskDetection.swift:417`), and an uncalibrated demo has no
    /// ellipse either, so a mismatched map is *silently discarded* and the
    /// vectors pass through untransformed. An earlier version of this file used
    /// `width: 8, height: 1` against the 12×12 demo and did exactly that: the
    /// injected origin never reached the estimator, and the "acceptable"
    /// case was measuring radii from the detector corner.
    private func origin(residual: Float, centre: Float, scan: Int) -> OriginMaps {
        let count = scan * scan
        let signs = (0..<count).map { Float($0 % 2 == 0 ? 1 : -1) }
        return OriginMaps(
            width: scan, height: scan,
            measuredX: signs.map { centre + $0 * residual },
            measuredY: [Float](repeating: centre, count: count),
            fittedX: [Float](repeating: centre, count: count),
            fittedY: [Float](repeating: centre, count: count)
        )
    }

    private func install(residual: Float, on state: AppState) {
        let scan = state.descriptor.map { max($0.rx, $0.ry) } ?? 12
        let centre = Float(state.descriptor.map { $0.qx } ?? 64) / 2
        state.calibration.originProvenance = .fitted
        state.calibration.probeRadius = Self.probeRadius
        state.calibration.origin = origin(residual: residual, centre: centre, scan: scan)
        XCTAssertEqual(state.calibration.origin?.rmsResidual ?? .nan, residual, accuracy: 1e-4)
    }

    /// The defect: an origin the app itself calls unusable produced a Q pixel
    /// size stamped "Measured in app".
    func testUnusableOriginRefusesQCalibrationAndSetsNoScale() async throws {
        let state = try await stateReadyToCalibrateQ()
        // Si_SiGe's ratio to scale: residual ≈ 2.3× the probe radius.
        install(residual: Self.probeRadius * 2.32, on: state)

        await state.calibrateQFromCrystal()

        XCTAssertNil(state.calibration.qPixelSize,
                     "A refused Q calibration must not leave a scale behind")
        XCTAssertNil(state.calibrationProvenance.qScale,
                     "A refused Q calibration must not claim any provenance")
        XCTAssertNotEqual(state.calibrationProvenance.qScale, .measuredInApp)
        XCTAssertFalse(state.acomScaleSemantics.provenance.isPhysical,
                       "ACOM must fall back to exploratory matching, not a measured scale")
        XCTAssertTrue(state.statusText.contains("exceeds the 4.5 px probe radius"),
                      "The refusal must quote the numbers it judged: \(state.statusText)")
        XCTAssertTrue(state.statusText.contains("Origin fit"),
                      "The refusal must name the control that changes the fit: \(state.statusText)")
        XCTAssertNil(state.errorMessage,
                     "A refused calibration is recoverable and must stay off the modal path")
    }

    /// The other half of the pair: the gate must not have simply disabled the
    /// estimator. Same peaks, same model, a residual inside the probe disk.
    func testAcceptableOriginStillCalibratesAndStampsMeasuredInApp() async throws {
        let state = try await stateReadyToCalibrateQ()
        install(residual: Self.probeRadius * 0.2, on: state)

        await state.calibrateQFromCrystal()

        let scale = try XCTUnwrap(state.calibration.qPixelSize,
                                  "A usable origin must still calibrate: \(state.statusText)")
        // Assert the *value*, not merely that one exists. `scale > 0` would
        // pass on a Q derived from the detector corner, which is the same
        // class of defect as #46 — a number that exists and is wrong. The
        // demo cube is gold at 0.02 Å⁻¹/px (`DemoFourDDataSource`, and
        // `DemoWorkflowTests` matches against the same figure).
        XCTAssertEqual(scale, 0.02, accuracy: 0.006,
                       "Q from a usable origin drifted off the demo's own scale")
        XCTAssertEqual(state.calibration.qPixelUnits, "Å⁻¹")
        XCTAssertEqual(state.calibrationProvenance.qScale, .measuredInApp)
        XCTAssertTrue(state.acomScaleSemantics.provenance.isPhysical)
        XCTAssertTrue(state.statusText.contains("Q calibration ✓"),
                      "Expected the success status: \(state.statusText)")
    }

    /// The two surfaces are one judgement: whenever Prepare blocks the origin
    /// row on the fit, the Q action refuses, and vice versa.
    func testReadinessRowAndQRefusalAgree() {
        let state = AppState()

        install(residual: Self.probeRadius * 2.32, on: state)
        let blocked = state.calibrationReadiness.items.first { $0.kind == .originProbe }
        XCTAssertEqual(blocked?.status.isReady, false)
        XCTAssertNotNil(state.calibration.originFitRefusal)

        install(residual: Self.probeRadius * 0.2, on: state)
        let ready = state.calibrationReadiness.items.first { $0.kind == .originProbe }
        XCTAssertEqual(ready?.status.isReady, true)
        XCTAssertNil(state.calibration.originFitRefusal)
    }

    /// The gate is the residual, not the whole readiness row. An origin that
    /// was never fitted carries no residual to judge, and must still reach the
    /// existing prerequisite messages rather than this refusal.
    func testUnfittedOriginIsNotRefusedByTheFitGate() async {
        let state = AppState()
        XCTAssertNil(state.calibration.originFitRefusal)

        await state.calibrateQFromCrystal()

        XCTAssertTrue(state.statusText.contains("Detect Bragg disks"),
                      "Expected the pre-existing prerequisite message: \(state.statusText)")
    }
}
