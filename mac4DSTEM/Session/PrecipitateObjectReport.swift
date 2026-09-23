//
//  PrecipitateObjectReport.swift
//  Role: the reader-facing table of a class map's precipitate objects — one
//        row per object, one summary per class, and the CSV that carries
//        both out of the app with their provenance. Pure, value-typed, and
//        Codable so a table window can hold a snapshot of it.
//
//  Two rules it adds on top of `PrecipitateSegmentation.classObjects`, both
//  visible in every row and summary it produces:
//  - **Minimum object size** (`minimumAreaPx`, default 1 = keep every
//    object). A user-set cut, never a shipped threshold: the published
//    Thronsen truth removed small regions with cuts of 4, 782 and 10 px on
//    ITS dataset, and on a different specimen those numbers mean nothing
//    (`docs/cloud/2026-09-23/T2-direction-check.md`). Objects under it stay
//    in the rows, flagged, and are left out of the counted statistics.
//  - **The calibration is read at report time**, not at segmentation time,
//    so a density can never be stale against the scan scale the reader
//    now has.
//
//  Statistics are `PrecipitateStatistics.density`'s own: objects touching
//  the scan edge are never counted, and density refuses without a positive
//  real-space pixel size.
//
//  Session, not Core: like `PhaseMapObjectsBridge` it composes a Core result
//  with phase names, the session's calibration and a user setting.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

