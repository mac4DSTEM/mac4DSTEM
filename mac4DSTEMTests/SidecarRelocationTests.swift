//
//  SidecarRelocationTests.swift
//  Pins the file half of "Save Session Sidecar As…" (v2 S4):
//  `SessionSidecarLocator.copySidecarFile(from:to:)`. The panel and the seam retarget are
//  thin wiring around this; the copy decisions are what can silently lose a
//  session, so they are what gets pinned.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SidecarRelocationTests: XCTestCase {

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidecarRelocationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func write(_ text: String, to name: String) throws -> URL {
        let url = workDirectory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testAnExistingSidecarIsCopiedAndTheOriginalIsLeftInPlace() throws {
        let source = try write("session-content", to: "old.mac4dstem.h5")
        let destination = workDirectory.appendingPathComponent("new.mac4dstem.h5")
        XCTAssertEqual(SessionSidecarLocator.copySidecarFile(from: source, to: destination), .copied)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "session-content")
        // Copy, never move: deleting the previous companion would be the one
        // destructive step in an otherwise reversible gesture.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testAnExistingDestinationIsReplacedNotMergedInto() throws {
        // The save panel already asked the user about replacing; a stale file
        // half-surviving under the new name would be worse than either answer.
        let source = try write("current", to: "old.mac4dstem.h5")
        let destination = try write("stale", to: "new.mac4dstem.h5")
        XCTAssertEqual(SessionSidecarLocator.copySidecarFile(from: source, to: destination), .copied)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "current")
    }

    /// `isSameFile` is what "Allow Access…" trusts before it adopts a chosen file as this dataset's sidecar
    /// (2026-09-30): identity, not spelling — an alias to the same file passes, a same-named file elsewhere does not.
    func testSameFileIsByIdentityNotByName() throws {
        let sidecar = try write("session", to: "cube.mac4dstem.h5")
        let alias = workDirectory.appendingPathComponent("./cube.mac4dstem.h5")
        XCTAssertTrue(SessionSidecarLocator.isSameFile(alias, sidecar))
        let link = workDirectory.appendingPathComponent("link.h5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sidecar)
        XCTAssertTrue(SessionSidecarLocator.isSameFile(link, sidecar), "a symlink names the same file")
        let other = workDirectory.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let sameName = other.appendingPathComponent("cube.mac4dstem.h5")
        try Data("other cube's session".utf8).write(to: sameName)
        XCTAssertFalse(SessionSidecarLocator.isSameFile(sameName, sidecar), "the same name in another folder is another cube's sidecar")
        XCTAssertFalse(SessionSidecarLocator.isSameFile(workDirectory.appendingPathComponent("missing.h5"), sidecar))
    }

    func testAMissingSourceIsANormalOutcomeNotAFailure() {
        // First-ever relocation, before any save: there is nothing to copy and
        // that must not read as an error.
        let source = workDirectory.appendingPathComponent("never-written.mac4dstem.h5")
        let destination = workDirectory.appendingPathComponent("new.mac4dstem.h5")
        XCTAssertEqual(SessionSidecarLocator.copySidecarFile(from: source, to: destination), .nothingToCopy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testChoosingTheSameFileCopiesNothing() throws {
        let source = try write("content", to: "same.mac4dstem.h5")
        XCTAssertEqual(SessionSidecarLocator.copySidecarFile(from: source, to: source), .nothingToCopy)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "content")
    }

    func testAnAliasedPathToTheSameFileDoesNotDestroyIt() throws {
        // Case-insensitive APFS and symlinks spell one file two ways. A
        // path-string guard passes ("different strings"), the exists check
        // passes (same inode), and remove-then-copy would DELETE the only
        // sidecar. The alias here is a symlinked directory, so the two URLs
        // differ as strings while naming one file.
        let source = try write("the only copy", to: "session.mac4dstem.h5")
        let linkDirectory = workDirectory.appendingPathComponent("alias-dir")
        try FileManager.default.createSymbolicLink(
            at: linkDirectory, withDestinationURL: workDirectory
        )
        let alias = linkDirectory.appendingPathComponent("session.mac4dstem.h5")
        XCTAssertNotEqual(alias.path, source.path,
                          "the fixture needs two spellings of one file")
        XCTAssertEqual(SessionSidecarLocator.copySidecarFile(from: source, to: alias), .nothingToCopy)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "the only copy",
                       "an aliased 'copy onto itself' must never remove the file")
    }

    func testAnUnreadableSourceReportsFailureInsteadOfPretendingToCopy() throws {
        let source = try write("locked", to: "old.mac4dstem.h5")
        let destination = workDirectory.appendingPathComponent("new.mac4dstem.h5")
        try FileManager.default.setAttributes([.posixPermissions: 0],
                                              ofItemAtPath: source.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: source.path)
        }
        guard case .failed = SessionSidecarLocator.copySidecarFile(from: source, to: destination) else {
            return XCTFail("An unreadable source must surface as .failed — the caller's message depends on knowing the copy did not happen")
        }
    }
}
