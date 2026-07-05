import Darwin
import Foundation

typealias hid_t = Int64
typealias herr_t = Int32
typealias hsize_t = UInt64

nonisolated private let h5ReadOnly: UInt32 = 0x0000
nonisolated private let h5DefaultProperty: hid_t = 0
nonisolated private let h5SelectSet: Int32 = 0
nonisolated private let h5ChunkedLayout: Int32 = 2
nonisolated private let h5FloatClass: Int32 = 1
nonisolated private let h5IntegerClass: Int32 = 0
nonisolated private let h5TwosComplementSign: Int32 = 1

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
    typealias H5Oopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Oclose = @convention(c) (hid_t) -> herr_t
    typealias H5Aopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Aclose = @convention(c) (hid_t) -> herr_t
    typealias H5Aread = @convention(c) (hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t

    let handle: UnsafeMutableRawPointer
    let h5open: H5open
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
    let h5oopen: H5Oopen
    let h5oclose: H5Oclose
    let h5aopen: H5Aopen
    let h5aclose: H5Aclose
    let h5aread: H5Aread
    let nativeFloat: hid_t
    let nativeDouble: hid_t

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

        return HDF5Library(
            handle: handle,
            h5open: h5open,
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
            h5oopen: try symbol("H5Oopen", as: H5Oopen.self),
            h5oclose: try symbol("H5Oclose", as: H5Oclose.self),
            h5aopen: try symbol("H5Aopen", as: H5Aopen.self),
            h5aclose: try symbol("H5Aclose", as: H5Aclose.self),
            h5aread: try symbol("H5Aread", as: H5Aread.self),
            nativeFloat: try global("H5T_NATIVE_FLOAT_g", as: hid_t.self),
            nativeDouble: try global("H5T_NATIVE_DOUBLE_g", as: hid_t.self)
        )
    }

    private static func candidateLibraryPaths() -> [String] {
        [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libhdf5.dylib").path,
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("../Frameworks/libhdf5.dylib").standardized.path
        ].compactMap { $0 }
    }
}

actor H5Reader {
    private let hdf5: HDF5Library
    private let fileID: hid_t
    let filePath: String

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
        for path in Self.candidatePaths {
            if let descriptor = try? describe(path: path), descriptor.is4D {
                return descriptor
            }
        }
        throw H5Error.noDatasetFound(Self.candidatePaths)
    }

    func describe(path: String) throws -> DatasetDescriptor {
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

        return DatasetDescriptor(
            filePath: filePath,
            datasetPath: path,
            shape: shape,
            dtypeDescription: describeType(typeID),
            chunkShape: chunkShape
        )
    }

    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float] {
        let datasetID = descriptor.datasetPath.withCString { hdf5.h5dopen2(fileID, $0, h5DefaultProperty) }
        guard datasetID >= 0 else { throw H5Error.datasetOpenFailed(descriptor.datasetPath) }
        defer { _ = hdf5.h5dclose(datasetID) }

        let filespaceID = hdf5.h5dgetSpace(datasetID)
        defer { _ = hdf5.h5sclose(filespaceID) }

        let start: [hsize_t] = [hsize_t(ry), hsize_t(rx), 0, 0]
        let count: [hsize_t] = [1, 1, hsize_t(descriptor.qy), hsize_t(descriptor.qx)]
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

    func readDoubleAttribute(_ name: String, onObjectPath path: String = "/") -> Double? {
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
}
