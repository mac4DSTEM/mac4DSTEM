import XCTest
@testable import mac4DSTEM

final class ScaleBarUnitTests: XCTestCase {
    private let en = Locale(identifier: "en_US_POSIX")

    /// Mutation: ladder returns its input unchanged - "0.02 µm" survives, red.
    func testLadderPicksTheUnitSoTheNumberIsAtLeastOne() {
        var r = ScaleBar.ladder(0.02, unit: "\u{00B5}m")
        XCTAssertEqual(r.value, 20); XCTAssertEqual(r.unit, "nm")
        r = ScaleBar.ladder(2000, unit: "nm")
        XCTAssertEqual(r.value, 2); XCTAssertEqual(r.unit, "\u{00B5}m")
        r = ScaleBar.ladder(0.5, unit: "mm")
        XCTAssertEqual(r.value, 500); XCTAssertEqual(r.unit, "\u{00B5}m")
        r = ScaleBar.ladder(0.001, unit: "mm")
        XCTAssertEqual(r.value, 1); XCTAssertEqual(r.unit, "\u{00B5}m")
        r = ScaleBar.ladder(0.000002, unit: "mm")
        XCTAssertEqual(r.value, 2); XCTAssertEqual(r.unit, "nm")
        r = ScaleBar.ladder(1000, unit: "nm")
        XCTAssertEqual(r.value, 1); XCTAssertEqual(r.unit, "\u{00B5}m")
        r = ScaleBar.ladder(999, unit: "nm")
        XCTAssertEqual(r.value, 999); XCTAssertEqual(r.unit, "nm")
        r = ScaleBar.ladder(5000, unit: "mm")   // top rung: stays mm
        XCTAssertEqual(r.value, 5000); XCTAssertEqual(r.unit, "mm")
        r = ScaleBar.ladder(0.2, unit: "nm")    // bottom rung: stays nm
        XCTAssertEqual(r.value, 0.2); XCTAssertEqual(r.unit, "nm")
    }

    /// Mutation: ladder relabels without scaling the number - 0.02 stays 0.02, red.
    func testLadderKeepsTheLengthExactAndLeavesOtherUnitsAlone() {
        for (v, u) in [(0.02, "\u{00B5}m"), (2000.0, "nm"), (0.05, "mm"), (50000.0, "nm")] {
            let r = ScaleBar.ladder(v, unit: u)
            let toNm = { (x: Double, unit: String) -> Double in
                x * (unit == "mm" ? 1e6 : unit == "\u{00B5}m" ? 1e3 : 1) }
            XCTAssertEqual(toNm(r.value, r.unit), toNm(v, u), accuracy: toNm(v, u) * 1e-12)
        }
        for u in ["\u{00C5}", "pm", "nm\u{207B}\u{00B9}", "\u{00C5}\u{207B}\u{00B9}", "mrad", "px", "furlong"] {
            let r = ScaleBar.ladder(0.02, unit: u)
            XCTAssertEqual(r.value, 0.02); XCTAssertEqual(r.unit, u)
        }
    }

    /// Mutation: spokenUnit returns the unit as written - "Scale bar, 10 nm", red.
    func testSpokenLabelSaysTheUnitInFull() {
        XCTAssertEqual(ScaleBar.spokenLabel(value: 10, unit: "nm", locale: en), "Scale bar, 10 nanometres")
        let table: [(String, String)] = [
            ("\u{00B5}m", "micrometres"), ("\u{00C5}", "\u{00E5}ngstr\u{00F6}ms"),
            ("1/nm", "inverse nanometres"), ("nm\u{207B}\u{00B9}", "inverse nanometres"),
            ("\u{00C5}\u{207B}\u{00B9}", "inverse \u{00E5}ngstr\u{00F6}ms"),
            ("mrad", "milliradians"), ("px", "pixels"), ("furlong", "furlong"),
        ]
        for (u, spoken) in table { XCTAssertEqual(ScaleBar.spokenUnit(u), spoken, u) }
    }
}
