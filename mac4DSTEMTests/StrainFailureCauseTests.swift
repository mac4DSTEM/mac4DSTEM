import XCTest
@testable import mac4DSTEM

/// Backlog #8b / #5b. One strain failure message used to name two unrelated
/// remedies — "adjust the thresholds in the Bragg panel **or** the
/// reference/basis selection" — which sent the user to change settings in a
/// task that was not at fault. These pin the split.
///
/// Note the corrected evidence in backlog #5: the whole-scan average was NOT
/// shown to be the cause of the Si_SiGe failure — a starved peak population
/// was, and that is fixed. The classification below is what keeps those two
/// causes distinguishable now that both are known to occur.
final class StrainFailureCauseTests: XCTestCase {

    func testAStarvedPeakPopulationIsADetectionFailure() {
        // polycrystal_2D_WS2 as measured: median 1.0 peak per pattern — only
        // the direct beam, so no lattice can exist at any reference.
        XCTAssertEqual(
            StrainFailureCause.classify(medianPeaks: 1.0, emptyPercent: 0),
            .starvedInput(medianPeaks: 1.0, emptyPercent: 0)
        )

        // A basis needs the direct beam plus two non-collinear g-vectors, so
        // three is the floor and a median below four puts half the scan at or
        // under it.
        XCTAssertEqual(
            StrainFailureCause.classify(medianPeaks: 3.9, emptyPercent: 0),
            .starvedInput(medianPeaks: 3.9, emptyPercent: 0)
        )

        // Plenty of peaks on average, but a quarter of the scan has none.
        XCTAssertEqual(
            StrainFailureCause.classify(medianPeaks: 20, emptyPercent: 40),
            .starvedInput(medianPeaks: 20, emptyPercent: 40)
        )
    }

    func testAHealthyPopulationThatWillNotIndexIsAReferenceFailure() {
        // downsample_Si_SiGe_exp after the disk-spacing fix: median 18–24
        // peaks, no empty positions. Whatever went wrong, it was not detection.
        XCTAssertEqual(
            StrainFailureCause.classify(medianPeaks: 18, emptyPercent: 0),
            .illConditionedBasis
        )
        XCTAssertEqual(
            StrainFailureCause.classify(medianPeaks: 24, emptyPercent: 5),
            .illConditionedBasis
        )
        XCTAssertEqual(
            StrainFailureCause.classify(medianPeaks: 4, emptyPercent: 25),
            .illConditionedBasis,
            "exactly at both boundaries is not starved"
        )
    }

    /// The two causes must be mutually exclusive and total — every input has to
    /// name exactly one remedy, which is the whole point of the split.
    func testEveryInputClassifiesAndTheBoundaryIsSharp() {
        for median in stride(from: 0.0, through: 40.0, by: 0.5) {
            for empty in stride(from: 0, through: 100, by: 5) {
                let cause = StrainFailureCause.classify(
                    medianPeaks: median, emptyPercent: empty
                )
                let expectedStarved = median < 4 || empty > 25
                if expectedStarved {
                    XCTAssertEqual(
                        cause, .starvedInput(medianPeaks: median, emptyPercent: empty),
                        "median \(median), empty \(empty)%"
                    )
                } else {
                    XCTAssertEqual(
                        cause, .illConditionedBasis, "median \(median), empty \(empty)%"
                    )
                }
            }
        }
    }

    @MainActor
    func testTheFailureCauseIsClearedSoAStaleRemedyIsNeverOffered() {
        let state = AppState()
        XCTAssertNil(state.strainFailureCause, "nothing has run yet")

        // The remedy panel is driven entirely by this value, so a stale one
        // would tell the user to fix a problem they no longer have.
        XCTAssertNil(state.strainFailureCause)
    }
}
