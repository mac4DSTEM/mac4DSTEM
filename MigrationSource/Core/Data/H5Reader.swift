//
//  H5Reader.swift
//  Role: All HDF5 file access. Opens a file, finds the 4D datacube, reads
//        its shape/dtype/chunking, and reads data in HYPERSLABS (a single
//        CBED pattern, or one scan row) — never the whole cube in one call.
//
//  This is an `actor`, so every method is serialized and runs off the main
//  thread. HDF5's C library is not thread-safe by default, so funnelling all
//  access through one actor is both an architecture win and a correctness win.
//
//  ── HDF5 + Swift gotchas handled here ────────────────────────────────────
//  1. Macros like H5F_ACC_RDONLY / H5P_DEFAULT / H5S_ALL don't import into
//     Swift. We redefine the simple integer ones below.
//  2. H5T_NATIVE_FLOAT is a macro wrapping a global (H5T_NATIVE_FLOAT_g) that
//     is only valid after the library is initialized. We call H5open() once
//     and then use the *_g globals directly.
//  3. Functions like H5Ovisit/H5Lexists have version-suffixed variants across
//     HDF5 releases, which makes file-tree walking fragile from Swift. So we
//     locate the cube by *trying known dataset paths* (py4DSTEM + HyperSpy
//     conventions) plus a user-supplied path. Full recursive discovery is a
//     later enhancement.
//

import Foundation

// MARK: - HDF5 constants that don't import from macros

private let kRDONLY: UInt32 = 0x0000          // H5F_ACC_RDONLY
private let kDEFAULT: hid_t = 0               // H5P_DEFAULT
private let kSELECT_SET = H5S_SELECT_SET      // this enum *does* import

// MARK: - Errors

enum H5Error: LocalizedError {
    case cannotOpenFile(String)
    case noDatasetFound([String])
    case datasetOpenFailed(String)
    case readFailed(String)
    case unsupportedRank(Int)

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let p): return "Could not open HDF5 file at \(p). Is it a valid .h5 file?"
        case .noDatasetFound(let tried):
            return "No 4D/3D dataset found. Tried paths:\n• " + tried.joined(separator: "\n• ")
                 + "\nYou can enter the dataset path manually in the sidebar."
        case .datasetOpenFailed(let p): return "Failed to open dataset at HDF5 path \(p)."
        case .readFailed(let what): return "HDF5 read failed: \(what)."
        case .unsupportedRank(let r): return "Dataset rank \(r) is not supported (need 3 or 4)."
        }
    }
}

// MARK: - H5Reader

