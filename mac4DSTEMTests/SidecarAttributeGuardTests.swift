//
//  SidecarAttributeGuardTests.swift
//  S5 — the sidecar reader's attribute guard, D003's twin.
//
//  `BraggVectorEMDWriter.readStringAttribute` handed `H5Aread` one `char *`
//  (8 bytes) for whatever the attribute held. `H5Aread` writes the WHOLE
//  attribute and reports success when it overruns (D003, 2026-09-09: 24 bytes
//  into 8), so a sidecar attribute of the wrong shape or type corrupted the
//  stack and then dereferenced a garbage pointer. These tests write such
//  attributes into a real sidecar with the same bundled libhdf5 the writer
//  loaded, then read them back through the writer's public entry points.
//
//  Break-first: every case below crashes or fails on the pre-S5 reader.
//

import XCTest
import MachO
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SidecarAttributeGuardTests: XCTestCase {

    private var directory: URL!
    private var sidecar: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s5-attribute-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sidecar = BraggVectorEMDWriter.sessionSidecarURL(
            forSourcePath: directory.appendingPathComponent("cube.h5").path
        )
        // A real sidecar, written by the writer — which also dlopens the
        // library the patcher below reuses.
        try BraggVectorEMDWriter.mergeCalibration(
            PixelCalibration(), qWidth: 64, qHeight: 64, to: sidecar
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let labels = "mac4dstem_disk_centre_labels"

    /// Mutation it catches: delete the `elementCount == 1` guard. The reader
    /// then reads 3 × 8 bytes into one 8-byte pointer — the D003 overrun.
    func testAMultiElementAttributeRefusesByName() throws {
        try SidecarPatcher.write(
            .fixedStrings(["abcdefg", "hijklmn", "opqrstu"], size: 8),
            named: labels, into: sidecar
        )
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: sidecar)) { error in
            guard case BraggVectorEMDWriter.WriterError.malformedAttribute(let name) = error else {
                return XCTFail("Expected malformedAttribute, got \(error)")
            }
            XCTAssertEqual(name, self.labels)
        }
    }

    /// Mutation it catches: delete the string-class check. A scalar double
    /// then reads through the fixed-length branch as garbage text instead of
    /// refusing.
    func testANonStringAttributeRefusesByName() throws {
        try SidecarPatcher.write(.double(2.5), named: labels, into: sidecar)
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: sidecar)) { error in
            guard case BraggVectorEMDWriter.WriterError.malformedAttribute = error else {
                return XCTFail("Expected malformedAttribute, got \(error)")
            }
        }
    }

    /// A scalar FIXED-length string (h5py's `np.bytes_`) is a legitimate
    /// encoding and must read back exactly. Mutation it catches: delete the
    /// fixed-length branch — the 23 bytes land in the 8-byte pointer, as
    /// before S5.
    func testAScalarFixedLengthStringReadsBackExactly() throws {
        let json = #"{"centres":[[1,2]]}"#   // 19 characters, longer than a pointer
        try SidecarPatcher.write(.fixedStrings([json], size: 23), named: labels, into: sidecar)
        XCTAssertEqual(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: sidecar), json)
    }

    /// The minimum-reader marker keeps its documented rule — an unparseable
    /// marker reads as absent, never as a refusal that bricks the file.
    /// Mutation it catches: drop `enforceMinimumReader`'s
    /// `catch WriterError.malformedAttribute` — the whole read then throws.
    func testAMalformedMinimumReaderMarkerReadsAsAbsent() throws {
        try SidecarPatcher.write(
            .fixedStrings(["5", "6", "7"], size: 2),
            named: SessionSidecarFormat.minimumReaderAttribute, into: sidecar
        )
        XCTAssertNil(try BraggVectorEMDWriter.loadDiskCentreLabelsJSON(from: sidecar))
        XCTAssertNoThrow(try BraggVectorEMDWriter.loadSession(from: sidecar))
    }
}

/// Writes one attribute onto a sidecar's session root with the bundled
/// libhdf5 — the image the writer already loaded, found through dyld, so the
/// process holds one copy of the (non-thread-safe) library.
private enum SidecarPatcher {
    enum Value {
        case fixedStrings([String], size: Int)
        case double(Double)
    }

    private typealias Open = @convention(c) () -> Int32
    private typealias FOpen = @convention(c) (UnsafePointer<CChar>?, UInt32, Int64) -> Int64
    private typealias GOpen = @convention(c) (Int64, UnsafePointer<CChar>?, Int64) -> Int64
    private typealias Close = @convention(c) (Int64) -> Int32
    private typealias TCopy = @convention(c) (Int64) -> Int64
    private typealias TSetSize = @convention(c) (Int64, Int) -> Int32
    private typealias SCreate = @convention(c) (Int32) -> Int64
    private typealias SCreateSimple = @convention(c) (Int32, UnsafePointer<UInt64>?, UnsafePointer<UInt64>?) -> Int64
    private typealias ACreate = @convention(c) (Int64, UnsafePointer<CChar>?, Int64, Int64, Int64, Int64) -> Int64
    private typealias AWrite = @convention(c) (Int64, Int64, UnsafeRawPointer?) -> Int32
    private typealias AExists = @convention(c) (Int64, UnsafePointer<CChar>?) -> Int32
    private typealias ADelete = @convention(c) (Int64, UnsafePointer<CChar>?) -> Int32

