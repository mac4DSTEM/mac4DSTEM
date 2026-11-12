//
//  ProductDataExport.swift
//  Role: "Export Data…" in Results — the product on screen written as its own .h5 file, the float
//        array exactly as computed (not the display-mapped image) with pixel size, units, kind and
//        provenance, as a py4DSTEM-readable EMD 1.0 RealSlice. No new HDF5 layer: it reuses
//        `BraggVectorEMDWriter.writeScientificBundle` with a one-field bundle. Owner card S8 (b),
//        2026-10-02. Colour-only products (an RGBA map) are not exported here.
//

import AppKit
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import Foundation
import UniformTypeIdentifiers

extension AppState {
    /// The scalar map the Export Data… button would write; nil when the view is a colour image or
    /// nothing is shown. Panel-free so a test can read the exact payload.
    func productDataExportMap() -> ScalarResultMap? {
        currentScalarResultMapForPersistence()
    }

    /// The numbers behind the phase map on screen, one field each per scan position: the phase label (the index into
    /// `phase_names`, -1 where no phase won), the verdict code, the winning mean distance and the margin over the best other
    /// phase (Å⁻¹, NaN where none was scored) and the matched vector count. Nil unless the phase map is the product shown.
    func phaseMapDataExportMaps() -> [ScalarResultMap]? {
        guard resultPresentation.product?.kind == "phase_map", let map = phaseMapping.map,
              map.width > 0, map.height > 0, map.results.count == map.width * map.height else { return nil }
        let own = scanMapPersistenceMetadata(for: .phaseMapping)
        let provenance = own.provenance.merging([
            "phase_names": map.phaseNames.joined(separator: "\n"),
            "matrix_phase_index": String(map.matrixPhaseIndex),
            "verdict_codes": PhaseVerdict.allCases.map { "\($0.rawValue) \($0.displayName)" }.joined(separator: ", "),
        ]) { _, new in new }
        func field(_ kind: String, _ name: String, _ units: String, _ value: (PhaseVectorResult) -> Float) -> ScalarResultMap {
            ScalarResultMap(width: map.width, height: map.height, pixels: map.results.map(value), kind: kind,
                            displayName: name, valueUnits: units, pixelSizeRow: own.row, pixelSizeColumn: own.column,
                            pixelUnits: own.units, provenance: provenance)
        }
        return [
            field("phase_label", "Phase label", "phase index") {
                ($0.verdict == .matrix || $0.verdict == .indexed) && $0.phaseIndex >= 0 ? Float($0.phaseIndex) : -1
            },
            field("phase_verdict", "Phase verdict", "verdict code") { Float($0.verdict.rawValue) },
            field("phase_distance", "Phase mean distance", "Å⁻¹") { $0.score },
            field("phase_contrast", "Phase contrast", "Å⁻¹") { $0.phaseContrast },
            field("phase_matched", "Phase matched vectors", "count") { Float($0.matchedCount) },
        ]
    }

    /// True when the product on screen is a colour image only (the button's disabled-help case).
    var productIsColourImageOnly: Bool {
        resultPresentation.resultImage == nil && resultPresentation.resultRGBA != nil
    }

    func exportProductData() {
        guard let descriptor, let map = productDataExportMap() else {
            present(SimpleError("This view has no scalar data to export."))
            return
        }
        let stem = (descriptor.fileName as NSString).deletingPathExtension
        let kind = map.kind.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let panel = NSSavePanel()
        panel.title = "Export Data"
        panel.allowedContentTypes = [UTType(filenameExtension: "h5") ?? .data]
        panel.nameFieldStringValue = "\(stem)_\(String(kind)).h5"
        guard panel.runModal() == .OK, let url = panel.url else {
            statusText = "Data export cancelled"
            return
        }
        // The source file and its sidecar are never overwritten (the publish renames over the target).
        if let line = BraggVectorEMDWriter.exportDestinationRefusal(url, sourcePath: descriptor.filePath) {
            present(SimpleError(line))
            return
        }
        let calibration = sessionPixelCalibration(descriptor: descriptor)
        let token = beginCancellableOperation("Export data", status: "Writing \(map.displayName)…", totalUnits: 1)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishCancellableOperation(token) }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BraggVectorEMDWriter.writeScientificBundle(
                        maps: [map], calibration: calibration, to: url, cancellation: token)
                }.value
                guard self.isCurrentOperation(token) else { return }
                self.recordExportRun(format: "emd_realslice", fileName: url.lastPathComponent,
                                     productKind: map.kind)   // lineage sink (ADR 047)
                self.statusText = "Exported \(map.displayName) → \(url.lastPathComponent)"
            } catch BraggVectorEMDWriter.WriterError.cancelled {
                self.statusText = "Data export cancelled"
            } catch {
                self.present(error)
            }
        }
    }
}
