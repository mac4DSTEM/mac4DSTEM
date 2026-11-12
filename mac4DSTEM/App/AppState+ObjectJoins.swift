//
//  AppState+ObjectJoins.swift
//  Role: composition and strain per precipitate object (suite task 42): when the objects, the quantified maps, the registration or
//        the strain map change, the two joins (`ObjectJoins.swift`, ImagoKit's labelled means) are recomputed off the main actor and
//        the result lands only if no newer request was made. The views read the object report, which carries the rows.
//

import Foundation
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import ImagoCore
import SpectroCore
import SpectroEDX
import ShellEDXModel

/// The two joins' results as one value the report is made from.
nonisolated struct PrecipitateJoins: Sendable, Equatable {
    var composition: ObjectJoinResult<ObjectCompositionValue>?
    var strain: ObjectJoinResult<ObjectStrain>?
    var variants: ObjectJoinResult<VariantAssignment>?
    var variantEndOnDirection: Int?
    var variantDirections: [Int]?
}

extension AppState {
    /// Recomputes the composition and strain joins for the standing class map; clears them when there is none. A newer call cancels
    /// the running one and wins, and nothing runs without objects. The composition is one pooled fit per object, so it runs detached.
    func refreshPrecipitateJoins() {
        precipitateJoinGeneration += 1
        let generation = precipitateJoinGeneration
        precipitateJoinTask?.cancel()
        let quantification = Self.objectCompositionInputs(fit: edx.fit, source: edx.source)
        precipitateCompositionKey = quantification?.method.hash
        guard let objects = precipitateClassification.result else {
            assignPrecipitateJoins(PrecipitateJoins())
            return
        }
        // The room has quantified (a fit stands): each object's summed spectrum is fitted with the method that fit ran with.
        let source = quantification?.source, method = quantification?.method ?? edx.method
        let registration = spectroscopy.registration
        let strainMap = strain.map?.presented(in: strainPresentationFrame)
        let variantSettings = precipitateVariantSettings
        let phaseMap = phaseMapping.map, library = phaseMapping.lastLibrary, matrixEntry = phaseMapping.lastRun?.matrixEntryIndex
        // A map made from the structures brings its own orientations (mac4DSTEM#245). The phase list must still be the run's.
        var structureRun: ObjectVariantJoin.StructureRun?
        if let run = phaseMapping.lastStructureRun, let phaseMap, !phaseMapping.isStale, phaseMapping.phases.count == phaseMap.phaseNames.count {
            var next = 0
            let candidateIndex: [Int?] = phaseMapping.phases.map { slot in
                if slot.isMatrix { return nil }
                defer { next += 1 }
                return next
            }
            structureRun = ObjectVariantJoin.StructureRun(
                run: run, crystals: phaseMapping.phases.map(\.model.structure), candidateIndex: candidateIndex,
                reachInvAngstrom: phaseMapping.lastRun?.libraryKMaxInvAngstrom ?? 0,
                pairRadiusInvAngstrom: phaseMapping.lastRun?.matching.pairRadiusInvAngstrom ?? 0.02,
                excitationSlabs: phaseMapping.phases.map { $0.excitationSlabInvAngstrom ?? PhaseMappingProduct.structuresExcitationSlabDefault })
        }
        precipitateJoinTask = Task { @MainActor [weak self] in
            let work = Task.detached(priority: .userInitiated) {
                let quantified = source.map { ObjectCompositionJoin.Quantified(source: $0, method: method, tables: QuantificationTables.bundled()) }
                let variants = variantSettings.map { ObjectVariantJoin.run(objects: objects, map: phaseMap, library: library, matrixEntryIndex: matrixEntry, settings: $0,
                                                                           structureRun: structureRun) }
                return PrecipitateJoins(
                    composition: ObjectCompositionJoin.run(objects: objects, quantified: quantified, registration: registration,
                                                           cancelled: { Task.isCancelled }),
                    strain: ObjectStrainJoin.run(objects: objects, strain: strainMap),
                    variants: variants?.result, variantEndOnDirection: variants?.endOnDirection,
                    variantDirections: variants?.habitFamilies)
            }
            let joins = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, self.precipitateJoinGeneration == generation else { return }
            self.assignPrecipitateJoins(joins)
        }
    }

    /// What the per-object fits take from the room once it has quantified: the spectrum image and the method THE ROOM'S FIT RAN WITH
    /// (`fit.method`). Not the session's `method`: the EDS session puts the picked elements into the method only while a fit runs and
    /// empties the list afterwards, so a fit with `session.method` is refused for every object ("No element is switched on"), which is
    /// what the object table showed on screen after #158. Nil until a fit stands.
    nonisolated static func objectCompositionInputs(fit: PooledQuantification?, source: (any SpectrumImageSource)?)
        -> (source: any SpectrumImageSource, method: QuantificationMethod)? {
        guard let fit, let source else { return nil }
        return (source, fit.method)
    }

    /// The composition per object is fitted with the Spectroscopy room's method, so it follows the room: when a fit first stands, goes
    /// away, or the method changes (elements, k-factors, absorption), the joins are recomputed. A new region's fit with the same method
    /// changes nothing here. Set once (`wirePoolHooks`); each change re-arms the watch.
    func watchEDSQuantificationForObjectJoins() {
        withObservationTracking {
            _ = edx.fit?.method
            _ = edx.source == nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let key = Self.objectCompositionInputs(fit: self.edx.fit, source: self.edx.source)?.method.hash
                if key != self.precipitateCompositionKey { self.refreshPrecipitateJoins() }
                self.watchEDSQuantificationForObjectJoins()
            }
        }
    }
}
