//
//  UnreadableFileRoutingTests.swift
//  A file the app may not read is refused as unreadable, not as an unknown format (#356: a valid HDF5 file in another app's sandbox
//  container was refused as "not a format the app opens").
//

import XCTest
import DSTEMCore

final class UnreadableFileRoutingTests: XCTestCase {
    /// Mutation: drop the readability check - "is not a format the app opens", red.
    func testAFileThatCannotBeReadSaysSo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("unreadable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("scan.h5")
        try Data([0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 0, count: 64)).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        guard case .refused(let sentence) = FileRouting.route(path: file.path) else {
            return XCTFail("an unreadable file must be refused")
        }
        XCTAssertTrue(sentence.contains("can't be read"), sentence)
        XCTAssertFalse(sentence.contains("not a format"), sentence)
    }

    /// A readable file of an unknown format keeps its sentence.
    func testAnUnknownFormatStillSaysSo() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("unknown-\(UUID().uuidString).xyz")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        guard case .refused(let sentence) = FileRouting.route(path: file.path) else { return XCTFail("an unknown format is refused") }
        XCTAssertTrue(sentence.contains("not a format"), sentence)
    }
}
