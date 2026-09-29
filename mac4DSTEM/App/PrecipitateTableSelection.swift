//
//  PrecipitateTableSelection.swift
//  Role: the one app-scoped relay between the object table window (a snapshot
//        value in its own scene) and the dataset windows' scan pane: which
//        objects the reader has selected, and of which classification run.
//        The table writes it; a dataset window draws an outline from it only
//        when `sourceID` is its own current run's (`AppState.
//        precipitateHighlightOutline(for:)`). Nothing here is persisted.
//

import Foundation
import Observation

@Observable
@MainActor
final class PrecipitateTableSelection {
    /// The run the selected objects belong to (`PrecipitateObjectReport.sourceID`).
    var sourceID: UUID?
    var objectIDs: Set<Int> = []

    func select(_ ids: Set<Int>, of source: UUID?) {
        sourceID = source
        objectIDs = ids
    }

    /// The table closing clears only what it wrote: another table (a newer
    /// run) may hold the relay by then.
    func clear(ifOwnedBy source: UUID?) {
        guard sourceID == source else { return }
        sourceID = nil
        objectIDs = []
    }
}
