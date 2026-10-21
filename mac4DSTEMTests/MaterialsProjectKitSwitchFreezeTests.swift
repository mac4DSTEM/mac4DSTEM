//
//  MaterialsProjectKitSwitchFreezeTests.swift
//  Tier 1 (a model's identity and numbers): the Materials Project import pinned across the switch from the app's own
//  `MaterialsProjectImport` (Core/Crystal) to DiffractoKit 0.7.1's (`structure(from:)`, `request`, `decode`, `check`). The
//  expectations were RECORDED from the app's own pre-switch code on 2026-10-21: for each served document the model's id, name,
//  symmetry, space group, revisionID, contentFingerprint, provenance, cell and site bit patterns, and the FNV digest of its kept
//  kinematic reflections at kMax 1.0; for each refusal the exact message; for each expectation the verdict. They must be equal
//  after it, except where a DEVIATION is written below.
//

import XCTest
import simd
import DiffractoCore
import DiffractoScattering
import DSTEMCore
@testable import mac4DSTEM

final class MaterialsProjectKitSwitchFreezeTests: XCTestCase {

    // MARK: Digest

    private static func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        return String(format: "%016llx", hash)
    }

    private static func bits(_ v: Double) -> String { String(v.bitPattern, radix: 16) }

    /// Everything a scientist or a session file reads from the model. `sortedSites`: the atoms as a multiset (a disordered
    /// centred cell, where the kit orders the atoms of one site species-major; see DEVIATION).
    private static func describe(_ model: CrystalModel, sortedSites: Bool = false) -> String {
        var lines = [model.id, model.displayName, model.symmetry.rawValue, String(describing: model.spaceGroupNumber)]
        if !sortedSites { lines.append(model.contentFingerprint) }     // it digests the atoms in order
        let c = model.structure.cell
        lines.append([c.a, c.b, c.c, c.alphaDeg, c.betaDeg, c.gammaDeg].map(bits).joined(separator: ","))
        var sites = model.structure.sites.map {
            "\($0.z):\(bits($0.fractional.x)),\(bits($0.fractional.y)),\(bits($0.fractional.z)):\(bits($0.occupancy))"
        }
        if sortedSites { sites.sort() } else { lines.append(model.revisionID) }
        lines += sites
        lines += model.provenance.sorted { $0.key < $1.key }
            .filter { !(sortedSites && ($0.key == "atomic_basis")) }.map { "\($0.key)=\($0.value)" }
        if let kept = try? model.structure.kinematicReflections(kMax: 1.0, retainingAll: false).kept {
            // Sorted atoms: the structure factor sums its atoms in another order, so the intensity is compared to 9 digits.
            var list = kept.map {
                sortedSites ? String(format: "%d,%d,%d,%.9e,%.9e", $0.h, $0.k, $0.l, $0.gLength, $0.intensity)
                    : "\($0.h),\($0.k),\($0.l),\(bits($0.gLength)),\(bits($0.intensity))"
            }
            list.sort()
            lines.append("reflections=\(list.count):\(fnv(list.joined(separator: ";")))")
        }
        return fnv(lines.joined(separator: "\n"))
    }

    private let fetched = Date(timeIntervalSince1970: 1_700_000_000)

    private func outcome(_ doc: MaterialsProjectDocument, sortedSites: Bool = false) -> String {
        do { return Self.describe(try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: fetched), sortedSites: sortedSites) }
        catch { return "ERR \(error.localizedDescription)" }
    }

    // MARK: Documents

    private func site(_ element: String, _ abc: [Double], label: String? = nil, occu: Double = 1) -> MaterialsProjectSite {
        MaterialsProjectSite(label: label, species: [MaterialsProjectSpecies(element: element, occu: occu)], abc: abc)
    }

    private func params(_ rows: [SIMD3<Double>]) -> (Double, Double, Double, Double, Double, Double) {
        func angle(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> Double {
            acos(min(1, max(-1, dot(u, v) / (length(u) * length(v))))) * 180 / .pi
        }
        return (length(rows[0]), length(rows[1]), length(rows[2]),
                angle(rows[1], rows[2]), angle(rows[0], rows[2]), angle(rows[0], rows[1]))
    }

    private func primitive(_ id: String, _ formula: String, rows: [SIMD3<Double>], sites: [MaterialsProjectSite],
                           system: String?, symbol: String?, number: Int?) -> MaterialsProjectDocument {
        let p = params(rows)
        return MaterialsProjectDocument(
            materialID: id, formulaPretty: formula,
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(a: p.0, b: p.1, c: p.2, alpha: p.3, beta: p.4, gamma: p.5,
                                                 matrix: rows.map { [$0.x, $0.y, $0.z] }),
                sites: sites),
            symmetry: MaterialsProjectSymmetry(crystalSystem: system, symbol: symbol, number: number))
    }

    private func conventional(_ id: String, _ formula: String, a: Double, b: Double, c: Double,
                              alpha: Double = 90, beta: Double = 90, gamma: Double = 90,
                              sites: [MaterialsProjectSite], system: String?, symbol: String?, number: Int?,
                              matrix: Bool = false, deprecated: Bool? = nil) -> MaterialsProjectDocument {
        MaterialsProjectDocument(
            materialID: id, formulaPretty: formula, deprecated: deprecated,
            structure: MaterialsProjectStructure(
                lattice: MaterialsProjectLattice(a: a, b: b, c: c, alpha: alpha, beta: beta, gamma: gamma), sites: sites),
            symmetry: symbol == nil && system == nil ? nil
                : MaterialsProjectSymmetry(crystalSystem: system, symbol: symbol, number: number))
    }

    private func fccPrimitive(_ a: Double) -> [SIMD3<Double>] {
        let h = a / 2
        return [SIMD3(0, h, h), SIMD3(h, 0, h), SIMD3(h, h, 0)]
    }

    private var documents: [(String, MaterialsProjectDocument)] {
        let h = 5.431 / 2
        let bccRows = { (a: Double) in [SIMD3(-a / 2, a / 2, a / 2), SIMD3(a / 2, -a / 2, a / 2), SIMD3(a / 2, a / 2, -a / 2)] }
        let hexA = 4.1, hexC = 14.2
        let rhombo = [SIMD3(hexA / 2, hexA / (2 * 3.0.squareRoot()), hexC / 3),
                      SIMD3(-hexA / 2, hexA / (2 * 3.0.squareRoot()), hexC / 3),
                      SIMD3(0, -hexA / 3.0.squareRoot(), hexC / 3)]
        let mixed = [MaterialsProjectSpecies(element: "Si", occu: 0.5), MaterialsProjectSpecies(element: "Ge", occu: 0.5)]
        var list: [(String, MaterialsProjectDocument)] = []
        list.append(("si-conventional-labelled", conventional(
            "mp-149", "Si", a: 5.431, b: 5.431, c: 5.431,
            sites: [site("Si", [0, 0, 0], label: "Si1"), site("Si", [0.5, 0.5, 0], label: "Si2"),
                    site("Si", [0.5, 0, 0.5], label: "Si3"), site("Si", [0, 0.5, 0.5], label: "Si4"),
                    site("Si", [0.25, 0.25, 0.25], label: "Si5"), site("Si", [0.75, 0.75, 0.25], label: "Si6"),
                    site("Si", [0.75, 0.25, 0.75], label: "Si7"), site("Si", [0.25, 0.75, 0.75], label: "Si8")],
            system: "cubic", symbol: "Fd-3m", number: 227, deprecated: false)))
        list.append(("al-conventional-fm3m-served-conventional", conventional(
            "mp-134", "Al", a: 4.05, b: 4.05, c: 4.05,
            sites: [site("Al", [0, 0, 0]), site("Al", [0, 0.5, 0.5]), site("Al", [0.5, 0, 0.5]), site("Al", [0.5, 0.5, 0])],
            system: "Cubic", symbol: "Fm-3m", number: 225)))
        list.append(("mg-hexagonal", conventional(
            "mp-153", "Mg", a: 3.209, b: 3.209, c: 5.211, gamma: 120,
            sites: [site("Mg", [0, 0, 0]), site("Mg", [0.6666666667, 0.3333333333, 0.5])],
            system: "hexagonal", symbol: "P6_3/mmc", number: 194)))
        list.append(("monoclinic-no-symmetry-block", conventional(
            "mp-999001", "AlO", a: 6.0, b: 4.0, c: 5.0, beta: 100,
            sites: [site("Al", [0, 0, 0]), site("O", [0.5, 0.5, 0.5])], system: nil, symbol: nil, number: nil)))
        list.append(("si-f-primitive", primitive(
            "mp-149", "Si", rows: fccPrimitive(5.431),
            sites: [site("Si", [0, 0, 0], label: "Si1"), site("Si", [0.25, 0.25, 0.25], label: "Si2")],
            system: "cubic", symbol: "Fd-3m", number: 227)))
        list.append(("au-f-primitive-no-matrix", {
            var d = primitive("mp-81", "Au", rows: fccPrimitive(4.0782), sites: [site("Au", [0, 0, 0])],
                              system: "cubic", symbol: "Fm-3m", number: 225)
            let l = d.structure!.lattice!
            d = MaterialsProjectDocument(materialID: d.materialID, formulaPretty: d.formulaPretty,
                                         structure: MaterialsProjectStructure(
                                            lattice: MaterialsProjectLattice(a: l.a, b: l.b, c: l.c, alpha: l.alpha, beta: l.beta, gamma: l.gamma),
                                            sites: d.structure!.sites), symmetry: d.symmetry)
            return d
        }()))
        list.append(("w-i-primitive", primitive(
            "mp-91", "W", rows: bccRows(3.165), sites: [site("W", [0, 0, 0], label: "W1")],
            system: "cubic", symbol: "Im-3m", number: 229)))
        list.append(("bi2te3-like-r-primitive", primitive(
            "mp-34202", "Bi2Te3", rows: rhombo,
            sites: [site("Te", [0, 0, 0]), site("Bi", [0.4, 0.4, 0.4]), site("Bi", [0.6, 0.6, 0.6]),
                    site("Te", [0.2, 0.2, 0.2]), site("Te", [0.8, 0.8, 0.8])],
            system: "trigonal", symbol: "R-3m", number: 166)))
        list.append(("tetragonal-i-primitive", primitive(
            "mp-1", "Ti", rows: [SIMD3(-2.0, 2.0, 3.0), SIMD3(2.0, -2.0, 3.0), SIMD3(2.0, 2.0, -3.0)],
            sites: [site("Ti", [0, 0, 0])], system: "tetragonal", symbol: "I4/mmm", number: 139)))
        list.append(("orthorhombic-c-primitive", primitive(
            "mp-2", "FeS", rows: [SIMD3(2.0, -3.0, 0), SIMD3(2.0, 3.0, 0), SIMD3(0, 0, 5.0)],
            sites: [site("Fe", [0, 0, 0]), site("S", [0.3, 0.3, 0.25])], system: "orthorhombic", symbol: "Cmcm", number: 63)))
        list.append(("si-ge-disordered-f-primitive", primitive(
            "mp-3", "SiGe", rows: fccPrimitive(5.431),
            sites: [MaterialsProjectSite(label: "mixed", species: mixed, abc: [0, 0, 0]), site("Si", [0.25, 0.25, 0.25], label: "pure")],
            system: "cubic", symbol: "Fd-3m", number: 227)))
        list.append(("si-ge-disordered-conventional", conventional(
            "mp-4", "SiGe", a: 5.431, b: 5.431, c: 5.431,
            sites: [MaterialsProjectSite(label: "mixed", species: mixed, abc: [0, 0, 0]),
                    MaterialsProjectSite(label: "mixed2", species: mixed, abc: [0.5, 0.5, 0]),
                    MaterialsProjectSite(label: "mixed3", species: mixed, abc: [0.5, 0, 0.5]),
                    MaterialsProjectSite(label: "mixed4", species: mixed, abc: [0, 0.5, 0.5])],
            system: "cubic", symbol: "Fm-3m", number: 225)))
        return list
    }

    private var refusals: [(String, MaterialsProjectDocument)] {
        let ok = [site("Al", [0, 0, 0])]
        let cubicLattice = MaterialsProjectLattice(a: 4, b: 4, c: 4, alpha: 90, beta: 90, gamma: 90)
        let fPrimitive = fccPrimitive(4.0)
        let p = params(fPrimitive)
        let fLattice = MaterialsProjectLattice(a: p.0, b: p.1, c: p.2, alpha: p.3, beta: p.4, gamma: p.5,
                                               matrix: fPrimitive.map { [$0.x, $0.y, $0.z] })
        func doc(_ structure: MaterialsProjectStructure?, symmetry: MaterialsProjectSymmetry? = nil) -> MaterialsProjectDocument {
            MaterialsProjectDocument(materialID: "mp-7", formulaPretty: "Al", structure: structure, symmetry: symmetry)
        }
        let fSym = MaterialsProjectSymmetry(crystalSystem: "cubic", symbol: "Fm-3m", number: 225)
        return [
            ("no-structure", doc(nil)),
            ("no-lattice", doc(MaterialsProjectStructure(lattice: nil, sites: ok))),
            ("no-sites", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: nil))),
            ("empty-sites", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: []))),
            ("site-no-abc", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Al", occu: 1)], abc: nil)]))),
            ("site-short-abc", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [site("Al", [0, 0])]))),
            ("site-no-species", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [MaterialsProjectSite(species: nil, abc: [0, 0, 0])]))),
            ("site-empty-species", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [MaterialsProjectSite(species: [], abc: [0, 0, 0])]))),
            ("unknown-element", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [site("Xx", [0, 0, 0])]))),
            ("nan-lattice", doc(MaterialsProjectStructure(lattice: MaterialsProjectLattice(a: .nan, b: 4, c: 4, alpha: 90, beta: 90, gamma: 90), sites: ok))),
            ("bad-occupancy", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [site("Al", [0, 0, 0], occu: 1.5)]))),
            ("atoms-too-close", doc(MaterialsProjectStructure(lattice: cubicLattice, sites: [site("Al", [0, 0, 0]), site("Al", [0.0001, 0, 0])]))),
            ("centred-wrong-metric", doc(MaterialsProjectStructure(lattice: MaterialsProjectLattice(a: 3, b: 4, c: 5, alpha: 70, beta: 80, gamma: 85), sites: ok),
                                         symmetry: fSym)),
            ("centred-site-no-abc", doc(MaterialsProjectStructure(lattice: fLattice, sites: [site("Al", [0, 0, 0]), MaterialsProjectSite(species: [MaterialsProjectSpecies(element: "Al", occu: 1)], abc: nil)]), symmetry: fSym)),
            ("centred-unknown-element", doc(MaterialsProjectStructure(lattice: fLattice, sites: [site("Xx", [0, 0, 0])]), symmetry: fSym)),
            ("centred-no-species", doc(MaterialsProjectStructure(lattice: fLattice, sites: [MaterialsProjectSite(species: nil, abc: [0, 0, 0])]), symmetry: fSym)),
            ("centred-coincident-sites", doc(MaterialsProjectStructure(lattice: fLattice, sites: [site("Al", [0, 0, 0]), site("Al", [0, 0, 0])]), symmetry: fSym)),
        ]
    }

    // Recorded from the pre-switch code, 2026-10-21.
    private static let documentDigests: [String: String] = [
        "al-conventional-fm3m-served-conventional": "22c914dbd082517d",
        "au-f-primitive-no-matrix": "0b2452064e68c476",
        "bi2te3-like-r-primitive": "a99bb9a1ddba4a28",
        "mg-hexagonal": "67a9dbc0279cca02",
        "monoclinic-no-symmetry-block": "71e237e400e3a24c",
        "orthorhombic-c-primitive": "04cdea83a65a1eef",
        "si-conventional-labelled": "fc0d0fa8e56715c4",
        "si-f-primitive": "eb1209b62fa6cb53",
        "si-ge-disordered-conventional": "90487e944831db4e",
        "tetragonal-i-primitive": "be5e188c94833709",
        "w-i-primitive": "73382cd0cacc332a",
    ]
    private static let refusalMessages: [String: String] = [
        "atoms-too-close": "ERR Materials Project response could not be used: mp-7 failed validation: Two fully-occupied atomic sites are 0.0004 Å apart — closer than any real interatomic distance, so the cell holds more atoms than the structure has.",
        "bad-occupancy": "ERR Materials Project response could not be used: mp-7 failed validation: Atomic occupancies must be finite and in (0, 1].",
        "centred-coincident-sites": "ERR Materials Project cell could not be safely standardised: mp-7: two sites of Z=13 landed on each other after the conversion; the served sites are not this centring's asymmetric unit. Import a conventional CIF for this phase instead.",
        "centred-no-species": "ERR Materials Project response could not be used: Site 0 of mp-7 lists no species.",
        // DEVIATION (DiffractoKit structure(from:)): the former adapter refused this unnamed ("a site has no usable fractional
        // coordinates to standardise."); the kit names the site, as it does for an uncentred cell.
        "centred-site-no-abc": "ERR Materials Project response could not be used: Site 1 of mp-7 has no usable fractional coordinates.",
        "centred-unknown-element": "ERR Materials Project response could not be used: Site 0 of mp-7 has an unrecognized element symbol \"Xx\".",
        "centred-wrong-metric": "ERR Materials Project cell could not be safely standardised: mp-7: converting as F-centred did not give a conventional cubic cell (a=7.508636532492104, b=6.279880713121656, c=5.762073130645699, α=120.41523057580362°, β=107.19536069103795°, γ=87.45750594682568°). Import a conventional CIF for this phase instead.",
        "empty-sites": "ERR Materials Project response could not be used: mp-7's structure lists no atomic sites.",
        "nan-lattice": "ERR Materials Project response could not be used: mp-7 failed validation: Cell lengths must be finite and positive.; The lattice vectors do not form a finite positive-volume cell.",
        "no-lattice": "ERR Materials Project response could not be used: mp-7's structure has no lattice.",
        "no-sites": "ERR Materials Project response could not be used: mp-7's structure lists no atomic sites.",
        "no-structure": "ERR Materials Project response could not be used: mp-7 has no structure block.",
        "site-empty-species": "ERR Materials Project response could not be used: Site 0 of mp-7 lists no species.",
        "site-no-abc": "ERR Materials Project response could not be used: Site 0 of mp-7 has no usable fractional coordinates.",
        "site-no-species": "ERR Materials Project response could not be used: Site 0 of mp-7 lists no species.",
        "site-short-abc": "ERR Materials Project response could not be used: Site 0 of mp-7 has no usable fractional coordinates.",
        "unknown-element": "ERR Materials Project response could not be used: Site 0 of mp-7 has an unrecognized element symbol \"Xx\".",
    ]
    private static let disorderedSortedDigest = "baddc0eebd22d5d8"

    func testServedDocumentsAreEqualToTheRecording() throws {
        for (key, doc) in documents where !key.contains("disordered-f") {
            XCTAssertEqual(outcome(doc), Self.documentDigests[key], key)
        }
    }

    /// DEVIATION (DiffractoKit `MaterialsProjectImport.structure(from:)`): a disordered site of a centred primitive cell
    /// leaves the kit one atom per species, species-major then centring translation; the app's former adapter made it
    /// site-major (all species of a site together, then the next translation). Same atoms, same positions, same
    /// occupancies; the order of `structure.sites` (so `revisionID` and `atomic_basis`) differs for that case only. The
    /// atoms are compared as a multiset here.
    func testDisorderedCentredDocumentHasTheSameAtomsInTheKitsOrder() throws {
        let doc = try XCTUnwrap(documents.first { $0.0 == "si-ge-disordered-f-primitive" }).1
        XCTAssertEqual(outcome(doc, sortedSites: true), Self.disorderedSortedDigest)
    }

    func testDisorderedConventionalDocumentKeepsItsOrder() throws {
        let doc = try XCTUnwrap(documents.first { $0.0 == "si-ge-disordered-conventional" }).1
        XCTAssertEqual(outcome(doc), Self.documentDigests["si-ge-disordered-conventional"])
    }

    func testRefusalsKeepTheirMessages() throws {
        for (key, doc) in refusals {
            XCTAssertEqual(outcome(doc), Self.refusalMessages[key], key)
        }
    }

    func testRequestAndDecodeAndFirstDocument() throws {
        let request = try MaterialsProjectImport.request(materialID: "mp-149", apiKey: "TEST-KEY")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.materialsproject.org/materials/summary/?material_ids=mp-149&_fields=material_id,formula_pretty,structure,symmetry,deprecated,last_updated")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "TEST-KEY")
        for bad in ["", "mp-", "mp-12a", "MP-1", "149", "mp-1 "] {
            XCTAssertThrowsError(try MaterialsProjectImport.request(materialID: bad, apiKey: "k"), bad) { error in
                XCTAssertEqual(error as? MaterialsProjectImport.Failure, .invalidMaterialID(bad))
            }
        }
        let withErrors = try MaterialsProjectImport.decode(Data(#"{"data": [], "errors": [{"code": 403, "message": "no"}]}"#.utf8))
        XCTAssertThrowsError(try MaterialsProjectImport.firstDocument(in: withErrors)) {
            XCTAssertEqual($0 as? MaterialsProjectImport.Failure, .apiError(code: 403, message: "no"))
        }
        let empty = try MaterialsProjectImport.decode(Data(#"{"data": []}"#.utf8))
        XCTAssertThrowsError(try MaterialsProjectImport.firstDocument(in: empty)) {
            XCTAssertEqual($0 as? MaterialsProjectImport.Failure, .emptyResult("the response's data array was empty."))
        }
        let one = try MaterialsProjectImport.decode(Data(#"{"data": [{"material_id": "mp-1", "extra": 1}], "meta": {}}"#.utf8))
        XCTAssertEqual(try MaterialsProjectImport.firstDocument(in: one).materialID, "mp-1")
        XCTAssertThrowsError(try MaterialsProjectImport.decode(Data("[]".utf8)))
    }

    func testCheckVerdicts() {
        let doc = MaterialsProjectDocument(materialID: "mp-1185307", formulaPretty: "Al2CuLi",
                                           symmetry: MaterialsProjectSymmetry(symbol: "Pm-3m", number: 221))
        let noFormula = MaterialsProjectDocument(materialID: "mp-9")
        let cases: [(MaterialsProjectDocument, PhaseExpectation, PhaseExpectationVerdict)] = [
            (doc, PhaseExpectation(), .unchecked),
            (doc, PhaseExpectation(formula: "LiAl2Cu"), .matches),
            (doc, PhaseExpectation(formula: "LiAl2Cu", spaceGroupNumber: 221), .matches),
            (doc, PhaseExpectation(formula: "AlCu"), .mismatch(reason: "mp-1185307 is Al2CuLi; expected AlCu.")),
            (doc, PhaseExpectation(formula: "al2"), .mismatch(reason: "Could not parse expected formula \"al2\".")),
            (doc, PhaseExpectation(spaceGroupNumber: 225),
             .mismatch(reason: "mp-1185307 is Al2CuLi in Pm-3m (221); expected space group 225.")),
            (noFormula, PhaseExpectation(formula: "Al"),
             .mismatch(reason: "mp-9 has no usable formula to compare against \"Al\".")),
            (noFormula, PhaseExpectation(spaceGroupNumber: 1),
             .mismatch(reason: "mp-9 is mp-9 in an unrecorded space group; expected space group 1.")),
        ]
        for (d, e, want) in cases { XCTAssertEqual(MaterialsProjectImport.check(d, against: e), want, "\(e)") }
    }
}
