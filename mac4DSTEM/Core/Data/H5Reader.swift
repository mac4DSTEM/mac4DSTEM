import Darwin
import Foundation

nonisolated private let h5ReadOnly: UInt32 = 0x0000
nonisolated private let h5DefaultProperty: hid_t = 0
nonisolated private let h5SelectSet: Int32 = 0
nonisolated private let h5ChunkedLayout: Int32 = 2
nonisolated private let h5FloatClass: Int32 = 1
nonisolated private let h5IntegerClass: Int32 = 0
nonisolated private let h5TwosComplementSign: Int32 = 1

nonisolated private final class H5LinkCollector: @unchecked Sendable {
    package var paths: [String] = []
}

nonisolated private let collectH5Link: @convention(c)
    (hid_t, UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t = {
        _, name, _, context in
        guard let name, let context else { return 0 }
        let collector = Unmanaged<H5LinkCollector>.fromOpaque(context).takeUnretainedValue()
        if collector.paths.count < 100_000 { collector.paths.append("/" + String(cString: name)) }
        return 0
    }

package enum H5Error: LocalizedError {
    case libraryUnavailable(String)
    case symbolMissing(String)
    case cannotOpenFile(String)
    case noDatasetFound([String])
    /// The opened file is one of this app's own session sidecars — recognised
    /// by its root schema attribute, which the open path never used to check.
    /// The release owner hit the raw path-wall answer twice in one afternoon
    /// (2026-08-19): the open panel offers both files of the sharing pair and
    /// they sort adjacently under near-identical names, so this failure mode
    /// is EXPECTED, not exotic — it deserves a sentence, not a dump. // v2 S4
    case sessionSidecarOpened(sidecar: String, suggestedSource: String?)
    case datasetOpenFailed(String)
    case readFailed(String)
    case unsupportedRank(Int)

    package var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let detail):
            return "Could not load the bundled HDF5 library: \(detail)"
        case .symbolMissing(let name):
            return "The HDF5 library is missing required symbol \(name)."
        case .cannotOpenFile(let path):
            return "Could not open \(displayFileName(path)). Is it a valid .h5 file?"
        case .noDatasetFound(let paths):
            // Capped: the full wall (30+ probed paths on a real sidecar) buries
            // the one sentence that matters. The first few say what was tried;
            // the count says the search was thorough.
            let shown = paths.prefix(8)
            let remainder = paths.count - shown.count
            let tail = remainder > 0 ? "\n… and \(remainder) more paths" : ""
            return "No 4D or 3D dataset found. Tried paths:\n"
                + shown.joined(separator: "\n") + tail
        case .sessionSidecarOpened(let sidecar, let suggestedSource):
            // `suggestedSource` is a STEM, never a filename: the sidecar
            // naming rule strips any extension from the source, so asserting
            // ".h5" here would send a .dm4 user hunting for a file that never
            // existed (caught by Gate A before it shipped).
            let first = "\(sidecar) is a mac4DSTEM session sidecar — the companion "
                + "file that stores a session's calibration and results, not a dataset."
            if let suggestedSource {
                return first + " Open the dataset named “\(suggestedSource)” beside it "
                    + "and the saved session loads with it automatically."
            }
            return first + " Open the dataset it was saved beside and the "
                + "saved session loads with it automatically."
        case .datasetOpenFailed(let path):
            return "Failed to open dataset at HDF5 path \(path)."
        case .readFailed(let operation):
            return "HDF5 read failed: \(operation)."
        case .unsupportedRank(let rank):
            return "Dataset rank \(rank) is not supported. Expected rank 3 or 4."
        }
    }
}

