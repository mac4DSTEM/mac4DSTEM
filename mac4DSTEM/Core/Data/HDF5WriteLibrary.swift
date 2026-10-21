import Darwin
import Foundation
import FormatoHDF5
import SpectroCore


// MARK: - HDF5 dynamic binding
//
// delete at FormatoKit <next>: the session-sidecar WRITER (this binding, HDF5WritePrimitives.swift, SessionSidecarWriting.swift and
// `BraggVectorEMDWriter.publish` / `temporaryPublishURL`) is not switched in the 0.7.0 round. FormatoKit 0.7.0 has the pieces: `HDF5NewFile.write`
// (item-replacement scratch and an atomic publish, so `temporaryPublishURL` goes), `writeEMDFileHeader` / `createEMDRoot` /
// `writeEMDCalibration` / `writeEMDScalarMap` / `writeEMDRGBAMap`, `writeText` / `writeBool` / `setVariableLengthTextAttribute`,
// `copyObject(from:_:to:replace:)` for the carried-over objects, and `BraggVectorsEMD.write` for the variable-length peak grid (its
// sandbox fix is that item-replacement build). What is left is not a drop-in: `writeFile` is one function that holds the new file's
// handle, an `H5Ocopy` handle on the file it replaces and the app's `mac4dstem_*` attributes in a fixed order, so it has to be
// rewritten onto a session, and its output compared object by object (every dataset's bytes, every attribute, link order) with the
// former writer's over the sidecar variants (`tools/harnesses/sidecar-result-test`, the sidecar-parity gate). `write(vectors:)` has
// no production caller, so it is not the place to start.

nonisolated let h5DefaultProperty: hid_t = 0
nonisolated let h5EntireDataspace: hid_t = 0
nonisolated let h5FileTruncate: UInt32 = 0x0002
nonisolated let h5FileReadOnly: UInt32 = 0x0000
nonisolated let h5ScalarDataspace: Int32 = 0
nonisolated let h5CompoundClass: Int32 = 6
nonisolated let h5StringClass: Int32 = 3
nonisolated let h5UTF8CharacterSet: Int32 = 1
nonisolated let h5SelectSet: Int32 = 0
nonisolated let h5IndexByName: Int32 = 0
nonisolated let h5IterationIncreasing: Int32 = 0

nonisolated struct EMDPeakRecord {
    package var qx: Double
    package var qy: Double
    package var intensity: Double
}

nonisolated struct H5VariableLength {
    package var length: Int
    package var pointer: UnsafeMutableRawPointer?
}

