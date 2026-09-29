//
//  PhaseClaimGuardTests.swift
//  Three defects found in aa920d0 by review, each on its pure seam:
//    1. a `PendingEdits` closure flushed after an earlier phase was removed
//       must write to ITS phase (`PhaseMappingProduct.updatePhase(id:)`);
//    2. the claimed-disks overlay refuses when the origin or ellipse moved
//       since the run, not only the Q scale (`RunRecord.claimsRefusal`);
//    3. the run's reference library is kept by the product and dies with the run.
//  Each test names the mutation it was broken with.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PhaseClaimGuardTests: XCTestCase {

    // MARK: - 1. Deferred edits name a phase by id

    private func twoPhases() -> PhaseMappingProduct {
        let product = PhaseMappingProduct()
        product.add(CrystalModelLibrary.model(id: "al_fcc")!)
        product.add(CrystalModelLibrary.model(id: "mg_hcp")!)
        return product
    }

    /// Mutation: `updatePhase` looks the phase up by a position (`phases.indices.first`)
    /// instead of `id` -> the slab lands on the matrix, and this goes red.
    func testFlushedEditAfterRemovingAnEarlierPhaseLandsOnItsOwnPhase() {
        let product = twoPhases()
        let candidate = product.phases[1]
        let editID = UUID()
        // What the excitation-slab field registers at a keystroke: the slot's
        // stable id, resolved when the edit is flushed.
        let slotID = candidate.id
        PendingEdits.register(editID) {
            product.updatePhase(id: slotID) { $0.excitationSlabInvAngstrom = 0.3 }
        }
        // The earlier phase is removed before a toolbar verb flushes the edit.
        product.phases.remove(at: 0)
        product.phases[0].isMatrix = true
        PendingEdits.commitAll()

        XCTAssertEqual(product.phases.count, 1)
        XCTAssertEqual(product.phases[0].id, candidate.id)
        XCTAssertEqual(product.phases[0].excitationSlabInvAngstrom, 0.3)
    }

    /// Mutation: `updatePhase` returns true / writes `phases[0]` when the id is
    /// missing -> a removed phase's flush would edit a survivor; red here.
    func testFlushedEditForARemovedPhaseChangesNothing() {
        let product = twoPhases()
        let gone = product.phases[1].id
        product.phases.remove(at: 1)
        let before = product.phases
        XCTAssertFalse(product.updatePhase(id: gone) { $0.excitationSlabInvAngstrom = 9 })
        XCTAssertEqual(product.phases, before)
        XCTAssertNil(product.phases[0].excitationSlabInvAngstrom)
    }

    // MARK: - 2. Claims refuse on origin / ellipse changes

    private func calibration(ellipse: [Double]? = [1.0, 1.1, 0.3],
                             fittedX: [Float]? = [10, 11, 12, 13],
                             fittedY: [Float] = [20, 21, 22, 23]) -> Calibration {
        var c = Calibration()
        if let ellipse { c.ellipseA = ellipse[0]; c.ellipseB = ellipse[1]; c.ellipseTheta = ellipse[2] }
        if let fittedX {
            c.origin = OriginMaps(width: 2, height: 2, measuredX: nil, measuredY: nil,
                                  fittedX: fittedX, fittedY: fittedY)
        }
        return c
    }

    private func stamp(_ c: Calibration, origin: (x: Float, y: Float) = (10, 20))
        -> PhaseMappingProduct.CalibrationStamp {
        PhaseMappingProduct.CalibrationStamp(calibration: c, referenceOrigin: origin)
    }

    private func run(_ s: PhaseMappingProduct.CalibrationStamp) -> PhaseMappingProduct.RunRecord {
        PhaseMappingProduct.RunRecord(
            phaseSignature: "x", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(),
            libraryEntryCount: 1, matrixEntryIndex: 0, matrixInPlaneDegrees: 0,
            worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01, qScaleIsPhysical: true,
            peakCount: 0, calibration: s)
    }

    /// Mutation: `claimsRefusal` returns nil where it compares `calibration`
    /// (delete the `guard calibration == currentCalibration`) -> the origin,
    /// ellipse and map cases below go red.
    func testRefusesWhenOriginOrEllipseDiffersFromTheRun() {
        let base = calibration()
        let r = run(stamp(base))
        let message = "Origin or ellipse changed since the map — run again"
        XCTAssertNil(r.claimsRefusal(currentInvAngstromPerPixel: 0.01, currentCalibration: stamp(base)),
                     "unchanged calibration draws")

        let cases: [(String, PhaseMappingProduct.CalibrationStamp)] = [
            ("reference origin", stamp(base, origin: (10.5, 20))),
            ("ellipse b", stamp(calibration(ellipse: [1.0, 1.2, 0.3]))),
            ("ellipse removed", stamp(calibration(ellipse: nil))),
            ("one fitted-X value", stamp(calibration(fittedX: [10, 11, 12, 13.5]))),
            ("one fitted-Y value", stamp(calibration(fittedY: [20, 21, 22, 23.5]))),
            ("origin maps removed", stamp(calibration(fittedX: nil))),
        ]
        for (name, changed) in cases {
            XCTAssertEqual(r.claimsRefusal(currentInvAngstromPerPixel: 0.01, currentCalibration: changed),
                           message, name)
        }
    }

    /// Mutation: drop the Q comparison -> red.
    func testStillRefusesOnQScaleAndSaysSo() {
        let base = calibration()
        let r = run(stamp(base))
        XCTAssertEqual(r.claimsRefusal(currentInvAngstromPerPixel: 0.0101, currentCalibration: stamp(base)),
                       "Q calibration changed since the map — run again")
    }

    /// The quick stamp (no map digest) must not depend on the maps' contents.
    func testQuickStampIgnoresMapContentsButKeepsOriginAndEllipse() {
        let a = PhaseMappingProduct.CalibrationStamp(
            calibration: calibration(), referenceOrigin: (10, 20), includeMapDigest: false)
        let b = PhaseMappingProduct.CalibrationStamp(
            calibration: calibration(fittedX: [10, 11, 12, 13.5]), referenceOrigin: (10, 20),
            includeMapDigest: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, PhaseMappingProduct.CalibrationStamp(
            calibration: calibration(ellipse: [1, 1.3, 0.3]), referenceOrigin: (10, 20),
            includeMapDigest: false))
    }

    /// Fable review of c8db808: an origin re-fit that keeps the mean origin and
    /// the map dimensions left the overlay's task key unchanged, so the old
    /// rings stayed drawn. The quick stamp (the old key) is equal for these two
    /// calibrations; the key must not be. Mutation: drop `fittedX/fittedY` from
    /// `CalibrationKey` -> the last assertion goes red.
    func testOverlayKeyChangesWhenTheFittedMapsChangeButTheirMeanDoesNot() {
        let a = calibration(fittedX: [10, 11, 12, 13], fittedY: [20, 21, 22, 23])
        let b = calibration(fittedX: [13, 12, 11, 10], fittedY: [23, 22, 21, 20])   // same mean, same size
        let quick = { (c: Calibration) in
            PhaseMappingProduct.CalibrationStamp(calibration: c, referenceOrigin: (11.5, 21.5),
                                                 includeMapDigest: false)
        }
        XCTAssertEqual(quick(a), quick(b), "premise: the old key could not tell these apart")
        XCTAssertNotEqual(stamp(a, origin: (11.5, 21.5)), stamp(b, origin: (11.5, 21.5)),
                          "the full stamp (what claimsRefusal compares) can")
        let key = { (c: Calibration) in
            PhaseMappingProduct.CalibrationKey(calibration: c, referenceOrigin: (11.5, 21.5))
        }
        XCTAssertEqual(key(a), key(a))
        XCTAssertNotEqual(key(a), key(b), "the overlay must re-run its task")
        XCTAssertNotEqual(key(a), key(calibration(fittedX: [10, 11, 12, 13], fittedY: [23, 22, 21, 20])),
                          "a Y-only change")
    }

    // MARK: - 3. The library lives with the run

    private func library(entries: Int) -> PhaseReferenceLibrary {
        let phases = [PhaseDefinition(id: "matrix", displayName: "Matrix", crystal: .aluminum,
                                      role: .matrix, zoneAxes: [SIMD3(0, 0, 1)])]
        let vectors = [ReferenceVector(h: 1, k: 0, l: 0, q: SIMD2(0.5, 0), length: 0.5, relativeIntensity: 1)]
        return PhaseReferenceLibrary(
            phases: phases, settings: PhaseReferenceSettings(),
            entries: (0..<entries).map { _ in
                PhaseOrientationReference(phaseIndex: 0, zoneAxis: SIMD3(0, 0, 1),
                                          inPlaneRotationRad: 0, vectors: vectors)
            }, matrixPhaseIndex: 0)
    }

    private func map() -> PhaseMap {
        PhaseMap(width: 1, height: 1, matrixEntryIndex: 0, phaseNames: ["Al"], matrixPhaseIndex: 0)
    }

    /// Mutation: `publish` forgets `lastLibrary = library` -> first assertion red;
    /// `clear` forgets `lastLibrary = nil` -> the last one red.
    func testProductKeepsTheRunsLibraryAndDropsItWithTheRun() {
        let product = PhaseMappingProduct()
        XCTAssertNil(product.lastLibrary)
        product.publish(map(), ranWith: run(stamp(calibration())), library: library(entries: 1))
        XCTAssertEqual(product.lastLibrary?.entries.count, 1)
        product.publish(map(), ranWith: run(stamp(calibration())), library: library(entries: 2))
        XCTAssertEqual(product.lastLibrary?.entries.count, 2, "a new run replaces the pair")
        product.publish(map(), ranWith: run(stamp(calibration())))
        XCTAssertNil(product.lastLibrary, "a run published without a library must not keep the old one")
        product.publish(map(), ranWith: run(stamp(calibration())), library: library(entries: 1))
        product.clear()
        XCTAssertNil(product.lastLibrary)
        XCTAssertNil(product.lastRun)
    }

    // MARK: - 4. The zone-axis ranking is stale once the calibration moves (S4)

    private func fit() -> PhaseVectorMatcher.ZoneAxisFit {
        PhaseVectorMatcher.ZoneAxisFit(zoneAxis: SIMD3(1, 1, 0), inPlaneRotationRad: 0,
                                       matchedVectors: 40, totalVectors: 100, meanDistance: 0.002,
                                       chanceMatchedVectors: 5, sweepMedianFraction: 0.1)
    }

    private func zoneRun(_ c: Calibration, q: Double = 0.01, matrix: String = "",
                         tolerance: Double = 0.02) -> PhaseMappingProduct.ZoneAxisRun {
        PhaseMappingProduct.ZoneAxisRun(invAngstromPerPixel: q, calibration: stamp(c),
                                        matrixPhase: matrix, matrixToleranceInvAngstrom: tolerance)
    }

    /// Mutation: drop the Q comparison in `ZoneAxisRun.staleness` -> the Q case
    /// goes red; drop the `calibration ==` guard -> the origin/ellipse/map
    /// cases go red. Against the old code (no scale beside the list) none of
    /// this compiles: the list was shown whatever the calibration.
    func testRankingIsStaleWhenQOriginOrEllipseMoved() {
        let base = calibration()
        let product = PhaseMappingProduct()
        product.setZoneAxisFits([fit()], ranWith: zoneRun(base))
        XCTAssertNil(product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.01,
                                               currentCalibration: stamp(base)), "unchanged is current")
        XCTAssertEqual(product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.0101,
                                                 currentCalibration: stamp(base)),
                       "The Q scale changed since this ranking — fit again")
        let moved = "The origin or ellipse changed since this ranking — fit again"
        XCTAssertEqual(product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.01,
                                                 currentCalibration: stamp(base, origin: (10.5, 20))), moved, "origin")
        XCTAssertEqual(product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.01,
                                                 currentCalibration: stamp(calibration(ellipse: [1, 1.2, 0.3]))),
                       moved, "ellipse")
        XCTAssertEqual(product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.01,
                                                 currentCalibration: stamp(calibration(fittedX: [10, 11, 12, 13.5]))),
                       moved, "origin map X value")
        XCTAssertEqual(product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.01,
                                                 currentCalibration: stamp(calibration(fittedY: [20, 21, 22, 23.5]))),
                       moved, "origin map Y value")
    }

    /// S12: the ranking is also a function of WHICH crystal is the matrix and of
    /// the matrix tolerance the sweep scored with. Mutations: drop the matrix-phase
    /// guard in `ZoneAxisRun.staleness` (or `matrixIdentity` returning a constant)
    /// -> the swap cases go red; drop the tolerance guard -> the tolerance case goes
    /// red; put the zone axis into `matrixIdentity` -> the "fit writes the axis"
    /// case goes red (the ranking would mark itself stale the moment it wrote its winner).
    func testRankingIsStaleWhenTheMatrixPhaseOrTheMatchingToleranceChanged() {
        let base = calibration()
        let product = PhaseMappingProduct()
        let al = CrystalModelLibrary.models[0], other = CrystalModelLibrary.models[1]
        product.phases = [
            PhaseMappingSlot(model: al, isMatrix: true, u: 1, v: 1, w: 0),
            PhaseMappingSlot(model: other, isMatrix: false, u: 0, v: 0, w: 1),
        ]
        product.matching.matrixToleranceInvAngstrom = 0.02
        product.setZoneAxisFits([fit()], ranWith: zoneRun(base, matrix: product.matrixIdentity, tolerance: 0.02))
        func staleness() -> String? {
            product.zoneAxisStaleness(currentInvAngstromPerPixel: 0.01, currentCalibration: stamp(base))
        }
        XCTAssertNotEqual(product.matrixIdentity, "", "the matrix slot has an identity")
        XCTAssertNil(staleness(), "unchanged is current")

        // The fit's own write-back and edits to a candidate are not a change of matrix.
        product.phases[0].u = 2; product.phases[0].v = 0; product.phases[0].w = 0
        product.phases[1].w = 3
        XCTAssertNil(staleness(), "the winner written into the matrix axis leaves the ranking current")

        product.matching.matrixToleranceInvAngstrom = 0.03
        XCTAssertEqual(staleness(), "The matrix removal tolerance changed since this ranking — fit again")
        product.matching.matrixToleranceInvAngstrom = 0.02
        XCTAssertNil(staleness(), "back to the recorded tolerance is current again")

        product.phases[0].isMatrix = false
        product.phases[1].isMatrix = true
        XCTAssertEqual(staleness(), "The matrix phase changed since this ranking — fit again", "another phase is the matrix")
        product.phases[1].isMatrix = false
        XCTAssertEqual(staleness(), "The matrix phase changed since this ranking — fit again", "no phase is the matrix")
        product.phases[0].isMatrix = true
        product.phases[0].model = CrystalModel(id: al.id, displayName: al.displayName, crystal: other.crystal,
                                               symmetry: other.symmetry, source: .builtIn)
        XCTAssertEqual(staleness(), "The matrix phase changed since this ranking — fit again",
                       "a different crystal under the same id")
    }

    /// Mutation: `clear` (or the preset) forgets `zoneAxisRun = nil` -> red;
    /// a run and its list are written and cleared together (setZoneAxisFits / clear), so a list without a run is unreachable.
    func testRankingRunDiesWithTheListAndAnEmptyListIsNeverStale() {
        let product = PhaseMappingProduct()
        XCTAssertNil(product.zoneAxisStaleness(currentInvAngstromPerPixel: 5, currentCalibration: stamp(calibration())),
                     "nothing shown, nothing stale")
        product.setZoneAxisFits([fit()], ranWith: zoneRun(calibration()))
        product.clear()
        XCTAssertTrue(product.zoneAxisFits.isEmpty)
        XCTAssertNil(product.zoneAxisRun)
        product.setZoneAxisFits([fit()], ranWith: zoneRun(calibration()))
        product.applyAlMgSiPreset(precipitate: CrystalModelLibrary.model(id: "mg_hcp")!)
        XCTAssertTrue(product.zoneAxisFits.isEmpty)
        XCTAssertNil(product.zoneAxisRun)
    }
}
