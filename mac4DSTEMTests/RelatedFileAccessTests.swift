//
//  RelatedFileAccessTests.swift
//  The sandbox grants the picked file, not its companion (mac4DSTEM#120). RelatedFileAccess asks for the companion as a
//  related item, which macOS allows only for extensions Info.plist declares with NSIsRelatedItemType. These hold the code's
//  list and the built Info.plist together, and pin which sibling each format asks for. Whether the grant works in the
//  sandboxed app is a drive on a real .mib/.hdr and EMPAD pair, recorded on the issue.
//

import XCTest
@testable import mac4DSTEM

final class RelatedFileAccessTests: XCTestCase {

    /// Mutation: drop "hdr" (or any companion) from the related item type in mac4DSTEM/Info.plist - red.
    func testEveryCompanionExtensionIsARelatedItemTypeOfTheBuiltApp() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let related = Set(types.filter { $0["NSIsRelatedItemType"] as? Bool == true }
            .flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] })
        let needed = Set(RelatedFileAccess.companionExtensions.values.flatMap { $0 })
        XCTAssertEqual(needed, ["hdr", "xml", "raw"])
        XCTAssertTrue(needed.isSubset(of: related), "not declared related: \(needed.subtracting(related).sorted())")
        // The related type claims nothing: raw and xml stay out of Open With (Info.plist's comment on the viewer type).
        for type in types where type["NSIsRelatedItemType"] as? Bool == true {
            XCTAssertEqual(type["CFBundleTypeRole"] as? String, "None")
            XCTAssertEqual(type["LSHandlerRank"] as? String, "None")
        }
    }

    /// Mutation: map "mib" to anything but "hdr", or forget a direction of the EMPAD pair - red.
    func testEachFormatAsksForItsSiblingBesideThePickedFile() {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("related-\(UUID().uuidString)")
        XCTAssertEqual(RelatedFileAccess.companions(of: folder.appendingPathComponent("scan.mib")).map(\.lastPathComponent),
                       ["scan.hdr"])
        XCTAssertEqual(RelatedFileAccess.companions(of: folder.appendingPathComponent("scan.xml")).map(\.lastPathComponent),
                       ["scan.raw"])
        XCTAssertEqual(RelatedFileAccess.companions(of: folder.appendingPathComponent("scan.raw")).map(\.lastPathComponent),
                       ["scan.xml"])
        XCTAssertEqual(RelatedFileAccess.companions(of: folder.appendingPathComponent("SCAN.MIB")).map(\.lastPathComponent),
                       ["SCAN.HDR"], "an upper-case pair keeps its case")
        XCTAssertEqual(RelatedFileAccess.companions(of: folder.appendingPathComponent("scan.dm4")), [])
        XCTAssertEqual(RelatedFileAccess.companions(of: folder.appendingPathComponent("scan.h5")), [])
    }

    /// Outside the sandbox (the test host) the grant is harmless, and a second call for the same file adds nothing.
    func testGrantingTwiceIsHarmless() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("related-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let mib = folder.appendingPathComponent("scan.mib")
        try Data([0]).write(to: mib)
        try Data([0]).write(to: folder.appendingPathComponent("scan.hdr"))
        RelatedFileAccess.grant(for: mib)
        RelatedFileAccess.grant(for: mib)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: folder.appendingPathComponent("scan.hdr").path))
    }
}
