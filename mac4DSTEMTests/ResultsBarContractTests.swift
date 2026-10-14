import XCTest
@testable import mac4DSTEM

/// Source contracts for the Results room's bar and inspector (lane C, 2026-10-14). SwiftUI layout cannot be measured headless, so
/// these read the source, as `ReviewUXTests` does: each fails when the line it guards is put back. Tier 2.
final class ResultsBarContractTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("source tree not beside the tests: \(url.path)")
        }
        return text
    }

    /// Mutation: put back `Button("A")` / `Button("B")` -> red.
    func testTheCompareButtonsAreLabelledSetAsAAndSetAsB() throws {
        let text = try source("mac4DSTEM/UI/ResultsSettings.swift")
        XCTAssertTrue(text.contains("\"Set as A\""))
        XCTAssertTrue(text.contains("\"Set as B\""))
        XCTAssertFalse(text.contains("Button(\"A\")") || text.contains("Button(\"B\")"), "bare one-letter buttons are back")
    }

    /// One name per export, the File menu's. Mutation: rename the bar's button back to "Export PNG…" -> red.
    func testTheResultBarNamesItsExportsAsTheFileMenuDoes() throws {
        let bar = try source("mac4DSTEM/UI/ResultsWorkspace.swift")
        let menu = try source("mac4DSTEM/App/mac4DSTEMApp.swift")
        XCTAssertTrue(menu.contains("Button(\"Export Result PNG…\")"))
        XCTAssertTrue(bar.contains("Label(\"Export Result PNG…\""))
        XCTAssertFalse(bar.contains("Label(\"Export PNG…\""))
        XCTAssertTrue(bar.contains("Label(\"Export Data…\"") && bar.contains("Label(\"Export Bundle…\""))
    }

    /// Mutation: take the `ViewThatFits` or the menu fallback out of the bar -> red.
    func testTheResultBarFallsBackToOneExportMenuInsteadOfClipping() throws {
        let bar = try source("mac4DSTEM/UI/ResultsWorkspace.swift")
        guard let start = bar.range(of: "private var currentResultSummary"),
              let end = bar.range(of: "private var exportDataReason") else { return XCTFail("bar not found") }
        let body = String(bar[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(body.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(body.contains("summaryRow(exportsAsMenu: true)"))
        XCTAssertTrue(body.contains("Label(\"Export\", systemImage:"))
        XCTAssertTrue(body.contains("exportItems"), "the menu holds the same items as the buttons")
    }

    /// Mutation: put `.lineLimit(1)` back on the value, or take `selectableText` off -> red.
    func testLineageValuesWrapAndCanBeSelected() throws {
        let text = try source("mac4DSTEM/UI/LineageGraphView.swift")
        guard let start = text.range(of: "private struct LineageDetailRow") else { return XCTFail("row not found") }
        let row = String(text[start.lowerBound...])
        guard let valueStart = row.range(of: "Text(value)") else { return XCTFail("value text not found") }
        let value = String(row[valueStart.lowerBound...].prefix(400))
        XCTAssertTrue(value.contains(".selectableText(value)"))
        XCTAssertTrue(value.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(value.contains(".lineLimit(1)"), "the value is wrapped, not cut")
    }

    /// Keyboard focus must be visible on the lineage graph and list. Mutation: restore `.focusEffectDisabled()` -> red.
    func testTheLineageFocusRingIsNotHidden() throws {
        let text = try source("mac4DSTEM/UI/LineageGraphView.swift")
        XCTAssertFalse(text.contains(".focusEffectDisabled()"))
    }
}
