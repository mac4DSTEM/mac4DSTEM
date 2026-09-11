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
