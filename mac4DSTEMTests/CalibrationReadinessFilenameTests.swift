import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Coverage for the scan-step token parser behind the R pixel-scale conflict
/// note (backlog #10). The note contradicts an imported, correct calibration
/// when it fires wrongly, so the no-token and unparseable cases matter more
/// than the happy path.
final class CalibrationReadinessFilenameTests: XCTestCase {

    private func parse(_ name: String) -> (angstromPerPixel: Double, text: String)? {
        UI2PrepareSettings.scanStepAngstromPerPixel(inFilename: name)
    }

    // MARK: - Tokens that must parse

    func testParsesScanStepFromTheRealTrainingFilename() throws {
        let parsed = try XCTUnwrap(parse(
            "Particle_1_Stack_1_45x90_ss30nm_0p09s_spot8_alpha=0p48_bin2_cl-600mm_300kV_bin8.h5"
        ))
        // 30 nm = 300 Å.
        XCTAssertEqual(parsed.angstromPerPixel, 300, accuracy: 1e-9)
        XCTAssertEqual(parsed.text, "30nm")
    }

    func testParsesEachSupportedUnit() throws {
        XCTAssertEqual(try XCTUnwrap(parse("a_ss5nm_b.h5")).angstromPerPixel, 50, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("a_ss500pm_b.h5")).angstromPerPixel, 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("a_ss2um_b.h5")).angstromPerPixel, 20_000, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("a_ss12a_b.h5")).angstromPerPixel, 12, accuracy: 1e-9)
    }

    func testParsesDecimalTokenAndIsCaseInsensitive() throws {
        XCTAssertEqual(try XCTUnwrap(parse("a_ss1.5nm_b.h5")).angstromPerPixel, 15, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("a_SS30NM_b.h5")).angstromPerPixel, 300, accuracy: 1e-9)
    }

    func testParsesFromAFullPathNotJustABareName() throws {
        let parsed = try XCTUnwrap(parse("/Users/x/data/ss30nm/scan_ss45nm.h5"))
        // The token must come from the last path component, not a parent
        // directory that happens to carry a different step.
        XCTAssertEqual(parsed.angstromPerPixel, 450, accuracy: 1e-9)
    }

    // MARK: - The cases where a false positive would libel a good calibration

    func testReturnsNilWhenTheFilenameHasNoScanStepToken() {
        XCTAssertNil(parse("downsample_Si_SiGe_exp.h5"))
        XCTAssertNil(parse("sim_Au_data_all_binned.h5"))
        XCTAssertNil(parse("polycrystal_2D_WS2.h5"))
    }

    func testReturnsNilForUnsupportedOrMissingUnits() {
        XCTAssertNil(parse("a_ss30_b.h5"))
        XCTAssertNil(parse("a_ss30mm_b.h5"))
        XCTAssertNil(parse("a_ss30s_b.h5"))
    }

    /// Other `ss`-free numeric tokens are everywhere in these filenames
    /// (`bin2`, `45x90`, `300kV`); none may be mistaken for a scan step.
    /// ui-09 (S22e): the unanchored regex matched `ss30nm` INSIDE
    /// `thickness30nm` — "thickne**ss30nm**" — and fired the filename-vs-
    /// imported-scale conflict note against a correct calibration. A token
    /// must not start mid-word.
    func testDoesNotMatchSSInsideAnOrdinaryWord() {
        XCTAssertNil(parse("thickness30nm_scan.h5"))
        XCTAssertNil(parse("glass5nm_region2.h5"))
        // The genuine token still parses when word-separated.
        XCTAssertNotNil(parse("sample_ss30nm_scan.h5"))
        XCTAssertNotNil(parse("ss30nm_scan.h5"))
    }

    func testDoesNotMatchUnrelatedNumericTokens() {
        XCTAssertNil(parse("Particle_1_Stack_1_45x90_bin2_300kV.h5"))
        XCTAssertNil(parse("a_cl-600mm_b.h5"))
    }
}
