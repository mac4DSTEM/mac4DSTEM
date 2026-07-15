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
    var paths: [String] = []
}

nonisolated private let collectH5Link: @convention(c)
    (hid_t, UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t = {
        _, name, _, context in
        guard let name, let context else { return 0 }
        let collector = Unmanaged<H5LinkCollector>.fromOpaque(context).takeUnretainedValue()
        if collector.paths.count < 100_000 { collector.paths.append("/" + String(cString: name)) }
        return 0
    }

enum H5Error: LocalizedError {
    case libraryUnavailable(String)
    case symbolMissing(String)
    case cannotOpenFile(String)
    case noDatasetFound([String])
    case datasetOpenFailed(String)
    case readFailed(String)
    case unsupportedRank(Int)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let detail):
            return "Could not load the bundled HDF5 library: \(detail)"
        case .symbolMissing(let name):
            return "The HDF5 library is missing required symbol \(name)."
        case .cannotOpenFile(let path):
            return "Could not open HDF5 file at \(path). Is it a valid .h5 file?"
        case .noDatasetFound(let paths):
            return "No 4D or 3D dataset found. Tried paths:\n" + paths.joined(separator: "\n")
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
    typealias H5open = @convention(c) () -> herr_t
    typealias H5EAuto2 = @convention(c) (hid_t, UnsafeMutableRawPointer?) -> herr_t
    typealias H5EsetAuto2 = @convention(c) (hid_t, H5EAuto2?, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Fopen = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t) -> hid_t
    typealias H5Fclose = @convention(c) (hid_t) -> herr_t
    typealias H5Dopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Dclose = @convention(c) (hid_t) -> herr_t
    typealias H5DgetSpace = @convention(c) (hid_t) -> hid_t
    typealias H5DgetType = @convention(c) (hid_t) -> hid_t
    typealias H5DgetCreatePlist = @convention(c) (hid_t) -> hid_t
    typealias H5Dread = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Sclose = @convention(c) (hid_t) -> herr_t
    typealias H5SgetSimpleExtentNdims = @convention(c) (hid_t) -> Int32
    typealias H5SgetSimpleExtentDims = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?, UnsafeMutablePointer<hsize_t>?) -> Int32
    typealias H5SselectHyperslab = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> herr_t
    typealias H5ScreateSimple = @convention(c) (Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> hid_t
    typealias H5Pclose = @convention(c) (hid_t) -> herr_t
    typealias H5PgetLayout = @convention(c) (hid_t) -> Int32
    typealias H5PgetChunk = @convention(c) (hid_t, Int32, UnsafeMutablePointer<hsize_t>?) -> Int32
    typealias H5Tclose = @convention(c) (hid_t) -> herr_t
    typealias H5TgetClass = @convention(c) (hid_t) -> Int32
    typealias H5TgetSize = @convention(c) (hid_t) -> Int
    typealias H5TgetSign = @convention(c) (hid_t) -> Int32
    typealias H5Tcopy = @convention(c) (hid_t) -> hid_t
    typealias H5TsetSize = @convention(c) (hid_t, UInt) -> herr_t
    typealias H5TisVariableStr = @convention(c) (hid_t) -> Int32
    typealias H5AgetType = @convention(c) (hid_t) -> hid_t
    typealias H5Oopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Oclose = @convention(c) (hid_t) -> herr_t
    typealias H5Aopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Aclose = @convention(c) (hid_t) -> herr_t
    typealias H5Aread = @convention(c) (hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Literate = @convention(c)
        (hid_t, UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Lvisit2 = @convention(c)
        (hid_t, Int32, Int32, H5Literate, UnsafeMutableRawPointer?) -> herr_t

    let handle: UnsafeMutableRawPointer
    let h5open: H5open
    let h5esetAuto2: H5EsetAuto2
    let h5fopen: H5Fopen
    let h5fclose: H5Fclose
    let h5dopen2: H5Dopen2
    let h5dclose: H5Dclose
    let h5dgetSpace: H5DgetSpace
    let h5dgetType: H5DgetType
    let h5dgetCreatePlist: H5DgetCreatePlist
    let h5dread: H5Dread
    let h5sclose: H5Sclose
    let h5sgetSimpleExtentNdims: H5SgetSimpleExtentNdims
    let h5sgetSimpleExtentDims: H5SgetSimpleExtentDims
    let h5sselectHyperslab: H5SselectHyperslab
    let h5screateSimple: H5ScreateSimple
    let h5pclose: H5Pclose
    let h5pgetLayout: H5PgetLayout
    let h5pgetChunk: H5PgetChunk
    let h5tclose: H5Tclose
    let h5tgetClass: H5TgetClass
    let h5tgetSize: H5TgetSize
    let h5tgetSign: H5TgetSign
    let h5tcopy: H5Tcopy
    let h5tsetSize: H5TsetSize
    let h5tisVariableStr: H5TisVariableStr
    let h5agetType: H5AgetType
    let h5oopen: H5Oopen
    let h5oclose: H5Oclose
    let h5aopen: H5Aopen
    let h5aclose: H5Aclose
    let h5aread: H5Aread
    let h5lvisit2: H5Lvisit2
    let nativeFloat: hid_t
    let nativeDouble: hid_t
    let nativeInt: hid_t
    let stringC1: hid_t          // H5T_C_S1 base type for string reads

    static func load() throws -> HDF5Library {
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

actor H5Reader: FourDDataSource {
    private let hdf5: HDF5Library
    private let fileID: hid_t
    let filePath: String
    /// Path of the most recently described dataset — anchor for locating the
    /// py4DSTEM calibration bundle / EMD dim vectors relative to the datacube.
    private var lastDatasetPath: String?
    private var lastDatasetShape: [Int]?

    static let candidatePaths: [String] = [
        "/dm_dataset_root/dm_dataset/data",
        "/4DSTEM_experiment/data/datacubes/datacube_0/data",
        "/4DSTEM/data/datacubes/datacube_root/data",
        "/datacube_root/datacube/data",
        "/Experiments/__unnamed__/data",
        "/Experiments/__unnamed__/data/data"
    ]

    init(path: String) throws {
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

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        silenceAutomaticErrors()
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
            if let descriptor = try? describe(path: path), descriptor.is4D {
                return descriptor
            }
        }
        throw H5Error.noDatasetFound(Self.candidatePaths + candidates)
    }

    func describe(path: String) throws -> DatasetDescriptor {
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

    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float] {
        silenceAutomaticErrors()
        let datasetID = descriptor.datasetPath.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard datasetID >= 0 else { throw H5Error.datasetOpenFailed(descriptor.datasetPath) }
        defer { _ = hdf5.h5dclose(datasetID) }

        let filespaceID = hdf5.h5dgetSpace(datasetID)
        defer { _ = hdf5.h5sclose(filespaceID) }

        // Rank-3 files were reshaped to [1, N, Qy, Qx] in describe(); the file
        // dataspace is still rank 3, so the hyperslab must drop the Ry axis.
        let fileRank = Int(hdf5.h5sgetSimpleExtentNdims(filespaceID))
        let start: [hsize_t]
        let count: [hsize_t]
        if fileRank == 3 {
            start = [hsize_t(rx), 0, 0]
            count = [1, hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        } else {
            start = [hsize_t(ry), hsize_t(rx), 0, 0]
            count = [1, 1, hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        }
        let selectionStatus = start.withUnsafeBufferPointer { startBuffer in
            count.withUnsafeBufferPointer { countBuffer in
                hdf5.h5sselectHyperslab(
                    filespaceID,
                    h5SelectSet,
                    startBuffer.baseAddress,
                    nil,
                    countBuffer.baseAddress,
                    nil
                )
            }
        }
        guard selectionStatus >= 0 else { throw H5Error.readFailed("pattern hyperslab selection") }

        let memoryDimensions: [hsize_t] = [hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        let memorySpaceID = memoryDimensions.withUnsafeBufferPointer {
            hdf5.h5screateSimple(2, $0.baseAddress, nil)
        }
        defer { _ = hdf5.h5sclose(memorySpaceID) }

        var buffer = [Float](repeating: 0, count: descriptor.qy * descriptor.qx)
        let status = buffer.withUnsafeMutableBytes {
            hdf5.h5dread(datasetID, hdf5.nativeFloat, memorySpaceID, filespaceID, h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0 else { throw H5Error.readFailed("pattern at ry \(ry), rx \(rx)") }
        return buffer
    }

    /// Read an entire scan row: all Rx patterns for a fixed Ry, flattened as
    /// [Rx * Qy * Qx]. This remains a useful compatibility primitive; bounded
    /// whole-scan consumers prefer `readScanTile`.
    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float] {
        silenceAutomaticErrors()
        let datasetID = descriptor.datasetPath.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard datasetID >= 0 else { throw H5Error.datasetOpenFailed(descriptor.datasetPath) }
        defer { _ = hdf5.h5dclose(datasetID) }

        let filespaceID = hdf5.h5dgetSpace(datasetID)
        defer { _ = hdf5.h5sclose(filespaceID) }

        // Same rank-3 handling as readPattern: the whole rank-3 dataset is one
        // "scan row" of the reshaped [1, N, Qy, Qx] cube.
        let fileRank = Int(hdf5.h5sgetSimpleExtentNdims(filespaceID))
        let start: [hsize_t]
        let count: [hsize_t]
        if fileRank == 3 {
            start = [0, 0, 0]
            count = [hsize_t(descriptor.rx), hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        } else {
            start = [hsize_t(ry), 0, 0, 0]
            count = [1, hsize_t(descriptor.rx), hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        }
        let selectionStatus = start.withUnsafeBufferPointer { startBuffer in
            count.withUnsafeBufferPointer { countBuffer in
                hdf5.h5sselectHyperslab(
                    filespaceID,
                    h5SelectSet,
                    startBuffer.baseAddress,
                    nil,
                    countBuffer.baseAddress,
                    nil
                )
            }
        }
        guard selectionStatus >= 0 else { throw H5Error.readFailed("scan-row hyperslab selection") }

        let memoryDimensions: [hsize_t] = [hsize_t(descriptor.rx), hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        let memorySpaceID = memoryDimensions.withUnsafeBufferPointer {
            hdf5.h5screateSimple(3, $0.baseAddress, nil)
        }
        defer { _ = hdf5.h5sclose(memorySpaceID) }

        var buffer = [Float](repeating: 0, count: descriptor.rx * descriptor.qy * descriptor.qx)
        let status = buffer.withUnsafeMutableBytes {
            hdf5.h5dread(datasetID, hdf5.nativeFloat, memorySpaceID, filespaceID, h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0 else { throw H5Error.readFailed("scan row \(ry)") }
        return buffer
    }

    func readScanTile(_ descriptor: DatasetDescriptor,
                      yRange: Range<Int>) throws -> FourDScanTile {
        silenceAutomaticErrors()
        guard yRange.lowerBound >= 0, yRange.upperBound <= descriptor.ry,
              !yRange.isEmpty else {
            throw H5Error.readFailed("invalid scan tile \(yRange)")
        }
        let datasetID = descriptor.datasetPath.withCString {
            hdf5.h5dopen2(fileID, $0, h5DefaultProperty)
        }
        guard datasetID >= 0 else { throw H5Error.datasetOpenFailed(descriptor.datasetPath) }
        defer { _ = hdf5.h5dclose(datasetID) }
        let filespaceID = hdf5.h5dgetSpace(datasetID)
        defer { _ = hdf5.h5sclose(filespaceID) }

        let fileRank = Int(hdf5.h5sgetSimpleExtentNdims(filespaceID))
        let start: [hsize_t]
        let count: [hsize_t]
        if fileRank == 3 {
            guard yRange == 0..<1 else {
                throw H5Error.readFailed("rank-3 tile must be the sole scan row")
            }
            start = [0, 0, 0]
            count = [hsize_t(descriptor.rx), hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        } else {
            start = [hsize_t(yRange.lowerBound), 0, 0, 0]
            count = [hsize_t(yRange.count), hsize_t(descriptor.rx),
                     hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        }
        let selected = start.withUnsafeBufferPointer { starts in
            count.withUnsafeBufferPointer { counts in
                hdf5.h5sselectHyperslab(filespaceID, h5SelectSet,
                                        starts.baseAddress, nil, counts.baseAddress, nil)
            }
        }
        guard selected >= 0 else { throw H5Error.readFailed("scan-tile hyperslab selection") }

        let memoryDimensions: [hsize_t] = fileRank == 3
            ? [hsize_t(descriptor.rx), hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
            : [hsize_t(yRange.count), hsize_t(descriptor.rx),
               hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
        let memorySpaceID = memoryDimensions.withUnsafeBufferPointer {
            hdf5.h5screateSimple(Int32(memoryDimensions.count), $0.baseAddress, nil)
        }
        defer { _ = hdf5.h5sclose(memorySpaceID) }
        let pixelCount = yRange.count * descriptor.rx * descriptor.qy * descriptor.qx
        var pixels = [Float](repeating: 0, count: pixelCount)
        let status = pixels.withUnsafeMutableBytes {
            hdf5.h5dread(datasetID, hdf5.nativeFloat, memorySpaceID, filespaceID,
                         h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0 else { throw H5Error.readFailed("scan tile \(yRange)") }
        return FourDScanTile(
            yRange: yRange, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
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
    func pixelCalibration() -> PixelCalibration? {
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

    func readDoubleAttribute(_ name: String, onObjectPath path: String = "/") -> Double? {
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
