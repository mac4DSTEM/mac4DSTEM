//
//  SessionProductOrigin.swift
//  mac4DSTEM
//
//  The wording of the Info tab's "In memory" rows, kept out of the Frozen
//  Shell file that draws them (WorkspaceInspector.swift, ADR 035).
//

import DSTEMCore
import DSTEMSession

/// What each row of the in-memory list says about WHERE its value came from —
/// wording only, so a value restored from a file or a session is never read as
/// something this session computed (S12; "Computed this session" was a bare
/// predicate on what exists, 2026-09-11). Pure, so it is unit-tested.
enum SessionProductOrigin {
    static func originCalibration(_ provenance: OriginProvenance) -> String? {
        switch provenance {
        case .fitted: "fitted here"
        case .sessionMean, .sessionMaps: "restored from session"
        case .fileMean, .fileMaps: "from file"
        case .manual: "set by hand"
        case .geometricDefault: nil
        }
    }

    static func rotation(_ provenance: CalibrationValueProvenance?) -> String? {
        switch provenance {
        case .measuredInApp: "measured here"
        case .sessionSidecar: "restored from session"
        case .importedFile: "from file"
        case .manual: "set by hand"
        case .mixed, .fitAnyway, nil: nil
        }
    }

    /// `computedThisSession` is "a detection run wrote its summary"
    /// (`AppState.completedDiskSummary`): a session restore sets the peaks and
    /// their count, never the summary.
    static func braggDisks(peakCount: Int?, computedThisSession: Bool) -> String? {
        guard let peakCount else { return nil }
        // The same grouped count as the status bar and "Peaks found" (drive, 2026-09-30 night).
        let count = SystemMonitor.count(peakCount)
        return computedThisSession ? "\(count) peaks" : "\(count) peaks · restored"
    }
}
