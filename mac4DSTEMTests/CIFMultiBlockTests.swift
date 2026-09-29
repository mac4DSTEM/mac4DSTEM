import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// D006 — a multi-`data_` CIF was merged into one crystal (cell values
/// last-wins, atom sites and symmetry operations concatenated across blocks).
/// Decided 2026-09-29: refuse, naming the blocks. Pre-registration: session
/// scratchpad `a/d006-prereg.md`.
final class CIFMultiBlockTests: XCTestCase {

    private let header = """
    _cell_length_a 4.0782
    _cell_length_b 4.0782
    _cell_length_c 4.0782
    _cell_angle_alpha 90
    _cell_angle_beta 90
    _cell_angle_gamma 90
    """
    private let loopHeader = """
    loop_
    _atom_site_label
    _atom_site_type_symbol
    _atom_site_fract_x
    _atom_site_fract_y
    _atom_site_fract_z
    """
    private var goldBlock: String {
        """
        data_gold
        \(header)
        \(loopHeader)
        Au1 Au 0.0 0.0 0.0
        Au2 Au 0.5 0.5 0.0
        Au3 Au 0.5 0.0 0.5
        Au4 Au 0.0 0.5 0.5
        """
    }
    private var siliconBlock: String {
        """
        data_silicon
        _cell_length_a 5.4309
        _cell_length_b 5.4309
        _cell_length_c 5.4309
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        \(loopHeader)
        Si1 Si 0.0  0.0  0.0
        Si2 Si 0.5  0.5  0.0
        Si3 Si 0.5  0.0  0.5
        Si4 Si 0.0  0.5  0.5
        Si5 Si 0.25 0.25 0.25
        Si6 Si 0.75 0.75 0.25
        Si7 Si 0.75 0.25 0.75
        Si8 Si 0.25 0.75 0.75
        """
    }

    func testTwoStructureBlocksAreRefusedByName() {
        let cif = goldBlock + "\n" + siliconBlock
        XCTAssertThrowsError(try CIFImport.crystalModel(from: cif, fileBaseName: "two")) { error in
            XCTAssertEqual(error as? CIFImportError,
                           .multipleStructures(blockNames: ["gold", "silicon"]))
            let text = (error as? CIFImportError)?.errorDescription ?? ""
            XCTAssertTrue(text.contains("This CIF holds 2 structures (gold, silicon); import one at a time"), text)
        }
    }

    func testASingleBlockStillImportsUnchanged() throws {
        let model = try CIFImport.crystalModel(from: goldBlock, fileBaseName: "gold")
        XCTAssertEqual(model.crystal.sites.count, 4)
        XCTAssertEqual(model.crystal.a, 4.0782, accuracy: 1e-9)
    }

    /// A journal-only block (`data_global`, as Acta Cryst. CIFs carry) defines
    /// no structure; refusing it would refuse files that hold one crystal.
    func testAJournalOnlyGlobalBlockDoesNotCount() throws {
        let cif = "data_global\n_journal_name_full 'Some Journal'\n_publ_section_title 'A title'\n\n" + goldBlock
        let model = try CIFImport.crystalModel(from: cif, fileBaseName: "gold")
        XCTAssertEqual(model.crystal.sites.count, 4)
    }

    /// Every reference CIF the repo ships with (gitignored `References/`, so
    /// skipped where it is absent) is a single block and must keep importing
    /// — the refusal must not reach any of them. Symmetry-family refusals for
    /// non-cubic/hexagonal files are a different, pre-existing verdict.
    func testNoReferenceCIFIsRefusedAsMultiBlock() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("References/crystal-structures")
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "cif" } ?? []
        try XCTSkipIf(files.isEmpty, "References/crystal-structures is absent")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            do {
                _ = try CIFImport.crystalModel(from: text, fileBaseName: file.deletingPathExtension().lastPathComponent)
            } catch let error as CIFImportError {
                if case .multipleStructures = error {
                    XCTFail("\(file.lastPathComponent) refused as multi-block: \(error)")
                }
            }
        }
    }
}
