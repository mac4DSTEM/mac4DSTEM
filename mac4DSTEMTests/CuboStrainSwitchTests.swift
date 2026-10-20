import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The call sites of the CuboStrain / CuboPhase switch (2026-10-20): what the app asks of the kit and what it keeps when the
/// kit refuses. The kit's own numbers are pinned in CuboKit; these pin the app's adaptation.
final class CuboStrainSwitchTests: XCTestCase {

    private let origin = (x: Float(50), y: Float(50))

    private func lattice(g1: (Float, Float), g2: (Float, Float), weight: Float = 1) -> [BraggPeak] {
        let hk: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)]
        return hk.map { h, k in
            BraggPeak(x: origin.x + h * g1.0 + k * g2.0, y: origin.y + h * g1.1 + k * g2.1, intensity: weight)
        }
    }

    private func vectors(extra: [BraggPeak] = [], weight: Float = 1) -> BraggVectors {
        let reference = lattice(g1: (12, 0), g2: (0, 12), weight: weight)
        let strained = lattice(g1: (12.6, 0), g2: (0, 11.4), weight: weight)
        let peaks = [reference + extra, reference, strained + extra, reference, reference, strained]
        return BraggVectors(scanWidth: 3, scanHeight: 2, peaks: peaks)
    }

    private func compute(_ v: BraggVectors) throws -> StrainMap {
        try XCTUnwrap(StrainMapping.compute(bragg: v, originX: origin.x, originY: origin.y, minNumPeaks: 5))
    }

    /// Mutation: pass NaN / inf peaks to the kit unfiltered - the kit refuses the whole population and no basis is found.
    func testNonFinitePeaksAreDroppedWithoutChangingTheBasis() throws {
        let clean = try compute(vectors())
        let junk = [BraggPeak(x: .nan, y: 3, intensity: 1), BraggPeak(x: .infinity, y: .nan, intensity: 1),
                    BraggPeak(x: 60, y: 61, intensity: .nan)]
        let dirty = try compute(vectors(extra: junk))
        XCTAssertEqual(dirty.refG1.x, clean.refG1.x); XCTAssertEqual(dirty.refG1.y, clean.refG1.y)
        XCTAssertEqual(dirty.refG2.x, clean.refG2.x); XCTAssertEqual(dirty.refG2.y, clean.refG2.y)
        XCTAssertEqual(dirty.diagnostics.basisConditionNumber, clean.diagnostics.basisConditionNumber)
        XCTAssertEqual(dirty.indexedFraction, 1)
    }

    /// Mutation: drop the division by the largest weight in `fitLattice` - a weight of 1e11 trips the kit's 1e10 guard,
    /// every position is refused, and indexedFraction is 0.
    func testAWeightAboveTheKitsGuardStillIndexesAndGivesTheSameStrain() throws {
        let light = try compute(vectors(weight: 1))
        let heavy = try compute(vectors(weight: 1e11))
        XCTAssertEqual(heavy.indexedFraction, 1)
        XCTAssertEqual(heavy.diagnostics.refusedLocalFitCount, 0)
        for i in 0..<6 {
            XCTAssertEqual(heavy.exx[i], light.exx[i], accuracy: 1e-5)
            XCTAssertEqual(heavy.eyy[i], light.eyy[i], accuracy: 1e-5)
        }
    }

    /// iDPC refuses a non-finite CoM field by name (the kit's refusal, as DPC.IDPCError), never an image.
    func testIDPCRefusesANonFiniteFieldWithATypedError() {
        var com = [Float](repeating: 0.1, count: 3 * 3 * 2)
        com[5] = .nan
        XCTAssertThrowsError(try DPC.integrateIDPC(com: com, width: 3, height: 3)) { error in
            guard case DPC.IDPCError.invalidInput = error else { return XCTFail("\(error)") }
        }
    }
}
