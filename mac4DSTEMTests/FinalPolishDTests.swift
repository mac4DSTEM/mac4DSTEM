import XCTest
import DSTEMCore
import DSTEMSession
import FormatoDM
import SpectroCore

/// Slot 4⅞ lane D (owner card Q1 = a, 2026-10-04): a DM4 whose disk has been
/// disconnected refuses with `DM4Error.volumeGone` instead of dying with a
/// SIGBUS, and the refusal LATCHES — once a read has found the disk gone, the
/// old mapping is never read again, because it stays dead after a remount.
/// Since 2026-10-30 a later read maps the file anew from its path and reads
/// again once the disk is back; while it is away every read throws.
///
/// The real SIGBUS and the real forced unmount are not unit-testable; the
/// probe that measured them (a RAM disk, `hdiutil detach -force`, HEAD dies
/// with exit status 138, the guarded reader throws, and the same-name remount
/// still refuses) is archived beside the Slot 4⅞ record. These tests drive the
/// reader through an injected liveness check, and the real descriptor check
/// through what a healthy disk can still do (a rename, an unlink).
final class FinalPolishDTests: XCTestCase {

    // MARK: Fixture: the 2 x 2 x 2 x 3 int16 cube of `tools/harnesses/dm4-robustness-test`'s testValid

    private struct Writer {
        var bytes: [UInt8] = []
        mutating func u8(_ v: UInt8) { bytes.append(v) }
        mutating func u16be(_ v: UInt16) { bytes += [UInt8(v >> 8), UInt8(v & 0xFF)] }
        mutating func u32be(_ v: UInt32) { for s in [24, 16, 8, 0] { bytes.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        mutating func u64be(_ v: UInt64) { for s in [56, 48, 40, 32, 24, 16, 8, 0] { bytes.append(UInt8((v >> UInt64(s)) & 0xFF)) } }
        mutating func i16le(_ v: Int16) { let u = UInt16(bitPattern: v); bytes += [UInt8(u & 0xFF), UInt8(u >> 8)] }
        mutating func i32le(_ v: Int32) { let u = UInt32(bitPattern: v); for s in [0, 8, 16, 24] { bytes.append(UInt8((u >> UInt32(s)) & 0xFF)) } }
        mutating func ascii(_ s: String) { bytes += Array(s.utf8) }
    }

    private static func numberTag(_ label: String, _ value: Int32) -> [UInt8] {
        var w = Writer()
        w.u8(21); w.u16be(UInt16(label.utf8.count)); w.ascii(label)
        w.u64be(0); w.ascii("%%%%"); w.u64be(1); w.u64be(3); w.i32le(value)
        return w.bytes
    }

    private static func subgroup(_ label: String, nTags: Int) -> [UInt8] {
        var w = Writer()
        w.u8(20); w.u16be(UInt16(label.utf8.count)); w.ascii(label); w.u64be(0)
        w.u8(1); w.u8(0); w.u64be(UInt64(nTags))
        return w.bytes
    }

    /// Ry = 2, Rx = 2, Qy = 2, Qx = 3, int16 values 0..<24 in storage order.
    private static func tinyCube(base: Int16 = 0, scanY: Int32 = 2) -> Data {
        var header = Writer()
        header.u32be(4); header.u64be(0); header.u32be(1)
        var group = Writer()
        group.u8(1); group.u8(0); group.u64be(1)
        var pixels = Writer()
        for i in 0..<(12 * Int(scanY)) { pixels.i16le(base + Int16(i)) }
        var array = Writer()
        array.u8(21); array.u16be(4); array.ascii("Data")
        array.u64be(0); array.ascii("%%%%"); array.u64be(3); array.u64be(20); array.u64be(2); array.u64be(UInt64(12 * scanY))
        // Wrapped as DigitalMicrograph stores an image: ImageList entry 1 holds ImageData (FormatoKit reads that structure only).
        let image = subgroup("ImageList", nTags: 1) + subgroup("", nTags: 1) + subgroup("ImageData", nTags: 3)
            + numberTag("DataType", 1)
            + subgroup("Dimensions", nTags: 4)
            + numberTag("0", 3) + numberTag("1", 2) + numberTag("2", 2) + numberTag("3", scanY)
            + array.bytes + pixels.bytes
        return Data(header.bytes + group.bytes + image)
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac4dstem-finalpolish-d-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeCube(named name: String = "cube.dm4", base: Int16 = 0, scanY: Int32 = 2) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Self.tinyCube(base: base, scanY: scanY).write(to: url)
        return url.path
    }

    /// A liveness check the test flips, and counts.
    private nonisolated final class Disk: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [Bool]
        private var asked = 0
        /// `script` is consumed one answer per question; the last answer repeats.
        init(_ script: [Bool]) { answers = script }
        /// Replaces what is left of the script: the disk is back, or gone, for every later question.
        func answerFromNowOn(_ alive: Bool) { lock.lock(); defer { lock.unlock() }; answers = [alive] }
        var questions: Int { lock.lock(); defer { lock.unlock() }; return asked }
        var liveness: MappingLiveness {
            MappingLiveness { [self] in
                lock.lock(); defer { lock.unlock() }
                asked += 1
                return answers.count > 1 ? answers.removeFirst() : (answers.first ?? true)
            }
        }
    }

