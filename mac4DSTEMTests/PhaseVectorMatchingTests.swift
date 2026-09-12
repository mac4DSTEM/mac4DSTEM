//
//  PhaseVectorMatchingTests.swift
//  The unit-level invariants of vector-matched phase mapping. The SCIENCE is
//  gated by `tools/phase-vector-matching`, against arithmetic and planted
//  truth; what is here is the behaviour a caller can rely on — the refusals,
//  the frames, and the two optimisations that must not change an answer.
//
//  Every assertion below states the mutation it catches, and each was run
//  against that mutation before being trusted.
//

import XCTest
import simd
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class PhaseVectorMatchingTests: XCTestCase {

    // MARK: The library

    /// Mutation: `cartesianZoneAxis` returning `SIMD3(Double(uvw.x), ...)`
    /// normalised — the naive reading of [u v w]. Invisible on every cubic
    /// phase, wrong on every monoclinic one, which is the case the feature
    /// exists for.
    func testZoneAxisIsARealSpaceDirectionNotACartesianTriple() {
        let beta = Crystal.betaDoublePrime
        let n = PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(0, 0, 1), crystal: beta)
        let axis = try! XCTUnwrap(n)
        let betaRad = beta.betaDeg * .pi / 180
        XCTAssertEqual(axis.x, cos(betaRad), accuracy: 1e-12)
        XCTAssertEqual(axis.y, 0, accuracy: 1e-12)
        XCTAssertEqual(axis.z, sin(betaRad), accuracy: 1e-12)
        // And it really differs from the naive triple, so the mutation is
        // detectable rather than merely wrong.
        XCTAssertGreaterThan(acos(abs(axis.z)) * 180 / .pi, 10)
    }

    /// Mutation: dropping the `guard n > 1e-12` in `cartesianZoneAxis`.
    func testZeroZoneAxisYieldsNoDirection() {
        XCTAssertNil(PhaseReferenceLibrary.cartesianZoneAxis(
            SIMD3(0, 0, 0), crystal: Crystal.aluminum))
    }

    /// Mutation: `matrixIndices.count == 1` relaxed to `>= 1`, or the guard
    /// removed. Without exactly one matrix there is no "by exclusion" answer,
    /// and silently picking the first would make the verdict depend on the
    /// order the user added phases.
    func testLibraryRefusesUnlessExactlyOneMatrixPhase() {
        func build(_ roles: [PhaseDefinition.Role]) throws -> PhaseReferenceLibrary {
            try PhaseReferenceLibrary.build(phases: roles.enumerated().map {
                PhaseDefinition(id: "p\($0.offset)", displayName: "P\($0.offset)",
                                crystal: .aluminum, role: $0.element,
                                zoneAxes: [SIMD3(0, 0, 1)])
            }, settings: coarseSettings())
        }
        XCTAssertThrowsError(try build([.candidate, .candidate])) { error in
            XCTAssertEqual(error as? PhaseReferenceLibrary.Failure,
                           .matrixPhaseNotUnique(count: 0))
        }
        XCTAssertThrowsError(try build([.matrix, .matrix, .candidate])) { error in
            XCTAssertEqual(error as? PhaseReferenceLibrary.Failure,
                           .matrixPhaseNotUnique(count: 2))
        }
        XCTAssertThrowsError(try build([.matrix])) { error in
            XCTAssertEqual(error as? PhaseReferenceLibrary.Failure, .noCandidatePhases)
        }
        XCTAssertNoThrow(try build([.matrix, .candidate]))
    }

    /// Mutation: the `requested <= maximumEntries` guard removed.
    ///
    /// It does NOT catch the guard being MOVED after the build loop, and two
    /// attempts to make it do so both failed (measured 2026-09-12): building
    /// 720 entries takes under a second, and so does building 44 640, because
    /// each entry is a rotation of an already-projected set of at most 48
    /// vectors. Timing cannot separate "refused before any work" from
    /// "refused after cheap work". The ordering is stated in the source and is
    /// what makes the refusal meaningful for a library that WOULD be expensive;
    /// this test pins the refusal and its numbers, which is what it can see.
    /// Saying so beats keeping an assertion that cannot fail — this repo has
    /// shipped one of those before (`docs/development-process.md`, the L4
    /// control that everyone believed had teeth).
    func testOversizedLibraryIsRefusedWithTheNumbersThatExplainIt() throws {
        var settings = coarseSettings()
        settings.inPlaneStepDeg = 1
        settings.maximumEntries = 10
        // Empty `zoneAxes` means every low-index axis, so this asks for tens of
        // thousands of entries of a 22-atom monoclinic cell. The size is the
        // point: at 720 entries the timing bound below had no teeth — building
        // them took under a second and the test passed against the mutation it
        // names (measured 2026-09-12).
        let axes = PhaseReferenceLibrary.lowIndexZoneAxes.count
        let expected = 2 * axes * 360
        XCTAssertGreaterThan(expected, 20000)
        let started = Date()
        XCTAssertThrowsError(try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                            role: .matrix, zoneAxes: []),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: .betaDoublePrime,
                            role: .candidate, zoneAxes: []),
        ], settings: settings)) { error in
            guard case .libraryTooLarge(let requested, let limit)? =
                    error as? PhaseReferenceLibrary.Failure else {
                return XCTFail("expected libraryTooLarge, got \(error)")
            }
            XCTAssertEqual(requested, expected)
            XCTAssertEqual(limit, 10)
        }
        // Kept as a smoke bound only — it is NOT the ordering check its first
        // version claimed to be (see the comment above).
        XCTAssertLessThan(Date().timeIntervalSince(started), 30.0)
    }

    /// Mutation: the cap applied before the strongest-first sort, or the tie
    /// break dropped so the kept set depends on enumeration order.
    func testDensityCapKeepsTheStrongestAndIsDeterministic() {
        var settings = coarseSettings()
        settings.minimumIntensityFraction = 0
        settings.maximumVectorsPerEntry = 0
        let beta = Crystal.betaDoublePrime
        let uncapped = PhaseReferenceLibrary.projectedVectors(
            reflections: beta.reflections(kMax: settings.kMaxInvAngstrom), crystal: beta,
            zoneAxis: SIMD3(0, 1, 0), settings: settings)
        settings.maximumVectorsPerEntry = 12
        let capped = PhaseReferenceLibrary.projectedVectors(
            reflections: beta.reflections(kMax: settings.kMaxInvAngstrom), crystal: beta,
            zoneAxis: SIMD3(0, 1, 0), settings: settings)
        XCTAssertGreaterThan(uncapped.count, 12)
        XCTAssertEqual(capped.count, 12)
        let weakestKept = capped.map(\.relativeIntensity).min() ?? 0
        let strongestDropped = uncapped
            .filter { kept in !capped.contains { $0.h == kept.h && $0.l == kept.l } }
            .map(\.relativeIntensity).max() ?? 0
        XCTAssertGreaterThanOrEqual(weakestKept, strongestDropped,
                                    "the cap dropped a reflection stronger than one it kept")
        // Determinism: the same inputs give the same set, every time.
        let again = PhaseReferenceLibrary.projectedVectors(
            reflections: beta.reflections(kMax: settings.kMaxInvAngstrom), crystal: beta,
            zoneAxis: SIMD3(0, 1, 0), settings: settings)
        XCTAssertEqual(capped.map(\.length), again.map(\.length))
    }

    /// Mutation: `rotate` using `[c, s; -s, c]` (the transpose), or recomputing
    /// `length` from the rotated components and letting rounding reorder the
    /// array. The matcher's binary search assumes the sort, so a reordering is
    /// a wrong answer, not a slow one.
    func testRotationPreservesLengthsAndSortOrder() {
        let al = Crystal.aluminum
        let settings = coarseSettings()
        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: al.reflections(kMax: settings.kMaxInvAngstrom), crystal: al,
            zoneAxis: SIMD3(0, 0, 1), settings: settings)
        let turned = PhaseReferenceLibrary.rotate(base, by: 37.2 * .pi / 180)
        XCTAssertEqual(base.count, turned.count)
        for (b, t) in zip(base, turned) {
            XCTAssertEqual(b.length, t.length, accuracy: 1e-15)
            XCTAssertEqual(simd_length(t.q), t.length, accuracy: 1e-12)
        }
        XCTAssertEqual(turned, turned.sorted { $0.length < $1.length }.map { $0 },
                       "the rotated set is no longer sorted by |q|")
        // The sense of the rotation: +37.2° takes (x, 0) into the first
        // quadrant, not the fourth. A transposed matrix fails here.
        let probe = PhaseReferenceLibrary.rotate(
            [ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(1, 0), length: 1, relativeIntensity: 1)],
            by: 37.2 * .pi / 180)
        XCTAssertGreaterThan(probe[0].q.y, 0)
    }

    /// Mutation: `inPlaneSteps` returning `stride(from: 0, through: 360)`,
    /// which duplicates 0 and 360, or dropping the guard so a step of 0 loops.
    func testInPlaneStepsCoverTheCircleOnceAndIncludeZero() {
        var settings = coarseSettings()
        settings.inPlaneStepDeg = 90
        let steps = PhaseReferenceLibrary.inPlaneSteps(settings)
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps.first, 0)
        XCTAssertLessThan(steps.last!, 2 * .pi)
        settings.inPlaneStepDeg = 0
        XCTAssertEqual(PhaseReferenceLibrary.inPlaneSteps(settings), [0])
        settings.inPlaneStepDeg = .nan
        XCTAssertEqual(PhaseReferenceLibrary.inPlaneSteps(settings), [0])
    }

    /// Mutation: `chanceMatchFraction` using radius instead of radius², or
    /// dropping the `min(1, …)` clamp so it reports a probability above one.
    func testChanceMatchFractionIsAnAreaRatioAndIsClamped() {
        let entry = PhaseOrientationReference(
            phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1), inPlaneRotationRad: 0,
            vectors: (0..<10).map {
                ReferenceVector(h: $0, k: 0, l: 0, q: SIMD2(Double($0) * 0.1, 0),
                                length: Double($0) * 0.1, relativeIntensity: 1)
            })
        // 10 discs of radius 0.02 in a disc of radius 1: 10 × 0.0004 / 1.
        XCTAssertEqual(entry.chanceMatchFraction(pairRadius: 0.02, accessibleRadius: 1),
                       0.004, accuracy: 1e-12)
        // Doubling the radius quadruples it — an area, not a length.
        XCTAssertEqual(entry.chanceMatchFraction(pairRadius: 0.04, accessibleRadius: 1),
                       0.016, accuracy: 1e-12)
        XCTAssertEqual(entry.chanceMatchFraction(pairRadius: 1, accessibleRadius: 1), 1)
        XCTAssertEqual(entry.chanceMatchFraction(pairRadius: 0.02, accessibleRadius: 0), 0)
    }

    // MARK: The matcher

    /// Mutation: `len > directBeamRadius` weakened to `len >= 0`, or the
    /// origin subtraction dropped. The direct beam is the brightest peak in
    /// every pattern and would match the shortest reference vector of every
    /// phase at once.
    func testExperimentalVectorsSubtractTheOriginAndDropTheDirectBeam() {
        let peaks = [
            BraggPeak(x: 128, y: 128, intensity: 100),      // the direct beam
            BraggPeak(x: 148, y: 128, intensity: 5),        // +20 px in x
            BraggPeak(x: 128, y: 108, intensity: 5),        // −20 px in y
        ]
        let vectors = PhaseVectorMatcher.experimentalVectors(
            peaks: peaks, originX: 128, originY: 128, invAngstromPerPixel: 0.01,
            directBeamRadiusInvAngstrom: 0.05)
        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(vectors[0].y, 0, accuracy: 1e-9)
        // y is NOT flipped: a peak at a smaller row gives a negative q_y, the
        // same sense `OrientationMatcher.prepareExperimentalFFT` uses.
        XCTAssertEqual(vectors[1].y, -0.2, accuracy: 1e-9)
    }

    /// Mutation: the `bestD <= radius` test dropped, so `nearest` always
    /// returns its closest vector however far away it is — which turns every
    /// pattern into a match for every phase.
    ///
    /// THE ANGULAR PROBE IS THE ONE THAT BITES, and the first version of this
    /// test did not have it. Every radial probe is caught by the length-band
    /// prune before the clamp is ever consulted — a reference outside
    /// `|u| ± radius` is never even visited, so `best` stays −1 and the
    /// function returns nil whether the clamp is there or not. Only a
    /// reference at the SAME |q| and a different azimuth reaches the clamp.
    /// Measured 2026-09-12: with only radial probes this test passed against
    /// the mutation it names.
    func testNearestRespectsThePairRadius() {
        let refs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.5, 0), length: 0.5, relativeIntensity: 1),
            ReferenceVector(h: 2, k: 0, l: 0, q: SIMD2(0.9, 0), length: 0.9, relativeIntensity: 1),
        ]
        let hit = PhaseVectorMatcher.nearest(SIMD2(0.51, 0), in: refs, radius: 0.02)
        XCTAssertEqual(hit?.index, 0)
        XCTAssertEqual(hit?.distance ?? .nan, 0.01, accuracy: 1e-12)
        XCTAssertNil(PhaseVectorMatcher.nearest(SIMD2(0.7, 0), in: refs, radius: 0.02))
        XCTAssertNil(PhaseVectorMatcher.nearest(SIMD2(0.5, 0), in: [], radius: 0.02))
        // Same |q| as the first reference, 90° away: inside the length band,
        // 0.707 Å⁻¹ from any reference. Only the clamp refuses it.
        XCTAssertNil(PhaseVectorMatcher.nearest(SIMD2(0, 0.5), in: refs, radius: 0.02),
                     "a reference at the same |q| but 90° away was accepted as a match")
        // And a near miss in angle alone, just outside the radius.
        let a = 0.05 / 0.5      // arc ≈ chord at this scale
        XCTAssertNil(PhaseVectorMatcher.nearest(SIMD2(0.5 * cos(a), 0.5 * sin(a)),
                                                in: refs, radius: 0.02))
    }

    /// Mutation: the binary search's lower bound computed from `uLen` rather
    /// than `uLen − radius`, which silently skips the reference just inside
    /// the band. Only vectors whose |q| is slightly ABOVE the reference's
    /// expose it, so both directions are probed.
    func testTheLengthBandPruneFindsMatchesOnBothSidesOfTheBand() {
        let refs = (1...40).map {
            ReferenceVector(h: $0, k: 0, l: 0, q: SIMD2(Double($0) * 0.05, 0),
                            length: Double($0) * 0.05, relativeIntensity: 1)
        }
        for i in 1...40 {
            let exact = Double(i) * 0.05
            for offset in [-0.015, 0.015] {
                let hit = PhaseVectorMatcher.nearest(
                    SIMD2(exact + offset, 0), in: refs, radius: 0.02)
                XCTAssertEqual(hit?.index, i - 1,
                               "missed the reference at |q| = \(exact) from \(offset)")
            }
        }
    }

    /// Mutation: `minimumVectors` compared with `>` rather than `>=`, or the
    /// matrix branch returning `.notIndexed`. A pattern that is pure matrix is
    /// the commonest case in a real scan — it must not be an unknown.
    func testTooLittleSurvivingMeansTheMatrixByExclusion() throws {
        let library = try smallLibrary()
        let matrixEntry = library.entries[library.matrixEntryIndices[0]]
        let scratch = PhaseVectorMatcher.Scratch(capacity: 64)
        // Every vector taken from the matrix's own reference set.
        let vectors = matrixEntry.vectors.prefix(6).map(\.q)
        let result = PhaseVectorMatcher.classify(
            vectors: Array(vectors), library: library, settings: PhaseVectorSettings(),
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(result.verdict, .matrix)
        XCTAssertEqual(Int(result.phaseIndex), library.matrixPhaseIndex)
        XCTAssertEqual(Int(result.removedCount), 6)
        XCTAssertEqual(Int(result.survivingCount), 0)
    }

    /// Mutation: the `notIndexedAboveInvAngstrom` comparison inverted or
    /// removed, so an unexplained pattern is forced into whichever phase
    /// happened to score least badly. The refusal IS the feature.
    ///
    /// TWO CASES, and the first version of this test had only the second.
    /// Vectors pointing nowhere are refused by the ELIGIBILITY guards
    /// (`minimumMatchedVectors`, `chanceMatchMultiple`) long before the
    /// threshold is consulted, so that case passes against the mutation it
    /// names — measured 2026-09-12. What reaches the threshold is a pattern
    /// that matches a phase's vectors well enough to be eligible and not well
    /// enough to be called: an offset INSIDE the pair radius and ABOVE the
    /// not-indexed distance.
    func testUnexplainedVectorsAreNotIndexedRatherThanLabelled() throws {
        let library = try smallLibrary()
        let settings = PhaseVectorSettings()
        let scratch = PhaseVectorMatcher.Scratch(capacity: 256)

        // Case 1 — eligible, but too far to call. Every vector is a real β″
        // reference displaced by 0.015 Å⁻¹: inside the 0.020 pair radius, above
        // the 0.010 not-indexed distance.
        let entry = library.entries[library.candidateEntryIndices[0]]
        XCTAssertGreaterThan(settings.pairRadiusInvAngstrom, 0.015)
        XCTAssertLessThan(settings.notIndexedAboveInvAngstrom, 0.015)
        let displaced = entry.vectors.prefix(10).map { $0.q + SIMD2(0.015, 0) }
        let nearMiss = PhaseVectorMatcher.classify(
            vectors: Array(displaced), library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(nearMiss.verdict, .notIndexed,
                       "a pattern 0.015 Å⁻¹ off every reference was called a phase")
        XCTAssertGreaterThan(nearMiss.matchedCount, 0,
                             "the near-miss case never reached the threshold")
        XCTAssertTrue(nearMiss.score.isFinite,
                      "a refused position must still carry the numbers behind the refusal")
        XCTAssertEqual(nearMiss.phaseIndex, -1)
        XCTAssertEqual(nearMiss.entryIndex, -1)

        // Case 2 — vectors on a ring no phase has a reflection near. Refused
        // by the eligibility guards, which is a different mechanism.
        let elsewhere = (0..<8).map { i -> SIMD2<Double> in
            let a = Double(i) * .pi / 4
            return SIMD2(0.313 * cos(a), 0.313 * sin(a))
        }
        let unknown = PhaseVectorMatcher.classify(
            vectors: elsewhere, library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(unknown.verdict, .notIndexed)
        XCTAssertEqual(unknown.phaseIndex, -1)
    }

    /// Mutation: `classify` returning `.notIndexed` for an empty pattern.
    /// "No peaks here" and "peaks I cannot explain" are different facts about
    /// the specimen and must not share a colour on the map.
    func testAnEmptyPatternIsNoDataNotNotIndexed() throws {
        let library = try smallLibrary()
        let result = PhaseVectorMatcher.classify(
            vectors: [], library: library, settings: PhaseVectorSettings(),
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 64))
        XCTAssertEqual(result.verdict, .noData)
        XCTAssertEqual(result.survivingCount, 0)
    }

    /// Mutation: `score` averaging over MATCHED vectors instead of unique
    /// references. Two experimental vectors claiming one reference must count
    /// once, at the better distance — otherwise a split peak halves the score
    /// of whichever phase happens to sit between its two halves.
    func testScoreAveragesOverUniqueReferencesAtTheirBestDistance() {
        let refs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.5, 0), length: 0.5, relativeIntensity: 1),
        ]
        let entry = PhaseOrientationReference(phaseIndex: 1, zoneAxis: SIMD3(0, 0, 1),
                                              inPlaneRotationRad: 0, vectors: refs)
        let scored = PhaseVectorMatcher.score(
            vectors: [SIMD2(0.504, 0), SIMD2(0.512, 0)], against: entry,
            pairRadius: 0.02, scratch: PhaseVectorMatcher.Scratch(capacity: 8))
        XCTAssertEqual(scored?.matched, 2)
        XCTAssertEqual(scored?.uniqueReferences, 1)
        XCTAssertEqual(scored?.score ?? .nan, 0.004, accuracy: 1e-12)
    }

    /// Mutation: `Scratch.bestPerRef` not reset after a call, so the second
    /// entry scored with the same scratch inherits the first's distances.
    /// Nothing else in the suite would notice — every other test scores once.
    func testScratchIsReusableWithoutCarryingStateBetweenCalls() {
        let entry = PhaseOrientationReference(
            phaseIndex: 1, zoneAxis: SIMD3(0, 0, 1), inPlaneRotationRad: 0,
            vectors: [ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.5, 0),
                                      length: 0.5, relativeIntensity: 1)])
        let scratch = PhaseVectorMatcher.Scratch(capacity: 8)
        let first = PhaseVectorMatcher.score(vectors: [SIMD2(0.5, 0)], against: entry,
                                             pairRadius: 0.02, scratch: scratch)
        XCTAssertEqual(first?.score ?? .nan, 0, accuracy: 1e-15)
        let second = PhaseVectorMatcher.score(vectors: [SIMD2(0.515, 0)], against: entry,
                                              pairRadius: 0.02, scratch: scratch)
        XCTAssertEqual(second?.score ?? .nan, 0.015, accuracy: 1e-12)
        // 90° away at the same |q|: inside the length band, so this reaches the
        // radius clamp rather than being pruned before it (see
        // `testNearestRespectsThePairRadius`).
        let third = PhaseVectorMatcher.score(vectors: [SIMD2(0, 0.5)], against: entry,
                                             pairRadius: 0.02, scratch: scratch)
        XCTAssertNil(third, "a reference outside the radius still counted as matched")
    }

    /// Mutation: `map` accepting a `BraggVectors` whose `peaks` count does not
    /// match `scanWidth * scanHeight`, which would index out of bounds on the
    /// first short row rather than refuse.
    func testMapRefusesAMalformedScan() throws {
        let library = try smallLibrary()
        let malformed = BraggVectors(scanWidth: 4, scanHeight: 4, peaks: [[], [], []])
        XCTAssertNil(PhaseVectorMatcher.map(
            bragg: malformed, library: library, settings: PhaseVectorSettings(),
            originX: 0, originY: 0, invAngstromPerPixel: 0.01))
    }

    /// Mutation: BOTH `guard cancellation?.isCancelled != true` lines in `map`
    /// removed, so a cancelled run returns a half-filled map presented as a
    /// finished one.
    ///
    /// Both, and stated that way because it was measured: removing either one
    /// alone leaves this test passing (2026-09-12), because the other still
    /// returns nil. They are redundant BY DESIGN — one saves the scan's work,
    /// one guarantees the answer — and a test with a pre-cancelled token can
    /// only see that at least one survives. What it does guarantee is the
    /// property that matters to a caller: a cancelled run never hands back a
    /// partial map wearing the look of a finished one.
    func testACancelledRunReturnsNothingRatherThanAPartialMap() throws {
        let library = try smallLibrary()
        let token = AnalysisCancellationToken()
        token.cancel()
        let bragg = BraggVectors(scanWidth: 2, scanHeight: 2,
                                 peaks: Array(repeating: [], count: 4))
        XCTAssertNil(PhaseVectorMatcher.map(
            bragg: bragg, library: library, settings: PhaseVectorSettings(),
            originX: 0, originY: 0, invAngstromPerPixel: 0.01, cancellation: token))
    }

    /// Mutation: any coordinate of the published β″ structure, or the C2/m
    /// expansion collapsing a 4i site to 2. The cell content is what the paper
    /// states and is the only independent check on a hand-entered structure.
    func testBetaDoublePrimeMatchesThePublishedCellContent() {
        let beta = Crystal.betaDoublePrime
        XCTAssertEqual(beta.sites.count, 22)
        XCTAssertEqual(beta.sites.filter { $0.z == 12 }.count, 10)   // Mg
        XCTAssertEqual(beta.sites.filter { $0.z == 14 }.count, 12)   // Si
        XCTAssertEqual(beta.a, 15.16, accuracy: 1e-12)
        XCTAssertEqual(beta.b, 4.05, accuracy: 1e-12)
        XCTAssertEqual(beta.c, 6.74, accuracy: 1e-12)
        XCTAssertEqual(beta.betaDeg, 105.3, accuracy: 1e-12)
        // No two sites coincide — a collapsed expansion would double an atom
        // and multiply straight into every structure factor.
        for i in beta.sites.indices {
            for j in (i + 1)..<beta.sites.count {
                let d = beta.sites[i].fractional - beta.sites[j].fractional
                XCTAssertGreaterThan(simd_length(d), 1e-6)
            }
        }
        XCTAssertTrue(beta.unsupportedElements.isEmpty)

        // THE CELL CONTENT DOES NOT PIN THE COORDINATES, and the first version
        // of this test stopped above. Measured 2026-09-12: changing Si3's z
        // from 0.617 to 0.671 — a transposed pair of digits, the likeliest
        // transcription error there is — left every assertion above passing,
        // and the gated harness too, because |q(h0l)| depends on the CELL and
        // not on where the atoms sit inside it. So the six published sites are
        // pinned directly against Andersen et al. 1998, Table 3 set 3: a
        // reader can check these six rows against the paper, which is the only
        // independent check a hand-entered structure can have.
        let published: [(Int, Double, Double)] = [
            (12, 0.0,    0.0),      // Mg1, 2a
            (12, 0.3459, 0.089),    // Mg2
            (12, 0.430,  0.652),    // Mg3
            (14, 0.0565, 0.649),    // Si1
            (14, 0.1885, 0.224),    // Si2
            (14, 0.2171, 0.617),    // Si3
        ]
        for (z, x, zc) in published {
            let present = beta.sites.contains {
                $0.z == z && abs($0.fractional.x - x) < 1e-12
                    && abs($0.fractional.y) < 1e-12 && abs($0.fractional.z - zc) < 1e-12
            }
            XCTAssertTrue(present, "the published site Z=\(z) (\(x), 0, \(zc)) is not in the cell")
        }

        // And one physical consequence, so a coordinate that is wrong in a way
        // the list above would not catch (a whole site replaced, say) still
        // has somewhere to fail: no two atoms may sit closer than a real Mg-Si
        // or Si-Si contact.
        var shortest = Double.infinity
        for i in beta.sites.indices {
            for j in (i + 1)..<beta.sites.count {
                for dx in -1...1 {
                    for dz in -1...1 {
                        var d = beta.sites[i].fractional - beta.sites[j].fractional
                        d.x += Double(dx); d.z += Double(dz)
                        let cart = d.x * beta.latReal[0] + d.y * beta.latReal[1]
                            + d.z * beta.latReal[2]
                        shortest = min(shortest, simd_length(cart))
                    }
                }
            }
        }
        XCTAssertGreaterThan(shortest, 2.0,
                             "shortest interatomic contact \(shortest) Å is not chemistry")
        XCTAssertLessThan(shortest, 3.2,
                          "shortest interatomic contact \(shortest) Å — the cell is not bonded")
    }

    // MARK: Fixtures

    private func coarseSettings() -> PhaseReferenceSettings {
        var s = PhaseReferenceSettings()
        s.kMaxInvAngstrom = 1.0
        s.inPlaneStepDeg = 90
        return s
    }

    private func matrixAluminium() -> PhaseDefinition {
        PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                        role: .matrix, zoneAxes: [SIMD3(0, 0, 1)])
    }

    private func candidateBeta() -> PhaseDefinition {
        PhaseDefinition(id: "beta", displayName: "β″", crystal: .betaDoublePrime,
                        role: .candidate, zoneAxes: [SIMD3(0, 1, 0)])
    }

    private func smallLibrary() throws -> PhaseReferenceLibrary {
        try PhaseReferenceLibrary.build(phases: [matrixAluminium(), candidateBeta()],
                                        settings: coarseSettings())
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
}

