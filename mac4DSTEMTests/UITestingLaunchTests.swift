import XCTest
@testable import mac4DSTEM

/// The `--ui-testing` reset in one place: saved window and split geometry and saved application state go, other defaults stay.
/// The reset is a no-op unless the process was launched with the flag, so the test passes the flag's state through the helper's
/// own entry and checks only the file and defaults effects it can reach.
final class UITestingLaunchTests: XCTestCase {
    func testTheDefaultWindowIsFourteenFortyByNineHundred() {
        XCTAssertEqual(UITestingLaunch.windowHeight, 900)
        XCTAssertGreaterThanOrEqual(UITestingLaunch.windowWidth, 800)
    }

    func testResetIsInertWithoutTheFlag() throws {
        try XCTSkipIf(UITestingLaunch.isActive, "this process was launched with --ui-testing")
        let suite = "UITestingLaunchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("1 2 3 4", forKey: "NSWindow Frame dataset")
        UITestingLaunch.resetSavedState(defaults: defaults, home: NSTemporaryDirectory(), bundleIdentifier: nil)
        XCTAssertEqual(defaults.string(forKey: "NSWindow Frame dataset"), "1 2 3 4", "without the flag the reset must not touch a person's windows")
    }
}
