import Darwin
import Foundation

/// One scalar real-space result persisted as a py4DSTEM `RealSlice`.
/// Pixels use app row-major `[y][x]`, which is the same memory order as
/// py4DSTEM's real-space `[R_Nx,R_Ny]` convention established by H5Reader.
package nonisolated struct ScalarResultMap: Sendable {
    package static let legacyEMDName = "result_map"
    /// v2 DPC-angle unit repair: old sidecars stored normalized turns while
    /// claiming `rad`. New maps name their encoding so the reader can migrate
    /// only the legacy absence, without guessing about future representations.
    package static let dpcAngleEncodingKey = "dpc_angle_encoding"
    package static let dpcAngleRadiansEncoding = "radians"
    package static let dpcAngleTurnsEncoding = "normalized_turns"

    package let width: Int
    package let height: Int
    package let pixels: [Float]
    package let kind: String
    package let displayName: String
    package let valueUnits: String
    package let pixelSizeRow: Double?
    package let pixelSizeColumn: Double?
    package let pixelUnits: String?
    package let provenance: [String: String]

    package init(width: Int, height: Int, pixels: [Float], kind: String,
         displayName: String, valueUnits: String,
         pixelSizeRow: Double? = nil, pixelSizeColumn: Double? = nil,
         pixelUnits: String? = nil, provenance: [String: String] = [:]) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.kind = kind
        self.displayName = displayName
        self.valueUnits = valueUnits
        self.pixelSizeRow = pixelSizeRow
        self.pixelSizeColumn = pixelSizeColumn
        self.pixelUnits = pixelUnits
        self.provenance = provenance
    }
}

/// One pre-colored scan-shaped scientific result (for example DPC direction
/// or cubic IPF-Z), persisted losslessly as uint8 `[height,width,RGBA]`.
package nonisolated struct RGBAResultMap: Sendable {
    package let width: Int
    package let height: Int
    package let rgba: [UInt8]
    package let kind: String
    package let displayName: String
    package let valueUnits: String
    package let pixelSizeRow: Double?
    package let pixelSizeColumn: Double?
    package let pixelUnits: String?
    package let provenance: [String: String]

    package init(
        width: Int, height: Int, rgba: [UInt8], kind: String,
        displayName: String, valueUnits: String,
        pixelSizeRow: Double? = nil, pixelSizeColumn: Double? = nil,
        pixelUnits: String? = nil, provenance: [String: String] = [:]
    ) {
        self.width = width
        self.height = height
        self.rgba = rgba
        self.kind = kind
        self.displayName = displayName
        self.valueUnits = valueUnits
        self.pixelSizeRow = pixelSizeRow
        self.pixelSizeColumn = pixelSizeColumn
        self.pixelUnits = pixelUnits
        self.provenance = provenance
    }
}

package nonisolated enum SessionResultStorage: String, Sendable {
    case scalarFloat32 = "scalar_f32"
    case rgba8 = "rgba8"
}

/// Lightweight on-disk map metadata used by the session inventory. The `id`
/// is the stable HDF5 node name, not a user-visible label.
package nonisolated struct SessionResultDescriptor: Identifiable, Sendable, Equatable {
    package let id: String
    package let kind: String
    package let displayName: String
    package let valueUnits: String
    package let width: Int
    package let height: Int
    package let storage: SessionResultStorage
    package let pixelSizeRow: Double?
    package let pixelSizeColumn: Double?
    package let pixelUnits: String?
    package let provenance: [String: String]

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(id: String, kind: String, displayName: String, valueUnits: String, width: Int, height: Int, storage: SessionResultStorage, pixelSizeRow: Double?, pixelSizeColumn: Double?, pixelUnits: String?, provenance: [String: String]) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.valueUnits = valueUnits
        self.width = width
        self.height = height
        self.storage = storage
        self.pixelSizeRow = pixelSizeRow
        self.pixelSizeColumn = pixelSizeColumn
        self.pixelUnits = pixelUnits
        self.provenance = provenance
    }
}

package nonisolated struct SessionSidecarInventory: Sendable, Equatable {
    package static let empty = SessionSidecarInventory(
        hasSidecar: false, hasBraggVectors: false, hasCalibration: false,
        results: [], currentResultID: nil
    )

    package let hasSidecar: Bool
    package let hasBraggVectors: Bool
    package let hasCalibration: Bool
    package let results: [SessionResultDescriptor]
    package let currentResultID: String?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(hasSidecar: Bool, hasBraggVectors: Bool, hasCalibration: Bool, results: [SessionResultDescriptor], currentResultID: String?) {
        self.hasSidecar = hasSidecar
        self.hasBraggVectors = hasBraggVectors
        self.hasCalibration = hasCalibration
        self.results = results
        self.currentResultID = currentResultID
    }
}

package nonisolated struct SessionSidecarSnapshot: Sendable {
    package let inventory: SessionSidecarInventory
    package let calibration: PixelCalibration?
    package let currentResult: ScalarResultMap?
    package let currentRGBAResult: RGBAResultMap?
    /// The view these products were computed under. **Nil means full extent**,
    /// not "unknown": a sidecar written before L6 recorded no specification
    /// because there was none to record.
    ///
    /// Reopening re-applies this to the SOURCE file. It is never used to
    /// re-derive from reduced data — the source is what is reopened, and the
    /// specification is applied to it again, which is the whole reason a crop is
    /// a view rather than a new dataset (docs/v2-scope.md §6.1).
    package var loadSpecification: LoadSpecification? = nil
    /// The recorded analysis pipeline, when the sidecar carries one.
    /// **Nil means "no recipe was recorded"** — absence is absence, never an
    /// empty-but-asserted record (the `?? .fullExtent` lesson). // v2 S5
    package var replayRecord: SessionReplayRecord? = nil

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(inventory: SessionSidecarInventory, calibration: PixelCalibration?, currentResult: ScalarResultMap?, currentRGBAResult: RGBAResultMap?, loadSpecification: LoadSpecification? = nil, replayRecord: SessionReplayRecord? = nil) {
        self.inventory = inventory
        self.calibration = calibration
        self.currentResult = currentResult
        self.currentRGBAResult = currentRGBAResult
        self.loadSpecification = loadSpecification
        self.replayRecord = replayRecord
    }
}

