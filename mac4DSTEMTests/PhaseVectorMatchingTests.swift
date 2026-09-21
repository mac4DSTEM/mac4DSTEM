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

    // MARK: Staleness follows the list order

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

    // MARK: The reciprocal lattice the library is built from

    /// Every lattice point inside kMax, enumerated over a tile far larger than
    /// any bound the code could pick. Ground truth is the lattice itself: a
    /// one-atom P1 cell has no extinction and `f_e > 0`, so every one of these
    /// must be returned; an fcc cell must return exactly the all-even /
    /// all-odd subset.
    private func latticePoints(_ crystal: Crystal, kMax: Double, tile: Int = 48) -> Set<SIMD3<Int>> {
        var out = Set<SIMD3<Int>>()
        for h in -tile...tile { for k in -tile...tile { for l in -tile...tile {
            if h == 0 && k == 0 && l == 0 { continue }
            let g = Double(h) * crystal.latInv[0] + Double(k) * crystal.latInv[1]
                + Double(l) * crystal.latInv[2]
            if simd_length(g) <= kMax { out.insert(SIMD3(h, k, l)) }
        } } }
        return out
    }

    /// Mutation: the tile bound `ceil(kMax / kMin)` that stood until
    /// 2026-09-14 (and still stands in py4DSTEM). The exact bound on an index
    /// is |h| = |g·a₁| ≤ kMax·|a₁|, and for a b-unique monoclinic cell
    /// 1/kMin ≤ a·sin β < a, so the old tile fell short as β left 90° and
    /// reflections went missing with no signal. Gate B measured 6 lost at
    /// β = 110°, 48 at 115°, 198 at 125° on the β″-shaped cell (open-items,
    /// 2026-09-12); this pins the 125° case against the lattice and the
    /// shipped cells against their own extinction rules, so a bound that
    /// over-tiles is not caught here — only one that under-tiles.
    func testReflectionsCoverEveryLatticePointInsideKMaxOnObliqueCells() {
        let kMax = 1.6
        for betaDeg in [105.3, 115.0, 125.0] {
            let cell = Crystal(a: 15.16, b: 4.05, c: 6.74, betaDeg: betaDeg,
                               sites: [AtomSite(z: 13, fractional: SIMD3(0, 0, 0))])
            let expected = latticePoints(cell, kMax: kMax)
            let got = Set(cell.reflections(kMax: kMax).map { SIMD3($0.h, $0.k, $0.l) })
            XCTAssertEqual(got.count, expected.count,
                           "β = \(betaDeg)°: \(expected.subtracting(got).count) lattice points "
                           + "inside kMax are missing, e.g. \(expected.subtracting(got).prefix(3))")
            XCTAssertTrue(got.isSubset(of: expected), "β = \(betaDeg)°: a reflection outside kMax")
        }
        // The shipped cells, against their space groups: fcc keeps hkl of one
        // parity; β″ (C2/m) keeps h + k even. Both must be complete AND exact.
        let al = Crystal.fcc(a: 4.05, z: 13)
        let alExpected = latticePoints(al, kMax: kMax).filter {
            ($0.x & 1) == ($0.y & 1) && ($0.y & 1) == ($0.z & 1)
        }
        let alGot = Set(al.reflections(kMax: kMax).map { SIMD3($0.h, $0.k, $0.l) })
        XCTAssertEqual(alGot, alExpected)
        // Tolerance 1e-9, not the default 1e-4: 38 allowed β″ reflections are
        // accidentally weak enough to fall under the default (measured
        // 2026-09-14), and this asserts the LATTICE, not the intensity cut.
        let beta = Crystal.betaDoublePrime
        let betaExpected = latticePoints(beta, kMax: kMax).filter { ($0.x + $0.y) & 1 == 0 }
        let betaGot = Set(beta.reflections(kMax: kMax, tolerance: 1e-9).map { SIMD3($0.h, $0.k, $0.l) })
        XCTAssertEqual(betaGot, betaExpected)
    }

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
    /// shipped one of those before (`docs/archive/development-process-2026-08-31.md`, the L4
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

    /// The outer reach (`maximumVectorInvAngstrom`, 2026-09-15): a vector at
    /// or beyond it is dropped, 0 keeps everything. Mutations: `<` to `<=`
    /// (the vector AT the reach survives), the guard dropped (both survive).
    func testTheOuterReachDropsVectorsAtAndBeyondIt() {
        let peaks = [
            BraggPeak(x: 128, y: 128, intensity: 100),
            BraggPeak(x: 148, y: 128, intensity: 5),        // 0.20 Å⁻¹
            BraggPeak(x: 168, y: 128, intensity: 5),        // 0.40 Å⁻¹, at the reach
            BraggPeak(x: 128, y: 178, intensity: 5),        // 0.50 Å⁻¹, beyond it
        ]
        func vectors(reach: Double) -> [SIMD2<Double>] {
            PhaseVectorMatcher.experimentalVectors(
                peaks: peaks, originX: 128, originY: 128, invAngstromPerPixel: 0.01,
                directBeamRadiusInvAngstrom: 0.05, maximumVectorInvAngstrom: reach)
        }
        XCTAssertEqual(vectors(reach: 0).count, 3, "0 is not a reach")
        let capped = vectors(reach: 0.4)
        XCTAssertEqual(capped.count, 1, "the vector at the reach or beyond survived: \(capped)")
        XCTAssertEqual(capped.first?.x ?? 0, 0.2, accuracy: 1e-9)
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

    /// Mutation: the fall-back firing at its default of 0; the fraction
    /// compared with `>` so a position exactly at the bar is lost;
    /// `survivingCount` used in place of `removedCount`, which inverts it.
    ///
    /// The fall-back exists because a position is otherwise called matrix only
    /// by EXCLUSION, never because the matrix explains it, so improving
    /// detection turns matrix positions into refusals (measured 2026-09-16,
    /// `open-items.md`). It ships OFF, and this test pins that first: the
    /// default must be a refusal, because a silent matrix verdict overstates
    /// the phase fraction this feature exists to report.
    func testTheMatrixFallBackIsOffByDefaultAndFiresOnlyAboveItsFraction() throws {
        let library = try smallLibrary()
        let matrixEntry = library.entries[library.matrixEntryIndices[0]]
        let scratch = PhaseVectorMatcher.Scratch(capacity: 64)
        // Six vectors the matrix explains, plus three on a ring no phase has a
        // reflection near: too many survive for the by-exclusion branch, and
        // nothing clears the candidate guards. Explained fraction 6 / 9 = 0.667.
        let explained = matrixEntry.vectors.prefix(6).map(\.q)
        let unexplainable = (0..<3).map { i -> SIMD2<Double> in
            let a = Double(i) * .pi / 4
            return SIMD2(0.313 * cos(a), 0.313 * sin(a))
        }
        let vectors = Array(explained) + unexplainable

        var settings = PhaseVectorSettings()
        XCTAssertEqual(settings.matrixFallbackExplainedFraction, 0,
                       "the fall-back must ship off -- it converts an honest refusal "
                       + "into a positive matrix claim")
        let refused = PhaseVectorMatcher.classify(
            vectors: vectors, library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(refused.verdict, .notIndexed,
                       "at the default the position must be refused, not called matrix")
        XCTAssertEqual(Int(refused.removedCount), 6)
        XCTAssertEqual(Int(refused.survivingCount), 3)

        settings.matrixFallbackExplainedFraction = 0.5
        let taken = PhaseVectorMatcher.classify(
            vectors: vectors, library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(taken.verdict, .matrix,
                       "0.667 explained is above the 0.5 bar, so the matrix takes it")
        XCTAssertEqual(Int(taken.phaseIndex), library.matrixPhaseIndex)
        XCTAssertEqual(Int(taken.entryIndex), -1)

        settings.matrixFallbackExplainedFraction = 0.8
        let stillRefused = PhaseVectorMatcher.classify(
            vectors: vectors, library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(stillRefused.verdict, .notIndexed,
                       "0.667 explained is below the 0.8 bar -- the fraction must be compared, "
                       + "not merely tested for being armed")
    }

    /// Mutation: the `notIndexedAboveInvAngstrom` comparison inverted or
    /// removed, so an unexplained pattern is forced into whichever phase
    /// happened to score least badly. The refusal IS the feature. Also: the
    /// score's mean replaced by its max (case 1b).
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
        // reference displaced by 0.018 Å⁻¹: inside the 0.020 pair radius, above
        // the 0.015 not-indexed distance (0.75 of the radius since 2026-09-15).
        let entry = library.entries[library.candidateEntryIndices[0]]
        XCTAssertGreaterThan(settings.pairRadiusInvAngstrom, 0.018)
        XCTAssertLessThan(settings.notIndexedAboveInvAngstrom, 0.018)
        let displaced = entry.vectors.prefix(10).map { $0.q + SIMD2(0.018, 0) }
        let nearMiss = PhaseVectorMatcher.classify(
            vectors: Array(displaced), library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(nearMiss.verdict, .notIndexed,
                       "a pattern 0.018 Å⁻¹ off every reference was called a phase")
        XCTAssertGreaterThan(nearMiss.matchedCount, 0,
                             "the near-miss case never reached the threshold")
        XCTAssertTrue(nearMiss.score.isFinite,
                      "a refused position must still carry the numbers behind the refusal")
        XCTAssertEqual(nearMiss.phaseIndex, -1)
        XCTAssertEqual(nearMiss.entryIndex, -1)

        // Case 1b — NON-uniform residuals (Gate B 2026-09-15: every case above
        // displaces every vector identically, so a `max` or a median in place
        // of the mean was invisible). Half the vectors 0.012 off, half 0.017
        // off: mean 0.0145 is under the 0.015 verdict distance, the largest is
        // over it. The mean is the rule, so this is called.
        let mixed = entry.vectors.prefix(10).enumerated().map { i, v in
            v.q + SIMD2(i < 5 ? 0.012 : 0.017, 0)
        }
        let called = PhaseVectorMatcher.classify(
            vectors: Array(mixed), library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(called.verdict, .indexed,
                       "a pattern whose MEAN residual is under the verdict distance was refused "
                       + "-- mutation: the score is not the mean (max or median)")

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

    /// Mutation: `classify` reading `pairRadiusInvAngstrom` for the matrix
    /// removal, or `matrixToleranceInvAngstrom` for the candidate scoring.
    /// Both ship at 0.02, so the conflation was invisible to every check
    /// (Gate B mutation E, 2026-09-12) — this fixture sets them 0.005 and
    /// 0.020 and displaces every vector by 0.012, between the two.
    func testMatrixRemovalAndCandidateScoringReadTheirOwnRadii() throws {
        let library = try smallLibrary()
        var settings = PhaseVectorSettings()
        settings.matrixToleranceInvAngstrom = 0.005
        settings.pairRadiusInvAngstrom = 0.020
        let scratch = PhaseVectorMatcher.Scratch(capacity: 256)
        let matrixEntry = library.entries[library.matrixEntryIndices[0]]
        let candidate = library.entries[library.candidateEntryIndices[0]]
        let d = SIMD2(0.012, 0.0)
        let offMatrix = matrixEntry.vectors.prefix(6).map { $0.q + d }
        let offCandidate = candidate.vectors.prefix(10).map { $0.q + d }
        let result = PhaseVectorMatcher.classify(
            vectors: offMatrix + offCandidate, library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices,
            scratch: scratch)
        XCTAssertEqual(result.removedCount, 0,
                       "a vector 0.012 off the matrix, with a 0.005 tolerance, was removed: "
                       + "matrix removal read the pair radius")
        XCTAssertEqual(result.survivingCount, 16)
        XCTAssertGreaterThanOrEqual(result.matchedCount, 3,
                                    "candidate vectors 0.012 off, within a 0.020 pair radius, "
                                    + "were not matched: scoring read the matrix tolerance")
    }

    /// The orientation relationship, stated as parallel lattice vectors
    /// (2026-09-15, replacing a library-frame degree list; the Gate D record
    /// is the step 3 entry of `docs/open-items.md`):
    /// `PhaseDefinition.orientationRelationships` restricts a candidate
    /// entry to ones whose DERIVED azimuth (`PhaseVectorMatcher.
    /// projectedAzimuth`, from each entry's own zone and rotation) agrees
    /// with a listed pair's, relative to the fitted matrix entry. Mutations
    /// this names: the 180° fold dropped (a candidate 180° from the listed
    /// pair — equally valid, since a flat-Ewald ZOLZ excites g and −g alike
    /// — refused); the matrix azimuth ignored (as if `matrixRad` were
    /// always 0); the candidate zone's own `detectorBasis` replaced by the
    /// matrix's; a pair whose vector is not in an entry's own zone treated
    /// as applying to it anyway instead of being skipped.
    func testTheOrientationRelationshipIsStatedAsParallelVectorsAndDerivedPerZone() throws {
        // --- 1. `LatticeVector.cartesian` ---------------------------------
        let al = Crystal.aluminum
        let g200 = LatticeVector.plane(SIMD3(2, 0, 0)).cartesian(in: al)
        XCTAssertEqual(simd_length(g200), 2 / al.a, accuracy: 1e-9,
                       "(200)Al should have |g| = 2/a")
        let d100 = LatticeVector.direction(SIMD3(1, 0, 0)).cartesian(in: al)
        XCTAssertEqual(simd_length(d100 - SIMD3(al.a, 0, 0)), 0, accuracy: 1e-9,
                       "[100]Al should be a·x̂")

        // --- 2. `projectedAzimuth` -----------------------------------------
        let zoneAxis001 = try XCTUnwrap(
            PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(0, 0, 1), crystal: al),
            "Al [001] should not be degenerate")
        let basis = ACOMOrientation.detectorBasis(zoneAxis: zoneAxis001)
        let expectedAzimuth200 = atan2(simd_dot(g200, basis.columns.1),
                                       simd_dot(g200, basis.columns.0))
        let azimuth200 = try XCTUnwrap(PhaseVectorMatcher.projectedAzimuth(
            of: g200, zoneAxis: zoneAxis001, inPlaneRotationRad: 0),
            "(200) is in the [001] zone and must project")
        XCTAssertEqual(azimuth200, expectedAzimuth200, accuracy: 1e-9,
                       "the (200) azimuth must come from the entry's own detectorBasis, "
                       + "not a hardcoded angle")

        let g002 = LatticeVector.plane(SIMD3(0, 0, 2)).cartesian(in: al)
        XCTAssertNil(PhaseVectorMatcher.projectedAzimuth(
            of: g002, zoneAxis: zoneAxis001, inPlaneRotationRad: 0),
            "(002) lies along the [001] zone axis -- not in the zone, must not project")

        let theta = 30 * Double.pi / 180
        let rotatedAzimuth = try XCTUnwrap(PhaseVectorMatcher.projectedAzimuth(
            of: g200, zoneAxis: zoneAxis001, inPlaneRotationRad: theta))
        var advance = (rotatedAzimuth - azimuth200).truncatingRemainder(dividingBy: 2 * .pi)
        if advance < 0 { advance += 2 * .pi }
        XCTAssertEqual(advance, theta, accuracy: 1e-9,
                       "rotating the entry by θ should advance its azimuth by +θ")

        // --- 3. `orientationConsistent` on its own, with the expected
        // answer computed independently of the function under test --------
        //
        // 3a. Candidate and matrix share the SAME crystal, zone axis and
        // relationship vector, so the azimuth difference `orientationConsistent`
        // must compare is EXACTLY (candidate rotation − matrix rotation), no
        // crystal geometry to derive by hand.
        let sameGeometryRelationship = OrientationRelationship(
            candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(2, 0, 0)))
        func sameZoneEntry(rotationDeg: Double) -> PhaseOrientationReference {
            PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1),
                                      inPlaneRotationRad: rotationDeg * .pi / 180, vectors: [])
        }
        XCTAssertTrue(PhaseVectorMatcher.orientationConsistent(
            candidate: sameZoneEntry(rotationDeg: 8), candidateCrystal: al,
            matrix: sameZoneEntry(rotationDeg: 0), matrixCrystal: al,
            relationships: [sameGeometryRelationship], toleranceDeg: 10),
            "8° apart, within tolerance 10, was refused")
        XCTAssertFalse(PhaseVectorMatcher.orientationConsistent(
            candidate: sameZoneEntry(rotationDeg: 12), candidateCrystal: al,
            matrix: sameZoneEntry(rotationDeg: 0), matrixCrystal: al,
            relationships: [sameGeometryRelationship], toleranceDeg: 10),
            "12° apart, outside tolerance 10, was allowed")
        XCTAssertTrue(PhaseVectorMatcher.orientationConsistent(
            candidate: sameZoneEntry(rotationDeg: 171), candidateCrystal: al,
            matrix: sameZoneEntry(rotationDeg: 0), matrixCrystal: al,
            relationships: [sameGeometryRelationship], toleranceDeg: 10),
            "171° apart folds to 9° from 180° -- mutation: the 180° fold dropped")
        XCTAssertFalse(PhaseVectorMatcher.orientationConsistent(
            candidate: sameZoneEntry(rotationDeg: 169), candidateCrystal: al,
            matrix: sameZoneEntry(rotationDeg: 0), matrixCrystal: al,
            relationships: [sameGeometryRelationship], toleranceDeg: 10),
            "169° apart folds to 11° from 180°, outside tolerance")
        XCTAssertTrue(PhaseVectorMatcher.orientationConsistent(
            candidate: sameZoneEntry(rotationDeg: 95), candidateCrystal: al,
            matrix: sameZoneEntry(rotationDeg: 90), matrixCrystal: al,
            relationships: [sameGeometryRelationship], toleranceDeg: 10),
            "a candidate 5° past a matrix at 90° was refused "
            + "-- mutation: the matrix azimuth ignored")

        // 3b. Candidate and matrix now use DIFFERENT zone axes (still the
        // same crystal, to keep this arithmetic rather than crystallographic):
        // the expected offset is computed by calling `projectedAzimuth`
        // directly -- already verified in part 2 above -- not by calling
        // `orientationConsistent` and trusting whatever it says.
        let zoneAxis100 = try XCTUnwrap(
            PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(1, 0, 0), crystal: al))
        let candidateVectorB = LatticeVector.plane(SIMD3(0, 2, 0)).cartesian(in: al)
        let matrixVectorB = LatticeVector.plane(SIMD3(2, 0, 0)).cartesian(in: al)
        let az0cB = try XCTUnwrap(PhaseVectorMatcher.projectedAzimuth(
            of: candidateVectorB, zoneAxis: zoneAxis100, inPlaneRotationRad: 0)) * 180 / .pi
        let az0mB = try XCTUnwrap(PhaseVectorMatcher.projectedAzimuth(
            of: matrixVectorB, zoneAxis: zoneAxis001, inPlaneRotationRad: 0)) * 180 / .pi
        let differentZoneRelationship = OrientationRelationship(
            candidate: .plane(SIMD3(0, 2, 0)), matrix: .plane(SIMD3(2, 0, 0)))
        let thetaMB = 20.0
        // Solved so the TRUE azimuth difference is exactly 0: if the
        // candidate's own [100] basis were replaced by the matrix's [001]
        // basis, az0cB would be wrong and this would stop landing at 0.
        let thetaCB = (thetaMB + az0mB - az0cB).truncatingRemainder(dividingBy: 360)
        XCTAssertTrue(PhaseVectorMatcher.orientationConsistent(
            candidate: PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(1, 0, 0),
                                                 inPlaneRotationRad: thetaCB * .pi / 180, vectors: []),
            candidateCrystal: al,
            matrix: PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1),
                                              inPlaneRotationRad: thetaMB * .pi / 180, vectors: []),
            matrixCrystal: al,
            relationships: [differentZoneRelationship], toleranceDeg: 10),
            "the exact azimuth match (solved from projectedAzimuth's own frames) was refused "
            + "-- mutation: the candidate zone's own detectorBasis replaced by the matrix's")
        XCTAssertFalse(PhaseVectorMatcher.orientationConsistent(
            candidate: PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(1, 0, 0),
                                                 inPlaneRotationRad: (thetaCB + 45) * .pi / 180, vectors: []),
            candidateCrystal: al,
            matrix: PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1),
                                              inPlaneRotationRad: thetaMB * .pi / 180, vectors: []),
            matrixCrystal: al,
            relationships: [differentZoneRelationship], toleranceDeg: 10),
            "45° off the exact match was allowed")

        // --- 4. `map` end to end: θ′ edge-on [100] as candidate on Al
        // [001] matrix, inPlaneStepDeg = 45, the relationship
        // (002)θ′ ∥ (200)Al. The candidate entry AT the OR angle must be
        // indexed; a neighbour 45° off must not -- and the same holds with
        // the matrix fitted away from 0°, because a grain's rotation is not
        // always 0 (Gate B 2026-09-15: a previous test fit the matrix at 0°
        // throughout and so never caught the matrix azimuth being ignored).
        // This is an INTEGRATION check that the pieces compose through
        // `map`; the mutations above are what part 3 independently catches.
        let thetaPrime = Crystal(a: 4.04, b: 4.04, c: 5.80, sites: [
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.000000]),
            AtomSite(z: 13, fractional: [0.500000, 0.500000, 0.500000]),
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.500000]),
            AtomSite(z: 13, fractional: [0.500000, 0.500000, 0.000000]),
            AtomSite(z: 29, fractional: [0.000000, 0.500000, 0.250000]),
            AtomSite(z: 29, fractional: [0.500000, 0.000000, 0.750000]),
        ])
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 0.8
        reference.inPlaneStepDeg = 45
        let relationship = OrientationRelationship(
            candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(2, 0, 0)))
        let matrixPhase = PhaseDefinition(id: "al", displayName: "Al", crystal: al,
                                          role: .matrix, zoneAxes: [SIMD3(0, 0, 1)])
        let candidatePhase = PhaseDefinition(
            id: "theta-edge", displayName: "θ′ edge-on", crystal: thetaPrime,
            role: .candidate, zoneAxes: [SIMD3(1, 0, 0)],
            orientationRelationships: [relationship])
        let library = try PhaseReferenceLibrary.build(
            phases: [matrixPhase, candidatePhase], settings: reference)

        var fixtureSettings = PhaseVectorSettings()
        fixtureSettings.directBeamRadiusInvAngstrom = 0
        fixtureSettings.orientationRelationshipToleranceDeg = 10
        let scale = 0.005

        func braggFor(entryIndex: Int, in aLibrary: PhaseReferenceLibrary) -> BraggVectors {
            let peaks: [BraggPeak] = aLibrary.entries[entryIndex].vectors.map {
                BraggPeak(x: Float($0.q.x / scale), y: Float($0.q.y / scale), intensity: 1)
            }
            return BraggVectors(scanWidth: 1, scanHeight: 1, peaks: [peaks])
        }

        func check(matrixDeg: Double) throws {
            let matrixIndex = try XCTUnwrap(library.matrixEntryIndices.first {
                abs(library.entries[$0].inPlaneRotationRad * 180 / .pi - matrixDeg) < 1e-6
            }, "no matrix entry at \(matrixDeg)° in the fixture")
            let matrixEntry = library.entries[matrixIndex]

            let passing = library.candidateEntryIndices.filter { index in
                PhaseVectorMatcher.orientationConsistent(
                    candidate: library.entries[index], candidateCrystal: thetaPrime,
                    matrix: matrixEntry, matrixCrystal: al,
                    relationships: [relationship], toleranceDeg: 10)
            }
            let hit = try XCTUnwrap(passing.first,
                "no candidate rotation of the 45° sweep satisfies the OR at matrix \(matrixDeg)°")
            let hitDeg = library.entries[hit].inPlaneRotationRad * 180 / .pi
            let miss = try XCTUnwrap(library.candidateEntryIndices.first { index in
                guard !passing.contains(index) else { return false }
                let deg = library.entries[index].inPlaneRotationRad * 180 / .pi
                let delta = abs(deg - hitDeg).truncatingRemainder(dividingBy: 360)
                let wrapped = min(delta, 360 - delta)
                return wrapped > 44 && wrapped < 46
            }, "no 45°-off, non-passing neighbour of the OR entry at matrix \(matrixDeg)°")

            let hitMap = try XCTUnwrap(PhaseVectorMatcher.map(
                bragg: braggFor(entryIndex: hit, in: library), library: library, settings: fixtureSettings,
                originX: 0, originY: 0, invAngstromPerPixel: scale, matrixEntryIndex: matrixIndex))
            XCTAssertEqual(hitMap.results[0].verdict, .indexed,
                           "the candidate entry AT the OR angle (matrix \(matrixDeg)°) was not indexed")

            let missMap = try XCTUnwrap(PhaseVectorMatcher.map(
                bragg: braggFor(entryIndex: miss, in: library), library: library, settings: fixtureSettings,
                originX: 0, originY: 0, invAngstromPerPixel: scale, matrixEntryIndex: matrixIndex))
            XCTAssertNotEqual(missMap.results[0].verdict, .indexed,
                              "the candidate entry 45° off the OR angle (matrix \(matrixDeg)°) "
                              + "was indexed anyway")
        }
        try check(matrixDeg: 0)
        try check(matrixDeg: 45)

        // --- 5. An empty list is free -------------------------------------
        let freePhase = PhaseDefinition(
            id: "theta-edge", displayName: "θ′ edge-on", crystal: thetaPrime,
            role: .candidate, zoneAxes: [SIMD3(1, 0, 0)], orientationRelationships: [])
        let freeLibrary = try PhaseReferenceLibrary.build(
            phases: [matrixPhase, freePhase], settings: reference)
        let freeMatrixIndex = try XCTUnwrap(freeLibrary.matrixEntryIndices.first {
            freeLibrary.entries[$0].inPlaneRotationRad.magnitude < 1e-9
        })
        // Any grid rotation will do -- 45°, which the constrained sweep
        // above found to be off the OR angle at matrix 0°.
        let freeCandidateIndex = try XCTUnwrap(freeLibrary.candidateEntryIndices.first {
            abs(freeLibrary.entries[$0].inPlaneRotationRad * 180 / .pi - 45) < 1e-6
        })
        let freeMap = try XCTUnwrap(PhaseVectorMatcher.map(
            bragg: braggFor(entryIndex: freeCandidateIndex, in: freeLibrary), library: freeLibrary,
            settings: fixtureSettings, originX: 0, originY: 0, invAngstromPerPixel: scale,
            matrixEntryIndex: freeMatrixIndex))
        XCTAssertEqual(freeMap.results[0].verdict, .indexed,
                       "an empty orientation-relationship list should not constrain the map")

        // --- 6. A pair whose vector is not in the entry's zone does not
        // constrain it: (200)θ′ lies exactly along the [100] zone axis, so
        // it can never be projected, and the phase must stay free rather
        // than refusing every entry.
        let outOfZoneRelationship = OrientationRelationship(
            candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(2, 0, 0)))
        let outOfZonePhase = PhaseDefinition(
            id: "theta-edge", displayName: "θ′ edge-on", crystal: thetaPrime,
            role: .candidate, zoneAxes: [SIMD3(1, 0, 0)],
            orientationRelationships: [outOfZoneRelationship])
        let outOfZoneLibrary = try PhaseReferenceLibrary.build(
            phases: [matrixPhase, outOfZonePhase], settings: reference)
        let outOfZoneMatrixIndex = try XCTUnwrap(outOfZoneLibrary.matrixEntryIndices.first {
            outOfZoneLibrary.entries[$0].inPlaneRotationRad.magnitude < 1e-9
        })
        let outOfZoneCandidateIndex = try XCTUnwrap(outOfZoneLibrary.candidateEntryIndices.first {
            abs(outOfZoneLibrary.entries[$0].inPlaneRotationRad * 180 / .pi - 45) < 1e-6
        })
        let outOfZoneMap = try XCTUnwrap(PhaseVectorMatcher.map(
            bragg: braggFor(entryIndex: outOfZoneCandidateIndex, in: outOfZoneLibrary), library: outOfZoneLibrary,
            settings: fixtureSettings, originX: 0, originY: 0, invAngstromPerPixel: scale,
            matrixEntryIndex: outOfZoneMatrixIndex))
        XCTAssertEqual(outOfZoneMap.results[0].verdict, .indexed,
                       "a relationship pair not in either zone must not constrain the entry")

        // --- Gate B 2026-09-15: every plane above has the same azimuth in
        // either crystal (orthogonal cells, (h00)-type), so the two crystals
        // SWAPPED inside `orientationConsistent` was invisible. A hexagonal
        // candidate's (110) sits 60° from a in the basal plane, a cubic
        // matrix's 45°, so the derived offset is 15° one way and −15° the
        // other; the swap flips its sign. (The exact-tolerance boundary is
        // real-valued after atan2 and is not pinned: `<` vs `<=` differ only
        // at equality, which no fixture reaches exactly.)
        let hexagonal = Crystal(a: 4.94775, b: 4.94775, c: 14.14499,
                                alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
                                sites: [AtomSite(z: 13, fractional: SIMD3(0, 0, 0))])
        let cubic = Crystal.aluminum
        let basal = SIMD3<Int>(0, 0, 1)
        let up = SIMD3<Double>(0, 0, 1)           // both cells carry c along z
        let azHex = try XCTUnwrap(PhaseVectorMatcher.projectedAzimuth(
            of: LatticeVector.plane(SIMD3(1, 1, 0)).cartesian(in: hexagonal),
            zoneAxis: up, inPlaneRotationRad: 0))
        let azCubic = try XCTUnwrap(PhaseVectorMatcher.projectedAzimuth(
            of: LatticeVector.plane(SIMD3(1, 1, 0)).cartesian(in: cubic),
            zoneAxis: up, inPlaneRotationRad: 0))
        let derivedOffset = azCubic - azHex
        XCTAssertGreaterThan(abs(derivedOffset) * 180 / .pi, 12,
                             "the two (110) azimuths must differ by more than the tolerance for this to bite")
        let oneOneZero = [OrientationRelationship(candidate: .plane(SIMD3(1, 1, 0)),
                                                  matrix: .plane(SIMD3(1, 1, 0)))]
        func hexCandidate(at rad: Double) -> PhaseOrientationReference {
            PhaseOrientationReference(phaseIndex: 1, zoneAxis: basal, inPlaneRotationRad: rad, vectors: [])
        }
        let cubicMatrix = PhaseOrientationReference(phaseIndex: 0, zoneAxis: basal,
                                                    inPlaneRotationRad: 0, vectors: [])
        XCTAssertTrue(PhaseVectorMatcher.orientationConsistent(
            candidate: hexCandidate(at: derivedOffset), candidateCrystal: hexagonal,
            matrix: cubicMatrix, matrixCrystal: cubic, relationships: oneOneZero, toleranceDeg: 10),
            "the offset derived from the two crystals was not accepted")
        XCTAssertFalse(PhaseVectorMatcher.orientationConsistent(
            candidate: hexCandidate(at: -derivedOffset), candidateCrystal: hexagonal,
            matrix: cubicMatrix, matrixCrystal: cubic, relationships: oneOneZero, toleranceDeg: 10),
            "the offset with its sign flipped was accepted -- mutation: the two crystals swapped")
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

    // MARK: - Item K: cross-phase-completeness-guard (off by default)

    /// `PhaseVectorMatcher.crossPhaseWinsOver` in isolation -- the exact
    /// scenario `docs/open-items.md` measured (Gate B, 2026-09-15): a
    /// 2-vector match at 0.004 Å⁻¹ against a 10-vector match of another
    /// phase at 0.012 Å⁻¹. Shipped (mean distance alone) picks the sparse
    /// match; the completeness-aware candidate picks the dense one.
    ///
    /// Mutation this catches: the `completenessAware` guard deleted (the
    /// candidate rule would then always apply, changing shipped behavior),
    /// or `matched != matched` compared with `<` instead of `>` (the dense
    /// match would lose to the sparse one even with the guard on).
    func testCrossPhaseWinsOverPicksTheSparseMatchByDefaultAndTheDenseMatchWithTheGuard() {
        let sparsePrecise = (matched: 2, score: 0.004)
        let denseImprecise = (matched: 10, score: 0.012)

        XCTAssertTrue(
            PhaseVectorMatcher.crossPhaseWinsOver(sparsePrecise, denseImprecise, completenessAware: false),
            "shipped default (mean distance alone): the sparse, precise match must still win")
        XCTAssertFalse(
            PhaseVectorMatcher.crossPhaseWinsOver(denseImprecise, sparsePrecise, completenessAware: false),
            "the ordering must be antisymmetric: the dense match cannot ALSO outrank the sparse one")

        XCTAssertTrue(
            PhaseVectorMatcher.crossPhaseWinsOver(denseImprecise, sparsePrecise, completenessAware: true),
            "completeness-aware (off by default): the dense match must win when the flag is on")
        XCTAssertFalse(
            PhaseVectorMatcher.crossPhaseWinsOver(sparsePrecise, denseImprecise, completenessAware: true),
            "and the sparse match must no longer outrank it")
    }

    /// Equal matched counts always fall back to mean distance, with the
    /// guard on or off -- the tiebreak, not a separate rule. Mutation: the
    /// tiebreak branch skipped when `completenessAware` is true (an equal
    /// matched count would then order arbitrarily by dictionary iteration).
    func testCrossPhaseWinsOverTiesOnMatchedCountFallToMeanDistanceEitherWay() {
        let lowerDistance = (matched: 5, score: 0.006)
        let higherDistance = (matched: 5, score: 0.009)
        for completenessAware in [false, true] {
            XCTAssertTrue(
                PhaseVectorMatcher.crossPhaseWinsOver(
                    lowerDistance, higherDistance, completenessAware: completenessAware),
                "completenessAware=\(completenessAware): equal matched counts must still prefer the closer mean")
        }
    }

    /// `completenessAwareCrossPhaseRanking` ships off -- the item's own
    /// requirement ("moves a per-position verdict... measure and propose,
    /// never merge"). If this ever reads true, `classify` is silently using
    /// the unmeasured candidate ranking on every real dataset.
    func testCompletenessAwareCrossPhaseRankingShipsOff() {
        XCTAssertFalse(PhaseVectorSettings().completenessAwareCrossPhaseRanking)
    }

    // MARK: - `.knownVariants` (Thronsen et al.'s own rule, session S1)

    /// A library built directly from hand-placed reference vectors, bypassing
    /// `PhaseReferenceLibrary.build`'s crystallography so every distance in a
    /// `.knownVariants` test below is exact rather than derived from a
    /// projected cell. Each of `candidateEntries` becomes one
    /// `PhaseOrientationReference` at its own phase index; phase 0 (index
    /// `matrixPhaseIndex`) is reserved for the matrix and carries no entry
    /// unless the test builds one itself and splices it in.
    private func knownVariantsLibrary(
        candidateEntries: [(phaseIndex: Int, vectors: [ReferenceVector])],
        matrixPhaseIndex: Int = 0
    ) -> PhaseReferenceLibrary {
        var phases: [PhaseDefinition] = [
            PhaseDefinition(id: "matrix", displayName: "Matrix", crystal: .aluminum,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
        ]
        var entries: [PhaseOrientationReference] = []
        for (offset, candidate) in candidateEntries.enumerated() {
            phases.append(PhaseDefinition(id: "c\(offset)", displayName: "C\(offset)",
                                          crystal: .aluminum, role: .candidate,
                                          zoneAxes: [SIMD3(0, 0, 1)]))
            entries.append(PhaseOrientationReference(
                phaseIndex: candidate.phaseIndex, zoneAxis: SIMD3(0, 0, 1),
                inPlaneRotationRad: 0, vectors: candidate.vectors))
        }
        return PhaseReferenceLibrary(phases: phases, settings: PhaseReferenceSettings(),
                                     entries: entries, matrixPhaseIndex: matrixPhaseIndex)
    }

    /// (1) A planted candidate pattern -- exactly a library entry's own
    /// vectors -- is labelled that phase, `.indexed`, at zero residual.
    /// Mutation: `classifyKnownVariants` never reached from `classify`, or
    /// the winner's phase/entry index mixed up.
    func testKnownVariantsPlantedPatternIsLabelledThatPhase() {
        let refs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.30, 0), length: 0.30, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 1, l: 0, q: SIMD2(0, 0.40), length: 0.40, relativeIntensity: 1),
            ReferenceVector(h: 1, k: 1, l: 0, q: SIMD2(0.30, 0.40), length: 0.5, relativeIntensity: 1),
        ]
        let library = knownVariantsLibrary(candidateEntries: [(phaseIndex: 1, vectors: refs)])
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        let result = PhaseVectorMatcher.classify(
            vectors: refs.map(\.q), library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 8))
        XCTAssertEqual(result.verdict, .indexed)
        XCTAssertEqual(Int(result.phaseIndex), 1)
        XCTAssertEqual(Int(result.entryIndex), library.candidateEntryIndices[0])
        XCTAssertEqual(result.score, 0, accuracy: 1e-12)
        XCTAssertEqual(Int(result.matchedCount), 3)
    }

    /// (2) Survivor count alone decides the matrix branch: 0 and 1 survivors
    /// -> `.matrix`, 2 -> reaches scoring. Mutation: `<=` relaxed to `<`, or
    /// the matrix shortcut firing at 2 survivors too.
    func testKnownVariantsSurvivorCountDecidesMatrixVsScored() {
        let matrixEntry = PhaseOrientationReference(
            phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1), inPlaneRotationRad: 0,
            vectors: [ReferenceVector(h: 2, k: 0, l: 0, q: SIMD2(0.4, 0), length: 0.4, relativeIntensity: 1)])
        let candidateRefs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(1.0, 0), length: 1.0, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 1, l: 0, q: SIMD2(1.2, 0), length: 1.2, relativeIntensity: 1),
        ]
        let library = knownVariantsLibrary(candidateEntries: [(phaseIndex: 1, vectors: candidateRefs)])
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        let scratch = PhaseVectorMatcher.Scratch(capacity: 8)

        // 0 survivors: the only input vector is the matrix's own.
        let zero = PhaseVectorMatcher.classify(
            vectors: [SIMD2(0.4, 0)], library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        XCTAssertEqual(zero.verdict, .matrix)
        XCTAssertEqual(Int(zero.phaseIndex), library.matrixPhaseIndex)
        XCTAssertEqual(Int(zero.survivingCount), 0)
        XCTAssertEqual(Int(zero.removedCount), 1)

        // 1 survivor: one matches the matrix and is removed, one does not.
        let one = PhaseVectorMatcher.classify(
            vectors: [SIMD2(0.4, 0), SIMD2(1.0, 0)], library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        XCTAssertEqual(one.verdict, .matrix)
        XCTAssertEqual(Int(one.survivingCount), 1)
        XCTAssertEqual(Int(one.removedCount), 1)

        // 2 survivors: neither matches the matrix -- must reach scoring,
        // not the by-exclusion shortcut.
        let two = PhaseVectorMatcher.classify(
            vectors: [SIMD2(1.0, 0), SIMD2(1.2, 0)], library: library, settings: settings,
            matrixEntry: matrixEntry, candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        XCTAssertEqual(two.verdict, .indexed, "2 survivors must reach scoring, not the matrix shortcut")
        XCTAssertEqual(Int(two.phaseIndex), 1)
        XCTAssertEqual(two.score, 0, accuracy: 1e-12)
    }

    /// (3) The unique-hit denominator: two survivors that both land nearest
    /// the SAME reference spot must score WORSE than two survivors landing
    /// nearest two DISTINCT spots at the same two distances -- cell 16's
    /// `np.unique(ref_tmp[n], axis=0).shape[0]` denominator.
    /// Break-first M1: divide by `surviving.count` instead of the unique-hit
    /// count -- both cases then have denominator 2 and score identically,
    /// so `XCTAssertGreaterThan` below must go red.
    func testKnownVariantsUniqueHitDenominatorPenalisesRepeatedHits() {
        let refs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.30, 0), length: 0.30, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 1, l: 0, q: SIMD2(0.60, 0), length: 0.60, relativeIntensity: 1),
        ]
        let library = knownVariantsLibrary(candidateEntries: [(phaseIndex: 1, vectors: refs)])
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        let scratch = PhaseVectorMatcher.Scratch(capacity: 8)

        // Both survivors nearest the SAME reference (0.30): distances 0.01
        // and 0.01, unique hits 1 -> score 0.02 / 1 = 0.02.
        let sameSpot = PhaseVectorMatcher.classify(
            vectors: [SIMD2(0.29, 0), SIMD2(0.31, 0)], library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        // Survivors nearest two DIFFERENT references at the same two
        // distances: unique hits 2 -> score 0.02 / 2 = 0.01.
        let distinctSpots = PhaseVectorMatcher.classify(
            vectors: [SIMD2(0.29, 0), SIMD2(0.61, 0)], library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)

        XCTAssertEqual(sameSpot.verdict, .indexed)
        XCTAssertEqual(distinctSpots.verdict, .indexed)
        XCTAssertEqual(sameSpot.score, 0.02, accuracy: 1e-6)
        XCTAssertEqual(distinctSpots.score, 0.01, accuracy: 1e-6)
        XCTAssertGreaterThan(sameSpot.score, distinctSpots.score,
                             "two hits on one reference must score worse than two hits on distinct ones")
    }

    /// (4) The residual cutoff, right at the edge: mean residual just below
    /// `residualCutoffInvAngstrom` is `.indexed`, just above is
    /// `.notIndexed`. Break-first M2: flip the comparison -- both cases
    /// swap verdicts, so this must go red.
    func testKnownVariantsCutoffBoundary() {
        let cutoff = PhaseVectorSettings().residualCutoffInvAngstrom
        let refs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.30, 0), length: 0.30, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 1, l: 0, q: SIMD2(0, 0.60), length: 0.60, relativeIntensity: 1),
        ]
        let library = knownVariantsLibrary(candidateEntries: [(phaseIndex: 1, vectors: refs)])
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        let scratch = PhaseVectorMatcher.Scratch(capacity: 8)

        func result(offset: Double) -> PhaseVectorResult {
            PhaseVectorMatcher.classify(
                vectors: [SIMD2(0.30 + offset, 0), SIMD2(0, 0.60 + offset)],
                library: library, settings: settings, matrixEntry: nil,
                candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        }

        let justBelow = result(offset: cutoff - 0.001)
        let justAbove = result(offset: cutoff + 0.001)
        XCTAssertEqual(justBelow.verdict, .indexed,
                       "mean residual \(justBelow.score) is under the cutoff \(cutoff)")
        XCTAssertEqual(justAbove.verdict, .notIndexed,
                       "mean residual \(justAbove.score) is over the cutoff \(cutoff)")
        // Still filled on a refusal, so the probe can print the distribution
        // of would-be winners among the not-indexed positions.
        XCTAssertEqual(Int(justAbove.phaseIndex), 1)
        XCTAssertTrue(justAbove.score.isFinite)
    }

    /// (5) Partial explanation loses: an entry explaining 2 of 12 survivors
    /// at 0.003 Å⁻¹ and leaving the other 10 far away must lose to an entry
    /// explaining all 12 at 0.008 Å⁻¹ -- the measured θ′ edge-on -> T1
    /// mechanism (`docs/archive/v3/phase-map-residual-detail-2026-09-21.md`:
    /// a Friedel-pair floor lets a 2-of-12 partial match win under `.search`;
    /// `.knownVariants` has no such floor, and summing every survivor is what
    /// makes leaving ten unexplained costly instead of merely absent from the
    /// count). Break-first M3: sum only the matched-within-radius distances
    /// -- the ten far survivors drop out of entry X's sum, its score
    /// collapses to near 0.003, and it wins instead, so this must go red.
    func testKnownVariantsPartialExplanationLoses() {
        let survivors = (0..<12).map { SIMD2<Double>(Double($0) * 1.0, 0) }
        // Entry X: two reference vectors. Survivors 0 and 1 land 0.003 from
        // one each; survivors 2...11 are all nearest the SECOND of the two,
        // "far away" as the residual record describes.
        let entryXRefs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.003, 0), length: 0.003, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 1, l: 0, q: SIMD2(1.003, 0), length: 1.003, relativeIntensity: 1),
        ]
        // Entry Y: twelve reference vectors, each 0.008 from its own survivor.
        let entryYRefs = (0..<12).map { i in
            ReferenceVector(h: i, k: 0, l: 0, q: SIMD2(Double(i) * 1.0 + 0.008, 0),
                            length: Double(i) * 1.0 + 0.008, relativeIntensity: 1)
        }
        let library = knownVariantsLibrary(candidateEntries: [
            (phaseIndex: 1, vectors: entryXRefs),
            (phaseIndex: 2, vectors: entryYRefs),
        ])
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        let result = PhaseVectorMatcher.classify(
            vectors: survivors, library: library, settings: settings, matrixEntry: nil,
            candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 16))
        XCTAssertEqual(result.verdict, .indexed)
        XCTAssertEqual(Int(result.phaseIndex), 2,
                       "the entry explaining all 12 survivors must win over one explaining only 2 of them")
        XCTAssertEqual(result.score, 0.008, accuracy: 1e-6)
        XCTAssertEqual(Int(result.runnerUpPhaseIndex), 1)
    }

    /// (6) A matrix-phase entry is never the winner under this rule, even
    /// when spliced into the candidate list with a perfect (zero-distance)
    /// score -- the matrix is decided only by step b, never scored.
    /// Mutation: the `entry.phaseIndex != library.matrixPhaseIndex` guard
    /// removed from the scoring loop.
    func testKnownVariantsNeverPicksTheMatrixPhaseEvenWhenItWouldScoreBest() {
        let matrixRefs = [
            ReferenceVector(h: 2, k: 0, l: 0, q: SIMD2(0.50, 0), length: 0.50, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 2, l: 0, q: SIMD2(0, 0.70), length: 0.70, relativeIntensity: 1),
        ]
        let matrixEntry = PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1),
                                                    inPlaneRotationRad: 0, vectors: matrixRefs)
        // A real candidate, 0.01 Å⁻¹ off each spot -- the only legitimate winner.
        let candidateRefs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.51, 0), length: 0.51, relativeIntensity: 1),
            ReferenceVector(h: 0, k: 1, l: 0, q: SIMD2(0, 0.71), length: 0.71, relativeIntensity: 1),
        ]
        let base = knownVariantsLibrary(candidateEntries: [(phaseIndex: 1, vectors: candidateRefs)])
        // Splice the matrix's own entry into the SAME entries array, so the
        // guard under test is `classify`'s own, not merely a caller that
        // already knew to leave the matrix out.
        let library = PhaseReferenceLibrary(phases: base.phases, settings: base.settings,
                                            entries: [matrixEntry] + base.entries,
                                            matrixPhaseIndex: base.matrixPhaseIndex)
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        // Deliberately pass EVERY entry as a candidate, the matrix's included.
        let result = PhaseVectorMatcher.classify(
            vectors: [SIMD2(0.50, 0), SIMD2(0, 0.70)], library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: Array(library.entries.indices),
            scratch: PhaseVectorMatcher.Scratch(capacity: 8))
        XCTAssertEqual(result.verdict, .indexed)
        XCTAssertEqual(Int(result.phaseIndex), 1,
                       "the matrix's own entry scored 0 and must still never win")
        XCTAssertEqual(result.score, 0.01, accuracy: 1e-6)
    }

    /// (7) `.search` is unchanged by `.knownVariants` existing: a hand-placed
    /// fixture's FULL `PhaseVectorResult` is pinned, and the default settings
    /// (`.search`) agree exactly with settings that name `.search` explicitly
    /// -- the dispatch adds a branch, it does not move which branch the
    /// default takes or any field `.search` computes. `PhaseVectorResult`'s
    /// synthesized `==` is not used directly: NaN != NaN would make a
    /// passing runner-up comparison look like a failure.
    func testKnownVariantsRuleDoesNotChangeSearchsOwnResult() {
        let refs = [
            ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.10, 0), length: 0.10, relativeIntensity: 1),
            ReferenceVector(h: 2, k: 0, l: 0, q: SIMD2(0.20, 0), length: 0.20, relativeIntensity: 1),
            ReferenceVector(h: 3, k: 0, l: 0, q: SIMD2(0.30, 0), length: 0.30, relativeIntensity: 1),
            ReferenceVector(h: 5, k: 0, l: 0, q: SIMD2(0.50, 0), length: 0.50, relativeIntensity: 1),
        ]
        let library = knownVariantsLibrary(candidateEntries: [(phaseIndex: 1, vectors: refs)])
        let vectors = [SIMD2(0.101, 0.0), SIMD2(0.199, 0.0), SIMD2(0.302, 0.0), SIMD2(0.505, 0.0)]
        var settings = PhaseVectorSettings()
        XCTAssertEqual(settings.classificationRule, .search, "the shipped default must stay .search")

        let result = PhaseVectorMatcher.classify(
            vectors: vectors, library: library, settings: settings, matrixEntry: nil,
            candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 8))
        XCTAssertEqual(result.verdict, .indexed)
        XCTAssertEqual(Int(result.phaseIndex), 1)
        XCTAssertEqual(Int(result.entryIndex), library.candidateEntryIndices[0])
        XCTAssertEqual(result.score, 0.00225, accuracy: 1e-6)
        XCTAssertEqual(Int(result.matchedCount), 4)
        XCTAssertEqual(Int(result.survivingCount), 4)
        XCTAssertEqual(Int(result.removedCount), 0)
        XCTAssertEqual(Int(result.runnerUpPhaseIndex), -1)
        XCTAssertTrue(result.runnerUpScore.isNaN)

        settings.classificationRule = .search
        let explicit = PhaseVectorMatcher.classify(
            vectors: vectors, library: library, settings: settings, matrixEntry: nil,
            candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 8))
        XCTAssertEqual(explicit.verdict, result.verdict)
        XCTAssertEqual(explicit.phaseIndex, result.phaseIndex)
        XCTAssertEqual(explicit.entryIndex, result.entryIndex)
        XCTAssertEqual(explicit.score, result.score)
        XCTAssertEqual(explicit.matchedCount, result.matchedCount)
        XCTAssertEqual(explicit.survivingCount, result.survivingCount)
        XCTAssertEqual(explicit.removedCount, result.removedCount)
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
        XCTAssertEqual(resolution.notIndexedAbovePixels, 0.328, accuracy: 0.001)
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
    /// pair radius rather than three quarters of it (half until 2026-09-15,
    /// when the half was measured to reject honest many-vector fits). The
    /// pair radius says what COULD be the same reflection; the verdict
    /// distance says what is close enough to call — equal values collapse
    /// the distinction and index everything the pair radius admits.
    func testScalingToTheDetectorKeepsTheShippedRatio() {
        let scale = 0.045741477608680726
        let scaled = PhaseVectorResolution(settings: PhaseVectorSettings(),
                                           invAngstromPerPixel: scale)
            .scaledToDetector(PhaseVectorSettings())
        XCTAssertEqual(scaled.pairRadiusInvAngstrom, scale, accuracy: 1e-12)
        XCTAssertEqual(scaled.matrixToleranceInvAngstrom, scale, accuracy: 1e-12)
        XCTAssertEqual(scaled.notIndexedAboveInvAngstrom, scale * 0.75, accuracy: 1e-12)
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

/// Asking the data which beam direction the specimen is on. This is the half
/// of the diagnosis that was missing: the app told the owner to check his
/// matrix zone axis and gave him no way to answer it.
final class ZoneAxisFitTests: XCTestCase {

    /// Planted truth: patterns built from aluminium's own ⟨110⟩ projection,
    /// at a sign-discriminating in-plane rotation. The fit must recover the
    /// FAMILY, and — because fcc is cubic — every sampled ⟨110⟩ equivalent
    /// must tie EXACTLY. The tie is the real assertion: it is what cubic
    /// symmetry requires, so a sweep that returns a winner without it is
    /// returning something rather than measuring something.
    ///
    /// Mutation: ranking by `meanDistance` alone instead of matched count
    /// first — the trap the source comment names, where one vector at
    /// 0.001 Å⁻¹ beats nine at 0.01.
    func testTheFitRecoversThePlantedFamilyAndTiesAcrossIt() throws {
        let al = Crystal.aluminum
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 1.2
        let planted = SIMD3(1, 1, 0)
        let rotation = 37.2 * Double.pi / 180

        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: al.reflections(kMax: reference.kMaxInvAngstrom), crystal: al,
            zoneAxis: planted, settings: reference)
        XCTAssertGreaterThan(base.count, 4)
        let turned = PhaseReferenceLibrary.rotate(base, by: rotation)

        let scale = 0.008
        let originX: Float = 128, originY: Float = 128
        let peaks: [[BraggPeak]] = (0..<64).map { _ in
            [BraggPeak(x: originX, y: originY, intensity: 10)]
                + turned.map { v in
                    BraggPeak(x: originX + Float(v.q.x / scale),
                              y: originY + Float(v.q.y / scale), intensity: 1)
                }
        }
        let bragg = BraggVectors(scanWidth: 8, scanHeight: 8, peaks: peaks)

        let fits = PhaseVectorMatcher.fitZoneAxis(
            bragg: bragg, crystal: al, referenceSettings: reference,
            settings: PhaseVectorSettings(), originX: originX, originY: originY,
            invAngstromPerPixel: scale, inPlaneStepDeg: 2)
        let winner = try XCTUnwrap(fits.first)

        func isOneOneZeroFamily(_ a: SIMD3<Int>) -> Bool {
            let m = [abs(a.x), abs(a.y), abs(a.z)].sorted()
            return m == [0, 1, 1]
        }
        XCTAssertTrue(isOneOneZeroFamily(winner.zoneAxis),
                      "fitted [\(winner.zoneAxis.x) \(winner.zoneAxis.y) \(winner.zoneAxis.z)], "
                      + "not a ⟨110⟩")
        XCTAssertEqual(winner.explainedFraction, 1.0, accuracy: 0.001)

        // THE TIE. Every ⟨110⟩ in the candidate list must score identically.
        let family = fits.filter { isOneOneZeroFamily($0.zoneAxis) }
        XCTAssertGreaterThanOrEqual(family.count, 3, "too few ⟨110⟩ axes to test the tie")
        for fit in family {
            XCTAssertEqual(fit.matchedVectors, winner.matchedVectors,
                           "[\(fit.zoneAxis.x) \(fit.zoneAxis.y) \(fit.zoneAxis.z)] "
                           + "broke the cubic tie")
        }
        // And a non-equivalent axis must NOT reach the same score, or the
        // sweep is not discriminating at all.
        let other = fits.first { !isOneOneZeroFamily($0.zoneAxis) }
        XCTAssertLessThan(try XCTUnwrap(other).matchedVectors, winner.matchedVectors)
    }

    /// The chance floor (2026-09-14). A percentage alone cannot be read: at a
    /// tight tolerance every axis explains a few percent of ANY vectors, and
    /// the panel presented a ⟨112⟩ family at 8 % the way it presents a real
    /// fit. `chanceMatchedVectors` is what separates them, and the two halves
    /// of this test are the two cases the owner cannot tell apart on screen.
    ///
    /// Mutations this names: computing the chance expectation at a fixed
    /// radius instead of each pattern's own reach; dropping the
    /// `chanceMatchMultiple` factor from `isAboveChance`; or returning zero
    /// chance, which would mark everything informative.
    func testAFitOnRandomVectorsIsAtChanceAndAPlantedOneIsNot() throws {
        let al = Crystal.aluminum
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 1.2
        let settings = PhaseVectorSettings()
        let scale = 0.008
        let originX: Float = 128, originY: Float = 128

        // Half one: aluminium's own ⟨110⟩ projection, as the recovery test
        // plants it. This must read as information.
        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: al.reflections(kMax: reference.kMaxInvAngstrom), crystal: al,
            zoneAxis: SIMD3(1, 1, 0), settings: reference)
        let turned = PhaseReferenceLibrary.rotate(base, by: 37.2 * .pi / 180)
        let plantedPeaks: [[BraggPeak]] = (0..<64).map { _ in
            [BraggPeak(x: originX, y: originY, intensity: 10)]
                + turned.map { v in
                    BraggPeak(x: originX + Float(v.q.x / scale),
                              y: originY + Float(v.q.y / scale), intensity: 1)
                }
        }
        let plantedFits = PhaseVectorMatcher.fitZoneAxis(
            bragg: BraggVectors(scanWidth: 8, scanHeight: 8, peaks: plantedPeaks),
            crystal: al, referenceSettings: reference, settings: settings,
            originX: originX, originY: originY, invAngstromPerPixel: scale,
            inPlaneStepDeg: 2)
        let plantedWinner = try XCTUnwrap(plantedFits.first)
        XCTAssertTrue(plantedWinner.isAboveChance(multiple: settings.chanceMatchMultiple),
                      "a perfectly planted ⟨110⟩ was marked as chance: "
                      + "\(plantedWinner.matchedVectors) matched against "
                      + "\(plantedWinner.chanceMatchedVectors) expected")
        XCTAssertGreaterThan(plantedWinner.chanceMatchedVectors, 0,
                             "the chance expectation is identically zero, so nothing "
                             + "could ever be marked at chance")

        // Half two: the same number of vectors pointing nowhere in
        // particular, drawn uniformly over the disc the data reaches — which
        // is the model `chanceMatchFraction` states for itself. Whatever axis
        // wins on these must NOT read as information.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {                     // deterministic; no shared RNG state
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let reach = turned.map { simd_length($0.q) }.max() ?? 0.8
        func sweep(_ peaks: [[BraggPeak]]) -> PhaseVectorMatcher.ZoneAxisFit? {
            PhaseVectorMatcher.fitZoneAxis(
                bragg: BraggVectors(scanWidth: 8, scanHeight: 8, peaks: peaks),
                crystal: al, referenceSettings: reference, settings: settings,
                originX: originX, originY: originY, invAngstromPerPixel: scale,
                inPlaneStepDeg: 2).first
        }
        let uniformPeaks: [[BraggPeak]] = (0..<64).map { _ in
            [BraggPeak(x: originX, y: originY, intensity: 10)]
                + turned.map { _ in
                    // sqrt keeps the draw uniform per unit AREA, not per radius.
                    let r = reach * next().squareRoot(), a = next() * 2 * .pi
                    return BraggPeak(x: originX + Float(r * cos(a) / scale),
                                     y: originY + Float(r * sin(a) / scale), intensity: 1)
                }
        }
        let uniformWinner = try XCTUnwrap(sweep(uniformPeaks))
        // The model's calibration, asserted rather than printed, because
        // `docs/open-items.md` quotes it: 14 matched of 1 379 against 11.4
        // expected. A band, not the number, so a change to the sampling is a
        // failure and a change to the last digit is not.
        XCTAssertEqual(Double(uniformWinner.matchedVectors),
                       uniformWinner.chanceMatchedVectors, accuracy: 6.0,
                       "the uniform-disc model no longer predicts what uniform vectors do: "
                       + "\(uniformWinner.matchedVectors) matched of "
                       + "\(uniformWinner.totalVectors), \(uniformWinner.chanceMatchedVectors) expected")
        XCTAssertFalse(uniformWinner.isAboveChance(multiple: settings.chanceMatchMultiple),
                       "vectors pointing nowhere produced a fit presented as information: "
                       + "\(uniformWinner.matchedVectors) matched, "
                       + "\(uniformWinner.chanceMatchedVectors) expected by chance")

        // MEASURED LIMIT, printed not asserted: vectors confined to the rings
        // the references occupy beat the disc model, because the model spreads
        // its area over the whole disc while the peaks sit where the
        // references are. `chanceMatchFraction`'s own comment says this
        // understatement is known; these two lines are what it costs here.
        let ringPeaks: [[BraggPeak]] = (0..<64).map { _ in
            [BraggPeak(x: originX, y: originY, intensity: 10)]
                + turned.map { v in
                    let r = simd_length(v.q), a = next() * 2 * .pi
                    return BraggPeak(x: originX + Float(r * cos(a) / scale),
                                     y: originY + Float(r * sin(a) / scale), intensity: 1)
                }
        }
        let ringWinner = try XCTUnwrap(sweep(ringPeaks))
        // AND THE LIMIT, asserted too: 63 matched against 10.7 expected. The
        // model spreads its area over the whole disc while these vectors sit
        // where the references are, so it understates chance about sixfold —
        // and the guard therefore reads them as information. This assertion
        // exists to fail if that ever stops being true, in either direction.
        XCTAssertGreaterThan(Double(ringWinner.matchedVectors),
                             4 * ringWinner.chanceMatchedVectors,
                             "the disc model no longer understates ring-concentrated vectors: "
                             + "\(ringWinner.matchedVectors) matched, "
                             + "\(ringWinner.chanceMatchedVectors) expected")
        XCTAssertTrue(ringWinner.isAboveChance(multiple: settings.chanceMatchMultiple),
                      "ring-concentrated vectors are no longer read as information; "
                      + "open-items.md's measured limit needs rewriting")
    }

    /// THE OWNER'S CASE, pinned (Gate D, 2026-09-15 night): a wrong axis on a
    /// real crystal explains a large share of the vectors through SHARED
    /// reflections, clears the disc-chance rule by a wide margin, and used to
    /// be presented exactly like the true one. A ⟨110⟩ plant degraded the way
    /// data is (30 % of spots missing, 0.004 Å⁻¹ jitter, three spurious peaks
    /// per pattern): the ⟨112⟩ family explains ~16 % — five times the
    /// chance rule allows, so `isAboveChance` is TRUE, which is the defect
    /// and is asserted as the control — while it sits at ~1.2× the sweep's
    /// median, under the 2× bar. The true family sits at ~6×. Mutations this
    /// names: `informativeSweepRatio` lowered to 1 (every wrong axis passes),
    /// the median computed over the top few instead of the sweep, or
    /// `isInformative` dropping either rule.
    func testAWrongAxisThatSharesReflectionsIsMarkedBelowTheSweep() throws {
        let al = Crystal.aluminum
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 1.2
        let settings = PhaseVectorSettings()
        let scale = 0.008
        let originX: Float = 128, originY: Float = 128
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        func gauss() -> Double {
            sqrt(-2 * log(max(1e-12, next()))) * cos(2 * .pi * next())
        }
        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: al.reflections(kMax: reference.kMaxInvAngstrom), crystal: al,
            zoneAxis: SIMD3(1, 1, 0), settings: reference)
        let turned = PhaseReferenceLibrary.rotate(base, by: 37.2 * .pi / 180)
        let reach = turned.map { simd_length($0.q) }.max() ?? 0.8
        let peaks: [[BraggPeak]] = (0..<64).map { _ in
            var out = [BraggPeak(x: originX, y: originY, intensity: 10)]
            for v in turned where next() >= 0.3 {
                out.append(BraggPeak(x: originX + Float((v.q.x + gauss() * 0.004) / scale),
                                     y: originY + Float((v.q.y + gauss() * 0.004) / scale),
                                     intensity: 1))
            }
            for _ in 0..<3 {
                let r = reach * next().squareRoot(), a = next() * 2 * .pi
                out.append(BraggPeak(x: originX + Float(r * cos(a) / scale),
                                     y: originY + Float(r * sin(a) / scale), intensity: 1))
            }
            return out
        }
        let fits = PhaseVectorMatcher.fitZoneAxis(
            bragg: BraggVectors(scanWidth: 8, scanHeight: 8, peaks: peaks),
            crystal: al, referenceSettings: reference, settings: settings,
            originX: originX, originY: originY, invAngstromPerPixel: scale,
            inPlaneStepDeg: 2)
        let winner = try XCTUnwrap(fits.first)
        XCTAssertEqual(Set([abs(winner.zoneAxis.x), abs(winner.zoneAxis.y), abs(winner.zoneAxis.z)]),
                       Set([0, 1]), "the ⟨110⟩ plant was not won by a ⟨110⟩: \(winner.zoneAxis)")
        XCTAssertTrue(winner.isInformative(multiple: settings.chanceMatchMultiple),
                      "the true axis was marked: \(winner.explainedFraction) against a sweep "
                      + "median of \(winner.sweepMedianFraction)")
        XCTAssertGreaterThan(winner.sweepRatio, 4, "the true family no longer stands out")

        let wrong112 = try XCTUnwrap(fits.first {
            Set([abs($0.zoneAxis.x), abs($0.zoneAxis.y), abs($0.zoneAxis.z)]) == Set([1, 1, 2])
        })
        // The control: the disc rule alone reads it as information.
        XCTAssertTrue(wrong112.isAboveChance(multiple: settings.chanceMatchMultiple),
                      "the defect this test pins no longer reproduces: ⟨112⟩ at "
                      + "\(wrong112.explainedFraction) is under 5× disc chance")
        XCTAssertGreaterThan(wrong112.explainedFraction, 0.05,
                             "⟨112⟩ explains too little for this to be the owner's case")
        // The fix: against the sweep it is a wrong axis.
        XCTAssertFalse(wrong112.isAboveSweep,
                       "⟨112⟩ at \(wrong112.explainedFraction) is \(wrong112.sweepRatio)× the "
                       + "sweep median of \(wrong112.sweepMedianFraction) and was not marked")
        XCTAssertFalse(wrong112.isInformative(multiple: settings.chanceMatchMultiple))
        // And every axis under 30 % is a wrong one here; none may stand out.
        for fit in fits where fit.explainedFraction < 0.3 {
            XCTAssertFalse(fit.isAboveSweep, "\(fit.zoneAxis) at \(fit.explainedFraction) "
                           + "stands out at \(fit.sweepRatio)× the median")
        }
    }

    /// Gate B (2026-09-15 night): with two candidate axes the "median" was
    /// the top axis's own fraction, so its ratio saturated at exactly 1 and
    /// a perfect fit could never clear the bar. Below five axes the sweep
    /// rule is inert. Mutation this names: the `>= 5` guard dropped.
    func testATinySweepHasNoMedianNull() throws {
        let al = Crystal.aluminum
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 1.2
        let scale = 0.008
        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: al.reflections(kMax: reference.kMaxInvAngstrom), crystal: al,
            zoneAxis: SIMD3(1, 1, 0), settings: reference)
        let peaks: [[BraggPeak]] = (0..<16).map { _ in
            [BraggPeak(x: 128, y: 128, intensity: 10)] + base.map {
                BraggPeak(x: 128 + Float($0.q.x / scale), y: 128 + Float($0.q.y / scale), intensity: 1)
            }
        }
        let fits = PhaseVectorMatcher.fitZoneAxis(
            bragg: BraggVectors(scanWidth: 4, scanHeight: 4, peaks: peaks),
            crystal: al, referenceSettings: reference, settings: PhaseVectorSettings(),
            originX: 128, originY: 128, invAngstromPerPixel: scale,
            candidateAxes: [SIMD3(1, 1, 0), SIMD3(0, 0, 1)], inPlaneStepDeg: 2)
        let winner = try XCTUnwrap(fits.first)
        XCTAssertEqual(winner.sweepMedianFraction, 0, "two axes are not a null")
        XCTAssertTrue(winner.isAboveSweep, "a perfect ⟨110⟩ fit failed a sweep of two: ratio \(winner.sweepRatio)")
    }

    /// Mutation: the `pairs > 0` guard dropped, or an axis with no reachable
    /// reflection admitted — it would divide by zero or report a perfect fit
    /// for a direction that presents nothing.
    func testAnAxisThatPresentsNothingIsNotRanked() {
        let al = Crystal.aluminum
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 1.2
        let bragg = BraggVectors(scanWidth: 2, scanHeight: 2,
                                 peaks: Array(repeating: [], count: 4))
        XCTAssertTrue(PhaseVectorMatcher.fitZoneAxis(
            bragg: bragg, crystal: al, referenceSettings: reference,
            settings: PhaseVectorSettings(), originX: 0, originY: 0,
            invAngstromPerPixel: 0.008).isEmpty,
            "a scan with no peaks produced a zone-axis ranking")
        for fit in PhaseVectorMatcher.fitZoneAxis(
            bragg: BraggVectors(scanWidth: 1, scanHeight: 1,
                                peaks: [[BraggPeak(x: 90, y: 0, intensity: 1)]]),
            crystal: al, referenceSettings: reference, settings: PhaseVectorSettings(),
            originX: 0, originY: 0, invAngstromPerPixel: 0.008) {
            XCTAssertTrue(fit.meanDistance.isFinite, "an unranked axis leaked a NaN")
            XCTAssertGreaterThan(fit.totalVectors, 0)
        }
    }
}