nonisolated private struct HDF5Library: @unchecked Sendable {
    package typealias H5open = @convention(c) () -> herr_t
    package typealias H5EAuto2 = @convention(c) (hid_t, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5EsetAuto2 = @convention(c) (hid_t, H5EAuto2?, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5Fopen = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t) -> hid_t
    package typealias H5Fclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Dopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    package typealias H5Dclose = @convention(c) (hid_t) -> herr_t
    package typealias H5DgetSpace = @convention(c) (hid_t) -> hid_t
    package typealias H5DgetType = @convention(c) (hid_t) -> hid_t
    package typealias H5DgetCreatePlist = @convention(c) (hid_t) -> hid_t
    package typealias H5Dread = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5Sclose = @convention(c) (hid_t) -> herr_t
    package typealias H5SgetSimpleExtentNdims = @convention(c) (hid_t) -> Int32
    package typealias H5SgetSimpleExtentDims = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?, UnsafeMutablePointer<hsize_t>?) -> Int32
    package typealias H5SselectHyperslab = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> herr_t
    package typealias H5ScreateSimple = @convention(c) (Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> hid_t
    package typealias H5Pclose = @convention(c) (hid_t) -> herr_t
    package typealias H5PgetLayout = @convention(c) (hid_t) -> Int32
    package typealias H5PgetChunk = @convention(c) (hid_t, Int32, UnsafeMutablePointer<hsize_t>?) -> Int32
    package typealias H5Tclose = @convention(c) (hid_t) -> herr_t
    package typealias H5TgetClass = @convention(c) (hid_t) -> Int32
    package typealias H5TgetSize = @convention(c) (hid_t) -> Int
    package typealias H5TgetSign = @convention(c) (hid_t) -> Int32
    package typealias H5Tcopy = @convention(c) (hid_t) -> hid_t
    package typealias H5TsetSize = @convention(c) (hid_t, UInt) -> herr_t
    package typealias H5TisVariableStr = @convention(c) (hid_t) -> Int32
    package typealias H5AgetType = @convention(c) (hid_t) -> hid_t
    package typealias H5Oopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    package typealias H5Oclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Aopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    package typealias H5Aclose = @convention(c) (hid_t) -> herr_t
    package typealias H5Aread = @convention(c) (hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5Literate = @convention(c)
        (hid_t, UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t
    package typealias H5Lvisit2 = @convention(c)
        (hid_t, Int32, Int32, H5Literate, UnsafeMutableRawPointer?) -> herr_t

    package let handle: UnsafeMutableRawPointer
    package let h5open: H5open
    package let h5esetAuto2: H5EsetAuto2
    package let h5fopen: H5Fopen
    package let h5fclose: H5Fclose
    package let h5dopen2: H5Dopen2
    package let h5dclose: H5Dclose
    package let h5dgetSpace: H5DgetSpace
    package let h5dgetType: H5DgetType
    package let h5dgetCreatePlist: H5DgetCreatePlist
    package let h5dread: H5Dread
    package let h5sclose: H5Sclose
    package let h5sgetSimpleExtentNdims: H5SgetSimpleExtentNdims
    package let h5sgetSimpleExtentDims: H5SgetSimpleExtentDims
    package let h5sselectHyperslab: H5SselectHyperslab
    package let h5screateSimple: H5ScreateSimple
    package let h5pclose: H5Pclose
    package let h5pgetLayout: H5PgetLayout
    package let h5pgetChunk: H5PgetChunk
    package let h5tclose: H5Tclose
    package let h5tgetClass: H5TgetClass
    package let h5tgetSize: H5TgetSize
    package let h5tgetSign: H5TgetSign
    package let h5tcopy: H5Tcopy
    package let h5tsetSize: H5TsetSize
    package let h5tisVariableStr: H5TisVariableStr
    package let h5agetType: H5AgetType
    package let h5oopen: H5Oopen
    package let h5oclose: H5Oclose
    package let h5aopen: H5Aopen
    package let h5aclose: H5Aclose
    package let h5aread: H5Aread
    package let h5lvisit2: H5Lvisit2
    package let nativeFloat: hid_t
    package let nativeDouble: hid_t
    package let nativeInt: hid_t
    package let stringC1: hid_t          // H5T_C_S1 base type for string reads

    package static func load() throws -> HDF5Library {
        let paths = candidateLibraryPaths()

        var failures: [String] = []
        var handle: UnsafeMutableRawPointer?
        for path in paths where handle == nil {
            dlerror()
            handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if handle == nil {
                let detail = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
                failures.append("\(path): \(detail)")
            }
        }

        guard let handle else {
            throw H5Error.libraryUnavailable(failures.joined(separator: "\n"))
        }

        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else {
                throw H5Error.symbolMissing(name)
            }
            return unsafeBitCast(pointer, to: type)
        }

        func global<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else {
                throw H5Error.symbolMissing(name)
            }
            return pointer.assumingMemoryBound(to: type).pointee
        }

        let h5open = try symbol("H5open", as: H5open.self)
        _ = h5open()
        let h5esetAuto2 = try symbol("H5Eset_auto2", as: H5EsetAuto2.self)
        // Missing optional py4DSTEM/EMD paths are normal during discovery.
        // HDF5 otherwise writes a full native stack to stderr for each probe;
        // the app reports its own actionable errors instead.
        _ = h5esetAuto2(h5DefaultProperty, nil, nil)

        return HDF5Library(
            handle: handle,
            h5open: h5open,
            h5esetAuto2: h5esetAuto2,
            h5fopen: try symbol("H5Fopen", as: H5Fopen.self),
            h5fclose: try symbol("H5Fclose", as: H5Fclose.self),
            h5dopen2: try symbol("H5Dopen2", as: H5Dopen2.self),
            h5dclose: try symbol("H5Dclose", as: H5Dclose.self),
            h5dgetSpace: try symbol("H5Dget_space", as: H5DgetSpace.self),
            h5dgetType: try symbol("H5Dget_type", as: H5DgetType.self),
            h5dgetCreatePlist: try symbol("H5Dget_create_plist", as: H5DgetCreatePlist.self),
            h5dread: try symbol("H5Dread", as: H5Dread.self),
            h5sclose: try symbol("H5Sclose", as: H5Sclose.self),
            h5sgetSimpleExtentNdims: try symbol("H5Sget_simple_extent_ndims", as: H5SgetSimpleExtentNdims.self),
            h5sgetSimpleExtentDims: try symbol("H5Sget_simple_extent_dims", as: H5SgetSimpleExtentDims.self),
            h5sselectHyperslab: try symbol("H5Sselect_hyperslab", as: H5SselectHyperslab.self),
            h5screateSimple: try symbol("H5Screate_simple", as: H5ScreateSimple.self),
            h5pclose: try symbol("H5Pclose", as: H5Pclose.self),
            h5pgetLayout: try symbol("H5Pget_layout", as: H5PgetLayout.self),
            h5pgetChunk: try symbol("H5Pget_chunk", as: H5PgetChunk.self),
            h5tclose: try symbol("H5Tclose", as: H5Tclose.self),
            h5tgetClass: try symbol("H5Tget_class", as: H5TgetClass.self),
            h5tgetSize: try symbol("H5Tget_size", as: H5TgetSize.self),
            h5tgetSign: try symbol("H5Tget_sign", as: H5TgetSign.self),
            h5tcopy: try symbol("H5Tcopy", as: H5Tcopy.self),
            h5tsetSize: try symbol("H5Tset_size", as: H5TsetSize.self),
            h5tisVariableStr: try symbol("H5Tis_variable_str", as: H5TisVariableStr.self),
            h5agetType: try symbol("H5Aget_type", as: H5AgetType.self),
            h5oopen: try symbol("H5Oopen", as: H5Oopen.self),
            h5oclose: try symbol("H5Oclose", as: H5Oclose.self),
            h5aopen: try symbol("H5Aopen", as: H5Aopen.self),
            h5aclose: try symbol("H5Aclose", as: H5Aclose.self),
            h5aread: try symbol("H5Aread", as: H5Aread.self),
            h5lvisit2: try symbol("H5Lvisit2", as: H5Lvisit2.self),
            nativeFloat: try global("H5T_NATIVE_FLOAT_g", as: hid_t.self),
            nativeDouble: try global("H5T_NATIVE_DOUBLE_g", as: hid_t.self),
            nativeInt: try global("H5T_NATIVE_INT_g", as: hid_t.self),
            stringC1: try global("H5T_C_S1_g", as: hid_t.self)
        )
    }

    private static func candidateLibraryPaths() -> [String] {
        // The app is self-contained. The environment override and bare-name
        // fallback exist only for standalone source harnesses.
        [
            ProcessInfo.processInfo.environment["MAC4DSTEM_HDF5_PATH"],
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libhdf5.dylib").path,
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("../Frameworks/libhdf5.dylib").standardized.path,
            "libhdf5.dylib"
        ].compactMap { $0 }
    }
}

package actor H5Reader: FourDDataSource {
    private let hdf5: HDF5Library
    private let fileID: hid_t
    package let filePath: String
    /// Path of the most recently described dataset — anchor for locating the
    /// py4DSTEM calibration bundle / EMD dim vectors relative to the datacube.
    private var lastDatasetPath: String?
    private var lastDatasetShape: [Int]?

    package static let candidatePaths: [String] = [
        "/dm_dataset_root/dm_dataset/data",
        "/4DSTEM_experiment/data/datacubes/datacube_0/data",
        "/4DSTEM/data/datacubes/datacube_root/data",
        "/datacube_root/datacube/data",
        "/Experiments/__unnamed__/data",
        "/Experiments/__unnamed__/data/data"
    ]

    package init(path: String) throws {
        let hdf5 = try HDF5Library.load()
        _ = hdf5.h5esetAuto2(h5DefaultProperty, nil, nil)
        let id = path.withCString { hdf5.h5fopen($0, h5ReadOnly, h5DefaultProperty) }
        guard id >= 0 else { throw H5Error.cannotOpenFile(path) }
        self.hdf5 = hdf5
        fileID = id
        filePath = path
    }

    deinit {
        if fileID >= 0 {
            _ = hdf5.h5fclose(fileID)
        }
    }

    package func discoverPrimaryDataset() throws -> DatasetDescriptor {
        silenceAutomaticErrors()
        // `try?` is correct here (v2 S7 audit): each candidate path is a
        // PROBE — "this file has no dataset at that name" is the expected
        // answer for most of them, not a failure to surface. A file-level
        // I/O error would also be swallowed per-candidate, but the file
        // handle was already opened successfully and the fall-through ends
        // in a named "no 4D dataset" error, never a silent success.
        for path in Self.candidatePaths {
            if let descriptor = try? describe(path: path), descriptor.is4D {
                return descriptor
            }
        }

        // EMD 1.0 permits arbitrary root/node names. Visit links only after
        // the fast canonical probes, then ask HDF5 itself which links are 3D/
        // 4D datasets. This avoids baking a particular py4DSTEM root name into
        // interoperability while keeping deterministic preference for `data`.
        let collector = H5LinkCollector()
        let unmanaged = Unmanaged.passUnretained(collector)
        _ = hdf5.h5lvisit2(fileID, 0, 0, collectH5Link, unmanaged.toOpaque())
        let candidates = collector.paths.sorted {
            let lhsData = $0.hasSuffix("/data") ? 0 : 1
            let rhsData = $1.hasSuffix("/data") ? 0 : 1
            if lhsData != rhsData { return lhsData < rhsData }
            let lhsDepth = $0.filter { $0 == "/" }.count
            let rhsDepth = $1.filter { $0 == "/" }.count
            return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
        }
        for path in candidates where !Self.candidatePaths.contains(path) {
            // Same probe contract as the canonical loop above. // v2 S7
            if let descriptor = try? describe(path: path), descriptor.is4D {
                return descriptor
            }
        }
        // Before answering "no dataset", ask whether this is one of the app's
        // own session sidecars: they contain no datacube BY DESIGN. The writer
        // stamps the schema attribute on its ROOT GROUP, not the file root —
        // the first version of this check read "/" and was caught by its own
        // test; "/" is kept as a fallback so a future writer that stamps the
        // file root is still recognised. Deliberately checked only AFTER the
        // full search fails: a file that carries both the attribute and a real
        // 4D dataset opens as data. The suggestion is the source's STEM, not a
        // filename — the naming rule strips any extension, so the source may
        // be .dm4, .emd, anything. // v2 S4
        let attribute = SessionSidecarFormat.schemaAttribute
        if readStringAttribute(attribute, onPath: "/" + SessionSidecarFormat.rootGroupName) != nil
            || readStringAttribute(attribute, onPath: "/") != nil {
            let name = URL(fileURLWithPath: filePath).lastPathComponent
            let suffix = SessionSidecarFormat.nameSuffix
            let suggested: String? = name.hasSuffix(suffix)
                ? String(name.dropLast(suffix.count))
                : nil
            throw H5Error.sessionSidecarOpened(sidecar: name, suggestedSource: suggested)
        }
        throw H5Error.noDatasetFound(Self.candidatePaths + candidates)
    }

    package func describe(path: String) throws -> DatasetDescriptor {
        silenceAutomaticErrors()
        let datasetID = path.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard datasetID >= 0 else { throw H5Error.datasetOpenFailed(path) }
        defer { _ = hdf5.h5dclose(datasetID) }

        let dataspaceID = hdf5.h5dgetSpace(datasetID)
        defer { _ = hdf5.h5sclose(dataspaceID) }

        let rank = Int(hdf5.h5sgetSimpleExtentNdims(dataspaceID))
        guard rank == 3 || rank == 4 else { throw H5Error.unsupportedRank(rank) }

        var dimensions = [hsize_t](repeating: 0, count: rank)
        _ = dimensions.withUnsafeMutableBufferPointer {
            hdf5.h5sgetSimpleExtentDims(dataspaceID, $0.baseAddress, nil)
        }

        var shape = dimensions.map(Int.init)
        if rank == 3 {
            shape = [1, shape[0], shape[1], shape[2]]
        }

        let typeID = hdf5.h5dgetType(datasetID)
        defer { _ = hdf5.h5tclose(typeID) }

        var chunkShape: [Int]?
        let propertyListID = hdf5.h5dgetCreatePlist(datasetID)
        defer { _ = hdf5.h5pclose(propertyListID) }
        if hdf5.h5pgetLayout(propertyListID) == h5ChunkedLayout {
            var chunkDimensions = [hsize_t](repeating: 0, count: rank)
            let count = chunkDimensions.withUnsafeMutableBufferPointer {
                Int(hdf5.h5pgetChunk(propertyListID, Int32(rank), $0.baseAddress))
            }
            if count > 0 {
                chunkShape = chunkDimensions.prefix(count).map(Int.init)
            }
        }

        lastDatasetPath = path
        lastDatasetShape = shape
        return DatasetDescriptor(
            filePath: filePath,
            datasetPath: path,
            shape: shape,
            dtypeDescription: describeType(typeID),
            chunkShape: chunkShape
        )
    }

    /// HDF5 pushes every axis of a crop into the hyperslab it already builds —
    /// **on a contiguous dataset**. On a *chunked* one it reads and decompresses
    /// whole chunks, so a crop that stays inside a chunk skips no bytes at all,
    /// and py4DSTEM EMD files are chunked. Measured 2026-08-18, gzip-chunked
    /// (16,16,256,256) f4 with chunks (1,16,256,256), `purge` between runs:
    /// the full detector took 0.137 s and 1/64 of it took 0.135 s.
    ///
    /// So the declaration is per-axis and conservative: a crop is only claimed
    /// to skip I/O on an axis whose chunk extent is smaller than the source, the
    /// case where cropping can exclude entire chunks. Claiming `.full`
    /// unconditionally — which this reader did until an adversarial review
    /// measured it — is exactly the overstatement `LoadPushdown` exists to stop.
    ///
    /// DEVIATION from py4DSTEM (preprocess.crop_data_diffraction,
    /// References/py4DSTEM-dev/py4DSTEM/preprocess/preprocess.py:123): py4DSTEM
    /// slices an already-resident array in place (`datacube.data[:, :, qx0:qx1,
    /// qy0:qy1]`), which is a NumPy view — the full cube stays alive as `.base`,
    /// so you lose access to the full extent while still paying for it. Here the
    /// crop is applied at READ time and the source file is untouched.
    package nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown {
        let source = view.source
        guard let chunk = source.chunkShape, chunk.count == 4 else { return .full }
        return LoadPushdown(
            scanCropSkipsIO: chunk[0] < source.ry || chunk[1] < source.rx,
            detectorCropSkipsIO: chunk[2] < source.qy || chunk[3] < source.qx
        )
    }

    /// Where the requested view starts and how much of it to take, in the
    /// file's own dataspace, plus the memory shape to read it into.
    ///
    /// Rank-3 files were reshaped to `[1, N, Qy, Qx]` in `describe()`; the file
    /// dataspace is still rank 3, so the scan-row axis is dropped and a scan
    /// crop's *x* offset indexes the N axis. Getting that mapping wrong would
    /// read the right number of pixels from the wrong frames, so the bounds
    /// check below is against the file's real dims rather than the descriptor.
    private func hyperslab(
        _ view: LoadView, filespaceID: hid_t, fileRank: Int,
        scanY: Range<Int>, scanX: Range<Int>
    ) throws -> (start: [hsize_t], count: [hsize_t], memory: [hsize_t]) {
        let specification = view.specification
        let (sourceY, sourceX) = specification.scanOffset
        // The READ crop, not the requested one: it is trimmed to a whole number
        // of bins, so the edge remainder is never decoded — and on a CONTIGUOUS
        // dataset never read either, though on a chunked one HDF5 still inflates
        // the whole chunk (see `loadPushdown`). And the extent here
        // is the PRE-bin one — the hyperslab selects pixels, `binned` reduces
        // them; no HDF5 selection can sum.
        let detectorY = view.readDetectorCrop?.yOffset ?? 0
        let detectorX = view.readDetectorCrop?.xOffset ?? 0
        let qy = view.readDetectorCrop?.height ?? view.source.qy
        let qx = view.readDetectorCrop?.width ?? view.source.qx

        let start: [Int]
        let count: [Int]
        if fileRank == 3 {
            guard scanY == 0..<1 else {
                throw H5Error.readFailed("rank-3 dataset has a single scan row; asked for \(scanY)")
            }
            start = [sourceX + scanX.lowerBound, detectorY, detectorX]
            count = [scanX.count, qy, qx]
        } else {
            start = [sourceY + scanY.lowerBound, sourceX + scanX.lowerBound,
                     detectorY, detectorX]
            count = [scanY.count, scanX.count, qy, qx]
        }

        // Bounds against the FILE, not against the descriptor we were handed.
        // A descriptor and a specification that disagree would otherwise select
        // a valid-looking hyperslab of the wrong region, and every length check
        // downstream would pass.
        var dims = [hsize_t](repeating: 0, count: fileRank)
        let dimsRead = dims.withUnsafeMutableBufferPointer {
            hdf5.h5sgetSimpleExtentDims(filespaceID, $0.baseAddress, nil)
        }
        guard dimsRead >= 0 else { throw H5Error.readFailed("could not read dataspace dims") }
        // The view must describe THIS dataset. Checked from the dims already in
        // hand rather than by re-opening the file, so it costs nothing on the
        // streaming hot path. Rank-3 files carry the same [1, N, Qy, Qx]
        // reshape `describe()` applied.
        let sourceShape = fileRank == 3
            ? [1] + dims.map(Int.init)
            : dims.map(Int.init)
        try view.requireSource(shape: sourceShape)
        for axis in 0..<fileRank {
            guard start[axis] >= 0, count[axis] > 0,
                  start[axis] + count[axis] <= Int(dims[axis]) else {
                throw H5Error.readFailed(
                    "selection \(start[axis])+\(count[axis]) exceeds axis \(axis) of \(dims[axis])"
                )
            }
        }

        let memory: [Int]
        if fileRank == 3 {
            memory = scanX.count == 1 && scanY.count == 1 ? [qy, qx] : count
        } else {
            memory = scanY.count == 1 && scanX.count == 1 ? [qy, qx] : count
        }
        return (start.map(hsize_t.init), count.map(hsize_t.init), memory.map(hsize_t.init))
    }

    private func read(
        _ view: LoadView, scanY: Range<Int>, scanX: Range<Int>, label: String
    ) throws -> [Float] {
        silenceAutomaticErrors()
        let datasetID = view.source.datasetPath.withCString {
            hdf5.h5dopen2(fileID, $0, h5DefaultProperty)
        }
        guard datasetID >= 0 else { throw H5Error.datasetOpenFailed(view.source.datasetPath) }
        defer { _ = hdf5.h5dclose(datasetID) }

        let filespaceID = hdf5.h5dgetSpace(datasetID)
        defer { _ = hdf5.h5sclose(filespaceID) }
        let fileRank = Int(hdf5.h5sgetSimpleExtentNdims(filespaceID))

        let slab = try hyperslab(view, filespaceID: filespaceID, fileRank: fileRank,
                                 scanY: scanY, scanX: scanX)
        let selectionStatus = slab.start.withUnsafeBufferPointer { startBuffer in
            slab.count.withUnsafeBufferPointer { countBuffer in
                hdf5.h5sselectHyperslab(
                    filespaceID, h5SelectSet,
                    startBuffer.baseAddress, nil, countBuffer.baseAddress, nil
                )
            }
        }
        guard selectionStatus >= 0 else { throw H5Error.readFailed("\(label) hyperslab selection") }

        let memorySpaceID = slab.memory.withUnsafeBufferPointer {
            hdf5.h5screateSimple(Int32(slab.memory.count), $0.baseAddress, nil)
        }
        defer { _ = hdf5.h5sclose(memorySpaceID) }

        let pixelCount = slab.count.reduce(1) { $0 * Int($1) }
        var buffer = [Float](repeating: 0, count: pixelCount)
        let status = buffer.withUnsafeMutableBytes {
            hdf5.h5dread(datasetID, hdf5.nativeFloat, memorySpaceID, filespaceID,
                         h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0 else { throw H5Error.readFailed(label) }
        let patternCount = pixelCount
            / max(1, (view.readDetectorCrop?.height ?? view.source.qy)
                     * (view.readDetectorCrop?.width ?? view.source.qx))
        return view.binned(buffer, patternCount: patternCount)
    }

    package func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        guard ry >= 0, ry < view.descriptor.ry, rx >= 0, rx < view.descriptor.rx else {
            throw H5Error.readFailed("scan position (\(ry), \(rx)) is outside the loaded view")
        }
        return try read(view, scanY: ry..<(ry + 1), scanX: rx..<(rx + 1),
                        label: "pattern at ry \(ry), rx \(rx)")
    }

    /// Read an entire view scan row: all view Rx patterns for a fixed view Ry,
    /// flattened as [Rx * Qy * Qx]. This remains a useful compatibility
    /// primitive; bounded whole-scan consumers prefer `readScanTile`.
    package func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        guard ry >= 0, ry < view.descriptor.ry else {
            throw H5Error.readFailed("scan row \(ry) is outside the loaded view")
        }
        return try read(view, scanY: ry..<(ry + 1), scanX: 0..<view.descriptor.rx,
                        label: "scan row \(ry)")
    }

    package func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        guard yRange.lowerBound >= 0, yRange.upperBound <= view.descriptor.ry,
              !yRange.isEmpty else {
            throw H5Error.readFailed("invalid scan tile \(yRange)")
        }
        let pixels = try read(view, scanY: yRange, scanX: 0..<view.descriptor.rx,
                              label: "scan tile \(yRange)")
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx,
            pixels: pixels
        )
    }

    /// Calibration from the file itself, tried in order:
    ///  1. py4DSTEM EMD calibration bundle:
    ///     <datacube-root>/metadatabundle/calibration/{Q,R}_pixel_size (+units,
    ///     QR_flip) — the exact values py4DSTEM would load.
    ///  2. EMD dim vectors dim0…dim3 beside the data (spacing = dim[1]−dim[0],
    ///     units from the dataset attribute) — generic EMD/HyperSpy fallback.
    /// Otherwise nil → manual entry in the Calibration section.
    package func pixelCalibration() -> PixelCalibration? {
        silenceAutomaticErrors()
        guard let dsPath = lastDatasetPath else { return nil }
        let components = dsPath.split(separator: "/").map(String.init)
        var out = PixelCalibration(rSize: nil, rUnits: nil, qSize: nil, qUnits: nil)

        // 1. py4DSTEM bundle: dataset ".../<group>/data" → "<group parent>".
        // emdfile's Metadata.to_h5 writes scalar/string entries as HDF5
        // *attributes* on the calibration group (only arrays become
        // datasets), so try the dataset form first, then the attribute form.
        if components.count >= 2 {
            let root = "/" + components.dropLast(2).joined(separator: "/")
            let cal = (root == "/" ? "" : root) + "/metadatabundle/calibration"
            func scalar(_ name: String) -> Double? {
                readScalarDouble(cal + "/" + name)
                    ?? readDoubleAttribute(name, onObjectPath: cal)
            }
            func string(_ name: String) -> String? {
                readStringDataset(cal + "/" + name)
                    ?? readStringAttribute(name, onPath: cal)
            }
            out.qSize = scalar("Q_pixel_size")
            out.qUnits = string("Q_pixel_units")
            out.rSize = scalar("R_pixel_size")
            out.rUnits = string("R_pixel_units")
            // QR_flip: h5py stores Python bools as an int8-based enum
            // {FALSE, TRUE}, which HDF5 converts to integer memory types but
            // not to double — both dataset and attribute reads go through an
            // int (py4DSTEM 0.14 writes it as a bool-enum scalar DATASET).
            out.qrFlip = readIntDataset(cal + "/QR_flip").map { $0 != 0 }
                ?? readScalarDouble(cal + "/QR_flip").map { $0 > 0.5 }
                ?? readIntAttribute("QR_flip", onPath: cal).map { $0 != 0 }
            // Origin (mean of the fitted per-position origins) and elliptical
            // distortion, under py4DSTEM Calibration's own key names. The full
            // per-position qx0/qy0 maps (2D array datasets) are not read here.
            out.qx0Mean = scalar("qx0_mean")
            out.qy0Mean = scalar("qy0_mean")
            out.ellipseA = scalar("a")
            out.ellipseB = scalar("b")
            out.ellipseTheta = scalar("theta")
            out.qrRotationRad = scalar("QR_rotation")
            out.probeSemiangle = scalar("probe_semiangle")

            // py4DSTEM Metadata writes array-valued calibration entries as
            // datasets. qx0/qy0 are shaped [R_Nx,R_Ny], the same real-space
            // order as this app's [Ry,Rx]; only their detector components are
            // swapped later at the AppState activation boundary.
            if let scanShape = lastDatasetShape.map({ Array($0.prefix(2)) }),
               let qx0 = readDoubleMatrix(cal + "/qx0", expectedShape: scanShape),
               let qy0 = readDoubleMatrix(cal + "/qy0", expectedShape: scanShape) {
                let qx0Measured = readDoubleMatrix(
                    cal + "/qx0_meas", expectedShape: scanShape)?.values
                let qy0Measured = readDoubleMatrix(
                    cal + "/qy0_meas", expectedShape: scanShape)?.values
                out.originMaps = PixelOriginMaps(
                    shape: scanShape,
                    fittedQX: qx0.values,
                    fittedQY: qy0.values,
                    measuredQX: qx0Measured != nil && qy0Measured != nil ? qx0Measured : nil,
                    measuredQY: qx0Measured != nil && qy0Measured != nil ? qy0Measured : nil
                )
            }
        }

        // 2. EMD dim-vector fallback ([Ry, Rx, Qy, Qx] → dim1 = R, dim3 = Q).
        if out.rSize == nil || out.qSize == nil {
            let parent = "/" + components.dropLast().joined(separator: "/")
            func dim(_ i: Int) -> (size: Double, units: String?)? {
                guard let v = readDoubleVector(parent + "/dim\(i)", maxCount: 65536),
                      v.count >= 2, v[1] - v[0] > 0 else { return nil }
                return (v[1] - v[0], readStringAttribute("units", onPath: parent + "/dim\(i)"))
            }
            if out.rSize == nil, let d = dim(1) { out.rSize = d.size; out.rUnits = d.units }
            if out.qSize == nil, let d = dim(3) { out.qSize = d.size; out.qUnits = d.units }
        }

        let hasCalibration = out.rSize != nil || out.qSize != nil
            || out.qrFlip != nil || out.qx0Mean != nil || out.qy0Mean != nil
            || out.ellipseA != nil || out.ellipseB != nil || out.ellipseTheta != nil
            || out.qrRotationRad != nil || out.probeSemiangle != nil
            || out.originMaps != nil
        return hasCalibration ? out : nil
    }

    // MARK: Small typed readers (calibration metadata)

    /// Number of elements in a dataset's dataspace (1 for scalar), or nil.
    private func elementCount(spaceID: hid_t) -> Int? {
        let rank = Int(hdf5.h5sgetSimpleExtentNdims(spaceID))
        guard rank >= 0 else { return nil }
        if rank == 0 { return 1 }
        var dims = [hsize_t](repeating: 0, count: rank)
        _ = dims.withUnsafeMutableBufferPointer {
            hdf5.h5sgetSimpleExtentDims(spaceID, $0.baseAddress, nil)
        }
        return dims.reduce(1) { $0 * Int($1) }
    }

    private func readScalarDouble(_ path: String) -> Double? {
        readDoubleVector(path, maxCount: 1)?.first
    }

    private func readDoubleVector(_ path: String, maxCount: Int) -> [Double]? {
        let ds = path.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard ds >= 0 else { return nil }
        defer { _ = hdf5.h5dclose(ds) }
        let space = hdf5.h5dgetSpace(ds)
        defer { _ = hdf5.h5sclose(space) }
        guard let n = elementCount(spaceID: space), n >= 1, n <= maxCount else { return nil }
        var buffer = [Double](repeating: 0, count: n)
        let status = buffer.withUnsafeMutableBytes {
            hdf5.h5dread(ds, hdf5.nativeDouble, 0, 0, h5DefaultProperty, $0.baseAddress)
        }
        return status >= 0 ? buffer : nil
    }

    /// Read a finite rank-2 double-convertible dataset with an exact shape.
    private func readDoubleMatrix(_ path: String,
                                  expectedShape: [Int]) -> (shape: [Int], values: [Double])? {
        guard expectedShape.count == 2, expectedShape.allSatisfy({ $0 > 0 }) else { return nil }
        let ds = path.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard ds >= 0 else { return nil }
        defer { _ = hdf5.h5dclose(ds) }
        let space = hdf5.h5dgetSpace(ds)
        defer { _ = hdf5.h5sclose(space) }
        guard hdf5.h5sgetSimpleExtentNdims(space) == 2 else { return nil }
        var dims = [hsize_t](repeating: 0, count: 2)
        _ = dims.withUnsafeMutableBufferPointer {
            hdf5.h5sgetSimpleExtentDims(space, $0.baseAddress, nil)
        }
        let shape = dims.map(Int.init)
        guard shape == expectedShape else { return nil }
        var values = [Double](repeating: 0, count: shape[0] * shape[1])
        let status = values.withUnsafeMutableBytes {
            hdf5.h5dread(ds, hdf5.nativeDouble, 0, 0, h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0, values.allSatisfy(\.isFinite) else { return nil }
        return (shape, values)
    }

    /// Read a 1-element string dataset (variable- or fixed-length).
    private func readStringDataset(_ path: String) -> String? {
        let ds = path.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard ds >= 0 else { return nil }
        defer { _ = hdf5.h5dclose(ds) }
        let space = hdf5.h5dgetSpace(ds)
        defer { _ = hdf5.h5sclose(space) }
        guard elementCount(spaceID: space) == 1 else { return nil }
        let fileType = hdf5.h5dgetType(ds)
        defer { _ = hdf5.h5tclose(fileType) }
        return readStringValue(fileType: fileType) { memType, buf in
            hdf5.h5dread(ds, memType, 0, 0, h5DefaultProperty, buf)
        }
    }

    /// Read a 1-element integer-convertible dataset (plain ints, or h5py's
    /// enum-typed Python bools — HDF5 converts enum→int but not enum→double).
    private func readIntDataset(_ path: String) -> Int? {
        let ds = path.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard ds >= 0 else { return nil }
        defer { _ = hdf5.h5dclose(ds) }
        let space = hdf5.h5dgetSpace(ds)
        defer { _ = hdf5.h5sclose(space) }
        guard elementCount(spaceID: space) == 1 else { return nil }
        var value: Int32 = 0
        let status = withUnsafeMutableBytes(of: &value) {
            hdf5.h5dread(ds, hdf5.nativeInt, 0, 0, h5DefaultProperty, $0.baseAddress)
        }
        return status >= 0 ? Int(value) : nil
    }

    /// Read an integer-convertible attribute (plain ints, or h5py's
    /// enum-typed Python bools) on the object at `path`.
    private func readIntAttribute(_ name: String, onPath path: String) -> Int? {
        let obj = path.withCString { hdf5.h5oopen(fileID, $0, h5DefaultProperty) }
        guard obj >= 0 else { return nil }
        defer { _ = hdf5.h5oclose(obj) }
        let attr = name.withCString { hdf5.h5aopen(obj, $0, h5DefaultProperty) }
        guard attr >= 0 else { return nil }
        defer { _ = hdf5.h5aclose(attr) }
        var value: Int32 = 0
        let status = withUnsafeMutableBytes(of: &value) {
            hdf5.h5aread(attr, hdf5.nativeInt, $0.baseAddress)
        }
        return status >= 0 ? Int(value) : nil
    }

    /// Read a string attribute on the object at `path`.
    private func readStringAttribute(_ name: String, onPath path: String) -> String? {
        let obj = path.withCString { hdf5.h5oopen(fileID, $0, h5DefaultProperty) }
        guard obj >= 0 else { return nil }
        defer { _ = hdf5.h5oclose(obj) }
        let attr = name.withCString { hdf5.h5aopen(obj, $0, h5DefaultProperty) }
        guard attr >= 0 else { return nil }
        defer { _ = hdf5.h5aclose(attr) }
        let fileType = hdf5.h5agetType(attr)
        defer { _ = hdf5.h5tclose(fileType) }
        return readStringValue(fileType: fileType) { memType, buf in
            hdf5.h5aread(attr, memType, buf)
        }
    }

    /// Shared string decode: variable-length strings read a malloc'd char*
    /// (freed here); fixed-length read into a sized buffer.
    /// The memory type is a copy of the file's own type — HDF5 has no
    /// conversion path between UTF-8 and ASCII string types, so reading
    /// h5py's UTF-8 strings through an ASCII H5T_C_S1 copy fails outright.
    /// String(cString:) decodes UTF-8, of which ASCII is a subset.
    private func readStringValue(fileType: hid_t,
                                 read: (hid_t, UnsafeMutableRawPointer?) -> herr_t) -> String? {
        let memType = hdf5.h5tcopy(fileType)
        defer { _ = hdf5.h5tclose(memType) }
        if hdf5.h5tisVariableStr(fileType) > 0 {
            var cString: UnsafeMutablePointer<CChar>?
            let status = withUnsafeMutableBytes(of: &cString) { read(memType, $0.baseAddress) }
            guard status >= 0, let cString else { return nil }
            defer { free(cString) }
            return String(cString: cString)
        }
        let size = hdf5.h5tgetSize(fileType)
        guard size > 0, size < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        let status = buffer.withUnsafeMutableBytes { read(memType, $0.baseAddress) }
        guard status >= 0 else { return nil }
        return String(cString: buffer)
    }

    package func readDoubleAttribute(_ name: String, onObjectPath path: String = "/") -> Double? {
        silenceAutomaticErrors()
        let objectID = path.withCString { hdf5.h5oopen(fileID, $0, h5DefaultProperty) }
        guard objectID >= 0 else { return nil }
        defer { _ = hdf5.h5oclose(objectID) }

        let attributeID = name.withCString { hdf5.h5aopen(objectID, $0, h5DefaultProperty) }
        guard attributeID >= 0 else { return nil }
        defer { _ = hdf5.h5aclose(attributeID) }

        var value = 0.0
        let status = withUnsafeMutableBytes(of: &value) {
            hdf5.h5aread(attributeID, hdf5.nativeDouble, $0.baseAddress)
        }
        return status >= 0 ? value : nil
    }

    private func describeType(_ typeID: hid_t) -> String {
        let typeClass = hdf5.h5tgetClass(typeID)
        let size = hdf5.h5tgetSize(typeID)

        switch typeClass {
        case h5FloatClass:
            return "float\(size * 8)"
        case h5IntegerClass:
            let signed = hdf5.h5tgetSign(typeID) == h5TwosComplementSign
            return "\(signed ? "int" : "uint")\(size * 8)"
        default:
            return "class \(typeClass), \(size) bytes"
        }
    }

    /// HDF5's default error stack is thread-local. Actor continuations may
    /// resume on a different worker, so disable native stderr printing at each
    /// public entry point rather than assuming the initializer's thread sticks.
    private func silenceAutomaticErrors() {
        _ = hdf5.h5esetAuto2(h5DefaultProperty, nil, nil)
    }
}