nonisolated struct HDF5WriteLibrary: @unchecked Sendable {
    package typealias H5open = @convention(c) () -> herr_t
    /// `herr_t H5Eprint2(hid_t estack_id, FILE *stream)`. Optional: a library
    /// without it simply yields no detail rather than failing to load.
    package typealias H5Eprint2 = @convention(c) (hid_t, UnsafeMutablePointer<FILE>?) -> herr_t
    package typealias H5Fcreate = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t, hid_t) -> hid_t
    package typealias H5Fopen = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t) -> hid_t
    package typealias H5Fclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Gcreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t) -> hid_t
    package typealias H5Gopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    package typealias H5Gclose = @convention(c) (hid_t) -> herr_t
    package typealias H5GgetNumObjects = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?) -> herr_t
    package typealias H5Screate = @convention(c) (Int32) -> hid_t
    package typealias H5ScreateSimple = @convention(c) (Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> hid_t
    package typealias H5SselectHyperslab = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> herr_t
    package typealias H5Sclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Dcreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t, hid_t, hid_t) -> hid_t
    package typealias H5Dopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    package typealias H5DgetSpace = @convention(c) (hid_t) -> hid_t
    package typealias H5DgetType = @convention(c) (hid_t) -> hid_t
    package typealias H5Dwrite = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeRawPointer?) -> herr_t
    package typealias H5Dread = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5Dclose = @convention(c) (hid_t) -> herr_t
    package typealias H5SgetSimpleExtentNdims = @convention(c) (hid_t) -> Int32
    package typealias H5SgetSimpleExtentDims = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?, UnsafeMutablePointer<hsize_t>?) -> Int32
    package typealias H5SgetSimpleExtentNpoints = @convention(c) (hid_t) -> Int64
    package typealias H5Tcreate = @convention(c) (Int32, Int) -> hid_t
    package typealias H5Tinsert = @convention(c) (hid_t, UnsafePointer<CChar>?, Int, hid_t) -> herr_t
    package typealias H5TvlenCreate = @convention(c) (hid_t) -> hid_t
    package typealias H5Tcopy = @convention(c) (hid_t) -> hid_t
    package typealias H5TsetSize = @convention(c) (hid_t, UInt) -> herr_t
    package typealias H5TsetCset = @convention(c) (hid_t, Int32) -> herr_t
    package typealias H5Tclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Acreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t, hid_t) -> hid_t
    package typealias H5Aexists = @convention(c) (hid_t, UnsafePointer<CChar>?) -> Int32
    package typealias H5Aopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    package typealias H5AgetType = @convention(c) (hid_t) -> hid_t
    package typealias H5AgetSpace = @convention(c) (hid_t) -> hid_t
    package typealias H5TgetClass = @convention(c) (hid_t) -> Int32
    package typealias H5TgetSize = @convention(c) (hid_t) -> Int
    package typealias H5TisVariableStr = @convention(c) (hid_t) -> Int32
    package typealias H5Awrite = @convention(c) (hid_t, hid_t, UnsafeRawPointer?) -> herr_t
    package typealias H5Aread = @convention(c) (hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5Aclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Lexists = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> Int32
    package typealias H5Ocopy = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, UnsafePointer<CChar>?, hid_t, hid_t) -> herr_t
    package typealias H5freeMemory = @convention(c) (UnsafeMutableRawPointer?) -> herr_t
    package typealias H5LgetNameByIndex = @convention(c) (hid_t, UnsafePointer<CChar>?, Int32, Int32, hsize_t, UnsafeMutablePointer<CChar>?, Int, hid_t) -> Int
    package typealias H5Pcreate = @convention(c) (hid_t) -> hid_t
    package typealias H5PsetChunk = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?) -> herr_t
    package typealias H5Pclose = @convention(c) (hid_t) -> herr_t

    package let handle: UnsafeMutableRawPointer
    package let h5open: H5open
    package let h5eprint2: H5Eprint2?
    package let h5fcreate: H5Fcreate
    package let h5fopen: H5Fopen
    package let h5fclose: H5Fclose
    package let h5gcreate2: H5Gcreate2
    package let h5gopen2: H5Gopen2
    package let h5gclose: H5Gclose
    package let h5ggetNumObjects: H5GgetNumObjects
    package let h5screate: H5Screate
    package let h5screateSimple: H5ScreateSimple
    package let h5sselectHyperslab: H5SselectHyperslab
    package let h5sclose: H5Sclose
    package let h5dcreate2: H5Dcreate2
    package let h5dopen2: H5Dopen2
    package let h5dgetSpace: H5DgetSpace
    package let h5dgetType: H5DgetType
    package let h5dwrite: H5Dwrite
    package let h5dread: H5Dread
    package let h5dclose: H5Dclose
    package let h5sgetSimpleExtentNdims: H5SgetSimpleExtentNdims
    package let h5sgetSimpleExtentDims: H5SgetSimpleExtentDims
    package let h5sgetSimpleExtentNpoints: H5SgetSimpleExtentNpoints
    package let h5tcreate: H5Tcreate
    package let h5tinsert: H5Tinsert
    package let h5tvlenCreate: H5TvlenCreate
    package let h5tcopy: H5Tcopy
    package let h5tsetSize: H5TsetSize
    package let h5tsetCset: H5TsetCset
    package let h5tclose: H5Tclose
    package let h5acreate2: H5Acreate2
    package let h5aexists: H5Aexists
    package let h5aopen: H5Aopen
    package let h5agetType: H5AgetType
    package let h5agetSpace: H5AgetSpace
    package let h5tgetClass: H5TgetClass
    package let h5tgetSize: H5TgetSize
    package let h5tisVariableStr: H5TisVariableStr
    package let h5awrite: H5Awrite
    package let h5aread: H5Aread
    package let h5aclose: H5Aclose
    package let h5lexists: H5Lexists
    package let h5ocopy: H5Ocopy
    package let h5freeMemory: H5freeMemory
    package let h5lgetNameByIndex: H5LgetNameByIndex
    package let h5pcreate: H5Pcreate
    package let h5psetChunk: H5PsetChunk
    package let h5pclose: H5Pclose
    package let nativeFloat: hid_t
    package let nativeDouble: hid_t
    package let nativeInt: hid_t
    package let nativeLongLong: hid_t
    package let nativeHBool: hid_t
    package let nativeUChar: hid_t
    package let stringC1: hid_t
    package let datasetCreatePropertyClass: hid_t

    /// The thread's current HDF5 error stack, formatted, or nil if empty.
    ///
    /// `H5Reader` installs `H5Eset_auto2(H5E_DEFAULT, nil, nil)` process-wide
    /// (`H5Reader.swift:164-168`) so that the optional-path probing done during
    /// discovery does not spray native stack traces onto stderr. Turning the
    /// automatic printer off does **not** clear the stack — HDF5 still records
    /// why a call failed — so the reason has always been retrievable; nothing
    /// was reading it. Every `WriterError.hdf5` raised before 2026-08-18
    /// therefore reported *that* an open failed and never *why*, which is what
    /// left the 2026-08-18 sidecar-restore failure untriageable (S1).
    ///
    /// Must be called immediately after the failing call, with no other HDF5
    /// activity anywhere in the process in between.
    ///
    /// **Not "on the same thread" — the stack is process-GLOBAL.** The bundled
    /// build is `Threadsafety: OFF` and exports `_H5E_stack_g` as a plain
    /// `__DATA,__common` global with no thread-local storage, so a failure on
    /// one thread is visible to a capture on another (verified 2026-08-19 with
    /// a serialized two-thread probe: thread B, making no HDF5 call of its own,
    /// read thread A's failure). A successful HDF5 call clears the stack, so a
    /// stale reason cannot be picked up sequentially — only concurrently. The
    /// same global is why concurrent HDF5 use crashes rather than racing
    /// benignly; see the open item on `H5SL_search`.
    package func currentErrorStack() -> String? {
        guard let h5eprint2 else { return nil }
        var buffer: UnsafeMutablePointer<CChar>?
        var size = 0
        guard let stream = open_memstream(&buffer, &size) else { return nil }
        // H5E_DEFAULT is 0, the same numeric value as H5P_DEFAULT but a
        // different constant; spelled out here so the two do not read as one.
        _ = h5eprint2(0, stream)
        fclose(stream)
        defer { if let buffer { free(buffer) } }
        guard let buffer, size > 0 else { return nil }
        let lines = String(cString: buffer)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // HDF5 prints a frame per layer, outermost first ("unable to open
        // file"), and only the innermost frame says anything actionable —
        // `errno = 13 … 'Permission denied'` versus `file signature not found`.
        // Reporting all eight would put a wall of library internals into a
        // status line, so keep the innermost frame and its minor code.
        let innermost = lines.last { $0.hasPrefix("#") }
            .flatMap { frame -> String? in
                guard let range = frame.range(of: "): ", options: .backwards) else { return nil }
                return String(frame[range.upperBound...])
            }
        let minor = lines.last { $0.hasPrefix("minor:") }
            .map { $0.replacingOccurrences(of: "minor:", with: "").trimmingCharacters(in: .whitespaces) }

        switch (innermost, minor) {
        case let (detail?, code?): return "\(detail) [\(code)]"
        case let (detail?, nil):   return detail
        case let (nil, code?):     return code
        case (nil, nil):           return nil
        }
    }

    package static func load() throws -> HDF5WriteLibrary {
        var failures = [String]()
        var handle: UnsafeMutableRawPointer?
        for path in candidateLibraryPaths() where handle == nil {
            dlerror()
            handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if handle == nil {
                let detail = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
                failures.append("\(path): \(detail)")
            }
        }
        guard let handle else {
            throw BraggVectorEMDWriter.WriterError.libraryUnavailable(
                failures.joined(separator: "\n")
            )
        }
        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else {
                throw BraggVectorEMDWriter.WriterError.symbolMissing(name)
            }
            return unsafeBitCast(pointer, to: type)
        }
        func global<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else {
                throw BraggVectorEMDWriter.WriterError.symbolMissing(name)
            }
            return pointer.assumingMemoryBound(to: type).pointee
        }
        let h5open = try symbol("H5open", as: H5open.self)
        // After H5open, never before: HDF5 registers its own atexit teardown in there (HDF5Types.swift).
        if h5open() >= 0 { HDF5Serial.installExitBarrier() }
        // Looked up leniently: the error-stack detail is diagnostic, and losing
        // it must never turn into a failure to open a sidecar at all.
        let h5eprint2 = dlsym(handle, "H5Eprint2").map {
            unsafeBitCast($0, to: H5Eprint2.self)
        }
        return HDF5WriteLibrary(
            handle: handle,
            h5open: h5open,
            h5eprint2: h5eprint2,
            h5fcreate: try symbol("H5Fcreate", as: H5Fcreate.self),
            h5fopen: try symbol("H5Fopen", as: H5Fopen.self),
            h5fclose: try symbol("H5Fclose", as: H5Fclose.self),
            h5gcreate2: try symbol("H5Gcreate2", as: H5Gcreate2.self),
            h5gopen2: try symbol("H5Gopen2", as: H5Gopen2.self),
            h5gclose: try symbol("H5Gclose", as: H5Gclose.self),
            h5ggetNumObjects: try symbol("H5Gget_num_objs", as: H5GgetNumObjects.self),
            h5screate: try symbol("H5Screate", as: H5Screate.self),
            h5screateSimple: try symbol("H5Screate_simple", as: H5ScreateSimple.self),
            h5sselectHyperslab: try symbol("H5Sselect_hyperslab", as: H5SselectHyperslab.self),
            h5sclose: try symbol("H5Sclose", as: H5Sclose.self),
            h5dcreate2: try symbol("H5Dcreate2", as: H5Dcreate2.self),
            h5dopen2: try symbol("H5Dopen2", as: H5Dopen2.self),
            h5dgetSpace: try symbol("H5Dget_space", as: H5DgetSpace.self),
            h5dgetType: try symbol("H5Dget_type", as: H5DgetType.self),
            h5dwrite: try symbol("H5Dwrite", as: H5Dwrite.self),
            h5dread: try symbol("H5Dread", as: H5Dread.self),
            h5dclose: try symbol("H5Dclose", as: H5Dclose.self),
            h5sgetSimpleExtentNdims: try symbol("H5Sget_simple_extent_ndims", as: H5SgetSimpleExtentNdims.self),
            h5sgetSimpleExtentDims: try symbol("H5Sget_simple_extent_dims", as: H5SgetSimpleExtentDims.self),
            h5sgetSimpleExtentNpoints: try symbol("H5Sget_simple_extent_npoints", as: H5SgetSimpleExtentNpoints.self),
            h5tcreate: try symbol("H5Tcreate", as: H5Tcreate.self),
            h5tinsert: try symbol("H5Tinsert", as: H5Tinsert.self),
            h5tvlenCreate: try symbol("H5Tvlen_create", as: H5TvlenCreate.self),
            h5tcopy: try symbol("H5Tcopy", as: H5Tcopy.self),
            h5tsetSize: try symbol("H5Tset_size", as: H5TsetSize.self),
            h5tsetCset: try symbol("H5Tset_cset", as: H5TsetCset.self),
            h5tclose: try symbol("H5Tclose", as: H5Tclose.self),
            h5acreate2: try symbol("H5Acreate2", as: H5Acreate2.self),
            h5aexists: try symbol("H5Aexists", as: H5Aexists.self),
            h5aopen: try symbol("H5Aopen", as: H5Aopen.self),
            h5agetType: try symbol("H5Aget_type", as: H5AgetType.self),
            h5agetSpace: try symbol("H5Aget_space", as: H5AgetSpace.self),
            h5tgetClass: try symbol("H5Tget_class", as: H5TgetClass.self),
            h5tgetSize: try symbol("H5Tget_size", as: H5TgetSize.self),
            h5tisVariableStr: try symbol("H5Tis_variable_str", as: H5TisVariableStr.self),
            h5awrite: try symbol("H5Awrite", as: H5Awrite.self),
            h5aread: try symbol("H5Aread", as: H5Aread.self),
            h5aclose: try symbol("H5Aclose", as: H5Aclose.self),
            h5lexists: try symbol("H5Lexists", as: H5Lexists.self),
            h5ocopy: try symbol("H5Ocopy", as: H5Ocopy.self),
            h5freeMemory: try symbol("H5free_memory", as: H5freeMemory.self),
            h5lgetNameByIndex: try symbol("H5Lget_name_by_idx", as: H5LgetNameByIndex.self),
            h5pcreate: try symbol("H5Pcreate", as: H5Pcreate.self),
            h5psetChunk: try symbol("H5Pset_chunk", as: H5PsetChunk.self),
            h5pclose: try symbol("H5Pclose", as: H5Pclose.self),
            nativeFloat: try global("H5T_NATIVE_FLOAT_g", as: hid_t.self),
            nativeDouble: try global("H5T_NATIVE_DOUBLE_g", as: hid_t.self),
            nativeInt: try global("H5T_NATIVE_INT_g", as: hid_t.self),
            nativeLongLong: try global("H5T_NATIVE_LLONG_g", as: hid_t.self),
            nativeHBool: try global("H5T_NATIVE_HBOOL_g", as: hid_t.self),
            nativeUChar: try global("H5T_NATIVE_UCHAR_g", as: hid_t.self),
            stringC1: try global("H5T_C_S1_g", as: hid_t.self),
            datasetCreatePropertyClass: try global(
                "H5P_CLS_DATASET_CREATE_ID_g", as: hid_t.self
            )
        )
    }

    private static func candidateLibraryPaths() -> [String] { HDF5LibraryCandidates.paths }
}
