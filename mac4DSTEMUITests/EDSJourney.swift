// EDSJourney: the EDS room (macTEM 1.0's, 2026-10-23) on mac4DSTEM's own 4D-STEM + EDS file and on the owner's Velox file, through the
// app's real open path (`--open`). One pass before Paul's drive, never per session. Run as
//     tools/run-tests.sh ui EDSJourney
// The 4D + EDS file is References/demo-edx/AlMgSi_4D_EDX.dm4 (simulated, beside the repo); the Velox file is $MACEM_DATA/stem-edx (default ../data).

import XCTest

final class EDSJourney: Journey {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let fourDEDS = repo.appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX.dm4").path
    private static let velox1339 = (ProcessInfo.processInfo.environment["MACEM_DATA"] ?? repo.deletingLastPathComponent().appendingPathComponent("data").path)
        + "/stem-edx/SI HAADF 1339 65000 x 20260508.emd"

    private func open(_ path: String) throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "\(path) is not on this machine")
        launch(arguments: ["--open", path, "--export-dir", "eds-journey"])
        waitForLoadingToEnd(timeout: 180)
        wait(for: "edx.spectrum", timeout: 180)
        XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: 180), "the room never came back to idle after Auto ID on open")
    }

    private func quantify() {
        let verb = wait(for: "workspace.primaryAction", timeout: 60)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: verb)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 120), .completed, "Quantify never became enabled")
        verb.click()
        wait(for: "edx.compositionTable", timeout: 180)
        XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: 180), "the room did not come back to idle after Quantify")
    }

    private func exportResults() {
        let button = wait(for: "edx.export.results", timeout: 30)
        XCTAssertTrue(button.isEnabled, "Results CSV is not enabled after Quantify")
        button.click()
        let said = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Exported' OR value BEGINSWITH 'Exported'")).firstMatch
        XCTAssertTrue(said.waitForExistence(timeout: 30), "the status line never said the results were exported")
    }

    /// The 4D + EDS joint file: the cube opens, its spectrum image is in the EDS room on the same scan, Quantify fits, Results CSV writes.
    func test1_FourDEDSFileOpensQuantifiesAndExports() throws {
        try step("open AlMgSi_4D_EDX.dm4; the EDS room shows maps and spectrum") { try open(Self.fourDEDS) }
        step("Quantify") { quantify() }
        step("Results CSV") { exportResults() }
    }

    /// The owner's Velox file (STEM-EDX alone): the same room, the same verbs.
    func test2_VeloxFileOpensQuantifiesAndExports() throws {
        try step("open SI HAADF 1339; the EDS room shows maps and spectrum") { try open(Self.velox1339) }
        step("Quantify") { quantify() }
        step("Results CSV") { exportResults() }
    }
}