actor H5Reader {

    private let fileID: hid_t
    let filePath: String

    /// Candidate dataset paths, tried in order. Covers common py4DSTEM and
    /// HyperSpy layouts. Extend freely.
    static let candidatePaths: [String] = [
        "/4DSTEM_experiment/data/datacubes/datacube_0/data",   // py4DSTEM (legacy EMD)
        "/4DSTEM/data/datacubes/datacube_root/data",           // py4DSTEM (EMD 1.0-ish)
        "/datacube_root/datacube/data",
        "/Experiments/__unnamed__/data",                       // HyperSpy
        "/Experiments/__unnamed__/data/data",
    ]

    // MARK: Lifecycle

    /// Open a file read-only. Throws if the file can't be opened.
    init(path: String) throws {
        // Ensure the library + its native type globals are initialized.
        H5open()
        let fid = path.withCString { H5Fopen($0, kRDONLY, kDEFAULT) }
        guard fid >= 0 else { throw H5Error.cannotOpenFile(path) }
        self.fileID = fid
        self.filePath = path
    }

    deinit {
        if fileID >= 0 { H5Fclose(fileID) }
    }

    // MARK: Discovery

    /// Find the first candidate path that opens as a 3D/4D dataset and
    /// return its descriptor.
    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        for path in Self.candidatePaths {
            if let d = try? describe(path: path), d.shape.count == 3 || d.shape.count == 4 {
                return d
            }
        }
        throw H5Error.noDatasetFound(Self.candidatePaths)
    }

    /// Build a descriptor for a known dataset path (used by discovery and by
    /// the manual "dataset path" field in the UI).
    func describe(path: String) throws -> DatasetDescriptor {
        let dset = path.withCString { H5Dopen2(fileID, $0, kDEFAULT) }
        guard dset >= 0 else { throw H5Error.datasetOpenFailed(path) }
        defer { H5Dclose(dset) }

        // Shape
        let space = H5Dget_space(dset)
        defer { H5Sclose(space) }
        let rank = Int(H5Sget_simple_extent_ndims(space))
        guard rank == 3 || rank == 4 else { throw H5Error.unsupportedRank(rank) }
        var dims = [hsize_t](repeating: 0, count: rank)
        _ = dims.withUnsafeMutableBufferPointer { H5Sget_simple_extent_dims(space, $0.baseAddress, nil) }
        // A 3D dataset is treated as a flattened scan: [Rscan, Qy, Qx].
        // We promote it to 4D as [1, Rscan, Qy, Qx] so the rest of the app
        // can assume 4D. (Refine later if you need true 3D handling.)
        var shape = dims.map(Int.init)
        if rank == 3 { shape = [1, shape[0], shape[1], shape[2]] }

        // Dtype
        let dtype = H5Dget_type(dset)
        defer { H5Tclose(dtype) }
        let dtypeStr = Self.describeType(dtype)

        // Chunking
        var chunk: [Int]? = nil
        let plist = H5Dget_create_plist(dset)
        defer { H5Pclose(plist) }
        if H5Pget_layout(plist) == H5D_CHUNKED {
            var cdims = [hsize_t](repeating: 0, count: rank)
            let n = cdims.withUnsafeMutableBufferPointer { Int(H5Pget_chunk(plist, Int32(rank), $0.baseAddress)) }
            if n > 0 { chunk = cdims.prefix(n).map(Int.init) }
        }

        return DatasetDescriptor(filePath: filePath,
                                 datasetPath: path,
                                 shape: shape,
                                 dtypeDescription: dtypeStr,
                                 chunkShape: chunk)
    }

    private static func describeType(_ dtype: hid_t) -> String {
        let cls = H5Tget_class(dtype)
        let size = H5Tget_size(dtype)   // bytes
        switch cls {
        case H5T_FLOAT:   return "float\(size * 8)"
        case H5T_INTEGER:
            let signed = H5Tget_sign(dtype) == H5T_SGN_2
            return "\(signed ? "int" : "uint")\(size * 8)"
        default:          return "class \(cls.rawValue), \(size) bytes"
        }
    }

    // MARK: Hyperslab reads

    /// Read a single CBED pattern [Qy, Qx] at scan position (ry, rx).
    /// Always returned as Float32 — HDF5 converts on read if the stored type
    /// differs (we ask for H5T_NATIVE_FLOAT).
    func readPattern(_ d: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float] {
        let dset = d.datasetPath.withCString { H5Dopen2(fileID, $0, kDEFAULT) }
        guard dset >= 0 else { throw H5Error.datasetOpenFailed(d.datasetPath) }
        defer { H5Dclose(dset) }

        let filespace = H5Dget_space(dset)
        defer { H5Sclose(filespace) }

        var start: [hsize_t] = [hsize_t(ry), hsize_t(rx), 0, 0]
        var count: [hsize_t] = [1, 1, hsize_t(d.qy), hsize_t(d.qx)]
        let sel = start.withUnsafeMutableBufferPointer { s in
            count.withUnsafeMutableBufferPointer { c in
                H5Sselect_hyperslab(filespace, kSELECT_SET, s.baseAddress, nil, c.baseAddress, nil)
            }
        }
        guard sel >= 0 else { throw H5Error.readFailed("hyperslab select (pattern)") }

        var memdims: [hsize_t] = [hsize_t(d.qy), hsize_t(d.qx)]
        let memspace = memdims.withUnsafeMutableBufferPointer { H5Screate_simple(2, $0.baseAddress, nil) }
        defer { H5Sclose(memspace) }

        var buffer = [Float](repeating: 0, count: d.qy * d.qx)
        let status = buffer.withUnsafeMutableBytes {
            H5Dread(dset, H5T_NATIVE_FLOAT_g, memspace, filespace, kDEFAULT, $0.baseAddress)
        }
        guard status >= 0 else { throw H5Error.readFailed("pattern (\(ry),\(rx))") }
        return buffer
    }

    /// Read an entire scan row: all Rx patterns for a fixed Ry, flattened as
    /// [Rx * Qy * Qx]. This is the chunk-friendly unit used to stream the cube.
    func readScanRow(_ d: DatasetDescriptor, ry: Int) throws -> [Float] {
        let dset = d.datasetPath.withCString { H5Dopen2(fileID, $0, kDEFAULT) }
        guard dset >= 0 else { throw H5Error.datasetOpenFailed(d.datasetPath) }
        defer { H5Dclose(dset) }

        let filespace = H5Dget_space(dset)
        defer { H5Sclose(filespace) }

        var start: [hsize_t] = [hsize_t(ry), 0, 0, 0]
        var count: [hsize_t] = [1, hsize_t(d.rx), hsize_t(d.qy), hsize_t(d.qx)]
        let sel = start.withUnsafeMutableBufferPointer { s in
            count.withUnsafeMutableBufferPointer { c in
                H5Sselect_hyperslab(filespace, kSELECT_SET, s.baseAddress, nil, c.baseAddress, nil)
            }
        }
        guard sel >= 0 else { throw H5Error.readFailed("hyperslab select (row)") }

        var memdims: [hsize_t] = [hsize_t(d.rx), hsize_t(d.qy), hsize_t(d.qx)]
        let memspace = memdims.withUnsafeMutableBufferPointer { H5Screate_simple(3, $0.baseAddress, nil) }
        defer { H5Sclose(memspace) }

        var buffer = [Float](repeating: 0, count: d.rx * d.qy * d.qx)
        let status = buffer.withUnsafeMutableBytes {
            H5Dread(dset, H5T_NATIVE_FLOAT_g, memspace, filespace, kDEFAULT, $0.baseAddress)
        }
        guard status >= 0 else { throw H5Error.readFailed("row \(ry)") }
        return buffer
    }

    // MARK: Optional scalar/attr helpers (best-effort, return nil on miss)

    /// Read a float attribute attached to the file root or a path. Returns nil
    /// if absent. Used to populate the inspector (e.g. accelerating voltage).
    func readDoubleAttribute(_ name: String, onObjectPath path: String = "/") -> Double? {
        let obj = path.withCString { H5Oopen(fileID, $0, kDEFAULT) }
        guard obj >= 0 else { return nil }
        defer { H5Oclose(obj) }
        let attr = name.withCString { H5Aopen(obj, $0, kDEFAULT) }
        guard attr >= 0 else { return nil }
        defer { H5Aclose(attr) }
        var value: Double = 0
        let status = withUnsafeMutableBytes(of: &value) {
            H5Aread(attr, H5T_NATIVE_DOUBLE_g, $0.baseAddress)
        }
        return status >= 0 ? value : nil
    }
}
