import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// S22c seam: navigation/selection state (workspace, task, pane visibility)
/// lives on `WorkspaceNavigation`, held by `AppState` as `navigation` — the
/// same no-forwarding contract `StrainProductTests` pins for `strain`, with
/// the same known limit: `Mirror` sees stored properties only, so a computed
/// forwarder is caught by review, not here.
@MainActor
final class NavigationSeamTests: XCTestCase {

    func testAppStateHoldsTheNavigationSeamWithoutForwardingProperties() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("navigation"), "the facade holds the seam")
        let forbidden = ["workspaceArea", "analysisMode", "showToolsPane",
                         "showLogPane", "showInspectorPane", "focusedPane"]
        let shadows = forbidden.filter(names.contains)
        XCTAssertTrue(
            shadows.isEmpty,
            "navigation state may not shadow the seam on AppState: \(shadows)"
        )
    }

    /// The recovery hook keeps the exact semantics of the stored property's
    /// old didSet: fire on actual task changes, and only on those — a
    /// same-value write persisting recovery on every render would be the
    /// regression this pins against.
    func testModeChangeFiresTheRecoveryHookExactlyOnActualChanges() {
        let nav = WorkspaceNavigation()
        var fires = 0
        nav.onModeChange = { fires += 1 }
        nav.analysisMode = .virtualDetector
        XCTAssertEqual(fires, 0, "a same-value write must not fire the hook")
        nav.analysisMode = .dpc
        XCTAssertEqual(fires, 1, "an actual change fires the hook once")
        nav.analysisMode = .dpc
        XCTAssertEqual(fires, 1, "writing the current value again stays quiet")
    }
}
