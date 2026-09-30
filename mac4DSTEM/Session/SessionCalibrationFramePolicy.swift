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

    /// The decision for what a sidecar SAYS about its view. A recorded view
    /// decides as below; an unrecorded one (`SessionViewRecord.unrecorded`)
    /// is adopted only onto a whole-file load, the frame every pre-recording
    /// build wrote — never re-referenced into a reduced view, which would
    /// drive geometry from a full-extent claim nobody made.
    package static func decide(
        record: SessionViewRecord, loaded: LoadSpecification
    ) -> SessionCalibrationFramePolicy {
        switch record {
        case .recorded(let specification):
            return decide(session: specification, loaded: loaded)
        case .unrecorded:
            if loaded.isFullExtent { return .identity }
            return .refuse(reason:
                "The saved session did not record which view of the file its "
                + "calibration was measured on (it was saved by an older version), "
                + "so it cannot be moved into the view loaded now "
                + "(\(loaded.provenanceSummary ?? "a reduced view")). "
                + "Reopen the whole file to use it.")
        }
    }

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
        /// Why saved fitted-origin maps were NOT applied though the sidecar
        /// carried them (their shape is not this frame's scan extent); nil
        /// when there were none or they were applied. The mean origin then
        /// stands in, and the reason is for the reader (S18).
        package var mapsRefusal: String?

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal).
        package nonisolated init(calibration: Calibration, center: CalibrationReReference.DetectorPoint? = nil, restoredMaps: Bool, invalidated: [CalibrationInvalidation], mapsRefusal: String? = nil) {
            self.calibration = calibration
            self.center = center
            self.restoredMaps = restoredMaps
            self.invalidated = invalidated
            self.mapsRefusal = mapsRefusal
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
        // ADR 040: a marked sidecar holds py4DSTEM's sign; an unmarked one
        // (written before 2026-09-28) holds the app's own and is read as-is.
        if let value = saved.qrRotationRad {
            sessionFrame.rotationRad = Float(saved.qrRotationConvention == RQRotationConvention.marker
                ? RQRotationConvention.app(fromPy4DSTEM: value) : value)
        }
        if let value = saved.probeSemiangle { sessionFrame.probeRadius = Float(value) }
        if let value = saved.ellipseA { sessionFrame.ellipseA = value }
        if let value = saved.ellipseB { sessionFrame.ellipseB = value }
        if let value = saved.ellipseTheta { sessionFrame.ellipseTheta = value }
        var restoredMaps = false
        var mapsRefusal: String?
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
        if !restoredMaps, let maps = saved.originMaps, maps.shape.count == 2 {
            mapsRefusal = "The saved fitted-origin maps cover \(maps.shape[1]) × \(maps.shape[0]) scan positions, "
                + "but this frame's scan is \(mapExtent.rx) × \(mapExtent.ry), so they were not applied"
                + (saved.qx0Mean != nil && saved.qy0Mean != nil
                    ? "; the saved mean origin is used instead." : ".")
        }
        if !restoredMaps, let qx0 = saved.qx0Mean, let qy0 = saved.qy0Mean {
            sessionFrame.recordedOriginX = Float(qy0)
            sessionFrame.recordedOriginY = Float(qx0)
            sessionFrame.originProvenance = .sessionMean
            sessionCenter = .init(x: Float(qy0), y: Float(qx0))
        }

        guard case .reReference = policy else {
            return Output(calibration: sessionFrame, center: sessionCenter,
                          restoredMaps: restoredMaps, invalidated: [],
                          mapsRefusal: mapsRefusal)
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
            invalidated: outcome.invalidated,
            mapsRefusal: mapsRefusal
        )
    }
}

/// When the peaks a session sidecar stores may be adopted on open
/// (docs/archive/v4/bragg-restore-registration-2026-09-28.md). Pure, so each
/// refusal is unit-pinned. Peaks are scan-indexed detector coordinates:
/// unlike calibration they are never re-mapped between views, so the only
/// frame treatment that adopts them is `.identity` — the exact view they were
/// detected on. Every check that fails names itself in the returned sentence,
/// which becomes the status line; a nil return means adopt.
package nonisolated enum SessionPeakRestore {
    package static let diskStepKind = "disk_detection"

    /// The recorded disk-detection step, if the record has one.
    package static func diskStep(in record: SessionReplayRecord?) -> SessionReplayRecord.Step? {
        record?.steps.first { $0.kind == diskStepKind }
    }

    /// As below, for a sidecar's own view record: disks detected on a view the
    /// sidecar never recorded cannot be matched to the loaded one.
    package static func refusalBeforeReading(
        viewRecord: SessionViewRecord,
        loadedSpecification: LoadSpecification,
        replay: SessionReplayRecord?
    ) -> String? {
        guard case .recorded(let specification) = viewRecord else {
            return "Stored disks not used — the session did not record which view they were detected on"
        }
        return refusalBeforeReading(
            sessionSpecification: specification,
            loadedSpecification: loadedSpecification, replay: replay
        )
    }

    /// The checks that need no peaks read — run first so a sidecar that cannot
    /// pass is never read (a Thronsen-A grid is 18 MB).
    package static func refusalBeforeReading(
        sessionSpecification: LoadSpecification,
        loadedSpecification: LoadSpecification,
        replay: SessionReplayRecord?
    ) -> String? {
        guard SessionCalibrationFramePolicy.decide(
            session: sessionSpecification, loaded: loadedSpecification
        ) == .identity else {
            return "Stored disks not used — they were detected on a different view than the one loaded now"
        }
        guard diskStep(in: replay) != nil else {
            return "Stored disks not used — the session's recipe has no disk-detection step to vouch for them"
        }
        return nil
    }

    /// The checks that need the stored grid.
    package static func refusal(
        for grid: BraggVectorEMDWriter.StoredPeakGrid,
        scanWidth: Int, scanHeight: Int, detectorWidth: Int, detectorHeight: Int,
        step: SessionReplayRecord.Step
    ) -> String? {
        guard grid.vectors.scanWidth == scanWidth, grid.vectors.scanHeight == scanHeight else {
            return "Stored disks not used — they cover a \(grid.vectors.scanWidth) × \(grid.vectors.scanHeight) scan, not \(scanWidth) × \(scanHeight)"
        }
        guard grid.detectorWidth == detectorWidth, grid.detectorHeight == detectorHeight else {
            return "Stored disks not used — they were detected on a \(grid.detectorWidth) × \(grid.detectorHeight) detector, not \(detectorWidth) × \(detectorHeight)"
        }
        let differing = DiskDetectionRecordMatch.mismatches(
            provenance: grid.vectors.detectionProvenance, stepParameters: step.parameters
        )
        guard differing.isEmpty else {
            return "Stored disks not used — their detection settings do not match the session's recorded disk-detection step (\(differing.joined(separator: ", ")))"
        }
        return nil
    }
}
