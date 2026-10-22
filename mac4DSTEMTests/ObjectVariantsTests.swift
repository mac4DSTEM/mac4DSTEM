import XCTest
import simd
import DiffractoCore
import DiffractoOrientation
@testable import mac4DSTEM
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
            XCTAssertEqual(a.direction, try setup.habitFamily[k])
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

    /// Through the report: the planted per-variant, per-direction and unassigned counts come out of `PrecipitateObjectReport.make` exactly, a
    /// group's areal density is the kit function over that group's counted objects, the CSV carries the columns and the group lines, and a
    /// snapshot from before the columns decodes with none. Mutations: the unassigned counted as a variant, the direction groups built from
    /// the wrong objects, a column missing from the CSV or the header out of step with the rows - each moves a planted number.
    func testThePlantedCountsComeOutOfTheReportAndTheCSV() throws {
        var entries: [simd_double3x3] = []
        for k in 0..<12 { entries.append(try precipitateOrientation(variant: k, symmetry: k % 2)) }
        var plan: [(name: String, votes: [(entry: Int, count: Int)])] = (0..<12).map { ("v\($0)", [(entry: $0, count: 9)]) }
        plan.append(("majority", [(entry: 0, count: 6), (entry: 5, count: 3)]))
        plan.append(("tie", [(entry: 0, count: 4), (entry: 5, count: 4)]))
        plan.append(("weak", [(entry: 3, count: 3)]))
        plan.append(("none", []))
        let s = try scene(plan, entries: entries)
        let settings = VariantSettings()
        let run = ObjectVariantAssigner.run(objects: s.objects, results: s.results, orientations: s.orientations, precipitatePhaseIndex: 1,
                                            setup: try setup, settings: settings)
        let report = PrecipitateObjectReport.make(objects: s.objects, phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: 1, pixelUnit: "nm",
                                                  minimumAreaPx: 1, variantJoin: run, variantSettings: settings, endOnDirection: 2)
        let groups = try XCTUnwrap(report.variantGroups)
        func group(_ kind: PrecipitateObjectReport.VariantGroup.Kind, _ i: Int) -> PrecipitateObjectReport.VariantGroup { groups.first { $0.kind == kind && $0.index == i }! }
        let direction = try (0..<12).map { try setup.habitFamily[$0] }
        for d in 0..<3 {
            let expected = direction.filter { $0 == d }.count + (direction[0] == d ? 1 : 0)   // plus the majority object, variant 1
            XCTAssertEqual(group(.direction, d).totalObjects, expected, "direction \(d)")
            XCTAssertEqual(group(.direction, d).countedObjects, expected)
        }
        XCTAssertEqual((1...12).map { group(.variant, $0).totalObjects }, [2] + [Int](repeating: 1, count: 11), "variant 1 has its needle and the majority object")
        XCTAssertEqual(group(.unassigned, 0).totalObjects, 3, "the tie, the weak object and the one with no orientation")
        XCTAssertEqual(group(.unassigned, 0).detail, "ambiguous 2, no orientation 1")
        // the group's density is the kit function over exactly that group's counted objects
        let ids = Set(report.rows.filter { $0.variant?.direction == 0 }.map(\.id))
        let subset = s.objects.classes.flatMap(\.objects).filter { ids.contains($0.id) }
        let kit = PrecipitateSegmentation.density(objects: subset, accepted: ids, analysedPixels: s.objects.analysedPixels,
                                                  width: s.objects.width, height: s.objects.height, pixelSize: 1, pixelUnit: "nm")
        XCTAssertEqual(group(.direction, 0).arealDensity, kit.arealDensity)
        // the CSV
        let csv = report.csv()
        XCTAssertTrue(csv.contains("variant,direction,variant_status,variant_agreement,variant_angle_deg"))
        XCTAssertTrue(csv.contains("# unassigned 0: 3 counted of 3"))
        XCTAssertTrue(csv.contains("# end-on: needles along [001] lie along the beam"))
        let header = csv.split(separator: "\n").first { !$0.hasPrefix("#") }!.split(separator: ",", omittingEmptySubsequences: false).count
        for line in csv.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("id,") {
            XCTAssertEqual(line.split(separator: ",", omittingEmptySubsequences: false).count - (line.contains("\"") ? 1 : 0), header, "every row has the header's columns: \(line)")
        }
        // a report decoded from before the columns existed
        let old = PrecipitateObjectReport.make(objects: s.objects, phaseNames: ["Al", "beta"], matrixPhaseIndex: 0, pixelSize: 1, pixelUnit: "nm", minimumAreaPx: 1)
        let decoded = try JSONDecoder().decode(PrecipitateObjectReport.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.variantGroups); XCTAssertNil(decoded.rows.first?.variant)
        XCTAssertFalse(old.csv().contains("variant_status"))
        let round = try JSONDecoder().decode(PrecipitateObjectReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(round, report)
    }

    /// The settings round-trip through the lineage parameters; a sidecar without them gives none.
    func testTheSettingsRoundTripThroughTheLineageParameters() {
        var settings = VariantSettings()
        settings.toleranceDegrees = 2.5; settings.agreementMinimum = 0.6; settings.phaseName = "beta"
        XCTAssertEqual(VariantSettings(parameters: settings.parameters), settings)
        XCTAssertNil(VariantSettings(parameters: ["connectivity": "8"]))
        XCTAssertNil(VariantSettings().parameters["variant_tolerance_deg"], "no tolerance: the default is the library's, not a recorded number")
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

/// The variant colours and the legend's words (design 2026-10-22 §3.3). Pure values, no screen.
final class VariantPaletteTests: XCTestCase {
    /// Three directions are three different hues, a direction's four variants four different shades of it, and an unassigned object is grey:
    /// colour is never the only cue (the number is in the glyph and the table), but the colours must at least differ.
    /// Mutation: two directions given one hue, or the lightness steps equal - the sets collapse.
    func testDirectionsAndVariantsAreDistinct() {
        let hues = (0..<3).map { VariantPalette.rgb(direction: $0) }
        XCTAssertEqual(Set(hues.map { "\($0.r),\($0.g),\($0.b)" }).count, 3)
        let shades = (0..<4).map { VariantPalette.rgb(direction: 1, rank: $0) }
        XCTAssertEqual(Set(shades.map { "\($0.r),\($0.g),\($0.b)" }).count, 4)
        XCTAssertEqual(shades[0].g, VariantPalette.directionHues[1].g, "rank 0 is the hue itself")
        XCTAssertGreaterThan(shades[2].g, shades[0].g, "rank 2 is lighter")
        XCTAssertLessThan(shades[3].g, shades[0].g, "rank 3 is darker")
    }

    /// A variant's rank is its place among the variants of its direction in the kit's order; four per direction give ranks 0 to 3 each.
    func testTheRankIsThePlaceAmongTheDirectionsVariants() {
        let directions = [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]   // variants 1...12
        XCTAssertEqual((1...12).map { VariantPalette.rank(variant: $0, directions: directions) }, [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3])
        XCTAssertEqual(VariantPalette.rank(variant: 99, directions: directions), 0)
    }

    /// The scheme picks what is drawn: phase leaves it to the report, direction and variant use the palette, no verdict is grey.
    func testTheSchemePicksTheColour() {
        XCTAssertNil(VariantPalette.rgb(scheme: .phase, direction: 0, variant: 1, directions: []))
        let d = VariantPalette.rgb(scheme: .direction, direction: 2, variant: 3, directions: [])!
        XCTAssertEqual(d.r, VariantPalette.directionHues[2].r)
        let grey = VariantPalette.rgb(scheme: .variant, direction: nil, variant: nil, directions: [])!
        XCTAssertEqual(grey.r, VariantPalette.unassigned.r)
    }

    /// The legend's arithmetic: assigned (the direction rows' counted objects) plus unassigned is the counted total.
    func testTheTotalsLineAddsUp() {
        func g(_ kind: PrecipitateObjectReport.VariantGroup.Kind, _ i: Int, _ counted: Int) -> PrecipitateObjectReport.VariantGroup {
            PrecipitateObjectReport.VariantGroup(kind: kind, index: i, totalObjects: counted, countedObjects: counted, arealDensity: nil, detail: nil)
        }
        let groups = [g(.direction, 0, 6), g(.direction, 1, 7), g(.direction, 2, 9), g(.unassigned, 0, 3)]
        XCTAssertEqual(VariantGroupText.totals(groups), "22 assigned + 3 unassigned = 25 counted.")
    }
}

/// The plate presets (theta' and T1 in Al, Thronsen 2024): the variant set, the family of each variant by its plate normal, the planted counts
/// per family, the words. Planted truth from the kit's own variants, no Python reference; validation "none". Same file as `ObjectVariantsTests`
/// so the scene helper is shared.
extension ObjectVariantsTests {
    private func plateSetup(_ preset: OrientationRelationshipPreset) throws -> VariantSetup {
        let precipitate = preset == .t1InAl ? ThronsenReference.t1 : ThronsenReference.thetaPrime
        return try VariantSetup(precipitate: precipitate, matrix: CrystalPresets.aluminum, preset: preset)
    }

    /// `precipitateOrientation(variant:)` for another setup: `M_p = (R_k S delta)^T M_m`.
    private func plateOrientation(_ setup: VariantSetup, variant k: Int, symmetry s: Int) -> simd_double3x3 {
        let a = 0.3 * .pi / 180
        let delta = simd_double3x3(columns: (SIMD3(cos(a), sin(a), 0), SIMD3(-sin(a), cos(a), 0), SIMD3(0, 0, 1)))
        let ops = setup.set.precipitateSymmetry.operators
        return (setup.set.variants[k] * ops[s % ops.count] * delta).transpose * matrixOrientationAl
    }

    private var matrixOrientationAl: simd_double3x3 {
        let n = PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(0, 0, 1), crystal: CrystalPresets.aluminum)!
        return ZoneAxisFrame.matrix(detectorBasis: ZoneAxisFrame.detectorBasis(zoneAxis: n), inPlaneAngle: 0)
    }

    /// The kit's variant counts and the relation itself. Counts = |matrix group| / |matrix operators that leave the relation unchanged up to
    /// the precipitate group|: m-3m has 24 proper rotations. theta' (001)||(001), [100]||[100]: the relation is the identity, every proper
    /// rotation of the tetragonal group about the cube axis stays inside Al's group, so the count is 24 / |precipitate group|; T1 (0001)||(111),
    /// [10-10]||[1-10]: the six operators of 3-fold about [111] and the three 2-folds about <110> in that plane leave it unchanged, 24 / 6 = 4 =
    /// the four plate normals with one in-plane placement each. The numbers asserted are the kit's; the arithmetic is the explanation. The
    /// relation is read back: variant 1's rotation takes the plate normal onto a plate normal and the T1 [2 1 0] / theta' [100] onto the Al
    /// direction the statement names. Mutations: the second statement swapped for a direction 30 degrees off (T1 [1 0 0] || [1 -1 0]), the
    /// first statement changed to (111) || (001) - the read-back direction or the count moves.
    func testThePlatePresetsGiveTheKitsVariantCountsAndTheStatedRelation() throws {
        let theta = try plateSetup(.thetaPrimeInAl), t1 = try plateSetup(.t1InAl)
        XCTAssertEqual(t1.set.precipitateSymmetry.operators.count, 12, "6/mmm proper rotations (D6)")
        XCTAssertEqual(t1.set.variants.count, 4, "24 / 6: four plate normals, one in-plane placement each")
        XCTAssertEqual(t1.habitFamily.sorted(), [0, 1, 2, 3], "every <111> family has exactly one T1 variant")
        let thetaOps = theta.set.precipitateSymmetry.operators.count
        XCTAssertEqual(thetaOps, 8, "4/mmm proper rotations (D4)")
        XCTAssertEqual(theta.set.variants.count, 3, "24 / 8: the three plate normals, one in-plane placement each (the relation is the identity)")
        for f in 0..<3 {
            XCTAssertEqual(theta.habitFamily.filter { $0 == f }.count, theta.set.variants.count / 3, "the same number of variants per cube axis")
        }
        let c = PhaseReferenceLibrary.cartesianZoneAxis(SIMD3(0, 0, 1), crystal: ThronsenReference.t1)!
        let r = t1.set.matrix   // the stated relation itself; the variants are its images under the matrix group
        let normal = simd_normalize(r * c)
        XCTAssertEqual(abs(simd_dot(normal, simd_normalize(SIMD3(1, 1, 1)))), 1, accuracy: 1e-9, "(0001) || (111)")
        let a210 = simd_normalize(LatticeVector.direction(SIMD3(2, 1, 0)).cartesian(in: ThronsenReference.t1))
        XCTAssertEqual(abs(simd_dot(simd_normalize(r * a210), simd_normalize(SIMD3(1, -1, 0)))), 1, accuracy: 1e-9, "[2 1 0] (= [10-10]) || [1 -1 0]")
        let a100 = simd_normalize(LatticeVector.direction(SIMD3(1, 0, 0)).cartesian(in: ThronsenReference.thetaPrime))
        XCTAssertEqual(simd_dot(simd_normalize(theta.set.matrix * a100), SIMD3(1, 0, 0)), 1, accuracy: 1e-9, "theta' [100] || [100]")
    }

    /// The family of each variant is chosen by the plate normal; the preset's names, families and habit are what the legend reads.
    /// Mutation: the families left at the three cube axes for T1 (the fourth family empty, another overfull), or the names of T1 the cube ones.
    func testThePresetsNameTheirFamiliesAndHabit() {
        XCTAssertEqual(OrientationRelationshipPreset.thetaPrimeInAl.rawValue, "theta-prime-in-al")
        XCTAssertEqual(OrientationRelationshipPreset.t1InAl.rawValue, "t1-in-al")
        XCTAssertEqual(OrientationRelationshipPreset.betaDoublePrimeInAl.familyNames, ["[100]", "[010]", "[001]"])
        XCTAssertEqual(OrientationRelationshipPreset.thetaPrimeInAl.familyNames, ["[100]", "[010]", "[001]"])
        XCTAssertEqual(OrientationRelationshipPreset.t1InAl.familyNames, ["[111]", "[-111]", "[1-11]", "[11-1]"])
        XCTAssertEqual(OrientationRelationshipPreset.t1InAl.habitFamilies.count, 4)
        XCTAssertEqual(OrientationRelationshipPreset.betaDoublePrimeInAl.habit, .needle)
        XCTAssertEqual(OrientationRelationshipPreset.t1InAl.habit, .plate)
        XCTAssertEqual(OrientationRelationshipPreset.t1InAl.family(nearest: SIMD3(-1, -1, 1) * 2), 3, "+-n is one family: [-1 -1 1] is the opposite of [1 1 -1]")
        XCTAssertEqual(OrientationRelationshipPreset.thetaPrimeInAl.title, "\u{03B8}\u{2032} in Al, Thronsen 2024")
        XCTAssertEqual(OrientationRelationshipPreset.t1InAl.title, "T1 in Al, Thronsen 2024")
        var settings = VariantSettings(); settings.orientationRelationship = .t1InAl
        XCTAssertEqual(settings.parameters["variant_or"], "t1-in-al")
        XCTAssertEqual(VariantSettings(parameters: settings.parameters), settings)
    }

    /// The planted scene for a plate preset: one object per variant (each through another precipitate operator, 0.3 degrees off). Each is
    /// assigned its variant and the family of its plate normal, the legend's direction groups count them per family with the preset's names,
    /// the CSV carries the names, the plate wording and the face-on line (only when a family lies along the beam), and the report round-trips.
    /// Mutations: a variant counted into the wrong family, a family missing from the groups, the needle wording kept for plates, the face-on
    /// line written for a beam along no family - each moves a planted number or string.
    func testPlantedPlatesAreCountedPerFamilyWithTheirNames() throws {
        for (preset, beam) in [(OrientationRelationshipPreset.thetaPrimeInAl, 2 as Int?), (.t1InAl, nil)] {
            let setup = try plateSetup(preset)
            let n = setup.set.variants.count
            let entries = (0..<n).map { plateOrientation(setup, variant: $0, symmetry: $0) }
            let plan: [(name: String, votes: [(entry: Int, count: Int)])] = (0..<n).map { ("v\($0)", [(entry: $0, count: 9)]) }
            let s = try scene(plan, entries: entries)
            var settings = VariantSettings(); settings.orientationRelationship = preset
            let run = ObjectVariantAssigner.run(objects: s.objects, results: s.results, orientations: s.orientations, precipitatePhaseIndex: 1,
                                                setup: setup, settings: settings)
            for k in 0..<n {
                let a = try XCTUnwrap(run.perObject[try XCTUnwrap(s.idAt["v\(k)"])])
                XCTAssertEqual(a.variant, k + 1, "\(preset) plate \(k)")
                XCTAssertEqual(a.direction, setup.habitFamily[k])
                XCTAssertEqual(a.directionName, preset.familyNames[setup.habitFamily[k]])
            }
            let report = PrecipitateObjectReport.make(objects: s.objects, phaseNames: ["Al", "plate"], matrixPhaseIndex: 0, pixelSize: 1, pixelUnit: "nm",
                                                      minimumAreaPx: 1, variantJoin: run, variantSettings: settings, endOnDirection: beam,
                                                      variantDirections: setup.habitFamily)
            let groups = try XCTUnwrap(report.variantGroups)
            let directionGroups = groups.filter { $0.kind == .direction }
            XCTAssertEqual(directionGroups.map(\.title), preset.familyNames)
            XCTAssertEqual(directionGroups.map(\.totalObjects), preset.familyNames.indices.map { f in setup.habitFamily.filter { $0 == f }.count })
            XCTAssertTrue(directionGroups.allSatisfy { $0.totalObjects > 0 }, "every family is used")
            XCTAssertEqual(groups.filter { $0.kind == .variant }.count, n)
            XCTAssertEqual(report.variantHabit, .plate)
            let csv = report.csv()
            XCTAssertTrue(csv.contains("plate normals are matrix directions"))
            XCTAssertFalse(csv.contains("end-on"))
            for name in preset.familyNames { XCTAssertTrue(csv.contains("# direction \(name): "), name) }
            XCTAssertEqual(report.rows.filter { $0.variant?.isAssigned == true }.map(\.directionText).sorted(),
                           setup.habitFamily.map { preset.familyNames[$0] }.sorted())
            if beam != nil { XCTAssertTrue(csv.contains("# face-on: plates on [001] lie face-on to the beam")) }
            else { XCTAssertFalse(csv.contains("face-on")) }
            XCTAssertEqual(try JSONDecoder().decode(PrecipitateObjectReport.self, from: JSONEncoder().encode(report)), report)
        }
    }

    /// Which family lies along the beam: Al [001] along theta' plate normals names [001] (face-on), along T1's <111> plates names none, an
    /// Al <111> beam names its T1 family; a tilt of a degree names none. Mutation: the nearest family returned without the tolerance
    /// (T1 along [001] would name a family), or the beam sign mattering.
    func testTheFaceOnFamilyIsTheOneAlongTheBeam() {
        let theta = OrientationRelationshipPreset.thetaPrimeInAl, t1 = OrientationRelationshipPreset.t1InAl
        XCTAssertEqual(theta.family(alongBeam: SIMD3(0, 0, 1)), 2)
        XCTAssertEqual(theta.family(alongBeam: SIMD3(0, 0, -1)), 2)
        XCTAssertNil(t1.family(alongBeam: SIMD3(0, 0, 1)))
        XCTAssertEqual(t1.family(alongBeam: SIMD3(1, 1, 1)), 0)
        XCTAssertEqual(t1.family(alongBeam: SIMD3(1, -1, -1)), 1, "[1 -1 -1] is the opposite of [-1 1 1]")
        XCTAssertNil(theta.family(alongBeam: SIMD3(sin(1 * .pi / 180), 0, cos(1 * .pi / 180))))
    }
}
