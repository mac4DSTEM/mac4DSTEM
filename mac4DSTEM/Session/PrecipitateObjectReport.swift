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
//    (`../_archive/mac4DSTEM/docs/cloud/2026-09-23/T2-direction-check.md`). Objects under it stay
//    in the rows, flagged, and are left out of the counted statistics.
//  - **The calibration is read at report time**, not at segmentation time,
//    so a density can never be stale against the scan scale the reader
//    now has.
//
//  Statistics are ImagoKit's (`ObjectStatistics.arealDensity`): objects touching
//  the scan edge are never counted, and density refuses without a positive
//  real-space pixel size. The needle length is the Feret diameter (task 39).
//
//  Session, not Core: like `PhaseMapObjectsBridge` it composes a Core result
//  with phase names, the session's calibration and a user setting.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DiffractoOrientation
import ImagoCore
#endif

package nonisolated struct PrecipitateObjectReport: Sendable, Codable, Hashable {

    package nonisolated struct Row: Sendable, Codable, Hashable, Identifiable {
        package let id: Int
        package let label: Int32
        package let phaseName: String
        package let areaPx: Int
        /// The needle length: the Feret diameter (largest caliper), in pixels.
        package let lengthPx: Double
        /// The extent across the principal axis, in pixels.
        package let widthPx: Double
        /// Beside the Feret length: 4·√λ1 of the inertia tensor (`axis_major_length`), the perimeter, the equivalent circle's diameter and
        /// the solidity, from ImagoKit 0.7.0. Nil in a report decoded from before they existed.
        package let axisMajorLengthPx: Double?
        package let perimeterPx: Double?
        package let equivalentDiameterPx: Double?
        package let solidity: Double?
        /// Mean composition under the object from the quantified maps (suite task 42): per element, the EDX pixels averaged and
        /// those the maps could not give a value for. Nil without the join; `compositionNote` says why an object has none.
        package let composition: [ObjectComposition]?
        package let compositionPixels: Int?
        package let compositionExcluded: Int?
        package let compositionNote: String?
        /// Mean strain under the object (rows and columns) and its spread, or `strainNote`.
        package let strain: ObjectStrain?
        package let strainNote: String?
        /// The object's orientation-relationship variant (suite task 40) or why it has none; nil for an object of another phase, or without
        /// the variant run. A report decoded from before it existed has none.
        package let variant: VariantAssignment?
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
        package let axisMajorLength: Double?
        package let perimeter: Double?
        package let equivalentDiameter: Double?

        /// Sort keys for the table's optional columns (a report decoded from before these existed sorts them first).
        package var axisMajorSortKey: Double { axisMajorLengthPx ?? -1 }
        package var perimeterSortKey: Double { perimeterPx ?? -1 }
        package var equivalentDiameterSortKey: Double { equivalentDiameterPx ?? -1 }
        package var soliditySortKey: Double { solidity ?? -1 }

        /// The table's Direction and Variant cells ("" when the object has none; the reason is the row's help).
        package var directionText: String { variant?.directionName ?? variant?.direction.map { VariantGroup.directionName($0) } ?? "" }
        package var variantText: String { variant?.variant.map(String.init) ?? "" }
        package var directionSortKey: Int { variant?.direction ?? -1 }
        package var variantSortKey: Int { variant?.variant ?? 0 }
        package var variantNote: String? {
            guard let variant else { return nil }
            switch variant.status {
            case .assigned: return nil
            case .ambiguous(let why): return "Unassigned: \(why)"
            case .noOrientation: return "Unassigned: no pixel has an orientation"
            }
        }

        /// The table's one-cell texts for the joins (suite task 42): the object's own mean, or the reason it has none ("" without the join).
        package var compositionSummary: String {
            guard let composition else { return compositionNote ?? "" }
            let parts = composition.compactMap { e in e.atomicPercent.map { "\(e.symbol) " + Self.fixed($0, 1) } }
            return parts.joined(separator: " · ") + " at%" + ((compositionExcluded ?? 0) > 0 ? " (\(compositionPixels ?? 0) px, \(compositionExcluded ?? 0) failed or masked)" : "")
        }
        package var strainSummary: String {
            guard let strain else { return strainNote ?? "" }
            let pct = { (v: Double) in Self.fixed(v * 100, 2) }
            return "rr \(pct(strain.rr)) · cc \(pct(strain.cc)) · rc \(pct(strain.rc)) %, \(Self.fixed(strain.rotationDegrees, 2))°"
        }
        private static func fixed(_ v: Double, _ digits: Int) -> String { v.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "en_US_POSIX"))) }

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

    /// Counted and total objects of one variant group: a needle direction (the matrix cube axis the needle lies along), one of the twelve
    /// variants, or the unassigned ones. Counted = not on the scan edge, not under the minimum size; the density is the kit's (`ObjectStatistics.arealDensity`).
    package nonisolated struct VariantGroup: Sendable, Codable, Hashable, Identifiable {
        package enum Kind: String, Sendable, Codable { case direction, variant, unassigned }
        package let kind: Kind
        /// Direction 0...2 (0...3 for T1; an index into the preset's family names), variant 1...12, 0 for the unassigned.
        package let index: Int
        package let totalObjects: Int
        package let countedObjects: Int
        package let arealDensity: Double?
        /// For the unassigned: "ambiguous 2, no orientation 1".
        package let detail: String?
        /// A direction group's name from the preset ("[111]"); nil elsewhere and in a snapshot from before the presets (the cube axes then).
        package var name: String? = nil
        package init(kind: Kind, index: Int, totalObjects: Int, countedObjects: Int, arealDensity: Double?, detail: String?, name: String? = nil) {
            self.kind = kind; self.index = index; self.totalObjects = totalObjects; self.countedObjects = countedObjects
            self.arealDensity = arealDensity; self.detail = detail; self.name = name
        }
        package var id: String { "\(kind.rawValue)-\(index)" }
        package static func directionName(_ i: Int) -> String { ["[100]", "[010]", "[001]"].indices.contains(i) ? ["[100]", "[010]", "[001]"][i] : "[?]" }
        package var title: String {
            switch kind {
            case .direction: name ?? Self.directionName(index)
            case .variant: "Variant \(index)"
            case .unassigned: "Unassigned"
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
        /// Scan pixels; the physical versions multiply by `pixelSize`. The lengths are the counted objects' Feret diameters.
        package let medianLengthPx: Double?
        package let meanLengthPx: Double?
        package let meanWidthPx: Double?
        /// Counted objects, each edge-weighted (Miles–Lantuéjoul,
        /// `ObjectStatistics.arealDensity`), per unit² of analysed area; nil without a scale.
        package let arealDensity: Double?
        /// N_V = areal density / thickness per µm³ and its σ from the thickness's σ (ImagoKit's `numberDensity`); nil without a scale, a
        /// thickness, or a unit the app can convert to nm.
        package let nVolumePerUm3: Double?
        package let nVolumeSigmaPerUm3: Double?
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
    /// The classification result this table was built from
    /// (`PrecipitateClassificationProduct.sourceID`), so a table selection is
    /// only ever drawn on the map of the run it came from. Nil for a report
    /// with no such source (or decoded from before the field existed).
    package let sourceID: UUID?
    /// The typed thickness behind N_V (nm) and the kit's validation word for it ("none"); nil without a usable thickness.
    package let thicknessNm: Double?
    package let thicknessSigmaNm: Double?
    package let numberDensityValidation: String?
    /// The elements of the composition columns, in the maps' order; empty without the join. When a join could not run, why.
    package let compositionElements: [String]
    package let compositionUnavailable: String?
    package let strainAvailable: Bool
    package let strainUnavailable: String?
    /// The variant run (suite task 40): the groups (three directions, twelve variants, the unassigned) and the settings in words; nil without
    /// the run. `variantUnavailable` says why a run that was asked for could not be made. Both nil in a report decoded from before.
    package var variantGroups: [VariantGroup]? = nil
    package var variantSummary: String? = nil
    package var variantUnavailable: String? = nil
    /// The direction the beam runs along in the matrix (0...2) when it is a cube axis: that direction's needles are seen end-on.
    package var endOnDirection: Int? = nil
    /// Needle or plate (the preset's habit); nil in a snapshot from before the plate presets, which read as needles.
    package var variantHabit: OrientationRelationshipPreset.Habit? = nil
    /// Each variant's direction in the kit's order (12 values): what ranks a variant among the four of its direction for the colours.
    package var variantDirections: [Int]? = nil

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
        provenance: [(String, String)] = [],
        sourceID: UUID? = nil,
        thicknessNm: Double? = nil,
        thicknessSigmaNm: Double? = nil,
        compositionJoin: ObjectJoinResult<ObjectCompositionValue>? = nil,
        strainJoin: ObjectJoinResult<ObjectStrain>? = nil,
        variantJoin: ObjectJoinResult<VariantAssignment>? = nil,
        variantSettings: VariantSettings? = nil,
        endOnDirection: Int? = nil,
        variantDirections: [Int]? = nil
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
            let density = PrecipitateSegmentation.density(
                objects: classObjects.objects, accepted: accepted,
                analysedPixels: objects.analysedPixels,
                width: objects.width, height: objects.height,
                pixelSize: scale, pixelUnit: scale == nil ? nil : pixelUnit)
            let belowMinimum = classObjects.objects.filter { $0.area < minimum }
            let nv = Self.numberDensity(arealDensity: density.arealDensity, pixelUnit: scale == nil ? nil : pixelUnit,
                                        thicknessNm: thicknessNm, thicknessSigmaNm: thicknessSigmaNm)
            let feret = Self.feretSummary(classObjects.objects, minimumArea: minimum)
            summaries.append(ClassSummary(
                label: classObjects.label, phaseName: phaseName,
                totalObjects: classObjects.objects.count,
                countedObjects: density.counted,
                edgeExcluded: density.edgeExcluded,
                belowMinimumExcluded: belowMinimum.count,
                areaFraction: classObjects.areaFraction,
                medianLengthPx: feret.median,
                meanLengthPx: feret.mean,
                meanWidthPx: density.meanWidth,
                arealDensity: density.arealDensity,
                nVolumePerUm3: nv?.value, nVolumeSigmaPerUm3: nv?.sigma))
            for object in classObjects.objects {
                let length = Double(object.lengthPx), width = Double(object.widthPx)
                rows.append(Row(
                    id: object.id, label: classObjects.label, phaseName: phaseName,
                    areaPx: object.area, lengthPx: length, widthPx: width,
                    axisMajorLengthPx: object.axisMajorLengthPx, perimeterPx: object.perimeterPx,
                    equivalentDiameterPx: object.equivalentDiameterPx, solidity: object.solidity,
                    composition: compositionJoin?.perObject[object.id]?.elements,
                    compositionPixels: compositionJoin?.perObject[object.id]?.pixels,
                    compositionExcluded: compositionJoin?.perObject[object.id]?.excluded,
                    compositionNote: compositionJoin?.reasons[object.id],
                    strain: strainJoin?.perObject[object.id], strainNote: strainJoin?.reasons[object.id],
                    variant: variantJoin?.perObject[object.id],
                    orientationDegrees: Double(object.orientationDegrees),
                    centroidX: Double(object.centroidX), centroidY: Double(object.centroidY),
                    touchesEdge: object.touchesEdge, belowMinimum: object.area < minimum,
                    area: scale.map { Double(object.area) * $0 * $0 },
                    length: scale.map { length * $0 },
                    width: scale.map { width * $0 },
                    axisMajorLength: scale.map { object.axisMajorLengthPx * $0 },
                    perimeter: scale.map { object.perimeterPx * $0 },
                    equivalentDiameter: scale.map { object.equivalentDiameterPx * $0 }))
            }
        }
        rows.sort { $0.id < $1.id }
        var report = PrecipitateObjectReport(
            width: objects.width, height: objects.height,
            matrixPhaseIndex: matrixPhaseIndex,
            pixelSize: scale, pixelUnit: scale == nil ? nil : pixelUnit,
            minimumAreaPx: minimum,
            analysedPixels: objects.analysedPixels,
            notIndexedPixels: objects.notIndexedPixels,
            analysedAreaRule: objects.analysedAreaRule,
            rows: rows, summaries: summaries,
            provenance: provenance.map { [$0.0, $0.1] },
            sourceID: sourceID,
            thicknessNm: summaries.contains { $0.nVolumePerUm3 != nil } ? thicknessNm : nil,
            thicknessSigmaNm: summaries.contains { $0.nVolumePerUm3 != nil } ? thicknessSigmaNm : nil,
            numberDensityValidation: summaries.contains { $0.nVolumePerUm3 != nil }
                ? (try? ObjectStatistics.numberDensity(arealDensity: 0, thickness: 1))?.validation : nil,
            compositionElements: compositionJoin?.perObject.values.first?.elements.map(\.symbol) ?? [],
            compositionUnavailable: compositionJoin?.unavailable,
            strainAvailable: (strainJoin?.perObject.isEmpty == false),
            strainUnavailable: strainJoin?.unavailable)
        if let variantJoin {
            if let why = variantJoin.unavailable {
                report.variantUnavailable = why
            } else {
                let preset = variantSettings?.orientationRelationship ?? .betaDoublePrimeInAl
                report.variantGroups = Self.variantGroups(objects: objects, rows: rows, minimum: minimum, scale: scale, pixelUnit: pixelUnit,
                                                          familyNames: preset.familyNames, variantCount: variantDirections?.count ?? 12)
                report.variantHabit = preset.habit
                report.variantSummary = variantSettings.map { Self.variantSummary($0) }
                report.endOnDirection = endOnDirection
                report.variantDirections = variantDirections
            }
        }
        return report
    }

    /// The settings in words, for the CSV and the section's help: "beta'' in Al, Andersen 1998; tolerance 1 degree (half the library step) ...".
    package nonisolated static func variantSummary(_ s: VariantSettings) -> String {
        let tolerance = s.toleranceDegrees.map { number($0) + " degrees" } ?? "half the library's in-plane step"
        return "\(s.orientationRelationship.title); a pixel votes within \(tolerance); assigned at an agreement of at least \(number(s.agreementMinimum)) of the object's pixels"
    }

    /// The three needle directions, the twelve variants and the unassigned, over the objects the variant run covered.
    private nonisolated static func variantGroups(objects: PrecipitateSegmentation.ClassMapObjects, rows: [Row], minimum: Int, scale: Double?, pixelUnit: String?,
                                                    familyNames: [String], variantCount: Int) -> [VariantGroup] {
        let covered = rows.filter { $0.variant != nil }
        let allObjects = objects.classes.flatMap(\.objects)
        func group(_ kind: VariantGroup.Kind, _ index: Int, _ members: [Row], detail: String? = nil, name: String? = nil) -> VariantGroup {
            let ids = Set(members.map(\.id))
            let subset = allObjects.filter { ids.contains($0.id) }
            let accepted = Set(members.filter(\.isCounted).map(\.id))
            let density = PrecipitateSegmentation.density(
                objects: subset, accepted: accepted, analysedPixels: objects.analysedPixels, width: objects.width, height: objects.height,
                pixelSize: scale, pixelUnit: scale == nil ? nil : pixelUnit)
            return VariantGroup(kind: kind, index: index, totalObjects: members.count, countedObjects: accepted.count,
                                arealDensity: members.isEmpty ? nil : density.arealDensity, detail: detail, name: name)
        }
        var out: [VariantGroup] = []
        for d in familyNames.indices { out.append(group(.direction, d, covered.filter { $0.variant?.direction == d }, name: familyNames[d])) }
        for v in 1...max(variantCount, 1) { out.append(group(.variant, v, covered.filter { $0.variant?.variant == v })) }
        let unassigned = covered.filter { !($0.variant?.isAssigned ?? false) }
        let ambiguous = unassigned.filter { if case .ambiguous? = $0.variant?.status { true } else { false } }.count
        let none = unassigned.count - ambiguous
        out.append(group(.unassigned, 0, unassigned, detail: unassigned.isEmpty ? nil : "ambiguous \(ambiguous), no orientation \(none)"))
        return out
    }

    /// N_V per µm³ from a class's areal density (per pixel-unit²) and the typed thickness (nm): ImagoKit's `numberDensity` on the density
    /// converted to nm⁻². Nil unless every input is there and the pixel unit converts to nm. The kit refuses a thickness that is not
    /// positive and finite; so does this (nil).
    package nonisolated static func numberDensity(arealDensity: Double?, pixelUnit: String?, thicknessNm: Double?, thicknessSigmaNm: Double?)
        -> (value: Double, sigma: Double?)? {
        guard let arealDensity, let pixelUnit, let thicknessNm,
              let angstrom = CalibrationUnitConversion.realAngstromPerPixel(value: 1, units: pixelUnit) else { return nil }
        let nmPerUnit = angstrom * 0.1
        let perNm2 = arealDensity / (nmPerUnit * nmPerUnit)
        guard let nv = try? ObjectStatistics.numberDensity(arealDensity: perNm2, thickness: thicknessNm, thicknessSigma: thicknessSigmaNm)
        else { return nil }
        return (nv.value * 1e9, nv.sigma.map { $0 * 1e9 })   // per nm³ to per µm³
    }

    /// The median and mean of the counted objects' Feret lengths: the kit's `ObjectStatistics.feretSummary` (ImagoKit 0.8.0) over the objects'
    /// regions; objects without one (built by hand) fall back to their stored `lengthPx`, summed the same way.
    package nonisolated static func feretSummary(_ objects: [PrecipitateSegmentation.Object], minimumArea: Int) -> (median: Double?, mean: Double?) {
        let regions = objects.compactMap(\.region)
        if regions.count == objects.count {
            let s = ObjectStatistics.feretSummary(regions, minimumArea: minimumArea)
            return (s.medianFeret, s.meanFeret)
        }
        let counted = objects.filter { $0.area >= minimumArea && !$0.touchesEdge }
        guard !counted.isEmpty else { return (nil, nil) }
        let lengths = counted.map { Double($0.lengthPx) }.sorted()
        let median = lengths.count % 2 == 1 ? lengths[lengths.count / 2]
            : (lengths[lengths.count / 2 - 1] + lengths[lengths.count / 2]) / 2
        return (median, lengths.reduce(0, +) / Double(lengths.count))
    }

    // MARK: - Objects image

    /// The objects drawn over the scan: counted objects in their phase's map
    /// colour, objects left out of the statistics (scan edge, under the
    /// minimum size) at 35 % of that colour over the matrix grey, the matrix
    /// and unselected classes in the matrix grey (a matrix position the
    /// matrix won by challenge striped as on the phase map), not-indexed
    /// positions in the phase map's own two-grey hatch, no-data positions
    /// transparent.
    /// The picture shows exactly what the numbers count.
    package nonisolated static func image(
        objects: PrecipitateSegmentation.ClassMapObjects,
        report: PrecipitateObjectReport,
        results: [PhaseVectorResult],
        matrixPhaseIndex: Int
    ) -> RGBAImage {
        let count = objects.width * objects.height
        var out = [UInt8](repeating: 0, count: max(0, count * 4))
        for i in 0..<count {
            var rgb = PhaseMapPresentation.matrixColor
            var alpha: UInt8 = 255
            if results.indices.contains(i) {
                let x = i % objects.width, y = i / objects.width
                switch results[i].verdict {
                case .notIndexed:
                    rgb = PhaseMapPresentation.notIndexedPixelColor(x: x, y: y)
                case .noData:
                    alpha = 0
                case .matrix:
                    // The phase map's own rule: a matrix position the matrix won by
                    // challenge keeps the stripe it has there (S12).
                    rgb = PhaseMapPresentation.matrixPixelColor(results[i], x: x, y: y)
                case .indexed:
                    break
                }
            }
            out[i * 4] = rgb.r; out[i * 4 + 1] = rgb.g; out[i * 4 + 2] = rgb.b; out[i * 4 + 3] = alpha
        }
        let matrix = PhaseMapPresentation.matrixColor
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
        lines.append("# length: the Feret diameter (the largest caliper distance, scikit-image feret_diameter_max); axis_major_length is 4*sqrt(largest inertia eigenvalue), width the extent across the principal axis")
        lines.append("# density: each counted object weighted by W*H / ((W - bx - 1)(H - by - 1)) for its bounding box (Miles-Lantuejoul edge correction), over the analysed area")
        if let t = thicknessNm {
            lines.append("# N_V: areal density / thickness (\(Self.number(t)) nm" + (thicknessSigmaNm.map { " +/- \(Self.number($0))" } ?? "")
                + "), assuming the objects span the foil; validation: \(numberDensityValidation ?? "none")")
        }
        if !compositionElements.isEmpty {
            lines.append("# composition: the mean of the per-pixel at% and wt% maps over the object's EDX pixels (no sigma; not the pooled fit); objects under the minimum EDX pixels have none; validation: none")
        } else if let why = compositionUnavailable { lines.append("# composition: not available: \(why)") }
        if strainAvailable {
            lines.append("# strain: the mean of the strain map over the object's scan positions, in rows (rr) and columns (cc), rotation in degrees; *_sigma is the spread across the pixels, not a fit error")
        } else if let why = strainUnavailable { lines.append("# strain: not available: \(why)") }
        if let summary = variantSummary, variantGroups != nil {
            lines.append("# variants: \(summary); source: the phase map's winning library entry per position; \(variantHabit == .plate ? "plate normals are matrix directions" : "needle directions are the matrix cube axes"); validation: none")
            if let end = endOnDirection {
                let name = variantGroups?.first { $0.kind == .direction && $0.index == end }?.title ?? VariantGroup.directionName(end)
                lines.append(variantHabit == .plate ? "# face-on: plates on \(name) lie face-on to the beam" : "# end-on: needles along \(name) lie along the beam")
            }
        } else if let why = variantUnavailable { lines.append("# variants: not available: \(why)") }
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
            if let nv = s.nVolumePerUm3 {
                parts.append("N_V \(Self.number(nv))" + (s.nVolumeSigmaPerUm3.map { " +/- \(Self.number($0))" } ?? "") + " per um^3")
            }
            lines.append("# class \(Self.csvField(s.phaseName)): " + parts.joined(separator: ", "))
        }
        for g in variantGroups ?? [] where g.kind != .variant || g.totalObjects > 0 {
            var parts = ["\(g.countedObjects) counted of \(g.totalObjects)"]
            if let areal = g.arealDensity { parts.append("density \(Self.number(areal)) per \(unit)^2") }
            if let detail = g.detail { parts.append(detail) }
            lines.append("# \(g.kind.rawValue) \(g.kind == .direction ? g.title : String(g.index)): " + parts.joined(separator: ", "))
        }
        lines.append(columnNames.joined(separator: ","))
        for r in rows {
            var f = fields(of: r)
            f[1] = Self.csvField(f[1])
            lines.append(f.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The table's columns, as the CSV header names them. Physical ones carry the real-space unit.
    private var columnNames: [String] {
        let unit = pixelUnit ?? "unit"
        var names: [String] = ["id", "phase", "counted", "excluded_because", "area_px", "length_px", "width_px",
                               "aspect_ratio", "orientation_deg", "centroid_x_px", "centroid_y_px",
                               "area_\(unit)2", "length_\(unit)", "width_\(unit)"]
        names += ["axis_major_length_px", "perimeter_px", "equivalent_diameter_px", "solidity"]
        names += ["axis_major_length_\(unit)", "perimeter_\(unit)", "equivalent_diameter_\(unit)"]
        if !compositionElements.isEmpty {
            names.append("composition_px")
            for symbol in compositionElements { names.append(Self.csvName(symbol) + "_at_pct"); names.append(Self.csvName(symbol) + "_wt_pct") }
        }
        if variantGroups != nil { names += ["variant", "direction", "variant_status", "variant_agreement", "variant_angle_deg"] }
        if strainAvailable {
            names += ["strain_px", "strain_rr", "strain_cc", "strain_rc", "rotation_deg", "strain_rr_sigma", "strain_cc_sigma", "strain_rc_sigma"]
        }
        return names
    }

    /// One row's values in `columnNames` order, unquoted, in the CSV's locale-independent number format.
    /// The CSV and Copy both read it, so what is copied is what the file would hold.
    private func fields(of r: Row) -> [String] {
        func n(_ v: Double?) -> String { v.map(Self.number) ?? "" }
        var f: [String] = [String(r.id), r.phaseName, r.isCounted ? "1" : "0", r.exclusion ?? "", String(r.areaPx),
                           Self.number(r.lengthPx), Self.number(r.widthPx), Self.number(r.aspectRatio),
                           Self.number(r.orientationDegrees), Self.number(r.centroidX), Self.number(r.centroidY)]
        f += [n(r.area), n(r.length), n(r.width)]
        f += [n(r.axisMajorLengthPx), n(r.perimeterPx), n(r.equivalentDiameterPx), n(r.solidity)]
        f += [n(r.axisMajorLength), n(r.perimeter), n(r.equivalentDiameter)]
        if !compositionElements.isEmpty {
            f.append(r.compositionPixels.map(String.init) ?? "")
            for symbol in compositionElements {
                let e = r.composition?.first { $0.symbol == symbol }
                f.append(n(e?.atomicPercent)); f.append(n(e?.weightPercent))
            }
        }
        if variantGroups != nil {
            let v = r.variant
            let status: String = {
                switch v?.status {
                case .assigned?: "assigned"
                case .ambiguous(let why)?: "ambiguous: " + why
                case .noOrientation?: "no orientation"
                case nil: ""
                }
            }()
            f += [r.variantText, r.directionText, Self.csvField(status), v.map { Self.number($0.agreement) } ?? "", n(v?.angleDegrees)]
        }
        if strainAvailable {
            let s = r.strain
            f.append(s.map { String($0.pixels) } ?? "")
            f += [n(s?.rr), n(s?.cc), n(s?.rc), n(s?.rotationDegrees), n(s?.sigmaRR), n(s?.sigmaCC), n(s?.sigmaRC)]
        }
        return f
    }

    /// `rows` as tab-separated text under the CSV's header line, for the clipboard (Edit > Copy in the object
    /// table): a paste into a spreadsheet lands in columns. Same columns and number format as the CSV; no
    /// provenance comments, a phase name's tabs and line breaks become spaces.
    package func tabSeparatedText(of rows: [Row]) -> String {
        let clean: (String) -> String = {
            $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        var lines = [columnNames.joined(separator: "\t")]
        for r in rows { lines.append(fields(of: r).map(clean).joined(separator: "\t")) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The rows the table shows: one phase (or all, `nil`), counted ones only when asked, in the table's sort
    /// order. Computed on a change of filter or sort, not on every redraw.
    package func visibleRows(phase label: Int32?, countedOnly: Bool,
                             sortedUsing order: [KeyPathComparator<Row>]) -> [Row] {
        rows
            .filter { label == nil || $0.label == label }
            .filter { !countedOnly || $0.isCounted }
            .sorted(using: order)
    }

    /// The Save panel's suggestion: "<dataset>-precipitate-objects.csv" from the report's `source_file`
    /// provenance, "precipitate-objects.csv" when the report does not name one.
    package var csvFileName: String {
        guard let file = provenance.first(where: { $0.count == 2 && $0[0] == "source_file" })?[1],
              case let base = (file as NSString).deletingPathExtension
                  .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"),
              !base.isEmpty else { return "precipitate-objects.csv" }
        return "\(base)-precipitate-objects.csv"
    }

    /// Up to six significant digits, locale-independent, no exponent for
    /// ordinary magnitudes.
    package nonisolated static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// An element symbol as a column stem ("Mg" gives "mg").
    private nonisolated static func csvName(_ symbol: String) -> String { symbol.lowercased() }

    private nonisolated static func csvField(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Which scan pixels a table selection stands for, and the outline that
/// marks them on the map. Pure: the map view only strokes the segments. It is
/// an overlay, never a published product, so a highlight cannot reach Save
/// Result, the sidecar or a comparison.
package nonisolated enum PrecipitateHighlight {

    /// A unit edge on the scan grid: (x0, y0)–(x1, y1) in pixel corners, so
    /// pixel (x, y) spans x…x+1, y…y+1.
    package nonisolated struct Edge: Sendable, Hashable {
        package let x0: Int, y0: Int, x1: Int, y1: Int
        // Explicit so the initializer is `package` (synthesized ones are internal).
        package init(x0: Int, y0: Int, x1: Int, y1: Int) {
            self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        }
    }

    /// Scan-grid indices (y * width + x) of the objects with these ids.
    package nonisolated static func pixels(
        objects: PrecipitateSegmentation.ClassMapObjects, ids: Set<Int>
    ) -> Set<Int> {
        let count = objects.width * objects.height
        var out = Set<Int>()
        for classObjects in objects.classes {
            for object in classObjects.objects where ids.contains(object.id) {
                for i in object.pixelIndices where i >= 0 && i < count { out.insert(i) }
            }
        }
        return out
    }

    /// The boundary of those pixels: every pixel side that faces a pixel
    /// outside the selection or the scan edge.
    package nonisolated static func outline(
        objects: PrecipitateSegmentation.ClassMapObjects, ids: Set<Int>
    ) -> [Edge] {
        let w = objects.width
        let set = pixels(objects: objects, ids: ids)
        var edges: [Edge] = []
        for i in set {
            let x = i % w, y = i / w
            if x == 0 || !set.contains(i - 1) { edges.append(Edge(x0: x, y0: y, x1: x, y1: y + 1)) }
            if x == w - 1 || !set.contains(i + 1) { edges.append(Edge(x0: x + 1, y0: y, x1: x + 1, y1: y + 1)) }
            if !set.contains(i - w) { edges.append(Edge(x0: x, y0: y, x1: x + 1, y1: y)) }
            if !set.contains(i + w) { edges.append(Edge(x0: x, y0: y + 1, x1: x + 1, y1: y + 1)) }
        }
        return edges
    }
}
