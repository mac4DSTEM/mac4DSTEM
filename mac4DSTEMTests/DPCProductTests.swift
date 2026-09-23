import XCTest
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
}