/// Bounded preprocessing applied while streaming a source datacube into a
/// canonical py4DSTEM EMD file. Ranges use app/HDF5 order `[Ry,Rx]` and Q
/// binning sums non-overlapping detector blocks, matching py4DSTEM's count-
/// preserving diffraction binning semantics.
package nonisolated struct CalibratedDataCubeExportOptions: Sendable, Equatable {
    package let scanY: Range<Int>
    package let scanX: Range<Int>
    package let qBin: Int
    package let tileRows: Int

    package init(scanY: Range<Int>, scanX: Range<Int>, qBin: Int = 1, tileRows: Int = 1) {
        self.scanY = scanY
        self.scanX = scanX
        self.qBin = qBin
        self.tileRows = tileRows
    }
}

package nonisolated struct CalibratedDataCubeExportSummary: Sendable, Equatable {
    package let shape: [Int]
    package let discardedQRows: Int
    package let discardedQColumns: Int

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(shape: [Int], discardedQRows: Int, discardedQColumns: Int) {
        self.shape = shape
        self.discardedQRows = discardedQRows
        self.discardedQColumns = discardedQColumns
    }
}

/// How an exported reduced DataCube was derived from its source — the
/// "traceable to file + specification" half of the release claim, stamped as
/// a JSON attribute on the exported file (v2 S10). Deliberately NOT a
/// `LoadSpecification`: that type means "reopen the source this way" and is
/// bounded by the app's bin vocabulary (2/4/8), while a derivation composes
/// the view's bin with the export's (their product can be 16+) and means
/// only "this is where these pixels came from". Offsets are in SOURCE
/// pixels; extents are the exported file's own shape; `detectorBin` is the
/// TOTAL source→file factor. The file NAME travels, never the path — a
/// screenshot-able attribute must not leak the filesystem (the status-line
/// lesson, docs/open-items.md).
package nonisolated struct DataCubeDerivation: Codable, Sendable, Equatable {
    package var schema: Int = 1
    package var sourceFile: String?
    package var scanOffsetY: Int
    package var scanOffsetX: Int
    package var scanHeight: Int
    package var scanWidth: Int
    package var detectorOffsetY: Int
    package var detectorOffsetX: Int
    package var detectorBin: Int
    package var detectorHeight: Int
    package var detectorWidth: Int

    package enum CodingKeys: String, CodingKey {
        case schema
        case sourceFile = "source_file"
        case scanOffsetY = "scan_offset_y"
        case scanOffsetX = "scan_offset_x"
        case scanHeight = "scan_height"
        case scanWidth = "scan_width"
        case detectorOffsetY = "detector_offset_y"
        case detectorOffsetX = "detector_offset_x"
        case detectorBin = "detector_bin"
        case detectorHeight = "detector_height"
        case detectorWidth = "detector_width"
    }

    /// Compose the view's reduction with the export's. Exact by the floor
    /// identity `floor(floor(n/a)/b) == floor(n/(a·b))`: the view trims its
    /// detector to a multiple of its bin off the END of each axis, the export
    /// trims the view the same way, so the composition is one crop at the
    /// view's offsets with the total bin — no intermediate state survives.
    /// Scan composition is pure selection: offsets add.
    package static func compose(view: LoadView,
                        options: CalibratedDataCubeExportOptions,
                        outputShape: [Int],
                        sourceFileName: String?) -> DataCubeDerivation {
        let specification = view.specification
        let scanCrop = specification.scanCrop
        let detectorCrop = view.readDetectorCrop
        return DataCubeDerivation(
            sourceFile: sourceFileName,
            scanOffsetY: (scanCrop?.yOffset ?? 0) + options.scanY.lowerBound,
            scanOffsetX: (scanCrop?.xOffset ?? 0) + options.scanX.lowerBound,
            scanHeight: outputShape[0],
            scanWidth: outputShape[1],
            detectorOffsetY: detectorCrop?.yOffset ?? 0,
            detectorOffsetX: detectorCrop?.xOffset ?? 0,
            detectorBin: specification.detectorBin * options.qBin,
            detectorHeight: outputShape[2],
            detectorWidth: outputShape[3]
        )
    }

    /// Deterministic JSON, same conventions as the other stamped records.
    package var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // try? OK (v2 S7 audit): all stored properties are Ints and an
        // optional String — nothing here can fail to encode, and nil falls
        // through to "write no attribute".
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(schema: Int = 1, sourceFile: String? = nil, scanOffsetY: Int, scanOffsetX: Int, scanHeight: Int, scanWidth: Int, detectorOffsetY: Int, detectorOffsetX: Int, detectorBin: Int, detectorHeight: Int, detectorWidth: Int) {
        self.schema = schema
        self.sourceFile = sourceFile
        self.scanOffsetY = scanOffsetY
        self.scanOffsetX = scanOffsetX
        self.scanHeight = scanHeight
        self.scanWidth = scanWidth
        self.detectorOffsetY = detectorOffsetY
        self.detectorOffsetX = detectorOffsetX
        self.detectorBin = detectorBin
        self.detectorHeight = detectorHeight
        self.detectorWidth = detectorWidth
    }
}

