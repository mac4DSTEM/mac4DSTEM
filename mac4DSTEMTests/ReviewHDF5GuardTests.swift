//
//  ReviewHDF5GuardTests.swift
//  Slot 4¾ review, lane K (2026-10-02): the sidecar's calibration readers
//  (`readDoubleDataset` / `readBoolDataset` / `readStringDataset` in
//  BraggVectorEMDWriter.swift) handed `H5Dread` ONE stack value and it wrote
//  the WHOLE dataset there — the stack twin of the Qshape overrun CR3 closed.
//  A real sidecar is written by the app's writer, one calibration dataset is
//  then replaced with the same bundled libhdf5, and `loadSession` must refuse
//  it by name. The quit barrier (HDF5Types.swift) cannot be an XCTest — exit
//  ends the host — and is gated by tools/hdf5-exit-race-test.
//

import XCTest
import MachO
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class ReviewHDF5GuardTests: XCTestCase {

    private var directory: URL!
    private var sidecar: URL!

    private let written = PixelCalibration(rSize: 1.2, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: true,
                                           ellipseA: 1.01, ellipseB: 0.99, ellipseTheta: 0.2)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-hdf5-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: directory.appendingPathComponent("cube.h5").path)
        try BraggVectorEMDWriter.mergeCalibration(written, qWidth: 64, qHeight: 64, to: sidecar)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func assertRefused(naming name: String, because reason: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BraggVectorEMDWriter.loadSession(from: sidecar), file: file, line: line) { error in
            guard case BraggVectorEMDWriter.WriterError.hdf5(let detail) = error else {
                return XCTFail("expected WriterError.hdf5, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(detail.contains("dataset \(name),") && detail.contains(reason),
                          "refusal does not name \(name) / \(reason): \(detail)", file: file, line: line)
        }
    }

    /// The app's own sidecar — scalar numbers, variable-length strings — still restores exactly.
    /// Mutation it catches: the one-element check written as "rank 1" (`ndims == 1`), which refuses every scalar.
    func testTheAppsOwnCalibrationStillRestores() throws {
        let calibration = try XCTUnwrap(try BraggVectorEMDWriter.loadSession(from: sidecar).calibration)
        XCTAssertEqual(calibration.rSize, 1.2)
        XCTAssertEqual(calibration.rUnits, "nm")
        XCTAssertEqual(calibration.qUnits, "A^-1")
        XCTAssertEqual(calibration.qrFlip, true)
        XCTAssertNotNil(calibration.ellipseA)
    }

    /// The reviewer's case: a 3-element `a` (24 bytes into one 8-byte Double).
    /// Mutation it catches: `requireOneElement` removed / returning early.
    func testAThreeElementDoubleIsRefusedByName() throws {
        try CalibrationDatasetPatcher.replace("a", with: .doubles([1.01, 1.02, 1.03]), in: sidecar)
        assertRefused(naming: "a", because: "exactly one value")
    }

    /// Mutation it catches: the same check removed (QR_flip reads three values into one Bool).
    func testAThreeElementFlagIsRefusedByName() throws {
        try CalibrationDatasetPatcher.replace("QR_flip", with: .doubles([1, 0, 1]), in: sidecar)
        assertRefused(naming: "QR_flip", because: "exactly one value")
    }

    /// An empty dataset — shape (0,), or a NULL dataspace (h5py.Empty, rank 0 like a scalar) — reads nothing and
    /// would leave the default 0: a fabricated pixel size.
    /// Mutations it catches: the check weakened to "at most one value" (`<= 1`); the count taken from rank and dims
    /// (`elementCount`, where rank 0 means 1) instead of HDF5's own point count.
    func testAnEmptyDoubleIsRefusedByName() throws {
        try CalibrationDatasetPatcher.replace("R_pixel_size", with: .doubles([]), in: sidecar)
        assertRefused(naming: "R_pixel_size", because: "exactly one value")
        try CalibrationDatasetPatcher.replace("R_pixel_size", with: .nullDataspace, in: sidecar)
        assertRefused(naming: "R_pixel_size", because: "exactly one value")
    }

    /// Mutation it catches: the string reader's element check removed — three 8-byte strings land in one pointer.
    func testThreeStringsAreRefusedByName() throws {
        try CalibrationDatasetPatcher.replace("R_pixel_units", with: .fixedStrings(["abcdefg", "hijklmn", "opqrstu"], size: 8),
                                              in: sidecar)
        assertRefused(naming: "R_pixel_units", because: "exactly one value")
    }

    /// A number where a unit belongs is read in the file's own type: its 8 bytes would become the string's address.
    /// Mutation it catches: the variable-length-string check removed.
    func testANumberWhereAUnitBelongsIsRefusedByName() throws {
        try CalibrationDatasetPatcher.replace("Q_pixel_units", with: .doubles([2.5]), in: sidecar)
        assertRefused(naming: "Q_pixel_units", because: "variable-length string")
    }

    /// One fixed-length string longer than a pointer (h5py's `np.bytes_`) would overrun it.
    /// Mutation it catches: the variable-length-string check removed.
    func testAFixedLengthUnitStringIsRefusedByName() throws {
        try CalibrationDatasetPatcher.replace("R_pixel_units", with: .fixedStrings(["nanometres-long"], size: 16),
                                              in: sidecar)
        assertRefused(naming: "R_pixel_units", because: "variable-length string")
    }
}

