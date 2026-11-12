//
//  AppState+PhaseMappingFromStructures.swift
//  Role: Map Phases with the orientations found from the structures alone (mac4DSTEM#184): the structures and the
//        detected disks in, the phase of every position out, no zone axis typed.
//
//  The method is DiffractoKit's `PhaseVectorMatcher.mapFromStructures`: the matrix orientation of every position by
//  template matching, one orientation per grain, the matrix's spots removed, then each candidate's orientations searched,
//  its relationship to the matrix learned from the strong positions and every position scored against the variants
//  (vector matching after Thronsen et al., Ultramicroscopy 255 (2024) 113861; the proposals by template matching after
//  Ophus et al., Microsc. Microanal. 28 (2022) 390). This file only hands the kit its inputs and publishes what it returns.
//

import ShellLayout
import Foundation
#if canImport(DSTEMCore)
import DiffractoCore
import DSTEMCore
import DSTEMSession
#endif
import DiffractoOrientation

/// Why the kit refused a structures run, in its own words.
struct PhaseSearchRefusal: Error, Sendable { let reason: String }

extension AppState {

    /// One line per candidate phase on the relationship a structures run learned for it.
    nonisolated static func learnedRelationshipLines(names: [String], relationships: [[LearnedOrientationRelationship]]) -> [String] {
        zip(names, relationships).map { name, learned in
            guard let best = learned.max(by: { $0.positionCount < $1.positionCount }) else {
                return "\(name): no relationship to the matrix learned (too few strong positions)"
            }
            let spread = String(format: "%.1f", best.spreadRad * 180 / .pi)
            let more = learned.count > 1 ? ", and \(learned.count - 1) more" : ""
            return "\(name): relationship to the matrix learned from \(best.positionCount) positions (spread \(spread)°)\(more)"
        }
    }

