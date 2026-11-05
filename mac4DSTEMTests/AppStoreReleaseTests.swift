//
//  AppStoreReleaseTests.swift
//  One tag, two builds (mac4DSTEM#121): tools/release.sh builds the Developer ID DMG and, with --store, the App Store
//  package. The export options and the script's guards are files a later edit can quietly break; these read them.
//

import XCTest

final class AppStoreReleaseTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Mutation: method back to "developer-id", destination "upload", or another team - red.
    func testTheStoreExportOptionsExportAnAppStorePackageForTheTeam() throws {
        let url = root.appendingPathComponent("tools/release/ExportOptions-AppStore.plist")
        let options = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            as? [String: Any])
        XCTAssertEqual(options["method"] as? String, "app-store-connect")
        XCTAssertEqual(options["destination"] as? String, "export", "the export never uploads; --upload is its own step")
        XCTAssertEqual(options["teamID"] as? String, "3B8SMSSAX4")
        XCTAssertEqual(options["signingStyle"] as? String, "automatic")
    }

    /// Mutation: drop a product check from build-app-store.sh, or let release.sh upload without --upload - red.
    func testTheStoreBuildChecksItsProductAndUploadsOnlyWhenAsked() throws {
        let build = try String(contentsOf: root.appendingPathComponent("tools/release/build-app-store.sh"), encoding: .utf8)
        for check in ["MACEM_STORE_BUILD=YES", "pkgutil --check-signature", "com.apple.security.app-sandbox",
                      "get-task-allow", "PrivacyInfo.xcprivacy", "ITSAppUsesNonExemptEncryption", "Sparkle.framework",
                      "assert_mac4dstem_bundle_arm64_only", "ExportOptions-AppStore.plist"] {
            XCTAssertTrue(build.contains(check), "build-app-store.sh no longer checks \(check)")
        }
        XCTAssertFalse(build.contains("altool"), "the build step uploads nothing")

        let release = try String(contentsOf: root.appendingPathComponent("tools/release.sh"), encoding: .utf8)
        let uploads = release.components(separatedBy: "--upload-app").count - 1
        XCTAssertEqual(uploads, 1)
        let guardLine = try XCTUnwrap(release.range(of: "if (( UPLOAD == 1 )); then"))
        let uploadLine = try XCTUnwrap(release.range(of: "--upload-app"))
        XCTAssertLessThan(guardLine.lowerBound, uploadLine.lowerBound, "the upload sits behind --upload")
        XCTAssertTrue(release.contains("describe --exact-match --tags HEAD"), "both flavours build from a release tag")
    }
}
