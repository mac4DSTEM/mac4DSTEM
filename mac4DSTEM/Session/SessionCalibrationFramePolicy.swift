import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// Which frame treatment a session sidecar's calibration gets on restore.
///
/// A sidecar records calibration in its own view's frame, and the file may
/// now be loaded under a different specification. Adopting the sidecar's
/// values raw can misplace the aperture centre by a full frame and double
/// Q scales into strain (R11) when the loaded view differs from the
/// session's. The geometry lives in `CalibrationReReference`; this type is
/// only the POLICY of when it runs — pure, so the three-way decision is
/// unit-pinned.
package nonisolated enum SessionCalibrationFramePolicy: Equatable {
    /// Recorded on exactly the view now loaded — adopt verbatim.
    case identity
    /// Recorded at full extent — map into the loaded view with the engine,
    /// the same trip file-carried calibration takes.
    case reReference
    /// Recorded on a DIFFERENT reduced view: composing "undo one reduction,
    /// then apply another" is a guess this app refuses to make. The
    /// calibration is not adopted, and the reason is surfaced.
    case refuse(reason: String)

    package static func decide(
        session: LoadSpecification, loaded: LoadSpecification
    ) -> SessionCalibrationFramePolicy {
        if session == loaded { return .identity }
        if session.isFullExtent { return .reReference }
        func describe(_ spec: LoadSpecification) -> String {
            spec.isFullExtent ? "the whole file"
                              : (spec.provenanceSummary ?? "a reduced view")
        }
        return .refuse(reason:
            "The saved session's calibration was recorded on a different view "
            + "(\(describe(session))) than the one "
            + "loaded now (\(describe(loaded))). "
            + "Re-expressing it would be a guess, so it was not adopted — "
            + "reopen at the session's own view to use it.")
    }
}

/// Phases 1–2 of session-calibration adoption, kept pure so the wiring is
/// unit-pinned — a coverage gap here once stayed green through a flawed
/// intermediate. Phase 1 translates the sidecar's values into a calibration
/// of their own frame; phase 2 moves that snapshot through
/// `CalibrationReReference` when the policy says so. The state merge stays
/// in `AppState`.
package nonisolated enum SessionCalibrationTranslation {
    package struct Output {
        package var calibration: Calibration
        package var center: CalibrationReReference.DetectorPoint?
        package var restoredMaps: Bool
        package var invalidated: [CalibrationInvalidation]

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(calibration: Calibration, center: CalibrationReReference.DetectorPoint? = nil, restoredMaps: Bool, invalidated: [CalibrationInvalidation]) {
            self.calibration = calibration
            self.center = center
            self.restoredMaps = restoredMaps
            self.invalidated = invalidated
        }
    }

    /// Returns nil only when the policy demands the engine and no view
    /// exists — unreachable by construction (a non-identity policy implies a
    /// reduced loaded view, which only exists with a live `LoadView`).
    package static func translate(
        saved: PixelCalibration,
        policy: SessionCalibrationFramePolicy,
        view: LoadView?,
        descriptor: DatasetDescriptor
    ) -> Output? {
        var sessionFrame = Calibration()
        var sessionCenter: CalibrationReReference.DetectorPoint?
        if let value = saved.rSize { sessionFrame.rPixelSize = value }
        if let value = saved.rUnits { sessionFrame.rPixelUnits = value }
        if let value = saved.qSize { sessionFrame.qPixelSize = value }
        if let value = saved.qUnits { sessionFrame.qPixelUnits = value }
        if let value = saved.qrFlip { sessionFrame.transposeQR = value }
        if let value = saved.qrRotationRad { sessionFrame.rotationRad = Float(value) }
        if let value = saved.probeSemiangle { sessionFrame.probeRadius = Float(value) }
        if let value = saved.ellipseA { sessionFrame.ellipseA = value }
        if let value = saved.ellipseB { sessionFrame.ellipseB = value }
        if let value = saved.ellipseTheta { sessionFrame.ellipseTheta = value }
        var restoredMaps = false
        // Maps are sized against the extent the SESSION's frame describes:
        // the sidecar writer records maps in its live view's frame
        // (`ResultExport`), so an identity restore sizes against the loaded
        // descriptor and only a full-extent session describes the source
        // extent. Getting this wrong silently downgrades fitted maps to the
        // mean — pinned red-first in `SessionCalibrationTranslationTests`.
        let mapExtent: DatasetDescriptor
        if case .reReference = policy {
            mapExtent = view?.source ?? descriptor
        } else {
            mapExtent = descriptor
        }
        if let maps = saved.originMaps,
           let appMaps = maps.appOriginMaps(width: mapExtent.rx, height: mapExtent.ry) {
            sessionFrame.origin = appMaps
            sessionFrame.originProvenance = .sessionMaps
            if let origin = sessionFrame.meanOrigin {
                sessionCenter = .init(x: origin.x, y: origin.y)
            }
            restoredMaps = true
        }
        if !restoredMaps, let qx0 = saved.qx0Mean, let qy0 = saved.qy0Mean {
            sessionFrame.recordedOriginX = Float(qy0)
            sessionFrame.recordedOriginY = Float(qx0)
            sessionFrame.originProvenance = .sessionMean
            sessionCenter = .init(x: Float(qy0), y: Float(qx0))
        }

        guard case .reReference = policy else {
            return Output(calibration: sessionFrame, center: sessionCenter,
                          restoredMaps: restoredMaps, invalidated: [])
        }
        guard let view else { return nil }
        let outcome = CalibrationReReference.apply(
            view, to: sessionFrame, provenance: CalibrationProvenance(),
            apertureCenter: sessionCenter ?? .init(
                x: Float(view.descriptor.qx) / 2,
                y: Float(view.descriptor.qy) / 2
            )
        )
        return Output(
            calibration: outcome.calibration,
            center: sessionCenter == nil ? nil : outcome.apertureCenter,
            restoredMaps: restoredMaps,
            invalidated: outcome.invalidated
        )
    }
}
