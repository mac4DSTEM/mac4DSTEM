// ResultsJourney: the Results workspace on the demo (process/ui-testing-2026-10-21.md §3). Saving and exporting follow once the
// demo has a place to write: `--export-dir` is not read by an export yet (the save panel is not driven).

import XCTest

final class ResultsJourney: Journey {
    func testResultsStartEmptyOnTheDemo() {
        step("launch with the demo") { launch(arguments: ["--demo-fixture"]) }
        step("open Results") {
            waitForLoadingToEnd()
            wait(for: "workspace.results").click()
            wait(for: "results.nothingSaved")
        }
    }
}
