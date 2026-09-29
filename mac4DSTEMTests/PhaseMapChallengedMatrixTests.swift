//
//  PhaseMapChallengedMatrixTests.swift
//  A matrix verdict reached by CHALLENGE (an orientation of the matrix
//  crystal beat every candidate; `matchedCount > 0`) was drawn in the same
//  grey as one reached by EXCLUSION (removal left too little to index;
//  `matchedCount == 0`). They are different facts about the specimen.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class PhaseMapChallengedMatrixTests: XCTestCase {

    private func result(_ verdict: PhaseVerdict, matched: Int32 = 0) -> PhaseVectorResult {
        var r = PhaseVectorResult()
        r.verdict = verdict
        r.phaseIndex = 0
        r.matchedCount = matched
        r.survivingCount = 8
        r.removedCount = 2
        return r
    }

    /// Mutation: the verdict test dropped (an indexed or not-indexed position
    /// with matches called "challenged"), or `> 0` turned into `>= 0`.
    func testOnlyAMatrixVerdictWithMatchesIsChallenged() {
        XCTAssertTrue(PhaseMapPresentation.isChallengedMatrix(result(.matrix, matched: 6)))
        XCTAssertFalse(PhaseMapPresentation.isChallengedMatrix(result(.matrix, matched: 0)))
        XCTAssertFalse(PhaseMapPresentation.isChallengedMatrix(result(.indexed, matched: 6)))
        XCTAssertFalse(PhaseMapPresentation.isChallengedMatrix(result(.notIndexed, matched: 6)))
        XCTAssertFalse(PhaseMapPresentation.isChallengedMatrix(result(.noData, matched: 6)))
    }

    private func map() -> PhaseMap {
        var m = PhaseMap(width: 6, height: 3, matrixEntryIndex: 0,
                         phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        for x in 0..<6 { m.results[x] = result(.matrix, matched: 0) }      // row 0: exclusion
        for x in 0..<6 { m.results[6 + x] = result(.matrix, matched: 5) }  // row 1: challenged
        for x in 0..<6 {                                                   // row 2: a candidate
            m.results[12 + x] = result(.indexed, matched: 5)
            m.results[12 + x].phaseIndex = 1
        }
        return m
    }

    /// Mutation: `image()` painting every matrix verdict `matrixColor` again,
    /// or striping the exclusion route as well.
    func testChallengedMatrixIsStripedAndExclusionIsNot() {
        let image = PhaseMapPresentation.image(map())
        func rgb(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * 6 + x) * 4
            return [image.rgba[i], image.rgba[i + 1], image.rgba[i + 2], image.rgba[i + 3]]
        }
        let ground = PhaseMapPresentation.matrixColor
        let stripe = PhaseMapPresentation.challengedMatrixStripe
        for x in 0..<6 {
            XCTAssertEqual(rgb(x, 0), [ground.r, ground.g, ground.b, 255],
                           "matrix by exclusion keeps the flat matrix grey")
        }
        let row1 = (0..<6).map { rgb($0, 1) }
        XCTAssertTrue(row1.contains([ground.r, ground.g, ground.b, 255]),
                      "a challenged position keeps the matrix ground")
        XCTAssertTrue(row1.contains([stripe.r, stripe.g, stripe.b, 255]),
                      "a challenged position carries the stripe")
        XCTAssertNotEqual(stripe.r, ground.r)
        // Never the light not-indexed hatch, never a candidate hue.
        XCTAssertLessThan(Int(stripe.r), Int(PhaseMapPresentation.notIndexedColors.0.r))
    }

    /// Mutation: the challenged subset moving the verdict counts or the
    /// median explained fraction (the refuted-bar rule, and the phase
    /// fraction, must not change), or the row missing/miscounted.
    func testLegendNamesTheChallengedSubsetWithoutMovingAnyCount() {
        let m = map()
        XCTAssertEqual(m.count(of: .matrix), 12)
        XCTAssertEqual(m.phaseCounts[0], 12, "the matrix row still counts every matrix verdict")
        let rows = PhaseMapPresentation.legend(m)
        let challenged = rows.filter { $0.label.contains("challenged") }
        XCTAssertEqual(challenged.count, 1)
        XCTAssertEqual(challenged.first?.count, 6)
        XCTAssertEqual(rows.first?.label, "Al (matrix)")
        XCTAssertEqual(rows.first?.count, 12)
        XCTAssertEqual(rows[1].label, challenged.first?.label, "sits directly under the matrix row")

        var none = m
        for x in 0..<6 { none.results[6 + x] = result(.matrix, matched: 0) }
        XCTAssertFalse(PhaseMapPresentation.legend(none).contains { $0.label.contains("challenged") },
                       "no challenged position, no row")
    }

    /// The legend swatch of each striped class may carry only tones the map
    /// really paints for that class, and both of them. The map side is read
    /// off the rendered pixels, not from the constants, so a swatch colour
    /// the map never draws (the 2026-09 defect: a solid (98,98,110) and a
    /// flat grey 168 in the legend against stripes on the map) goes red.
    ///
    /// Mutation (turns it red): in `PhaseMapPresentation.legend`, change the
    /// challenged row's `stripe: matrixColor` to `stripe: nil` (or to any
    /// other colour); likewise `stripe: notIndexedColors.1` in the
    /// "Not indexed" row.
    func testStripedLegendRowsCarryExactlyTheTonesTheMapPaints() {
        var m = PhaseMap(width: 6, height: 3, matrixEntryIndex: 0,
                         phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        for x in 0..<6 { m.results[x] = result(.matrix, matched: 5) }      // row 0: challenged
        for x in 0..<6 { m.results[6 + x] = result(.notIndexed) }          // row 1: not indexed
        for x in 0..<6 { m.results[12 + x] = result(.matrix, matched: 0) } // row 2: exclusion
        let image = PhaseMapPresentation.image(m)
        func tones(row y: Int) -> Set<[UInt8]> {
            Set((0..<6).map { x -> [UInt8] in
                let i = (y * 6 + x) * 4
                return [image.rgba[i], image.rgba[i + 1], image.rgba[i + 2]]
            })
        }
        func legendTones(_ label: String) -> Set<[UInt8]>? {
            guard let row = PhaseMapPresentation.legend(m).first(where: { $0.label == label })
            else { return nil }
            guard let second = row.stripe else { return [[row.color.r, row.color.g, row.color.b]] }
            return [[row.color.r, row.color.g, row.color.b], [second.r, second.g, second.b]]
        }
        XCTAssertEqual(tones(row: 0).count, 2, "the map stripes the challenged row in two tones")
        XCTAssertEqual(legendTones("of which challenged"), tones(row: 0))
        XCTAssertEqual(tones(row: 1).count, 2, "the map stripes the not-indexed row in two tones")
        XCTAssertEqual(legendTones("Not indexed"), tones(row: 1))
        XCTAssertEqual(tones(row: 2).count, 1, "exclusion stays one flat tone")
        XCTAssertEqual(legendTones("Al (matrix)"), tones(row: 2))
    }

    /// S12: the pixel rule the phase map and the objects picture share.
    /// Mutations: `matrixPixelColor` returning `matrixColor` always -> the
    /// stripe half goes red; returning the stripe for every challenged pixel
    /// (dropping `isChallengedStripe`) -> the ground half goes red; dropping
    /// `isChallengedMatrix` (striping the exclusion route too) -> the
    /// exclusion half goes red.
    func testMatrixPixelRuleStripesOnlyChallengedPositionsOnTheStripeTone() {
        let ground = PhaseMapPresentation.matrixColor
        let stripe = PhaseMapPresentation.challengedMatrixStripe
        let challenged = result(.matrix, matched: 6)
        let excluded = result(.matrix, matched: 0)
        var sawStripe = false, sawGround = false
        for y in 0..<PhaseMapPresentation.stripePeriod {
            for x in 0..<PhaseMapPresentation.stripePeriod {
                let got = PhaseMapPresentation.matrixPixelColor(challenged, x: x, y: y)
                let onStripe = PhaseMapPresentation.isChallengedStripe(x: x, y: y)
                XCTAssertTrue(got == (onStripe ? stripe : ground), "challenged at (\(x), \(y))")
                if onStripe { sawStripe = true } else { sawGround = true }
                XCTAssertTrue(PhaseMapPresentation.matrixPixelColor(excluded, x: x, y: y) == ground,
                              "exclusion is flat at (\(x), \(y))")
            }
        }
        XCTAssertTrue(sawStripe && sawGround, "one period holds both tones")
        // The not-indexed hatch is the same shared rule the map paints.
        let hatch = PhaseMapPresentation.notIndexedColors
        XCTAssertTrue(PhaseMapPresentation.notIndexedPixelColor(x: 0, y: 0) == hatch.0)
        XCTAssertTrue(PhaseMapPresentation.notIndexedPixelColor(x: 3, y: 0) == hatch.1)
    }

    /// S12 (e): the evidence line of a challenge-turned matrix position says why
    /// the claimed-disks overlay shows some of its disks as unexplained — the
    /// challenger's zone axis is not recorded, so the overlay cannot pair against
    /// it. Mutation: dropping the sentence from `evidenceLine` -> red; adding it
    /// to the exclusion route as well -> the second assertion goes red.
    func testEvidenceLineNamesTheOverlayLimitOnlyForAChallengedPosition() {
        let m = map()
        let challenged = PhaseMapPresentation.evidenceLine(m.results[6], map: m)
        XCTAssertTrue(challenged.contains("Show claimed disks"), challenged)
        XCTAssertTrue(challenged.contains("unexplained"), challenged)
        XCTAssertTrue(challenged.contains("not recorded"), challenged)
        let excluded = PhaseMapPresentation.evidenceLine(m.results[0], map: m)
        XCTAssertFalse(excluded.contains("unexplained"), excluded)
    }

    /// The evidence line and the map share one classification.
    func testEvidenceLineAgreesWithTheClassification() {
        let m = map()
        XCTAssertTrue(PhaseMapPresentation.evidenceLine(m.results[6], map: m).contains("another orientation"))
        XCTAssertTrue(PhaseMapPresentation.evidenceLine(m.results[0], map: m).contains("too few to index"))
    }
}
