import XCTest
import simd
import DiffractoCore
import DiffractoOrientation
import DSTEMCore
import DSTEMSession

/// Task 40: the variant of each precipitate object. The planted case: beta'' needles in an Al scan whose orientations are built from the
/// kit's own twelve variants (`OrientationVariantSet`, planted truth with no Python reference), so the counts per variant and per needle
/// direction are known exactly. Validation "none" until the beta'' truth set.
final class ObjectVariantsTests: XCTestCase {
    private let al = CrystalPresets.aluminum
    private let beta = CrystalPresets.betaDoublePrime
    private var setup: VariantSetup { get throws { try VariantSetup(precipitate: beta, matrix: al, preset: .betaDoublePrimeInAl) } }

    /// The matrix's orientation: Al [001] along the beam, in-plane rotation 0.
    private var matrixOrientation: simd_double3x3 {
        let n = PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(0, 0, 1), crystal: al)!
        return ZoneAxisFrame.matrix(detectorBasis: ZoneAxisFrame.detectorBasis(zoneAxis: n), inPlaneAngle: 0)
    }

    /// A precipitate orientation whose precipitate-to-matrix rotation is variant `k` turned by `symmetry` on the right and by `degrees`
    /// about a fixed axis: `M_p = (R_k S delta)^T M_m` since `observed = M_m M_p^T`.
    private func precipitateOrientation(variant k: Int, symmetry s: Int = 0, offDegrees: Double = 0.3) throws -> simd_double3x3 {
        let set = try setup.set
        let op = set.precipitateSymmetry.operators[s]
        let a = offDegrees * .pi / 180
        let delta = simd_double3x3(columns: (SIMD3(cos(a), sin(a), 0), SIMD3(-sin(a), cos(a), 0), SIMD3(0, 0, 1)))
        let observed = set.variants[k] * op * delta
        return observed.transpose * matrixOrientation
    }

    private struct Scene {
        var objects: PrecipitateSegmentation.ClassMapObjects
        var results: [PhaseVectorResult]
        var orientations: ObjectVariantAssigner.Orientations
        var idAt: [String: Int]
    }

    /// 3 x 3 objects of class 1 on a 4-pixel pitch in a (4 * count + 4) x 16 scan; each is given a list of (entry index, pixel count) votes, the rest of its
    /// pixels unindexed. `entries` are the orientations of entries 0...; the matrix is class 0.
    private func scene(_ plan: [(name: String, votes: [(entry: Int, count: Int)])], entries: [simd_double3x3]) throws -> Scene {
        let w = 4 * plan.count + 4, h = 16
        var labels = [Int32](repeating: 0, count: w * h)
        var results = [PhaseVectorResult](repeating: { var r = PhaseVectorResult(); r.verdict = .matrix; r.phaseIndex = 0; return r }(), count: w * h)
        var anchors: [String: (x: Int, y: Int)] = [:]
        for (n, item) in plan.enumerated() {
            let x0 = 2 + 4 * n, y0 = 4
            anchors[item.name] = (x0, y0)
            var pixels: [Int] = []
            for dy in 0..<3 { for dx in 0..<3 { pixels.append((y0 + dy) * w + x0 + dx) } }
            var cursor = 0
            for i in pixels {
                labels[i] = 1
                var r = PhaseVectorResult()
                r.verdict = .notIndexed
                results[i] = r
            }
            for vote in item.votes {
                for _ in 0..<vote.count where cursor < pixels.count {
                    var r = PhaseVectorResult()
                    r.verdict = .indexed; r.phaseIndex = 1; r.entryIndex = Int32(vote.entry)
                    results[pixels[cursor]] = r
                    cursor += 1
                }
            }
        }
        let objects = PrecipitateSegmentation.classObjects(
            labels: labels, width: w, height: h,
            roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: []), pixelSize: 1, pixelUnit: "nm")
        var idAt: [String: Int] = [:]
        for object in objects.classes.flatMap(\.objects) {
            for (name, a) in anchors where object.pixelIndices.contains(a.y * w + a.x) { idAt[name] = object.id }
        }
        let orientations = ObjectVariantAssigner.Orientations(
            entryPhase: [Int](repeating: 1, count: entries.count), entryOrientation: entries, matrixOrientation: matrixOrientation, inPlaneStepDegrees: 2)
        return Scene(objects: objects, results: results, orientations: orientations, idAt: idAt)
    }

    /// The planted truth. Twelve needles, one per variant (each seen through a different precipitate symmetry operator and 0.3 degrees off),
    /// give twelve assigned objects, four per needle direction, each in its own variant. Then the refusals: 60 % and 40 % of the pixels for two
    /// variants (assigned to the majority), a tie, 30 % agreement, a needle 5 degrees from every variant, and an object with no orientation.
    /// Mutations: the variant read from the wrong end (`observedRelation` transposed), the direction from the wrong column, the agreement floor
    /// dropped, or a tie broken silently - each moves a planted count.
    func testPlantedNeedlesGiveThePlantedVariantsDirectionsAndRefusals() throws {
        let set = try setup.set
        var entries: [simd_double3x3] = []
        for k in 0..<12 { entries.append(try precipitateOrientation(variant: k, symmetry: k % 2)) }       // entries 0...11: variant k
        entries.append(try precipitateOrientation(variant: 7, offDegrees: 5))                              // entry 12: 5 degrees off variant 8
        var plan: [(name: String, votes: [(entry: Int, count: Int)])] = (0..<12).map { ("v\($0)", [(entry: $0, count: 9)]) }
        plan.append(("majority", [(entry: 0, count: 6), (entry: 5, count: 3)]))     // 6/9 = 67 % for variant 1: assigned
        plan.append(("tie", [(entry: 0, count: 4), (entry: 5, count: 4)]))          // 4 and 4 of 9: tie, ambiguous
        plan.append(("weak", [(entry: 3, count: 3)]))                               // 3/9 = 33 %: below the floor
        plan.append(("off", [(entry: 12, count: 9)]))                               // every pixel 5 degrees from variant 8
        plan.append(("none", []))                                                    // no indexed pixel
        let s = try scene(plan, entries: entries)
        let run = ObjectVariantAssigner.run(objects: s.objects, results: s.results, orientations: s.orientations, precipitatePhaseIndex: 1,
                                            setup: try setup, settings: VariantSettings())
        for k in 0..<12 {
            let a = try XCTUnwrap(run.perObject[try XCTUnwrap(s.idAt["v\(k)"])])
            XCTAssertEqual(a.variant, k + 1, "needle \(k)")
            XCTAssertEqual(a.direction, try setup.needleDirection[k])
            XCTAssertEqual(a.agreement, 1)
            XCTAssertEqual(try XCTUnwrap(a.angleDegrees), 0.3, accuracy: 0.01, "the planted 0.3 degrees")
        }
        let direction = (0..<12).map { try! XCTUnwrap(run.perObject[s.idAt["v\($0)"]!]?.direction) }
        XCTAssertEqual((0..<3).map { d in direction.filter { $0 == d }.count }, [4, 4, 4], "four needle variants per cube axis")
        XCTAssertEqual(set.variants.count, 12)
        XCTAssertEqual(run.perObject[s.idAt["majority"]!]?.variant, 1)
        XCTAssertEqual(try XCTUnwrap(run.perObject[s.idAt["majority"]!]?.agreement), 6.0 / 9, accuracy: 1e-12)
        XCTAssertEqual(run.perObject[s.idAt["tie"]!]?.status, .ambiguous("variants 1 and 6 tie"))
        XCTAssertNil(run.perObject[s.idAt["tie"]!]?.variant)
        XCTAssertEqual(run.perObject[s.idAt["weak"]!]?.status, .ambiguous("only 33 % of the pixels agree on variant 4"))
        XCTAssertEqual(run.perObject[s.idAt["off"]!]?.status, .ambiguous("no pixel is within 1\u{00B0} of a variant"))
        XCTAssertEqual(run.perObject[s.idAt["none"]!]?.status, .noOrientation)
        XCTAssertEqual(run.perObject.values.filter(\.isAssigned).count, 13, "12 needles and the majority one")
    }

    /// A looser tolerance admits the 5-degree needle: the tolerance is the person's, recorded, and moves the result.
    /// Mutation: the tolerance ignored - the needle stays refused.
    func testTheToleranceIsTheSettings() throws {
        let entries = [try precipitateOrientation(variant: 7, offDegrees: 5)]
        let s = try scene([("off", [(entry: 0, count: 9)])], entries: entries)
        var settings = VariantSettings()
        XCTAssertNil(ObjectVariantAssigner.run(objects: s.objects, results: s.results, orientations: s.orientations, precipitatePhaseIndex: 1,
                                               setup: try setup, settings: settings).perObject[s.idAt["off"]!]?.variant)
        settings.toleranceDegrees = 6
        let a = ObjectVariantAssigner.run(objects: s.objects, results: s.results, orientations: s.orientations, precipitatePhaseIndex: 1,
                                          setup: try setup, settings: settings).perObject[s.idAt["off"]!]
        XCTAssertEqual(a?.variant, 8)
        XCTAssertEqual(try XCTUnwrap(a?.angleDegrees), 5, accuracy: 0.01)
    }

    /// The entry-to-orientation convention against the kit's own projection: a reflection g of the crystal, projected into the detector plane
    /// by the library (zone axis frame, then rotated by +theta) equals the first two components of M^T g for the entry's orientation matrix M.
    /// This is what lets `observedRelation` be read as the precipitate-to-matrix rotation. Mutation: theta's sign flipped in
    /// `entryOrientation` - the second component's sign moves.
    func testAnEntrysOrientationReproducesTheLibrarysProjection() throws {
        let zone = SIMD3(0, 1, 0)
        let theta = 37.0 * .pi / 180
        let g = SIMD3<Double>(0.12, 0.0, 0.31)   // Cartesian reciprocal vector of beta'' (any vector: the identity is linear)
        let entry = PhaseOrientationReference(phaseIndex: 0, zoneAxis: zone, inPlaneRotationRad: theta, vectors: [])
        let n = try XCTUnwrap(PhaseReferenceLibrary.cartesianZoneAxis(zone, crystal: beta))
        let basis = ZoneAxisFrame.detectorBasis(zoneAxis: n)
        let base = SIMD2(simd_dot(g, basis.columns.0), simd_dot(g, basis.columns.1))
        let c = cos(theta), s = sin(theta)
        let libraryProjection = SIMD2(c * base.x - s * base.y, s * base.x + c * base.y)   // `PhaseReferenceLibrary.rotate`
        let m = try XCTUnwrap(ObjectVariantAssigner.entryOrientation(entry, crystal: beta))
        let detector = m.transpose * g
        XCTAssertEqual(detector.x, libraryProjection.x, accuracy: 1e-6)
        XCTAssertEqual(detector.y, libraryProjection.y, accuracy: 1e-6)
        XCTAssertEqual(detector.z, simd_dot(g, n), accuracy: 1e-9, "the third component is along the beam")
    }
}
