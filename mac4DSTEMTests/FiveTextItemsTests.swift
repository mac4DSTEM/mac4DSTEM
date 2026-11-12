//
//  FiveTextItemsTests.swift
//  Five text items seen on the final on-screen check of 5.3.0 (mac4DSTEM#280).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class FiveTextItemsTests: XCTestCase {
    /// 1. The Dataset menu says "Session", as the panel it opens does. Red before: "Session Sidecar" in all five.
    func testTheDatasetMenuSaysSession() {
        XCTAssertEqual(DatasetMenuWording.all.count, 5)
        for title in DatasetMenuWording.all {
            XCTAssertTrue(title.contains("Session"), title)
            XCTAssertFalse(title.localizedCaseInsensitiveContains("sidecar"), title)
        }
        XCTAssertFalse(AppState.SessionSavePanelWording.title.localizedCaseInsensitiveContains("sidecar"))
    }

    /// No sentence the user reads says "sidecar": the file is the session file everywhere. Reads the app's sources: every string
    /// literal with a space in it on a line that is not a comment, its interpolations left out. Red before: 61 of them.
    func testNoUserFacingTextSaysSidecar() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("mac4DSTEM")
        let literal = #/"((?:[^"\\]|\\.)*)"/#, interpolation = #/\\\((?:[^()]|\([^()]*\))*\)/#
        var found: [String] = [], files = 0
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" {
            files += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { continue }
                for match in line.matches(of: literal) {
                    let prose = String(match.1).replacing(interpolation, with: "")
                    if prose.contains(" "), prose.localizedCaseInsensitiveContains("sidecar") {
                        found.append("\(url.lastPathComponent):\(number + 1): \(prose)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(files, 100, "the sources were not found at \(sources.path)")
        XCTAssertEqual(found, [], "user-facing text says sidecar")
    }

    /// 2. The stale-disks reason once: with the requirement line saying it, no second note. Red before: both.
    func testTheStaleDisksReasonIsSaidOnce() {
        var readiness = ProductWorkflowReadiness()
        readiness.disksNotUsableReason = AppState.disksNotUsableReason(hasDisks: true, settingsAreStale: true, storedDisksNote: nil)
        XCTAssertTrue(readiness.diskRequirementTitle.contains("the detection settings changed"))
        XCTAssertFalse(readiness.needsSeparateStaleDisksNote(settingsAreStale: true), "the requirement line says it")
        readiness.disksNotUsableReason = nil
        XCTAssertTrue(readiness.needsSeparateStaleDisksNote(settingsAreStale: true), "nothing else says it")
        XCTAssertFalse(readiness.needsSeparateStaleDisksNote(settingsAreStale: false))
    }

    /// 3. The spot fit's refusal fits the status line; the note holds the whole sentence. Red before: one long sentence, cut.
    func testTheSpotFitsRefusalFitsTheStatusLine() {
        let refusal = AppState.spotDistortionRefusal(crystal: "Al_thronsen2024", fitSummary: "1,051 at 166° · residual 0,61 px (1,90 px without)")
        XCTAssertLessThanOrEqual(("Error: " + refusal.status).count, 115, refusal.status)
        XCTAssertTrue(refusal.status.contains("under the button"))
        XCTAssertTrue(refusal.note.contains("Al_thronsen2024") && refusal.note.contains("residual 0,61") && refusal.note.contains("Check the crystal"))
    }

    @MainActor
    func testTheRefusalsNoteGoesWithTheNextFit() {
        let run = SpotDistortionRun()
        run.refuse("why")
        XCTAssertEqual(run.refusal, "why")
        XCTAssertNil(run.pending)
        run.clear()
        XCTAssertNil(run.refusal)
    }

    /// 4. Reference inliers grouped by the Region. Red before: "1119/1309".
    func testReferenceInliersAreGrouped() {
        XCTAssertEqual(StrainBasisText.inliers(1119, of: 1309, locale: Locale(identifier: "en_US")), "1,119 of 1,309")
        XCTAssertEqual(StrainBasisText.inliers(1119, of: 1309, locale: Locale(identifier: "de_DE")), "1.119 of 1.309")
    }

    /// 5. Prepare's empty pane carries no other room's result name. Red before: "ACOM full scan · Reliability" over "No Result Yet".
    func testPreparesEmptyPaneHasNoResultTitle() {
        XCTAssertEqual(AppState.resultPaneTitle(name: "ACOM full scan · Reliability", hasResult: false, inPrepare: true), "")
        XCTAssertEqual(AppState.resultPaneTitle(name: "Virtual detector · Annulus", hasResult: true, inPrepare: true), "Virtual detector · Annulus")
        XCTAssertEqual(AppState.resultPaneTitle(name: "Phase map (3 candidates)", hasResult: false, inPrepare: false), "Phase map (3 candidates)",
                       "a task's own room keeps its title (mac4DSTEM#175)")
    }
}
