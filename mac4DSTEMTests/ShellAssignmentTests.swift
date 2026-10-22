import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The ring-sequence assignment of the known-crystal Q calibration, against planted truth (calibration design 2026-10-22, section 6).
/// No Python reference exists for it; every number below is a closed form.
final class ShellAssignmentTests: XCTestCase {
    private static let a = 4.0495
    /// Al's distinct shells, 1/d in Å⁻¹: 111, 200, 220, 311, 222, 400.
    private static let al: [Double] = [3.0, 4.0, 8.0, 11.0, 12.0, 16.0].map { $0.squareRoot() / a }
    private static let alLabels = ["{111}", "{200}", "{220}", "{311}", "{222}", "{400}"]
    private static let deltaQ = 0.0100

    /// Radii (px) of the Al [001] rings {200}, {220}, {400} at Δq = 0.0100, the same at every one of 25 positions.
    private static var plantedRadii: [Double] { [al[1], al[2], al[5]].map { $0 / deltaQ } }

    private func positions(_ rings: [Double], count: Int = 25, noise: Double = 0, seed: UInt64 = 1, descan: Double = 0) -> [[Double]] {
        var state = seed
        func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
        return (0..<count).map { _ in
            let shift = descan * uniform()
            return rings.flatMap { r in (0..<4).map { k in r + shift * (k % 2 == 0 ? 1 : -1) + noise * uniform() } }
        }
    }

    private func assign(_ radii: [[Double]], shells: [Double] = al, labels: [String]? = alLabels, prior: Double? = nil) -> ShellAssignment.Outcome? {
        ShellAssignment.assign(radiiPerPosition: radii, shellLengths: shells, labels: labels, crystalName: "Al", priorScale: prior)
    }

    private func assigned(_ outcome: ShellAssignment.Outcome?, file: StaticString = #filePath, line: UInt = #line) throws -> ShellAssignment.Assigned {
        guard case .assigned(let a)? = outcome else { XCTFail("not assigned: \(String(describing: outcome))", file: file, line: line); throw XCTSkip("") }
        return a
    }

    /// Case 2: the first visible ring of Al [001] is {200} (shell 1), Δq recovers to 1e-9 with no noise.
    func testAl001FirstRingIsTwoHundredAndDeltaQRecovers() throws {
        let result = try assigned(assign(positions(Self.plantedRadii)))
        XCTAssertEqual(result.shellIndex, 1)
        XCTAssertEqual(result.label, "{200}")
        XCTAssertEqual(result.matchedRings, 3)
        XCTAssertEqual(result.observedRings, 3)
        XCTAssertTrue(result.isChecked)
        let scale = result.referenceRadiusInvAngstrom / result.observedRadiiPixels[0]
        XCTAssertEqual(scale, Self.deltaQ, accuracy: 1e-9 * Self.deltaQ)
        // The second ring was matched to {220}.
        XCTAssertEqual(try XCTUnwrap(result.nextShellInvAngstrom), Self.al[2], accuracy: 1e-12)
    }

    /// The same with ±0.3 px on every peak and with a 1 px descan: Δq within 0.5 %.
    func testAl001WithNoiseAndDescan() throws {
        for radii in [positions(Self.plantedRadii, noise: 0.3, seed: 7), positions(Self.plantedRadii, seed: 11, descan: 1.0)] {
            let result = try assigned(assign(radii))
            XCTAssertEqual(result.shellIndex, 1)
            XCTAssertEqual(result.matchedRings, 3)
            let scale = result.referenceRadiusInvAngstrom / result.observedRadiiPixels[0]
            XCTAssertEqual(scale, Self.deltaQ, accuracy: 0.005 * Self.deltaQ)
        }
    }

    /// A cubic crystal's rings in the ratio 1 : √2 : 2 fit two starting shells with a long shell list ({200}, {220}, {400} and
    /// {220}, {400}, {440}); the shell window keeps the match to the low-order shells, so {200} wins. Break it by passing the whole
    /// list to the matcher.
    func testSelfSimilarRingsAreNotAmbiguousBecauseHigherShellsAreOutsideTheWindow() throws {
        let longList = [3.0, 4, 8, 11, 12, 16, 19, 20, 24, 27, 32, 35, 36, 40].map { $0.squareRoot() / Self.a }
        let result = try assigned(assign(positions(Self.plantedRadii), shells: longList, labels: nil))
        XCTAssertEqual(result.shellIndex, 1)
        XCTAssertEqual(result.matchedRings, 3)
    }

