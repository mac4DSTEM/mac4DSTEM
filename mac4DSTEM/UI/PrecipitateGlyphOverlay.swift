//
//  PrecipitateGlyphOverlay.swift
//  Role: draws a `PrecipitateGlyphSet` over a scan-grid pane in one Canvas through the pane's own size (the same transform as the
//        marks): counted objects in their phase colour, edge and small ones dimmed, the table-selected ones in a bright outline,
//        labels when asked. It reads only values (the set, the switches, the selection), so a pane redraws on zoom or a switch and
//        not on anything else.
//

import SwiftUI
import DSTEMCore
import DSTEMSession

struct PrecipitateGlyphOverlay: View {
    let set: PrecipitateGlyphSet
    let settings: PrecipitateOverlaySettings
    let selected: Set<Int>
    /// The object under the pointer (readout drawn beside it); nil: none.
    var hover: Int? = nil
    let colour: @Sendable (Int32) -> Color
    let zoom: CGFloat

    /// The glyph's stroke colour for the chosen scheme: the phase's, or the direction's / variant's hue (grey when the object has none).
    private func glyphColour(_ g: PrecipitateGlyph) -> Color {
        guard let c = VariantPalette.rgb(scheme: settings.colourBy, direction: g.direction, variant: g.variant, directions: set.variantDirections)
        else { return colour(g.phaseLabel) }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var body: some View {
        Canvas { context, size in
            for g in set.shown(settings) {
                let p = PrecipitateGlyphGeometry.place(g, gridWidth: set.width, gridHeight: set.height, paneSize: size)
                // Never smaller than a visible dot: a one-pixel object is a speck at fit zoom.
                let a = max(p.semiMajor, 2 / zoom), b = max(p.semiMinor, 2 / zoom)
                var path = Path(ellipseIn: CGRect(x: -a, y: -b, width: 2 * a, height: 2 * b))
                path = path.applying(CGAffineTransform(rotationAngle: CGFloat(p.angleDegrees * .pi / 180))
                    .concatenating(CGAffineTransform(translationX: p.centre.x, y: p.centre.y)))
                let base = glyphColour(g).opacity(g.counted ? 1 : 0.35)
                let isSelected = selected.contains(g.id)
                if isSelected {
                    context.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: 4 / zoom)
                    context.stroke(path, with: .color(.white), lineWidth: 2 / zoom)
                } else {
                    context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2.5 / zoom)
                    context.stroke(path, with: .color(base), lineWidth: 1.25 / zoom)
                }
                if g.id == hover {
                    let text = Text(g.readout).font(.system(size: 11 / zoom).weight(.semibold)).foregroundStyle(.white)
                    context.draw(context.resolve(text), at: CGPoint(x: p.centre.x + a, y: p.centre.y + b), anchor: .topLeading)
                } else if settings.labels {
                    let text = Text("#\(g.id)").font(.system(size: 10 / zoom)).foregroundStyle(.white)
                    context.draw(context.resolve(text), at: CGPoint(x: p.centre.x + a, y: p.centre.y - b), anchor: .bottomLeading)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension PrecipitateGlyphOverlay {
    /// The class's colour on the phase map, as the object table's swatch has it.
    static func phaseColour(report: PrecipitateObjectReport?, label: Int32) -> Color {
        let c = report?.color(of: label) ?? PhaseMapPresentation.color(phaseIndex: Int(label), matrixPhaseIndex: -1)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }
}
