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

/// Which part of the file a session sidecar says it describes.
///
/// The writer records a load specification only for a REDUCED view
/// (`BraggVectorEMDWriter`: a full-extent save writes no attribute), so
/// "absent" means two different things by era. From schema 6 (2026-08-24) on
/// it is the writer's own statement "whole file". Before it — schema 5, which
/// stayed 5 across the 2026-08-18 specification addition — it is the
/// absence of any statement, and reading it as the whole file is a claim the
/// file never made (S18).
package nonisolated enum SessionViewRecord: Equatable, Sendable {
    /// The sidecar states the view its products were computed under.
    case recorded(LoadSpecification)
    /// A sidecar from before views were recorded: no statement either way.
    case unrecorded

    /// The first schema whose writer states the view (absence = whole file).
    package static let firstSchemaThatRecordsTheView = 6
}

package nonisolated struct SessionSidecarSnapshot: Sendable {
    package let inventory: SessionSidecarInventory
    package let calibration: PixelCalibration?
    package let currentResult: ScalarResultMap?
    package let currentRGBAResult: RGBAResultMap?
    /// The specification ATTRIBUTE, verbatim: written only for a reduced view,
    /// so nil is "whole file" from schema 6 and "not recorded" before it —
    /// read `viewRecord`, never `?? .fullExtent` (S18).
    ///
    /// Reopening re-applies this to the SOURCE file. It is never used to
    /// re-derive from reduced data — the source is what is reopened, and the
    /// specification is applied to it again, which is the whole reason a crop is
    /// a view rather than a new dataset (docs/v2-scope.md §6.1).
    package var loadSpecification: LoadSpecification? = nil
    /// The sidecar's own schema stamp; nil when absent or unreadable.
    package var schema: Int? = nil
    /// What the sidecar says about its view — `loadSpecification` alone cannot
    /// tell "whole file" from "never recorded" (`SessionViewRecord`).
    package var viewRecord: SessionViewRecord {
        if let loadSpecification { return .recorded(loadSpecification) }
        if let schema, schema >= SessionViewRecord.firstSchemaThatRecordsTheView {
            return .recorded(.fullExtent)
        }
        return .unrecorded
    }
    /// The recorded analysis pipeline, when the sidecar carries one.
    /// **Nil means "no recipe was recorded"** — absence is absence, never an
    /// empty-but-asserted record (the `?? .fullExtent` lesson). // v2 S5
    package var replayRecord: SessionReplayRecord? = nil
    /// The run graph (schema 7). Nil only when the file carried neither a
    /// lineage nor a record. From a v1 file it is SYNTHESIZED in memory —
    /// nodes marked `source: "v1"`, `inputs` absent — and the file is not
    /// touched. // ADR 047 L1
    package var lineage: SessionLineage? = nil
    /// Set when a lineage was present but disagreed with the record beside it,
    /// so the file was read as v1. Nil otherwise. // ADR 047 R7
    package var lineageNote: String? = nil

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(inventory: SessionSidecarInventory, calibration: PixelCalibration?, currentResult: ScalarResultMap?, currentRGBAResult: RGBAResultMap?, loadSpecification: LoadSpecification? = nil, schema: Int? = nil, replayRecord: SessionReplayRecord? = nil, lineage: SessionLineage? = nil, lineageNote: String? = nil) {
        self.inventory = inventory
        self.calibration = calibration
        self.currentResult = currentResult
        self.currentRGBAResult = currentRGBAResult
        self.loadSpecification = loadSpecification
        self.schema = schema
        self.replayRecord = replayRecord
        self.lineage = lineage
        self.lineageNote = lineageNote
    }
}