/// Replaces one dataset of a sidecar's calibration group with the bundled
/// libhdf5 the writer already loaded (found through dyld, so the process holds
/// one copy of the non-thread-safe library), under `HDF5Serial`.
private enum CalibrationDatasetPatcher {
    enum Value {
        case doubles([Double])                       // rank 1 unless exactly one value (then scalar)
        case fixedStrings([String], size: Int)       // rank 1 unless exactly one string (then scalar)
        case nullDataspace                           // a double dataset with an H5S_NULL dataspace, nothing written
    }

    private typealias Open = @convention(c) () -> Int32
    private typealias FOpen = @convention(c) (UnsafePointer<CChar>?, UInt32, Int64) -> Int64
    private typealias GOpen = @convention(c) (Int64, UnsafePointer<CChar>?, Int64) -> Int64
    private typealias Close = @convention(c) (Int64) -> Int32
    private typealias LDelete = @convention(c) (Int64, UnsafePointer<CChar>?, Int64) -> Int32
    private typealias TCopy = @convention(c) (Int64) -> Int64
    private typealias TSetSize = @convention(c) (Int64, Int) -> Int32
    private typealias SCreate = @convention(c) (Int32) -> Int64
    private typealias SCreateSimple = @convention(c) (Int32, UnsafePointer<UInt64>?, UnsafePointer<UInt64>?) -> Int64
    private typealias DCreate = @convention(c) (Int64, UnsafePointer<CChar>?, Int64, Int64, Int64, Int64, Int64) -> Int64
    private typealias DWrite = @convention(c) (Int64, Int64, Int64, Int64, Int64, UnsafeRawPointer?) -> Int32

    struct Failure: Error, CustomStringConvertible { let description: String }