    /// The healthy case stays as it was: rings {111}, {200}, {220} read as the first three shells.
    func testRingsFromTheFirstShellStayAssignedToIt() throws {
        let rings = [Self.al[0], Self.al[1], Self.al[2]].map { $0 / 0.0125 }
        let result = try assigned(assign(positions(rings)))
        XCTAssertEqual(result.shellIndex, 0)
        XCTAssertEqual(result.matchedRings, 3)
    }

    /// Case 3: shells [1, √2, 2, 2√2] and rings in the ratio 1 : √2: H0 and H1 both match both rings with no misfit, so it refuses
    /// and names both.
    func testTwoEquallyGoodAssignmentsAreRefusedAndNamed() {
        let shells = [1.0, 2.0.squareRoot(), 2.0, 8.0.squareRoot()]
        let radii = positions([40, 40 * 2.0.squareRoot()])
        guard case .refused(let sentence)? = assign(radii, shells: shells, labels: ["{A}", "{B}", "{C}", "{D}"]) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertTrue(sentence.contains("Two assignments fit equally well"), sentence)
        XCTAssertTrue(sentence.contains("{A}") && sentence.contains("{B}"), sentence)
    }

    /// Case 4: ratios 1 : 1.3 match no starting shell of Al.
    func testRingsThatMatchNoStartingShellAreRefused() {
        guard case .refused(let sentence)? = assign(positions([50, 65])) else { return XCTFail("expected a refusal") }
        XCTAssertTrue(sentence.hasPrefix("The rings do not match any starting shell of Al"), sentence)
        XCTAssertTrue(sentence.contains("1.30"), sentence)
        XCTAssertTrue(sentence.contains("1.16, 1.63 ({111} first)") || sentence.contains("1.15, 1.63 ({111} first)")
                      || sentence.contains("({111} first)"), sentence)
        XCTAssertTrue(sentence.contains("({200} first)"), sentence)
    }

    /// Case 5: one ring cannot be tested: shell 0 is assumed, no refusal, not checked.
    func testASingleRingIsAssumedToBeTheFirstShellAndNotChecked() throws {
        let result = try assigned(assign(positions([Self.al[0] / Self.deltaQ])))
        XCTAssertEqual(result.shellIndex, 0)
        XCTAssertFalse(result.isChecked)
        XCTAssertEqual(result.observedRings, 1)
    }

    /// A prior scale breaks the single-ring tie only when it singles out exactly one shell within 10 %; it never overrides a
    /// checked sequence.
    func testAPriorScaleBreaksOnlyTheSingleRingTie() throws {
        let one = positions([Self.al[1] / Self.deltaQ])
        XCTAssertEqual(try assigned(assign(one, prior: 0.0100)).shellIndex, 1)
        XCTAssertEqual(try assigned(assign(one, prior: 0.0090)).shellIndex, 0, "the prior agrees with shell 0 only")
        XCTAssertEqual(try assigned(assign(one, prior: 5)).shellIndex, 0, "a prior that agrees with nothing leaves shell 0")
        // The sequence wins over a prior that points at shell 0.
        let three = positions(Self.plantedRadii)
        XCTAssertEqual(try assigned(assign(three, prior: 0.00866)).shellIndex, 1)
    }

    func testNoUsableRadiusGivesNil() {
        XCTAssertNil(assign([[], [1, .nan]]))
        XCTAssertNil(ShellAssignment.assign(radiiPerPosition: [[50]], shellLengths: [], priorScale: nil))
    }

    func testLabelsAreWrittenCompactWhenEveryIndexIsOneDigit() {
        XCTAssertEqual(ShellAssignment.compactLabel("{2 0 0}"), "{200}")
        XCTAssertEqual(ShellAssignment.compactLabel("{1 0 -1 1}"), "{1 0 -1 1}")
        XCTAssertEqual(ShellAssignment.compactLabel("{3 3 3} + {5 1 1}"), "{3 3 3} + {5 1 1}")
        XCTAssertEqual(ShellAssignment.compactLabel("{10 0 0}"), "{10 0 0}")
    }
}
