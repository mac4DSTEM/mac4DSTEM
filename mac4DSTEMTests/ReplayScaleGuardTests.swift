import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane F item 1 (Gate D; tier 1: the guard decides whether ACOM may run at a scale other than the one recorded).
///
/// Diagnosis: a recipe recorded before commit 2e46e215 (W′: the DPC wavelength moved to DiffractoKit's CODATA 2018 value,
/// +2.72e-5 relative at 200 kV) stores a scale derived from Q in mrad/px with the OLD wavelength, 12.2639/sqrt(V(1+0.97845e-6 V)).
/// The session now derives the same scale 2.72e-5 smaller, and the guard's registered-nowhere 1e-6 refused the replay or rewind
/// with "matching at a different scale", though the user never recalibrated. The guard keeps refusing a real recalibration
/// (>= 1e-3) and admits formula-level differences (<= 1e-4): `ACOMReplayPlan.scaleRelativeTolerance`.
@MainActor
final class ReplayScaleGuardTests: XCTestCase {

    /// The wavelength the pre-W′ DPC code returned (documented in ElectronWavelengthTests: 0.02507865865059979 Å at 200 kV).
    private func oldDPCWavelength(kV: Double) -> Double {
        let volts = kV * 1_000
        return 12.2639 / sqrt(volts * (1 + 0.97845e-6 * volts))
    }

    private func acomRecord(scale: Double) -> [String: String] {
        ["material": "au_fcc", "scale_inv_angstrom_per_pixel": String(scale),
         "matching_backend": "cpu", "scope": String(describing: ACOMRunScope.fullScan),
         "quality": String(describing: ACOMQualityPreset.fast)]
    }

