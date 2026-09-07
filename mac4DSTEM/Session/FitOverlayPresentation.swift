import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// The fit-verification overlays drawn on the diffraction pane — origin and
/// ellipse in Prepare, the local strain lattice, the matched ACOM template —
/// as one value computed over a snapshot of session state.
///
/// C5's first extraction (consolidation plan §4, 2026-09-07): this was 115
/// lines of computed properties on `AppState`. Pure, so the gating (only the
/// single pattern the vectors were measured from; only the mode that can
/// draw) and the reopen boundary (a calibration restored from a sidecar draws
/// the same origin and ellipse) are pinned in `FitOverlayPresentationTests`
/// without a window. `AppState.fitOverlays` builds the snapshot; the UI reads
/// this value. The geometry itself stays in Core's `FitOverlays`.
package nonisolated struct FitOverlayPresentation {
    package enum Analysis: Equatable { case strain, acom, other }

    /// The user's "Fit overlay" toggle.
    package var enabled: Bool
    package var analysis: Analysis
    /// The Prepare workspace is where origin and ellipse are judged.
    package var inPrepare: Bool
    /// True for the current pattern; false for the mean/max pattern, which
    /// no per-position vector describes.
    package var showsCurrentPattern: Bool
    /// True when the real-space selection is a single point (not an ROI).
    package var pointSelection: Bool
    package var descriptor: DatasetDescriptor?
    package var selectedX: Int
    package var selectedY: Int
    package var calibration: Calibration
    /// The in-app ellipse fit, which carries its own centre.
    package var ellipseFit: EllipseCalibrationFit?
    package var braggVectors: BraggVectors?
    package var strainMap: StrainMap?
    package var orientationPlan: OrientationPlan?
    package var orientationMap: OrientationMap?
    package var hasOrientationMap: Bool
    package var invAngstromPerPixel: Double

    package nonisolated init(
        enabled: Bool, analysis: Analysis, inPrepare: Bool,
        showsCurrentPattern: Bool, pointSelection: Bool,
        descriptor: DatasetDescriptor?, selectedX: Int, selectedY: Int,
        calibration: Calibration, ellipseFit: EllipseCalibrationFit? = nil,
        braggVectors: BraggVectors? = nil, strainMap: StrainMap? = nil,
        orientationPlan: OrientationPlan? = nil, orientationMap: OrientationMap? = nil,
        hasOrientationMap: Bool = false, invAngstromPerPixel: Double = 0
    ) {
        self.enabled = enabled
        self.analysis = analysis
        self.inPrepare = inPrepare
        self.showsCurrentPattern = showsCurrentPattern
        self.pointSelection = pointSelection
        self.descriptor = descriptor
        self.selectedX = selectedX
        self.selectedY = selectedY
        self.calibration = calibration
        self.ellipseFit = ellipseFit
        self.braggVectors = braggVectors
        self.strainMap = strainMap
        self.orientationPlan = orientationPlan
        self.orientationMap = orientationMap
        self.hasOrientationMap = hasOrientationMap
        self.invAngstromPerPixel = invAngstromPerPixel
    }

    /// Fit overlays are only meaningful on the single pattern they were
    /// measured from: the per-position stored vectors do not describe the
    /// mean/max pattern or an ROI-summed virtual pattern.
    package var patternShowsSelectedPosition: Bool {
        pointSelection && showsCurrentPattern
    }

    private var scanIndex: Int? {
        guard let d = descriptor else { return nil }
        return selectedY * d.rx + selectedX
    }

    private var referenceOrigin: (x: Float, y: Float)? {
        guard let d = descriptor else { return nil }
        return calibration.meanOrigin ?? (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
    }

    /// Stored (raw detector) Bragg peaks at the selected scan position —
    /// the measured evidence the strain/ACOM overlays are judged against.
    package var storedPeaksAtSelection: [BraggPeak] {
        guard let bragg = braggVectors, let d = descriptor, let scan = scanIndex,
              bragg.scanWidth == d.rx, bragg.scanHeight == d.ry,
              patternShowsSelectedPosition,
              bragg.peaks.indices.contains(scan) else { return [] }
        return bragg.peaks[scan]
    }

    /// Local fitted lattice vs reference lattice at the selected position,
    /// mapped back onto the raw pattern.
    package var strain: FitOverlays.StrainOverlay? {
        guard enabled, analysis == .strain, patternShowsSelectedPosition,
              let map = strainMap, let d = descriptor, let scan = scanIndex,
              map.width == d.rx, map.height == d.ry,
              let origin = referenceOrigin else { return nil }
        return FitOverlays.strainOverlay(
            map: map, scanIndex: scan,
            calibration: calibration, referenceOrigin: origin,
            patternWidth: d.qx, patternHeight: d.qy
        )
    }

    /// The matched template's predicted reflections at the selected position.
    package var template: FitOverlays.TemplateOverlay? {
        guard enabled, analysis == .acom, patternShowsSelectedPosition,
              let plan = orientationPlan, let map = orientationMap,
              let d = descriptor, let scan = scanIndex,
              map.width == d.rx, map.height == d.ry,
              selectedX >= 0, selectedX < map.width,
              selectedY >= 0, selectedY < map.height,
              let origin = referenceOrigin else { return nil }
        let result = map[selectedX, selectedY]
        guard result.templateIndex >= 0 else { return nil }
        return FitOverlays.acomTemplateOverlay(
            result: result, plan: plan,
            invAngstromPerPixel: invAngstromPerPixel,
            calibration: calibration, referenceOrigin: origin,
            scanIndex: scan, scanWidth: d.rx, scanHeight: d.ry,
            patternWidth: d.qx, patternHeight: d.qy
        )
    }

    /// The origin the calibration would use for the displayed pattern:
    /// per-position fitted origin for the current pattern, mean origin for
    /// the mean/max pattern.
    package var originPoint: (x: Float, y: Float)? {
        guard enabled, inPrepare, calibration.hasFittedOrigin,
              let d = descriptor, let scan = scanIndex, pointSelection,
              let mean = calibration.meanOrigin else { return nil }
        guard showsCurrentPattern else { return mean }
        return FitOverlays.localOrigin(
            calibration: calibration, referenceOrigin: mean,
            scanIndex: scan, scanWidth: d.rx, scanHeight: d.ry
        )
    }

    /// Fitted ellipse sampled in raw detector pixels. Prefers the in-app fit
    /// (which carries its own centre); a session/file ellipse without a
    /// centre is drawn around the mean origin.
    package var ellipse: [FitOverlays.Marker] {
        guard enabled, inPrepare, descriptor != nil else { return [] }
        if let fit = ellipseFit {
            return FitOverlays.ellipsePolyline(
                centerX: Float(fit.centerQY), centerY: Float(fit.centerQX),
                a: fit.a, b: fit.b, theta: fit.theta
            )
        }
        guard calibration.hasEllipse,
              let a = calibration.ellipseA, let b = calibration.ellipseB,
              let theta = calibration.ellipseTheta,
              let mean = calibration.meanOrigin else { return [] }
        return FitOverlays.ellipsePolyline(
            centerX: mean.x, centerY: mean.y, a: a, b: b, theta: theta
        )
    }

    /// True when the current mode/state could produce a fit overlay, so the
    /// toggle only appears where it has an effect.
    package var isAvailable: Bool {
        guard descriptor != nil else { return false }
        switch analysis {
        case .strain: return strainMap != nil
        case .acom: return hasOrientationMap
        case .other:
            return inPrepare && (calibration.hasFittedOrigin || calibration.hasEllipse)
        }
    }
}
