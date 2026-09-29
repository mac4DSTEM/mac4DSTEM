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
        guard let kind = SessionLineage.lineageKind(forProductKind: productKind) else { return nil }
        // The displayed product names its own run (`lineage_step`, R2) — after a
        // rewind that is not necessarily the active run of its kind. A name that
        // is not a node of this kind (a stale id from another file) is ignored.
        let named = resultPresentation.product?.provenance["lineage_step"]
            .flatMap { replay.lineage.node(id: $0) }
            .flatMap { $0.kind == kind ? $0 : nil }
        guard let node = named ?? replay.lineage.activeNodes().first(where: { $0.kind == kind })
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

    // MARK: - lineage_step (R2)

    /// Give the product on screen the run that made it. Only for a computed
    /// product of the run's own kind — never a restored one (its own file
    /// named its run) and never one of another task.
    func stampDisplayedProduct(lineageKind kind: String, step: String) {
        guard !step.isEmpty, let product = resultPresentation.product, product.origin == .computed,
              SessionLineage.lineageKind(forProductKind: product.kind) == kind,
              product.provenance["lineage_step"] != step else { return }
        resultPresentation.replaceProduct(product.addingProvenance(["lineage_step": step]))
    }

    // MARK: - Rewind (R4, phase L4)

    /// What the probe kernel must be for a restored detection.
    private enum KernelRestore {
        /// The live kernel is the recorded one (or none exists yet and the run will build it).
        case keep
        /// The recorded run used the synthetic kernel and a measured one is loaded.
        case rebuildSynthetic
    }

    /// One control write a rewind will make, parsed and checked BEFORE any write.
    private enum RewindRestore {
        case virtualDetector(shape: VirtualShapeMode, aperture: Aperture)
        case diskDetection(DiskDetectionParams, detector: ReplayStepPlan.DiskDetectorReplay, kernel: KernelRestore)
        case strain(ReplayStepPlan.StrainReplayPlan)
        case acom(ReplayStepPlan.ACOMReplayPlan)
        case ellipse(a: Double, b: Double, thetaDegrees: Double, provenance: CalibrationValueProvenance?)
        case qScale(size: Double, units: String?, provenance: CalibrationValueProvenance?)
    }

    /// Rewind to run `step` (ADR 047 R4 and its L4 amendment): put the settings
    /// of every run the rewind puts on (or brings back onto) the path into the
    /// live controls, make the active path its ancestry plus the descendants
    /// wholly on it plus the nodes other kinds hold now, and stop. Products that
    /// are now off the path read stale (`recordedReplayStep`); NOTHING is
    /// deleted and NOTHING recomputes — Run does that, and rewinding back is
    /// always possible. Returns nil when it rewound, otherwise the refusal
    /// sentence; every refusal is decided before the first control changes.
    ///
    /// Restored with the detection parameters: the probe kernel (a synthetic one
    /// is rebuilt; a measured one cannot be, and refuses). Not restored, and
    /// said so in the pane: origin calibration (only its mean is recorded, not
    /// the per-position fit), and the settings of phase mapping, objects and
    /// diffraction groups (their panels own them). A calibration whose live
    /// value already equals the recorded one is left untouched — the recorded
    /// text is a rounding of the value, and writing it back would change the
    /// last bits of an unchanged calibration.
    ///
    /// Re-running stale steps is deliberately not offered: `ReplayPlanner` /
    /// `executeReplay` is the promote path — it suppresses recording (the run
    /// would leave a product with no node), reopens at full extent and holds the
    /// Mac awake. Stale steps are re-run from their own tasks.
    @discardableResult
    func rewindLineage(to step: String) async -> String? {
        func refuse(_ reason: String) -> String {
            statusText = "Rewind refused — \(reason)"
            return reason
        }
        guard hasDataset, !datasetSession.isLoading, !isBusy, !replayRun.isRunning else {
            return refuse("wait for the running operation to finish, then rewind.")
        }
        let plan: SessionLineage.Rewind
        switch replay.lineage.rewindPlan(to: step) {
        case .failure(let refusal): return refuse(refusal.description)
        case .success(let value): plan = value
        }

        // 1. Every check, no write.
        var restores: [RewindRestore] = []
        for id in plan.restore {
            guard let node = replay.lineage.node(id: id) else { continue }
            switch preparedRestore(of: node) {
            case .failure(let failure): return refuse(failure.reason)
            case .success(let restore): if let restore { restores.append(restore) }
            }
        }
        // The ACOM scale guard, as replay applies it: matching at another scale
        // gets every orientation wrong with nothing to catch it. A Q scale this
        // same rewind restores counts as the scale that will be in force.
        var expectedScale = acomScaleSemantics.invAngstromPerPixel
        for case .qScale(let size, let units, _) in restores {
            let wavelength = calibrationSession.acceleratingVoltage.flatMap {
                DPC.electronWavelengthAngstrom(voltageKV: $0)
            }
            if let physical = CalibrationUnitConversion.reciprocalInvAngstromPerPixel(
                value: size, units: units, wavelengthAngstrom: wavelength) {
                expectedScale = physical
            }
        }
        for case .acom(let acomPlan) in restores {
            let recorded = acomPlan.scaleInvAngstromPerPixel
            guard abs(expectedScale - recorded) <= max(1e-12, abs(recorded) * 1e-6) else {
                return refuse(String(
                    format: "the recorded ACOM run matched at %.6g Å⁻¹/px but the scale in force would be %.6g Å⁻¹/px — matching at another scale gets orientations wrong with nothing to catch it, so recalibrate Q to the recorded value, then rewind.",
                    recorded, expectedScale))
            }
        }

        // 2. The refusals only applying can know, and the kernel.
        let epoch = datasetSession.epoch
        for case .diskDetection(_, let detector, _) in restores {
            if let reason = await learnedDetection.replayRefusal(for: detector) {
                return refuse("the recorded disk detection cannot be restored — \(reason)")
            }
        }
        guard datasetSession.epoch == epoch else { return refuse("the dataset changed.") }
        for case .diskDetection(_, _, .rebuildSynthetic) in restores {
            await generateProbeKernel()
            guard datasetSession.epoch == epoch else { return refuse("the dataset changed.") }
        }

        // 3. Write, farthest ancestor first, the target, then what came back.
        for restore in restores {
            switch restore {
            case .virtualDetector(let shape, let recorded):
                resultPresentation.virtualShape = shape
                aperture = recorded
            case .diskDetection(let params, _, _):
                diskDetection.diskParams = params
            case .strain(let strainPlan):
                applyStrainControls(strainPlan)
            case .acom(let acomPlan):
                _ = selectReplayMaterial(acomPlan)   // checked resolvable above
                acomSession.scope = acomPlan.scope
                acomSession.quality = acomPlan.quality
            case .ellipse(let a, let b, let thetaDegrees, let provenance):
                calibrationSession.calibration.ellipseA = a
                calibrationSession.calibration.ellipseB = b
                calibrationSession.calibration.ellipseTheta = thetaDegrees * .pi / 180
                // The value keeps the provenance the recorded run gave it. No
                // "restored by a rewind" label exists, and adding a case to the
                // provenance enum would reach every switch over it for a wording
                // question; an unknown recorded source leaves the current label.
                if let provenance { calibrationSession.provenance.ellipse = provenance }
                calibrationSession.lastEllipseFit = nil
                calibrationSession.ellipseFitAnywayOffer = nil
                if navigation.analysisMode == .disks, let vectors = resultPresentation.braggVectors,
                   let descriptor {
                    showBraggMap(vectors, descriptor: descriptor)
                }
            case .qScale(let size, let units, let provenance):
                calibrationSession.calibration.qPixelSize = size
                calibrationSession.calibration.qPixelUnits = units
                if let provenance { calibrationSession.provenance.qScale = provenance }
                phaseContrast.parallaxPreprocess = nil
                phaseContrast.parallaxAlignment = nil
            }
        }
        replay.apply(plan)
        var status = "Rewound to \(step) — \(plan.leaving.count) run\(plan.leaving.count == 1 ? "" : "s") left the active path; nothing was deleted or recomputed"
        if plan.restore.contains(where: { replay.lineage.node(id: $0)?.kind == "calibration_origin" }) {
            status += "; origin calibration kept as it is now"
        }
        statusText = status
        return nil
    }

    private var currentLineageFrame: SessionLineage.Frame? {
        switch ReplayParameterFrame.of(loadedView.specification) {
        case .detectorIdentity: SessionLineage.Frame()
        case .detectorReduced(let bin, let crop): SessionLineage.Frame(bin: bin, crop: crop)
        case .mixed, .unknown: nil
        }
    }

    /// Provenance of a value a node recorded (`String(describing: source)` of the
    /// case), or nil for anything else.
    private func recordedProvenance(_ name: String?) -> CalibrationValueProvenance? {
        switch name {
        case "importedFile": .importedFile
        case "sessionSidecar": .sessionSidecar
        case "measuredInApp": .measuredInApp
        case "manual": .manual
        case "mixed": .mixed
        case "fitAnyway": .fitAnyway
        default: nil
        }
    }

    /// The probe kernel a restored detection needs, judged against the one
    /// loaded. The kernel is a detection parameter (`kernel_source`,
    /// `kernel_mode`, `kernel_probe_path` are in the recorded step and in the
    /// staleness signature). A synthetic one can be rebuilt from the calibrated
    /// probe radius; a file's own probe is reproducible only if it is loaded; a
    /// kernel measured from a vacuum ROI or a separate scan is not stored anywhere.
    private func kernelRestore(for p: [String: String]) -> Result<KernelRestore, RewindFailure> {
        let source = p["kernel_source"], mode = p["kernel_mode"], path = p["kernel_probe_path"] ?? ""
        func matches(_ live: ProbeKernel) -> Bool {
            live.source.provenanceID == source && (mode == nil || live.mode.provenanceID == mode)
                && (live.probePath ?? "") == path
        }
        func refused(_ reason: String) -> Result<KernelRestore, RewindFailure> {
            .failure(RewindFailure(reason: reason))
        }
        switch source {
        case "synthetic":
            guard let live = probeKernel else { return .success(.keep) }   // the run builds it
            if matches(live) { return .success(.keep) }
            guard let radius = calibrationSession.calibration.probeRadius, let d = descriptor else {
                return refused("the recorded disk detection used the synthetic probe kernel, but a measured kernel is loaded and the probe radius needed to rebuild the synthetic one is not known — calibrate the origin first.")
            }
            guard let rebuilt = ProbeKernel.synthetic(radius: radius, qy: d.qy, qx: d.qx),
                  mode == nil || rebuilt.mode.provenanceID == mode else {
                return refused("the recorded disk detection used the synthetic probe kernel, which cannot be rebuilt here in the recorded mode.")
            }
            return .success(.rebuildSynthetic)
        case "measured_file_probe":
            if let live = probeKernel, matches(live) { return .success(.keep) }
            return refused("the recorded disk detection used the probe image stored in the file (\(path)), and that kernel is not the one loaded — choose Use File's Probe under Disk detection, then rewind.")
        case "measured_roi", "measured_vacuum_scan":
            let what = source == "measured_roi" ? "a vacuum region of the scan" : "a separate vacuum scan"
            return refused("the recorded disk detection used a probe kernel measured from \(what). That kernel is not stored, so a rewind cannot put it back, and detecting again with another kernel would not reproduce the run.")
        default:
            return .success(.keep)   // an unknown or missing source: `ReplayPlanner.parse` names it
        }
    }

    /// The write a node's settings call for (nil: nothing to write — the kind has
    /// no restorable control, or the live value already is the recorded one), or
    /// why it cannot be made.
    private func preparedRestore(of node: SessionLineage.Node) -> Result<RewindRestore?, RewindFailure> {
        let name = "\(node.id) (\(node.kind))"
        func failure(_ reason: String) -> Result<RewindRestore?, RewindFailure> {
            .failure(RewindFailure(reason: "\(name) cannot be restored — \(reason)"))
        }
        func frameMatches() -> Bool { node.frame != nil && node.frame == currentLineageFrame }
        let frameReason = "it was recorded on a different detector frame than this session is on, so its pixel-valued settings would mean something else."
        var parameters = node.parameters
        var kernel = KernelRestore.keep
        if node.kind == "disk_detection" {
            switch kernelRestore(for: parameters) {
            case .failure(let failure): return .failure(RewindFailure(reason: "\(name) cannot be restored — \(failure.reason)"))
            case .success(let decided): kernel = decided
            }
            // The kernel is decided above, in a rewind's words; `parse`'s own
            // refusal of a measured kernel is replay's ("on the promoted view").
            if parameters["kernel_source"] != nil { parameters["kernel_source"] = "synthetic" }
        }
        let step = SessionReplayRecord.Step(kind: node.kind, parameters: parameters, recorded: node.recorded)
        let p = node.parameters
        switch node.kind {
        case "virtual_detector", "disk_detection", "strain", "acom":
            let plan: ReplayStepPlan
            switch ReplayPlanner.parse(step) {
            case .failure(let refusal): return failure(refusal.reason)
            case .success(let parsed): plan = parsed
            }
            if plan.usesDetectorFrameParameters, !frameMatches() { return failure(frameReason) }
            switch plan {
            case .virtualDetector(let shape, let recorded):
                return .success(.virtualDetector(shape: shape, aperture: recorded))
            case .diskDetection(let params, let detector):
                return .success(.diskDetection(params, detector: detector, kernel: kernel))
            case .strain(var strainPlan):
                // A manual run recorded the basis it indexed with; the resolved
                // lattice in the step is what it found. Run again from the first.
                if strainPlan.manualBasis != nil,
                   let g1x = p["input_g1_x"].flatMap(Float.init), let g1y = p["input_g1_y"].flatMap(Float.init),
                   let g2x = p["input_g2_x"].flatMap(Float.init), let g2y = p["input_g2_y"].flatMap(Float.init),
                   [g1x, g1y, g2x, g2y].allSatisfy(\.isFinite) {
                    strainPlan.manualBasis = .init(g1x: g1x, g1y: g1y, g2x: g2x, g2y: g2y)
                }
                return .success(.strain(strainPlan))
            case .acom(let acomPlan):
                if let reason = replayMaterialRefusal(acomPlan) { return failure(reason) }
                return .success(.acom(acomPlan))
            case .dpc:
                return .success(nil)
            }
        case "calibration_ellipse":
            guard let a = p["a_px"].flatMap(Double.init), let b = p["b_px"].flatMap(Double.init),
                  let theta = p["theta_deg"].flatMap(Double.init),
                  a.isFinite, b.isFinite, theta.isFinite, a > 0, b > 0, a >= b else {
                return failure("its recorded ellipse is not a valid ellipse.")
            }
            let live = calibrationSession.calibration
            if let la = live.ellipseA, let lb = live.ellipseB, let lt = live.ellipseTheta,
               String(la) == p["a_px"], String(lb) == p["b_px"], String(lt * 180 / .pi) == p["theta_deg"] {
                return .success(nil)   // already this ellipse
            }
            if !frameMatches() { return failure(frameReason) }
            return .success(.ellipse(a: a, b: b, thetaDegrees: theta, provenance: recordedProvenance(p["source"])))
        case "calibration_q":
            guard let size = p["q_pixel_size"].flatMap(Double.init), size.isFinite, size > 0 else {
                return failure("its recorded reciprocal-pixel size is not a valid size.")
            }
            let live = calibrationSession.calibration
            if let liveSize = live.qPixelSize, String(liveSize) == p["q_pixel_size"],
               live.qPixelUnits == p["q_units"] {
                return .success(nil)   // already this scale
            }
            if !frameMatches() { return failure(frameReason) }
            return .success(.qScale(size: size, units: p["q_units"], provenance: recordedProvenance(p["source"])))
        default:
            // Origin calibration (only its mean is recorded), phase mapping,
            // objects, diffraction groups, unknown kinds, DPC: no control to restore.
            return .success(nil)
        }
    }
}

private struct RewindFailure: Error {
    let reason: String
}
