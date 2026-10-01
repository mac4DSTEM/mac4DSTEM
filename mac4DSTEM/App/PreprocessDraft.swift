//
//  PreprocessDraft.swift
//  Role: the "Preprocess Raw Data…" sheet's own choices and what they mean —
//        pure, so the sheet, the write and the tests read one definition.
//
//  OWNER: `PendingLoad.preprocess` (X3, 2026-10-01). The sheet's crop and bin
//  are the pending load's `LoadConfiguration` (dragged on the preview panes,
//  exactly as in the configurator); this draft adds only what the load never
//  has — scan stride, the hot-pixel filter, the destination and the write's
//  progress — and turns the pair into the ONE options value the existing
//  canonical writer takes (`CalibratedDataCubeExportOptions`). The writer is
//  the same one the open-cube export always used, so a setting means the same
//  file whichever door it came through.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

struct PreprocessDraft: Equatable {
    enum Origin: Equatable {
        /// A file picked for this sheet; no session calibration exists for it.
        case rawFile
        /// The open dataset's current view (owner 2026-10-01, answer 2a): the
        /// session's calibration is in the same frame, so its readiness shows.
        case currentView(name: String)
    }

    var origin: Origin
    /// py4DSTEM `thin_data_real`: every Nth position of the cropped scan.
    var scanStride = 1
    var hotPixelsEnabled = false
    var hotPixelThreshold = 8.0
    var destination: URL?
    /// Non-nil while the file is being written (0…1).
    var writeProgress: Double?
    /// The last write's failure, shown in the sheet (an alert would sit
    /// behind it).
    var failure: String?

    var isWriting: Bool { writeProgress != nil }

    /// Owner's answer 1a: a raw file has no session calibration, so the
    /// readiness section is shown only when the source is the open dataset.
    var showsCalibrationReadiness: Bool {
        if case .currentView = origin { return true }
        return false
    }

    // MARK: - From the configuration to the writer's options

    /// The cropped scan, in the sheet's source frame.
    static func scanExtent(_ configuration: LoadConfiguration) -> (y: Range<Int>, x: Range<Int>) {
        let source = configuration.source
        return (configuration.scanCrop?.yRange ?? 0..<source.ry,
                configuration.scanCrop?.xRange ?? 0..<source.rx)
    }

    /// The largest stride the cropped scan allows (the writer refuses more).
    static func strideLimit(for configuration: LoadConfiguration) -> Int {
        let extent = scanExtent(configuration)
        return max(1, min(extent.y.count, extent.x.count))
    }

    /// What is written: a tighter crop can shrink the range under a stride set
    /// earlier, and the clamped value is the one that goes in the file.
    func effectiveStride(for configuration: LoadConfiguration) -> Int {
        min(max(1, scanStride), Self.strideLimit(for: configuration))
    }

    func options(for configuration: LoadConfiguration) -> CalibratedDataCubeExportOptions {
        let extent = Self.scanExtent(configuration)
        return CalibratedDataCubeExportOptions(
            scanY: extent.y, scanX: extent.x,
            qBin: configuration.detectorBin, tileRows: 1,
            scanStride: effectiveStride(for: configuration),
            qCropY: configuration.detectorCrop?.yRange,
            qCropX: configuration.detectorCrop?.xRange,
            hotPixelThreshold: hotPixelsEnabled ? hotPixelThreshold : nil
        )
    }

    /// Rx-last order the file stores: [scan y, scan x, detector y, detector x].
    func outputShape(for configuration: LoadConfiguration) -> [Int] {
        let options = options(for: configuration)
        let source = configuration.source
        let bin = max(1, options.qBin)
        let rows = (options.qCropY?.count ?? source.qy) / bin
        let columns = (options.qCropX?.count ?? source.qx) / bin
        return [options.scanYPositions.count, options.scanXPositions.count, rows, columns]
    }

    func outputBytes(for configuration: LoadConfiguration) -> Int {
        outputShape(for: configuration).reduce(MemoryLayout<Float>.size) { $0 * max(0, $1) }
    }

    /// The Save panel's suggested name.
    static func suggestedFileName(forSource name: String) -> String {
        (name as NSString).deletingPathExtension + "_preprocessed.h5"
    }

    /// The destination as the sheet shows it: home abbreviated to "~".
    var destinationLabel: String? {
        destination.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }
}
