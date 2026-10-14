import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The annulus Fit Ellipse samples, drawn on the diffraction pattern while its section in Prepare is open (UI audit 2026-10-14,
/// "Fit annulus never drawn"). Before, the two radii were numbers with nothing to put them against: a reader could not see
/// whether the ring sat inside them, which is what the fit needs ("The annulus must contain a ring with broad angular
/// coverage").
///
/// **Where it is centred is the fit's own centre, not a choice made here.** `AppState.calibrateEllipse` hands
/// `EllipseCalibration` the aperture centre (`centerQX = aperture.centerY`, the row; `centerQY = aperture.centerX`, the column)
/// and the two radii, and the fit samples the pixels with `inner < r <= outer` from it. The circles are those radii around that
/// centre, in the same raw detector pixels (`PeakOverlayGeometry`'s pixel-centre convention), so the pixels between them are the
/// pixels the fit sees. `EllipseFitAnnulusTests` pins the aperture-centre claim against `AppState+Calibration.swift` and the frame
/// against a synthetic ring fitted the way the app fits it.
nonisolated enum EllipseFitAnnulus {
    /// The key `PrepareSettings` remembers its "Ellipse correction" section under (`@SceneStorage`): the pane reads the same
    /// key, so "open" has one owner and no new state.
    static let sectionStorageKey = "prepare.settings.ellipseCorrection.isExpanded"

    /// Where the circles go, in view points inside the pattern's (unzoomed) box.
    struct Metrics: Equatable {
        var center: CGPoint
        var inner: CGFloat
        var outer: CGFloat
    }

    /// nil for a radius that is not a number or is negative, or an outer radius of nothing.
    static func metrics(
        centerX: Float, centerY: Float, inner: Double, outer: Double,
        patternWidth: Int, patternHeight: Int, box: CGSize
    ) -> Metrics? {
        guard inner.isFinite, outer.isFinite, inner >= 0, outer > 0,
              patternWidth > 0, patternHeight > 0, box.width > 0, box.height > 0 else { return nil }
        // View points per detector pixel along a radius: the mean of the axis scales, as the aperture's own outline.
        let scale = (box.width / CGFloat(patternWidth) + box.height / CGFloat(patternHeight)) / 2
        return Metrics(
            center: PeakOverlayGeometry.center(
                x: centerX, y: centerY, patternWidth: patternWidth, patternHeight: patternHeight, box: box),
            inner: CGFloat(inner) * scale, outer: CGFloat(outer) * scale)
    }

    /// Drawn in Prepare only, while the section is open and the inspector that holds it is on screen.
    static func isShown(workspace: WorkspaceArea, sectionIsOpen: Bool, inspectorIsVisible: Bool) -> Bool {
        workspace == .prepare && sectionIsOpen && inspectorIsVisible
    }

    static func spoken(centerX: Float, centerY: Float, inner: Double, outer: Double) -> String {
        let number = { (value: Double) in CalibrationUnitConversion.displayNumber(value, digits: 4) }
        return "Inner radius \(number(inner)) pixels, outer radius \(number(outer)) pixels, centred at x \(number(Double(centerX))), y \(number(Double(centerY)))"
    }
}

/// Two dashed circles and a centre mark, in the zoomed layer so they follow the pattern. Strokes are divided by the zoom: they stay
/// as thin as they are at 1×. Red, the fit family's colour (`PatternFitOverlay`'s ellipse), dashed so the input annulus is not
/// mistaken for the fitted ellipse drawn solid; the outer circle's dashes are long and the inner's short so they tell apart.
struct EllipseFitAnnulusOverlay: View {
    let metrics: EllipseFitAnnulus.Metrics
    let zoom: CGFloat
    let spoken: String

    var body: some View {
        let z = max(zoom, 0.01)
        Canvas { context, _ in
            let c = metrics.center
            func circle(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
            }
            var cross = Path()
            let arm = ApertureOutline.crossArm / z
            cross.move(to: CGPoint(x: c.x - arm, y: c.y)); cross.addLine(to: CGPoint(x: c.x + arm, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - arm)); cross.addLine(to: CGPoint(x: c.x, y: c.y + arm))
            let marks: [(Path, [CGFloat])] = [
                (circle(metrics.outer), [8 / z, 4 / z]),
                (circle(metrics.inner), [3 / z, 3 / z]),
                (cross, []),
            ]
            // The dark under-stroke, widths and opacities the aperture outline has (`ApertureOutline`): a bare red line vanishes over a bright disk.
            for (path, dash) in marks {
                context.stroke(path, with: .color(.black.opacity(ApertureOutline.haloOpacity)),
                               style: StrokeStyle(lineWidth: ApertureOutline.haloWidth / z, dash: dash))
            }
            for (path, dash) in marks {
                context.stroke(path, with: .color(.red.opacity(ApertureOutline.lineOpacity)),
                               style: StrokeStyle(lineWidth: ApertureOutline.lineWidth / z, dash: dash))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ellipse fit annulus")
        .accessibilityValue(spoken)
        .accessibilityIdentifier("pattern.ellipseFitAnnulus")
    }
}
