import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// `UI/MapSettings.swift`'s ACOM "Source" row used to switch on
/// `CrystalModelSource` and fall through to `EmptyView()` for `.builtIn` and
/// `.custom` — both still reachable via a replayed
/// `CrystalModelSelection.library`/`.customCubic`, even though neither is
/// offered from the "Phase model" picker any more (consolidation review
/// 2026-09-22, finding C-3's residual after the picker itself was replaced
/// by session S5/2026-09-21's product decision). Pinned here directly on the
/// pure label function so a future silently-dropped case fails a unit test,
/// not just a screen nobody drove.
final class ACOMPhaseModelSourceLabelTests: XCTestCase {

    func testEveryCrystalModelSourceProducesANonEmptyLabel() {
        for source in CrystalModelSource.allCases {
            XCTAssertFalse(
                acomPhaseModelSourceLabel(source: source, id: "some_id").isEmpty,
                "\(source) must show something in the Source row"
            )
        }
    }

    func testEachSourcesLabelNamesItsOrigin() {
        XCTAssertEqual(acomPhaseModelSourceLabel(source: .imported, id: "imported_ws2"), "Imported CIF")
        XCTAssertEqual(acomPhaseModelSourceLabel(source: .materialsProject, id: "mp-101"), "Materials Project mp-101")
        XCTAssertEqual(acomPhaseModelSourceLabel(source: .builtIn, id: "au_fcc"), "Built-in library")
        XCTAssertEqual(acomPhaseModelSourceLabel(source: .custom, id: "custom_cubic"), "Custom cell")
    }
}
