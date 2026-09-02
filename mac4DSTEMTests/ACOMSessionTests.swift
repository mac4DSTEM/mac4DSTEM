import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// v2.5 step 7c 4b: `ACOMSession` owns the ACOM state, the plan and map, and
/// their invalidation; the effects that need the window reach `AppState`
/// through hooks. The forwarders that used to carry these rules are gone, so
/// the rules are pinned here on the owner.
@MainActor
final class ACOMSessionTests: XCTestCase {

    private func sessionWithPlanAndMap() -> ACOMSession {
        let session = ACOMSession()
        session.hasOrientationPlan = true
        session.hasOrientationMap = true
        session.lastRunScope = .preview
        session.lastRunQuality = .fast
        session.lastMatchedPositionCount = 12
        return session
    }

    func testADifferentCrystalOrQualityInvalidatesThePlanAndTheMap() {
        for mutate in [
            { (s: ACOMSession) in s.modelSelection = .customCubic },
            { (s: ACOMSession) in s.quality = .fast },
            { (s: ACOMSession) in s.customZ = 6 },
            { (s: ACOMSession) in s.customStructure = .bcc },
            { (s: ACOMSession) in s.customLatticeA = 2.87 },
        ] {
            let session = sessionWithPlanAndMap()
            var invalidations = 0
            session.onResultInvalidated = { invalidations += 1 }
            mutate(session)
            XCTAssertFalse(session.hasOrientationPlan)
            XCTAssertFalse(session.hasOrientationMap)
            XCTAssertNil(session.lastRunScope)
            XCTAssertNil(session.lastMatchedPositionCount)
            XCTAssertEqual(invalidations, 1, "the published product is AppState's to clear — once")
        }
    }

    func testADifferentScaleInvalidatesTheMapButKeepsThePlan() {
        let session = sessionWithPlanAndMap()
        session.exploratoryScale = 0.02
        XCTAssertTrue(session.hasOrientationPlan, "the template library does not depend on the scale")
        XCTAssertFalse(session.hasOrientationMap)
    }

    /// The setters this replaces were silent on same-value writes; a picker
    /// re-selecting the current crystal must not throw the map away.
    func testSameValueWritesInvalidateNothing() {
        let session = sessionWithPlanAndMap()
        var invalidations = 0
        session.onResultInvalidated = { invalidations += 1 }
        session.modelSelection = session.modelSelection
        session.quality = session.quality
        session.exploratoryScale = session.exploratoryScale
        session.customZ = session.customZ
        session.reliabilityThreshold = session.reliabilityThreshold
        XCTAssertTrue(session.hasOrientationPlan)
        XCTAssertTrue(session.hasOrientationMap)
        XCTAssertEqual(invalidations, 0)
    }

    func testScopeAndDisplayWritesReachTheirHooksEveryTime() {
        let session = ACOMSession()
        var scopes: [ACOMRunScope] = []
        var displayRefreshes = 0
        session.onScopeChange = { scopes.append($0) }
        session.onDisplayChange = { displayRefreshes += 1 }
        session.scope = .fullScan
        session.scope = .fullScan   // the old setter re-ran its effect on every write
        session.display = .ipfZ
        session.reliabilityThreshold = 0.4
        session.reliabilityThreshold = 0.4   // the old setter was change-gated here
        XCTAssertEqual(scopes, [.fullScan, .fullScan])
        XCTAssertEqual(displayRefreshes, 2)
    }

    /// The seam contract: AppState holds the session and no stored shadow of
    /// its state. `Mirror` sees stored properties only, so a computed
    /// forwarder is caught by review, not here (same limit as
    /// `NavigationSeamTests`).
    func testAppStateHoldsNoStoredACOMState() {
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("acomSession"))
        let shadows = ["orientationPlan", "orientationMap", "hasOrientationPlan", "hasOrientationMap",
                       "acomScope", "acomDisplay", "acomModelSelection"].filter(names.contains)
        XCTAssertTrue(shadows.isEmpty, "ACOM state may not shadow the session on AppState: \(shadows)")
    }

    /// AppState's wiring: a scope of `.selectedRegion` puts the region on the
    /// real-space pane; leaving it clears the selection.
    func testAppStateWiresTheScopeHook() {
        let state = AppState()
        state.acomSession.scope = .selectedRegion
        XCTAssertTrue(state.acomSession.regionSelectionActive)
        XCTAssertEqual(state.realSpaceShape, .rectangle)
        XCTAssertEqual(Int(state.realSpaceRadius), state.acomSession.regionRadius)
        state.acomSession.scope = .preview
        XCTAssertFalse(state.acomSession.regionSelectionActive)
    }
}
