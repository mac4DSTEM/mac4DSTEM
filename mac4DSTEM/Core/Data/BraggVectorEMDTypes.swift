//
//  BraggVectorEMDTypes.swift
//  Role: The pure data-model types the session-sidecar / EMD export pipeline
//        passes around -- scalar and RGBA result maps, the sidecar inventory
//        and snapshot, the calibrated-DataCube export options/summary, and
//        the derivation record a reduced export stamps. No HDF5 call, no I/O:
//        every type here is a value type with no behavior beyond composing
//        and encoding its own fields.
//
//  Split out of Core/Data/BraggVectorEMDWriter.swift (audit 3.2 row 7,
//  "Core/Data/BraggVectorEMDWriter.swift splits only with byte-identical
//  output evidence and a refuter"). This piece carries none of that risk --
//  a value-type declaration behaves identically regardless of which file in
//  the module it lives in, and nothing here calls into HDF5. The writer
//  itself (BraggVectorEMDWriter, the actual H5Fcreate/H5Dwrite calls) is
//  deliberately NOT touched here; see docs/open-items.md,
//  "braggvector-emd-writer-split, prepared and parked" for why and for the
//  plan for the rest.
//

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
    package nonisolated init(id: String, kind: String, displayName: String, valueUnits: String, width: Int, height: Int, storage: SessionResultStorage, pixelSizeRow: Double?, pixelSizeColumn: Double?, pixelUnits: String?, provenance: [String: String]) {
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
    package nonisolated init(hasSidecar: Bool, hasBraggVectors: Bool, hasCalibration: Bool, results: [SessionResultDescriptor], currentResultID: String?) {
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
    package nonisolated init(inventory: SessionSidecarInventory, calibration: PixelCalibration?, currentResult: ScalarResultMap?, currentRGBAResult: RGBAResultMap?, loadSpecification: LoadSpecification? = nil, replayRecord: SessionReplayRecord? = nil) {
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
    package nonisolated init(shape: [Int], discardedQRows: Int, discardedQColumns: Int) {
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
    package nonisolated init(schema: Int = 1, sourceFile: String? = nil, scanOffsetY: Int, scanOffsetX: Int, scanHeight: Int, scanWidth: Int, detectorOffsetY: Int, detectorOffsetX: Int, detectorBin: Int, detectorHeight: Int, detectorWidth: Int) {
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
