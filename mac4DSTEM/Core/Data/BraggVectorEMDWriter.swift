import Darwin
import Foundation

/// One scalar real-space result persisted as a py4DSTEM `RealSlice`.
/// Pixels use app row-major `[y][x]`, which is the same memory order as
/// py4DSTEM's real-space `[R_Nx,R_Ny]` convention established by H5Reader.
nonisolated struct ScalarResultMap: Sendable {
    static let legacyEMDName = "result_map"

    let width: Int
    let height: Int
    let pixels: [Float]
    let kind: String
    let displayName: String
    let valueUnits: String

    init(width: Int, height: Int, pixels: [Float], kind: String,
         displayName: String, valueUnits: String) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.kind = kind
        self.displayName = displayName
        self.valueUnits = valueUnits
    }
}

/// One pre-colored scan-shaped scientific result (for example DPC direction
/// or cubic IPF-Z), persisted losslessly as uint8 `[height,width,RGBA]`.
nonisolated struct RGBAResultMap: Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]
    let kind: String
    let displayName: String
    let valueUnits: String
}

nonisolated enum SessionResultStorage: String, Sendable {
    case scalarFloat32 = "scalar_f32"
    case rgba8 = "rgba8"
}

/// Lightweight on-disk map metadata used by the session inventory. The `id`
/// is the stable HDF5 node name, not a user-visible label.
nonisolated struct SessionResultDescriptor: Identifiable, Sendable, Equatable {
    let id: String
    let kind: String
    let displayName: String
    let valueUnits: String
    let width: Int
    let height: Int
    let storage: SessionResultStorage
}

nonisolated struct SessionSidecarInventory: Sendable, Equatable {
    static let empty = SessionSidecarInventory(
        hasSidecar: false, hasBraggVectors: false, hasCalibration: false,
        results: [], currentResultID: nil
    )

    let hasSidecar: Bool
    let hasBraggVectors: Bool
    let hasCalibration: Bool
    let results: [SessionResultDescriptor]
    let currentResultID: String?
}

nonisolated struct SessionSidecarSnapshot: Sendable {
    let inventory: SessionSidecarInventory
    let calibration: PixelCalibration?
    let currentResult: ScalarResultMap?
    let currentRGBAResult: RGBAResultMap?
}

/// Bounded preprocessing applied while streaming a source datacube into a
/// canonical py4DSTEM EMD file. Ranges use app/HDF5 order `[Ry,Rx]` and Q
/// binning sums non-overlapping detector blocks, matching py4DSTEM's count-
/// preserving diffraction binning semantics.
nonisolated struct CalibratedDataCubeExportOptions: Sendable, Equatable {
    let scanY: Range<Int>
    let scanX: Range<Int>
    let qBin: Int
    let tileRows: Int

    init(scanY: Range<Int>, scanX: Range<Int>, qBin: Int = 1, tileRows: Int = 1) {
        self.scanY = scanY
        self.scanX = scanX
        self.qBin = qBin
        self.tileRows = tileRows
    }
}

nonisolated struct CalibratedDataCubeExportSummary: Sendable, Equatable {
    let shape: [Int]
    let discardedQRows: Int
    let discardedQColumns: Int
}

