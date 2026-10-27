//
//  PhaseMapAppTests.swift
//  The app-owned tests that lived in PhaseVectorMatchingTests: phase-list staleness and naming (AppState,
//  PhaseMappingProduct), the phase-map presentation, zone-axis text parsing and the resolution diagnosis.
//  The matcher and the reference library are DiffractoKit's (0.3.1) and tested there.
//

import XCTest
import simd
import DiffractoCore
import DiffractoScattering
import DiffractoGeometry
import DiffractoOrientation
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseMapAppTests: XCTestCase {

    /// Mutation: `phaseSignature` sorting its slots, the form that stood
    /// until 2026-09-14. Colours are by list position, so a list whose
    /// positions changed no longer reads as the legend of the last run —
    /// and a sorted signature let `isStale` stay false through exactly that.
    func testPhaseSignatureFollowsTheListOrderBecauseTheColoursDo() {
        let models = CrystalModelLibrary.models
        XCTAssertGreaterThanOrEqual(models.count, 3)
        let a = PhaseMappingSlot(model: models[0], isMatrix: true, u: 0, v: 0, w: 1)
        let b = PhaseMappingSlot(model: models[1], isMatrix: false, u: 0, v: 0, w: 1)
        let c = PhaseMappingSlot(model: models[2], isMatrix: false, u: 0, v: 1, w: 0)
        let product = PhaseMappingProduct()
        product.phases = [a, b, c]
        let original = product.phaseSignature
        product.phases = [a, c, b]
        XCTAssertNotEqual(product.phaseSignature, original,
                          "b moved from position 1 to 2 and would be drawn in a different colour")
        let before = PhaseMapPresentation.color(phaseIndex: 1, matrixPhaseIndex: 0)
        let after = PhaseMapPresentation.color(phaseIndex: 2, matrixPhaseIndex: 0)
        XCTAssertTrue(before != after, "the premise: colour is by position")
        product.phases = [a, b, c]
        XCTAssertEqual(product.phaseSignature, original)
    }

    /// Two phases with one name (one structure imported from two files, one
    /// per zone axis) are named by their zone axis; a unique name is left
    /// alone. Break-first: the `shared` suffix removed leaves both
    /// "Twin" and this must go red.
    @MainActor
    func testPhasesSharingANameAreNamedByZoneAxis() throws {
        let base = CrystalModelLibrary.models[1]
        func twin(_ id: String) -> CrystalModel {
            CrystalModel(id: id, displayName: "Twin", structure: base.structure,
                         symmetry: base.symmetry, source: .imported)
        }
        let appState = AppState()
        appState.phaseMapping.phases = [
            PhaseMappingSlot(model: CrystalModelLibrary.models[0], isMatrix: true, u: 0, v: 0, w: 1),
            PhaseMappingSlot(model: twin("twin_a"), isMatrix: false, u: 0, v: 1, w: 0),
            PhaseMappingSlot(model: twin("twin_b"), isMatrix: false, u: 0, v: 0, w: 1),
        ]
        let names = try XCTUnwrap(appState.phaseDefinitions()).map(\.displayName)
        XCTAssertEqual(names[1], "Twin [0 1 0]")
        XCTAssertEqual(names[2], "Twin [0 0 1]")
        XCTAssertEqual(names[0], CrystalModelLibrary.models[0].displayName, "a unique name is unchanged")
    }

    // MARK: The diagnosis of an empty map (app presentation over the kit's PhaseMap)

    /// The map explains ITSELF when it found nothing. Mutation: the
    /// `matrix == 0` branch removed, so an empty map blames the candidate
    /// phases when the real cause is that the frame never worked at all.
    func testAnEmptyMapNamesTheMostSpecificCauseFirst() {
        func map(noData: Int, notIndexed: Int, matrix: Int, indexed: Int) -> PhaseMap {
            let total = noData + notIndexed + matrix + indexed
            var m = PhaseMap(width: total, height: 1, matrixEntryIndex: 0,
                             phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
            var i = 0
            for _ in 0..<noData { m.results[i].verdict = .noData; i += 1 }
            for _ in 0..<notIndexed { m.results[i].verdict = .notIndexed; i += 1 }
            for _ in 0..<matrix { m.results[i].verdict = .matrix; i += 1 }
            for _ in 0..<indexed { m.results[i].verdict = .indexed; i += 1 }
            return m
        }
        let coarse = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                           invAngstromPerPixel: 0.045741477608680726)

        // The owner's run, in proportion: no matrix at all.
        let owners = PhaseMapPresentation.diagnosis(map(noData: 0, notIndexed: 999,
                                                        matrix: 0, indexed: 1),
                                                    resolution: coarse)
        XCTAssertNotNil(owners)
        XCTAssertTrue(owners?.contains("Nothing was removed as matrix") ?? false, owners ?? "nil")
        XCTAssertTrue(owners?.contains("0.44") ?? false,
                      "the pixel number is what makes it actionable: \(owners ?? "nil")")

        // Same shape on a detector the tolerance fits: the cause must be the
        // zone axis, not the tolerance.
        let fine = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                         invAngstromPerPixel: 0.008)
        let axis = PhaseMapPresentation.diagnosis(map(noData: 0, notIndexed: 999,
                                                      matrix: 0, indexed: 1),
                                                  resolution: fine)
        XCTAssertTrue(axis?.contains("zone axis") ?? false, axis ?? "nil")
        XCTAssertFalse(axis?.contains("detector pixel") ?? true, axis ?? "nil")

        // No peaks beats every other explanation.
        let empty = PhaseMapPresentation.diagnosis(map(noData: 900, notIndexed: 100,
                                                       matrix: 0, indexed: 0),
                                                   resolution: coarse)
        XCTAssertTrue(empty?.contains("no usable peaks") ?? false, empty ?? "nil")

        // The matrix WAS found: then it is the candidates that do not match.
        let candidates = PhaseMapPresentation.diagnosis(map(noData: 0, notIndexed: 500,
                                                            matrix: 499, indexed: 1),
                                                        resolution: coarse)
        XCTAssertTrue(candidates?.contains("candidate phases") ?? false, candidates ?? "nil")

        // And a map that found things says nothing at all.
        XCTAssertNil(PhaseMapPresentation.diagnosis(map(noData: 0, notIndexed: 200,
                                                        matrix: 400, indexed: 400),
                                                    resolution: coarse))
        // Nor does a clean all-matrix result: a precipitate-free region is an
        // answer, not a failure, and telling its user to check their zone axes
        // would be the app second-guessing a correct measurement.
        XCTAssertNil(PhaseMapPresentation.diagnosis(map(noData: 0, notIndexed: 0,
                                                        matrix: 1000, indexed: 0),
                                                    resolution: coarse))
    }
}

