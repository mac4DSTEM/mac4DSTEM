//
//  PrecipitateGlyphSet.swift
//  Role: the precipitate objects as ellipse glyphs for the scan-grid panes (design rooms-2026-10-21 §3): one ellipse per object
//        from the object table's own rows (centroid, end-to-end length and width, orientation), no contour tracing. A snapshot
//        value: Equatable, built once per classification run and minimum size, drawn by every pane through its own transform.
//        Nothing here is a measurement beyond what the table already reports; the method rides with the table.
//

import Foundation
import DSTEMCore
import DSTEMSession

/// The overlay's switches (the Precipitates section): all off by default; the glyphs are drawn only when `onPanes`.
nonisolated struct PrecipitateOverlaySettings: Equatable, Sendable {
    var onPanes = false
    /// Edge and under-minimum objects are left out (they stay in the table).
    var countedOnly = true
    var labels = false
    /// Phase colour (today's), the needle direction, or the variant (task 40); the last two need the variant run.
    var colourBy = PrecipitateColourBy.phase
    init(onPanes: Bool = false, countedOnly: Bool = true, labels: Bool = false, colourBy: PrecipitateColourBy = .phase) {
        self.onPanes = onPanes; self.countedOnly = countedOnly; self.labels = labels; self.colourBy = colourBy
    }
}

nonisolated struct PrecipitateGlyph: Sendable, Equatable, Identifiable {
    let id: Int
    let phaseLabel: Int32
    let phaseName: String
    /// Centre in scan pixels (the table's centroid, image frame: x right, y down).
    let centreX: Double
    let centreY: Double
    /// Half the end-to-end length and width, scan pixels.
    let semiMajor: Double
    let semiMinor: Double
    /// Degrees from +x, positive clockwise on screen (the table's convention).
    let angleDegrees: Double
    let counted: Bool
    /// "#12 β″ 23 nm" (or px without a scale): the hover readout.
    let readout: String
    /// The variant run's verdict (task 40): the needle direction 0...2 and the variant 1...12, nil for an object that has none.
    var direction: Int? = nil
    var variant: Int? = nil
}

nonisolated struct PrecipitateGlyphSet: Sendable, Equatable {
    let width: Int
    let height: Int
    let sourceID: UUID?
    let glyphs: [PrecipitateGlyph]
    /// Each variant's direction in the kit's order (empty without the variant run): the rank of a variant among its direction's four.
    var variantDirections: [Int] = []

    init(width: Int, height: Int, sourceID: UUID?, glyphs: [PrecipitateGlyph], variantDirections: [Int] = []) {
        self.width = width; self.height = height; self.sourceID = sourceID; self.glyphs = glyphs; self.variantDirections = variantDirections
    }

    static func make(_ report: PrecipitateObjectReport) -> PrecipitateGlyphSet {
        let glyphs = report.rows.map { r -> PrecipitateGlyph in
            let size: String
            if let length = r.length, let unit = report.pixelUnit { size = PrecipitateFormat.number(length) + " " + unit }
            else { size = PrecipitateFormat.number(r.lengthPx) + " px" }
            return PrecipitateGlyph(
                id: r.id, phaseLabel: r.label, phaseName: r.phaseName, centreX: r.centroidX, centreY: r.centroidY,
                semiMajor: r.lengthPx / 2, semiMinor: r.widthPx / 2, angleDegrees: r.orientationDegrees,
                counted: r.isCounted,
                readout: "#\(r.id) \(r.phaseName)" + (r.variant?.isAssigned == true ? " \(r.directionText) v\(r.variantText)" : "") + " \(size)",
                direction: r.variant?.direction, variant: r.variant?.variant)
        }
        return PrecipitateGlyphSet(width: report.width, height: report.height, sourceID: report.sourceID, glyphs: glyphs,
                                   variantDirections: report.variantDirections ?? [])
    }

    func shown(_ settings: PrecipitateOverlaySettings) -> [PrecipitateGlyph] {
        settings.countedOnly ? glyphs.filter(\.counted) : glyphs
    }

    /// The glyph under a scan-pixel position (the nearest centre among those whose ellipse contains it), for the hover readout.
    func hit(x: Double, y: Double, settings: PrecipitateOverlaySettings) -> PrecipitateGlyph? {
        shown(settings).filter { g in
            let a = max(g.semiMajor, 0.5), b = max(g.semiMinor, 0.5)
            let t = g.angleDegrees * .pi / 180
            let dx = x - g.centreX, dy = y - g.centreY
            let u = dx * cos(t) + dy * sin(t), v = -dx * sin(t) + dy * cos(t)
            return (u / a) * (u / a) + (v / b) * (v / b) <= 1
        }.min { hypot($0.centreX - x, $0.centreY - y) < hypot($1.centreX - x, $1.centreY - y) }
    }
}

/// Where a glyph lands in a pane: the one transform every pane applies (the pane's size over the scan grid), so the same object is
/// at the same fraction of the picture on a virtual image, the phase map and an EDX map on the same scan.
nonisolated enum PrecipitateGlyphGeometry {
    struct Placed: Equatable {
        var centre: CGPoint
        var semiMajor: CGFloat
        var semiMinor: CGFloat
        var angleDegrees: Double
    }

    static func place(_ g: PrecipitateGlyph, gridWidth: Int, gridHeight: Int, paneSize: CGSize) -> Placed {
        let sx = paneSize.width / CGFloat(max(gridWidth, 1)), sy = paneSize.height / CGFloat(max(gridHeight, 1))
        return Placed(centre: CGPoint(x: (g.centreX + 0.5) * sx, y: (g.centreY + 0.5) * sy),
                      semiMajor: CGFloat(g.semiMajor) * sx, semiMinor: CGFloat(g.semiMinor) * sy, angleDegrees: g.angleDegrees)
    }
}