/// The two Gate B findings that were fixed in Core rather than only recorded
/// (2026-09-12). Both were invisible to every check that existed at the time.
final class PhaseVectorGateBTests: XCTestCase {

    /// Gate B finding 9. `gcd` floored itself at 1, so `gcd(0, 0)` returned 1
    /// and `[0 0 2]` never reduced — the list held it beside `[0 0 1]`, 50
    /// entries for 49 directions, and 180 redundant library entries per phase
    /// at the default step. Redundant entries are not merely wasted work: each
    /// is one more comparison in the best-of-N search every scan position runs.
    ///
    /// Mutation: `return a` in `gcd` put back to `return max(a, 1)`.
    func testLowIndexZoneAxesAreReducedAndDistinct() {
        let axes = PhaseReferenceLibrary.lowIndexZoneAxes
        XCTAssertFalse(axes.isEmpty)
        func gcd(_ a: Int, _ b: Int) -> Int {
            var a = abs(a), b = abs(b)
            while b != 0 { (a, b) = (b, a % b) }
            return a
        }
        for axis in axes {
            let g = gcd(gcd(axis.x, axis.y), axis.z)
            XCTAssertEqual(g, 1, "[\(axis.x) \(axis.y) \(axis.z)] is reducible by \(g)")
        }
        // No two entries name the same direction, in either sense.
        for i in axes.indices {
            for j in (i + 1)..<axes.count {
                let a = axes[i], b = axes[j]
                let parallel = a.x * b.y == a.y * b.x
                    && a.y * b.z == a.z * b.y && a.x * b.z == a.z * b.x
                XCTAssertFalse(parallel,
                               "[\(a.x) \(a.y) \(a.z)] and [\(b.x) \(b.y) \(b.z)] are the same axis")
            }
        }
    }