    struct Failure: Error, CustomStringConvertible { let description: String }

    static func write(_ value: Value, named name: String, into url: URL) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        let handle = try loadedLibrary()
        func symbol<T>(_ symbolName: String, _ type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, symbolName) else {
                throw Failure(description: "missing \(symbolName)")
            }
            return unsafeBitCast(pointer, to: type)
        }
        func global(_ symbolName: String) throws -> Int64 {
            guard let pointer = dlsym(handle, symbolName) else {
                throw Failure(description: "missing \(symbolName)")
            }
            return pointer.assumingMemoryBound(to: Int64.self).pointee
        }
        _ = try symbol("H5open", Open.self)()
        let fOpen = try symbol("H5Fopen", FOpen.self)
        let fClose = try symbol("H5Fclose", Close.self)
        let gOpen = try symbol("H5Gopen2", GOpen.self)
        let gClose = try symbol("H5Gclose", Close.self)
        let tCopy = try symbol("H5Tcopy", TCopy.self)
        let tSetSize = try symbol("H5Tset_size", TSetSize.self)
        let tClose = try symbol("H5Tclose", Close.self)
        let sCreate = try symbol("H5Screate", SCreate.self)
        let sCreateSimple = try symbol("H5Screate_simple", SCreateSimple.self)
        let sClose = try symbol("H5Sclose", Close.self)
        let aCreate = try symbol("H5Acreate2", ACreate.self)
        let aWrite = try symbol("H5Awrite", AWrite.self)
        let aClose = try symbol("H5Aclose", Close.self)
        let aExists = try symbol("H5Aexists", AExists.self)
        let aDelete = try symbol("H5Adelete", ADelete.self)

        let readWrite: UInt32 = 0x0001   // H5F_ACC_RDWR
        let file = url.path.withCString { fOpen($0, readWrite, 0) }
        guard file >= 0 else { throw Failure(description: "H5Fopen") }
        defer { _ = fClose(file) }
        let root = ("/" + SessionSidecarFormat.rootGroupName).withCString { gOpen(file, $0, 0) }
        guard root >= 0 else { throw Failure(description: "H5Gopen2") }
        defer { _ = gClose(root) }
        if name.withCString({ aExists(root, $0) }) > 0 {
            guard name.withCString({ aDelete(root, $0) }) >= 0 else {
                throw Failure(description: "H5Adelete")
            }
        }

        let type: Int64
        let space: Int64
        let bytes: [UInt8]
        switch value {
        case .fixedStrings(let strings, let size):
            type = try tCopy(global("H5T_C_S1_g"))
            _ = tSetSize(type, size)
            bytes = strings.flatMap { string -> [UInt8] in
                let utf8 = Array(string.utf8.prefix(size))
                return utf8 + [UInt8](repeating: 0, count: size - utf8.count)
            }
            if strings.count == 1 {
                space = sCreate(0)   // H5S_SCALAR
            } else {
                let dims = [UInt64(strings.count)]
                space = sCreateSimple(1, dims, nil)
            }
        case .double(let number):
            type = try tCopy(global("H5T_NATIVE_DOUBLE_g"))
            bytes = withUnsafeBytes(of: number) { Array($0) }
            space = sCreate(0)
        }
        guard type >= 0, space >= 0 else { throw Failure(description: "type/space") }
        defer { _ = tClose(type); _ = sClose(space) }
        let attribute = name.withCString { aCreate(root, $0, type, space, 0, 0) }
        guard attribute >= 0 else { throw Failure(description: "H5Acreate2") }
        defer { _ = aClose(attribute) }
        guard bytes.withUnsafeBytes({ aWrite(attribute, type, $0.baseAddress) }) >= 0 else {
            throw Failure(description: "H5Awrite")
        }
    }

    /// The libhdf5 image already mapped into this process by the writer.
    private static func loadedLibrary() throws -> UnsafeMutableRawPointer {
        for index in 0..<_dyld_image_count() {
            guard let cName = _dyld_get_image_name(index) else { continue }
            let path = String(cString: cName)
            // `libhdf5_hl` shares the prefix; the H5Fopen probe skips it.
            guard (path as NSString).lastPathComponent.hasPrefix("libhdf5"),
                  path.hasSuffix(".dylib"),
                  let handle = dlopen(path, RTLD_NOW | RTLD_NOLOAD),
                  dlsym(handle, "H5Fopen") != nil else { continue }
            return handle
        }
        throw Failure(description: "libhdf5 is not loaded — the writer must run first")
    }
}