    private func requireGone(_ read: () async throws -> Void, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await read()
            XCTFail("\(what) must throw once the disk is gone", file: file, line: line)
        } catch let error as DM4Error {
            guard case .volumeGone(let name) = error else {
                XCTFail("\(what) threw \(error), not volumeGone", file: file, line: line); return
            }
            XCTAssertEqual(name, "cube.dm4", "\(what) names the file", file: file, line: line)
        } catch {
            XCTFail("\(what) threw \(error), not a DM4Error", file: file, line: line)
        }
    }

    // MARK: A healthy disk reads exactly what it read before

    /// The default check is the real one (a held descriptor): an ordinary file
    /// on the internal volume must read exactly what the unguarded reader
    /// read — `tools/harnesses/dm4-robustness-test`'s testValid numbers.
    func testAHealthyFileReadsUnchanged() async throws {
        let reader = try await DM4Reader(path: try writeCube())
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        let pattern = try await reader.readPattern(view, ry: 1, rx: 0)
        XCTAssertEqual(pattern, [12, 13, 14, 15, 16, 17])
        let row = try await reader.readScanRow(view, ry: 0)
        XCTAssertEqual(row, (0..<12).map(Float.init))
        let tile = try await reader.readScanTile(view, yRange: 0..<2)
        XCTAssertEqual(tile.pixels, (0..<24).map(Float.init))
        // And again: nothing was latched by reading.
        let again = try await reader.readPattern(view, ry: 1, rx: 1)
        XCTAssertEqual(again, [18, 19, 20, 21, 22, 23])
    }

    /// The descriptor is the witness, not the path: a file the user renames in
    /// Finder, or deletes, while the dataset is open keeps its mapping, so the
    /// reader must keep reading. (A path probe — statfs/stat of the open-time
    /// path — fails both and would refuse a healthy dataset.)
    func testRenamingOrDeletingTheFileWhileOpenDoesNotRefuse() async throws {
        let path = try writeCube()
        let reader = try await DM4Reader(path: path)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        let renamed = directory.appendingPathComponent("renamed.dm4").path
        try FileManager.default.moveItem(atPath: path, toPath: renamed)
        let afterRename = try await reader.readPattern(view, ry: 0, rx: 1)
        XCTAssertEqual(afterRename, [6, 7, 8, 9, 10, 11])
        try FileManager.default.removeItem(atPath: renamed)
        let afterDelete = try await reader.readPattern(view, ry: 1, rx: 1)
        XCTAssertEqual(afterDelete, [18, 19, 20, 21, 22, 23])
    }

