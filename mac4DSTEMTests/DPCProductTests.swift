import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Seam 4 (docs/archive/v4/appstate-seams-plan.md), the last of the night's four
/// unattended seams: `DPCProduct` owns the DPC display choice
/// (`dpcDisplay`). The display derivation that used to run directly from
/// `dpcDisplay`'s `didSet` now reaches AppState through `onDisplayChange`,
/// the same hook shape `DiskDetectionProduct.onParamsChange` and
/// `PhaseContrastProduct`/`ACOMSession` use for effects that need the
/// window. These pin: construction defaults, a mutation through direct
/// assignment (the owner has no other mutator — `dpcDisplay` is its only
/// stored state), and the hook firing exactly once per assignment.
@MainActor
final class DPCProductTests: XCTestCase {

    func testConstructionDefaultsToMagnitude() {
        let dpc = DPCProduct()
        XCTAssertEqual(dpc.dpcDisplay, .magnitude,
                       "a fresh owner starts with the same default the pre-seam AppState field did")
    }

    /// `dpcDisplay` has no separate mutator method — the property write IS
    /// the mutation, same as the pre-seam field.
    func testAssigningDpcDisplayChangesTheValue() {
        let dpc = DPCProduct()

        dpc.dpcDisplay = .idpc

        XCTAssertEqual(dpc.dpcDisplay, .idpc)
    }

    /// The relocated `didSet`: AppState installs a hook for the effect that
    /// needs the window (`applyDPCDisplay()`); this pins that the observer
    /// fires exactly once per assignment, same-value writes included (the
    /// pre-seam `didSet` ran unconditionally on every write, never gated on
    /// `oldValue`).
    func testAssigningDpcDisplaySignalsTheHookOnce() {
        let dpc = DPCProduct()
        var signalled = 0
        dpc.onDisplayChange = { signalled += 1 }

        dpc.dpcDisplay = .angle

        XCTAssertEqual(signalled, 1,
                       "applyDPCDisplay must reach AppState through the hook")
    }

    /// Same-value writes still fire — the pre-seam `didSet` had no
    /// `oldValue` guard, and the hook relocation must not add one.
    func testAssigningTheSameDpcDisplayValueStillSignals() {
        let dpc = DPCProduct()
        var signalled = 0
        dpc.onDisplayChange = { signalled += 1 }

        dpc.dpcDisplay = .magnitude   // same as the default

        XCTAssertEqual(signalled, 1)
    }

    /// Through a real AppState (the S5-F8 lesson: wiring must be pinned
    /// where it lives, not on a lookalike): `AppState.init` wires the hook to
    /// `applyDPCDisplay()`, the pre-seam `didSet` body unchanged.
    func testAppStateHoldsTheSeamWithoutForwardingProperties() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("dpc"), "the facade holds the seam")
        XCTAssertFalse(names.contains("dpcDisplay"),
                       "no dpcDisplay stored property may shadow the seam")
    }

    /// A DPC product in milliradians derives from the Q scale at display time,
    /// so a Q change re-derives it (the rotation rule) instead of leaving the
    /// old scale on screen under a current badge. Mutation it catches: a Q
    /// setter that does not re-derive the displayed DPC product.
    func testAQChangeRederivesTheDisplayedDPCMagnitudeInMilliradians() async throws {
        let app = AppState()
        await app.openDemoFixture(calibrated: true)
        if app.calibrationSession.acceleratingVoltage == nil { app.calibrationSession.acceleratingVoltage = 300 }
        app.navigation.analysisMode = .dpc
        _ = await app.runDPC()
        app.dpc.dpcDisplay = .magnitudeMrad
        let before = try XCTUnwrap(app.resultPresentation.product, app.statusText)
        XCTAssertEqual(before.kind, "dpc_magnitude_mrad", "precondition: a physical Q scale and a voltage")
        guard case .scalar(let old) = before.payload else { return XCTFail("scalar payload expected") }
        let scale1 = try XCTUnwrap(app.dpcMilliradiansPerDetectorPixel)
        let q = try XCTUnwrap(app.calibrationSession.calibration.qPixelSize)

        app.setManualQPixelSize(q * 2)
        let scale2 = try XCTUnwrap(app.dpcMilliradiansPerDetectorPixel)
        XCTAssertEqual(Double(scale2 / scale1), 2, accuracy: 1e-3, "precondition: the scale doubled")
        let after = try XCTUnwrap(app.resultPresentation.product)
        guard case .scalar(let new) = after.payload else { return XCTFail("scalar payload expected") }
        let i = try XCTUnwrap(old.pixels.indices.max { old.pixels[$0] < old.pixels[$1] })
        XCTAssertGreaterThan(old.pixels[i], 0)
        XCTAssertEqual(Double(new.pixels[i] / old.pixels[i]), Double(scale2 / scale1), accuracy: 1e-3,
                       "the displayed magnitude follows the new Q scale")
    }

    private func dpcOnScreen(_ display: DPCDisplayMode) async throws -> AppState {
        let app = AppState()
        await app.openDemoFixture(calibrated: true)
        app.navigation.analysisMode = .dpc
        _ = await app.runDPC()
        app.dpc.dpcDisplay = display
        return app
    }

    /// Clear Calibration takes the Q scale away: a shown "DPC magnitude
    /// (mrad)" must not keep it. Mutation it catches: no re-derive in Clear.
    func testClearCalibrationRederivesTheDisplayedDPCWithoutTheOldScale() async throws {
        let app = try await dpcOnScreen(.magnitudeMrad)
        XCTAssertEqual(app.resultPresentation.product?.kind, "dpc_magnitude_mrad", "precondition")
        app.clearCalibration()
        XCTAssertEqual(app.resultPresentation.product?.kind, "dpc_magnitude", "no scale, no mrad")
    }

    /// A saved DPC map shown from the sidecar is its file's record: a Q edit
    /// must not overwrite it with the live field. Mutation it catches: the
    /// re-derive guarded on the kind alone.
    func testAQEditLeavesASavedDPCMapShownFromTheSidecarAlone() async throws {
        let app = try await dpcOnScreen(.magnitudeMrad)
        let live = try XCTUnwrap(app.resultPresentation.product)
        app.publishRestoredProduct(
            kind: live.kind, displayName: live.displayName, valueUnits: live.valueUnits, payload: live.payload,
            pixelSizeRow: live.sampling.row, pixelSizeColumn: live.sampling.column, pixelUnits: live.sampling.units,
            provenance: live.provenance)
        let q = try XCTUnwrap(app.calibrationSession.calibration.qPixelSize)
        app.setManualQPixelSize(q * 2)
        XCTAssertEqual(app.resultPresentation.product?.origin, .restoredFromSidecar)
    }

    /// Physical iDPC integrates with the real-space sampling: an R change
    /// re-derives it. Mutation it catches: an R setter without the re-derive.
    func testAnRChangeRederivesTheDisplayedPhysicalIDPC() async throws {
        let app = try await dpcOnScreen(.idpc)
        let before = try XCTUnwrap(app.resultPresentation.product, app.statusText)
        XCTAssertEqual(before.kind, "idpc_phase", "precondition: physical iDPC on the calibrated demo")
        let row = try XCTUnwrap(before.sampling.row)
        let r = try XCTUnwrap(app.calibrationSession.calibration.rPixelSize)
        app.setManualRPixelSize(r * 2)
        let after = try XCTUnwrap(app.resultPresentation.product)
        XCTAssertEqual(try XCTUnwrap(after.sampling.row) / row, 2, accuracy: 1e-6)
    }
}
