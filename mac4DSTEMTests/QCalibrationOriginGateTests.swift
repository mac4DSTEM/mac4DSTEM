import XCTest
import DSTEMCore
import DSTEMSession
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
        state.navigation.analysisMode = .disks
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
    ///
    /// **This test used to assert 0.02 Å⁻¹/px with `accuracy: 0.006` — a 30%
    /// tolerance on the one number it existed to pin, which hid a real error
    /// entirely.** v2 S13 found the error; Gate B corrected its size and its
    /// cause on the same day. What is true, measured:
    ///
    /// - `DemoFourDDataSource.pattern` draws **{110} at 45° and {200} on-axis**
    ///   — a SIMPLE-CUBIC [001] zone, confirmed from the fixture's own pixel
    ///   centroids — on a gold lattice constant. `Crystal.gold.reflections`
    ///   returns **zero** reflections at any permutation of (110).
    /// - The demo's declared 0.02 Å⁻¹/px is honoured by the geometry: the outer
    ///   ring is gold's {200} at that scale to **0.09%**.
    /// - So paired with `au_fcc` the innermost detected peak is not the
    ///   innermost allowed reflection, and the scale comes out wrong.
    ///
    /// **Nothing refuses it.** S13 shipped an estimator threshold that did, and
    /// Gate B refuted the threshold's derivation, so it was cut — the estimator
    /// now *measures* the shell ratio and reports it. This test pins both: the
    /// value, tightly enough to be worth pinning, and the fact that the
    /// disagreement is surfaced rather than swallowed.
    func testAcceptableOriginCalibratesAndTheShellDisagreementIsSurfaced() async throws {
        let state = try await stateReadyToCalibrateQ()
        install(residual: Self.probeRadius * 0.2, on: state)
        let descriptor = try XCTUnwrap(state.descriptor)

        XCTAssertNil(state.gates.reciprocalMetrologyRefusal(
            for: state.calibration, descriptor: descriptor,
            apertureCentre: (x: state.aperture.centerX, y: state.aperture.centerY)
        ), "a usable fitted origin must pass the metrology gate")

        await state.calibrateQFromCrystal()

        let scale = try XCTUnwrap(state.calibration.qPixelSize,
                                  "a usable origin must still calibrate: \(state.statusText)")
        XCTAssertEqual(state.calibrationProvenance.qScale, .measuredInApp)
        XCTAssertNil(state.qCalibration.refusal, "the estimator refuses nothing")

        // The value, pinned tightly. It is NOT the demo's declared 0.02 — it is
        // what the app produces from a simple-cubic ring read as gold's {111},
        // and pinning it is how a later session notices if the fixture or the
        // estimator changes. If it moves, check why first, then rewrite this.
        //
        // Moved once already, deliberately: 0.021 → 0.024472 on 2026-09-01,
        // when the probe-radius repair (meanDP instead of maxDP) took the
        // demo's kernel from the over-measured 9.649 px to 6.93 px — still
        // above the drawn 4.5, because the demo's rings are in EVERY pattern
        // and the mean keeps them at reduced strength; the scan-union share
        // is gone, the every-pattern share is not (Gate B measurement,
        // 2026-09-01) — and the measured first shell from ~20.4 px to 17.36
        // against the fixture's true 17.03, the kernel-following shift
        // collapsing as the 2026-08-28 entry predicted. The demo stays
        // wrong-by-construction, and MORE visibly so (shell ratio 1.433 vs
        // 1.155, previously 1.373) — see
        // docs/archive/v2-session-records/probe-radius.md.
        XCTAssertEqual(scale, 0.024472, accuracy: 0.0006,
                       "the known-wrong demo scale moved: \(state.statusText)")

        // And the disagreement must reach the user. This is what survived of
        // S13's §3: the measurement, without a verdict.
        let mismatch = try XCTUnwrap(state.qCalibration.shellCheck?.mismatch,
                                     "a two-shell pattern must report a measured ratio")
        XCTAssertGreaterThan(mismatch, 0.15,
                             "the demo's shells disagree with gold's by far more than rounding, "
                             + "and that must be visible: got \(mismatch)")
        let summary = try XCTUnwrap(state.qCalibration.selfCheckSummary)
        XCTAssertTrue(summary.contains("predicted"),
                      "the panel line must name both numbers: \(summary)")
        XCTAssertTrue(summary.contains("positions"),
                      "and how many positions it rests on: \(summary)")
    }

    /// The finding, pinned so a later session that repairs `DemoFourDDataSource`
    /// is told this test needs updating rather than discovering it.
    ///
    /// **Gate B measured that the obvious repair makes things worse**: drawing
    /// gold's {111} and {200} at the declared 0.02 produces a shell ratio that
    /// AGREES to 1.1% and a scale that is silently **−8.5%** wrong, because the
    /// probe radius was over-measured 2.15× on this fixture and a constant
    /// kernel bias moves the ratio by almost nothing. The radius half was
    /// fixed 2026-09-01 (meanDP; demo kernel now 6.93 px — see
    /// docs/archive/v2-session-records/probe-radius.md); whether the −8.5%
    /// figure still holds for a repaired fixture is unmeasured, so the
    /// fixture stays as-is and this pin stays load-bearing.
    func testTheDemoShellsDoNotMatchTheGoldModelItIsPairedWith() async throws {
        let state = try await stateReadyToCalibrateQ()
        install(residual: Self.probeRadius * 0.2, on: state)

        await state.calibrateQFromCrystal()

        guard case .measured(let observed, let expected, _)?
            = state.qCalibration.shellCheck else {
            return XCTFail("expected a measured shell ratio: \(state.statusText)")
        }
        XCTAssertEqual(expected, 2.0 / 3.0.squareRoot(), accuracy: 1e-9,
                       "gold's {200}/{111} is the prediction")
        XCTAssertGreaterThan(observed, expected * 1.15,
                             "and what the demo shows is well above it — observed \(observed)")
    }

    // MARK: - The nil-origin branch (v2 S13)
    //
    // S11 recorded the blind spot this closes, 2026-08-28: **every case above
    // builds origin MAPS**, so the branch where `calibration.origin` is nil —
    // the `.fileMean`/`.sessionMean` states, which are the ordinary shape of a
    // py4DSTEM calibration bundle — had never run in this suite at all. That is
    // exactly where the defect lived: `meanOrigin` was nil, `calibratedBraggVectors`
    // substituted `(qx/2, qy/2)`, and `originFitIsSane` returns `true` when
    // there is no residual to judge, so the result was stamped `.measuredInApp`
    // with the detector's geometric middle standing in for the beam.

    /// Nothing measured the beam: no maps, no recorded mean. The stricter
    /// predicate must refuse rather than fall through to the geometric middle.
    func testOriginWithNoMeasuredCentreRefusesQCalibration() async throws {
        let state = try await stateReadyToCalibrateQ()
        // `stateReadyToCalibrateQ` runs disk detection, which runs
        // `generateProbeKernel`, which calls `calibrateOrigin()` when there is
        // no probe radius — so the demo arrives here WITH fitted maps. Nulling
        // them is what reaches the branch S11 said had never run; an earlier
        // version of this test asserted the maps were already nil and was
        // simply wrong about the fixture.
        state.calibration.origin = nil
        state.calibration.probeRadius = Self.probeRadius
        XCTAssertNil(state.calibration.recordedMeanOrigin)
        // The LOOSER predicate still passes — unchanged behaviour, and the
        // reason the two had to be split rather than one tightened.
        XCTAssertTrue(state.calibration.originFitIsSane)

        await state.calibrateQFromCrystal()

        XCTAssertNil(state.calibration.qPixelSize,
                     "A guessed centre must not produce a scale: \(state.statusText)")
        XCTAssertNil(state.calibrationProvenance.qScale,
                     "and must not claim any provenance, least of all .measuredInApp")
        XCTAssertTrue(state.statusText.contains("measured beam centre"),
                      "The refusal must say what is missing: \(state.statusText)")
        XCTAssertNotNil(state.qCalibration.refusal, "the seam must carry the refusal")
        XCTAssertNil(state.qCalibration.estimate, "a refused run leaves no estimate behind")
    }

    /// The other half of the pair, and the one that proves the fix is a fix
    /// rather than a blanket refusal: a file's recorded beam centre, with no
    /// per-position maps, must be ACCEPTED as a measured origin — the exact
    /// state (`.fileMean`/`.sessionMean`) in which the app previously
    /// substituted the detector's geometric middle.
    ///
    /// Asserted at the gate rather than end to end, deliberately: the demo's
    /// shells do not match `au_fcc` (see above), so an end-to-end assertion
    /// here would be measuring that unrelated defect. The end-to-end value case
    /// is `tools/q-calibration-gate-test`.
    func testRecordedMeanOriginIsAcceptedAsAMeasuredBeamCentre() async throws {
        let state = try await stateReadyToCalibrateQ()
        let descriptor = try XCTUnwrap(state.descriptor)
        state.calibration.origin = nil
        state.calibration.probeRadius = Self.probeRadius

        let aperture = (x: state.aperture.centerX, y: state.aperture.centerY)
        XCTAssertNotNil(state.gates.reciprocalMetrologyRefusal(
            for: state.calibration, descriptor: descriptor, apertureCentre: aperture
        ), "with nothing measured, the gate refuses — the other half of the pair")

        state.calibration.recordedOriginX = Float(descriptor.qx) / 2
        state.calibration.recordedOriginY = Float(descriptor.qy) / 2
        state.calibration.originProvenance = .fileMean

        XCTAssertNil(state.gates.reciprocalMetrologyRefusal(
            for: state.calibration, descriptor: descriptor, apertureCentre: aperture
        ), "a recorded beam centre IS a measurement and must be admitted")

        // And it must be used as ITSELF. Before S13 this state produced
        // `(qx/2, qy/2)` — which on this fixture happens to be the same point,
        // so the value is checked against a DISPLACED recorded origin, where
        // the two answers differ.
        state.calibration.recordedOriginX = Float(descriptor.qx) / 2 + 7
        let resolved = state.calibration.referenceOrigin(
            detectorQX: descriptor.qx, detectorQY: descriptor.qy, apertureCentre: aperture
        )
        XCTAssertEqual(resolved.kind, .recordedMean)
        XCTAssertEqual(resolved.x, Float(descriptor.qx) / 2 + 7, accuracy: 1e-6,
                       "the recorded origin must be used verbatim, not collapsed to the middle")
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