/// Bounded preprocessing applied while streaming a source datacube into a
/// canonical py4DSTEM EMD file. Ranges use app/HDF5 order `[Ry,Rx]` and Q
/// binning sums non-overlapping detector blocks, matching py4DSTEM's count-
/// preserving diffraction binning semantics.
///
/// The steps run in py4DSTEM's order for the same calls: real-space crop,
/// then `thin_data_real` (stride), detector `crop_Q`, `bin_Q`, and last
/// `filter_hot_pixels` on the binned patterns (the order the owner's own
/// preprocessed file was made in, docs/archive/v4/parity-28gb-2026-09-30.md).
package nonisolated struct CalibratedDataCubeExportOptions: Sendable, Equatable {
    package let scanY: Range<Int>
    package let scanX: Range<Int>
    package let qBin: Int
    package let tileRows: Int
    /// py4DSTEM `thin_data_real`: every `scanStride`-th position of the
    /// cropped scan, starting at the crop's first, `floor(count / stride)` of
    /// them per axis (preprocess.py:315-346).
    package let scanStride: Int
    /// py4DSTEM `crop_Q`, in the view's detector pixels, first axis (py4DSTEM
    /// Qx) then second (Qy); `nil` keeps the whole detector. Applied before
    /// the bin, so the bin's edge remainder is trimmed off the CROPPED extent.
    package let qCropY: Range<Int>?
    package let qCropX: Range<Int>?
    /// py4DSTEM `filter_hot_pixels(thresh)`; `nil` = off (the default).
    package let hotPixelThreshold: Double?

    package init(scanY: Range<Int>, scanX: Range<Int>, qBin: Int = 1, tileRows: Int = 1,
                 scanStride: Int = 1, qCropY: Range<Int>? = nil, qCropX: Range<Int>? = nil,
                 hotPixelThreshold: Double? = nil) {
        self.scanY = scanY
        self.scanX = scanX
        self.qBin = qBin
        self.tileRows = tileRows
        self.scanStride = scanStride
        self.qCropY = qCropY
        self.qCropX = qCropX
        self.hotPixelThreshold = hotPixelThreshold
    }

    /// View scan positions the export keeps, in output order.
    package var scanYPositions: [Int] { Self.positions(scanY, stride: scanStride) }
    package var scanXPositions: [Int] { Self.positions(scanX, stride: scanStride) }

    private static func positions(_ range: Range<Int>, stride: Int) -> [Int] {
        guard stride > 0 else { return [] }
        return (0..<(range.count / stride)).map { range.lowerBound + $0 * stride }
    }

    /// True when the export changes the detector frame or thins the scan in a
    /// way the replay recipe's frame table does not describe.
    package var reframesRecipe: Bool { scanStride != 1 || qCropY != nil || qCropX != nil }
}

package nonisolated struct CalibratedDataCubeExportSummary: Sendable, Equatable {
    package let shape: [Int]
    package let discardedQRows: Int
    package let discardedQColumns: Int
    /// The hot-pixel mask the filter found, `[row, column]` in the exported
    /// detector; empty when the filter was off or found none.
    package let hotPixels: [[Int]]

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(shape: [Int], discardedQRows: Int, discardedQColumns: Int,
                             hotPixels: [[Int]] = []) {
        self.shape = shape
        self.discardedQRows = discardedQRows
        self.discardedQColumns = discardedQColumns
        self.hotPixels = hotPixels
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
    /// Present only when the export thinned the scan (X2): the source-scan
    /// stride, so `scan_offset` + `scan_stride` name every position kept.
    package var scanStride: Int?
    /// Present only when the hot-pixel filter ran (X2): py4DSTEM's `thresh`
    /// and the mask it found, `[row, column]` in THIS file's detector — the
    /// 15 positions of a filtered file are a property of the file, so the
    /// file says them.
    package var hotPixelThreshold: Double?
    package var hotPixels: [[Int]]?

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
        case scanStride = "scan_stride"
        case hotPixelThreshold = "hot_pixel_threshold"
        case hotPixels = "hot_pixels"
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
                        sourceFileName: String?,
                        hotPixels: [[Int]] = []) -> DataCubeDerivation {
        let specification = view.specification
        let scanCrop = specification.scanCrop
        let detectorCrop = view.readDetectorCrop
        // The export's own detector crop is in VIEW pixels, each
        // `detectorBin` source pixels wide.
        let viewBin: Int = specification.detectorBin
        let cropY0: Int = options.qCropY?.lowerBound ?? 0
        let cropX0: Int = options.qCropX?.lowerBound ?? 0
        let viewOffsetY: Int = detectorCrop?.yOffset ?? 0
        let viewOffsetX: Int = detectorCrop?.xOffset ?? 0
        let scanOffsetY: Int = (scanCrop?.yOffset ?? 0) + options.scanY.lowerBound
        let scanOffsetX: Int = (scanCrop?.xOffset ?? 0) + options.scanX.lowerBound
        // Assigned property by property: one 14-argument memberwise call with
        // arithmetic arguments exceeds the type checker's budget.
        var derivation = DataCubeDerivation(
            sourceFile: sourceFileName,
            scanOffsetY: scanOffsetY,
            scanOffsetX: scanOffsetX,
            scanHeight: outputShape[0],
            scanWidth: outputShape[1],
            detectorOffsetY: viewOffsetY + cropY0 * viewBin,
            detectorOffsetX: viewOffsetX + cropX0 * viewBin,
            detectorBin: viewBin * options.qBin,
            detectorHeight: outputShape[2],
            detectorWidth: outputShape[3]
        )
        if options.scanStride != 1 { derivation.scanStride = options.scanStride }
        if let threshold = options.hotPixelThreshold {
            derivation.hotPixelThreshold = threshold
            derivation.hotPixels = hotPixels
        }
        return derivation
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
