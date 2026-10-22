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

/// The two joins' results as one value the report is made from.
nonisolated struct PrecipitateJoins: Sendable, Equatable {
    var composition: ObjectJoinResult<ObjectCompositionValue>?
    var strain: ObjectJoinResult<ObjectStrain>?
}

extension AppState {
    /// Recomputes the composition and strain joins for the standing class map; clears them when there is none. Cheap to call: a
    /// newer call wins, and nothing runs without objects.
    func refreshPrecipitateJoins() {
        precipitateJoinGeneration += 1
        let generation = precipitateJoinGeneration
        guard let objects = precipitateClassification.result else {
            assignPrecipitateJoins(PrecipitateJoins())
            return
        }
        let maps = spectroscopyRoom.lastQuantMaps
        let registration = spectroscopy.registration
        let strainMap = strain.map?.presented(in: strainPresentationFrame)
        Task { @MainActor [weak self] in
            let joins = await Task.detached(priority: .userInitiated) {
                PrecipitateJoins(
                    composition: ObjectCompositionJoin.run(objects: objects, maps: maps, registration: registration),
                    strain: ObjectStrainJoin.run(objects: objects, strain: strainMap))
            }.value
            guard let self, self.precipitateJoinGeneration == generation else { return }
            self.assignPrecipitateJoins(joins)
        }
    }
}
