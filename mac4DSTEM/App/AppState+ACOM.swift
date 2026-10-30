//
//  AppState+ACOM.swift
//  Role: the ACOM (orientation mapping) orchestration — reciprocal-pixel
//        calibration from a known crystal, orientation-plan generation, the
//        match run, and the one publish site for every ACOM display mode.
//        The 15(ish) `acom*` properties these functions read live in
//        `Session/ACOMSession.swift` (see archived docs/archive/v4/appstate-seams-plan.md,
//        seam 2) — call sites here use the owner prefix
//        (`acomSession.modelSelectionIssue`, `.scanSelection(...)`,
//        `.effectiveBackend`, `.effectiveReliabilityThreshold`,
//        `.lastMeasuredTemplateCount`, `.lastMeasuredBackend`); properties
//        that stayed on AppState (`resolvedACOMModel`, `acomScaleSemantics`)
//        keep their own names.
//

import Foundation
import DiffractoOrientation
import DiffractoGeometry
import DiffractoCore
import ShellMetal
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DiffractoScattering
import DSTEMCore
import DSTEMSession
#endif

extension AppState {

    // MARK: - ACOM (orientation mapping)

    /// Build the orientation-plan template library for the selected crystal.
    func calibrateQFromCrystal() async {
        guard !diskDetectionSettingsAreStale else {
            presentComputeFailure(SimpleError("Detection settings changed — run Detect All Disks again before calibrating reciprocal pixels."))
            return
        }
        // Backlog #46. `calibratedBraggVectors` below re-centres every pattern
        // on the fitted origin, so this estimate is only ever as good as that
        // fit. On `downsample_Si_SiGe_exp` the fit RMS is 11.66 px against a
        // 5.03 px probe radius and a 14.9 px lattice period, and the Q pixel
        // size came out 2.56× too large — labelled `.measuredInApp`, which is
        // the string that travels into export, reopen and the QC log while the
        // warning stayed behind in the Origin row.
        // The gate is asked through `SessionGates` (S7's seam), which answers
        // it from `Calibration.originFitRefusal` — the same predicate the
        // readiness row renders, so there is one owner. It is
        // deliberately *only* the residual test and not the whole `originProbe`
        // row: an origin that was never fitted has no residual to judge and is
        // not a known-bad number, which is a different question (#29) and not
        // this defect. The manual Q field stays rendered either way, so
        // refusing here is never a dead end.
        // It runs *before* the input guards on purpose: the verdict does not
        // depend on having Bragg vectors, and re-detecting disks against a bad
        // origin is wasted work, so naming the origin first is the more useful
        // order. No dataset loaded means an empty `Calibration`, which has no
        // residual to judge and falls through to the guards below.
        guard let descriptor, let rawBragg = resultPresentation.braggVectors else {
            presentComputeFailure(SimpleError("Detect Bragg disks before calibrating reciprocal pixels."))
            return
        }
        // The STRICTER of the two predicates — runs before the model guard
        // because naming the origin first is more useful than re-detecting
        // disks against a bad one, and needs the descriptor, so the dataset
        // guard sits above it. What it adds over `originQuantitativeRefusal`
        // is the design's §2 second requirement: the origin must be a
        // MEASURED beam centre (S11's finding, closed structurally).
        if let refusal = gates.reciprocalMetrologyRefusal(
            for: calibrationSession.calibration, descriptor: descriptor,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ) {
            qCalibration.record(refusal: refusal)
            presentComputeFailure(SimpleError(refusal))
            return
        }
        guard let model = resolvedACOMModel else {
            presentComputeFailure(SimpleError(acomSession.modelSelectionIssue
                ?? "Choose a valid phase model before calibrating reciprocal pixels."))
            return
        }
        let modelRevision = model.revisionID
        let calibrated = calibratedBraggVectors(rawBragg, descriptor: descriptor)
        let epoch = datasetSession.epoch
        let probeRadiusPixels = calibrationSession.calibration.probeRadius.map(Double.init)
        // A scale this app measured itself is not an independent prior (a wrong one would confirm itself): only a file's or a typed one counts.
        let priorScale = calibrationSession.provenance.qScale == .measuredInApp ? nil : calibrationSession.calibration.qPixelSize.flatMap {
            CalibrationUnitConversion.reciprocalInvAngstromPerPixel(value: $0, units: calibrationSession.calibration.qPixelUnits)
        }
        let crystalName = model.displayName
        let outcome = await Task.detached(priority: .userInitiated) { () -> KnownCrystalQCalibration.AssignedOutcome? in
            // DISTINCT shell lengths. The reflection list returns every
            // symmetry equivalent separately, all at the same |g|, so the
            // "second shell" is the first length that DIFFERS — not
            // `reflections[1]`, which is another equivalent of the first.
            // Getting this wrong makes the self-check read 1.020 on healthy
            // sim_Au against an expected 1.155 and fire on good data
            // (measured, S13 E1).
            let list = try? model.structure.kinematicReflections(kMax: 2.5)
            var shells: [Double] = []
            for length in (list?.kept.map(\.gLength) ?? []) where shells.last.map({ length > $0 * (1 + 1e-6) }) ?? true {
                shells.append(length)
            }
            guard !shells.isEmpty else { return nil }
            // One family name per shell, for "assigned to {200}".
            let families = list?.families ?? []
            let labels = shells.map { g in
                families.first { abs($0.family.g / g - 1) < 1e-6 }.map { ShellAssignment.compactLabel($0.family.name) } ?? "shell \(shells.firstIndex(of: g).map { $0 + 1 } ?? 0)"
            }
            return KnownCrystalQCalibration.estimateAssigned(
                bragg: calibrated.vectors, origin: calibrated.origin.point, shells: shells, labels: labels,
                crystalName: crystalName, priorScale: priorScale)
        }.value
        guard epoch == datasetSession.epoch,
              modelRevision == resolvedACOMModel?.revisionID else { return }
        guard let outcome else {
            let reason = "Could not identify a non-central first Bragg shell."
            qCalibration.record(refusal: reason)
            presentComputeFailure(SimpleError(reason))
            return
        }
        // The ring sequence decides which crystal shell the first ring is; a sequence that fits nothing or two shells equally
        // refuses, names why, and writes nothing (an existing scale stays).
        let estimate: QCalibrationEstimate
        switch outcome {
        case .refused(let sentence):
            qCalibration.record(refusal: sentence)
            presentComputeFailure(SimpleError(sentence))
            return
        case .estimate(let made):
            estimate = made
        }
        // The estimator MEASURES a shell ratio and refuses nothing — plausibility
        // thresholds here were tried and their derivation refuted by Gate B
        // (see `KnownCrystalQCalibration` for what went wrong). What survives
        // is the measurement, which `qCalibration.selfCheckSummary` surfaces.
        qCalibration.record(estimate)
        calibrationSession.calibration.qPixelSize = estimate.invAngstromPerPixel
        calibrationSession.calibration.qPixelUnits = "Å⁻¹"
        calibrationSession.provenance.qScale = .measuredInApp
        // The Q row says what was not checked (lane Q, 2026-09-30): nil for a
        // measured ratio, whose numbers are shown instead and never judged.
        calibrationSession.provenance.qShellCaveat = Self.qShellCaveatText(estimate).map {
            CalibrationProvenance.QShellCaveat(pixelSize: estimate.invAngstromPerPixel, text: $0)
        }
        // An orientation map stays and reads stale, as after a typed Q (`setManualQPixelSize`).
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        var status = "Q calibration ✓  \(Num.fixed(Double(estimate.invAngstromPerPixel), 6)) Å⁻¹/px"
            + " · first shell \(Num.fixed(Double(estimate.observedRadiusPixels), 2)) px"
            + " · \(Self.positionCountText(estimate.sampleCount))"
        if let assigned = estimate.assignment { status += " · assigned to \(assigned.label)" }
        switch estimate.shellCheck {
        case .notSelfChecked:
            status += " · shell ratio unchecked"
        case .measured(let observed, let expected, _):
            status += " · shell ratio \(Num.fixed(Double(observed), 3)) vs \(Num.fixed(Double(expected), 3)) predicted"
        }
        statusText = status
        recordQCalibrationRun()   // lineage node (ADR 047)
        rederiveDisplayedDPCForScaleChange()
    }

