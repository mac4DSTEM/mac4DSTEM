//
//  AppState+ACOM.swift
//  Role: the ACOM (orientation mapping) orchestration — reciprocal-pixel
//        calibration from a known crystal, orientation-plan generation, the
//        match run, and the one publish site for every ACOM display mode.
//        Moved verbatim out of AppState.swift on 2026-09-18 (seam 2,
//        docs/appstate-seams-plan.md): a placement change, no logic touched.
//        The 15(ish) `acom*` properties these functions read moved into
//        `Session/ACOMSession.swift` in the same seam — call sites here are
//        renamed to the owner prefix (`acomSession.modelSelectionIssue`,
//        `.scanSelection(...)`, `.effectiveBackend`,
//        `.effectiveReliabilityThreshold`, `.lastMeasuredTemplateCount`,
//        `.lastMeasuredBackend`) but otherwise unchanged; everything that
//        stayed an AppState computed property (`resolvedACOMModel`,
//        `acomScaleSemantics`, `acomModelSelectionIssue`'s callers already
//        renamed above) keeps its pre-seam name.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
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
        // v2 S13: the STRICTER of the two predicates. It still runs before the
        // model guard for the reason the old comment gives — naming the origin
        // first is more useful than re-detecting disks against a bad one — but
        // it now needs the descriptor, so the dataset guard moved above it.
        // What it adds over `originQuantitativeRefusal` is the second
        // requirement from the design's §2: the origin must be a MEASURED beam
        // centre. That is S11's worst finding closed structurally.
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
        let estimate = await Task.detached(priority: .userInitiated) {
            // DISTINCT shell lengths. `Crystal.reflections` returns every
            // symmetry equivalent separately, all at the same |g|, so the
            // "second shell" is the first length that DIFFERS — not
            // `reflections[1]`, which is another equivalent of the first.
            // Measured consequence of getting this wrong (S13 E1): the
            // self-check reads 1.020 on healthy sim_Au against an expected
            // 1.155 and fires on good data.
            let lengths = model.crystal.reflections(kMax: 2.5).map(\.gLength)
            var shells: [Double] = []
            for length in lengths where shells.last.map({ length > $0 * (1 + 1e-6) }) ?? true {
                shells.append(length)
            }
            guard let firstShell = shells.first else { return nil as QCalibrationEstimate? }
            return KnownCrystalQCalibration.estimate(
                bragg: calibrated.vectors, origin: calibrated.origin.point,
                referenceRadiusInvAngstrom: firstShell,
                secondShellRadiusInvAngstrom: shells.count > 1 ? shells[1] : nil,
                probeRadiusPixels: probeRadiusPixels
            )
        }.value
        guard epoch == datasetSession.epoch,
              modelRevision == resolvedACOMModel?.revisionID else { return }
        guard let estimate else {
            let reason = "Could not identify a non-central first Bragg shell."
            qCalibration.record(refusal: reason)
            presentComputeFailure(SimpleError(reason))
            return
        }
        // The estimator MEASURES a shell ratio and refuses nothing. v2 S13
        // shipped three plausibility thresholds here and Gate B refuted the
        // derivation of all three the same day (see `KnownCrystalQCalibration`
        // for what went wrong and what a later session needs). What survived is
        // the measurement, which `qCalibration.selfCheckSummary` surfaces.
        qCalibration.record(estimate)
        calibrationSession.calibration.qPixelSize = estimate.invAngstromPerPixel
        calibrationSession.calibration.qPixelUnits = "Å⁻¹"
        calibrationSession.provenance.qScale = .measuredInApp
        acomSession.invalidateResult()
        phaseContrast.parallaxPreprocess = nil
        phaseContrast.parallaxAlignment = nil
        var status = String(
            format: "Q calibration ✓  %.6f Å⁻¹/px · first shell %.2f px · %d positions",
            estimate.invAngstromPerPixel, estimate.observedRadiusPixels,
            estimate.sampleCount
        )
        switch estimate.shellCheck {
        case .notSelfChecked:
            status += " · shell ratio NOT self-checked"
        case .measured(let observed, let expected, _):
            status += String(format: " · shell ratio %.3f vs %.3f predicted", observed, expected)
        }
        statusText = status
    }

    /// Build the orientation-plan template library for the selected crystal.
    func generateOrientationPlan() async {
        guard descriptor != nil else { return }
        let templateCount = acomSession.quality.templateCount
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
        let missing = model.crystal.unsupportedElements
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
        let plan = await Task.detached(priority: .userInitiated) {
            OrientationPlan.generate(crystal: model.crystal, kMax: 1.2,
                                     zoneAxisCount: templateCount,
                                     symmetry: model.symmetry,
                                     wavelengthAngstrom: planWavelength,
                                     cancellation: cancellation)
        }.value
        guard epoch == datasetSession.epoch,
              modelRevision == resolvedACOMModel?.revisionID else { return }
        if cancellation.isCancelled {
            statusText = "Orientation-plan generation cancelled"
            return
        }
        guard let plan else {
            presentComputeFailure(SimpleError("Could not generate an orientation plan."))
            return
        }
        acomSession.orientationPlan = plan
        acomSession.hasOrientationPlan = true
        statusText = "Orientation plan ✓  \(plan.count) templates (\(model.displayName))"
    }

    /// Match the chosen preview, selected region, or full scan against the
    /// plan (needs a prior disk-detection pass; builds the plan first if needed).
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
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
        let epoch = datasetSession.epoch
        let map = await Task.detached(priority: .userInitiated) { [self] in
            OrientationMatching.matchAll(bragg: calibrated.vectors, plan: plan,
                                         originX: origin.x, originY: origin.y,
                                         invAngstromPerPixel: scale,
                                         backend: backend,
                                         selection: selection,
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
        // Recipe step (v2 S5). Everything from the CAPTURED run semantics,
        // nothing from live state: the first version recorded the exploratory
        // slider even when the run matched at the calibrated physical scale —
        // a replay at 0.01 Å⁻¹/px instead of the calibrated value gets every
        // orientation wrong with no shape check to catch it (Gate B-lite F3).
        // The material is recorded by ID: a replay that cannot resolve it
        // must fail by name, never fall back to a different crystal.
        // The custom id carries structure and Z but not a₀; the record also
        // carries lattice_a so replay can refuse a drifted a₀ by name.
        recordReplayStep(kind: "acom",
                         parameters: ReplayStepPlan.ACOMReplayPlan.recordedParameters(
                             model: model, scale: scale, backend: map.matchingBackend.rawValue,
                             scope: scope, quality: quality),
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
        statusText = String(
            format: "ACOM %@ ✓  %@ · %@ · %@ positions · %.1f s",
            scope.resultQualifier, map.matchingBackend.rawValue,
            runSemantics.scale.provenance.displayName,
            workCount.formatted(), elapsed
        )
        // R17 (owner, 2026-09-01): a landed preview's natural next step is
        // the full map, so the scope — and with it the header's primary
        // action — advances to it. The segmented control shows the change,
        // and the user can step back to Preview at any time.
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
        publishProduct(
            kind: "acom_\(scope.resultQualifier)_\(baseKind.dropFirst(5))",
            displayName: "ACOM \(scope.rawValue.lowercased()) · \(acomSession.display.rawValue)",
            valueUnits: angular.contains(acomSession.display) ? "rad" : "dimensionless",
            payload: payload,
            validityMask: map.results.map { $0.templateIndex >= 0 },
            qualityFields: [
                ProductQualityField(name: "reliability", units: "dimensionless", image: map.reliabilityImage),
                ProductQualityField(name: "score", units: "dimensionless", image: map.scoreImage),
            ],
            overlays: [ProductOverlayDescriptor(
                kind: "matched_template", provenance: "selected ACOM orientation template")])
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
