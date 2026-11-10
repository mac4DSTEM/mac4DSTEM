//
//  AgentDoorSnapshot.swift
//  Role: What a window tells an agent about itself (`AgentDoorRouter`): the state the person sees, as JSON, and the two pictures
//        the panes show, as PNG. Read-only: nothing here writes a property, starts a run or touches a file.
//
//  One source per fact. The result picture is `resultExportImage`, the figure File > Export writes; its record is
//  `exportedImageProvenanceRecord`, the one that figure carries. The pattern picture is the export's raster with what the pane
//  draws over it: the virtual detector in its task and, in the Disks task, the detected disks. Calibration states are the
//  readiness report's own words. So an agent judges what the person would judge, not a second rendering.
//
//  Numbers JSON cannot carry (NaN, infinity) are written as null.
//

import CoreGraphics
import Foundation
import ImageIO
import ShellLayout
import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

nonisolated enum AgentJSON {
    /// A finite number, or null.
    static func number<T: BinaryFloatingPoint>(_ value: T?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return Double(value)
    }

    static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    /// A `Codable` value as JSON: sorted keys, ISO 8601 dates, non-finite numbers as the strings "NaN", "Infinity", "-Infinity".
    static func encoded<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try? encoder.encode(value)
    }

    /// The PNG bytes of `image`; nil when ImageIO cannot write it.
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// The recipe and the run graph it is the projection of, as the sidecar stores them.
nonisolated struct AgentLineageAnswer: Encodable {
    var recipe: [SessionReplayRecord.Step]
    var lineage: SessionLineage
}

extension AppState {

    // MARK: Pictures

    /// The diffraction pattern as the pane shows it: the export's pixels and scale bar, the virtual detector in its task and, in the
    /// Disks task, the detected disks of the pattern on screen (`agentPatternOverlays`).
    func agentPatternImage(scale: Int) throws -> CGImage {
        let raster = try patternExportRaster()
        return Self.burnScaleBar(on: raster.image, unitsPerDataPixel: raster.sampling, unitLabel: raster.unit,
                                 pixelScale: scale, overlays: agentPatternOverlays)
    }

    /// What the diffraction pane strokes over the pattern, under the pane's own conditions (`UI/ImagePanes.swift`).
    var agentPatternOverlays: [FigureOverlay] {
        var overlays = patternExportOverlays
        if navigation.analysisMode == .disks, !currentPeaks.isEmpty {
            overlays.append(.peaks(currentPeaks, probeRadius: probeKernel?.probeRadius, exportColorScheme))
        }
        return overlays
    }

    // MARK: The window in one line

    func agentSummary(id: String) -> [String: Any] {
        [
            "id": id,
            "file_name": AgentJSON.orNull(descriptor?.fileName),
            "has_4d_dataset": hasDataset,
            "has_spectrum_image": hasSpectrumImage,
            "workspace": navigation.workspaceArea.title,
            "task": navigation.analysisMode.rawValue,
            "busy": isBusy,
            "status": statusText,
        ]
    }

    // MARK: The window in full

    func agentSnapshot(id: String) -> [String: Any] {
        var snapshot = agentSummary(id: id)
        snapshot["dataset"] = agentDataset
        snapshot["calibration"] = agentCalibration
        snapshot["view"] = [
            "workspace": navigation.workspaceArea.title,
            "workspace_id": navigation.workspaceArea.rawValue,
            "task": navigation.analysisMode.rawValue,
            "scan_position": ["x": selectedScan.x, "y": selectedScan.y],
            "pattern_shown": patternDisplayMode.rawValue,
            "task_settings": AgentJSON.orNull(settingsReplaySignature(for: navigation.analysisMode)),
        ] as [String: Any]
        snapshot["operation"] = [
            "busy": isBusy,
            "name": AgentJSON.orNull(activeOperation),
            "progress": AgentJSON.number(progress),
            "status": statusText,
            "error": AgentJSON.orNull(errorMessage),
        ] as [String: Any]
        snapshot["result"] = agentResult(id: id)
        snapshot["pattern"] = agentPattern(id: id)
        snapshot["disk_detection"] = agentDiskDetection
        snapshot["session"] = agentSession
        snapshot["has_precipitate_objects"] = precipitateObjectReport != nil
        snapshot["log_tail"] = Array(activityLog.messages.suffix(20))
        return snapshot
    }

    private var agentDataset: Any {
        guard let descriptor else { return NSNull() }
        return [
            "file_name": descriptor.fileName,
            "file_path": descriptor.filePath,
            "dataset_path": descriptor.datasetPath,
            "source_shape": descriptor.shape,
            "source_shape_order": descriptor.is4D ? "scan rows, scan columns, detector rows, detector columns" : "as stored",
            "dtype": descriptor.dtypeDescription,
            "loaded_view": loadedView.summary ?? "whole file",
            "binning_notice": AgentJSON.orNull(loadedView.binningNotice),
        ] as [String: Any]
    }

    private var agentCalibration: [String: Any] {
        let calibration = calibrationSession.calibration
        let verdict = calibrationSession.verdict
        var out: [String: Any] = [
            "quantitative": verdict.quantitative,
            "verdict": verdict.summary,
            "items": calibrationSession.readiness.items.map { item in
                ["item": item.kind.rawValue, "state": item.status.displayName, "ready": item.status.isReady, "detail": item.detail] as [String: Any]
            },
            "q_pixel_size": AgentJSON.number(calibration.qPixelSize),
            "q_pixel_units": AgentJSON.orNull(calibration.qPixelUnits),
            "r_pixel_size": AgentJSON.number(calibration.rPixelSize),
            "r_pixel_units": AgentJSON.orNull(calibration.rPixelUnits),
            "qr_rotation_deg": AgentJSON.number(calibration.rotationRad.map { Double($0) * 180 / Double.pi }),
            "probe_radius_px": AgentJSON.number(calibration.probeRadius),
            "accelerating_voltage_kv": AgentJSON.number(calibrationSession.acceleratingVoltage),
        ]
        if let origin = calibration.meanOrigin {
            out["mean_origin_px"] = ["x": AgentJSON.number(origin.x), "y": AgentJSON.number(origin.y)]
        } else {
            out["mean_origin_px"] = NSNull()
        }
        return out
    }

