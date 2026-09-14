//
//  AppState+PhaseMapping.swift
//  Role: the only writer of `PhaseMappingProduct` — build the reference
//        library, run the matcher over the detected Bragg vectors, publish the
//        phase map and its distance companion.
//
//  Why this is a post-processing pass and not a pipeline: `BraggVectors` is
//  computed once per scan and already shared by strain and ACOM. Thronsen et
//  al. call accurate peak finding "perhaps most challenging" and "the most
//  computationally intensive step" of vector matching; here it is already paid
//  for, gated, and sub-pixel refined. That is the deviation worth making
//  (`docs/v3-phase-mapping-method-choice.md`).
//
//  UNVALIDATED. Every product published here carries `validation: "none"` and
//  an exploratory quantitative status until step 3 of
//  `docs/v3-vector-matching-plan.md` has run against Thronsen et al.'s
//  published ground truth. A phase map you can look at is worth having; a
//  density taken off one is not a measurement yet.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif
import simd

extension AppState {

    /// The phase list as Core's own definitions, or nil if the list is not
    /// runnable. Kept separate from `runPhaseMapping` so the settings panel can
    /// size the library without starting one.
    func phaseDefinitions() -> [PhaseDefinition]? {
        guard phaseMapping.runRefusal == nil else { return nil }
        return phaseMapping.phases.map { slot in
            PhaseDefinition(
                id: slot.model.id, displayName: slot.model.displayName,
                crystal: slot.model.crystal,
                role: slot.isMatrix ? .matrix : .candidate,
                zoneAxes: [slot.zoneAxis]
            )
        }
    }

    /// Human-readable reason a `PhaseReferenceLibrary.Failure` happened.
    /// Every arm names a number or a phase, because "could not build the
    /// library" tells a user nothing they can act on.
    static func phaseLibraryFailureMessage(_ failure: PhaseReferenceLibrary.Failure) -> String {
        switch failure {
        case .unsupportedElements(let phase, let z):
            let symbols = z.map { ScatteringFactors.symbols[$0] ?? "Z\($0)" }
            return "\(phase) contains \(symbols.joined(separator: ", ")), "
                + "for which this app has no electron scattering factors."
        case .degenerateZoneAxis(let phase):
            return "\(phase)'s zone axis is [0 0 0], which names no direction."
        case .noVisibleReflections(let phase):
            return "\(phase) has no reflection above the visibility cut at any "
                + "sampled orientation. Raise Max |q| or lower the minimum intensity."
        case .libraryTooLarge(let requested, let limit):
            return "That would build \(requested) reference orientations against a "
                + "limit of \(limit). Increase the in-plane step, or raise the limit."
        case .matrixPhaseNotUnique(let count):
            return count == 0 ? "Mark one phase as the matrix."
                              : "Exactly one phase can be the matrix; \(count) are marked."
        case .noCandidatePhases:
            return "Add a candidate phase to look for."
        }
    }