    static func replace(_ name: String, with value: Value, in url: URL) throws {
        HDF5Serial.acquire(); defer { HDF5Serial.release() }
        let handle = try loadedLibrary()
        func symbol<T>(_ symbolName: String, _ type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, symbolName) else { throw Failure(description: "missing \(symbolName)") }
            return unsafeBitCast(pointer, to: type)
        }
        func global(_ symbolName: String) throws -> Int64 {
            guard let pointer = dlsym(handle, symbolName) else { throw Failure(description: "missing \(symbolName)") }
            return pointer.assumingMemoryBound(to: Int64.self).pointee
        }
        _ = try symbol("H5open", Open.self)()
        let fOpen = try symbol("H5Fopen", FOpen.self), fClose = try symbol("H5Fclose", Close.self)
        let gOpen = try symbol("H5Gopen2", GOpen.self), gClose = try symbol("H5Gclose", Close.self)
        let lDelete = try symbol("H5Ldelete", LDelete.self)
        let tCopy = try symbol("H5Tcopy", TCopy.self), tSetSize = try symbol("H5Tset_size", TSetSize.self)
        let tClose = try symbol("H5Tclose", Close.self)
        let sCreate = try symbol("H5Screate", SCreate.self), sClose = try symbol("H5Sclose", Close.self)
        let sCreateSimple = try symbol("H5Screate_simple", SCreateSimple.self)
        let dCreate = try symbol("H5Dcreate2", DCreate.self), dWrite = try symbol("H5Dwrite", DWrite.self)
        let dClose = try symbol("H5Dclose", Close.self)

        let file = url.path.withCString { fOpen($0, 0x0001, 0) }   // H5F_ACC_RDWR
        guard file >= 0 else { throw Failure(description: "H5Fopen") }
        defer { _ = fClose(file) }
        let group = "/\(SessionSidecarFormat.rootGroupName)/metadatabundle/calibration".withCString { gOpen(file, $0, 0) }
        guard group >= 0 else { throw Failure(description: "H5Gopen2") }
        defer { _ = gClose(group) }
        guard name.withCString({ lDelete(group, $0, 0) }) >= 0 else { throw Failure(description: "H5Ldelete \(name)") }

        let type: Int64
        let bytes: [UInt8]
        let count: Int
        var null = false
        switch value {
        case .nullDataspace:
            type = tCopy(try global("H5T_NATIVE_DOUBLE_g"))
            bytes = []
            count = 0
            null = true
        case .doubles(let numbers):
            type = tCopy(try global("H5T_NATIVE_DOUBLE_g"))
            bytes = numbers.withUnsafeBytes { Array($0) }
            count = numbers.count
        case .fixedStrings(let strings, let size):
            type = tCopy(try global("H5T_C_S1_g"))
            _ = tSetSize(type, size)
            bytes = strings.flatMap { string -> [UInt8] in
                let utf8 = Array(string.utf8.prefix(size))
                return utf8 + [UInt8](repeating: 0, count: size - utf8.count)
            }
            count = strings.count
        }
        let dims = [UInt64(count)]
        let space = null ? sCreate(2) : count == 1 ? sCreate(0) : sCreateSimple(1, dims, nil)   // 2 NULL, 0 SCALAR
        guard type >= 0, space >= 0 else { throw Failure(description: "type/space") }
        defer { _ = tClose(type); _ = sClose(space) }
        let dataset = name.withCString { dCreate(group, $0, type, space, 0, 0, 0) }
        guard dataset >= 0 else { throw Failure(description: "H5Dcreate2 \(name)") }
        defer { _ = dClose(dataset) }
        guard count == 0 || bytes.withUnsafeBytes({ dWrite(dataset, type, 0, 0, 0, $0.baseAddress) }) >= 0 else {
            throw Failure(description: "H5Dwrite \(name)")
        }
    }

    /// The libhdf5 image already mapped into this process by the writer.
    private static func loadedLibrary() throws -> UnsafeMutableRawPointer {
        for index in 0..<_dyld_image_count() {
            guard let cName = _dyld_get_image_name(index) else { continue }
            let path = String(cString: cName)
            guard (path as NSString).lastPathComponent.hasPrefix("libhdf5"), path.hasSuffix(".dylib"),
                  let handle = dlopen(path, RTLD_NOW | RTLD_NOLOAD), dlsym(handle, "H5Fopen") != nil else { continue }
            return handle
        }
        throw Failure(description: "libhdf5 is not loaded — the writer must run first")
    }
}