    /// Gate B finding 6. The chance expectation is computed over the area the
    /// DATA occupies, and that radius used to be `max |u|` — so one spurious
    /// maximum far from the others inflated the area, weakened the guard for
    /// every other vector in the same pattern, and turned refusals into
    /// labels. Measured by the reviewer at 10 false positives in 1024
    /// patterns; second-largest makes it 0.
    ///
    /// Mutation: `accessibleRadius` put back to the running maximum.
    func testOneDistantSpuriousPeakDoesNotWeakenTheChanceGuard() throws {
        let library = try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: .betaDoublePrime,
                            role: .candidate, zoneAxes: [SIMD3(0, 1, 0)]),
        ], settings: {
            var s = PhaseReferenceSettings()
            s.kMaxInvAngstrom = 1.2
            s.inPlaneStepDeg = 2
            return s
        }())
        let settings = PhaseVectorSettings()
        let scratch = PhaseVectorMatcher.Scratch(
            capacity: library.entries.map(\.vectors.count).max() ?? 1)

        // Deterministic: a gate that is not reproducible is not a gate.
        var state: UInt64 = 0xD1B5_4A32_D192_ED03
        func uniform() -> Double {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return Double((state &* 2685821657736338717) >> 11) * (1.0 / 9007199254740992.0)
        }
        var indexedWithOutlier = 0, indexedWithout = 0
        for _ in 0..<1024 {
            var vectors: [SIMD2<Double>] = []
            for _ in 0..<8 {
                let r = 0.25 + 0.15 * uniform(), a = 2 * Double.pi * uniform()
                vectors.append(SIMD2(r * cos(a), r * sin(a)))
            }
            func verdict(_ v: [SIMD2<Double>]) -> PhaseVerdict {
                PhaseVectorMatcher.classify(
                    vectors: v, library: library, settings: settings, matrixEntry: nil,
                    candidateEntryIndices: library.candidateEntryIndices, scratch: scratch
                ).verdict
            }
            if verdict(vectors) == .indexed { indexedWithout += 1 }
            if verdict(vectors + [SIMD2(1.15, 0)]) == .indexed { indexedWithOutlier += 1 }
        }
        XCTAssertEqual(indexedWithout, 0,
                       "random vectors were indexed even without an outlier")
        XCTAssertEqual(indexedWithOutlier, 0,
                       "\(indexedWithOutlier) of 1024 random patterns became a phase "
                       + "because one distant peak widened the chance expectation")
    }
}

