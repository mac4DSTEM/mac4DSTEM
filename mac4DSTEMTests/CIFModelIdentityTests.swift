import XCTest
import DiffractoCore
import DSTEMCore
@testable import mac4DSTEM

func rdCIF(_ name: String, _ cell: [Double], _ ops: [String], _ atoms: [(String, Double, Double, Double)]) -> String {
    var s = "data_\(name)\n_cell_length_a \(cell[0])\n_cell_length_b \(cell[1])\n_cell_length_c \(cell[2])\n_cell_angle_alpha \(cell[3])\n_cell_angle_beta \(cell[4])\n_cell_angle_gamma \(cell[5])\n"
    if !ops.isEmpty { s += "loop_\n_symmetry_equiv_pos_as_xyz\n" + ops.map { "'\($0)'" }.joined(separator: "\n") + "\n" }
    s += "loop_\n_atom_site_label\n_atom_site_type_symbol\n_atom_site_fract_x\n_atom_site_fract_y\n_atom_site_fract_z\n"
    for (i, a) in atoms.enumerated() { s += "\(a.0)\(i) \(a.0) \(a.1) \(a.2) \(a.3)\n" }
    return s
}
let rdP63mmc = ["x,y,z", "-y,x-y,z", "-x+y,-x,z", "-x,-y,z+1/2", "y,-x+y,z+1/2", "x-y,x,z+1/2", "-x+y,y,z", "x,x-y,z", "y,x,z+1/2", "x-y,-y,z+1/2", "-x,-x+y,z+1/2", "-y,-x,z", "-x,-y,-z", "y,-x+y,-z", "x-y,x,-z", "x,y,-z+1/2", "-y,x-y,-z+1/2", "-x+y,-x,-z+1/2", "x-y,-y,-z", "-x,-x+y,-z", "-y,-x,-z+1/2", "-x+y,y,-z+1/2", "x,x-y,-z+1/2", "y,x,-z"]
let rdFcc = ["x,y,z", "x+1/2,y+1/2,z", "x+1/2,y,z+1/2", "x,y+1/2,z+1/2"]
func rdFPCases() -> [(String, String)] {
    let t = 1.0 / 3, u = 2.0 / 3
    return [
        ("mg24", rdCIF("mg24", [3.2094, 3.2094, 5.2108, 90, 90, 120], rdP63mmc, [("Mg", t, u, 0.25)])),
        ("nias", rdCIF("nias", [3.62, 3.62, 5.03, 90, 90, 120], rdP63mmc, [("Ni", 0, 0, 0), ("As", t, u, 0.25)])),
        ("nias_rev", rdCIF("nias_rev", [3.62, 3.62, 5.03, 90, 90, 120], rdP63mmc, [("As", t, u, 0.25), ("Ni", 0, 0, 0)])),
        ("nacl", rdCIF("nacl", [5.64, 5.64, 5.64, 90, 90, 90], rdFcc, [("Cl", 0.5, 0.5, 0.5), ("Na", 0, 0, 0)])),
        ("sidia", rdCIF("sidia", [5.4309, 5.4309, 5.4309, 90, 90, 90], rdFcc, [("Si", 0.25, 0.25, 0.25), ("Si", 0, 0, 0)])),
        ("monob", rdCIF("monob", [5, 6, 7, 90, 100, 90], ["x,y,z", "-x,y,-z", "-x,-y,-z", "x,-y,z"], [("Si", 0.1, 0.2, 0.3), ("O", 0.4, 0.0, 0.7)])),
        ("p1scr", rdCIF("p1scr", [4.0495, 4.0495, 4.0495, 90, 90, 90], [], [("Al", 0, 0.5, 0.5), ("Al", 0.5, 0, 0.5), ("Al", 0, 0, 0), ("Al", 0.5, 0.5, 0)])),
        ("mgo333", rdCIF("mgo333", [3.2094, 3.2094, 5.2108, 90, 90, 120], ["x,y,z", "-x,-y,z+1/2", "-y,x-y,z", "y,-x+y,z+1/2", "-x+y,-x,z", "x-y,x,z+1/2"], [("Mg", 0, 0, 0.0), ("O", 0.333, 0.667, 0.25)])),
    ]
}


