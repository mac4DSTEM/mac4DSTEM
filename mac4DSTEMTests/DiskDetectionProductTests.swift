import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Seam 3 (docs/archive/v4/appstate-seams-plan.md): `DiskDetectionProduct` owns
/// `diskParams` and its pure size-aware defaulting; the live-overlay refresh
/// that used to run directly from `diskParams`'s `didSet` now reaches
/// AppState through `onParamsChange`, the same hook shape
/// `PhaseContrastProduct`/`ACOMSession` use for effects that need the
/// window. These pin: construction defaults, `reset`/`refreshForMeasuredProbe`
/// mutating through the owner's own methods, and the hook firing exactly
/// once per `didSet`.
@MainActor
final class DiskDetectionProductTests: XCTestCase {

    func testConstructionDefaultsToStandardParams() {
        let diskDetection = DiskDetectionProduct()
        XCTAssertEqual(diskDetection.diskParams, DiskDetectionParams(),
                       "a fresh owner starts with the same defaults the pre-seam AppState field did")
        XCTAssertFalse(diskDetection.liveDetectionInFlight)
        XCTAssertFalse(diskDetection.liveDetectionPending)
    }

    /// `reset` is the pure half of the pre-seam `resetDiskDetectionParams()`
    /// — the caller resolves `descriptor.qy/qx` and the fitted probe radius;
    /// this owner only ever sees the resolved numbers.
    func testResetBuildsSizeAwareDefaultsFromTheGivenProbeRadius() {
        let diskDetection = DiskDetectionProduct()

        diskDetection.reset(qy: 128, qx: 128, probeRadius: 8)

        let expected = DiskDetectionParams.detectorAdapted(qy: 128, qx: 128, probeRadius: 8)
        XCTAssertEqual(diskDetection.diskParams, expected)
    }

    /// `refreshForMeasuredProbe` only replaces the minimum spacing when it is
    /// still at the placeholder value — a user's own choice must survive a
    /// later probe measurement (the pre-seam docstring's exact contract).
    func testRefreshForMeasuredProbeLeavesAUserChosenSpacingAlone() {
        let diskDetection = DiskDetectionProduct()
        diskDetection.reset(qy: 128, qx: 128, probeRadius: nil)
        diskDetection.diskParams.minPeakSpacing = 42

        diskDetection.refreshForMeasuredProbe(qy: 128, qx: 128, probeRadius: 6)

        XCTAssertEqual(diskDetection.diskParams.minPeakSpacing, 42,
                       "a spacing the user touched must not be overwritten by a later probe measurement")
    }

    func testRefreshForMeasuredProbeAdoptsTheProbeScaledSpacingWhenUntouched() {
        let diskDetection = DiskDetectionProduct()
        diskDetection.reset(qy: 128, qx: 128, probeRadius: nil)
        let placeholderSpacing = diskDetection.diskParams.minPeakSpacing

        diskDetection.refreshForMeasuredProbe(qy: 128, qx: 128, probeRadius: 6)

        let expected = DiskDetectionParams.detectorAdapted(qy: 128, qx: 128, probeRadius: 6).minPeakSpacing
        XCTAssertEqual(diskDetection.diskParams.minPeakSpacing, expected)
        XCTAssertNotEqual(diskDetection.diskParams.minPeakSpacing, placeholderSpacing,
                          "an untouched placeholder must adopt the probe-scaled value")
    }

    /// The relocated `didSet`: `PhaseContrastProduct`/`ACOMSession` install a
    /// hook for effects that need the window; this pins that the observer
    /// fires exactly once per assignment, same-value writes included (the
    /// pre-seam `didSet` ran unconditionally on every write, never gated on
    /// `oldValue`).
    func testAssigningDiskParamsSignalsTheHookOnce() {
        let diskDetection = DiskDetectionProduct()
        var signalled = 0
        diskDetection.onParamsChange = { signalled += 1 }

        diskDetection.diskParams.maxNumPeaks = 12

        XCTAssertEqual(signalled, 1,
                       "the live overlay must reach AppState's detectCurrentPattern through the hook")
    }

    /// `reset`/`refreshForMeasuredProbe` write `diskParams` through the same
    /// stored property, so they must also reach the hook — a caller that
    /// mutates through the owner's own methods must not be a silent bypass.
    func testResetAlsoSignalsTheHook() {
        let diskDetection = DiskDetectionProduct()
        var signalled = 0
        diskDetection.onParamsChange = { signalled += 1 }

        diskDetection.reset(qy: 128, qx: 128, probeRadius: 8)

        XCTAssertEqual(signalled, 1)
    }

    /// Through a real AppState (the S5-F8 lesson: wiring must be pinned
    /// where it lives, not on a lookalike): `AppState.init` wires the hook to
    /// `detectCurrentPattern()`, the pre-seam `didSet` body unchanged.
    func testAppStateHoldsTheSeamWithoutForwardingProperties() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("diskDetection"), "the facade holds the seam")
        XCTAssertFalse(names.contains("diskParams"),
                       "no diskParams stored property may shadow the seam")
    }
}