    /// What the Q row says beside the scale, or nil: the unchecked note (with the shell the first ring was assumed to be) and, when
    /// the ring sequence put the first ring on a later shell, which one ("assigned to {200}").
    static func qShellCaveatText(_ estimate: QCalibrationEstimate) -> String? {
        var parts: [String] = []
        if let note = estimate.shellCheck.uncheckedNote {
            if let assigned = estimate.assignment, !assigned.isChecked {
                parts.append(note + "; first ring assumed to be \(assigned.label)")
            } else { parts.append(note) }
        }
        if let assigned = estimate.assignment, assigned.isChecked, assigned.shellIndex > 0 {
            parts.append("Assigned to \(assigned.label): \(assigned.matchedRings) of \(assigned.observedRings) rings match")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "1 position" / "N positions" for status text.
    static func positionCountText(_ n: Int) -> String {
        n == 1 ? "1 position" : "\(n) positions"
    }

    /// "Yes"/"No" for whether the match at the selected scan position came from
    /// the matcher's mirror pass; nil without a match (same rule as `selectedEulerText`).
    var selectedMirroredText: String? {
        guard let map = acomSession.orientationMap,
              map.eulerText(x: selectedScan.x, y: selectedScan.y) != nil else { return nil }
        return map[selectedScan.x, selectedScan.y].mirrored ? "Yes" : "No"
    }

    /// Build the orientation-plan template library for the selected crystal.
    func generateOrientationPlan() async {
        guard descriptor != nil else { return }
        let templateCount = acomTemplateCount
        let cancellation = beginCancellableOperation(
            "Orientation plan", status: "Generating orientation plan…",
            totalUnits: templateCount
        )
        defer { finishCancellableOperation(cancellation) }

        guard let model = resolvedACOMModel else {
            presentComputeFailure(SimpleError(acomSession.modelSelectionIssue
                ?? "Choose a valid phase model before generating an orientation plan."))
            return
        }
        let modelRevision = model.revisionID
        let missing = model.structure.unsupportedElements
        guard missing.isEmpty else {
            presentComputeFailure(SimpleError("No scattering factors for element(s) Z = "
                + missing.map(String.init).joined(separator: ", ")
                + " — structure factors would be wrong."))
            return
        }
        let epoch = datasetSession.epoch
        // Without the beam energy the plan falls back to a flat Ewald sphere,
        // which makes every template exactly π-periodic in azimuth and leaves
        // the in-plane angle determined only modulo 180°. Pass the wavelength
        // whenever the dataset carries a voltage.
        let planWavelength = calibrationSession.acceleratingVoltage.flatMap {
            DPC.electronWavelengthAngstrom(voltageKV: $0)
        }
        let planKMax = 1.2
        let (plan, refusal) = await Task.detached(priority: .userInitiated) {
            let plan = OrientationPlan.generate(crystal: model.structure, kMax: planKMax,
                                                zoneAxisCount: templateCount,
                                                symmetry: model.symmetry,
                                                wavelengthAngstrom: planWavelength,
                                                cancellation: cancellation)
            // A nil plan is a cancellation or a refusal of the reflection list; the cause is named below.
            let refusal = plan == nil && !cancellation.isCancelled
                ? OrientationPlan.refusalReason(crystal: model.structure, kMax: planKMax) : nil
            return (plan, refusal)
        }.value
        guard epoch == datasetSession.epoch,
              modelRevision == resolvedACOMModel?.revisionID else { return }
        if cancellation.isCancelled {
            statusText = "Orientation-plan generation cancelled"
            return
        }
        guard let plan else {
            presentComputeFailure(SimpleError(refusal.map { "Could not generate an orientation plan. \($0)" }
                ?? "Could not generate an orientation plan."))
            return
        }
        acomSession.orientationPlan = plan
        acomSession.hasOrientationPlan = true
        statusText = "Orientation plan ✓  \(plan.count) templates (\(model.displayName))"
    }

    /// Match the chosen preview, selected region, or full scan against the
    /// plan (needs a prior disk-detection pass; builds the plan first if needed).
    /// Returns the typed run verdict — see `runVirtualDetector`'s note.
    @discardableResult
    func runACOM(replaying: Bool = false) async -> AnalysisRunOutcome {
        let actionStarted = Date()
        guard !diskDetectionSettingsAreStale else {
            let reason = "Detection settings changed — run Detect All Disks again before ACOM."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let descriptor, let bragg = resultPresentation.braggVectors else {
            let reason = "Detect Bragg disks first (Disks mode), then run ACOM."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let model = resolvedACOMModel else {
            let reason = acomSession.modelSelectionIssue
                ?? "Choose a valid phase model before running ACOM."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        if acomSession.orientationPlan == nil { await generateOrientationPlan() }
        guard let plan = acomSession.orientationPlan else {
            return .failed("No orientation plan could be generated")
        }

        let selection = acomSession.scanSelection(selectedX: selectedScan.x, selectedY: selectedScan.y)
        let scope = acomSession.scope
        let quality = acomSession.quality
        let workCount = selection.positionCount(
            width: descriptor.rx, height: descriptor.ry
        )
        let operationName: String
        switch scope {
        case .preview: operationName = "ACOM preview"
        case .selectedRegion: operationName = "ACOM selected region"
        case .fullScan: operationName = "ACOM full scan"
        }

        let cancellation = beginCancellableOperation(
            operationName, status: "\(operationName)…",
            totalUnits: workCount
        )
        defer { finishCancellableOperation(cancellation) }

        let selectedPositions = selection.sourceIndices(
            width: descriptor.rx, height: descriptor.ry
        )
        let calibrated = calibratedBraggVectors(
            bragg, descriptor: descriptor, positions: selectedPositions
        )
        let origin = calibrated.origin
        let scaleSemantics = acomScaleSemantics
        let scale = scaleSemantics.invAngstromPerPixel
        let runSemantics = ACOMRunSemantics(
            materialModelID: model.id,
            materialDescription: model.displayName,
            scale: scaleSemantics,
            materialProvenance: model.provenance,
            // Snapshot NOW, beside the origin the vectors were just re-centred
            // against — the same moment `strain.publish` takes its copy.
            originProvenance: originFitProvenance
        )
        let modelRevision = model.revisionID
        let backend = acomSession.effectiveBackend
        let refinesInPlane = acomSession.refinesInPlaneAngle
        let epoch = datasetSession.epoch
        let map = await Task.detached(priority: .userInitiated) { [self] in
            OrientationMatching.matchAll(bragg: calibrated.vectors, plan: plan,
                                         originX: origin.x, originY: origin.y,
                                         invAngstromPerPixel: scale,
                                         backend: backend,
                                         selection: selection,
                                         refinesInPlaneAngle: refinesInPlane,
                                         cancellation: cancellation) { fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isCurrentOperation(cancellation),
                          !cancellation.isCancelled else { return }
                    self.progress = max(self.progress ?? 0, fraction)
                    self.showReadout("\(operationName)…")   // the bar draws the fraction
                }
            }
        }.value
        guard epoch == datasetSession.epoch else { return .failed("The dataset changed during the run") }
        if cancellation.isCancelled {
            acomSession.lastEndToEndDuration = Date().timeIntervalSince(actionStarted)
            statusText = "ACOM matching cancelled"
            return .cancelled
        }
        guard let map else {
            presentComputeFailure(SimpleError("ACOM matching failed to initialize."))
            return .failed("ACOM matching failed to initialize.")
        }
        guard resolvedACOMModel?.revisionID == modelRevision,
              acomScaleSemantics == scaleSemantics else {
            statusText = "Discarded ACOM result because its material or Q scale changed"
            return .failed("Discarded ACOM result because its material or Q scale changed")
        }
        acomSession.orientationMap = map
        acomSession.hasOrientationMap = true
        // Recipe step. Everything recorded comes from the CAPTURED run
        // semantics, never live state: recording the live exploratory slider
        // instead would let a replay run at e.g. 0.01 Å⁻¹/px instead of the
        // calibrated value and get every orientation wrong with no shape
        // check to catch it (Gate B-lite F3). The material is recorded by
        // ID: a replay that cannot resolve it must fail by name, never fall
        // back to a different crystal. The custom id carries structure and Z
        // but not a₀; the record also carries lattice_a so replay can refuse
        // a drifted a₀ by name.
        recordReplayStep(kind: "acom",
                         parameters: ReplayStepPlan.ACOMReplayPlan.recordedParameters(
                             model: model, scale: scale, backend: map.matchingBackend.rawValue,
                             scope: scope, quality: quality, refinesInPlaneAngle: refinesInPlane),
                         replaying: replaying)
        acomSession.lastRunScope = scope
        acomSession.lastRunQuality = quality
        acomSession.lastRunSemantics = runSemantics
        acomSession.lastMatchedPositionCount = workCount
        let elapsed = max(Date().timeIntervalSince(actionStarted), 0.001)
        acomSession.lastEndToEndDuration = elapsed
        acomSession.lastPositionsPerSecond = Double(workCount) / elapsed
        acomSession.lastMeasuredTemplateCount = plan.count
        acomSession.lastMeasuredBackend = map.matchingBackend
        acomSession.regionSelectionActive = false
        promoteIPFZDisplayIfDefault(for: map)
        applyACOMDisplay()
        statusText = "ACOM \(scope.resultQualifier) ✓  \(map.matchingBackend.rawValue)"
            + " · \(runSemantics.scale.provenance.displayName)"
            + " · \(workCount.formatted()) positions · \(Num.fixed(Double(elapsed), 1)) s"
        // A landed preview's natural next step is the full map, so the scope
        // — and with it the header's primary action — advances to it (R17,
        // owner decision). The segmented control shows the change, and the
        // user can step back to Preview at any time.
        if scope == .preview { acomSession.scope = .fullScan }
        return .published
    }

    /// The one publish site for every ACOM display mode: pixels, label,
    /// validity and quality fields chosen together (v2.5 step 3e, condition 2).
    /// Widened from `private` (seam 2): `AppState.swift` calls it from the
    /// `onDisplayChange` hook wiring, `activate`'s mode-switch, and
    /// `promoteIPFZDisplayIfDefault`'s caller — all outside this file now.
    func applyACOMDisplay() {
        guard let map = acomSession.orientationMap, navigation.analysisMode == .acom else { return }
        resultPresentation.resultColormap = .viridis
        let payload: ProductPayload
        let baseKind: String
        switch acomSession.display {
        case .ipfZ:           payload = .rgba(map.ipfZImage(maskingReliabilityBelow: acomSession.effectiveReliabilityThreshold)); baseKind = "acom_ipf_z"
        case .reliability:    payload = .scalar(map.reliabilityImage);            baseKind = "acom_reliability"
        case .disorientation: payload = .scalar(map.symmetryDisorientationImage); baseKind = "acom_\(map.symmetry.rawValue)_fz_angle"
        case .score:          payload = .scalar(map.scoreImage);                  baseKind = "acom_score"
        case .inPlane:        payload = .scalar(map.inPlaneAngleImage);           baseKind = "acom_in_plane"
        case .mirrored:       payload = .scalar(map.mirroredImage);               baseKind = "acom_mirrored"
        case .phi1:           payload = .scalar(map.phi1Image);                   baseKind = "acom_phi1"
        case .Phi:            payload = .scalar(map.PhiImage);                    baseKind = "acom_Phi"
        case .phi2:           payload = .scalar(map.phi2Image);                   baseKind = "acom_phi2"
        }
        // All three scopes are named, including full scan: a product whose
        // label said least about how it was made was the most complete one.
        let scope = acomSession.lastRunScope ?? .fullScan
        let angular: Set<ACOMDisplayMode> = [.inPlane, .phi1, .Phi, .phi2, .disorientation]
        // The gate travels with the product: threshold and the fraction it keeps.
        var gateProvenance: [String: String] = [:]
        if let threshold = acomSession.effectiveReliabilityThreshold,
           let kept = map.fractionOfMatchedPositions(withReliabilityAtLeast: threshold) {
            gateProvenance["reliability_threshold"] = String(format: "%.3f", threshold)
            gateProvenance["fraction_above_reliability_threshold"] = String(format: "%.3f", kept)
        }
        let own = scalarPersistenceMetadata(for: .acom)   // its own keys, whatever the current mode
        publishProduct(
            kind: "acom_\(scope.resultQualifier)_\(baseKind.dropFirst(5))",
            displayName: "ACOM \(scope.rawValue.lowercased()) · \(acomSession.display.rawValue)",
            valueUnits: angular.contains(acomSession.display) ? "rad" : "dimensionless",
            payload: payload,
            validityMask: map.results.map { $0.templateIndex >= 0 },
            qualityFields: [
                ProductQualityField(name: "reliability", units: "dimensionless", image: map.reliabilityImage),
                ProductQualityField(name: "score", units: "dimensionless", image: map.scoreImage),
                // The mirror flag travels with every ACOM map (the in-plane angle is relative to the mirror image where it is 1).
                ProductQualityField(name: "mirrored", units: "flag", image: map.mirroredImage),
            ],
            overlays: [ProductOverlayDescriptor(
                kind: "matched_template", provenance: "selected ACOM orientation template")],
            sampling: ProductSampling(row: own.row, column: own.column, units: own.units),
            extraProvenance: own.provenance, ownProvenanceOnly: true)
        if !gateProvenance.isEmpty, let product = resultPresentation.product {
            resultPresentation.replaceProduct(DisplayedProduct(
                origin: product.origin, kind: product.kind, displayName: product.displayName,
                payload: product.payload, domain: product.domain, validityMask: product.validityMask,
                qualityFields: product.qualityFields, sampling: product.sampling,
                valueUnits: product.valueUnits, quantitativeStatus: product.quantitativeStatus,
                provenance: product.provenance.merging(gateProvenance) { _, gate in gate },
                overlays: product.overlays))
        }
    }
}
