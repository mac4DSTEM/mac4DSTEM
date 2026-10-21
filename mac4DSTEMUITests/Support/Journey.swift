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

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    /// A fresh launch with the deterministic-app arguments plus the journey's own.
    func launch(arguments extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-ApplePersistenceIgnoreState", "YES"] + extra
        app.launch()
        app.activate()
        // The window first: a launch that shows none is a launch failure, named as one, with what the app says it is doing.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "mac4DSTEM showed no window after launch (state \(app.state.rawValue), \(app.windows.count) windows)\n\(app.debugDescription.split(separator: "\n").filter { !$0.contains("MenuItem") && !$0.contains("Menu,") && !$0.contains("MenuBarItem") }.joined(separator: "\n").prefix(3000))")
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

    /// Waits until the element's accessibility value satisfies `predicate` (a compute step: 60 s on the demo).
    func waitValue(of identifier: String, timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line,
                   where predicate: @escaping (String) -> Bool) {
        let e = element(identifier)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate((e.value as? String) ?? "") }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(identifier) never reached the expected value (last: \(String(describing: e.value)))", file: file, line: line)
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
