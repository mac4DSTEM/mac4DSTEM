//
//  FitOverlayViews.swift
//  Role: Draws fit-verification overlays on the diffraction pane — measured
//        peaks vs the model the app fitted (strain lattice, matched ACOM
//        template, calibrated origin/ellipse). Rendering only; the geometry
//        comes from FitOverlays (raw detector px) and is mapped to view
//        points with the same fitted-box math as the disk-peak overlay, so
//        marks stay pixel-accurate at any zoom.
//
//  Visual vocabulary (kept consistent across modes):
//    green circle  = measured Bragg peak (same as Disks mode)
//    orange cross  = model prediction (local lattice point / template spot)
//    orange arrow  = fitted local lattice vector
//    dashed white  = reference lattice vector
//    red           = calibration (origin marker, fitted ellipse)
//

import SwiftUI

struct PatternFitOverlayView: View {
    let strain: FitOverlays.StrainOverlay?
    let template: FitOverlays.TemplateOverlay?
    let originPoint: (x: Float, y: Float)?
    let ellipse: [FitOverlays.Marker]
    let measuredPeaks: [BraggPeak]
    let probeRadius: Float
    let patternWidth: Int
    let patternHeight: Int
    let box: CGSize

    private static let predictionColor = Color.orange
    private static let calibrationColor = Color.red
    private static let measuredColor = Color.green

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawEllipse(context)
                drawMeasuredPeaks(context)
                if let strain { drawStrain(strain, context) }
                if let template { drawTemplate(template, context) }
                if let originPoint {
                    drawOriginMarker(at: point(originPoint.x, originPoint.y),
                                     context)
                }
            }
            .frame(width: box.width, height: box.height)

            legend
                .padding(6)
        }
        .frame(width: box.width, height: box.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fit overlay")
        .accessibilityValue(legendText)
    }

    // MARK: - Coordinate mapping

    private func point(_ x: Float, _ y: Float) -> CGPoint {
        PeakOverlayGeometry.center(
            x: x, y: y,
            patternWidth: patternWidth, patternHeight: patternHeight, box: box
        )
    }

    // MARK: - Marks

    private func drawMeasuredPeaks(_ context: GraphicsContext) {
        guard !measuredPeaks.isEmpty else { return }
        let r = PeakOverlayGeometry.radius(
            probeRadius: probeRadius,
            patternWidth: patternWidth, patternHeight: patternHeight, box: box
        )
        for peak in measuredPeaks {
            let c = point(peak.x, peak.y)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            context.stroke(Path(ellipseIn: rect),
                           with: .color(Self.measuredColor), lineWidth: 1.2)
        }
    }

    private func drawStrain(_ overlay: FitOverlays.StrainOverlay,
                            _ context: GraphicsContext) {
        drawVector(overlay.referenceG1, context,
                   color: .white.opacity(0.7), dash: [4, 3])
        drawVector(overlay.referenceG2, context,
                   color: .white.opacity(0.7), dash: [4, 3])
        if let g1 = overlay.localG1 {
            drawVector(g1, context, color: Self.predictionColor)
        }
        if let g2 = overlay.localG2 {
            drawVector(g2, context, color: Self.predictionColor)
        }
        for marker in overlay.predicted {
            drawCross(at: point(marker.x, marker.y), context,
                      color: Self.predictionColor, opacity: 1)
        }
        drawOriginMarker(at: point(overlay.originX, overlay.originY), context)
    }

    private func drawTemplate(_ overlay: FitOverlays.TemplateOverlay,
                              _ context: GraphicsContext) {
        for marker in overlay.predicted {
            drawCross(at: point(marker.x, marker.y), context,
                      color: Self.predictionColor,
                      opacity: 0.35 + 0.65 * Double(marker.weight))
        }
        drawOriginMarker(at: point(overlay.originX, overlay.originY), context)
    }

    private func drawEllipse(_ context: GraphicsContext) {
        guard ellipse.count > 2 else { return }
        var path = Path()
        path.move(to: point(ellipse[0].x, ellipse[0].y))
        for marker in ellipse.dropFirst() {
            path.addLine(to: point(marker.x, marker.y))
        }
        context.stroke(path, with: .color(Self.calibrationColor.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
    }

    private func drawCross(at c: CGPoint, _ context: GraphicsContext,
                           color: Color, opacity: Double) {
        let arm: CGFloat = 4
        var path = Path()
        path.move(to: CGPoint(x: c.x - arm, y: c.y - arm))
        path.addLine(to: CGPoint(x: c.x + arm, y: c.y + arm))
        path.move(to: CGPoint(x: c.x - arm, y: c.y + arm))
        path.addLine(to: CGPoint(x: c.x + arm, y: c.y - arm))
        context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1.4)
    }

    private func drawOriginMarker(at c: CGPoint, _ context: GraphicsContext) {
        let arm: CGFloat = 6
        var path = Path()
        path.move(to: CGPoint(x: c.x - arm, y: c.y))
        path.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - arm))
        path.addLine(to: CGPoint(x: c.x, y: c.y + arm))
        // Black halo first, so the marker reads on any colormap.
        context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: 3)
        context.stroke(path, with: .color(Self.calibrationColor), lineWidth: 1.2)
    }

    private func drawVector(_ vector: FitOverlays.Vector,
                            _ context: GraphicsContext,
                            color: Color, dash: [CGFloat] = []) {
        let from = point(vector.fromX, vector.fromY)
        let to = point(vector.toX, vector.toY)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)

        // Arrowhead: two short strokes back from the tip.
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = 7
        for side in [CGFloat(1), -1] {
            let a = angle + .pi + side * 0.45
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x + headLength * cos(a),
                                     y: to.y + headLength * sin(a)))
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.3, dash: dash))
    }

    // MARK: - Legend

    private var legendText: String {
        if let strain {
            if let residual = strain.localResidualPixels {
                return String(
                    format: "● measured  ✕ local fit  ⇢ reference · residual %.3g px",
                    residual
                )
            }
            return "● measured · no local fit at this position"
        }
        if let template {
            return String(
                format: "● measured  ✕ template · reliability %.2f",
                template.reliability
            )
        }
        var parts: [String] = []
        if originPoint != nil { parts.append("✚ fitted origin") }
        if !ellipse.isEmpty { parts.append("◌ fitted ellipse") }
        return parts.joined(separator: " · ")
    }

    private var legend: some View {
        Text(legendText)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.48), in: Capsule())
    }
}
