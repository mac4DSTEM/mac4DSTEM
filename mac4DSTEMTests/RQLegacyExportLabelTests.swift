import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The decision rule behind `RQLegacyExportTests`. Pure: no file.
final class RQLegacyExportLabelTests: XCTestCase {
    func testOnlyThisAppsUnmarkedFilesAreLabelled() {
        typealias C = RQRotationConvention
        XCTAssertTrue(C.isUnmarkedExportOfThisApp(authoringProgram: "mac4DSTEM", convention: nil),
                      "this app's export with no marker predates 2026-09-28")
        XCTAssertFalse(C.isUnmarkedExportOfThisApp(authoringProgram: "mac4DSTEM", convention: C.marker))
        XCTAssertFalse(C.isUnmarkedExportOfThisApp(authoringProgram: "emdfile", convention: nil),
                       "a py4DSTEM-authored file is not labelled")
        XCTAssertFalse(C.isUnmarkedExportOfThisApp(authoringProgram: nil, convention: nil),
                       "no stamp at all is no evidence")
    }

    func testTheNoteSaysTheSignIsUnproven() {
        XCTAssertTrue(RQRotationConvention.legacyNote.contains("2026-09-28"))
        XCTAssertTrue(RQRotationConvention.legacyNote.contains("check it"))
    }
}
