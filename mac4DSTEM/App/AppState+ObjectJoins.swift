//
//  AppState+ObjectJoins.swift
//  Role: composition and strain per precipitate object (suite task 42): when the objects, the quantified maps, the registration or
//        the strain map change, the two joins (`ObjectJoins.swift`, ImagoKit's labelled means) are recomputed off the main actor and
//        the result lands only if no newer request was made. The views read the object report, which carries the rows.
//

import Foundation
import DSTEMCore
import DSTEMSession
import ImagoCore
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
        precipitateCompositionKey = edx.fit != nil ? edx.method.hash : nil
        guard let objects = precipitateClassification.result else {
            assignPrecipitateJoins(PrecipitateJoins())
            return
        }
        // The room has quantified (a fit stands): each object's summed spectrum is fitted with the room's method.
        let source = edx.fit != nil ? edx.source : nil, method = edx.method
        let registration = spectroscopy.registration
        let strainMap = strain.map?.presented(in: strainPresentationFrame)
        let variantSettings = precipitateVariantSettings
        let phaseMap = phaseMapping.map, library = phaseMapping.lastLibrary, matrixEntry = phaseMapping.lastRun?.matrixEntryIndex
        precipitateJoinTask = Task { @MainActor [weak self] in
            let work = Task.detached(priority: .userInitiated) {
                let quantified = source.map { ObjectCompositionJoin.Quantified(source: $0, method: method, tables: QuantificationTables.bundled()) }
                let variants = variantSettings.map { ObjectVariantJoin.run(objects: objects, map: phaseMap, library: library, matrixEntryIndex: matrixEntry, settings: $0) }
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

    /// The composition per object is fitted with the Spectroscopy room's method, so it follows the room: when a fit first stands, goes
    /// away, or the method changes (elements, k-factors, absorption), the joins are recomputed. A new region's fit with the same method
    /// changes nothing here. Set once (`wirePoolHooks`); each change re-arms the watch.
    func watchEDSQuantificationForObjectJoins() {
        withObservationTracking {
            _ = edx.fit == nil
            _ = edx.method
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if (self.edx.fit != nil ? self.edx.method.hash : nil) != self.precipitateCompositionKey { self.refreshPrecipitateJoins() }
                self.watchEDSQuantificationForObjectJoins()
            }
        }
    }
}
