// Help > Send Feedback: an email the person sends themselves, to the project's address, naming the build.

import XCTest
@testable import mac4DSTEM

final class FeedbackLinksTests: XCTestCase {
    /// Mutation: another address, or the versions dropped from the body - red.
    func testFeedbackIsAnEmailToTheProjectThatNamesTheBuild() throws {
        let url = try XCTUnwrap(FeedbackLinks.mail(appVersion: "5.2.1 (41)", systemVersion: "26.1.0"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "mail@mac4dstem.com")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "subject" }?.value, "mac4DSTEM feedback")
        let body = try XCTUnwrap(parts.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.hasSuffix("mac4DSTEM 5.2.1 (41), macOS 26.1.0"), body)
        XCTAssertTrue(body.hasPrefix("\n\n"), "room to write above the versions")
    }

    func testSupportIsTheWebsitesSupportPage() {
        XCTAssertEqual(FeedbackLinks.support?.absoluteString, "https://mac4dstem.com/support.html")
        XCTAssertNotNil(FeedbackLinks.mail)
    }
}