/// Writes the detected peak grid as a py4DSTEM 0.14 / EMD 1.0 BraggVectors
/// sidecar. The source dataset is never opened for writing. Publication is an
/// atomic rename of a completed sibling temporary file, so cancellation or an
/// HDF5 failure cannot leave a partial result at the requested destination.
package nonisolated enum BraggVectorEMDWriter {
    private static let rootPath = "/" + SessionSidecarFormat.rootGroupName
    // Shared with H5Reader's sidecar recognition via SessionSidecarFormat
    // (Core/Data/HDF5Types.swift) — one constant, both sides. // v2 S4
    private static let schemaAttribute = SessionSidecarFormat.schemaAttribute
    private static let resultNodesAttribute = "mac4dstem_result_nodes"
    private static let currentResultAttribute = "mac4dstem_current_result"
    /// The `LoadSpecification` a session's products were computed under, as
    /// JSON. Absent on a full-extent session — the identity, so a sidecar
    /// written before L6 reads as "the whole file", which is what it was.
    private static let loadSpecificationAttribute = "mac4dstem_load_specification"
    /// How an exported reduced DataCube was derived from its source
    /// (`DataCubeDerivation`, v2 S10). On the exported file's `datacube_root`
    /// — deliberately NOT `loadSpecificationAttribute`, whose meaning is
    /// "reopen the SOURCE this way" on a sidecar; this one means "this file's
    /// pixels came from there" and instructs nothing.
    private static let derivationAttribute = "mac4dstem_derivation"
    private static let minimumReaderAttribute = SessionSidecarFormat.minimumReaderAttribute
    private static let replayRecordAttribute = SessionSidecarFormat.replayRecordAttribute
    /// Derived, never a literal: "5" famously stayed put across a format
    /// addition (2026-08-18), which is what made the stamp meaningless.
    /// `SessionSidecarFormat.currentSchema` is the one place the number
    /// moves. // v2 S5
    private static let sessionSchemaVersion = String(SessionSidecarFormat.currentSchema)

    /// The OLDEST schema a reader may implement and still interpret a file
    /// with this specification without misreading it. Additive content (the
    /// replay record) does not raise it; a reduced specification does —
    /// ignoring one restores scan-indexed results at wrong positions (the
    /// docs/v2-release.md §5 evidence for the marker). // v2 S5
    package static func minimumReaderSchema(for specification: LoadSpecification?) -> Int {
        (specification == nil || specification?.isFullExtent == true) ? 5 : 6
    }

    package enum WriterError: LocalizedError {
        case cancelled
        case invalidDimensions(String)
        case libraryUnavailable(String)
        case symbolMissing(String)
        case hdf5(String)
        case publishFailed(String)
        /// The file's minimum-reader marker demands a schema newer than this
        /// build understands. A REFUSAL, never a partial restore: the marker
        /// exists because a v1.0.0 build silently ignored the specification
        /// attribute and restored results at wrong positions — worse than
        /// "cannot read" (docs/v2-release.md §5). // v2 S5
        case sidecarRequiresNewerReader(minimum: Int, supported: Int)
        /// An attribute EXISTS on the sidecar and cannot be decoded. A
        /// refusal, never a silent nil: a mangled specification attribute
        /// that reads as "no crop recorded" reopens a cropped session at
        /// full extent without a word — the exact misread the attribute
        /// exists to prevent — and a mangled recipe reads as "no recipe".
        /// // v2 S7
        case malformedAttribute(name: String)

        package var errorDescription: String? {
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
                // Not "export failed": the same case is raised on the sidecar
                // *read* path, where the 2026-08-18 restore failure reported an
                // export that was never attempted (S1).
                return "HDF5 failed while \(operation)."
            case .publishFailed(let detail):
                return "Could not publish the completed sidecar: \(detail)"
            case .sidecarRequiresNewerReader(let minimum, let supported):
                return "This session sidecar requires mac4DSTEM session schema "
                    + "\(minimum) or newer to read safely; this build supports "
                    + "\(supported). It was probably written by a newer mac4DSTEM — "
                    + "nothing was restored, so nothing can be misread."
            case .malformedAttribute(let name):
                return "The session sidecar's \(name) attribute exists but "
                    + "could not be decoded — the file may be damaged. "
                    + "Nothing was restored, so nothing can be misread."
            }
        }
    }

    /// An `.hdf5` error carrying the reason HDF5 recorded, not only the
    /// operation that failed. Used on the sidecar **read** path, where a bare
    /// "HDF5 export failed while opening the session sidecar" was the whole
    /// evidence available for the 2026-08-18 restore failure (S1) — it could
    /// not distinguish a sandbox denial from a lock, a truncated file or a
    /// wrong path. Call only immediately after the failing HDF5 call.
    fileprivate static func hdf5Failure(
        _ operation: String, _ h5: HDF5WriteLibrary
    ) -> WriterError {
        guard let stack = h5.currentErrorStack() else { return .hdf5(operation) }
        return .hdf5("\(operation) — HDF5 reported: \(stack)")
    }

    /// Publish several related scalar fields as sibling EMD RealSlice nodes in
    /// one atomic file. This is used for scientifically coherent strain and
    /// orientation bundles; a cancelled or failed write never exposes a
    /// partial collection.
    package static func writeScientificBundle(
        maps: [ScalarResultMap], calibration: PixelCalibration, to destination: URL,
        cancellation: AnalysisCancellationToken? = nil
    ) throws {
        guard !maps.isEmpty else {
            throw WriterError.invalidDimensions("a scientific bundle needs at least one field")
        }
        let shape = (maps[0].width, maps[0].height)
        guard shape.0 > 0, shape.1 > 0,
              maps.allSatisfy({ $0.width == shape.0 && $0.height == shape.1
                  && $0.pixels.count == shape.0 * shape.1 }) else {
            throw WriterError.invalidDimensions("bundle fields must share one non-empty shape")
        }
        guard Set(maps.map(\.kind)).count == maps.count else {
            throw WriterError.invalidDimensions("bundle field kinds must be unique")
        }
        try checkCancellation(cancellation)
        let fm = FileManager.default
        let (temporary, scratchDirectory) = temporaryPublishURL(for: destination)
        var published = false
        defer {
            // try? OK (v2 S7 audit): best-effort scratch cleanup on the way
            // out — on the failure path the primary error is already
            // in flight, and a leftover .tmp in the system-provided scratch
            // directory harms nothing the error did not already report.
            if !published { try? fm.removeItem(at: temporary) }
            if let scratchDirectory { try? fm.removeItem(at: scratchDirectory) }
        }
        let h5 = try HDF5WriteLibrary.load()
        let file = temporary.path.withCString {
            h5.h5fcreate($0, h5FileTruncate, h5DefaultProperty, h5DefaultProperty)
        }
        guard file >= 0 else { throw WriterError.hdf5("creating the bundle file") }
        do {
            defer { _ = h5.h5fclose(file) }
            try writeStringAttribute("emd_group_type", value: "file", on: file, hdf5: h5)
            try writeScalarAttribute("version_major", value: Int32(1), type: h5.nativeInt,
                                     on: file, hdf5: h5)
            try writeScalarAttribute("version_minor", value: Int32(0), type: h5.nativeInt,
                                     on: file, hdf5: h5)
            try writeStringAttribute("authoring_program", value: "mac4DSTEM", on: file, hdf5: h5)
            let root = try createGroup("scientific_bundle_root", in: file, hdf5: h5)
            defer { _ = h5.h5gclose(root) }
            try writeNodeAttributes(groupType: "root", pythonClass: "Root", on: root, hdf5: h5)
            try writeStringAttribute("mac4dstem_bundle_schema", value: "1", on: root, hdf5: h5)
            try writeStringAttribute("mac4dstem_bundle_fields",
                                     value: maps.map(\.kind).joined(separator: "\n"),
                                     on: root, hdf5: h5)
            try writeCalibration(calibration, targetPath: nil, in: root, hdf5: h5)
            for map in maps {
                try checkCancellation(cancellation)
                try writeResultMap(
                    map, nodeName: resultNodeName(forKind: map.kind),
                    calibration: calibration, in: root,
                    cancellation: cancellation, progress: nil, hdf5: h5
                )
            }
        }
        try checkCancellation(cancellation)
        let status = temporary.path.withCString { source in
            destination.path.withCString { target in Darwin.rename(source, target) }
        }
        guard status == 0 else {
            throw WriterError.publishFailed(String(cString: strerror(errno)))
        }
        published = true
    }

    /// Stable discoverable companion path used for automatic reload.
    package static func sessionSidecarURL(forSourcePath path: String) -> URL {
        let source = URL(fileURLWithPath: path)
        let stem = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent()
            .appendingPathComponent(stem + SessionSidecarFormat.nameSuffix, isDirectory: false)
    }

    /// `qHeight` is the detector row count and becomes py4DSTEM Qshape[0];
    /// `qWidth` is the detector column count and becomes Qshape[1].
    package static func write(
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
    package static func writeCalibratedDataCube(
        source: any FourDDataSource,
        view: LoadView,
        calibration: PixelCalibration,
        options: CalibratedDataCubeExportOptions,
        to destination: URL,
        sourceFileName: String? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CalibratedDataCubeExportSummary {
        // The export crops what is *loaded*, so its bounds are the view's, not
        // the source file's.
        //
        // **A reduced view exports since v2 S10.** The blanket refusal that
        // stood here ("needs the calibration re-reference (L3)") guarded one
        // invariant: pixels and calibration must be in the SAME frame. That
        // invariant holds structurally now — every read goes through the view
        // (`readScanTile` returns view-frame patterns), and the session
        // calibration handed in is view-frame because L3's
        // `CalibrationReReference.apply` re-references it at load time — so
        // `transformedCalibration` only ever composes the EXPORT-time bin on
        // top, which is the same math for a reduced view as for a full one.
        // What replaced the refusal is the checks the invariant deserves:
        // `transformedCalibration` now REFUSES (never silently drops or
        // passes through) origin maps whose shape is not this view's, and
        // refuses an origin that lands outside the exported detector — the
        // frame-mismatch net for a caller that hands a source-frame
        // calibration with reduced pixels, the py4DSTEM `bin_data_diffraction`
        // defect this file's own DEVIATION note forbids.
        let descriptor = view.descriptor
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
        let (temporary, scratchDirectory) = temporaryPublishURL(for: destination)
        var published = false
        defer {
            // try? OK (v2 S7 audit): best-effort scratch cleanup on the way
            // out — on the failure path the primary error is already
            // in flight, and a leftover .tmp in the system-provided scratch
            // directory harms nothing the error did not already report.
            if !published { try? fm.removeItem(at: temporary) }
            if let scratchDirectory { try? fm.removeItem(at: scratchDirectory) }
        }
        let h5 = try HDF5WriteLibrary.load()
        try await writeCalibratedDataCubeFile(
            at: temporary, source: source, view: view,
            calibration: try transformedCalibration(calibration, descriptor: descriptor,
                                                    options: options),
            options: options, outputShape: summary.shape,
            derivation: DataCubeDerivation.compose(view: view, options: options,
                                                   outputShape: summary.shape,
                                                   sourceFileName: sourceFileName),
            replayRecord: replayRecord,
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
    package static func mergeResultMap(
        _ map: ScalarResultMap,
        vectors: BraggVectors?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard map.width > 0, map.height > 0,
              map.pixels.count == map.width * map.height,
              map.pixelSizeRow == nil
                || (map.pixelSizeRow!.isFinite && map.pixelSizeRow! > 0),
              map.pixelSizeColumn == nil
                || (map.pixelSizeColumn!.isFinite && map.pixelSizeColumn! > 0) else {
            throw WriterError.invalidDimensions("the scalar result map is inconsistent")
        }
        if let vectors { try validate(vectors: vectors, qWidth: qWidth, qHeight: qHeight) }
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        // The specification is threaded on EVERY session rewrite, not only the
        // calibration save: the writer rebuilds the whole file, so a result
        // save that omitted it silently ERASED the crop attribute — a reopen
        // then restored results against the full extent (found by S5). // v2 S5
        try publish(vectors: vectors, map: map, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    cancellation: cancellation, progress: progress)
    }

    package static func mergeRGBAResultMap(
        _ map: RGBAResultMap,
        vectors: BraggVectors?,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        to destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
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
        // Same rule as mergeResultMap: every rewrite restates the view. // v2 S5
        try publish(vectors: vectors, map: nil, rgbaMap: map,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    cancellation: cancellation, progress: progress)
    }

    /// Atomically replace the session calibration while preserving every
    /// supported result object already present in the companion file.
    package static func mergeCalibration(
        _ calibration: PixelCalibration,
        qWidth: Int,
        qHeight: Int,
        to destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        supportedSchema: Int = SessionSidecarFormat.currentSchema,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard qWidth > 0, qHeight > 0 else {
            throw WriterError.invalidDimensions("the diffraction shape must be positive")
        }
        let existing = FileManager.default.fileExists(atPath: destination.path)
            ? destination : nil
        // `supportedSchema` is the same documented test seam as on
        // `loadSession`: the write-side refusal is only exercisable against a
        // real file by lowering what the "build" supports. // v2 S5
        try publish(vectors: nil, map: nil, rgbaMap: nil,
                    qWidth: qWidth, qHeight: qHeight,
                    calibration: calibration, preserving: existing, to: destination,
                    loadSpecification: loadSpecification, replayRecord: replayRecord,
                    supportedSchema: supportedSchema,
                    cancellation: cancellation, progress: progress)
    }

    /// Atomically remove one named result while preserving calibration,
    /// BraggVectors, and every other supported scalar/RGBA result.
    package static func removeResult(
        kind: String,
        qWidth: Int,
        qHeight: Int,
        calibration: PixelCalibration,
        from destination: URL,
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        guard qWidth > 0, qHeight > 0,
              FileManager.default.fileExists(atPath: destination.path) else {
            throw WriterError.invalidDimensions("the session sidecar does not exist")
        }
        // Removal also rebuilds the file — it restates the view like every
        // other rewrite, or removing a result would erase the crop. // v2 S5
        try publish(
            vectors: nil, map: nil, rgbaMap: nil,
            qWidth: qWidth, qHeight: qHeight, calibration: calibration,
            preserving: destination, to: destination, removingKind: kind,
            loadSpecification: loadSpecification, replayRecord: replayRecord,
            cancellation: cancellation, progress: progress
        )
    }

    /// Load the complete supported session inventory and the map recorded as
    /// current. Legacy one-slot sidecars are treated as a one-map inventory.
    /// The one minimum-reader check, shared by EVERY reader that hands back
    /// session content — `loadSession` and the two direct result readers
    /// (`loadResultMap(id:)`, `loadRGBAResultMap(id:)`), which used to bypass
    /// it and restore pixel arrays from a file the gate had refused
    /// (Gate B-lite F5). Absent marker ⇒ the file predates it ⇒ readable by
    /// the rules that applied when it was written; an unparseable value is
    /// treated the same, because refusing on garbage would brick every
    /// sidecar a bit-flip touches while a newer-format file always writes a
    /// clean integer. // v2 S5
    private static func enforceMinimumReader(
        on root: hid_t, hdf5 h5: HDF5WriteLibrary, supportedSchema: Int
    ) throws {
        if let markerText = try readStringAttribute(minimumReaderAttribute, on: root, hdf5: h5),
           let minimum = Int(markerText),
           minimum > supportedSchema {
            throw WriterError.sidecarRequiresNewerReader(
                minimum: minimum, supported: supportedSchema
            )
        }
    }

    /// `supportedSchema` exists so the minimum-reader refusal is testable
    /// against a REAL file through the REAL gate: a test reads a genuinely
    /// cropped sidecar as a schema-5 reader and watches the refusal fire.
    /// Production callers never pass it — the default is the build's truth.
    package static func loadSession(
        from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> SessionSidecarSnapshot {
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
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }

        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }

        // THE MINIMUM-READER GATE (v2 S5), checked before anything is
        // restored. A file demanding a newer reader is refused whole, with
        // both numbers named — a partial restore is exactly the "right
        // numbers at wrong positions, no warning" failure the marker exists
        // to prevent.
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)

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
        // Absent attribute ⇒ nil — nothing was recorded. Present-but-
        // undecodable ⇒ REFUSE by name (v2 S7): `.flatMap(decoded)` used to
        // collapse the two, so a mangled specification attribute read as "no
        // crop recorded" and the cropped session reopened silently at full
        // extent — the misread the attribute exists to prevent.
        let specification: LoadSpecification?
        if let json = try readStringAttribute(loadSpecificationAttribute,
                                              on: root, hdf5: h5) {
            guard let decoded = LoadSpecification.decoded(from: json) else {
                throw WriterError.malformedAttribute(name: loadSpecificationAttribute)
            }
            specification = decoded
        } else {
            specification = nil
        }
        // Absent attribute ⇒ nil record — no recipe was recorded, and the
        // snapshot says so rather than asserting an empty one. // v2 S5
        // Present-but-undecodable refuses, as above. // v2 S7
        let replay: SessionReplayRecord?
        if let json = try readStringAttribute(replayRecordAttribute, on: root, hdf5: h5) {
            guard let parsed = SessionReplayRecord.parse(json) else {
                throw WriterError.malformedAttribute(name: replayRecordAttribute)
            }
            replay = parsed
        } else {
            replay = nil
        }
        let inventory = SessionSidecarInventory(
            hasSidecar: true,
            hasBraggVectors: linkExists("\(rootPath)/braggvectors", in: fileID, hdf5: h5),
            hasCalibration: calibration != nil,
            results: results,
            currentResultID: currentID
        )
        return SessionSidecarSnapshot(
            inventory: inventory, calibration: calibration,
            currentResult: currentResult, currentRGBAResult: currentRGBAResult,
            loadSpecification: specification,
            replayRecord: replay
        )
    }

    package static func loadInventory(from url: URL) throws -> SessionSidecarInventory {
        try loadSession(from: url).inventory
    }

    package static func loadResultMap(from url: URL) throws -> ScalarResultMap? {
        try loadSession(from: url).currentResult
    }

    package static func loadResultMap(
        id: String, from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> ScalarResultMap? {
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)
        let descriptors = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        guard descriptors.contains(where: {
            $0.id == id && $0.storage == .scalarFloat32
        }) else { return nil }
        return try readResultMap(nodeName: id, from: root, hdf5: h5)
    }

    package static func loadRGBAResultMap(
        id: String, from url: URL,
        supportedSchema: Int = SessionSidecarFormat.currentSchema
    ) throws -> RGBAResultMap? {
        guard isSafeNodeName(id), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let h5 = try HDF5WriteLibrary.load()
        let fileID = url.path.withCString {
            h5.h5fopen($0, h5FileReadOnly, h5DefaultProperty)
        }
        guard fileID >= 0 else { throw hdf5Failure("opening the session sidecar", h5) }
        defer { _ = h5.h5fclose(fileID) }
        let root = rootPath.withCString { h5.h5gopen2(fileID, $0, h5DefaultProperty) }
        guard root >= 0 else { throw hdf5Failure("opening the session root", h5) }
        defer { _ = h5.h5gclose(root) }
        try enforceMinimumReader(on: root, hdf5: h5, supportedSchema: supportedSchema)
        let descriptors = try readResultDescriptors(from: root, file: fileID, hdf5: h5)
        guard descriptors.contains(where: { $0.id == id && $0.storage == .rgba8 }) else {
            return nil
        }
        return try readRGBAResultMap(nodeName: id, from: root, hdf5: h5)
    }

    /// Deterministic, HDF5-safe node name. The hash avoids collisions when two
    /// future result kinds sanitize to the same ASCII slug.
    package static func resultNodeName(forKind kind: String) -> String {
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
        let kind = try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
            ?? "unknown"
        let valueUnits = try readStringAttribute(
            "mac4dstem_value_units", on: group, hdf5: h5
        ) ?? "intensity"
        let provenance = try dpcAngleReadState(
            kind: kind,
            valueUnits: valueUnits,
            provenance: decodeProvenance(try readStringAttribute(
                "mac4dstem_provenance", on: group, hdf5: h5
            ))
        ).provenance
        return SessionResultDescriptor(
            id: nodeName,
            kind: kind,
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Saved result",
            valueUnits: valueUnits,
            width: width,
            height: height,
            storage: storage,
            pixelSizeRow: try readStringAttribute(
                "mac4dstem_pixel_size_row", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelSizeColumn: try readStringAttribute(
                "mac4dstem_pixel_size_column", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelUnits: try readStringAttribute(
                "mac4dstem_pixel_units", on: group, hdf5: h5
            ),
            provenance: provenance
        )
    }

    /// Normalizes the read-time contract for the one historical DPC encoding
    /// error. Both descriptors and decoded pixels must report the same state;
    /// the sidecar itself remains untouched until the user next saves it.
    private static func dpcAngleReadState(
        kind: String, valueUnits: String, provenance: [String: String]
    ) throws -> (provenance: [String: String], needsTurnToRadianScale: Bool) {
        guard kind == "dpc_angle", valueUnits == "rad" else {
            return (provenance, false)
        }
        var normalized = provenance
        switch normalized[ScalarResultMap.dpcAngleEncodingKey] {
        case nil, ScalarResultMap.dpcAngleTurnsEncoding:
            normalized[ScalarResultMap.dpcAngleEncodingKey] =
                ScalarResultMap.dpcAngleRadiansEncoding
            normalized["dpc_angle_migration"] = "normalized_turns_to_radians"
            return (normalized, true)
        case ScalarResultMap.dpcAngleRadiansEncoding:
            return (normalized, false)
        case .some:
            throw WriterError.malformedAttribute(
                name: "mac4dstem_provenance.\(ScalarResultMap.dpcAngleEncodingKey)"
            )
        }
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
        let kind = try readStringAttribute("mac4dstem_kind", on: group, hdf5: h5)
            ?? "unknown"
        let valueUnits = try readStringAttribute(
            "mac4dstem_value_units", on: group, hdf5: h5
        ) ?? "intensity"
        let readState = try dpcAngleReadState(
            kind: kind,
            valueUnits: valueUnits,
            provenance: decodeProvenance(try readStringAttribute(
                "mac4dstem_provenance", on: group, hdf5: h5
            ))
        )
        if readState.needsTurnToRadianScale {
            pixels = pixels.map { $0 * (2 * .pi) }
        }
        return ScalarResultMap(
            width: width,
            height: height,
            pixels: pixels,
            kind: kind,
            displayName: try readStringAttribute(
                "mac4dstem_display_name", on: group, hdf5: h5
            ) ?? "Restored result",
            valueUnits: valueUnits,
            pixelSizeRow: try readStringAttribute(
                "mac4dstem_pixel_size_row", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelSizeColumn: try readStringAttribute(
                "mac4dstem_pixel_size_column", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelUnits: try readStringAttribute(
                "mac4dstem_pixel_units", on: group, hdf5: h5
            ),
            provenance: readState.provenance
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
            ) ?? "rgba",
            pixelSizeRow: try readStringAttribute(
                "mac4dstem_pixel_size_row", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelSizeColumn: try readStringAttribute(
                "mac4dstem_pixel_size_column", on: group, hdf5: h5
            ).flatMap(Double.init),
            pixelUnits: try readStringAttribute(
                "mac4dstem_pixel_units", on: group, hdf5: h5
            ),
            provenance: decodeProvenance(try readStringAttribute(
                "mac4dstem_provenance", on: group, hdf5: h5
            ))
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
        loadSpecification: LoadSpecification? = nil,
        replayRecord: SessionReplayRecord? = nil,
        supportedSchema: Int = SessionSidecarFormat.currentSchema,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?
    ) throws {
        try checkCancellation(cancellation)

        let fm = FileManager.default
        let (temporary, scratchDirectory) = temporaryPublishURL(for: destination)
        var published = false
        defer {
            // try? OK (v2 S7 audit): best-effort scratch cleanup on the way
            // out — on the failure path the primary error is already
            // in flight, and a leftover .tmp in the system-provided scratch
            // directory harms nothing the error did not already report.
            if !published { try? fm.removeItem(at: temporary) }
            if let scratchDirectory { try? fm.removeItem(at: scratchDirectory) }
        }

        let hdf5 = try HDF5WriteLibrary.load()
        try writeFile(
            at: temporary, vectors: vectors, map: map, rgbaMap: rgbaMap,
            qWidth: qWidth, qHeight: qHeight,
            calibration: calibration, preserving: existing, removingKind: removingKind,
            loadSpecification: loadSpecification,
            replayRecord: replayRecord,
            supportedSchema: supportedSchema,
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

    /// A scratch URL to build a file in before publishing it onto `destination`.
    ///
    /// **Deliberately not a sibling of `destination`.** Every write path used to
    /// build `.<name>.<uuid>.tmp` in the destination's own directory. Under the
    /// app sandbox `NSSavePanel` grants access to *the file the user chose*, not
    /// to arbitrary new siblings in that folder, so creating the scratch file was
    /// denied and HDF5 failed with "creating the temporary file" — reported by
    /// the release owner 2026-08-05, and it blocked export outright.
    ///
    /// `.itemReplacementDirectory` is the system-sanctioned answer: it is
    /// writable under the sandbox and is guaranteed to be on the **same volume**
    /// as `destination`, so the `rename(2)` publish stays atomic. Falls back to a
    /// sibling only if the system cannot provide one, which preserves the old
    /// behaviour rather than failing outright on an unusual volume.
    private static func temporaryPublishURL(
        for destination: URL
    ) -> (url: URL, scratchDirectory: URL?) {
        let name = ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        let fm = FileManager.default
        if let directory = try? fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination, create: true
        ) {
            return (directory.appendingPathComponent(name, isDirectory: false), directory)
        }
        return (
            destination.deletingLastPathComponent()
                .appendingPathComponent(name, isDirectory: false),
            nil
        )
    }

    /// Re-express the session calibration in the exported file's own frame.
    ///
    /// The input is the VIEW's calibration (L3 re-references it at load time;
    /// values fitted in-session are natively view-frame), so the only
    /// transform applied here is the EXPORT-time bin — the same
    /// `(x + 0.5) / b - 0.5` convention as `CalibrationReReference`, and
    /// deliberately so (its `binnedCoordinate` doc comment names this site).
    ///
    /// **Refuses instead of guessing** (v2 S10; both were silent before):
    /// origin maps whose shape is not this view's scan have no honest
    /// sub-rectangle, and an origin outside the exported detector means the
    /// calibration and the pixels are in different frames — writing either
    /// would reproduce py4DSTEM's `bin_data_diffraction` defect with this
    /// writer's own signature on it.
    private static func transformedCalibration(
        _ source: PixelCalibration,
        descriptor: DatasetDescriptor,
        options: CalibratedDataCubeExportOptions
    ) throws -> PixelCalibration {
        var output = source
        let bin = Double(options.qBin)
        output.qSize = source.qSize.map { $0 * bin }
        let transformQ: (Double) -> Double = { ($0 + 0.5) / bin - 0.5 }
        output.qx0Mean = source.qx0Mean.map(transformQ)
        output.qy0Mean = source.qy0Mean.map(transformQ)
        output.probeSemiangle = source.probeSemiangle.map { $0 / bin }
        // The ellipse semi-axes are LENGTHS in detector pixels, exactly like
        // the probe radius one line up — omitting them left an export-binned
        // file carrying view-frame axes beside binned-frame everything else
        // (found by S10's review of this function; theta is an angle and
        // does not move).
        output.ellipseA = source.ellipseA.map { $0 / bin }
        output.ellipseB = source.ellipseB.map { $0 / bin }

        if let maps = source.originMaps {
            guard maps.shape == [descriptor.ry, descriptor.rx],
                  maps.fittedQX.count == descriptor.ry * descriptor.rx,
                  maps.fittedQY.count == descriptor.ry * descriptor.rx else {
                throw WriterError.invalidDimensions(
                    "the calibration's origin maps describe a \(maps.shape.map(String.init).joined(separator: " × ")) scan but the exported view's scan is \(descriptor.ry) × \(descriptor.rx) — the maps are not in this view's frame, so there is no honest way to export them"
                )
            }
            func cropped(_ values: [Double]?) -> [Double]? {
                // Optional arrays (measured maps) may be absent; a PRESENT
                // array of the wrong length is the same frame mismatch as a
                // wrong shape and is refused by the caller's guard above for
                // the fitted maps — measured maps that disagree are dropped
                // with the same reasoning `CalibrationReReference` applies
                // (they are a fit-quality record, not the calibration).
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
            // Non-optional by the guard above: the fitted maps have the
            // exact counts `cropped` requires.
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

        // The frame-mismatch net: every exported origin must lie inside the
        // exported detector, in pixel-centre coordinates `[-0.5, extent-0.5)`
        // (the same half-open convention as `CalibrationReReference`, written
        // in the positive so NaN refuses). py4DSTEM's qx is the FIRST Q axis
        // — this file's dim2, extent qy/bin. A view-frame calibration always
        // passes (the view contains its beam or L3 already invalidated it);
        // what this catches is a source-frame calibration handed in beside
        // reduced pixels — a net, not a proof, and the invariant's real home
        // is L3.
        let outQX = Double(descriptor.qy / options.qBin)   // py4DSTEM qx extent
        let outQY = Double(descriptor.qx / options.qBin)   // py4DSTEM qy extent
        func inside(_ value: Double, _ extent: Double) -> Bool {
            value.isFinite && value >= -0.5 && value < extent - 0.5
        }
        var outlier: (name: String, x: Double, extent: Double)?
        if let qx0 = output.qx0Mean, !inside(qx0, outQX) {
            outlier = ("mean origin qx0", qx0, outQX)
        } else if let qy0 = output.qy0Mean, !inside(qy0, outQY) {
            outlier = ("mean origin qy0", qy0, outQY)
        } else if let maps = output.originMaps {
            if let index = maps.fittedQX.firstIndex(where: { !inside($0, outQX) }) {
                outlier = ("fitted origin qx0 at scan position \(index)",
                           maps.fittedQX[index], outQX)
            } else if let index = maps.fittedQY.firstIndex(where: { !inside($0, outQY) }) {
                outlier = ("fitted origin qy0 at scan position \(index)",
                           maps.fittedQY[index], outQY)
            }
        }
        if let outlier {
            throw WriterError.invalidDimensions(
                "the \(outlier.name) lands at \(String(format: "%.2f", outlier.x)) in the exported detector, outside its \(Int(outlier.extent))-pixel extent — the calibration handed to the export is not in this view's frame, and writing it would pair pixels in one frame with an origin in another"
            )
        }
        return output
    }

    private static func writeCalibratedDataCubeFile(
        at url: URL,
        source: any FourDDataSource,
        view: LoadView,
        calibration: PixelCalibration,
        options: CalibratedDataCubeExportOptions,
        outputShape: [Int],
        derivation: DataCubeDerivation?,
        replayRecord: SessionReplayRecord?,
        cancellation: AnalysisCancellationToken?,
        progress: (@Sendable (Double) -> Void)?,
        hdf5 h5: HDF5WriteLibrary
    ) async throws {
        let descriptor = view.descriptor
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
        // Provenance the reduced file carries about itself (v2 S10): where its
        // pixels came from, and the recipe of the analyses run on this data —
        // the recipe already re-expressed in THIS file's frame by the caller
        // (`ReplayRecordFrameMap`), never the view's, so no reader has to know
        // a frame this file cannot describe. py4DSTEM ignores both attributes.
        // Absence is absence: a session with no recipe stamps nothing.
        if let derivation, let json = derivation.jsonString {
            try writeStringAttribute(derivationAttribute, value: json, on: root, hdf5: h5)
        }
        if let replayRecord, !replayRecord.isEmpty, let json = replayRecord.jsonString {
            try writeStringAttribute(replayRecordAttribute, value: json, on: root, hdf5: h5)
        }
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
            let sourceTile = try await source.readScanTile(view, yRange: sourceY..<endY)
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
        loadSpecification: LoadSpecification?,
        replayRecord: SessionReplayRecord?,
        supportedSchema: Int,
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

        let root = try createGroup(SessionSidecarFormat.rootGroupName, in: fileID, hdf5: h5)
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
                    // A rewrite is a read followed by a write: a file whose
                    // marker demands a newer reader must be REFUSED here too,
                    // or a save would silently drop the newer content this
                    // build cannot see and then stamp the marker back DOWN —
                    // a mangled file claiming to be safely readable
                    // (Gate B-lite F6). The publish is atomic, so a refusal
                    // leaves the original untouched. // v2 S5
                    try enforceMinimumReader(on: existingRoot, hdf5: h5,
                                             supportedSchema: supportedSchema)
                    return try readResultDescriptors(
                        from: existingRoot, file: existingID, hdf5: h5
                    )
                }()
            }
        }
        // Preserve an existing replay record when this save carries none —
        // same rule as the result nodes above. Without this, a save from a
        // session that ran no analyses (a colleague adjusting calibration)
        // would silently ERASE the recipe the sidecar exists to carry. // v2 S5
        var preservedReplayJSON: String?
        if replayRecord == nil, let existingID {
            let existingRoot = rootPath.withCString {
                h5.h5gopen2(existingID, $0, h5DefaultProperty)
            }
            if existingRoot >= 0 {
                defer { _ = h5.h5gclose(existingRoot) }
                preservedReplayJSON = try readStringAttribute(
                    replayRecordAttribute, on: existingRoot, hdf5: h5
                )
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
            if let provenance = encodeProvenance(vectors.detectionProvenance) {
                try writeStringAttribute(
                    "mac4dstem_detection_provenance", value: provenance,
                    on: bragg, hdf5: h5
                )
            }
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
        if let specification = loadSpecification, !specification.isFullExtent,
           let json = specification.jsonString {
            // Written whenever a session is published from a reduced view, even
            // with no results yet: the specification is what makes a product
            // traceable to *file + view*, and a calibration saved from a binned
            // cube is already a product of that view.
            try writeStringAttribute(loadSpecificationAttribute, value: json,
                                     on: root, hdf5: h5)
        }
        // The schema attribute is the file's IDENTITY marker, not a result
        // manifest, so it is written on every file this writer produces —
        // a calibration-only sidecar is still a sidecar. It used to ride the
        // result-nodes condition below, which left exactly the file the
        // release owner double-clicked twice on 2026-08-19 (8.9 kB,
        // calibration only) unrecognisable to the open path's sidecar check.
        // Nothing reads this attribute to mean "has results"; the inventory
        // reads `resultNodesAttribute`. // v2 S4
        try writeStringAttribute(schemaAttribute, value: sessionSchemaVersion,
                                 on: root, hdf5: h5)
        // The minimum-reader marker, on every file (v2 S5): the oldest schema
        // that interprets THIS file without misreading it — 6 when a reduced
        // specification is recorded (dangerous to ignore), 5 otherwise, so a
        // marker-checking reader never refuses a file it could read safely.
        try writeStringAttribute(
            minimumReaderAttribute,
            value: String(minimumReaderSchema(for: loadSpecification)),
            on: root, hdf5: h5
        )
        // The replay record: the caller's live record wins; failing that, the
        // record the existing file already carried survives the rewrite.
        if let json = replayRecord?.jsonString ?? preservedReplayJSON {
            try writeStringAttribute(replayRecordAttribute, value: json,
                                     on: root, hdf5: h5)
        }
        if !resultNodeNames.isEmpty {
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
        if let value = map.pixelSizeRow {
            try writeStringAttribute("mac4dstem_pixel_size_row", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let value = map.pixelSizeColumn {
            try writeStringAttribute("mac4dstem_pixel_size_column", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let units = map.pixelUnits {
            try writeStringAttribute("mac4dstem_pixel_units", value: units,
                                     on: group, hdf5: h5)
        }
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringAttribute("mac4dstem_provenance", value: provenance,
                                     on: group, hdf5: h5)
        }

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

        let rowStep = map.pixelSizeRow ?? calibration.rSize ?? 1
        let columnStep = map.pixelSizeColumn ?? calibration.rSize ?? 1
        let dimUnits = map.pixelUnits ?? calibration.rUnits ?? "pixels"
        try writeDoubleVectorDataset("dim0", values: [0, rowStep], name: "Rx",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: [0, columnStep], name: "Ry",
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
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringDataset("provenance", value: provenance,
                                   metadataType: "string", in: metadata, hdf5: h5)
        }
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
        if let value = map.pixelSizeRow {
            try writeStringAttribute("mac4dstem_pixel_size_row", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let value = map.pixelSizeColumn {
            try writeStringAttribute("mac4dstem_pixel_size_column", value: String(value),
                                     on: group, hdf5: h5)
        }
        if let units = map.pixelUnits {
            try writeStringAttribute("mac4dstem_pixel_units", value: units,
                                     on: group, hdf5: h5)
        }
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringAttribute("mac4dstem_provenance", value: provenance,
                                     on: group, hdf5: h5)
        }

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

        let rowStep = map.pixelSizeRow ?? calibration.rSize ?? 1
        let columnStep = map.pixelSizeColumn ?? calibration.rSize ?? 1
        let dimUnits = map.pixelUnits ?? calibration.rUnits ?? "pixels"
        try writeDoubleVectorDataset("dim0", values: [0, rowStep], name: "Rx",
                                     units: dimUnits, in: group, hdf5: h5)
        try writeDoubleVectorDataset("dim1", values: [0, columnStep], name: "Ry",
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
        if let provenance = encodeProvenance(map.provenance) {
            try writeStringDataset("provenance", value: provenance,
                                   metadataType: "string", in: metadata, hdf5: h5)
        }
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

    // try? OK (v2 S7 audit): serializing a [String: String] that
    // `isValidJSONObject` just accepted cannot fail; the guard is belt and
    // braces around an unreachable branch, and nil means "write no
    // provenance attribute", which reads back as an absent one.
    private static func encodeProvenance(_ values: [String: String]) -> String? {
        guard !values.isEmpty,
              JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(
                withJSONObject: values, options: [.sortedKeys]
              ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // try? accepted with a stated limit (v2 S7 audit): a malformed
    // provenance attribute decodes as EMPTY — visibly absent labels, which a
    // reader can see and question. This is the opposite shape from the
    // specification/recipe attributes above, where absent has a load-bearing
    // meaning ("full extent" / "no recipe") and malformed must therefore
    // refuse (`WriterError.malformedAttribute`); absent provenance asserts
    // nothing.
    private static func decodeProvenance(_ value: String?) -> [String: String] {
        guard let value, let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: String] else { return [:] }
        return dictionary
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
    package var qx: Double
    package var qy: Double
    package var intensity: Double
}

nonisolated private struct H5VariableLength {
    package var length: Int
    package var pointer: UnsafeMutableRawPointer?
}

nonisolated private struct HDF5WriteLibrary: @unchecked Sendable {
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
        _ = h5open()
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
