//
//  PrecipitateReportUpdates.swift
//  Role: the app-scoped relay that keeps an open object table current with its own run (`PrecipitateTableSelection` is the same
//        relay the other way). The table window is opened with a report value and has no reference to a dataset window's state;
//        the composition per object is one pooled fit per object and lands after the table may already be open. The dataset
//        window publishes its report here whenever its joins land; a table shows the newest report OF ITS OWN RUN
//        (`PrecipitateObjectReport.sourceID`), so it fills in by itself and never turns into another run's table. Nothing here is
//        persisted.
//

import Foundation
import Observation
import DSTEMSession

@Observable
@MainActor
final class PrecipitateReportUpdates {
    /// The newest report of each classification run, by the run's id.
    private(set) var latest: [UUID: PrecipitateObjectReport] = [:]

    /// A dataset window's report after its joins landed. A report without a run id is not kept (no table can ask for it).
    func publish(_ report: PrecipitateObjectReport) {
        guard let id = report.sourceID, latest[id] != report else { return }
        latest[id] = report
    }

    /// What a table opened with `opened` shows: the newest report of the same run, or `opened` itself.
    func report(for opened: PrecipitateObjectReport) -> PrecipitateObjectReport {
        opened.sourceID.flatMap { latest[$0] } ?? opened
    }

    /// A run that is gone (its window closed or a new run replaced it) is dropped; open tables keep what they last showed.
    func forget(_ id: UUID?) {
        if let id { latest[id] = nil }
    }
}