/// The matrix's last word before a position may be called a precipitate
/// (`PhaseVectorMatcher.challengeByMatrix`, 2026-09-14). Gate D record:
/// `docs/open-items.md`, "A second matrix grain is labelled as a candidate
/// phase". The defect these pin cost 2 250 positions of pure aluminium a
/// 100 % confident β″ label on the demo cube.
final class MatrixChallengeTests: XCTestCase {

    /// Mutation this names: deleting the step-5 block in `classify`, or
    /// passing an empty `matrixChallenge` from `map`. Both restore the defect
    /// exactly — the second assertion here is the defect, kept as the control.
    ///
    /// The planted rotation is 37.3°, deliberately NOT a multiple of the 2°
    /// library step. MEASURED, not assumed: snapping the derived rotation to
    /// that grid does NOT turn this test red — 0.7° at |q| ≤ 0.8 Å⁻¹ is
    /// 0.0098 Å⁻¹, still inside the 0.02 pair radius, so the verdict survives
    /// at a worse distance. The grid mutation is caught by
    /// `testAMatrixOrientationExplainingLessDoesNotWin`, which compares the
    /// distance rather than the verdict.
    func testAMatrixGrainOnAnotherZoneAxisIsNotLabelledAsACandidate() throws {
        let library = try challengeLibrary()
        let planted = matrixVectorsOnAnotherAxis(library, degrees: 37.3)
        XCTAssertGreaterThanOrEqual(planted.count, 4,
                                    "the fixture planted too few vectors to decide anything")
        let settings = PhaseVectorSettings()
        let bases = PhaseVectorMatcher.matrixChallengeBases(library: library)
        XCTAssertFalse(bases.isEmpty, "the challenge pool is empty; nothing was tested")

        // The control: without the challenge this IS the defect.
        let unchallenged = PhaseVectorMatcher.classify(
            vectors: planted, library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 256))
        XCTAssertEqual(unchallenged.verdict, .indexed,
                       "the fixture no longer reproduces the defect it was built for, "
                       + "so the challenged case below proves nothing")

