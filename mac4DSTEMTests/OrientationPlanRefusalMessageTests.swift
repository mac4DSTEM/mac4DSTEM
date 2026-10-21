import XCTest
import DiffractoCore
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane F item 4 (tier 2, wording and a failure path, no number moves): when the kit refuses the reflection list, "Generate
/// plan" used to say only "Could not generate an orientation plan."; it now names the cause. `OrientationPlan.generate` still
/// returns nil for the refusal (unchanged); `refusalReason` is asked only on that failure path.
@MainActor
final class OrientationPlanRefusalMessageTests: XCTestCase {

    private let kMax = 1.2

    /// fcc Al in a 150 A cube: about 2.4e7 reflections at 1.2 A^-1, over the kit's 10 000 000 (cellTooLargeOrInvalid).
    private func hugeCell() -> CrystalStructure { CrystalPresets.cubic(.fcc, a: 150, z: 13) }

    func testALargeCellIsNamedAsTooLargeForTheKRange() throws {
        let text = try XCTUnwrap(OrientationPlan.refusalReason(crystal: hugeCell(), kMax: kMax))
        XCTAssertTrue(text.contains("too large"), text)
        XCTAssertTrue(text.contains("1.2"), "names the k range: \(text)")
        XCTAssertTrue(text.contains("smaller cell"), "says what to do: \(text)")
        XCTAssertNil(OrientationPlan.generate(crystal: hugeCell(), kMax: kMax, zoneAxisCount: 4, symmetry: .cubic),
                     "the refusal still yields no plan")
    }

    func testAnOrdinaryCellHasNoRefusal() {
        XCTAssertNil(OrientationPlan.refusalReason(crystal: CrystalPresets.cubic(.fcc, a: 4.05, z: 13), kMax: kMax))
    }

    func testAnUnsupportedElementIsNamedByTheKit() throws {
        let text = try XCTUnwrap(OrientationPlan.refusalReason(crystal: CrystalPresets.cubic(.fcc, a: 4.05, z: 150), kMax: kMax))
        XCTAssertTrue(text.contains("150"), text)
    }

    /// Through the button's own path: the status line carries the cause, not just the generic sentence.
    func testGeneratePlanOnALargeCellShowsTheCause() async {
        let state = AppState()
        await state.openDemoFixture()
        state.acomSession.customStructure = .fcc
        state.acomSession.customZ = 13
        state.acomSession.customLatticeA = 150
        state.acomSession.modelSelection = .customCubic
        await state.generateOrientationPlan()
        XCTAssertTrue(state.statusText.contains("Could not generate an orientation plan."), state.statusText)
        XCTAssertTrue(state.statusText.contains("too large"), state.statusText)
        XCTAssertFalse(state.acomSession.hasOrientationPlan)
    }
}