/// The presentation layer of the phase map, and the one piece of ACOM
/// presentation that moved into Core to pay for this feature's AppState lines.
final class PhaseMapPresentationTests: XCTestCase {

    /// Mutation: `color(phaseIndex:matrixPhaseIndex:)` indexing the palette by
    /// `phaseIndex` directly. The map would then recolour every precipitate
    /// when the user marks a different phase as the matrix — which is a
    /// presentation change that looks exactly like a science change.
    func testCandidateColoursDoNotDependOnWhereTheMatrixSitsInTheList() {
        let first = PhaseMapPresentation.color(phaseIndex: 1, matrixPhaseIndex: 0)
        let second = PhaseMapPresentation.color(phaseIndex: 0, matrixPhaseIndex: 2)
        XCTAssertEqual(first.r, second.r)
        XCTAssertEqual(first.g, second.g)
        XCTAssertEqual(first.b, second.b)
        // And the matrix keeps its neutral whatever its index.
        for index in 0..<4 {
            let matrix = PhaseMapPresentation.color(phaseIndex: index, matrixPhaseIndex: index)
            XCTAssertEqual(matrix.r, PhaseMapPresentation.matrixColor.r)
            XCTAssertEqual(matrix.b, PhaseMapPresentation.matrixColor.b)
        }
    }

