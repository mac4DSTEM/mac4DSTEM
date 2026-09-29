//
//  AppState+Lineage.swift
//  Role: The run sites' one door into the lineage (ADR 047, L1) for the kinds
//        that are NOT recipe steps — calibration, diffraction groups, phase
//        mapping, precipitate objects, export. The five replayable kinds
//        already reach `SessionReplay.record` through `recordReplayStep`.
//
//  The live lineage is owned by `SessionReplay` (`replay.lineage`); nothing is
//  stored on `AppState`. Each helper here only turns a finished run's numbers
//  into the flat string-to-string snapshot a node holds, and states its
//  suppression rule once: while a dataset load is in flight the automatic
//  re-establishing pass runs with defaults, and recording it would overwrite an
//  adopted colleague's node with them (`recordReplayStep`'s F1 rule, v2 S5).
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    /// Record one completed run of a lineage-only kind. Nil when suppressed.
    @discardableResult
    func recordLineageRun(kind: String, parameters: [String: String],
                          external: [SessionLineage.External] = []) -> String? {
        guard !datasetSession.isLoading else { return nil }
        return replay.record(kind: kind, parameters: parameters, external: external,
                             under: ReplayParameterFrame.of(loadedView.specification))
    }

    /// The origin fit just landed in `calibrationSession`.
    func recordOriginCalibrationRun(fitFunction: OriginFitFunction, method: OriginMethod,
                                    probeRadius: Float, rmsResidual: Float?) {
        var parameters = [
            "fit_function": fitFunction.rawValue,
            "method": method.rawValue,
            "probe_radius_px": String(probeRadius),
        ]
        if let origin = calibrationSession.calibration.meanOrigin {
            parameters["origin_x_px"] = String(origin.x)
            parameters["origin_y_px"] = String(origin.y)
        }
        if let rmsResidual { parameters["fit_rms_px"] = String(rmsResidual) }
        recordLineageRun(kind: "calibration_origin", parameters: parameters)
    }

    /// The ellipse in `calibrationSession` was just fitted or typed.
    func recordEllipseCalibrationRun() {
        let calibration = calibrationSession.calibration
        guard let a = calibration.ellipseA, let b = calibration.ellipseB,
              let theta = calibration.ellipseTheta else { return }
        var parameters = [
            "a_px": String(a), "b_px": String(b),
            "theta_deg": String(theta * 180 / .pi),
        ]
        if let source = calibrationSession.provenance.ellipse {
            parameters["source"] = String(describing: source)
        }
        recordLineageRun(kind: "calibration_ellipse", parameters: parameters)
    }

    /// The reciprocal-pixel size in `calibrationSession` was just measured or typed.
    func recordQCalibrationRun() {
        let calibration = calibrationSession.calibration
        guard let size = calibration.qPixelSize, size.isFinite, size > 0 else { return }
        var parameters = ["q_pixel_size": String(size)]
        if let units = calibration.qPixelUnits { parameters["q_units"] = units }
        if let source = calibrationSession.provenance.qScale {
            parameters["source"] = String(describing: source)
        }
        recordLineageRun(kind: "calibration_q", parameters: parameters)
    }

    /// The run whose product is about to be saved is no longer collapsible (R3).
    /// Marks the ACTIVE node of the product kind's run with the result node
    /// name the writer will give it, BEFORE the save captures the lineage — so
    /// the file that carries the map also says which run made it. Returns what
    /// to hand `undoLineageProductMark` if the save fails; nil when no
    /// recorded run stands behind this product kind.
    func markLineageProductSaved(productKind: String) -> (step: String, previous: String?)? {
        guard let kind = SessionLineage.lineageKind(forProductKind: productKind),
              let node = replay.lineage.activeNodes().first(where: { $0.kind == kind })
        else { return nil }
        replay.markProduct(step: node.id, as: BraggVectorEMDWriter.resultNodeName(forKind: productKind))
        return (node.id, node.product)
    }

    func undoLineageProductMark(_ mark: (step: String, previous: String?)?) {
        guard let mark else { return }
        replay.restoreProduct(step: mark.step, to: mark.previous)
    }

    /// A save just finished: if the writer left the lineage out (it will not
    /// write one it could not read back, or one that disagrees with the recipe
    /// beside it), say so in the session log.
    func reportLineageOmission() {
        if let note = BraggVectorEMDWriter.takeLineageOmission() { activityLog.record(note) }
    }

    /// A sink: something left the session (a file in a format). Not
    /// rewindable and never collapsed into (R1, R3) — the file name is the
    /// only identity it has, so each export is a node. `productKind`, when the
    /// export wrote the displayed product, names the run it wrote (edge role
    /// `product`); an export of the source data consumes no recorded run.
    @discardableResult
    func recordExportRun(format: String, fileName: String, productKind: String? = nil) -> String? {
        guard !datasetSession.isLoading else { return nil }
        var sources: [SessionLineage.Input] = []
        if let productKind, let kind = SessionLineage.lineageKind(forProductKind: productKind),
           let node = replay.lineage.activeNodes().first(where: { $0.kind == kind }) {
            sources.append(SessionLineage.Input(step: node.id, role: "product"))
        }
        let id = replay.record(
            kind: "export",
            parameters: ["format": format, "file_name": fileName],
            extraInputs: sources,
            under: ReplayParameterFrame.of(loadedView.specification))
        // Marked as a product so the collapse rule (R3) can never fold two
        // exports into one node.
        replay.markProduct(step: id, as: fileName)
        return id
    }
}