/// The two things the owner's 2026-09-12 run needed the app to say and it
/// said neither: what a tolerance in Å⁻¹ means on the detector in front of
/// you, and why a map came back empty.
final class PhaseVectorResolutionTests: XCTestCase {

    /// The owner's own cube: 0.045741 Å⁻¹ per detector pixel after 4× binning.
    /// The shipped 0.020 Å⁻¹ tolerances are 0.44 of one pixel there, matrix
    /// removal removed nothing at all, and 108 899 of 108 900 positions came
    /// back "not indexed".
    ///
    /// Mutation: `pairRadiusPixels` computed as `scale / setting` (inverted),
    /// which is the easiest way to get a unit conversion backwards and would
    /// read as a comfortable 2.29 px instead of a hopeless 0.44.
    func testTolerancesAreReportedInDetectorPixels() {
        let resolution = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                               invAngstromPerPixel: 0.045741477608680726)
        XCTAssertEqual(resolution.pairRadiusPixels, 0.437, accuracy: 0.001)
        XCTAssertEqual(resolution.matrixRemovalPixels, 0.437, accuracy: 0.001)
        XCTAssertEqual(resolution.notIndexedAbovePixels, 0.219, accuracy: 0.001)
        // A finer detector meets the same settings comfortably, which is what
        // makes the number worth showing rather than the setting worth banning.
        let fine = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                         invAngstromPerPixel: 0.008)
        XCTAssertEqual(fine.pairRadiusPixels, 2.5, accuracy: 1e-9)
        XCTAssertNil(fine.advice, "a detector that can meet the tolerance was warned about")
    }

    /// Mutation: the `pairRadiusPixels < 1` guard removed or inverted. A
    /// warning that fires on every dataset is one nobody reads.
    func testAdviceFiresOnlyWhenTheToleranceIsUnderOnePixel() {
        func advice(_ scale: Double) -> String? {
            PhaseVectorResolution(settings: PhaseVectorSettings(),
                                  invAngstromPerPixel: scale).advice
        }
        XCTAssertNotNil(advice(0.045741477608680726))
        XCTAssertNotNil(advice(0.0201))
        XCTAssertNil(advice(0.0199), "0.02 Å⁻¹ over a 0.0199 Å⁻¹ pixel is 1.005 px")
        XCTAssertNil(advice(0.008))
        XCTAssertNil(advice(0), "an uncalibrated detector has no pixel to compare against")
        XCTAssertTrue(advice(0.045741477608680726)?.contains("0.44") ?? false,
                      "the advice must carry the number: \(advice(0.045741477608680726) ?? "nil")")
    }

    /// Mutation: `scaledToDetector` setting the verdict distance equal to the
    /// pair radius rather than half of it. The pair radius says what COULD be
    /// the same reflection; the verdict distance says what is close enough to
    /// call — equal values collapse the distinction and index everything the
    /// pair radius admits.
    func testScalingToTheDetectorKeepsTheShippedRatio() {
        let scale = 0.045741477608680726
        let scaled = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                           invAngstromPerPixel: scale)
            .scaledToDetector(PhaseVectorSettings())
        XCTAssertEqual(scaled.pairRadiusInvAngstrom, scale, accuracy: 1e-12)
        XCTAssertEqual(scaled.matrixToleranceInvAngstrom, scale, accuracy: 1e-12)
        XCTAssertEqual(scaled.notIndexedAboveInvAngstrom, scale / 2, accuracy: 1e-12)
        XCTAssertLessThan(scaled.notIndexedAboveInvAngstrom, scaled.pairRadiusInvAngstrom)
        // The direct beam is only ever widened, never narrowed: a user who set
        // it wide for a big probe must not have it cut by a scaling action.
        var wide = PhaseVectorSettings()
        wide.directBeamRadiusInvAngstrom = 0.5
        let keptWide = PhaseVectorResolution(settings: wide, invAngstromPerPixel: scale)
            .scaledToDetector(wide)
        XCTAssertEqual(keptWide.directBeamRadiusInvAngstrom, 0.5, accuracy: 1e-12)
        // And a run with no Q calibration changes nothing at all.
        let uncalibrated = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                                 invAngstromPerPixel: 0)
            .scaledToDetector(PhaseVectorSettings())
        XCTAssertEqual(uncalibrated, PhaseVectorSettings())
    }

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