        let challenged = PhaseVectorMatcher.classify(
            vectors: planted, library: library, settings: settings,
            matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
            scratch: PhaseVectorMatcher.Scratch(capacity: 256),
            matrixChallenge: bases)
        XCTAssertEqual(challenged.verdict, .matrix,
                       "aluminium on a second zone axis was labelled a candidate phase")
        XCTAssertEqual(Int(challenged.phaseIndex), library.matrixPhaseIndex)
    }

    /// Mutation this names: relaxing `candidate.matched > winner.matched` to
    /// `>=`. That single character is what makes a precipitate impossible to
    /// erase — a candidate explaining every surviving vector cannot be beaten
    /// on count — and Gate B measured what `>=` costs before it was tightened:
    /// **26.5 % of three-vector precipitates taken by the matrix** at
    /// 0.004 Å⁻¹ of jitter, a third of a detector pixel on the demo cube.
    ///
    /// THE JITTER IS THE POINT. The first version of this test planted a
    /// candidate entry's own vectors verbatim, so the winner's mean distance
    /// was exactly 0 and `candidate.score < winner.score` could never hold for
    /// any challenger — it passed under every loosening of the guard it
    /// claimed to hold. A real measurement is never exact.
    func testTheChallengeDoesNotTakeATruePrecipitate() throws {
        let library = try challengeLibrary()
        let candidate = library.entries[library.candidateEntryIndices[0]]
        let bases = PhaseVectorMatcher.matrixChallengeBases(library: library)
        let settings = PhaseVectorSettings()

        // Deterministic jitter, well inside the pair radius: a real peak is
        // measured, not looked up.
        var seed: UInt64 = 0xD1B54A32D192ED03
        func jitter() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) / Double(UInt64(1) << 53) - 0.5) * 0.008
        }
        // Sparse, because sparse is the case that was being stolen: the file
        // header names "a thin precipitate showing two spots", and
        // `minimumMatchedVectors` admits three.
        for count in [3, 4, 5, 6] {
            let planted = candidate.vectors.prefix(count).map {
                $0.q + SIMD2(jitter(), jitter())
            }
            let result = PhaseVectorMatcher.classify(
                vectors: Array(planted), library: library, settings: settings,
                matrixEntry: nil, candidateEntryIndices: library.candidateEntryIndices,
                scratch: PhaseVectorMatcher.Scratch(capacity: 256),
                matrixChallenge: bases)
            XCTAssertEqual(result.verdict, .indexed,
                           "a \(count)-vector precipitate was taken by the matrix")
            XCTAssertNotEqual(Int(result.phaseIndex), library.matrixPhaseIndex,
                              "a \(count)-vector precipitate was relabelled as the matrix")
        }
    }

    /// Mutation this names: dropping `candidate.matched >= winner.matched`, or
    /// turning `candidate.score < winner.score` into `<=`. The rule is that a
    /// challenger must explain AT LEAST AS MUCH of the pattern, not merely
    /// explain a corner of it more precisely.
    func testAMatrixOrientationExplainingLessDoesNotWin() throws {
        let library = try challengeLibrary()
        let planted = matrixVectorsOnAnotherAxis(library, degrees: 37.3)
        let bases = PhaseVectorMatcher.matrixChallengeBases(library: library)
        let settings = PhaseVectorSettings()
        let scratch = PhaseVectorMatcher.Scratch(capacity: 256)

        // ONE named orientation, not the whole pool: the pool holds six
        // ⟨011⟩ variants and 49 axes in all, and a boundary asserted against
        // all of them would be decided by whichever one happens to win.
        // Restricting it to the planted axis makes "the challenger's numbers"
        // exact.
        // The planted axis itself, up to sign — NOT the ⟨011⟩ family, which
        // has six members in `lowIndexZoneAxes` and would reintroduce the same
        // first-versus-best ambiguity.
        let oneBase = bases.filter {
            $0.zoneAxis == SIMD3(0, 1, 1) || $0.zoneAxis == SIMD3(0, -1, -1)
        }
        XCTAssertEqual(oneBase.count, 1, "expected exactly one [011] base in the pool")

        // What that orientation can actually do here, measured rather than
        // assumed, so the comparisons below sit exactly on its boundary.
        guard let best = PhaseVectorMatcher.challengeByMatrix(
            surviving: planted, bases: oneBase, settings: settings,
            accessibleRadius: 1.0, beating: (matched: 0, score: .infinity),
            scratch: scratch) else {
            return XCTFail("the matrix explains every planted vector exactly and still lost")
        }
        XCTAssertEqual(best.matched, planted.count,
                       "the planted grain was not fully explained by its own orientation")

        // ON the boundary: a winner the challenger merely TIES on count is not
        // beaten, because the rule is strictly more. This is the assertion that
        // makes a fully explained precipitate safe, and it is what turns
        // `>` into `>=` red.
        XCTAssertNil(PhaseVectorMatcher.challengeByMatrix(
            surviving: planted, bases: oneBase, settings: settings,
            accessibleRadius: 1.0, beating: (matched: best.matched, score: 1.0),
            scratch: scratch),
            "a challenger that merely tied the winner's count took the position")

        // And a winner it explains more than, it takes.
        XCTAssertNotNil(PhaseVectorMatcher.challengeByMatrix(
            surviving: planted, bases: oneBase, settings: settings,
            accessibleRadius: 1.0, beating: (matched: best.matched - 1, score: 1.0),
            scratch: scratch),
            "a challenger explaining one more vector than the winner did not take it")

        // The distance half of the rule, at its own boundary.
        XCTAssertNil(PhaseVectorMatcher.challengeByMatrix(
            surviving: planted, bases: oneBase, settings: settings,
            accessibleRadius: 1.0, beating: (matched: best.matched - 1, score: best.score),
            scratch: scratch),
            "a challenger tied the winner's distance and took the position anyway")
    }

    /// THE FRIEDEL-PAIR FLOOR (2026-09-15, Thronsen step 3). A candidate that
    /// explains exactly the two survivors u and −u is indexed; two survivors
    /// that are not a pair are not enough. Mutations this names: the
    /// `containsFriedelPair` clause dropped (the pair case goes not indexed),
    /// or the floor applied to any two survivors (the control goes indexed
    /// — its two survivors both match the candidate, so it is the floor and
    /// nothing else that keeps it out).
    func testAFriedelPairAloneIndexesACandidateAndTwoStraySurvivorsDoNot() throws {
        let library = try challengeLibrary()
        let settings = PhaseVectorSettings()
        let candidate = library.entries[library.candidateEntryIndices[0]]
        let scratch = PhaseVectorMatcher.Scratch(capacity: 64)
        // A reference vector of the candidate that no matrix vector sits on,
        // and its Friedel partner.
        let matrix = library.entries[library.matrixEntryIndices[0]]
        let own = try XCTUnwrap(candidate.vectors.first { v in
            !matrix.vectors.contains { simd_distance($0.q, v.q) < 2 * settings.pairRadiusInvAngstrom }
                && candidate.vectors.contains { simd_distance($0.q, -v.q) < 1e-6 }
        }, "the candidate has no Friedel pair clear of the matrix")
        let pair = [own.q, -own.q]
        let indexed = PhaseVectorMatcher.classify(
            vectors: pair, library: library, settings: settings, matrixEntry: matrix,
            candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        XCTAssertEqual(indexed.verdict, .indexed,
                       "a Friedel pair of the candidate's own reflections was not indexed: \(indexed.verdict)")
        XCTAssertEqual(Int(indexed.phaseIndex), candidate.phaseIndex)

        // Two survivors that are NOT a pair but are both the candidate's own
        // reflections, clear of the matrix, no shorter than `own` (so the
        // chance guard passes as it did for the pair): two matched of two,
        // which only the pair floor could admit. A stray that matches one
        // reference cannot tell the floor from the count (Gate B 2026-09-15).
        let other = try XCTUnwrap(candidate.vectors.first { v in
            simd_length(v.q) >= simd_length(own.q) - 1e-9
                && simd_distance(v.q, own.q) > 2 * settings.pairRadiusInvAngstrom
                && simd_distance(v.q, -own.q) > 2 * settings.pairRadiusInvAngstrom
                && !matrix.vectors.contains { simd_distance($0.q, v.q) < 2 * settings.pairRadiusInvAngstrom }
        }, "the candidate has no second reflection clear of the matrix")
        let stray = [own.q, other.q]
        XCTAssertFalse(PhaseVectorMatcher.containsFriedelPair(stray, radius: settings.pairRadiusInvAngstrom))
        let control = PhaseVectorMatcher.classify(
            vectors: stray, library: library, settings: settings, matrixEntry: matrix,
            candidateEntryIndices: library.candidateEntryIndices, scratch: scratch)
        XCTAssertNotEqual(control.verdict, .indexed,
                          "two stray survivors were indexed as a candidate under the pair floor")
    }

    // MARK: Fixtures

    /// Al as the matrix on [001], β″ [001] as the candidate — the pair that
    /// produced the false label, because β″ is coherent with Al and its [001]
    /// net covers most of Al's [011] net.
    private func challengeLibrary() throws -> PhaseReferenceLibrary {
        var settings = PhaseReferenceSettings()
        settings.kMaxInvAngstrom = 0.8
        settings.inPlaneStepDeg = 2
        return try PhaseReferenceLibrary.build(phases: [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "beta", displayName: "β″", crystal: .betaDoublePrime,
                            role: .candidate, zoneAxes: [SIMD3(0, 0, 1)]),
        ], settings: settings)
    }

    /// The matrix crystal's [011] net — a second aluminium grain, the case the
    /// library has no entry for because the user named one zone axis.
    private func matrixVectorsOnAnotherAxis(_ library: PhaseReferenceLibrary,
                                            degrees: Double) -> [SIMD2<Double>] {
        let crystal = library.phases[library.matrixPhaseIndex].crystal
        let reflections = crystal.reflections(kMax: library.settings.kMaxInvAngstrom)
        let base = PhaseReferenceLibrary.projectedVectors(
            reflections: reflections, crystal: crystal,
            zoneAxis: SIMD3(0, 1, 1), settings: library.settings)
        return PhaseReferenceLibrary.rotate(base, by: degrees * .pi / 180).map(\.q)
    }
}
