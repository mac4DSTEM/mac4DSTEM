import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Coverage for the shared `axisDelta` free function (`Core/Crystal/Crystal.swift`),
/// consolidated 2026-09-17 from byte-identical bodies in `CrystalModel.swift` and
/// `CIFImport.swift` (audit `docs/archive/audit-2026-09-16/REPORT.md` §3.2 row 8).
/// Neither file had a test that exercised its minimum-image wraparound before this:
/// a mutation deleting the `d > 0.5` correction survived both harnesses that compile
/// the file (`cif-symmetry-test`, `acom-orientation-test`) untouched.
final class CrystalMathTests: XCTestCase {

    /// The property the whole function exists for: two fractional coordinates
    /// straddling a cell boundary (0.99, 0.01) are 0.02 apart by minimum image,
    /// not 0.98 apart by raw subtraction. Mutation this catches: deleting or
    /// inverting the `d > 0.5` wraparound correction.
    func testAxisDeltaWrapsAcrossTheCellBoundary() {
        XCTAssertEqual(axisDelta(0.99, 0.01), 0.02, accuracy: 1e-9)
        XCTAssertEqual(axisDelta(0.01, 0.99), 0.02, accuracy: 1e-9,
                       "must be symmetric in its two arguments")
        XCTAssertEqual(axisDelta(0.5, 0.0), 0.5, accuracy: 1e-9,
                       "exactly half a cell apart is the boundary case, not a wrap")
        XCTAssertEqual(axisDelta(0.3, 0.7), 0.4, accuracy: 1e-9,
                       "an ordinary same-image separation is untouched by the wrap")
    }

    /// Integration check through the real caller: `CrystalModel.shortestCloseContact`
    /// prefilters pairs with `axisDelta` before the expensive 27-image search
    /// (`CrystalModel.swift`). Two sites at x=0.99 and x=0.01 in a 5 Å cubic cell are
    /// 0.1 Å apart by minimum image — well inside `closeContactLimit` (0.5 Å) — but a
    /// broken (non-wrapping) `axisDelta` computes a raw prefilter distance of 0.98,
    /// which exceeds the axis's own filter bound (0.1 Å for this cell), so the pair is
    /// dropped before the search ever runs and the contact goes undetected. This is the
    /// mutation `testAxisDeltaWrapsAcrossTheCellBoundary` alone would not reach if the
    /// prefilter and the search ever drifted to use different helpers.
    func testShortestCloseContactFindsAWraparoundPair() throws {
        let sites = [
            AtomSite(z: 14, fractional: SIMD3(0.99, 0.5, 0.5)),
            AtomSite(z: 14, fractional: SIMD3(0.01, 0.5, 0.5)),
        ]
        let crystal = Crystal(a: 5, b: 5, c: 5, sites: sites)
        let model = CrystalModel(
            id: "wrap-test", displayName: "wraparound test", crystal: crystal,
            symmetry: .cubic, source: .builtIn)
        let contact = try XCTUnwrap(model.shortestCloseContact,
                                    "a real 0.1 A contact across the cell boundary was missed")
        XCTAssertEqual(contact, 0.1, accuracy: 1e-6)
    }
}
