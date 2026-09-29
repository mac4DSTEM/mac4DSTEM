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
                             fittedX: [Float]? = [10, 11, 12, 13]) -> Calibration {
        var c = Calibration()
        if let ellipse { c.ellipseA = ellipse[0]; c.ellipseB = ellipse[1]; c.ellipseTheta = ellipse[2] }
        if let fittedX {
            c.origin = OriginMaps(width: 2, height: 2, measuredX: nil, measuredY: nil,
                                  fittedX: fittedX, fittedY: [20, 21, 22, 23])
        }
        return c
    }

    private func stamp(_ c: Calibration, origin: (x: Float, y: Float) = (10, 20))
        -> PhaseMappingProduct.CalibrationStamp {
        PhaseMappingProduct.CalibrationStamp(calibration: c, referenceOrigin: origin)
    }

    private func run(_ s: PhaseMappingProduct.CalibrationStamp?) -> PhaseMappingProduct.RunRecord {
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
        XCTAssertNil(r.claimsRefusal(currentInvAngstromPerPixel: 0.01, currentCalibration: stamp(base)),
                     "unchanged calibration draws")

        let moved = r.claimsRefusal(currentInvAngstromPerPixel: 0.01,
                                    currentCalibration: stamp(base, origin: (10.5, 20)))
        XCTAssertEqual(moved, "Origin or ellipse changed since the map — run again", "reference origin")

        XCTAssertNotNil(r.claimsRefusal(currentInvAngstromPerPixel: 0.01,
                                        currentCalibration: stamp(calibration(ellipse: [1.0, 1.2, 0.3]))),
                        "ellipse b")
        XCTAssertNotNil(r.claimsRefusal(currentInvAngstromPerPixel: 0.01,
                                        currentCalibration: stamp(calibration(ellipse: nil))),
                        "ellipse removed")
        XCTAssertNotNil(r.claimsRefusal(currentInvAngstromPerPixel: 0.01,
                                        currentCalibration: stamp(calibration(fittedX: [10, 11, 12, 13.5]))),
                        "one fitted origin value")
        XCTAssertNotNil(r.claimsRefusal(currentInvAngstromPerPixel: 0.01,
                                        currentCalibration: stamp(calibration(fittedX: nil))),
                        "origin maps removed")
    }

    /// Mutation: drop the Q comparison -> red.
    func testStillRefusesOnQScaleAndSaysSo() {
        let base = calibration()
        let r = run(stamp(base))
        XCTAssertEqual(r.claimsRefusal(currentInvAngstromPerPixel: 0.0101, currentCalibration: stamp(base)),
                       "Q calibration changed since the map — run again")
    }

    /// A run that recorded no calibration cannot be verified, so it does not draw.
    func testRefusesARunThatRecordedNoCalibration() {
        let base = calibration()
        XCTAssertNotNil(run(nil).claimsRefusal(currentInvAngstromPerPixel: 0.01,
                                               currentCalibration: stamp(base)))
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
        product.publish(map(), ranWith: run(nil), library: library(entries: 1))
        XCTAssertEqual(product.lastLibrary?.entries.count, 1)
        product.publish(map(), ranWith: run(nil), library: library(entries: 2))
        XCTAssertEqual(product.lastLibrary?.entries.count, 2, "a new run replaces the pair")
        product.publish(map(), ranWith: run(nil))
        XCTAssertNil(product.lastLibrary, "a run published without a library must not keep the old one")
        product.publish(map(), ranWith: run(nil), library: library(entries: 1))
        product.clear()
        XCTAssertNil(product.lastLibrary)
        XCTAssertNil(product.lastRun)
    }
}