/// Refuter D, P3 (and the site ORDER behind it) on CIFs the lane did not use: P6_3/mmc with a 24-operation loop, NiAs written in
/// both atom orders, NaCl and diamond Si with centring-only loops and the atoms listed in reverse, a b-unique monoclinic with a
/// general position, a scrambled P1 fcc, magnesium written with 0.333. Expected strings are 7f192da9's own `CIFImport.crystalModel`
/// (compiled standalone through its tools manifest): symmetry, site count, contentFingerprint, FNV-1a of revisionID, of the site
/// list (z and the bit patterns of the fractional coordinates, in order) and of the sorted provenance.
final class CIFModelIdentityTests: XCTestCase {
    private static func fnv(_ bytes: [UInt8]) -> UInt64 { var h: UInt64 = 0xcbf29ce484222325; for b in bytes { h ^= UInt64(b); h = h &* 0x100000001b3 }; return h }
    private static let old: [String: String] = [
        "mg24": "hexagonal 2 fp 6ef52ca6b968eb4e rev 3a8a3849f7cbe3d6 sites b9dd96cefb395578 prov 5e65271463940e86",
        "nias": "hexagonal 4 fp e6f150c56cb77005 rev dc4195ccc9bd15be sites d02553e3db76c27f prov 1d27bea5bc6a300f",
        "nias_rev": "hexagonal 4 fp 3eaf288dc1d8ec3f rev 0fd3b09ba1d31576 sites 45f09b06412c9a1b prov c8e057cb54cfcd49",
        "nacl": "cubic 8 fp 470dc9212ac7621d rev ccdbd0fc33e04d19 sites bd67e66db89fa580 prov f4906a7ef5735562",
        "sidia": "cubic 8 fp 135db76bcc528cdd rev b7ef98f7973578f5 sites 6fd5ee3a05ec94c8 prov 2316d9f830b7d1a0",
        "monob": "monoclinic 6 fp 948a841a16b43437 rev 95d4be21ccd9777e sites 124037fb150e56af prov 5c079ae880b6a1b2",
        "p1scr": "cubic 4 fp 4a616d3e96aaf4ea rev bb636f9bdd047183 sites bfb921fd88c2acc4 prov 207130c2eb4bdf04",
        "mgo333": "hexagonal 4 fp 8ee7790a0f6b0fa1 rev 9921298469011ae3 sites 7c1402f6ba708b54 prov bce69c8776085645"
    ]
    func testImportedModelIdentityAndSiteOrderAreByteEqualToThePreSwitchImporter() throws {
        var bad: [String] = []
        for (name, text) in rdFPCases() {
            let line: String
            do {
                let m = try CIFModelImport.crystalModel(from: text, fileBaseName: name)
                let sites = m.structure.sites.map { "\($0.z):\($0.fractional.x.bitPattern),\($0.fractional.y.bitPattern),\($0.fractional.z.bitPattern):\($0.occupancy)" }.joined(separator: ";")
                let prov = m.provenance.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                line = "\(m.symmetry.rawValue) \(m.structure.sites.count) fp \(m.contentFingerprint) rev \(String(format: "%016llx", Self.fnv(Array(m.revisionID.utf8)))) sites \(String(format: "%016llx", Self.fnv(Array(sites.utf8)))) prov \(String(format: "%016llx", Self.fnv(Array(prov.utf8))))"
            } catch { line = "REFUSED \(error)" }
            if Self.old[name] != line { bad.append("\(name)\n  old \(Self.old[name] ?? "?")\n  new \(line)") }
        }
        XCTAssertEqual(bad, [], "models whose identity differs from the pre-switch importer's")
    }
}
