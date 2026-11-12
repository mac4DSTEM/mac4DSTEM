import XCTest
import DiffractoCore
import DiffractoOrientation
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#221: the reference library is built to the nearest detector edge, a square detector records to its corners. A
/// peak beyond the library's reach has no reference in any entry, so the matcher must not be given it: on a 66 px SPED scan
/// (Zenodo 10.5281/zenodo.2652906) the Al 400 spots in the detector's corners made all 160,000 positions "not indexed".
final class PeaksBeyondLibraryReachTests: XCTestCase {

    /// "Ignore peaks beyond" 0 means the detector's edge, which is the library's reach; a larger setting is held to the
    /// reach; a smaller one stands; nothing else in the settings changes.
    func testThePeakCutIsHeldToTheLibrarysReach() {
        var settings = PhaseVectorSettings()
        settings.pairRadiusInvAngstrom = 0.0265
        settings.maximumVectorInvAngstrom = 0
        let fromZero = AppState.matchingWithinLibraryReach(settings, libraryKMaxInvAngstrom: 0.876)
        XCTAssertEqual(fromZero.maximumVectorInvAngstrom, 0.876)
        XCTAssertEqual(fromZero.pairRadiusInvAngstrom, 0.0265)

        settings.maximumVectorInvAngstrom = 1.6
        XCTAssertEqual(AppState.matchingWithinLibraryReach(settings, libraryKMaxInvAngstrom: 0.876).maximumVectorInvAngstrom, 0.876)

        settings.maximumVectorInvAngstrom = 0.68   // Thronsen et al.'s step 3 against a library to 0.70
        XCTAssertEqual(AppState.matchingWithinLibraryReach(settings, libraryKMaxInvAngstrom: 0.70).maximumVectorInvAngstrom, 0.68)

        // A reach that cannot be read changes nothing.
        settings.maximumVectorInvAngstrom = 0
        XCTAssertEqual(AppState.matchingWithinLibraryReach(settings, libraryKMaxInvAngstrom: .nan).maximumVectorInvAngstrom, 0)
        XCTAssertEqual(AppState.matchingWithinLibraryReach(settings, libraryKMaxInvAngstrom: 0).maximumVectorInvAngstrom, 0)
    }

    /// The matcher itself, on a planted pattern: the matrix's spots inside the library's reach and two more beyond it (a
    /// square detector's corners). With every peak given, the position has two vectors nothing explains and is not the
    /// matrix; with the cut at the reach it is.
    func testCornerPeaksBeyondTheReachNoLongerUnmakeTheMatrix() throws {
        let reach = 0.80, q = 0.02, origin: Float = 50
        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = reach
        let aluminium = PhaseDefinition(id: "al", displayName: "Al", crystal: CrystalPresets.aluminum, role: .matrix, zoneAxes: [SIMD3(0, 0, 1)],
                                        orientationRelationships: [], excitationSlabInvAngstrom: 0.05)
        let precipitate = PhaseDefinition(id: "beta", displayName: "beta''", crystal: CrystalPresets.betaDoublePrime, role: .candidate, zoneAxes: [SIMD3(0, 1, 0)],
                                          orientationRelationships: [], excitationSlabInvAngstrom: 0.05)
        let library = try PhaseReferenceLibrary.build(phases: [aluminium, precipitate], settings: reference)
        let matrixIndex = try XCTUnwrap(library.entries.indices.first { !library.candidateEntryIndices.contains($0) })
        let entry = library.entries[matrixIndex]
        // The entry's own reflections as peaks, plus two at 0.99 1/Å (Al 400 lies there) in opposite corners.
        var vectors: [SIMD2<Double>] = entry.vectors.map(\.q)
        vectors.append(SIMD2<Double>(0.70, 0.70))
        vectors.append(SIMD2<Double>(-0.70, -0.70))
        vectors.insert(SIMD2<Double>(0, 0), at: 0)
        let peaks: [SIMD2<Double>] = vectors.map { v in SIMD2<Double>(Double(origin) + v.x / q, Double(origin) + v.y / q) }
        var settings = PhaseVectorSettings()
        settings.classificationRule = .knownVariants
        func verdict(_ s: PhaseVectorSettings) throws -> PhaseVerdict {
            let map = try XCTUnwrap(PhaseVectorMatcher.map(scan: [peaks], scanWidth: 1, scanHeight: 1, library: library, settings: s,
                                                           originX: origin, originY: origin, invAngstromPerPixel: q, progress: nil, isCancelled: nil))
            return map.results[0].verdict
        }
        XCTAssertNotEqual(try verdict(settings), .matrix, "fixture: with the corner peaks given the position must not come out as matrix")
        XCTAssertEqual(try verdict(AppState.matchingWithinLibraryReach(settings, libraryKMaxInvAngstrom: reach)), .matrix)
    }
}
