//
//  SoftwareUpdateTests.swift
//  The website download's updater (#122): Sparkle in that build only. The App Store build reads Info.plist and
//  mac4DSTEM.entitlements; the download reads Info-Direct.plist and mac4DSTEM-Direct.entitlements (MACEM_STORE_BUILD=NO).
//  These hold the two pairs to differ by exactly the updater's keys, the project to switch on that one setting, and the
//  release scripts to sign the download's updater and refuse it in the store build.
//

import XCTest
@testable import mac4DSTEM

final class SoftwareUpdateTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], path)
    }

    private func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Mutation: edit Info.plist without copying the change, drop a Sparkle key, or turn system profiling or automatic
    /// checks on without asking - red.
    func testTheDownloadsInfoPlistIsTheStoresPlusTheUpdaterKeys() throws {
        let store = try plist("mac4DSTEM/Info.plist")
        var direct = try plist("mac4DSTEM/Info-Direct.plist")
        XCTAssertEqual(direct.removeValue(forKey: "SUFeedURL") as? String, "https://mac4dstem.com/appcast/mac4dstem.xml")
        let key = try XCTUnwrap(direct.removeValue(forKey: "SUPublicEDKey") as? String)
        XCTAssertEqual(key, "j4qRIz2RC40tuHy7FRngpvq0OHuJWLjAT7v/Mtx49qE=", "the public half of Paul's EdDSA key (made 2026-11-13, #285)")
        XCTAssertEqual(direct.removeValue(forKey: "SUEnableInstallerLauncherService") as? Bool, true, "the sandboxed installer")
        XCTAssertEqual(direct.removeValue(forKey: "SUEnableSystemProfiling") as? Bool, false, "no system profile is sent")
        XCTAssertNil(direct["SUEnableAutomaticChecks"], "Sparkle asks the person before it checks by itself")
        XCTAssertEqual(NSDictionary(dictionary: direct), NSDictionary(dictionary: store),
                       "Info-Direct.plist is Info.plist plus the four Sparkle keys")
        XCTAssertTrue(store.keys.allSatisfy { !$0.hasPrefix("SU") }, "the store build names no updater")
    }

    /// Mutation: give the store build the installer exception, or the download any other extra entitlement - red.
    func testTheDownloadsEntitlementsAreTheStoresPlusTheInstallerException() throws {
        let store = try plist("mac4DSTEM/mac4DSTEM.entitlements")
        var direct = try plist("mac4DSTEM/mac4DSTEM-Direct.entitlements")
        let names = try XCTUnwrap(direct.removeValue(forKey: "com.apple.security.temporary-exception.mach-lookup.global-name")
            as? [String])
        XCTAssertEqual(names, ["$(PRODUCT_BUNDLE_IDENTIFIER)-spks", "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"])
        XCTAssertEqual(NSDictionary(dictionary: direct), NSDictionary(dictionary: store))
        XCTAssertEqual(store["com.apple.security.network.client"] as? Bool, true, "the feed is fetched by the app itself")
    }

    /// Mutation: a configuration that forgets the switch, or a store build that keeps the framework - red.
    func testTheProjectSwitchesTheUpdaterOnTheStoreBuildSetting() throws {
        let project = try text("mac4DSTEM.xcodeproj/project.pbxproj")
        func count(_ line: String) -> Int { project.components(separatedBy: line).count - 1 }
        // Debug, Release and Develop of the app target.
        XCTAssertEqual(count("MACEM_STORE_BUILD = NO;"), 3)
        XCTAssertEqual(count(#"INFOPLIST_FILE = "mac4DSTEM/Info$(MACEM_FLAVOUR_SUFFIX_$(MACEM_STORE_BUILD)).plist";"#), 3)
        XCTAssertEqual(count(#"CODE_SIGN_ENTITLEMENTS = "mac4DSTEM/mac4DSTEM$(MACEM_FLAVOUR_SUFFIX_$(MACEM_STORE_BUILD)).entitlements";"#), 3)
        XCTAssertEqual(count(#"SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) $(MACEM_UPDATER_CONDITION_$(MACEM_STORE_BUILD))";"#), 3)
        XCTAssertEqual(count("MACEM_UPDATER_CONDITION_NO = SPARKLE;"), 3)
        // -dead_strip_dylibs alone also dropped the three HDF5 frameworks' load commands (FormatoKit opens them by path, so
        // nothing names their symbols): they are kept as needed, so the store executable differs from the download's only by Sparkle.
        XCTAssertEqual(count(#"MACEM_STORE_LDFLAGS_YES = "-Wl,-dead_strip_dylibs -Wl,-needed_framework,FormatoLibHDF5 -Wl,-needed_framework,FormatoLibSZ -Wl,-needed_framework,FormatoLibAEC";"#), 3)
        XCTAssertTrue(project.contains(#"rm -rf \"${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Sparkle.framework\""#))
        XCTAssertTrue(project.contains(#""Info-Direct.plist","#), "the download's plist is not copied as a resource")
        // The bundle identifier, one setting a drive copy overrides (MACEM_APP_ID): the release value stays the App Store record's.
        XCTAssertTrue(try text("Config/Version.xcconfig").contains("\nMACEM_APP_ID = com.mac4dstem.mac4DSTEM\n"))
        XCTAssertEqual(count(#"PRODUCT_BUNDLE_IDENTIFIER = "$(MACEM_APP_ID)";"#), 3)
        XCTAssertEqual(count(#"PRODUCT_BUNDLE_IDENTIFIER = "$(MACEM_APP_ID).QuickLookPreview";"#), 3)
        XCTAssertEqual(count(#"PRODUCT_BUNDLE_IDENTIFIER = "$(MACEM_APP_ID).QuickLookThumbnail";"#), 3)
    }

    /// Mutation: drop the helper signing, the key check or the feed step from the download; or a store check - red.
    func testTheReleaseScriptsSignTheDownloadsUpdaterAndRefuseItInTheStore() throws {
        let download = try text("tools/release/build-developer-id.sh")
        for check in ["Installer.xpc", "Autoupdate", "Updater.app", "Downloader.xpc", "SUPublicEDKey", "SET-BEFORE-RELEASE",
                      "-clonedSourcePackagesDirPath", "CURRENT_PROJECT_VERSION=\"$VERSION_SET\"", "mach-lookup"] {
            XCTAssertTrue(download.contains(check), "build-developer-id.sh no longer handles \(check)")
        }
        XCTAssertTrue(try text("tools/release.sh").contains("tools/release/appcast.sh"))
        let feed = try text("tools/release/appcast.sh")
        for part in ["sign_update", "sparkle:version", "sparkle:minimumSystemVersion", "releases/download/{tag}/mac4DSTEM-{version}.dmg"] {
            XCTAssertTrue(feed.contains(part), "appcast.sh no longer writes \(part)")
        }
        let store = try text("tools/release/build-app-store.sh")
        for check in ["otool -L", "SUFeedURL", "temporary-exception", "FormatoLibHDF5 FormatoLibSZ FormatoLibAEC"] {
            XCTAssertTrue(store.contains(check), "build-app-store.sh no longer checks \(check)")
        }
    }

    /// Mutation: start the updater in a Debug build, under UI tests, or with the placeholder key - red.
    func testTheUpdaterStartsOnlyInAReleaseWithARealKey() {
        let real: [String: Any] = ["SUFeedURL": "https://mac4dstem.com/appcast/mac4dstem.xml", "SUPublicEDKey": "c2lnbmluZy1rZXk="]
        XCTAssertTrue(SoftwareUpdatePolicy.shouldStart(info: real, debugBuild: false, uiTesting: false))
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: real, debugBuild: true, uiTesting: false))
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: real, debugBuild: false, uiTesting: true))
        var placeholder = real
        placeholder["SUPublicEDKey"] = SoftwareUpdatePolicy.placeholderKey
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: placeholder, debugBuild: false, uiTesting: false))
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: [:], debugBuild: false, uiTesting: false), "the store build's plist")
    }
}
