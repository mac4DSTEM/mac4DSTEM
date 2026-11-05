//
//  PrivacyManifestTests.swift
//  App Store Connect rejects an upload whose bundles use a required-reason API without a privacy manifest, and asks the
//  export-compliance question on every build unless Info.plist answers it (mac4DSTEM#119). These read the BUILT host app.
//

import XCTest

final class PrivacyManifestTests: XCTestCase {
    private var app: Bundle { Bundle.main }

    /// Every bundle that ships: the app, both Quick Look extensions, the HDF5 XPC helper.
    private func shippedBundles() throws -> [URL] {
        let root = app.bundleURL.appendingPathComponent("Contents")
        let plugIns = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("PlugIns"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "appex" }
        let xpc = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("XPCServices"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "xpc" }
        XCTAssertEqual(plugIns.count, 2, "QuickLookPreview and QuickLookThumbnail")
        XCTAssertEqual(xpc.count, 1, "HDF5Helper")
        return [app.bundleURL] + plugIns + xpc
    }

    private func manifest(in bundle: URL) throws -> [String: Any] {
        let resources = bundle.appendingPathComponent("Contents/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: resources)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// Mutation: delete any one PrivacyInfo.xcprivacy, or drop the UserDefaults entry - red.
    func testEveryShippedBundleDeclaresNoTrackingAndItsRequiredReasons() throws {
        for bundle in try shippedBundles() {
            let plist = try manifest(in: bundle)
            XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false, bundle.lastPathComponent)
            XCTAssertEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0, bundle.lastPathComponent)
            let types = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? []
            let reasons = Dictionary(uniqueKeysWithValues: types.compactMap { entry -> (String, [String])? in
                guard let type = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
                return (type, entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
            })
            XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"], bundle.lastPathComponent)
            XCTAssertTrue(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"]?.contains("3B52.1") == true,
                          bundle.lastPathComponent)
        }
    }

    /// Mutation: remove the key from mac4DSTEM/Info.plist - red.
    func testTheAppDeclaresNoNonExemptEncryption() {
        XCTAssertEqual(app.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
    }

    /// `statfs` is a disk-space required-reason API, and no listed reason fits asking whether a volume is local; the
    /// reader asks `volumeIsLocal` instead. Mutation: put `statfs(` back in DM4Reader.swift - red.
    func testAppSourcesCallNoDiskSpaceAPI() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mac4DSTEM")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for api in ["statfs(", "statvfs(", "fstatfs(", "volumeAvailableCapacity", "systemFreeSize"] {
                let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                XCTAssertFalse(code.contains { $0.contains(api) }, "\(file.lastPathComponent) calls \(api)")
            }
        }
    }
}
