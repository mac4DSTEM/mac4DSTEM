import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoCore
import DiffractoGeometry   // QCalibrationShellCheck is DiffractoKit's LinearScaleShellCheck
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
/// refusal are one predicate — is covered by `tools/harnesses/calibration-readiness-test`.
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

        let vectors = try XCTUnwrap(state.resultPresentation.braggVectors,
                                    "Demo disk detection published no Bragg vectors")
        XCTAssertGreaterThan(vectors.totalPeakCount, 0)
        XCTAssertNil(state.calibrationSession.calibration.qPixelSize,
                     "The uncalibrated demo must not arrive with a Q pixel size")

        state.acomSession.modelSelection = .library("au_fcc")
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
        state.calibrationSession.calibration.originProvenance = .fitted
        state.calibrationSession.calibration.probeRadius = Self.probeRadius
        state.calibrationSession.calibration.origin = origin(residual: residual, centre: centre, scan: scan)
        XCTAssertEqual(state.calibrationSession.calibration.origin?.rmsResidual ?? .nan, residual, accuracy: 1e-4)
    }

    /// The defect: an origin the app itself calls unusable produced a Q pixel
    /// size stamped "Measured in app".
    func testUnusableOriginRefusesQCalibrationAndSetsNoScale() async throws {
        let state = try await stateReadyToCalibrateQ()
        // Si_SiGe's ratio to scale: residual ≈ 2.3× the probe radius.
        install(residual: Self.probeRadius * 2.32, on: state)

        await state.calibrateQFromCrystal()

        XCTAssertNil(state.calibrationSession.calibration.qPixelSize,
                     "A refused Q calibration must not leave a scale behind")
        XCTAssertNil(state.calibrationSession.provenance.qScale,
                     "A refused Q calibration must not claim any provenance")
        XCTAssertNotEqual(state.calibrationSession.provenance.qScale, .measuredInApp)
        XCTAssertFalse(state.acomScaleSemantics.provenance.isPhysical,
                       "ACOM must fall back to exploratory matching, not a measured scale")
        XCTAssertTrue(state.statusText.contains("exceeds the 4.5 px probe radius"),
                      "The refusal must quote the numbers it judged: \(state.statusText)")
        XCTAssertTrue(state.statusText.contains("Origin fit"),
                      "The refusal must name the control that changes the fit: \(state.statusText)")
        XCTAssertNil(state.errorMessage,
                     "A refused calibration is recoverable and must stay off the modal path")
    }

    /// The other half of the pair: the gate must not have simply disabled the estimator. Same origin gate, a residual inside the
    /// probe disk, and rings planted on Al [001] (Δq 0.0320 Å⁻¹/px: {200}, {220}, {400} at 15.4, 21.8 and 30.9 px).
    ///
    /// **This test used to pin the demo cube read against gold, 0.024440 Å⁻¹/px with a shell ratio 1.43 against 1.155 predicted:
    /// the known-wrong result of taking the demo's first ring ({110} of a simple-cubic [001] zone) for gold's {111}.** Moved on
    /// purpose, 2026-10-22, when the first ring stopped being assumed (`ShellAssignment`, calibration design section 6): that
    /// pairing is now refused (`testTheDemoRingsFitTwoGoldAssignmentsAndAreRefused`), and a case that is assigned reads back
    /// the planted scale. The measured shell ratio is still reported beside the crystal's, unjudged.
    func testAcceptableOriginCalibratesAndTheAssignedShellIsSurfaced() async throws {
        let state = try await stateReadyToCalibrateQ()
        install(residual: Self.probeRadius * 0.2, on: state)
        let descriptor = try XCTUnwrap(state.descriptor)
        state.acomSession.modelSelection = .library("al_fcc")
        let deltaQ = 0.0320
        PlantedQCalibration.setRings(
            radiiPixels: [4.0, 8.0, 16.0].map { PlantedQCalibration.g($0) / deltaQ }, on: state)

        XCTAssertNil(state.gates.reciprocalMetrologyRefusal(
            for: state.calibrationSession.calibration, descriptor: descriptor,
            apertureCentre: (x: state.aperture.centerX, y: state.aperture.centerY)
        ), "a usable fitted origin must pass the metrology gate")

        await state.calibrateQFromCrystal()

        let scale = try XCTUnwrap(state.calibrationSession.calibration.qPixelSize,
                                  "a usable origin must still calibrate: \(state.statusText)")
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .measuredInApp)
        XCTAssertNil(state.qCalibration.refusal)
        XCTAssertEqual(scale, deltaQ, accuracy: 1e-6 * deltaQ, "the planted scale: \(state.statusText)")
        XCTAssertEqual(state.qCalibration.estimate?.assignment?.label, "{200}")

        // The measured ratio of the second ring against the crystal's {220}/{200} reaches the user: the measurement, without a verdict.
        let mismatch = try XCTUnwrap(state.qCalibration.shellCheck?.mismatch,
                                     "a two-shell pattern must report a measured ratio")
        XCTAssertLessThan(mismatch, 1e-6, "planted rings sit on the crystal's ratio")
        let summary = try XCTUnwrap(state.qCalibration.selfCheckSummary)
        XCTAssertTrue(summary.contains("predicted"), "the panel line must name both numbers: \(summary)")
        XCTAssertTrue(summary.contains("positions"), "and how many positions it rests on: \(summary)")
    }

    /// The demo draws {110} at 45 degrees and {200} on the axes (a simple-cubic [001] zone, confirmed from the fixture's pixel
    /// centroids) at a 1 : 1.433 ratio. Against gold that ratio fits two starting shells equally well: {200} then {220} (1.414),
    /// and {220} then {400} (1.414). The estimator used to take the first ring for {111} and write a scale 22 % off; now it
    /// refuses, names both assignments and writes nothing. Break it by assuming H0 again.
    func testTheDemoRingsFitTwoGoldAssignmentsAndAreRefused() async throws {
        let state = try await stateReadyToCalibrateQ()
        install(residual: Self.probeRadius * 0.2, on: state)

        await state.calibrateQFromCrystal()

        let refusal = try XCTUnwrap(state.qCalibration.refusal, "expected a refusal: \(state.statusText)")
        XCTAssertTrue(refusal.contains("Two assignments fit equally well"), refusal)
        XCTAssertNil(state.calibrationSession.calibration.qPixelSize, "a refusal writes no scale")
        XCTAssertNil(state.calibrationSession.provenance.qScale)
        XCTAssertNil(state.qCalibration.estimate)
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
        state.calibrationSession.calibration.origin = nil
        state.calibrationSession.calibration.probeRadius = Self.probeRadius
        XCTAssertNil(state.calibrationSession.calibration.recordedMeanOrigin)
        // The LOOSER predicate still passes — unchanged behaviour, and the
        // reason the two had to be split rather than one tightened.
        XCTAssertTrue(state.calibrationSession.calibration.originFitIsSane)

        await state.calibrateQFromCrystal()

        XCTAssertNil(state.calibrationSession.calibration.qPixelSize,
                     "A guessed centre must not produce a scale: \(state.statusText)")
        XCTAssertNil(state.calibrationSession.provenance.qScale,
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
    /// is `tools/harnesses/q-calibration-gate-test`.
    func testRecordedMeanOriginIsAcceptedAsAMeasuredBeamCentre() async throws {
        let state = try await stateReadyToCalibrateQ()
        let descriptor = try XCTUnwrap(state.descriptor)
        state.calibrationSession.calibration.origin = nil
        state.calibrationSession.calibration.probeRadius = Self.probeRadius

        let aperture = (x: state.aperture.centerX, y: state.aperture.centerY)
        XCTAssertNotNil(state.gates.reciprocalMetrologyRefusal(
            for: state.calibrationSession.calibration, descriptor: descriptor, apertureCentre: aperture
        ), "with nothing measured, the gate refuses — the other half of the pair")

        state.calibrationSession.calibration.recordedOriginX = Float(descriptor.qx) / 2
        state.calibrationSession.calibration.recordedOriginY = Float(descriptor.qy) / 2
        state.calibrationSession.calibration.originProvenance = .fileMean

        XCTAssertNil(state.gates.reciprocalMetrologyRefusal(
            for: state.calibrationSession.calibration, descriptor: descriptor, apertureCentre: aperture
        ), "a recorded beam centre IS a measurement and must be admitted")

        // And it must be used as ITSELF. Before S13 this state produced
        // `(qx/2, qy/2)` — which on this fixture happens to be the same point,
        // so the value is checked against a DISPLACED recorded origin, where
        // the two answers differ.
        state.calibrationSession.calibration.recordedOriginX = Float(descriptor.qx) / 2 + 7
        let resolved = state.calibrationSession.calibration.referenceOrigin(
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
        XCTAssertNil(state.calibrationSession.calibration.originFitRefusal)

        await state.calibrateQFromCrystal()

        XCTAssertTrue(state.statusText.contains("Detect Bragg disks"),
                      "Expected the pre-existing prerequisite message: \(state.statusText)")
    }

    /// Gate D 2026-09-05 (`../_archive/mac4DSTEM/docs/q-calibration-design.md` §8): the innermost
    /// shell is k noisy equivalents of one radius; their minimum is biased low
    /// by c_k·σ and the scale read 2.1 % high on WS₂, 2.4 % on sim_Au. The
    /// estimator averages the same-shell cluster. The minimum, computed here
    /// from the same peaks, must read low — or the test compares nothing.
    func testSameShellEquivalentsAreAveragedNotMinimised() throws {
        var state: UInt64 = 0x5133
        func normal() -> Double {
            func uniform() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(1 << 53)
            }
            let u1 = max(uniform(), 1e-12), u2 = uniform()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        let truth = 20.0, sigma = 0.3, positions = 300
        let centre = (x: Float(64), y: Float(64))
        var peaks: [[BraggPeak]] = []
        var minima: [Double] = []
        for _ in 0..<positions {
            var row: [BraggPeak] = []
            var radii: [Double] = []
            for spoke in 0..<6 {
                let angle = Double(spoke) * .pi / 3 + 0.2
                let radius = truth + normal() * sigma
                radii.append(radius)
                row.append(BraggPeak(x: centre.x + Float(radius * cos(angle)),
                                     y: centre.y + Float(radius * sin(angle)), intensity: 1))
            }
            peaks.append(row)
            minima.append(radii.min()!)
        }
        let vectors = BraggVectors(scanWidth: positions, scanHeight: 1, peaks: peaks)
        let estimate = try XCTUnwrap(KnownCrystalQCalibration.estimate(
            bragg: vectors, origin: centre, referenceRadiusInvAngstrom: 0.4,
            secondShellRadiusInvAngstrom: nil, probeRadiusPixels: nil))
        let minimumMedian = minima.sorted()[positions / 2]
        XCTAssertGreaterThan(truth - minimumMedian, 0.25,
                             "fixture broken: the minimum of six must read ≥ 0.25 px low (c_6·σ = 0.38)")
        XCTAssertEqual(estimate.observedRadiusPixels, truth, accuracy: 0.03,
                       "the cluster mean is unbiased; the minimum reads \(minimumMedian)")
        XCTAssertEqual(estimate.sameShellPeaksPerPosition, 6)
        XCTAssertEqual(estimate.invAngstromPerPixel, 0.4 / truth, accuracy: 0.4 / truth * 0.002)
    }
}