    /// Map every scan position to a phase, or to "not indexed".
    func runPhaseMapping() async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("Open a dataset first.") }
        if let refusal = phaseMapping.runRefusal { return .failed(refusal) }
        guard let rawVectors = braggVectors else {
            return .failed("Detect Bragg disks first — phase mapping matches the "
                           + "peaks disk detection finds, it does not find its own.")
        }
        guard let definitions = phaseDefinitions() else {
            return .failed(phaseMapping.runRefusal ?? "The phase list is not runnable.")
        }

        let referenceSettings = phaseMapping.reference
        let matchSettings = phaseMapping.matching
        let phaseSignature = phaseMapping.phaseSignature

        let library: PhaseReferenceLibrary
        do {
            library = try PhaseReferenceLibrary.build(phases: definitions,
                                                      settings: referenceSettings)
        } catch let failure as PhaseReferenceLibrary.Failure {
            return .failed(Self.phaseLibraryFailureMessage(failure))
        } catch {
            return .failed(error.localizedDescription)
        }

        let calibrated = calibratedBraggVectors(rawVectors, descriptor: descriptor)
        let origin = calibrated.origin.point
        let scale = acomScaleSemantics

        let cancellation = beginCancellableOperation(
            "Phase mapping",
            status: "Matching \(calibrated.vectors.peaks.count) patterns against "
                  + "\(library.entries.count) reference orientations…",
            totalUnits: calibrated.vectors.peaks.count
        )
        defer { finishCancellableOperation(cancellation) }
        let epoch = datasetEpoch

        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self, self.isCurrentOperation(cancellation) else { return }
                self.updateCancellableOperation(
                    cancellation, progress: fraction,
                    status: "Matching patterns…")
            }
        }

        // Detached for the same reason `runDiffractionGroups` is: the matcher
        // is `nonisolated` but not `async`, and calling it inline would run a
        // whole-scan nearest-neighbour search on the main actor.
        let vectors = calibrated.vectors
        let result = await Task.detached(priority: .userInitiated) {
            PhaseVectorMatcher.map(
                bragg: vectors, library: library, settings: matchSettings,
                originX: origin.x, originY: origin.y,
                invAngstromPerPixel: scale.invAngstromPerPixel,
                cancellation: cancellation, progress: progress
            )
        }.value

        guard epoch == datasetEpoch else {
            return .failed("The dataset changed while phase mapping was running.")
        }
        guard let map = result else { return .cancelled }

        let worstChance = library.candidateEntryIndices
            .map {
                library.entries[$0].chanceMatchFraction(
                    pairRadius: matchSettings.pairRadiusInvAngstrom,
                    accessibleRadius: referenceSettings.kMaxInvAngstrom)
            }
            .max() ?? 0
        let matrixDegrees = map.matrixEntryIndex >= 0
            ? library.entries[map.matrixEntryIndex].inPlaneRotationRad * 180 / .pi : .nan

        phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: phaseSignature,
            reference: referenceSettings,
            matching: matchSettings,
            libraryEntryCount: library.entries.count,
            matrixEntryIndex: map.matrixEntryIndex,
            matrixInPlaneDegrees: matrixDegrees,
            worstChanceMatchPercent: 100 * worstChance,
            invAngstromPerPixel: scale.invAngstromPerPixel,
            qScaleIsPhysical: scale.provenance.isPhysical,
            peakCount: rawVectors.totalPeakCount
        ))

        publishPhaseMapProduct()
        let counts = map.phaseCounts
        let indexed = counts.enumerated()
            .filter { $0.offset != map.matrixPhaseIndex && $0.element > 0 }
            .map { "\(map.phaseNames[$0.offset]) \($0.element)" }
            .joined(separator: ", ")
        statusText = "Phase map: \(indexed.isEmpty ? "no candidate phase found" : indexed)"
            + ", matrix \(map.count(of: .matrix)), not indexed \(map.count(of: .notIndexed))"
            + " — unvalidated"
        return .published
    }

    /// The phase map itself: an RGBA image, categorical, with the legend and
    /// the numbers that produced it in provenance.
    func publishPhaseMapProduct() {
        guard let map = phaseMapping.map, let run = phaseMapping.lastRun else { return }
        let candidates = max(0, map.phaseNames.count - 1)
        publishProduct(
            kind: "phase_map",
            displayName: PhaseMappingProduct.mapDisplayName(candidatePhases: candidates),
            valueUnits: "phase",
            payload: .rgba(PhaseMapPresentation.image(map)),
            domain: .scan,
            extraProvenance: phaseProvenance(map: map, run: run).merging(
                ["quantitative_status": "categorical"], uniquingKeysWith: { a, _ in a })
        )
    }

    /// The distance companion: how far, in Å⁻¹, the winning phase's reference
    /// vectors sat from the measured peaks. The map says which phase; this
    /// says how well, and it is the one a reader can argue with.
    func publishPhaseDistanceProduct() {
        guard let map = phaseMapping.map, let run = phaseMapping.lastRun else { return }
        publishProduct(
            kind: "phase_match_distance",
            displayName: PhaseMappingProduct.distanceDisplayName,
            valueUnits: "inv_angstrom",
            payload: .scalar(PhaseMapPresentation.distanceImage(map)),
            validityMask: PhaseMapPresentation.distanceValidity(map),
            domain: .scan,
            extraProvenance: phaseProvenance(map: map, run: run).merging(
                ["quantitative_status": "relative"], uniquingKeysWith: { a, _ in a })
        )
    }

    /// Provenance both phase products share.
    ///
    /// `validation: "none"` is the load-bearing key. It is what stops a phase
    /// fraction read off this map from being quoted as a measurement before
    /// the acceptance test of `v3-vector-matching-plan.md` step 3 has run.
    private func phaseProvenance(map: PhaseMap,
                                 run: PhaseMappingProduct.RunRecord) -> [String: String] {
        var out: [String: String] = [
            "method": "vector_matching",
            "method_citation": "Thronsen et al., Ultramicroscopy 255 (2024) 113861",
            "validation": "none",
            "phases": map.phaseNames.joined(separator: "|"),
            "matrix_phase": map.phaseNames.indices.contains(map.matrixPhaseIndex)
                ? map.phaseNames[map.matrixPhaseIndex] : "?",
            "library_entries": String(run.libraryEntryCount),
            "in_plane_step_deg": String(format: "%.3g", run.reference.inPlaneStepDeg),
            "k_max_inv_angstrom": String(format: "%.4g", run.reference.kMaxInvAngstrom),
            "max_vectors_per_entry": String(run.reference.maximumVectorsPerEntry),
            "pair_radius_inv_angstrom": String(format: "%.4g", run.matching.pairRadiusInvAngstrom),
            "matrix_tolerance_inv_angstrom":
                String(format: "%.4g", run.matching.matrixToleranceInvAngstrom),
            "not_indexed_above_inv_angstrom":
                String(format: "%.4g", run.matching.notIndexedAboveInvAngstrom),
            // Named for its radius: this is computed at the library's full
            // reach, while the guard itself uses each position's own
            // outermost vectors, so the two are not the same number and
            // the key must not pretend they are (Gate B finding 5).
            "worst_chance_match_percent_at_k_max":
                String(format: "%.2f", run.worstChanceMatchPercent),
            "q_scale_inv_angstrom_per_pixel": String(format: "%.6g", run.invAngstromPerPixel),
            "q_scale_provenance": run.qScaleIsPhysical ? "physical" : "exploratory",
            "peaks_matched": String(run.peakCount),
        ]
        if run.matrixInPlaneDegrees.isFinite {
            // Recorded with what it means: the in-plane angle is determined
            // only modulo the projected symmetry of the phase, which the gated
            // harness demonstrates on fcc [001] (P5a).
            out["matrix_in_plane_deg_mod_symmetry"] =
                String(format: "%.1f", run.matrixInPlaneDegrees)
        }
        for (index, name) in map.phaseNames.enumerated() {
            let counts = map.phaseCounts
            out["count_\(index)_\(name)"] = String(index < counts.count ? counts[index] : 0)
        }
        out["count_not_indexed"] = String(map.count(of: .notIndexed))
        out["count_no_peaks"] = String(map.count(of: .noData))
        return out
    }

    /// What the phase-mapping tolerances mean on the detector currently open.
    ///
    /// The settings are in Å⁻¹ and the measurement is on a pixel grid; the Q
    /// calibration is the only thing that joins them, and until 2026-09-12
    /// nothing showed the user the conversion. On the owner's own cube the
    /// shipped 0.020 Å⁻¹ tolerances are 0.44 of one detector pixel, matrix
    /// removal removed nothing at all, and the map came back empty.
    ///
    /// Nil when there is no Q scale to convert through — an exploratory scale
    /// is a slider value, and a pixel count derived from one would be a number
    /// wearing the look of a measurement.
    var phaseVectorResolution: PhaseVectorResolution? {
        let scale = acomScaleSemantics
        guard scale.provenance.isPhysical, scale.invAngstromPerPixel > 0 else { return nil }
        return PhaseVectorResolution(settings: phaseMapping.matching,
                                     invAngstromPerPixel: scale.invAngstromPerPixel)
    }

    /// Put the three matching tolerances onto this detector's own grid.
    func scalePhaseMatchingToDetector() {
        guard let resolution = phaseVectorResolution else { return }
        phaseMapping.matching = resolution.scaledToDetector(phaseMapping.matching)
        statusText = String(format: "Phase matching scaled to this detector: "
                            + "pair radius %.4f Å⁻¹, one detector pixel",
                            phaseMapping.matching.pairRadiusInvAngstrom)
    }

    /// Ask the DATA which beam direction the matrix is on, and set it.
    ///
    /// The app's own diagnosis tells a user to check the matrix zone axis when
    /// nothing was removed as matrix. Telling someone to check something and
    /// giving them no way to answer it is half a feature — this is the other
    /// half. The owner hit exactly this on 2026-09-12 with Al on [001] and a
    /// matrix verdict count of zero.
    ///
    /// Reports the top three, because a tie across a symmetry-equivalent
    /// family is the sign the sweep is behaving (all five sampled ⟨110⟩ tied
    /// at 39.0 % on his cube) and a user who sees only the winner cannot tell
    /// a fit from a coin toss.
    func findMatrixZoneAxis() async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("Open a dataset first.") }
        guard let matrixIndex = phaseMapping.phases.firstIndex(where: \.isMatrix) else {
            return .failed("Mark one phase as the matrix first.")
        }
        guard let rawVectors = braggVectors else {
            return .failed("Detect Bragg disks first — this fits the axis to the "
                           + "peaks disk detection found.")
        }
        let slot = phaseMapping.phases[matrixIndex]
        let calibrated = calibratedBraggVectors(rawVectors, descriptor: descriptor)
        let origin = calibrated.origin.point
        let scale = acomScaleSemantics
        let reference = phaseMapping.reference
        let matching = phaseMapping.matching
        let crystal = slot.model.crystal
        let vectors = calibrated.vectors

        let cancellation = beginCancellableOperation(
            "Matrix zone axis",
            status: "Fitting \(slot.model.displayName) against every low-index zone axis…")
        defer { finishCancellableOperation(cancellation) }
        let epoch = datasetEpoch

        let fits = await Task.detached(priority: .userInitiated) {
            PhaseVectorMatcher.fitZoneAxis(
                bragg: vectors, crystal: crystal,
                referenceSettings: reference, settings: matching,
                originX: origin.x, originY: origin.y,
                invAngstromPerPixel: scale.invAngstromPerPixel,
                cancellation: cancellation)
        }.value

        guard !cancellation.isCancelled else { return .cancelled }
        // The same two guards `runPhaseMapping` has: a fit against the peaks
        // of a dataset that is no longer open is not a fit for this one, and
        // the phase list is editable while the sweep runs, so the slot at
        // `matrixIndex` must still be the phase that was fitted.
        guard epoch == datasetEpoch else {
            return .failed("The dataset changed while the zone axis was being fitted.")
        }
        guard let winner = fits.first else {
            return .failed("No low-index zone axis of \(slot.model.displayName) "
                           + "presents any reflection this detector can reach.")
        }
        // `id` is the model's, so the same crystal at two zone axes shares
        // it; requiring `isMatrix` too pins the one slot that can be the
        // matrix (Gate B, 2026-09-14).
        guard phaseMapping.phases.indices.contains(matrixIndex),
              phaseMapping.phases[matrixIndex].id == slot.id,
              phaseMapping.phases[matrixIndex].isMatrix else { return .cancelled }
        phaseMapping.phases[matrixIndex].u = winner.zoneAxis.x
        phaseMapping.phases[matrixIndex].v = winner.zoneAxis.y
        phaseMapping.phases[matrixIndex].w = winner.zoneAxis.z
        phaseMapping.zoneAxisFits = Array(fits.prefix(3))

        statusText = "\(slot.model.displayName) best fits "
            + "[\(winner.zoneAxis.x) \(winner.zoneAxis.y) \(winner.zoneAxis.z)], "
            + String(format: "explaining %.0f %% of the measured vectors at %.4f Å⁻¹",
                     100 * winner.explainedFraction, winner.meanDistance)
        return .published
    }

    /// What a finished map says about itself when it found nothing, or nil.
    var phaseMappingDiagnosis: String? {
        guard let map = phaseMapping.map else { return nil }
        return PhaseMapPresentation.diagnosis(map, resolution: phaseVectorResolution)
    }

    /// The evidence for the scan position the user is looking at, in one line.
    /// Nil when there is no map, or the position is outside it.
    var phaseMappingEvidenceLine: String? {
        guard let map = phaseMapping.map else { return nil }
        let x = selectedScan.x, y = selectedScan.y
        guard x >= 0, y >= 0, x < map.width, y < map.height else { return nil }
        return PhaseMapPresentation.evidenceLine(map.results[y * map.width + x], map: map)
    }
}