package nonisolated struct PrecipitateObjectReport: Sendable, Codable, Hashable {

    package nonisolated struct Row: Sendable, Codable, Hashable, Identifiable {
        package let id: Int
        package let label: Int32
        package let phaseName: String
        package let areaPx: Int
        package let lengthPx: Double
        package let widthPx: Double
        /// (-90, 90], image frame: 0 = +x, positive reads clockwise on screen.
        package let orientationDegrees: Double
        package let centroidX: Double
        package let centroidY: Double
        package let touchesEdge: Bool
        package let belowMinimum: Bool
        /// Physical values, nil without a real-space pixel size.
        package let area: Double?
        package let length: Double?
        package let width: Double?

        /// In the counted statistics: not on the scan edge, not under the
        /// minimum size.
        package var isCounted: Bool { !touchesEdge && !belowMinimum }
        /// Length over width, both end-to-end extents (≥ 1 by construction).
        package var aspectRatio: Double { widthPx > 0 ? lengthPx / widthPx : .nan }
        /// Why a row is left out of the counted statistics, or nil.
        package var exclusion: String? {
            switch (touchesEdge, belowMinimum) {
            case (true, true): "edge, small"
            case (true, false): "edge"
            case (false, true): "small"
            case (false, false): nil
            }
        }
    }

    package nonisolated struct ClassSummary: Sendable, Codable, Hashable, Identifiable {
        package let label: Int32
        package let phaseName: String
        package let totalObjects: Int
        package let countedObjects: Int
        package let edgeExcluded: Int
        package let belowMinimumExcluded: Int
        package let areaFraction: Double?
        /// Scan pixels (`PrecipitateStatistics.density`'s contract); the
        /// physical versions below multiply by `pixelSize`.
        package let medianLengthPx: Double?
        package let meanLengthPx: Double?
        package let meanWidthPx: Double?
        /// Counted objects per unit² of analysed area; nil without a scale.
        package let arealDensity: Double?
        package var id: Int32 { label }
    }

    package let width: Int
    package let height: Int
    /// The phase map's matrix phase, so every surface colours a phase the
    /// way the map does (`PhaseMapPresentation.color`).
    package let matrixPhaseIndex: Int
    package let pixelSize: Double?
    package let pixelUnit: String?
    package let minimumAreaPx: Int
    package let analysedPixels: Int
    package let notIndexedPixels: Int
    package let analysedAreaRule: String
    package let rows: [Row]
    package let summaries: [ClassSummary]
    /// Ordered key/value provenance, written as the CSV's comment header.
    package let provenance: [[String]]

    package var hasPhysicalScale: Bool { pixelSize != nil && pixelUnit != nil }

    /// A class's colour on the phase map, 0–255 RGB.
    package func color(of label: Int32) -> PhaseMapPresentation.RGB {
        PhaseMapPresentation.color(phaseIndex: Int(label), matrixPhaseIndex: matrixPhaseIndex)
    }

    package nonisolated static func make(
        objects: PrecipitateSegmentation.ClassMapObjects,
        phaseNames: [String],
        matrixPhaseIndex: Int,
        pixelSize: Double?,
        pixelUnit: String?,
        minimumAreaPx: Int,
        provenance: [(String, String)] = []
    ) -> PrecipitateObjectReport {
        let minimum = max(1, minimumAreaPx)
        let scale: Double? = {
            guard let pixelSize, pixelSize.isFinite, pixelSize > 0, pixelUnit != nil else { return nil }
            return pixelSize
        }()
        func name(_ label: Int32) -> String {
            phaseNames.indices.contains(Int(label)) ? phaseNames[Int(label)] : "class \(label)"
        }

        var rows: [Row] = []
        var summaries: [ClassSummary] = []
        for classObjects in objects.classes {
            let phaseName = name(classObjects.label)
            let accepted = Set(classObjects.objects.filter { $0.area >= minimum }.map(\.id))
            let density = PrecipitateStatistics.density(
                objects: classObjects.objects, accepted: accepted,
                analysedPixels: objects.analysedPixels,
                pixelSize: scale, pixelUnit: scale == nil ? nil : pixelUnit)
            let belowMinimum = classObjects.objects.filter { $0.area < minimum }
            summaries.append(ClassSummary(
                label: classObjects.label, phaseName: phaseName,
                totalObjects: classObjects.objects.count,
                countedObjects: density.acceptedCount,
                edgeExcluded: density.edgeCount,
                belowMinimumExcluded: belowMinimum.count,
                areaFraction: classObjects.areaFraction,
                medianLengthPx: density.medianLength,
                meanLengthPx: density.meanLength,
                meanWidthPx: density.meanWidth,
                arealDensity: density.arealDensity))
            for object in classObjects.objects {
                let length = Double(object.lengthPx), width = Double(object.widthPx)
                rows.append(Row(
                    id: object.id, label: classObjects.label, phaseName: phaseName,
                    areaPx: object.area, lengthPx: length, widthPx: width,
                    orientationDegrees: Double(object.orientationDegrees),
                    centroidX: Double(object.centroidX), centroidY: Double(object.centroidY),
                    touchesEdge: object.touchesEdge, belowMinimum: object.area < minimum,
                    area: scale.map { Double(object.area) * $0 * $0 },
                    length: scale.map { length * $0 },
                    width: scale.map { width * $0 }))
            }
        }
        rows.sort { $0.id < $1.id }
        return PrecipitateObjectReport(
            width: objects.width, height: objects.height,
            matrixPhaseIndex: matrixPhaseIndex,
            pixelSize: scale, pixelUnit: scale == nil ? nil : pixelUnit,
            minimumAreaPx: minimum,
            analysedPixels: objects.analysedPixels,
            notIndexedPixels: objects.notIndexedPixels,
            analysedAreaRule: objects.analysedAreaRule,
            rows: rows, summaries: summaries,
            provenance: provenance.map { [$0.0, $0.1] })
    }

    // MARK: - Objects image

    /// The objects drawn over the scan: counted objects in their phase's map
    /// colour, objects left out of the statistics (scan edge, under the
    /// minimum size) at 35 % of that colour over the matrix grey, the matrix
    /// and unselected classes in the matrix grey, not-indexed positions in
    /// the phase map's own two-grey hatch, no-data positions transparent.
    /// The picture shows exactly what the numbers count.
    package nonisolated static func image(
        objects: PrecipitateSegmentation.ClassMapObjects,
        report: PrecipitateObjectReport,
        verdicts: [PhaseVerdict],
        matrixPhaseIndex: Int
    ) -> RGBAImage {
        let count = objects.width * objects.height
        var out = [UInt8](repeating: 0, count: max(0, count * 4))
        let matrix = PhaseMapPresentation.matrixColor
        for i in 0..<count {
            var rgb = matrix
            var alpha: UInt8 = 255
            if verdicts.indices.contains(i) {
                switch verdicts[i] {
                case .notIndexed:
                    let x = i % objects.width, y = i / objects.width
                    rgb = ((x + y) % 6 < 3) ? PhaseMapPresentation.notIndexedColors.0
                                            : PhaseMapPresentation.notIndexedColors.1
                case .noData:
                    alpha = 0
                case .matrix, .indexed:
                    break
                }
            }
            out[i * 4] = rgb.r; out[i * 4 + 1] = rgb.g; out[i * 4 + 2] = rgb.b; out[i * 4 + 3] = alpha
        }
        let counted = Set(report.rows.filter(\.isCounted).map(\.id))
        for classObjects in objects.classes {
            let full = PhaseMapPresentation.color(phaseIndex: Int(classObjects.label),
                                                  matrixPhaseIndex: matrixPhaseIndex)
            let dim: PhaseMapPresentation.RGB = (
                UInt8((Int(full.r) * 35 + Int(matrix.r) * 65) / 100),
                UInt8((Int(full.g) * 35 + Int(matrix.g) * 65) / 100),
                UInt8((Int(full.b) * 35 + Int(matrix.b) * 65) / 100))
            for object in classObjects.objects {
                let rgb = counted.contains(object.id) ? full : dim
                for i in object.pixelIndices where i >= 0 && i < count {
                    out[i * 4] = rgb.r; out[i * 4 + 1] = rgb.g; out[i * 4 + 2] = rgb.b; out[i * 4 + 3] = 255
                }
            }
        }
        return RGBAImage(width: objects.width, height: objects.height, rgba: out)
    }

    // MARK: - CSV

    /// The object table as CSV. Comment lines (`# key: value`) carry the
    /// provenance, the counting rules and the per-class summaries; then one
    /// header line and one line per object. Physical columns are empty
    /// without a real-space scale — never filled in pixels under a
    /// physical name.
    package func csv() -> String {
        let unit = pixelUnit ?? "unit"
        var lines: [String] = []
        for pair in provenance where pair.count == 2 {
            lines.append("# \(pair[0]): \(pair[1])")
        }
        lines.append("# scan: \(width) x \(height) positions, 8-connected objects per class")
        if let pixelSize, let pixelUnit {
            lines.append("# real-space pixel size: \(Self.number(pixelSize)) \(pixelUnit)")
        } else {
            lines.append("# real-space pixel size: none (physical columns empty, no density)")
        }
        lines.append("# minimum object size: \(minimumAreaPx) px (user setting; smaller objects are listed, not counted)")
        lines.append("# counting: objects touching the scan edge are listed, not counted")
        lines.append("# analysed area: \(analysedPixels) positions; \(analysedAreaRule)")
        for s in summaries {
            var parts = ["\(s.countedObjects) counted of \(s.totalObjects)",
                         "\(s.edgeExcluded) on edge", "\(s.belowMinimumExcluded) small"]
            if let fraction = s.areaFraction { parts.append("area fraction \(Self.number(fraction))") }
            if let median = s.medianLengthPx {
                parts.append(pixelSize.map { "median length \(Self.number(median * $0)) \(unit)" }
                             ?? "median length \(Self.number(median)) px")
            }
            if let areal = s.arealDensity { parts.append("density \(Self.number(areal)) per \(unit)^2") }
            lines.append("# class \(Self.csvField(s.phaseName)): " + parts.joined(separator: ", "))
        }
        lines.append([
            "id", "phase", "counted", "excluded_because", "area_px", "length_px", "width_px",
            "aspect_ratio", "orientation_deg", "centroid_x_px", "centroid_y_px",
            "area_\(unit)2", "length_\(unit)", "width_\(unit)",
        ].joined(separator: ","))
        for r in rows {
            lines.append([
                String(r.id), Self.csvField(r.phaseName), r.isCounted ? "1" : "0",
                r.exclusion ?? "", String(r.areaPx), Self.number(r.lengthPx), Self.number(r.widthPx),
                Self.number(r.aspectRatio), Self.number(r.orientationDegrees),
                Self.number(r.centroidX), Self.number(r.centroidY),
                r.area.map(Self.number) ?? "", r.length.map(Self.number) ?? "",
                r.width.map(Self.number) ?? "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Up to six significant digits, locale-independent, no exponent for
    /// ordinary magnitudes.
    package nonisolated static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private nonisolated static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
