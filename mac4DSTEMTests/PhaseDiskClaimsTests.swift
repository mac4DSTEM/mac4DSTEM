//
//  PhaseDiskClaimsTests.swift
//  Which detected disk did which phase claim: `PhaseVectorMatcher.claims`
//  (the "Show claimed disks" overlay's Core). Hand-placed reference vectors,
//  so every pairing below is exact and readable.
//
//  The fixture is one detector of 0.01 Å⁻¹ per pixel with the direct beam at
//  pixel (100, 100):
//    matrix       (phase 0)  ±0.50 on each axis            -> pixels 50 / 150
//    precipitate  (phase 1)  (0.30, 0.20), (-0.30, -0.20), (0.35, -0.25)
//    a stray disk at (0.60, 0.70) belongs to nobody
//    the direct beam itself is detected at (100, 100)
//
//  Each test states the mutation it catches. They are written to go red on
//  it; the orchestrator's serial gate is where they are run.
//

import XCTest
import simd
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseDiskClaimsTests: XCTestCase {

    private let scale = 0.01
    private let origin: Float = 100

    private func ref(_ x: Double, _ y: Double, _ h: Int = 1) -> ReferenceVector {
        ReferenceVector(h: h, k: 0, l: 0, q: SIMD2(x, y), length: simd_length(SIMD2(x, y)),
                        relativeIntensity: 1)
    }

    /// Entries: 0 = matrix, 1 = the precipitate. Vectors sorted by length,
    /// as the library guarantees.
    private func fixtureLibrary() -> PhaseReferenceLibrary {
        let matrixVectors = [ref(0.5, 0), ref(0, 0.5), ref(-0.5, 0), ref(0, -0.5)]
        let precipitateVectors = [ref(0.30, 0.20), ref(-0.30, -0.20), ref(0.35, -0.25)]
            .sorted { $0.length < $1.length }
        let phases = [
            PhaseDefinition(id: "matrix", displayName: "Matrix", crystal: .aluminum,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "precip", displayName: "Precipitate", crystal: .aluminum,
                            role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
        ]
        return PhaseReferenceLibrary(
            phases: phases, settings: PhaseReferenceSettings(),
            entries: [
                PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1),
                                          inPlaneRotationRad: 0, vectors: matrixVectors),
                PhaseOrientationReference(phaseIndex: 1, zoneAxis: SIMD3(0, 0, 1),
                                          inPlaneRotationRad: 0, vectors: precipitateVectors),
            ], matrixPhaseIndex: 0)
    }

    /// A peak at the pixel that puts it at detector vector (qx, qy).
    private func peak(_ qx: Double, _ qy: Double) -> BraggPeak {
        BraggPeak(x: origin + Float((qx / scale).rounded()),
                  y: origin + Float((qy / scale).rounded()), intensity: 1)
    }

    private var directBeam: BraggPeak { BraggPeak(x: origin, y: origin, intensity: 9) }

    /// direct beam, 3 matrix disks, 3 precipitate disks, 1 stray — in that order.
    private func mixedPeaks() -> [BraggPeak] {
        [directBeam,
         peak(0.5, 0), peak(0, 0.5), peak(-0.5, 0),
         peak(0.30, 0.20), peak(-0.30, -0.20), peak(0.35, -0.25),
         peak(0.60, 0.70)]
    }

    private func claims(_ peaks: [BraggPeak], library: PhaseReferenceLibrary,
                        result: PhaseVectorResult,
                        settings: PhaseVectorSettings = PhaseVectorSettings()) -> [PhaseDiskClaim] {
        PhaseVectorMatcher.claims(
            peaks: peaks, originX: origin, originY: origin, invAngstromPerPixel: scale,
            settings: settings, matrixEntry: library.entries[0], result: result, library: library)
    }

    private func classify(_ peaks: [BraggPeak], library: PhaseReferenceLibrary,
                          settings: PhaseVectorSettings = PhaseVectorSettings()) -> PhaseVectorResult {
        let vectors = PhaseVectorMatcher.experimentalVectors(
            peaks: peaks, originX: origin, originY: origin, invAngstromPerPixel: scale,
            directBeamRadiusInvAngstrom: settings.directBeamRadiusInvAngstrom,
            maximumVectorInvAngstrom: settings.maximumVectorInvAngstrom)
        return PhaseVectorMatcher.classify(
            vectors: vectors, library: library, settings: settings,
            matrixEntry: library.entries[0], candidateEntryIndices: [1],
            scratch: PhaseVectorMatcher.Scratch(capacity: 8))
    }

    // MARK: - The claim of each disk

    /// Matrix lattice + one precipitate + one stray: exactly matrix / phase /
    /// unexplained, and the direct beam not matched at all.
    ///
    /// Mutations: matrix removal skipped (the matrix disks would go to
    /// "unexplained"); the matrix entry used as the winning entry (the
    /// precipitate disks would go "unexplained"); the direct-beam guard
    /// dropped (the beam would be "matrix"/"unexplained"); pair radius
    /// widened so the stray pairs with a precipitate reference.
    func testMixedPositionClaimsMatrixPhaseUnexplainedExactly() {
        let library = fixtureLibrary()
        let peaks = mixedPeaks()
        let result = classify(peaks, library: library)
        XCTAssertEqual(result.verdict, .indexed, "fixture must be indexed, or the test says nothing")
        XCTAssertEqual(Int(result.phaseIndex), 1)

        XCTAssertEqual(claims(peaks, library: library, result: result), [
            .notMatched,
            .matrix, .matrix, .matrix,
            .phase(1), .phase(1), .phase(1),
            .unexplained,
        ])
    }

    /// The claims reproduce the counts the map recorded for the position:
    /// phase claims = `matchedCount`, matrix claims = `removedCount`,
    /// phase + unexplained = `survivingCount`. This is what "cannot disagree
    /// with the map" means in numbers.
    ///
    /// Mutation: a claim rule with its own pairing (e.g. a different radius
    /// or a nearest-in-any-entry rule) changes one of these three counts.
    func testClaimCountsEqualTheMatchersOwnCounts() {
        let library = fixtureLibrary()
        let peaks = mixedPeaks()
        let result = classify(peaks, library: library)
        let c = claims(peaks, library: library, result: result)

        XCTAssertEqual(c.filter { $0 == .phase(Int(result.phaseIndex)) }.count, Int(result.matchedCount))
        XCTAssertEqual(c.filter { $0 == .matrix }.count, Int(result.removedCount))
        XCTAssertEqual(c.filter { $0 == .phase(1) || $0 == .unexplained }.count,
                       Int(result.survivingCount))
    }

    /// A claim names only the phase the map drew. A position the map did not
    /// index gets no phase claim, whatever the disks would have matched.
    ///
    /// Mutation: claims recomputed from the best entry instead of read from
    /// the recorded verdict; the `verdict == .indexed` guard removed.
    func testNoPhaseClaimWhereTheMapDidNotIndex() {
        let library = fixtureLibrary()
        let peaks = mixedPeaks()
        var refused = classify(peaks, library: library)
        refused.verdict = .notIndexed          // the map's recorded verdict, entry still attached
        let c = claims(peaks, library: library, result: refused)
        XCTAssertFalse(c.contains { if case .phase = $0 { return true } else { return false } })
        XCTAssertEqual(c.filter { $0 == .unexplained }.count, 4,
                       "the precipitate's three disks and the stray survive matrix removal")
    }

    /// The claim follows the RECORDED entry: pointing the result at a
    /// different phase names that phase (and its index).
    ///
    /// Mutation: the phase in `.phase(_)` taken from the entry list position
    /// or hard-coded instead of `result.phaseIndex`.
    func testPhaseClaimCarriesTheResultsPhaseIndex() {
        let base = fixtureLibrary()
        let third = PhaseDefinition(id: "other", displayName: "Other", crystal: .aluminum,
                                    role: .candidate, zoneAxes: [SIMD3(0, 0, 1)])
        let library = PhaseReferenceLibrary(
            phases: base.phases + [third], settings: base.settings,
            entries: base.entries + [PhaseOrientationReference(
                phaseIndex: 2, zoneAxis: SIMD3(0, 0, 1), inPlaneRotationRad: 0,
                vectors: [ref(0.60, 0.70)])],
            matrixPhaseIndex: 0)
        var result = PhaseVectorResult()
        result.verdict = .indexed; result.phaseIndex = 2; result.entryIndex = 2
        let c = claims(mixedPeaks(), library: library, result: result)
        XCTAssertEqual(c.last, .phase(2), "the stray sits on the third phase's only reference")
        XCTAssertEqual(c.filter { $0 == .unexplained }.count, 3,
                       "the precipitate disks are unexplained when the recorded entry is another phase's")
    }

    /// A disk past `maximumVectorInvAngstrom` was never offered, so it is
    /// "not matched" — not unexplained.
    ///
    /// Mutation: the range guard missing from `experimentalVector` (or the
    /// claim using its own predicate).
    func testDiskBeyondMaximumVectorIsNotMatchedRatherThanUnexplained() {
        let library = fixtureLibrary()
        var settings = PhaseVectorSettings()
        settings.maximumVectorInvAngstrom = 0.65
        let peaks = mixedPeaks()                 // the stray is at |q| = 0.92
        let result = classify(peaks, library: library, settings: settings)
        let c = claims(peaks, library: library, result: result, settings: settings)
        XCTAssertEqual(c.first, .notMatched)
        XCTAssertEqual(c.last, .notMatched)
        XCTAssertFalse(c.contains(.unexplained))
    }

    /// The single-peak predicate and the array function are one rule.
    ///
    /// Mutation: `experimentalVectors` reverted to its own inline guard with
    /// a different rule (e.g. the direct-beam test dropped from one of the
    /// two), so the arrays differ.
    func testExperimentalVectorsIsExactlyTheSinglePeakRule() {
        let peaks = mixedPeaks()
        let many = PhaseVectorMatcher.experimentalVectors(
            peaks: peaks, originX: origin, originY: origin, invAngstromPerPixel: scale,
            directBeamRadiusInvAngstrom: 0.15)
        let one = peaks.compactMap {
            PhaseVectorMatcher.experimentalVector(
                peak: $0, originX: origin, originY: origin, invAngstromPerPixel: scale,
                directBeamRadiusInvAngstrom: 0.15)
        }
        XCTAssertEqual(many, one)
        XCTAssertEqual(many.count, 7, "only the direct beam is left out")
    }

    // MARK: - Against the map itself

    /// Every position of a real `PhaseVectorMatcher.map` run: the claims
    /// agree with the position's recorded label and counts. Positions: a
    /// mixed one (indexed), pure matrix, matrix + one stray (matrix by
    /// exclusion), three strays (not indexed), and an empty one.
    ///
    /// Mutation: any claim rule that diverges from the matcher — checked per
    /// position on verdict, phase, and the three counts.
    func testClaimsAgreeWithTheMapsOwnLabelAtEveryPosition() throws {
        let library = fixtureLibrary()
        let matrixDisks = [peak(0.5, 0), peak(0, 0.5), peak(-0.5, 0)]
        let positions: [[BraggPeak]] = [
            mixedPeaks(),
            [directBeam] + matrixDisks,
            [directBeam] + matrixDisks + [peak(0.60, 0.70)],
            [peak(0.60, 0.70), peak(0.62, -0.70), peak(-0.70, 0.60)],
            [],
        ]
        let bragg = BraggVectors(scanWidth: positions.count, scanHeight: 1, peaks: positions)
        let settings = PhaseVectorSettings()
        let map = try XCTUnwrap(PhaseVectorMatcher.map(
            bragg: bragg, library: library, settings: settings,
            originX: origin, originY: origin, invAngstromPerPixel: scale,
            matrixEntryIndex: 0))

        XCTAssertEqual(map.results.map(\.verdict), [.indexed, .matrix, .matrix, .notIndexed, .noData],
                       "the fixture must reach each verdict, or the agreement below proves less")

        for (i, peaks) in positions.enumerated() {
            let result = map.results[i]
            let c = PhaseVectorMatcher.claims(
                peaks: peaks, originX: origin, originY: origin, invAngstromPerPixel: scale,
                settings: settings, matrixEntry: library.entries[Int(map.matrixEntryIndex)],
                result: result, library: library)
            XCTAssertEqual(c.count, peaks.count, "position \(i)")

            let phaseClaims = c.compactMap { claim -> Int? in
                if case .phase(let p) = claim { return p } else { return nil }
            }
            let matrixCount = c.filter { $0 == .matrix }.count
            let unexplained = c.filter { $0 == .unexplained }.count
            let usable = c.filter { $0 != .notMatched }.count

            XCTAssertEqual(matrixCount, Int(result.removedCount), "position \(i): matrix claims")
            if result.verdict == .indexed {
                XCTAssertTrue(phaseClaims.allSatisfy { $0 == Int(result.phaseIndex) }, "position \(i)")
                XCTAssertEqual(phaseClaims.count, Int(result.matchedCount), "position \(i): phase claims")
            } else {
                XCTAssertTrue(phaseClaims.isEmpty, "position \(i): only an indexed position has a phase claim")
            }
            XCTAssertEqual(phaseClaims.count + unexplained, Int(result.survivingCount),
                           "position \(i): what survived matrix removal is claimed or unexplained")
            XCTAssertEqual(usable, matrixCount + phaseClaims.count + unexplained, "position \(i)")
        }
    }
}
