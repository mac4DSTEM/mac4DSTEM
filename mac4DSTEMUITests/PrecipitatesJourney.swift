// PrecipitatesJourney: the precipitate variant map on the public Al-Mg-Si demo, through the app's real open path (`--open`).
// Open the cube, detect the disks, run Phase mapping with the Al-Mg-Si preset (Al and the beta'' CIF), turn on Count variants with
// the beta'' / Al orientation relationship, and see the variant legend (or the room's own reason it cannot name variants).
//
// RUN PENDING (written and compiled 2026-10-31, never run): it drives an open panel and a full phase map, so it needs a quiet Mac
// that nobody is using. Run it once there as
//     tools/run-tests.sh ui PrecipitatesJourney
// The inputs are read, never written: the demo cube is copied into the runner's temporary folder first and the copy is opened, so
// nothing the room saves next to its file lands in References. The References folder defaults to the one beside this checkout;
// pass TEST_RUNNER_MAC4DSTEM_REFERENCES=<path to References> from a worktree.

import XCTest

final class PrecipitatesJourney: Journey {
    private static let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let references = ProcessInfo.processInfo.environment["MAC4DSTEM_REFERENCES"]
        ?? checkout.deletingLastPathComponent().appendingPathComponent("References").path
    private static let demoCube = references + "/mac4DSTEM/demo-dataset/AlMgSi_demo.h5"
    private static let betaDoublePrimeCIF = references + "/mac4DSTEM/crystal-structures/beta_double_prime_Mg5Si6.cif"

    /// The demo cube copied into a fresh temporary folder; the copy is what the app opens.
    private func copyOfTheDemoCube() throws -> String {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.demoCube), "\(Self.demoCube) is not on this machine")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.betaDoublePrimeCIF), "\(Self.betaDoublePrimeCIF) is not on this machine")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PrecipitatesJourney-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("AlMgSi_demo.h5")
        try FileManager.default.copyItem(atPath: Self.demoCube, toPath: copy.path)
        return copy.path
    }

    /// Picks a file in the open panel the app just showed: Go to Folder (shift-command-G), the path, Return, then Open.
    private func choose(_ path: String) {
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "the open panel did not appear")
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
        let open = panel.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the open panel has no Open button")
        open.click()
    }

    private func waitIdle(_ what: String, timeout: TimeInterval = 300) {
        XCTAssertTrue(element("toolbar.display.idle").waitForExistence(timeout: timeout), "the room did not come back to idle after \(what)")
    }

    func testTheVariantMapOnTheAlMgSiDemo() throws {
        let cube = try copyOfTheDemoCube()
        step("open the Al-Mg-Si demo") {
            launch(arguments: ["--open", cube])
            waitForLoadingToEnd(timeout: 180)
        }
        step("detect all disks") {
            wait(for: "workspace.braggDisks", timeout: 60).click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 300)
        }
        step("open Phase mapping") {
            wait(for: "workspace.map").click()
            wait(for: "task.Phase mapping").click()
        }
        step("add the Al-Mg-Si preset with the beta'' CIF") {
            wait(for: "phaseMapping.addPhase", timeout: 30).click()
            let preset = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Al–Mg–Si'")).firstMatch
            XCTAssertTrue(preset.waitForExistence(timeout: 10), "the Add Phase menu has no Al-Mg-Si preset")
            preset.click()
            choose(Self.betaDoublePrimeCIF)
            wait(for: "phaseMapping.matrix", timeout: 30)
        }
        step("run the phase map") {
            // The preset leaves Q unset ("calibrate from this scan's own lattice"): take the room's own scale when it offers one.
            let scale = element("phaseMapping.scaleToDetector")
            if scale.waitForExistence(timeout: 5), scale.isEnabled { scale.click() }
            let run = wait(for: "phaseMapping.run", timeout: 30)
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: run)
            XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "Run never became enabled")
            run.click()
            waitGone("toolbar.display.busy", timeout: 900)
            waitIdle("the phase map")
        }
        step("count variants with the beta'' / Al relationship") {
            let toggle = wait(for: "precipitates.variants.section", timeout: 60)
            toggle.click()
            wait(for: "precipitates.variants.orPicker", timeout: 30)
        }
        step("the variant legend, or the room's reason, is shown") {
            let legend = element("precipitates.variants.legend")
            let unavailable = element("precipitates.variants.unavailable")
            let shown = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in legend.exists || unavailable.exists }, object: nil)
            XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 120), .completed, "neither the variant legend nor a reason appeared")
            if unavailable.exists {
                XCTFail("the room cannot name variants on the demo: \(unavailable.label) \(String(describing: unavailable.value))")
            } else {
                XCTAssertTrue(element("precipitates.variants.totals").exists, "the legend has no totals row")
            }
        }
    }
}