    /// A file that cannot be watched is refused (fix round, refuter 2026-10-04:
    /// it used to come back `nil` and the reader then mapped the file with no
    /// guard at all). The refusal names the file, not the folder above it.
    func testTheRealCheckAnswersAliveForAnOpenableFileAndRefusesAMissingOne() throws {
        let path = try writeCube()
        let liveness = try MappingLiveness.descriptor(path: path)
        XCTAssertTrue(liveness.isAlive())
        XCTAssertThrowsError(
            try MappingLiveness.descriptor(path: directory.appendingPathComponent("absent.dm4").path)
        ) { error in
            guard case DM4Error.cannotOpen(let detail) = error else {
                return XCTFail("threw \(error), not DM4Error.cannotOpen")
            }
            XCTAssertTrue(detail.hasPrefix("absent.dm4 — its disk could not be watched"), detail)
            XCTAssertFalse(detail.contains(directory.lastPathComponent), "no folder above the file: \(detail)")
        }
    }

    /// Both opens fail on an unreadable file (mode 000): the refusal must be the
    /// OPEN's own error, as before the guard existed, not the descriptor's — the
    /// descriptor's refusal is only for a file the open could read.
    func testAnUnreadableMappedFileKeepsTheOpensOwnError() async throws {
        let path = try writeCube()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        do {
            _ = try await DM4Reader(path: path)
            XCTFail("an unreadable file must not open")
        } catch DM4Error.cannotOpen(let detail) {
            XCTAssertTrue(detail.hasPrefix("cube.dm4 — "), detail)
            XCTAssertFalse(detail.contains("could not be watched"),
                           "the open's own error wins, the descriptor's does not replace it: \(detail)")
        } catch {
            XCTFail("threw \(error), not DM4Error.cannotOpen")
        }
    }

    // MARK: A gone disk refuses at every public read