    /// Map Phases, orientations from the structures. Called by `runPhaseMapping` after its refusals (stale disks, the
    /// list's own refusal, no disks, no physical Q scale), so none of them is repeated here.
    func runPhaseMappingFromStructures() async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("Open a dataset first.") }
        guard let rawVectors = resultPresentation.braggVectors else { return .failed("Detect Bragg disks first.") }
        let slots = phaseMapping.phases
        guard let matrixSlot = slots.firstIndex(where: \.isMatrix) else { return .failed("Mark one phase as the matrix.") }
        let candidateSlots = slots.indices.filter { !slots[$0].isMatrix }
        guard !candidateSlots.isEmpty else { return .failed("Add a candidate phase to look for.") }

        let referenceSettings = phaseMapping.reference
        let matchSettings = phaseMapping.matching
        let phaseSignature = phaseMapping.phaseSignature
        let calibrated = calibratedBraggVectors(rawVectors, descriptor: descriptor)
        let origin = calibrated.origin.point
        // The reach is the typed path's library reach (the nearest detector edge, at most Max |q|), and the peaks are cut
        // there as for a typed run (`matchingWithinLibraryReach`).
        let reach = phaseLibraryKMax(setting: referenceSettings.kMaxInvAngstrom, origin: origin, descriptor: descriptor)
        let cut = Self.matchingWithinLibraryReach(matchSettings, libraryKMaxInvAngstrom: reach).maximumVectorInvAngstrom
        let settings = StructurePhaseMappingSettings(
            reachInvAngstrom: reach, maximumVectorInvAngstrom: cut,
            matrixToleranceInvAngstrom: matchSettings.matrixToleranceInvAngstrom,
            pairRadiusInvAngstrom: matchSettings.pairRadiusInvAngstrom,
            residualCutoffInvAngstrom: matchSettings.residualCutoffInvAngstrom,
            directBeamRadiusInvAngstrom: matchSettings.directBeamRadiusInvAngstrom)
        let matrix = StructurePhase(name: slots[matrixSlot].model.displayName, crystal: slots[matrixSlot].model.structure)
        // A phase's own excitation slab, or the one default (`structuresExcitationSlabDefault`).
        let slabs = candidateSlots.map { slots[$0].excitationSlabInvAngstrom ?? PhaseMappingProduct.structuresExcitationSlabDefault }
        let candidates = zip(candidateSlots, slabs).map { index, slab in
            StructurePhase(name: slots[index].model.displayName, crystal: slots[index].model.structure, excitationSlabInvAngstrom: slab)
        }

        let calibrationStamp = PhaseMappingProduct.CalibrationStamp(
            calibration: calibrationSession.calibration, referenceOrigin: origin)
        let scale = acomScaleSemantics
        let invAngstromPerPixel = scale.invAngstromPerPixel

        let cancellation = beginCancellableOperation(
            "Phase mapping",
            status: "Finding the matrix orientation of \(calibrated.vectors.peaks.count) patterns…",
            totalUnits: calibrated.vectors.peaks.count
        )
        defer { finishCancellableOperation(cancellation) }
        let epoch = datasetSession.epoch
        let progress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentOperation(cancellation) else { return }
                // The kit reports the matrix step up to 0.6; the search and the classification follow.
                self.updateCancellableOperation(
                    cancellation, progress: fraction,
                    status: fraction < 0.6 ? "Finding the matrix orientation…" : "Searching the phases' orientations…")
            }
        }

        let scan = calibrated.vectors.phaseScan
        let scanWidth = calibrated.vectors.scanWidth, scanHeight = calibrated.vectors.scanHeight
        // The kit's refusal travels as its words: the error type stays in the kit.
        let outcome: Result<StructurePhaseMapping?, PhaseSearchRefusal> = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try PhaseVectorMatcher.mapFromStructures(
                    scan: scan, scanWidth: scanWidth, scanHeight: scanHeight,
                    matrix: matrix, candidates: candidates, settings: settings,
                    originX: origin.x, originY: origin.y, invAngstromPerPixel: invAngstromPerPixel,
                    isCancelled: { cancellation.isCancelled }, progress: progress))
            } catch {
                return .failure(PhaseSearchRefusal(reason: "\(error)"))
            }
        }.value

        guard epoch == datasetSession.epoch else {
            return .failed("The dataset changed while phase mapping was running.")
        }
        let found: StructurePhaseMapping
        switch outcome {
        case .failure(let refusal):
            let reason = "A phase's structure cannot be searched: \(refusal.reason)"
            statusText = reason
            return .failed(reason)
        case .success(nil):
            return .cancelled
        case .success(let value?):
            found = value
        }
        guard let map = PhaseMappingProduct.mapInListOrder(found.map, slotNames: slots.map(\.model.displayName),
                                                           matrixSlot: matrixSlot, candidateSlots: candidateSlots) else {
            return .failed("The phase list changed shape during the run.")
        }
        let learned = Self.learnedRelationshipLines(names: candidates.map(\.name),
                                                    relationships: found.classification.relationships)

        phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: phaseSignature,
            reference: referenceSettings,
            matching: matchSettings,
            libraryEntryCount: 0,
            matrixEntryIndex: -1,
            matrixInPlaneDegrees: .nan,
            worstChanceMatchPercent: 0,
            invAngstromPerPixel: scale.invAngstromPerPixel,
            qScaleIsPhysical: scale.provenance.isPhysical,
            peakCount: rawVectors.totalPeakCount,
            calibration: calibrationStamp,
            libraryKMaxInvAngstrom: reach,
            orientationSource: .structures,
            learnedRelationships: learned,
            excitationSlabs: zip(candidates, slabs).map { "\($0.name): " + String(format: "%.3g", $1) }
        ), structureRun: found)

        // What the run found beyond its map goes to the Output pane (control placement, rule 9).
        for line in learned { activityLog.record("Map Phases: " + line) }
        recordPhaseMappingRun(map: map, run: phaseMapping.lastRun)
        publishPhaseMapProduct()
        await publishPrecipitateClassificationFromPhaseMap()
        let counts = map.phaseCounts
        let indexed = counts.enumerated()
            .filter { $0.offset != map.matrixPhaseIndex && $0.element > 0 }
            .map { "\(map.phaseNames[$0.offset]) \($0.element)" }
            .joined(separator: ", ")
        statusText = "Phase map: \(indexed.isEmpty ? "no candidate phase found" : indexed)"
            + ", matrix \(map.count(of: .matrix)), not indexed \(map.count(of: .notIndexed))"
        return .published
    }
}