    private var scanCrop: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        return spec
    }

    /// A demo session whose Q scale was entered as `q` in `units` at `kV`.
    private func session(q: Double, units: String, kV: Double) async throws -> (state: AppState, kernel: ProbeKernel) {
        let state = AppState()
        await state.openDemoFixture(specification: scanCrop)
        await state.generateProbeKernel()
        let kernel = try XCTUnwrap(state.probeKernel, "no synthetic kernel: \(state.statusText)")
        state.calibrationSession.calibration.qPixelSize = q
        state.calibrationSession.calibration.qPixelUnits = units
        state.calibrationSession.acceleratingVoltage = kV
        return (state, kernel)
    }

    /// Records detection, ACOM at `recordedScale`, detection again (so the ACOM node is behind the active one) and
    /// returns the ACOM node's id.
    @discardableResult
    private func recordHistory(_ state: AppState, kernel: ProbeKernel, recordedScale: Double) -> String {
        let p1 = state.diskDetection.diskParams
        state.replay.record(kind: "disk_detection",
                            parameters: p1.replayParameters(kernel: kernel).merging(["detector_class": "classical"]) { _, n in n },
                            under: .detectorIdentity)
        let acom = state.replay.record(kind: "acom", parameters: acomRecord(scale: recordedScale), under: .detectorIdentity)
        var p2 = p1; p2.sigmaCC += 1
        state.replay.record(kind: "disk_detection",
                            parameters: p2.replayParameters(kernel: kernel).merging(["detector_class": "classical"]) { _, n in n },
                            under: .detectorIdentity)
        state.diskDetection.diskParams = p2
        return acom
    }

    // MARK: the reproduction (written first; red on the strict 1e-6 guard)

    /// P-A: the mechanism. The old and the new derivation of the same mrad entry differ by -2.72e-5 relative at 200 kV.
    func testTheWavelengthChangeMovesAnMradDerivedScaleBy272Ppm() async throws {
        let (state, _) = try await session(q: 0.25, units: "mrad", kV: 200)
        let oldScale = 0.25 / (1_000 * oldDPCWavelength(kV: 200))
        XCTAssertEqual(oldDPCWavelength(kV: 200), 0.02507865865059979, accuracy: 1e-15)
        let relative = (state.acomScaleSemantics.invAngstromPerPixel - oldScale) / oldScale
        XCTAssertEqual(relative, -2.72e-5, accuracy: 0.08e-5, "mechanism: the wavelength, nothing else")
    }

    /// P-B/P-D: a recipe stored exactly as the pre-W′ code stored it, rewound on the current code.
    /// Red before the fix: "the recorded ACOM run matched at … but the scale in force would be …".
    func testARecipeRecordedBeforeTheWavelengthChangeRewindsWithAnMradQ() async throws {
        let (state, kernel) = try await session(q: 0.25, units: "mrad", kV: 200)
        let oldScale = 0.25 / (1_000 * oldDPCWavelength(kV: 200))
        let acom = recordHistory(state, kernel: kernel, recordedScale: oldScale)
        let refusal = await state.rewindLineage(to: acom)
        XCTAssertNil(refusal, refusal ?? "")
        XCTAssertEqual(state.acomSession.modelSelection, .library("au_fcc"))
    }

    /// P-C, the control: the same recipe with Q entered in Å⁻¹/px never depended on the wavelength.
    func testTheSameRecipeWithAnAngstromQRewinds() async throws {
        let (state, kernel) = try await session(q: 0.01, units: "Å⁻¹", kV: 200)
        let acom = recordHistory(state, kernel: kernel, recordedScale: 0.01)
        let refusal = await state.rewindLineage(to: acom)
        XCTAssertNil(refusal, refusal ?? "")
    }

    // MARK: a real recalibration still refuses (both sites)

    func testARealRecalibrationOf1PerMilleStillRefusesARewind() async throws {
        for factor in [1.001, 0.999] {
            let (state, kernel) = try await session(q: 0.25, units: "mrad", kV: 200)
            let inForce = state.acomScaleSemantics.invAngstromPerPixel
            let acom = recordHistory(state, kernel: kernel, recordedScale: inForce * factor)
            let refusal = await state.rewindLineage(to: acom)
            XCTAssertTrue(try XCTUnwrap(refusal, "factor \(factor) was accepted").contains("scale"), refusal ?? "")
        }
    }

    func testReplayAcceptsThePreWPrimeScaleAndRefusesARealRecalibration() async throws {
        let (state, _) = try await session(q: 0.25, units: "mrad", kV: 200)
        func plan(_ scale: Double) -> ReplayStepPlan.ACOMReplayPlan {
            ReplayStepPlan.ACOMReplayPlan(materialID: "au_fcc", latticeA: nil, scaleInvAngstromPerPixel: scale,
                                          scope: .fullScan, quality: .fast)
        }
        let oldScale = 0.25 / (1_000 * oldDPCWavelength(kV: 200))
        XCTAssertNil(state.replayScaleRefusal(plan(oldScale)))
        let inForce = state.acomScaleSemantics.invAngstromPerPixel
        for factor in [1.001, 0.999] {
            let text = try XCTUnwrap(state.replayScaleRefusal(plan(inForce * factor)), "factor \(factor) was accepted")
            XCTAssertTrue(text.contains("different scale"), text)
        }
    }

    // MARK: the comparison itself

    func testTheScaleToleranceIsOneHundredPpmRelativeBothWays() {
        let plan = ReplayStepPlan.ACOMReplayPlan(materialID: "x", latticeA: nil, scaleInvAngstromPerPixel: 0.0125,
                                                 scope: .fullScan, quality: .fast)
        XCTAssertEqual(ReplayStepPlan.ACOMReplayPlan.scaleRelativeTolerance, 1e-4)
        for factor in [1.0, 1 - 2.72e-5, 1 + 2.72e-5, 1 + 0.99e-4, 1 - 0.99e-4] {
            XCTAssertTrue(plan.agrees(withScaleInForce: 0.0125 * factor), "\(factor)")
        }
        for factor in [1 + 1.5e-4, 1 - 1.5e-4, 1.001, 0.999, 2, 0.5] {
            XCTAssertFalse(plan.agrees(withScaleInForce: 0.0125 * factor), "\(factor)")
        }
        XCTAssertFalse(plan.agrees(withScaleInForce: .nan))
        XCTAssertFalse(plan.agrees(withScaleInForce: .infinity))
    }
}
