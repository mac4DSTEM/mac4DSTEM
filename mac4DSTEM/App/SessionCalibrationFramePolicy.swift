import Foundation
import DSTEMCore

/// P2 (Gate D, 2026-09-01): which frame treatment a session sidecar's
/// calibration gets on restore.
///
/// A sidecar records calibration in ITS OWN view's frame; the file may now be
/// loaded under a different specification. `applySessionCalibration` used to
/// adopt the values raw — on a 2× binned open of a full-extent session that
/// put the aperture centre one full frame off (the owner's corner BF preset)
/// and doubled-frame Q scales into strain (R11). The geometry lives in
/// `CalibrationReReference`; this type is only the POLICY of when it runs —
/// pure, so the three-way decision is unit-pinned.
nonisolated enum SessionCalibrationFramePolicy: Equatable {
    /// Recorded on exactly the view now loaded — adopt verbatim.
    case identity
    /// Recorded at full extent — map into the loaded view with the engine,
    /// the same trip file-carried calibration takes.
    case reReference
    /// Recorded on a DIFFERENT reduced view: composing "undo one reduction,
    /// then apply another" is a guess this app refuses to make. The
    /// calibration is not adopted, and the reason is surfaced.
    case refuse(reason: String)

    static func decide(
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

/// P2: phases 1–2 of session-calibration adoption, pure so the wiring the
/// unit gate proved uncovered (it stayed green across a known-flawed
/// intermediate) is pinned by test. Phase 1 translates the sidecar's values
/// into a calibration of their own frame; phase 2 moves that snapshot
/// through `CalibrationReReference` when the policy says so. The state
/// merge stays in `AppState`.
nonisolated enum SessionCalibrationTranslation {
    struct Output {
        var calibration: Calibration
        var center: CalibrationReReference.DetectorPoint?
        var restoredMaps: Bool
        var invalidated: [CalibrationInvalidation]
    }

    /// Returns nil only when the policy demands the engine and no view
    /// exists — unreachable by construction (a non-identity policy implies a
    /// reduced loaded view, which only exists with a live `LoadView`).
    static func translate(
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
        // Maps are sized against the extent the SESSION's frame describes —
        // and the sidecar WRITER records maps in its LIVE VIEW's frame
        // (`ResultExport`), so an identity restore sizes against the loaded
        // descriptor; only a full-extent session describes the source extent.
        // Getting this wrong silently downgrades fitted maps to the mean
        // (refuter correction, 2026-09-01; pinned red-first in
        // `SessionCalibrationTranslationTests`).
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
