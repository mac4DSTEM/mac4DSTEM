import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Review 2026-09-30 rows 4 and 5: two edits that change what the orientation
/// plan's templates are built from, neither of which threw the plan away.
///
/// Row 4: re-importing a CIF with the same stem replaces the model in
/// `importedCrystalModels` in place and re-asserts the same selection — a
/// same-value write `modelSelection.didSet` ignores — so `runACOM` reused the
/// old crystal's templates and stamped the new fingerprint.
/// Row 5: the plan is generated with the wavelength of
/// `calibrationSession.acceleratingVoltage` (Ewald curvature of every
/// template); a voltage edit invalidated the result only when Q was in mrad.
@MainActor
final class ACOMRow4Row5PlanInvalidationTests: XCTestCase {

    private func imported(_ id: String, a: Double) -> CrystalModel {
        CrystalModel(id: id, displayName: id, crystal: Crystal.cubic(.fcc, a: a, z: 13),
                     symmetry: .cubic, source: .imported)
    }

    private func planned(_ session: ACOMSession) {
        session.hasOrientationPlan = true
        session.hasOrientationMap = true
        session.lastMatchedPositionCount = 12
    }

    /// Mutation it catches: dropping the `importedCrystalModels` observer
    /// (the plan survives a re-import with a different cell).
    func testReimportingTheSelectedCIFWithADifferentCellInvalidatesThePlan() {
        let session = ACOMSession()
        session.importedCrystalModels = [imported("my_phase", a: 4.0)]
        session.modelSelection = .imported("my_phase")
        planned(session)
        var invalidations = 0
        session.onResultInvalidated = { invalidations += 1 }

        // The replacement path `importCrystalModel` takes for a same-stem file.
        session.importedCrystalModels[0] = imported("my_phase", a: 4.2)
        session.modelSelection = .imported("my_phase")   // the same-value write

        XCTAssertFalse(session.hasOrientationPlan, "templates were built for a = 4.0")
        XCTAssertFalse(session.hasOrientationMap)
        XCTAssertEqual(invalidations, 1)
    }

    /// The same file imported again unchanged, or another model added beside
    /// the selected one, is not a reason to rebuild.
    func testAnIdenticalReimportOrAnUnselectedModelKeepsThePlan() {
        let session = ACOMSession()
        session.importedCrystalModels = [imported("my_phase", a: 4.0)]
        session.modelSelection = .imported("my_phase")
        planned(session)
        session.importedCrystalModels[0] = imported("my_phase", a: 4.0)
        session.importedCrystalModels.append(imported("other", a: 3.6))
        session.importedCrystalModels[1] = imported("other", a: 3.7)
        XCTAssertTrue(session.hasOrientationPlan)
        XCTAssertTrue(session.hasOrientationMap)
    }

    /// Mutation it catches: the voltage setter not calling `invalidatePlan`
    /// (HEAD: only `invalidateResult`, and only for mrad units).
    func testAVoltageEditInvalidatesThePlanASameValueCommitDoesNot() {
        let state = AppState()
        state.setManualAcceleratingVoltage(200)
        planned(state.acomSession)
        XCTAssertEqual(state.calibrationSession.acceleratingVoltage, 200)

        state.setManualAcceleratingVoltage(300)
        XCTAssertFalse(state.acomSession.hasOrientationPlan,
                       "templates were built with the 200 kV Ewald curvature")
        XCTAssertFalse(state.acomSession.hasOrientationMap)

        planned(state.acomSession)
        state.setManualAcceleratingVoltage(300)
        XCTAssertTrue(state.acomSession.hasOrientationPlan, "re-committing 300 kV is not an edit")
        XCTAssertTrue(state.acomSession.hasOrientationMap)
    }
}