    /// Mutation: `.noData` drawn with alpha 255, or `.notIndexed` drawn as a
    /// flat grey. "No peaks here" and "peaks I cannot explain" are different
    /// facts and must not share an appearance — nor may either be mistakable
    /// for a phase.
    func testNoDataIsTransparentAndNotIndexedIsHatched() {
        var map = PhaseMap(width: 6, height: 2, matrixEntryIndex: 0,
                           phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        for x in 0..<6 { map.results[x].verdict = .notIndexed }        // row 0
        for x in 0..<6 { map.results[6 + x].verdict = .noData }        // row 1
        let image = PhaseMapPresentation.image(map)
        for x in 0..<6 {
            XCTAssertEqual(image.rgba[x * 4 + 3], 255, "not-indexed must be opaque")
            XCTAssertEqual(image.rgba[(6 + x) * 4 + 3], 0, "no-data must be transparent")
        }
        // The hatch really alternates along the row, rather than being one grey.
        let greys = (0..<6).map { image.rgba[$0 * 4] }
        XCTAssertGreaterThan(Set(greys).count, 1, "the not-indexed hatch is a flat fill")
    }

    /// Mutation: `survivingCount` used for `removedCount`, which inverts the
    /// fraction; the median taken over every position rather than the matrix
    /// ones; a fully-explained position reported as partial.
    ///
    /// A matrix verdict is returned both when almost nothing survived removal
    /// and when the matrix won the challenge, and neither says how much the
    /// matrix EXPLAINED. This reports that, and deliberately does NOT threshold
    /// it: a 0.90 bar measured on Thronsen flagged 46 % of the demo cube, whose
    /// every acceptance clause passes (2026-09-16, `open-items.md`).
    func testTheMatrixExplainedFractionIsReportedAndNotThresholded() {
        var map = PhaseMap(width: 3, height: 1, matrixEntryIndex: 0,
                           phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        // 0: fully explained (4 of 4). 1: partial (1 of 4). 2: indexed.
        map.results[0].verdict = .matrix; map.results[0].phaseIndex = 0
        map.results[0].removedCount = 4; map.results[0].survivingCount = 0
        map.results[1].verdict = .matrix; map.results[1].phaseIndex = 0
        map.results[1].removedCount = 1; map.results[1].survivingCount = 3
        map.results[2].verdict = .indexed; map.results[2].phaseIndex = 1
        map.results[2].removedCount = 0; map.results[2].survivingCount = 9

        XCTAssertEqual(PhaseMapPresentation.explainedFraction(map.results[0]), 1.0)
        XCTAssertEqual(PhaseMapPresentation.explainedFraction(map.results[1]), 0.25)

        // The median is over the MATRIX positions only: the indexed position's
        // 0.0 must not drag it down, or the number answers a different question.
        XCTAssertEqual(PhaseMapPresentation.medianMatrixExplainedFraction(map) ?? -1,
                       1.0, accuracy: 1e-9,
                       "the median must be taken over matrix verdicts alone")

        // Both are still matrix: reporting the evidence must not move the
        // phase fraction, in either direction.
        XCTAssertEqual(map.phaseCounts[0], 2)
        XCTAssertFalse(PhaseMapPresentation.legend(map).contains { $0.label.contains("partly") },
                       "the refuted 0.90 bar must not come back as a legend row")

        // A map with no matrix positions has no such number to report.
        var none = PhaseMap(width: 1, height: 1, matrixEntryIndex: 0,
                            phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        none.results[0].verdict = .notIndexed
        XCTAssertNil(PhaseMapPresentation.medianMatrixExplainedFraction(none))
    }

    /// Mutation: `distanceImage` writing 0 rather than NaN at a matrix or
    /// no-data position. Zero reads as a PERFECT match — the most misleading
    /// value available — and would drag every colour scale to it.
    func testDistanceIsNotANumberWhereNothingWasMatched() {
        var map = PhaseMap(width: 3, height: 1, matrixEntryIndex: 0,
                           phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        map.results[0].verdict = .matrix
        map.results[1].verdict = .indexed; map.results[1].score = 0.004
        map.results[2].verdict = .noData
        let image = PhaseMapPresentation.distanceImage(map)
        XCTAssertTrue(image.pixels[0].isNaN)
        XCTAssertEqual(image.pixels[1], 0.004, accuracy: 1e-7)
        XCTAssertTrue(image.pixels[2].isNaN)
        XCTAssertEqual(PhaseMapPresentation.distanceValidity(map), [false, true, false])
    }

    /// Mutation: `evidenceLine` dropping the counts, or naming the phase
    /// without the distance. The line IS the argument for the colour under the
    /// cursor; a line that says only "β″" is a label, not evidence.
    func testEvidenceLineCarriesTheNumbersBehindTheLabel() {
        let map = PhaseMap(width: 1, height: 1, matrixEntryIndex: 0,
                           phaseNames: ["Al", "β″"], matrixPhaseIndex: 0)
        var result = PhaseVectorResult()
        result.verdict = .indexed
        result.phaseIndex = 1
        result.matchedCount = 7
        result.survivingCount = 9
        result.removedCount = 12
        result.score = 0.0043
        result.runnerUpPhaseIndex = 0
        result.runnerUpScore = 0.019
        let line = PhaseMapPresentation.evidenceLine(result, map: map)
        XCTAssertTrue(line.contains("β″"), line)
        XCTAssertTrue(line.contains("7 of 9"), line)
        XCTAssertTrue(line.contains("0.0043"), line)
        XCTAssertTrue(line.contains("12 matrix removed"), line)
        XCTAssertTrue(line.contains("0.0190"), line)

        var none = PhaseVectorResult()
        none.verdict = .noData
        XCTAssertEqual(PhaseMapPresentation.evidenceLine(none, map: map),
                       "No peaks at this position.")
    }

    /// Mutation: `OrientationMap.eulerText` dropping the `templateIndex >= 0`
    /// guard. An unindexed position has an `euler` of (0, 0, 0), which renders
    /// as a perfectly plausible "0.0°, 0.0°, 0.0°" — a read-out that is not a
    /// measurement, wearing the look of one. This is the ACOM read-out that
    /// moved out of `AppState` into Core with this feature, and it had no test
    /// of its own there.
    func testEulerTextRefusesAnUnindexedPositionAndOneOffTheMap() {
        var map = OrientationMap(width: 2, height: 2, matchingBackend: .cpu,
                                 symmetry: .cubic, templateCount: 1)
        map.results[0].templateIndex = -1
        map.results[1].templateIndex = 0
        map.results[1].euler = .zero
        XCTAssertNil(map.eulerText(x: 0, y: 0), "an unindexed position produced angles")
        XCTAssertEqual(map.eulerText(x: 1, y: 0), "0.0°, 0.0°, 0.0°")
        XCTAssertNil(map.eulerText(x: -1, y: 0))
        XCTAssertNil(map.eulerText(x: 2, y: 0))
        XCTAssertNil(map.eulerText(x: 0, y: 2))
    }
}

/// The zone-axis field's parser. A crystallographer types [010] or 0 1 0 or
/// 0,1,0, and every one of those must reach the same direction — while
/// anything that is NOT three integers must be refused rather than rounded
/// into [0 0 0], which names no direction and would silently change the map.
final class ZoneAxisParsingTests: XCTestCase {

    /// Mutation: the single-token branch removed, or `-` handled as a
    /// separator rather than a sign. `0-12` is 0, −1, 2 — a real zone axis —
    /// and reading it as 0, 1, 2 is a wrong answer, not a parse failure.
    func testEveryWayOfWritingTheSameAxisReachesIt() {
        for text in ["0 1 0", "0,1,0", "[010]", "[0 1 0]", " 010 ", "0, 1, 0"] {
            XCTAssertEqual(PhaseMappingSlot.parseZoneAxis(text), SIMD3(0, 1, 0),
                           "\(text) did not parse to [0 1 0]")
        }
        XCTAssertEqual(PhaseMappingSlot.parseZoneAxis("0 -1 2"), SIMD3(0, -1, 2))
        XCTAssertEqual(PhaseMappingSlot.parseZoneAxis("0-12"), SIMD3(0, -1, 2))
        XCTAssertEqual(PhaseMappingSlot.parseZoneAxis("[1-10]"), SIMD3(1, -1, 0))
    }

    /// Mutation: the `fields.count == 3` guard relaxed, or a failed `Int.init`
    /// defaulted to 0. Either turns a typo into a silently different zone axis,
    /// which changes every reference vector in the library.
    func testAnythingThatIsNotThreeIntegersIsRefused() {
        for text in ["", "0 1", "0 1 0 1", "a b c", "0 1 x", "0.5 1 0", "--1 0 0", "[]"] {
            XCTAssertNil(PhaseMappingSlot.parseZoneAxis(text),
                         "\(text) was accepted as a zone axis")
        }
    }

    /// The orientation-relationship field's parser: pairs "A ∥ B" separated by
    /// "," or ";", A this phase's vector and B the matrix's, each a plane
    /// "(hkl)" (parens optional) or a direction "[uvw]" (brackets required).
    ///
    /// Mutations named here because each is a plausible wrong shortcut:
    /// - only the first pair parsed and the rest of the list silently dropped
    ///   (a `split` that stops after one, or a loop with an early `return`);
    /// - a bracketed "[uvw]" read as a plane instead of a direction (the
    ///   bracket/paren dispatch collapsed to one case);
    /// - empty text returning `nil` (a refusal) instead of `[]` (free — no
    ///   constraint), which would make every existing phase's empty field an
    ///   error the day this shipped.
    func testAnOrientationRelationshipParsesTheWayItIsWritten() {
        let twoPairs = PhaseMappingSlot.parseOrientationRelationships(
            "(002) ∥ (200), (002) ∥ (020)")
        XCTAssertEqual(twoPairs, [
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)),
                                    matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)),
                                    matrix: .plane(SIMD3(0, 2, 0))),
        ])

        XCTAssertEqual(PhaseMappingSlot.parseOrientationRelationships("002 || 200"), [
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)),
                                    matrix: .plane(SIMD3(2, 0, 0))),
        ])

        XCTAssertEqual(PhaseMappingSlot.parseOrientationRelationships("[210] // (220)"), [
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)),
                                    matrix: .plane(SIMD3(2, 2, 0))),
        ])

        XCTAssertEqual(PhaseMappingSlot.parseOrientationRelationships(""), [])
        XCTAssertEqual(PhaseMappingSlot.parseOrientationRelationships("  "), [])

        for text in ["(002) ∥", "abc ∥ (200)", "(002) (200)"] {
            XCTAssertNil(PhaseMappingSlot.parseOrientationRelationships(text),
                         "\(text) was accepted as an orientation relationship")
        }

        var slot = PhaseMappingSlot(model: CrystalModelLibrary.models[0], isMatrix: false,
                                    u: 0, v: 0, w: 1)
        let before = slot.signature
        slot.orientationRelationshipText = "(002) ∥ (200)"
        XCTAssertNotEqual(slot.signature, before,
                          "the signature did not change when the OR text did")
    }
}
