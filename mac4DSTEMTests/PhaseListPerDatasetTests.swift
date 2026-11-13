import XCTest
import DiffractoCore
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#294: every dataset is individual. The phase list of one file (its phases and their excitation slabs) did not
/// go when the next file opened, and Map Phases then refused the doubled matrix once the new file's phases were added.
@MainActor
final class PhaseListPerDatasetTests: XCTestCase {

    /// Two datasets in sequence: the second starts with an empty phase list, and adding its matrix makes a list that runs.
    /// Red before the fix: the first file's Al and β″ (with its slab) were still listed. Break it by deleting the line
    /// that empties `phaseMapping.phases` in `activate`.
    func testASecondDatasetStartsWithAnEmptyPhaseList() async throws {
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertNotNil(state.descriptor, state.statusText)
        let al = try XCTUnwrap(CrystalModelLibrary.model(id: "al_fcc"))
        let beta = CrystalModel(id: "preset_betaDoublePrime", displayName: "betaDoublePrime",
                                structure: CrystalPresets.betaDoublePrime, symmetry: .monoclinic, source: .builtIn)
        state.addPhaseMappingSlot(al)
        state.addPhaseMappingSlot(beta)
        XCTAssertEqual(state.phaseMapping.phases.count, 2, "precondition")

        await state.openDemoFixture(calibrated: false)
        XCTAssertNotNil(state.descriptor, state.statusText)
        XCTAssertEqual(state.phaseMapping.phases.map(\.model.id), [], "the first dataset's phases carried over")

        state.addPhaseMappingSlot(al)
        XCTAssertEqual(state.phaseMapping.phases.filter(\.isMatrix).map(\.model.id), [al.id], "one matrix, the new one")
    }
}
