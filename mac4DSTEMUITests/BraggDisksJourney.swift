// BraggDisksJourney: Bragg Disks on the demo, the current pattern's peak count is positive (process/ui-testing-2026-10-21.md §3).

import XCTest

final class BraggDisksJourney: Journey {
    func testDetectionFindsPeaksOnTheCurrentPattern() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("detect all disks") {
            waitForLoadingToEnd()
            wait(for: "workspace.braggDisks").click()
            wait(for: "workspace.primaryAction").click()
            waitGone("toolbar.display.busy", timeout: 120)
        }
        step("the current pattern shows peaks") {
            wait(for: "disk.currentPeakCount", timeout: 30)
            // The row's value is its own text ("9 peaks"); the identifier sits on the row, which exposes only the title.
            let value = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS ' peaks' OR value CONTAINS ' peaks' OR title CONTAINS ' peaks'")).firstMatch
            let lines = app.debugDescription.split(separator: "\n").filter { $0.contains("peak") || $0.contains("CBED") }.prefix(8).joined(separator: " // ")
            XCTAssertTrue(value.waitForExistence(timeout: 30), "no peak count text; peak-like elements: \(lines)")
            let text = [value.label, (value.value as? String) ?? "", value.title].joined(separator: " ")
            let peaks = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.max() ?? 0
            XCTAssertGreaterThan(peaks, 0, "peak count read: \(text)")
        }
    }
}