    private func agentResult(id: String) -> Any {
        guard let product = displayedProduct else { return NSNull() }
        var out: [String: Any] = [
            "kind": product.kind,
            "name": product.displayName,
            "width": product.width,
            "height": product.height,
            "domain": product.domain.rawValue,
            "quantitative_status": product.quantitativeStatus.rawValue,
            "value_units": product.valueUnits,
            "pixel_size_row": AgentJSON.number(product.sampling.row),
            "pixel_size_column": AgentJSON.number(product.sampling.column),
            "pixel_units": AgentJSON.orNull(product.sampling.units),
            "provenance": product.provenance,
            "caption": publicationCaption,
            "image": "/v1/windows/\(id)/result.png",
        ]
        if let range = resultDisplayedValueRange {
            out["display_range"] = ["low": AgentJSON.number(range.low), "high": AgentJSON.number(range.high)]
        }
        return out
    }

    private func agentPattern(id: String) -> Any {
        guard let pattern = displayedPattern else { return NSNull() }
        return [
            "width": pattern.qx,
            "height": pattern.qy,
            "shown": patternDisplayMode.rawValue,
            "log_scale": logScale,
            "image": "/v1/windows/\(id)/pattern.png",
        ] as [String: Any]
    }

    private var agentDiskDetection: [String: Any] {
        let params = diskDetection.diskParams
        var out: [String: Any] = [
            "parameters": [
                "corr_power": AgentJSON.number(params.corrPower),
                "sigma_dp": AgentJSON.number(params.sigmaDP),
                "sigma_cc": AgentJSON.number(params.sigmaCC),
                "subpixel": params.subpixel.rawValue,
                "upsample_factor": params.upsampleFactor,
                "min_absolute_intensity": AgentJSON.number(params.minAbsoluteIntensity),
                "min_relative_intensity": AgentJSON.number(params.minRelativeIntensity),
                "relative_to_peak": params.relativeToPeak,
                "min_peak_spacing": AgentJSON.number(params.minPeakSpacing),
                "edge_boundary": params.edgeBoundary,
                "max_num_peaks": params.maxNumPeaks,
            ] as [String: Any],
            "probe_radius_px": AgentJSON.number(probeKernel?.probeRadius),
            "validation_issues": diskDetectionValidationIssues.map(\.message),
            "current_pattern_disk_count": currentPeaks.count,
            "has_current_bragg_vectors": hasCurrentBraggVectors,
            "settings_changed_since_run": diskDetectionSettingsAreStale,
        ]
        if let diagnostics = currentDiskDiagnostics {
            out["current_pattern"] = [
                "local_maxima": diagnostics.localMaximumCount,
                "after_absolute_threshold": diagnostics.afterAbsoluteThresholdCount,
                "after_relative_threshold": diagnostics.afterRelativeThresholdCount,
                "after_spacing": diagnostics.afterSpacingCount,
                "accepted": diagnostics.acceptedCount,
                "count_limited": diagnostics.wasCountLimited,
                "correlation_maximum": AgentJSON.number(diagnostics.correlationMaximum),
                "non_finite_pixels": diagnostics.nonFinitePixelCount,
                "failure": AgentJSON.orNull(diagnostics.detectionFailure),
            ] as [String: Any]
        }
        if let summary = completedDiskSummary {
            out["scan_summary"] = [
                "positions": summary.positionCount,
                "total_disks": summary.totalPeakCount,
                "minimum_per_position": summary.minimumPeakCount,
                "median_per_position": AgentJSON.number(summary.medianPeakCount),
                "maximum_per_position": summary.maximumPeakCount,
                "positions_without_disks": summary.zeroPeakPositionCount,
                "positions_at_the_maximum": summary.atMaximumPositionCount,
                "positions_failed": summary.failedPositionCount,
                "warnings": summary.warnings,
            ] as [String: Any]
        }
        return out
    }

    private var agentSession: [String: Any] {
        [
            "has_sidecar": sessionInventory.hasSidecar,
            "has_bragg_vectors": sessionInventory.hasBraggVectors,
            "has_calibration": sessionInventory.hasCalibration,
            "saved_results": sessionInventory.results.map { saved in
                ["id": saved.id, "kind": saved.kind, "name": saved.displayName, "width": saved.width, "height": saved.height,
                 "value_units": saved.valueUnits, "provenance": saved.provenance] as [String: Any]
            },
            "recipe_steps": replay.record.steps.map(\.kind),
        ]
    }

    // MARK: Lists

    /// The detected disks of the pattern on screen, in the pattern's own pixels.
    var agentPeaks: [String: Any] {
        [
            "scan_position": ["x": selectedScan.x, "y": selectedScan.y],
            "coordinates": "detector pixels of the pattern as shown: x to the right, y down, (0, 0) the centre of the top-left pixel",
            "probe_radius_px": AgentJSON.number(probeKernel?.probeRadius),
            "disks": currentPeaks.map { peak in
                ["x": AgentJSON.number(peak.x), "y": AgentJSON.number(peak.y), "intensity": AgentJSON.number(peak.intensity)]
            },
        ]
    }

    var agentLineage: AgentLineageAnswer {
        AgentLineageAnswer(recipe: replay.record.steps, lineage: replay.lineage)
    }
}