/// Writes the detected peak grid as a py4DSTEM 0.14 / EMD 1.0 BraggVectors
/// sidecar. The source dataset is never opened for writing. Publication is an
/// atomic rename of a completed sibling temporary file, so cancellation or an
/// HDF5 failure cannot leave a partial result at the requested destination.
nonisolated enum BraggVectorEMDWriter {
    private static let rootPath = "/braggvectors_root"
    private static let schemaAttribute = "mac4dstem_session_schema"
    private static let resultNodesAttribute = "mac4dstem_result_nodes"
    private static let currentResultAttribute = "mac4dstem_current_result"
    private static let sessionSchemaVersion = "3"

    enum WriterError: LocalizedError {
        case cancelled
        case invalidDimensions(String)
        case libraryUnavailable(String)
        case symbolMissing(String)
        case hdf5(String)
        case publishFailed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "The sidecar operation was cancelled."
            case .invalidDimensions(let detail):
                return "Cannot write or load the sidecar: \(detail)"
            case .libraryUnavailable(let detail):
                return "Could not load the bundled HDF5 library: \(detail)"
            case .symbolMissing(let name):
                return "The HDF5 library is missing required symbol \(name)."
            case .hdf5(let operation):
                return "HDF5 export failed while \(operation)."
            case .publishFailed(let detail):
                return "Could not publish the completed sidecar: \(detail)"
            }
        }
    }

    /// Stable discoverable companion path used for automatic reload.
    static func sessionSidecarURL(forSourcePath path: String) -> URL {
        let source = URL(fileURLWithPath: path)
        let stem = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent()
            .appendingPathComponent(stem + ".mac4dstem.h5", isDirectory: false)
    }

    /// `qHeight` is the detector row count and becomes py4DSTEM Qshape[0];
    /// `qWidth` is the detector column count and becomes Qshape[1].
    static func write(
        vectors: BraggVectors,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight)
        try publish(vectors: vectors, map: nil, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: nil, to: destination,
                    cancellation: cancellation, progress: progress)
    }

    /// Stream a real-space crop through an optional integer detector bin into
    /// a canonical float32 py4DSTEM DataCube. Source reads and destination
    /// writes stay bounded by `tileRows`; the final file appears atomically.
    static func writeCalibratedDataCube(
        source: any FourDDataSource,
        descriptor: DatasetDescriptor,
        calibration: PixelCalibration,
        options: CalibratedDataCubeExportOptions,
        to destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CalibratedDataCubeExportSummary {
        guard options.scanY.lowerBound >= 0,
              options.scanY.upperBound <= descriptor.ry,
              options.scanX.lowerBound >= 0,
              options.scanX.upperBound <= descriptor.rx,
              !options.scanY.isEmpty, !options.scanX.isEmpty else {
            throw WriterError.invalidDimensions("the real-space crop is outside the source scan")
        }
        guard options.qBin > 0, options.qBin <= descriptor.qy,
              options.qBin <= descriptor.qx else {
            throw WriterError.invalidDimensions("the diffraction bin factor is invalid")
        }
        guard options.tileRows > 0 else {
            throw WriterError.invalidDimensions("the export tile height must be positive")
        }
        let outQY = descriptor.qy / options.qBin
        let outQX = descriptor.qx / options.qBin
        guard outQY > 0, outQX > 0 else {
            throw WriterError.invalidDimensions("the binned diffraction shape is empty")
        }
        let summary = CalibratedDataCubeExportSummary(
            shape: [options.scanY.count, options.scanX.count, outQY, outQX],
            discardedQRows: descriptor.qy - outQY * options.qBin,
            discardedQColumns: descriptor.qx - outQX * options.qBin
        )

        try checkCancellation(cancellation)
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        var published = false
        defer { if !published { try? fm.removeItem(at: temporary) } }
        let h5 = try HDF5WriteLibrary.load()
        try await writeCalibratedDataCubeFile(
            at: temporary, source: source, descriptor: descriptor,
            calibration: transformedCalibration(calibration, descriptor: descriptor,
                                                options: options),
            options: options, outputShape: summary.shape,
            cancellation: cancellation, progress: progress, hdf5: h5
        )
        try checkCancellation(cancellation)
        let renamed = temporary.path.withCString { sourcePath in
            destination.path.withCString { targetPath in Darwin.rename(sourcePath, targetPath) }
        }
        guard renamed == 0 else {
            throw WriterError.publishFailed(String(cString: strerror(errno)))
        }
        published = true
        return summary
    }

    /// Add or replace the stable scalar result in a session sidecar. If the
    /// existing sidecar contains BraggVectors and no new vectors are supplied,
    /// HDF5 copies that object into the new temporary file before publication.
    static func mergeResultMap(
        _ map: ScalarResultMap,
        vectors: BraggVectors?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard map.width > 0, map.height > 0,
              map.pixels.count == map.width * map.height else {
            throw WriterError.invalidDimensions("the scalar result map is inconsistent")
        }
        if let vectors { try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight) }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        try publish(vectors: vectors, map: map, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    cancellation: cancellation, progress: progress)
    }

    static func mergeRGBAResultMap(
        _ map: RGBAResultMap,
        vectors: BraggVectors?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard map.width > 0, map.height > 0,
              map.rgba.count == map.width * map.height * 4 else {
            throw WriterError.invalidDimensions("the RGBA result map is inconsistent")
        }
        if let vectors { try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight) }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        try publish(vectors: vectors, map: nil, rgbaMap: map,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    cancellation: cancellation, progress: progress)
    }

    /// Atomically replace the session calibration while preserving every
    /// supported result object already present in the companion file.
    static func mergeCalibration(
        _ calibration: PixelCalibration,
        qWidth: Int,
        qHeight: Int,
        to destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        try publish(vectors: nil, map: nil, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    cancellation: cancellation, progress: progress)
    }

    /// Atomically remove one named result while preserving calibration,
    /// BraggVectors, and every other supported scalar/RGBA result.
    static func removeResult(
        kind: String,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        from destination: URL,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard qWidth > 0, qHeight > 0,
              FileManager.default.fileExists(atPath: destination.path) else {
            throw WriterError.invalidDimensions("the session sidecar does not exist")
        }
        try publish(
            vectors: nil, map: nil, rgbaMap: nil,
            qWidth: qWidth, qHeight: qHeight, calibration: calibration,
            preserving: destination, to: destination, removingKind: kind,
            cancellation: cancellation, progress: progress
        )
    }

    /// Load the complete supported session inventory and the map recorded as
    /// current. Legacy one-slot sidecars are treated as a one-map inventory.
    static func loadSession(from url: URL) throws -> SessionSidecarSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SessionSidecarSnapshot(
                inventory: .empty, calibration: nil, currentResult: nil,
                currentRGBAResult: nil
            )
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("opening the session sidecar") }
        defer { _ = h5.h5fclose(fileID) }

        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw WriterError.hdf5("opening the session root") }
        defer { _ = h5.h5gclose(root) }

        let results = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        let recordedCurrent = try readStringAttribute(currentResultAttribute, on: root, hdf5: h5)
        let currentID = recordedCurrent.flatMap { id in
            results.contains(where: { $0.id == id }) ? id : nil
        } ?? results.last?.id
        let currentDescriptor = currentID.flatMap { id in
            results.first(where: { $0.id == id })
        }
        let currentResult = try currentDescriptor.flatMap { descriptor in
            descriptor.storage == .scalarFloat32
                ? try readResultMap(nodeName: descriptor.id, from: root, hdf5: h5)
                : nil
        }
        let currentRGBAResult = try currentDescriptor.flatMap { descriptor in
            descriptor.storage == .rgba8
                ? try readRGBAResultMap(nodeName: descriptor.id, from: root, hdf5: h5)
                : nil
        }
        let calibration = try readCalibration(from: root, hdf5: h5)
        let inventory = SessionSidecarInventory(
            hasSidecar: true,
            hasBraggVectors: linkExists("\(rootPath)/braggvectors", in: fileID, hdf5: h5),
            hasCalibration: calibration != nil,
            results: results,
            currentResultID: currentID
        )
        return SessionSidecarSnapshot(
            inventory: inventory, calibration: calibration,
            currentResult: currentResult, currentRGBAResult: currentRGBAResult
        )
    }

    static func loadInventory(from url: URL) throws -> SessionSidecarInventory {
        try loadSession(from: url).inventory
    }

    static func loadResultMap(from url: URL) throws -> ScalarResultMap? {
        try loadSession(from: url).currentResult
    }

    static func loadResultMap(id: String, from url: URL) throws -> ScalarResultMap? {
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("opening the session sidecar") }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw WriterError.hdf5("opening the session root") }
        defer { _ = h5.h5gclose(root) }
        let descriptors = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        guard descriptors.contains(where: {
            $0.id == id && $0.storage == .scalarFloat32
        }) else { return nil }
        return try readResultMap(nodeName: id, from: root, hdf5: h5)
    }

    static func loadRGBAResultMap(id: String, from url: URL) throws -> RGBAResultMap? {
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("opening the session sidecar") }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw WriterError.hdf5("opening the session root") }
        defer { _ = h5.h5gclose(root) }
        let descriptors = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        guard descriptors.contains(where: { $0.id == id && $0.storage == .rgba8 }) else {
            return nil
        }
        return try readRGBAResultMap(nodeName: id, from: root, hdf5: h5)
    }

    /// Deterministic, HDF5-safe node name. The hash avoids collisions when two
    /// future result kinds sanitize to the same ASCII slug.
    static func resultNodeName(forKind kind: String) -> String {
        var slug = ""
        var previousUnderscore = false
        for scalar in kind.lowercased().unicodeScalars {
            let value = scalar.value
            let isLetter = value >= 97 && value <= 122
            let isDigit = value >= 48 && value <= 57
            if isLetter || isDigit {
                slug.unicodeScalars.append(scalar)
                previousUnderscore = false
            } else if !previousUnderscore, !slug.isEmpty {
                slug.append("_")
                previousUnderscore = true
            }
        }
        while slug.last == "_" { slug.removeLast() }
        if slug.isEmpty { slug = "map" }

        var hash: UInt32 = 2_166_136_261
        for byte in kind.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return "result_\(slug)_\(String(format: "%08x", hash))"
    }

    private static func readResultDescriptors(
        from root: hid_t, file: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> [SessionResultDescriptor] {
        var nodeNames: [String]
        if let manifest = try readStringAttribute(resultNodesAttribute, on: root, hdf5: h5) {
            nodeNames = manifest.split(separator: "\n").map(String.init)
        } else if linkExists("\(rootPath)/\(ScalarResultMap.legacyEMDName)",
                             in: file, hdf5: h5) {
            nodeNames = [ScalarResultMap.legacyEMDName]
        } else {
            nodeNames = []
        }

        var seen = Set<String>()
        var results: [SessionResultDescriptor] = []
        for nodeName in nodeNames where isSafeNodeName(nodeName) && seen.insert(nodeName).inserted {
            guard linkExists("\(rootPath)/\(nodeName)", in: file, hdf5: h5),
                  let descriptor = try readResultDescriptor(
                    nodeName: nodeName, from: root, hdf5: h5
                  ) else { continue }
            results.append(descriptor)
        }
        return results
    }

    private static func readCalibration(
        from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> PixelCalibration? {
        let group = "metadatabundle/calibration".withCString {
            h5.h5gopen2(root, $0, h5DefaultProperty)
        }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }

        var calibration = PixelCalibration(
            rSize: try readDoubleDataset("R_pixel_size", from: group, hdf5: h5),
            rUnits: try readStringDataset("R_pixel_units", from: group, hdf5: h5),
            qSize: try readDoubleDataset("Q_pixel_size", from: group, hdf5: h5),
            qUnits: try readStringDataset("Q_pixel_units", from: group, hdf5: h5),
            qrFlip: try readBoolDataset("QR_flip", from: group, hdf5: h5)
        )
        calibration.qx0Mean = try readDoubleDataset("qx0_mean", from: group, hdf5: h5)
        calibration.qy0Mean = try readDoubleDataset("qy0_mean", from: group, hdf5: h5)
        calibration.ellipseA = try readDoubleDataset("a", from: group, hdf5: h5)
        calibration.ellipseB = try readDoubleDataset("b", from: group, hdf5: h5)
        calibration.ellipseTheta = try readDoubleDataset("theta", from: group, hdf5: h5)
        calibration.qrRotationRad = try readDoubleDataset(
            "QR_rotation", from: group, hdf5: h5
        )
        calibration.probeSemiangle = try readDoubleDataset(
            "probe_semiangle", from: group, hdf5: h5
        )
        if let qx0 = try readDoubleMatrix("qx0", from: group, hdf5: h5),
           let qy0 = try readDoubleMatrix("qy0", from: group, hdf5: h5),
           qx0.shape == qy0.shape {
            let measuredQX = try readDoubleMatrix("qx0_meas", from: group, hdf5: h5)
            let measuredQY = try readDoubleMatrix("qy0_meas", from: group, hdf5: h5)
            let measuredPair = measuredQX?.shape == qx0.shape
                && measuredQY?.shape == qx0.shape
            calibration.originMaps = PixelOriginMaps(
                shape: qx0.shape,
                fittedQX: qx0.values,
                fittedQY: qy0.values,
                measuredQX: measuredPair ? measuredQX?.values : nil,
                measuredQY: measuredPair ? measuredQY?.values : nil
            )
        }
        let hasValue = calibration.rSize != nil || calibration.rUnits != nil
            || calibration.qSize != nil || calibration.qUnits != nil
            || calibration.qrFlip != nil || calibration.qx0Mean != nil
            || calibration.qy0Mean != nil || calibration.originMaps != nil
            || calibration.ellipseA != nil || calibration.ellipseB != nil
            || calibration.ellipseTheta != nil || calibration.qrRotationRad != nil
            || calibration.probeSemiangle != nil
        return hasValue ? calibration : nil
    }

    private static func readDoubleDataset(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> Double? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        var value = 0.0
        guard withUnsafeMutablePointer(to: &value, {
            h5.h5dread(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        return value.isFinite ? value : nil
    }

    private static func readBoolDataset(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> Bool? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        var value = false
        guard withUnsafeMutablePointer(to: &value, {
            h5.h5dread(dataset, h5.nativeHBool, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        return value
    }

    private static func readStringDataset(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> String? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let type = h5.h5dgetType(dataset)
        guard type >= 0 else { throw WriterError.hdf5("opening dataset type \(name)") }
        defer { _ = h5.h5tclose(type) }
        var pointer: UnsafeMutablePointer<CChar>?
        guard withUnsafeMutablePointer(to: &pointer, {
            h5.h5dread(dataset, type, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        guard let pointer else { return "" }
        defer { _ = h5.h5freeMemory(pointer) }
        return String(cString: pointer)
    }

    private static func readDoubleMatrix(
        _ name: String, from group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> (shape: [Int], values: [Double])? {
        guard linkExists(name, in: group, hdf5: h5) else { return nil }
        let dataset = name.withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("opening dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        guard h5.h5sgetSimpleExtentNdims(space) == 2 else { return nil }
        var rawShape = [hsize_t](repeating: 0, count: 2)
        guard rawShape.withUnsafeMutableBufferPointer({
            h5.h5sgetSimpleExtentDims(space, $0.baseAddress, nil)
        }) == 2,
        rawShape.allSatisfy({ $0 > 0 && $0 <= hsize_t(Int.max) }) else { return nil }
        let shape = rawShape.map(Int.init)
        guard shape[0] <= Int.max / shape[1] else { return nil }
        var values = [Double](repeating: 0, count: shape[0] * shape[1])
        guard values.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading dataset \(name)") }
        guard values.allSatisfy(\.isFinite) else { return nil }
        return (shape, values)
    }

    private static func readResultDescriptor(
        nodeName: String, from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> SessionResultDescriptor? {
        let group = nodeName.withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        let storage = try readStringAttribute("mac4dstem_storage", on: group, hdf5: h5)
            .flatMap(SessionResultStorage.init(rawValue:)) ?? .scalarFloat32
        guard let (width, height) = try readResultShape(
            from: group, storage: storage, hdf5: h5
        ) else {
            return nil
        }
        return SessionResultDescriptor(
            id: nodeName,
            kind: try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
                ?? "unknown",
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Saved result",
            valueUnits: try readStringAttribute(
                "mac4dstem_value_units", on: group, hdf5: h5
            ) ?? "intensity",
            width: width,
            height: height,
            storage: storage
        )
    }

    private static func readResultMap(
        nodeName: String, from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> ScalarResultMap? {
        let group = nodeName.withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        guard let (width, height) = try readResultShape(
            from: group, storage: .scalarFloat32, hdf5: h5
        ) else {
            return nil
        }
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        var pixels = [Float](repeating: 0, count: width * height)
        guard pixels.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeFloat, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading the scalar result pixels") }
        return ScalarResultMap(
            width: width,
            height: height,
            pixels: pixels,
            kind: try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
                ?? "unknown",
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Restored result",
            valueUnits: try readStringAttribute(
                "mac4dstem_value_units", on: group, hdf5: h5
            ) ?? "intensity"
        )
    }

    private static func readRGBAResultMap(
        nodeName: String, from root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> RGBAResultMap? {
        let group = nodeName.withCString { h5.h5gopen2(root, $0, h5DefaultProperty) }
        guard group >= 0 else { return nil }
        defer { _ = h5.h5gclose(group) }
        guard let (width, height) = try readResultShape(
            from: group, storage: .rgba8, hdf5: h5
        ) else { return nil }
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard rgba.withUnsafeMutableBytes({
            h5.h5dread(dataset, h5.nativeUChar, h5EntireDataspace, h5EntireDataspace,
                       h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("reading the RGBA result pixels") }
        return RGBAResultMap(
            width: width, height: height, rgba: rgba,
            kind: try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
                ?? "unknown",
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Restored RGBA result",
            valueUnits: try readStringAttribute(
                "mac4dstem_value_units", on: group, hdf5: h5
            ) ?? "rgba"
        )
    }

    private static func readResultShape(
        from group: hid_t, storage: SessionResultStorage,
        hdf5 h5: HDF5WriteLibrary
    ) throws -> (width: Int, height: Int)? {
        let dataset = "data".withCString { h5.h5dopen2(group, $0, h5DefaultProperty) }
        guard dataset >= 0 else { return nil }
        defer { _ = h5.h5dclose(dataset) }
        let space = h5.h5dgetSpace(dataset)
        guard space >= 0 else { throw WriterError.hdf5("opening the scalar result dataspace") }
        defer { _ = h5.h5sclose(space) }
        let rank = storage == .rgba8 ? 3 : 2
        guard h5.h5sgetSimpleExtentNdims(space) == rank else { return nil }
        var dimensions = [hsize_t](repeating: 0, count: rank)
        guard dimensions.withUnsafeMutableBufferPointer({
            h5.h5sgetSimpleExtentDims(space, $0.baseAddress, nil)
        }) == rank else { throw WriterError.hdf5("reading the result shape") }
        if storage == .rgba8, dimensions[2] != 4 { return nil }
        guard dimensions[0] <= hsize_t(Int.max), dimensions[1] <= hsize_t(Int.max) else {
            return nil
        }
        let height = Int(dimensions[0]), width = Int(dimensions[1])
        guard width > 0, height > 0, width <= Int.max / height else { return nil }
        return (width, height)
    }

    private static func isSafeNodeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 160 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (value >= 97 && value <= 122)
                || (value >= 48 && value <= 57)
                || value == 95
        }
    }

    private static func validate(vectors: BraggVectors, qWidth: Int, qHeight: Int) throws {
        guard vectors.scanWidth > 0, vectors.scanHeight > 0,
              vectors.peaks.count == vectors.scanWidth * vectors.scanHeight else {
            throw WriterError.invalidDimensions("the scan grid is inconsistent")
        }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
    }

    private static func publish(
        vectors: BraggVectors?, map: ScalarResultMap?, rgbaMap: RGBAResultMap?,
        qWidth: Int, qHeight: Int,
        calibration: PixelCalibration, preserving existing: URL?, to destination: URL,
        removingKind: String? = nil,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        try checkCancellation(cancellation)

        let fm = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        var published = false
        defer {
            if !published { try? fm.removeItem(at: temporary) }
        }

        let hdf5 = try HDF5WriteLibrary.load()
        try writeFile(
            at: temporary, vectors: vectors, map: map, rgbaMap: rgbaMap,
            qWidth: qWidth, qHeight: qHeight,
            calibration: calibration, preserving: existing, removingKind: removingKind,
            cancellation: cancellation,
            progress: progress, hdf5: hdf5
        )
        try checkCancellation(cancellation)

        let renameStatus = temporary.path.withCString { source in
            destination.path.withCString { target in Darwin.rename(source, target) }
        }
        guard renameStatus == 0 else {
            throw WriterError.publishFailed(String(cString: strerror(errno)))
        }
        published = true
    }

    private static func checkCancellation(_ token: AnalysisCancellationToken?) throws {
        if token?.isCancelled == true { throw WriterError.cancelled }
    }

    private static func transformedCalibration(
        _ source: PixelCalibration,
        descriptor: DatasetDescriptor,
        options: CalibratedDataCubeExportOptions
    ) -> PixelCalibration {
        var output = source
        let bin = Double(options.qBin)
        output.qSize = source.qSize.map { $0 * bin }
        let transformQ: (Double) -> Double = { ($0 + 0.5) / bin - 0.5 }
        output.qx0Mean = source.qx0Mean.map(transformQ)
        output.qy0Mean = source.qy0Mean.map(transformQ)
        output.probeSemiangle = source.probeSemiangle.map { $0 / bin }

        if let maps = source.originMaps,
           maps.shape == [descriptor.ry, descriptor.rx],
           maps.fittedQX.count == descriptor.ry * descriptor.rx,
           maps.fittedQY.count == descriptor.ry * descriptor.rx {
            func cropped(_ values: [Double]?) -> [Double]? {
                guard let values, values.count == descriptor.ry * descriptor.rx else {
                    return nil
                }
                var result = [Double]()
                result.reserveCapacity(options.scanY.count * options.scanX.count)
                for y in options.scanY {
                    for x in options.scanX {
                        result.append(transformQ(values[y * descriptor.rx + x]))
                    }
                }
                return result
            }
            let fittedQX = cropped(maps.fittedQX) ?? []
            let fittedQY = cropped(maps.fittedQY) ?? []
            output.originMaps = PixelOriginMaps(
                shape: [options.scanY.count, options.scanX.count],
                fittedQX: fittedQX, fittedQY: fittedQY,
                measuredQX: cropped(maps.measuredQX),
                measuredQY: cropped(maps.measuredQY)
            )
            output.qx0Mean = fittedQX.isEmpty
                ? output.qx0Mean : fittedQX.reduce(0, +) / Double(fittedQX.count)
            output.qy0Mean = fittedQY.isEmpty
                ? output.qy0Mean : fittedQY.reduce(0, +) / Double(fittedQY.count)
        }
        return output
    }

    private static func writeCalibratedDataCubeFile(
        at url: URL,
        source: any FourDDataSource,
        descriptor: DatasetDescriptor,
        calibration: PixelCalibration,
        options: CalibratedDataCubeExportOptions,
        outputShape: [Int],
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) async throws {
        let fileID = url.path.withCString {
            h5.h5fcreate($0, h5FileTruncate, h5DefaultProperty, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("creating the calibrated datacube") }
        defer { _ = h5.h5fclose(fileID) }

        try writeStringAttribute("emd_group_type", value: "file", on: fileID, hdf5: h5)
        try writeScalarAttribute("version_major", value: Int32(1), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeScalarAttribute("version_minor", value: Int32(0), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeStringAttribute("UUID", value: UUID().uuidString, on: fileID, hdf5: h5)
        try writeStringAttribute("authoring_program", value: "mac4DSTEM", on: fileID, hdf5: h5)
        try writeStringAttribute("authoring_user", value: "", on: fileID, hdf5: h5)

        let root = try createGroup("datacube_root", in: fileID, hdf5: h5)
        defer { _ = h5.h5gclose(root) }
        try writeNodeAttributes(groupType: "root", pythonClass: "Root", on: root, hdf5: h5)
        let cube = try createGroup("datacube", in: root, hdf5: h5)
        defer { _ = h5.h5gclose(cube) }
        try writeNodeAttributes(groupType: "array", pythonClass: "DataCube", on: cube, hdf5: h5)

        let dimensions = outputShape.map(hsize_t.init)
        let fileSpace = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(4, $0.baseAddress, nil)
        }
        guard fileSpace >= 0 else { throw WriterError.hdf5("creating the datacube dataspace") }
        defer { _ = h5.h5sclose(fileSpace) }
        let creation = h5.h5pcreate(h5.datasetCreatePropertyClass)
        guard creation >= 0 else { throw WriterError.hdf5("creating the chunk property list") }
        defer { _ = h5.h5pclose(creation) }
        let chunk = [hsize_t(1), hsize_t(1), dimensions[2], dimensions[3]]
        guard chunk.withUnsafeBufferPointer({
            h5.h5psetChunk(creation, 4, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("configuring datacube chunks") }
        let dataset = "data".withCString {
            h5.h5dcreate2(cube, $0, h5.nativeFloat, fileSpace, h5DefaultProperty,
                          creation, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the datacube dataset") }
        defer { _ = h5.h5dclose(dataset) }
        try writeStringAttribute("units", value: "pixel intensity", on: dataset, hdf5: h5)

        let rStep = calibration.rSize ?? 1
        let qStep = calibration.qSize ?? 1
        let rUnits = calibration.rUnits ?? "pixels"
        let qUnits = calibration.qUnits ?? "pixels"
        func linearDimension(count: Int, step: Double) -> [Double] {
            count > 1 ? [0, step] : [0]
        }
        try writeDoubleVectorDataset("dim0", values: linearDimension(count: outputShape[0], step: rStep), name: "Rx",
                                     units: rUnits, in: cube, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: linearDimension(count: outputShape[1], step: rStep), name: "Ry",
                                     units: rUnits, in: cube, hdf5: h5)
        try writeDoubleVectorDataset("dim2", values: linearDimension(count: outputShape[2], step: qStep), name: "Qx",
                                     units: qUnits, in: cube, hdf5: h5)
        try writeDoubleVectorDataset("dim3", values: linearDimension(count: outputShape[3], step: qStep), name: "Qy",
                                     units: qUnits, in: cube, hdf5: h5)
        try writeCalibration(calibration, targetPath: "/datacube", in: root, hdf5: h5)

        let outQY = outputShape[2], outQX = outputShape[3]
        let sourcePatternCount = descriptor.qy * descriptor.qx
        var sourceY = options.scanY.lowerBound
        while sourceY < options.scanY.upperBound {
            try checkCancellation(cancellation)
            let endY = min(sourceY + options.tileRows, options.scanY.upperBound)
            let sourceTile = try await source.readScanTile(descriptor, yRange: sourceY..<endY)
            try checkCancellation(cancellation)
            var output = [Float](repeating: 0,
                count: (endY - sourceY) * options.scanX.count * outQY * outQX)
            for localY in 0..<(endY - sourceY) {
                for (outX, sourceX) in options.scanX.enumerated() {
                    let inputBase = (localY * descriptor.rx + sourceX) * sourcePatternCount
                    let outputBase = (localY * options.scanX.count + outX) * outQY * outQX
                    for qy in 0..<outQY {
                        for qx in 0..<outQX {
                            var sum: Float = 0
                            for by in 0..<options.qBin {
                                let row = inputBase + (qy * options.qBin + by) * descriptor.qx
                                for bx in 0..<options.qBin {
                                    sum += sourceTile.pixels[row + qx * options.qBin + bx]
                                }
                            }
                            output[outputBase + qy * outQX + qx] = sum
                        }
                    }
                }
            }

            let targetSpace = h5.h5dgetSpace(dataset)
            guard targetSpace >= 0 else { throw WriterError.hdf5("opening the output dataspace") }
            defer { _ = h5.h5sclose(targetSpace) }
            let start = [hsize_t(sourceY - options.scanY.lowerBound), 0, 0, 0]
            let count = [hsize_t(endY - sourceY), hsize_t(options.scanX.count),
                         hsize_t(outQY), hsize_t(outQX)]
            let selected = start.withUnsafeBufferPointer { starts in
                count.withUnsafeBufferPointer { counts in
                    h5.h5sselectHyperslab(targetSpace, h5SelectSet, starts.baseAddress,
                                          nil, counts.baseAddress, nil)
                }
            }
            guard selected >= 0 else { throw WriterError.hdf5("selecting the output tile") }
            let memorySpace = count.withUnsafeBufferPointer {
                h5.h5screateSimple(4, $0.baseAddress, nil)
            }
            guard memorySpace >= 0 else { throw WriterError.hdf5("creating the output tile dataspace") }
            let wrote = output.withUnsafeBytes {
                h5.h5dwrite(dataset, h5.nativeFloat, memorySpace, targetSpace,
                            h5DefaultProperty, $0.baseAddress)
            }
            _ = h5.h5sclose(memorySpace)
            guard wrote >= 0 else { throw WriterError.hdf5("writing the output tile") }
            sourceY = endY
            progress?(Double(sourceY - options.scanY.lowerBound) / Double(options.scanY.count))
        }
        try checkCancellation(cancellation)
        progress?(1)
    }

    private static func writeFile(
        at url: URL,
        vectors: BraggVectors?,
        map: ScalarResultMap?,
        rgbaMap: RGBAResultMap?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        preserving existing: URL?,
        removingKind: String?,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        let fileID = url.path.withCString {
            h5.h5fcreate($0, h5FileTruncate, h5DefaultProperty, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw WriterError.hdf5("creating the temporary file") }
        defer { _ = h5.h5fclose(fileID) }

        let existingID: hid_t? = existing.flatMap { source in
            let id = source.path.withCString {
                h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
            }
            return id >= 0 ? id : nil
        }
        defer {
            if let existingID { _ = h5.h5fclose(existingID) }
        }

        try writeStringAttribute("emd_group_type", value: "file", on: fileID, hdf5: h5)
        try writeScalarAttribute("version_major", value: Int32(1), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeScalarAttribute("version_minor", value: Int32(0), type: h5.nativeInt,
                                 on: fileID, hdf5: h5)
        try writeStringAttribute("UUID", value: UUID().uuidString, on: fileID, hdf5: h5)
        try writeStringAttribute("authoring_program", value: "mac4DSTEM", on: fileID, hdf5: h5)
        // Match emdfile's default without silently embedding the Mac account name.
        try writeStringAttribute("authoring_user", value: "", on: fileID, hdf5: h5)

        let root = try createGroup("braggvectors_root", in: fileID, hdf5: h5)
        defer { _ = h5.h5gclose(root) }
        try writeNodeAttributes(groupType: "root", pythonClass: "Root", on: root, hdf5: h5)

        var existingResults: [SessionResultDescriptor] = []
        if let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                existingResults = try {
                    defer { _ = h5.h5gclose(existingRoot) }
                    return try readResultDescriptors(
                        from: existingRoot, file: existingID, hdf5: h5
                    )
                }()
            }
        }

        let canCopyBragg = vectors == nil && existingID.map {
            linkExists("\(rootPath)/braggvectors", in: $0, hdf5: h5)
        } == true
        try writeCalibration(
            calibration,
            targetPath: vectors != nil || canCopyBragg ? "/braggvectors" : nil,
            in: root, hdf5: h5
        )

        if let vectors {
            let bragg = try createGroup("braggvectors", in: root, hdf5: h5)
            defer { _ = h5.h5gclose(bragg) }
            try writeNodeAttributes(groupType: "custom", pythonClass: "BraggVectors",
                                    on: bragg, hdf5: h5)
            try writeShapeMetadata(scanHeight: vectors.scanHeight, scanWidth: vectors.scanWidth,
                                   qHeight: qHeight, qWidth: qWidth, in: bragg, hdf5: h5)
            try writePeakGrid(vectors, in: bragg, cancellation: cancellation,
                              progress: progress, hdf5: h5)
        } else if canCopyBragg, let existingID {
            try checkCancellation(cancellation)
            let status = "\(rootPath)/braggvectors".withCString { sourceName in
                "braggvectors".withCString { targetName in
                    h5.h5ocopy(existingID, sourceName, root, targetName,
                               h5DefaultProperty, h5DefaultProperty)
                }
            }
            guard status >= 0 else {
                throw WriterError.hdf5("preserving the existing BraggVectors object")
            }
        }

        // Preserve root children that this schema does not understand (for
        // example emdfile Plot nodes or third-party analysis objects). Known
        // mutable objects are rebuilt/copied below; unknown objects move as
        // opaque HDF5 objects so an app save is not destructive to external
        // tooling.
        if let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                defer { _ = h5.h5gclose(existingRoot) }
                let reserved = Set(
                    ["metadatabundle", "braggvectors"] + existingResults.map(\.id)
                )
                for name in childLinkNames(in: existingRoot, hdf5: h5)
                    where !reserved.contains(name) {
                    try checkCancellation(cancellation)
                    let status = name.withCString { sourceName in
                        name.withCString { targetName in
                            h5.h5ocopy(existingRoot, sourceName, root, targetName,
                                       h5DefaultProperty, h5DefaultProperty)
                        }
                    }
                    guard status >= 0 else {
                        throw WriterError.hdf5("preserving external object \(name)")
                    }
                }
            }
        }

        var resultNodeNames: [String] = []
        var copiedNodeNames = Set<String>()
        let replacementKind = map?.kind ?? rgbaMap?.kind ?? removingKind
        if let existingID {
            for descriptor in existingResults where descriptor.kind != replacementKind {
                try checkCancellation(cancellation)
                let targetName = resultNodeName(forKind: descriptor.kind)
                guard copiedNodeNames.insert(targetName).inserted else { continue }
                let sourcePath = "\(rootPath)/\(descriptor.id)"
                let status = sourcePath.withCString { sourceName in
                    targetName.withCString { targetNamePointer in
                        h5.h5ocopy(existingID, sourceName, root, targetNamePointer,
                                   h5DefaultProperty, h5DefaultProperty)
                    }
                }
                guard status >= 0 else {
                    throw WriterError.hdf5("preserving saved result \(descriptor.displayName)")
                }
                resultNodeNames.append(targetName)
            }
        }
        if let map {
            let nodeName = resultNodeName(forKind: map.kind)
            try writeResultMap(map, nodeName: nodeName, calibration: calibration, in: root,
                               cancellation: cancellation, progress: progress, hdf5: h5)
            resultNodeNames.append(nodeName)
        }
        if let rgbaMap {
            let nodeName = resultNodeName(forKind: rgbaMap.kind)
            try writeRGBAResultMap(
                rgbaMap, nodeName: nodeName, calibration: calibration, in: root,
                cancellation: cancellation, progress: progress, hdf5: h5
            )
            resultNodeNames.append(nodeName)
        }
        if !resultNodeNames.isEmpty {
            try writeStringAttribute(schemaAttribute, value: sessionSchemaVersion,
                                     on: root, hdf5: h5)
            try writeStringAttribute(resultNodesAttribute,
                                     value: resultNodeNames.joined(separator: "\n"),
                                     on: root, hdf5: h5)
            try writeStringAttribute(currentResultAttribute,
                                     value: resultNodeNames.last!, on: root, hdf5: h5)
        }
        try checkCancellation(cancellation)
        progress?(1)
    }

    private static func writeCalibration(
        _ calibration: PixelCalibration, targetPath: String?,
        in root: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let bundle = try createGroup("metadatabundle", in: root, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle", on: bundle, hdf5: h5)

        let group = try createGroup("calibration", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Calibration",
                                on: group, hdf5: h5)

        if var qrFlip = calibration.qrFlip {
            try writeScalarDataset("QR_flip", value: &qrFlip, type: h5.nativeHBool,
                                   metadataType: "bool", in: group, hdf5: h5)
        }
        if var value = calibration.qSize {
            try writeScalarDataset("Q_pixel_size", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if let value = calibration.qUnits {
            try writeStringDataset("Q_pixel_units", value: value, metadataType: "string",
                                   in: group, hdf5: h5)
        }
        if var value = calibration.rSize {
            try writeScalarDataset("R_pixel_size", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if let value = calibration.rUnits {
            try writeStringDataset("R_pixel_units", value: value, metadataType: "string",
                                   in: group, hdf5: h5)
        }
        if var value = calibration.qrRotationRad {
            try writeScalarDataset("QR_rotation", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
            var degrees = value * 180 / .pi
            try writeScalarDataset("QR_rotation_degrees", value: &degrees,
                                   type: h5.nativeDouble, metadataType: "number",
                                   in: group, hdf5: h5)
        }
        if var value = calibration.probeSemiangle {
            try writeScalarDataset("probe_semiangle", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = calibration.ellipseA {
            try writeScalarDataset("a", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = calibration.ellipseB {
            try writeScalarDataset("b", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = calibration.ellipseTheta {
            try writeScalarDataset("theta", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }

        let maps = calibration.originMaps
        let mapCount = maps.map { $0.shape.reduce(1, *) }
        let validMaps = maps.flatMap { candidate -> PixelOriginMaps? in
            guard candidate.shape.count == 2,
                  candidate.shape.allSatisfy({ $0 > 0 }),
                  mapCount == candidate.fittedQX.count,
                  mapCount == candidate.fittedQY.count else { return nil }
            return candidate
        }
        let qxMean = calibration.qx0Mean ?? validMaps.map {
            $0.fittedQX.reduce(0, +) / Double($0.fittedQX.count)
        }
        let qyMean = calibration.qy0Mean ?? validMaps.map {
            $0.fittedQY.reduce(0, +) / Double($0.fittedQY.count)
        }
        if var value = qxMean {
            try writeScalarDataset("qx0_mean", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if var value = qyMean {
            try writeScalarDataset("qy0_mean", value: &value, type: h5.nativeDouble,
                                   metadataType: "number", in: group, hdf5: h5)
        }
        if let maps = validMaps {
            try writeDoubleMatrixDataset("qx0", values: maps.fittedQX, shape: maps.shape,
                                         in: group, hdf5: h5)
            try writeDoubleMatrixDataset("qy0", values: maps.fittedQY, shape: maps.shape,
                                         in: group, hdf5: h5)
            if let qxMean, let qyMean {
                try writeDoubleMatrixDataset(
                    "qx0_shift", values: maps.fittedQX.map { $0 - qxMean },
                    shape: maps.shape, in: group, hdf5: h5
                )
                try writeDoubleMatrixDataset(
                    "qy0_shift", values: maps.fittedQY.map { $0 - qyMean },
                    shape: maps.shape, in: group, hdf5: h5
                )
            }
            if let measuredQX = maps.measuredQX,
               let measuredQY = maps.measuredQY,
               measuredQX.count == maps.fittedQX.count,
               measuredQY.count == maps.fittedQY.count {
                try writeDoubleMatrixDataset("qx0_meas", values: measuredQX,
                                             shape: maps.shape, in: group, hdf5: h5)
                try writeDoubleMatrixDataset("qy0_meas", values: measuredQY,
                                             shape: maps.shape, in: group, hdf5: h5)
            }
        }
        if let targetPath {
            try writeStringDataset("_root_treepath", value: "", metadataType: "string",
                                   in: group, hdf5: h5)
            let targets = try createGroup("_target_paths", in: group, hdf5: h5)
            defer { _ = h5.h5gclose(targets) }
            try writeStringAttribute("type", value: "list_of_strings", on: targets, hdf5: h5)
            try writeScalarAttribute("length", value: Int32(1), type: h5.nativeInt,
                                     on: targets, hdf5: h5)
            try writeStringDataset("0", value: targetPath, metadataType: nil,
                                   in: targets, hdf5: h5)
        }
    }

    private static func writeResultMap(
        _ map: ScalarResultMap,
        nodeName: String,
        calibration: PixelCalibration,
        in root: hid_t,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        try checkCancellation(cancellation)
        let group = try createGroup(nodeName, in: root, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "array", pythonClass: "RealSlice",
                                on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_kind", value: map.kind, on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_display_name", value: map.displayName,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_value_units", value: map.valueUnits,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_storage",
                                 value: SessionResultStorage.scalarFloat32.rawValue,
                                 on: group, hdf5: h5)

        let dimensions = [hsize_t(map.height), hsize_t(map.width)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(2, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating the scalar result dataspace") }
        defer { _ = h5.h5sclose(space) }
        let dataset = "data".withCString {
            h5.h5dcreate2(group, $0, h5.nativeFloat, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the scalar result data") }
        defer { _ = h5.h5dclose(dataset) }
        guard map.pixels.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeFloat, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing the scalar result pixels") }
        // RealSlice 0.14 currently hard-codes its data units to intensity. The
        // actual display/physical units remain in the mac4DSTEM metadata.
        try writeStringAttribute("units", value: "intensity", on: dataset, hdf5: h5)

        let step = calibration.rSize ?? 1
        let dimUnits = calibration.rUnits ?? "pixels"
        try writeDoubleVectorDataset("dim0", values: [0, step], name: "Rx",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: [0, step], name: "Ry",
                                     units: dimUnits, in: group, hdf5: h5)

        let bundle = try createGroup("metadatabundle", in: group, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle",
                                 on: bundle, hdf5: h5)
        let metadata = try createGroup("mac4dstem", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(metadata) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Metadata",
                                on: metadata, hdf5: h5)
        try writeStringDataset("kind", value: map.kind, metadataType: "string",
                               in: metadata, hdf5: h5)
        try writeStringDataset("display_name", value: map.displayName, metadataType: "string",
                               in: metadata, hdf5: h5)
        try writeStringDataset("value_units", value: map.valueUnits, metadataType: "string",
                               in: metadata, hdf5: h5)
        progress?(1)
    }

    private static func writeRGBAResultMap(
        _ map: RGBAResultMap,
        nodeName: String,
        calibration: PixelCalibration,
        in root: hid_t,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        try checkCancellation(cancellation)
        let group = try createGroup(nodeName, in: root, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "array", pythonClass: "Array",
                                on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_kind", value: map.kind, on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_display_name", value: map.displayName,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_value_units", value: map.valueUnits,
                                 on: group, hdf5: h5)
        try writeStringAttribute("mac4dstem_storage",
                                 value: SessionResultStorage.rgba8.rawValue,
                                 on: group, hdf5: h5)

        let dimensions = [hsize_t(map.height), hsize_t(map.width), 4]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(3, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating the RGBA result dataspace") }
        defer { _ = h5.h5sclose(space) }
        let dataset = "data".withCString {
            h5.h5dcreate2(group, $0, h5.nativeUChar, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the RGBA result data") }
        defer { _ = h5.h5dclose(dataset) }
        guard map.rgba.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeUChar, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing the RGBA result pixels") }
        try writeStringAttribute("units", value: "rgba8", on: dataset, hdf5: h5)

        let step = calibration.rSize ?? 1
        let dimUnits = calibration.rUnits ?? "pixels"
        try writeDoubleVectorDataset("dim0", values: [0, step], name: "Rx",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: [0, step], name: "Ry",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim2", values: [0, 1], name: "RGBA",
                                     units: "channel", in: group, hdf5: h5)

        let bundle = try createGroup("metadatabundle", in: group, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle",
                                 on: bundle, hdf5: h5)
        let metadata = try createGroup("mac4dstem", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(metadata) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Metadata",
                                on: metadata, hdf5: h5)
        try writeStringDataset("kind", value: map.kind, metadataType: "string",
                               in: metadata, hdf5: h5)
        try writeStringDataset("display_name", value: map.displayName,
                               metadataType: "string", in: metadata, hdf5: h5)
        try writeStringDataset("value_units", value: map.valueUnits,
                               metadataType: "string", in: metadata, hdf5: h5)
        try writeStringDataset("storage", value: SessionResultStorage.rgba8.rawValue,
                               metadataType: "string", in: metadata, hdf5: h5)
        progress?(1)
    }

    private static func writeShapeMetadata(
        scanHeight: Int, scanWidth: Int, qHeight: Int, qWidth: Int,
        in bragg: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let bundle = try createGroup("metadatabundle", in: bragg, hdf5: h5)
        defer { _ = h5.h5gclose(bundle) }
        try writeStringAttribute("emd_group_type", value: "metadatabundle", on: bundle, hdf5: h5)

        let shape = try createGroup("_braggvectors_shape", in: bundle, hdf5: h5)
        defer { _ = h5.h5gclose(shape) }
        try writeNodeAttributes(groupType: "metadata", pythonClass: "Metadata",
                                on: shape, hdf5: h5)
        try writeInt64VectorDataset("Rshape", values: [Int64(scanHeight), Int64(scanWidth)],
                                    metadataType: "tuple", in: shape, hdf5: h5)
        try writeInt64VectorDataset("Qshape", values: [Int64(qHeight), Int64(qWidth)],
                                    metadataType: "tuple", in: shape, hdf5: h5)
    }

    private static func writePeakGrid(
        _ vectors: BraggVectors,
        in bragg: hid_t,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) throws {
        let group = try createGroup("_v_uncal", in: bragg, hdf5: h5)
        defer { _ = h5.h5gclose(group) }
        try writeNodeAttributes(groupType: "custom_pointlistarray", pythonClass: "PointListArray",
                                on: group, hdf5: h5)

        let compound = h5.h5tcreate(h5CompoundClass, MemoryLayout<EMDPeakRecord>.stride)
        guard compound >= 0 else { throw WriterError.hdf5("creating the peak compound type") }
        defer { _ = h5.h5tclose(compound) }
        guard "qx".withCString({ h5.h5tinsert(compound, $0, 0, h5.nativeDouble) }) >= 0,
              "qy".withCString({ h5.h5tinsert(compound, $0, 8, h5.nativeDouble) }) >= 0,
              "intensity".withCString({ h5.h5tinsert(compound, $0, 16, h5.nativeDouble) }) >= 0 else {
            throw WriterError.hdf5("defining the peak compound fields")
        }
        let variable = h5.h5tvlenCreate(compound)
        guard variable >= 0 else { throw WriterError.hdf5("creating the variable-length peak type") }
        defer { _ = h5.h5tclose(variable) }

        let dimensions = [hsize_t(vectors.scanHeight), hsize_t(vectors.scanWidth)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(2, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating the peak-grid dataspace") }
        defer { _ = h5.h5sclose(space) }
        let dataset = "data".withCString {
            h5.h5dcreate2(group, $0, variable, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating the peak-grid dataset") }
        defer { _ = h5.h5dclose(dataset) }

        var cells = [H5VariableLength]()
        cells.reserveCapacity(vectors.peaks.count)
        var allocations = [UnsafeMutablePointer<EMDPeakRecord>]()
        allocations.reserveCapacity(vectors.peaks.count)
        defer {
            for pointer in allocations { pointer.deallocate() }
        }

        for scanY in 0..<vectors.scanHeight {
            try checkCancellation(cancellation)
            for scanX in 0..<vectors.scanWidth {
                try checkCancellation(cancellation)
                let peaks = vectors.peaks[scanY * vectors.scanWidth + scanX]
                guard !peaks.isEmpty else {
                    cells.append(H5VariableLength(length: 0, pointer: nil))
                    continue
                }
                let pointer = UnsafeMutablePointer<EMDPeakRecord>.allocate(capacity: peaks.count)
                allocations.append(pointer)
                for (index, peak) in peaks.enumerated() {
                    // AXIS CONVERSION: py4DSTEM qx is detector row; qy is column.
                    pointer[index] = EMDPeakRecord(
                        qx: Double(peak.y), qy: Double(peak.x),
                        intensity: Double(peak.intensity)
                    )
                }
                cells.append(H5VariableLength(
                    length: peaks.count, pointer: UnsafeMutableRawPointer(pointer)
                ))
            }
            progress?(Double(scanY + 1) / Double(vectors.scanHeight))
        }
        try checkCancellation(cancellation)
        let status = cells.withUnsafeMutableBytes {
            h5.h5dwrite(dataset, variable, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }
        guard status >= 0 else { throw WriterError.hdf5("writing the peak grid") }
    }

    private static func createGroup(
        _ name: String, in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> hid_t {
        let id = name.withCString {
            h5.h5gcreate2(parent, $0, h5DefaultProperty, h5DefaultProperty, h5DefaultProperty)
        }
        guard id >= 0 else { throw WriterError.hdf5("creating group \(name)") }
        return id
    }

    private static func writeNodeAttributes(
        groupType: String, pythonClass: String, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        try writeStringAttribute("emd_group_type", value: groupType, on: object, hdf5: h5)
        try writeStringAttribute("python_class", value: pythonClass, on: object, hdf5: h5)
    }

    private static func makeVariableStringType(_ h5: HDF5WriteLibrary) throws -> hid_t {
        let type = h5.h5tcopy(h5.stringC1)
        guard type >= 0,
              h5.h5tsetSize(type, UInt.max) >= 0,
              h5.h5tsetCset(type, h5UTF8CharacterSet) >= 0 else {
            if type >= 0 { _ = h5.h5tclose(type) }
            throw WriterError.hdf5("creating a UTF-8 string type")
        }
        return type
    }

    private static func writeStringAttribute(
        _ name: String, value: String, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let type = try makeVariableStringType(h5)
        defer { _ = h5.h5tclose(type) }
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5sclose(space) }
        let attribute = name.withCString {
            h5.h5acreate2(object, $0, type, space, h5DefaultProperty, h5DefaultProperty)
        }
        guard attribute >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5aclose(attribute) }
        let status = value.withCString { characters in
            var pointer: UnsafePointer<CChar>? = characters
            return withUnsafePointer(to: &pointer) { h5.h5awrite(attribute, type, $0) }
        }
        guard status >= 0 else { throw WriterError.hdf5("writing attribute \(name)") }
    }

    private static func writeScalarAttribute<T>(
        _ name: String, value: T, type: hid_t, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5sclose(space) }
        let attribute = name.withCString {
            h5.h5acreate2(object, $0, type, space, h5DefaultProperty, h5DefaultProperty)
        }
        guard attribute >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5aclose(attribute) }
        var mutableValue = value
        guard withUnsafePointer(to: &mutableValue, {
            h5.h5awrite(attribute, type, UnsafeRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("writing attribute \(name)") }
    }

    private static func writeScalarDataset<T>(
        _ name: String, value: inout T, type: hid_t, metadataType: String?,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, type, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard withUnsafePointer(to: &value, {
            h5.h5dwrite(dataset, type, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, UnsafeRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        if let metadataType {
            try writeStringAttribute("type", value: metadataType, on: dataset, hdf5: h5)
        }
    }

    private static func writeStringDataset(
        _ name: String, value: String, metadataType: String?,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let type = try makeVariableStringType(h5)
        defer { _ = h5.h5tclose(type) }
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, type, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        let status = value.withCString { characters in
            var pointer: UnsafePointer<CChar>? = characters
            return withUnsafePointer(to: &pointer) {
                h5.h5dwrite(dataset, type, h5EntireDataspace, h5EntireDataspace,
                            h5DefaultProperty, $0)
            }
        }
        guard status >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        if let metadataType {
            try writeStringAttribute("type", value: metadataType, on: dataset, hdf5: h5)
        }
    }

    private static func writeInt64VectorDataset(
        _ name: String, values: [Int64], metadataType: String,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let dimensions = [hsize_t(values.count)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(1, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, h5.nativeLongLong, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard values.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeLongLong, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        try writeStringAttribute("type", value: metadataType, on: dataset, hdf5: h5)
    }

    private static func writeDoubleVectorDataset(
        _ name: String, values: [Double], name dimName: String, units: String,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let dimensions = [hsize_t(values.count)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(1, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, h5.nativeDouble, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard values.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        try writeStringAttribute("name", value: dimName, on: dataset, hdf5: h5)
        try writeStringAttribute("units", value: units, on: dataset, hdf5: h5)
    }

    private static func writeDoubleMatrixDataset(
        _ name: String, values: [Double], shape: [Int],
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        guard shape.count == 2, shape.allSatisfy({ $0 > 0 }),
              values.count == shape[0] * shape[1] else {
            throw WriterError.invalidDimensions("calibration matrix \(name) is inconsistent")
        }
        let dimensions = shape.map(hsize_t.init)
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(2, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, h5.nativeDouble, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard values.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        try writeStringAttribute("type", value: "array", on: dataset, hdf5: h5)
    }

    private static func linkExists(
        _ path: String, in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) -> Bool {
        path.withCString { h5.h5lexists(parent, $0, h5DefaultProperty) > 0 }
    }

    private static func childLinkNames(
        in group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) -> [String] {
        var childCount: hsize_t = 0
        guard h5.h5ggetNumObjects(group, &childCount) >= 0 else { return [] }
        var names = [String]()
        names.reserveCapacity(Int(childCount))
        for index in 0..<childCount {
            let length = ".".withCString { groupName in
                h5.h5lgetNameByIndex(
                    group, groupName, h5IndexByName, h5IterationIncreasing,
                    index, nil, 0, h5DefaultProperty
                )
            }
            guard length >= 0 else { continue }
            var bytes = [CChar](repeating: 0, count: length + 1)
            let read = ".".withCString { groupName in
                bytes.withUnsafeMutableBufferPointer { buffer in
                    h5.h5lgetNameByIndex(
                        group, groupName, h5IndexByName, h5IterationIncreasing,
                        index, buffer.baseAddress, buffer.count, h5DefaultProperty
                    )
                }
            }
            guard read >= 0 else { continue }
            names.append(String(cString: bytes))
        }
        return names
    }

    private static func readStringAttribute(
        _ name: String, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> String? {
        guard name.withCString({ h5.h5aexists(object, $0) }) > 0 else { return nil }
        let attribute = name.withCString { h5.h5aopen(object, $0, h5DefaultProperty) }
        guard attribute >= 0 else { throw WriterError.hdf5("opening attribute \(name)") }
        defer { _ = h5.h5aclose(attribute) }
        let type = h5.h5agetType(attribute)
        guard type >= 0 else { throw WriterError.hdf5("opening attribute type \(name)") }
        defer { _ = h5.h5tclose(type) }
        var pointer: UnsafeMutablePointer<CChar>?
        guard withUnsafeMutablePointer(to: &pointer, {
            h5.h5aread(attribute, type, UnsafeMutableRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("reading attribute \(name)") }
        guard let pointer else { return "" }
        defer { _ = h5.h5freeMemory(pointer) }
        return String(cString: pointer)
    }
}

// MARK: - HDF5 dynamic binding

nonisolated private let h5DefaultProperty: hid_t = 0
nonisolated private let h5EntireDataspace: hid_t = 0
nonisolated private let h5FileTruncate: UInt32 = 0x0002
nonisolated private let h5FileReadOnly: UInt32 = 0x0000
nonisolated private let h5ScalarDataspace: Int32 = 0
nonisolated private let h5CompoundClass: Int32 = 6
nonisolated private let h5UTF8CharacterSet: Int32 = 1
nonisolated private let h5SelectSet: Int32 = 0
nonisolated private let h5IndexByName: Int32 = 0
nonisolated private let h5IterationIncreasing: Int32 = 0

nonisolated private struct EMDPeakRecord {
    var qx: Double
    var qy: Double
    var intensity: Double
}

nonisolated private struct H5VariableLength {
    var length: Int
    var pointer: UnsafeMutableRawPointer?
}

nonisolated private struct HDF5WriteLibrary: @unchecked Sendable {
    typealias H5open = @convention(c) () -> herr_t
    typealias H5Fcreate = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t, hid_t) -> hid_t
    typealias H5Fopen = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t) -> hid_t
    typealias H5Fclose = @convention(c) (hid_t) -> herr_t
    typealias H5Gcreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t) -> hid_t
    typealias H5Gopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Gclose = @convention(c) (hid_t) -> herr_t
    typealias H5GgetNumObjects = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?) -> herr_t
    typealias H5Screate = @convention(c) (Int32) -> hid_t
    typealias H5ScreateSimple = @convention(c) (Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> hid_t
    typealias H5SselectHyperslab = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> herr_t
    typealias H5Sclose = @convention(c) (hid_t) -> herr_t
    typealias H5Dcreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t, hid_t, hid_t) -> hid_t
    typealias H5Dopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5DgetSpace = @convention(c) (hid_t) -> hid_t
    typealias H5DgetType = @convention(c) (hid_t) -> hid_t
    typealias H5Dwrite = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeRawPointer?) -> herr_t
    typealias H5Dread = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Dclose = @convention(c) (hid_t) -> herr_t
    typealias H5SgetSimpleExtentNdims = @convention(c) (hid_t) -> Int32
    typealias H5SgetSimpleExtentDims = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?, UnsafeMutablePointer<hsize_t>?) -> Int32
    typealias H5Tcreate = @convention(c) (Int32, Int) -> hid_t
    typealias H5Tinsert = @convention(c) (hid_t, UnsafePointer<CChar>?, Int, hid_t) -> herr_t
    typealias H5TvlenCreate = @convention(c) (hid_t) -> hid_t
    typealias H5Tcopy = @convention(c) (hid_t) -> hid_t
    typealias H5TsetSize = @convention(c) (hid_t, UInt) -> herr_t
    typealias H5TsetCset = @convention(c) (hid_t, Int32) -> herr_t
    typealias H5Tclose = @convention(c) (hid_t) -> herr_t
    typealias H5Acreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t, hid_t) -> hid_t
    typealias H5Aexists = @convention(c) (hid_t, UnsafePointer<CChar>?) -> Int32
    typealias H5Aopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5AgetType = @convention(c) (hid_t) -> hid_t
    typealias H5Awrite = @convention(c) (hid_t, hid_t, UnsafeRawPointer?) -> herr_t
    typealias H5Aread = @convention(c) (hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Aclose = @convention(c) (hid_t) -> herr_t
    typealias H5Lexists = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> Int32
    typealias H5Ocopy = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, UnsafePointer<CChar>?, hid_t, hid_t) -> herr_t
    typealias H5freeMemory = @convention(c) (UnsafeMutableRawPointer?) -> herr_t
    typealias H5LgetNameByIndex = @convention(c) (hid_t, UnsafePointer<CChar>?, Int32, Int32, hsize_t, UnsafeMutablePointer<CChar>?, Int, hid_t) -> Int
    typealias H5Pcreate = @convention(c) (hid_t) -> hid_t
    typealias H5PsetChunk = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?) -> herr_t
    typealias H5Pclose = @convention(c) (hid_t) -> herr_t

    let handle: UnsafeMutableRawPointer
    let h5open: H5open
    let h5fcreate: H5Fcreate
    let h5fopen: H5Fopen
    let h5fclose: H5Fclose
    let h5gcreate2: H5Gcreate2
    let h5gopen2: H5Gopen2
    let h5gclose: H5Gclose
    let h5ggetNumObjects: H5GgetNumObjects
    let h5screate: H5Screate
    let h5screateSimple: H5ScreateSimple
    let h5sselectHyperslab: H5SselectHyperslab
    let h5sclose: H5Sclose
    let h5dcreate2: H5Dcreate2
    let h5dopen2: H5Dopen2
    let h5dgetSpace: H5DgetSpace
    let h5dgetType: H5DgetType
    let h5dwrite: H5Dwrite
    let h5dread: H5Dread
    let h5dclose: H5Dclose
    let h5sgetSimpleExtentNdims: H5SgetSimpleExtentNdims
    let h5sgetSimpleExtentDims: H5SgetSimpleExtentDims
    let h5tcreate: H5Tcreate
    let h5tinsert: H5Tinsert
    let h5tvlenCreate: H5TvlenCreate
    let h5tcopy: H5Tcopy
    let h5tsetSize: H5TsetSize
    let h5tsetCset: H5TsetCset
    let h5tclose: H5Tclose
    let h5acreate2: H5Acreate2
    let h5aexists: H5Aexists
    let h5aopen: H5Aopen
    let h5agetType: H5AgetType
    let h5awrite: H5Awrite
    let h5aread: H5Aread
    let h5aclose: H5Aclose
    let h5lexists: H5Lexists
    let h5ocopy: H5Ocopy
    let h5freeMemory: H5freeMemory
    let h5lgetNameByIndex: H5LgetNameByIndex
    let h5pcreate: H5Pcreate
    let h5psetChunk: H5PsetChunk
    let h5pclose: H5Pclose
    let nativeFloat: hid_t
    let nativeDouble: hid_t
    let nativeInt: hid_t
    let nativeLongLong: hid_t
    let nativeHBool: hid_t
    let nativeUChar: hid_t
    let stringC1: hid_t
    let datasetCreatePropertyClass: hid_t

    static func load() throws -> HDF5WriteLibrary {
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
        _ = h5open()
        return HDF5WriteLibrary(
            handle: handle,
            h5open: h5open,
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

    private static func candidateLibraryPaths() -> [String] {
        [
            ProcessInfo.processInfo.environment["MAC4DSTEM_HDF5_PATH"],
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libhdf5.dylib").path,
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("../Frameworks/libhdf5.dylib").standardized.path,
            "libhdf5.dylib"
        ].compactMap { $0 }
    }
}
