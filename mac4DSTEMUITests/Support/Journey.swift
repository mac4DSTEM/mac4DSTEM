//
//  Journey.swift
//  Role: the base of every UI journey (process/ui-testing-2026-10-21.md §3, §5): launches the app fresh with the arguments the
//        journey names, runs named steps that each keep a screenshot, and waits on existence or on a value, never on a delay.
//        A step is named by what the user did ("calibrate origin"); the first failure stops the journey.
//

import XCTest

class Journey: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A fresh launch with the deterministic-app arguments plus the journey's own (the recipe macTEM's journeys use). The run must
    /// hold the machine-wide UI lock (`tools/run-tests.sh ui`): two UI runs, or a person using the machine, take the foreground away
    /// and the app then shows no window to the test.
    func launch(arguments extra: [String] = []) {
        let a = XCUIApplication()
        // -NSTreatUnknownArgumentsAsOpen NO (macTEM's launcher does the same): AppKit otherwise turns the path after `--open` into an
        // open-documents event instead of a plain launch, and SwiftUI then shows no window (an .h5 path: 0 windows, 2026-10-30).
        // `--open <path>` is read by the app itself, never by AppKit.
        a.launchArguments = ["--ui-testing", "-NSTreatUnknownArgumentsAsOpen", "NO"] + extra
        a.launch()
        a.activate()
        XCTAssertTrue(a.windows.firstMatch.waitForExistence(timeout: 20),
                      "mac4DSTEM showed no window after launch (state \(a.state.rawValue), \(a.windows.count) windows)")
        app = a
        addTeardownBlock {
            a.terminate()
            _ = a.wait(for: .notRunning, timeout: 20)   // the next journey launches into a quiet desktop
        }
    }

    /// Runs `body`, then keeps a screenshot of the screen under the step's name.
    func step(_ name: String, _ body: () throws -> Void) rethrows {
        try XCTContext.runActivity(named: name) { activity in
            try body()
            // The app's own window, never the whole screen: the desk around it is not the test's to keep.
            let window = app.windows.firstMatch
            guard window.exists else { return }   // no window, no picture: never the whole screen
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            activity.add(shot)
        }
    }

    /// The element with this identifier, found anywhere in the window.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    func wait(for identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = element(identifier)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(identifier) did not appear in \(Int(timeout)) s", file: file, line: line)
        return e
    }

    /// Waits until the identifier no longer exists (a busy indicator ends).
    func waitGone(_ identifier: String, timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(identifier))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(identifier) did not go away", file: file, line: line)
    }

    /// Waits until the demo's loading overlay is gone (it has no identifier: the one place a test reads a label).
    func waitForLoadingToEnd(timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line) {
        let loading = app.staticTexts["Loading dataset"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "the dataset kept loading", file: file, line: line)
    }
}