    /// One reader per entry point, so a read that forgot its guard cannot hide
    /// behind another entry point having latched first.
    func testReadPatternRefusesOnceTheDiskIsGone() async throws {
        let disk = Disk([false])
        let reader = try await DM4Reader(path: try writeCube(), liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        await requireGone({ _ = try await reader.readPattern(view, ry: 0, rx: 0) }, "readPattern")
    }

    func testReadScanRowRefusesOnceTheDiskIsGone() async throws {
        let disk = Disk([false])
        let reader = try await DM4Reader(path: try writeCube(), liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        await requireGone({ _ = try await reader.readScanRow(view, ry: 0) }, "readScanRow")
    }

    func testReadScanTileRefusesOnceTheDiskIsGone() async throws {
        let disk = Disk([false])
        let reader = try await DM4Reader(path: try writeCube(), liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        await requireGone({ _ = try await reader.readScanTile(view, yRange: 0..<1) }, "readScanTile")
    }

    /// The owner's sentence (card Q1 = a), with the file's name and nothing of
    /// the folders above it.
    func testTheRefusalReadsAsTheOwnerWroteItAndNamesNoFolder() async throws {
        let disk = Disk([false])
        let path = try writeCube()
        let reader = try await DM4Reader(path: path, liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        do {
            _ = try await reader.readPattern(view, ry: 0, rx: 0)
            XCTFail("a gone disk must refuse")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "cube.dm4 is no longer reachable: its disk was disconnected. Reconnect it and reopen.")
            XCTAssertFalse(error.localizedDescription.contains(directory.lastPathComponent),
                           "no folder above the file: \(error.localizedDescription)")
        }
    }

    /// The refusal needs no App change: a read error already reaches the
    /// window-modal alert as a data-source failure (`SessionGates`), and the
    /// alert shows the sentence as written (`sessionErrorDetail`), not a
    /// "domain code: ..." prefix.
    func testTheRefusalReachesTheModalAlertAsTheOwnersSentence() async throws {
        let disk = Disk([false])
        let reader = try await DM4Reader(path: try writeCube(), liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        do {
            _ = try await reader.readScanTile(view, yRange: 0..<2)
            XCTFail("a gone disk must refuse")
        } catch {
            XCTAssertTrue(SessionGates.isDataSourceFailure(error),
                          "a mid-scan loss of the disk invalidates the session: \(error)")
            XCTAssertEqual(
                sessionErrorDetail(error),
                "cube.dm4 is no longer reachable: its disk was disconnected. Reconnect it and reopen.")
        }
    }

    // MARK: The latch, and the reopen (2026-10-30)

    /// The old mapping is dead whatever the disk says once it was found gone, so
    /// the reader never reads through it again: it maps the file anew from its
    /// path. Here the file is gone with the disk and comes back with other
    /// pixels: the reads while it is away refuse, and the first read after it is
    /// back returns the NEW file's pixels, which only a fresh mapping can give.
    /// (Until 2026-10-30 every later read refused until the user reopened the
    /// dataset.)
    func testAReconnectedDiskReadsAgainThroughAFreshMapping() async throws {
        let disk = Disk([true, false])            // alive, then gone; the reopen's check answers alive below
        let path = try writeCube()
        let reader = try await DM4Reader(path: path, liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        let before = try await reader.readPattern(view, ry: 0, rx: 0)                         // question 1: alive
        XCTAssertEqual(before, [0, 1, 2, 3, 4, 5])
        try FileManager.default.removeItem(atPath: path)
        // Question 2 finds the disk gone; the file cannot be mapped again, so the read refuses.
        await requireGone({ _ = try await reader.readPattern(view, ry: 0, rx: 0) }, "the read that finds it gone")
        await requireGone({ _ = try await reader.readScanRow(view, ry: 1) }, "readScanRow while the file is away")
        // The disk is back, with the file at its path.
        _ = try writeCube(base: 100)
        disk.answerFromNowOn(true)
        let after = try await reader.readPattern(view, ry: 1, rx: 1)
        XCTAssertEqual(after, [118, 119, 120, 121, 122, 123], "the first read after the reconnect maps the file again")
        let tile = try await reader.readScanTile(view, yRange: 0..<2)
        XCTAssertEqual(tile.pixels, (100..<124).map(Float.init))
    }

    /// The disk answers "here" again but the reopened descriptor still says
    /// gone: the reader keeps refusing and never touches the old mapping.
    func testAReopenWhoseDiskStillAnswersGoneKeepsRefusing() async throws {
        let disk = Disk([true, false])            // alive once, gone ever after (the reopen asks too)
        let reader = try await DM4Reader(path: try writeCube(), liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        _ = try await reader.readPattern(view, ry: 0, rx: 0)
        await requireGone({ _ = try await reader.readPattern(view, ry: 0, rx: 0) }, "readPattern")
        await requireGone({ _ = try await reader.readScanRow(view, ry: 1) }, "readScanRow")
        await requireGone({ _ = try await reader.readScanTile(view, yRange: 0..<2) }, "readScanTile")
    }

    /// A file of another shape at the path is not the dataset that was opened:
    /// the reopen refuses it rather than read its pixels as this one's.
    func testAReopenRefusesAFileOfAnotherShapeAtThePath() async throws {
        let disk = Disk([true, false])
        let path = try writeCube()
        let reader = try await DM4Reader(path: path, liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        _ = try await reader.readPattern(view, ry: 0, rx: 0)
        try FileManager.default.removeItem(atPath: path)
        await requireGone({ _ = try await reader.readPattern(view, ry: 0, rx: 0) }, "the read that finds it gone")
        _ = try writeCube(scanY: 3)
        disk.answerFromNowOn(true)
        do {
            _ = try await reader.readPattern(view, ry: 0, rx: 0)
            XCTFail("a file of another shape must not be read as the opened dataset")
        } catch DM4Error.cannotOpen(let detail) {
            XCTAssertTrue(detail.hasPrefix("cube.dm4 — the file at its path is no longer the dataset that was opened"), detail)
        }
    }

    // MARK: One check per public read

    /// Not per decode, and not once more by an internal helper: a tile is many
    /// decodes and the check is a syscall.
    func testEachPublicReadAsksTheDiskExactlyOnce() async throws {
        let disk = Disk([true])
        let reader = try await DM4Reader(path: try writeCube(), liveness: disk.liveness)
        let ds = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: ds)
        XCTAssertEqual(disk.questions, 0, "opening asks nothing")
        _ = try await reader.readPattern(view, ry: 0, rx: 0)
        XCTAssertEqual(disk.questions, 1, "readPattern")
        _ = try await reader.readScanRow(view, ry: 0)
        XCTAssertEqual(disk.questions, 2, "readScanRow")
        _ = try await reader.readScanTile(view, yRange: 0..<2)
        XCTAssertEqual(disk.questions, 3, "readScanTile")
    }
}
