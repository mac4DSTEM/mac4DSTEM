//
//  SessionReplay.swift
//  Role: The live half of the replay record — the recipe of this session's
//        analyses as they run, adopted from the sidecar on restore, handed to
//        the writer on every save.
//
//  An `AppState` seam (docs/archive/development-process-2026-08-31.md §7): the state
//  this stage adds lives in its own `@Observable` type that `AppState` holds —
//  the `DatasetResidency` / `PendingLoad` precedent, no forwarding properties.
//  The serialized format lives in `Core/Data/SessionReplayRecord.swift`; this
//  type owns the session-lifetime mutations and nothing else.
//
//  LINEAGE (ADR 047, L1). The live source of truth is the run graph
//  (`Core/Data/SessionLineage.swift`), owned HERE — no new `AppState` storage.
//  `record` is its projection, recomputed after every mutation, so the linear
//  recipe every existing reader (`ReplayPlanner`, the promote caption, the
//  sidebar) sees is derived, not kept in step by hand. The lineage rides along
//  `recordForSaving` to the writer.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

@Observable
package final class SessionReplay {

    // Explicit so the default initializer is `package` (synthesized ones are internal).
    package nonisolated init() {}

    /// The run graph as currently known (ADR 047). Starts empty; `adopt`
    /// replaces it with a restored (or synthesized-v1) graph; every completed
    /// run is recorded through `record(kind:...)`.
    package private(set) var lineage = SessionLineage()

    /// The recipe as currently known — the PROJECTION of `lineage`: the active
    /// node of each replayable kind. Carries no lineage of its own.
    package private(set) var record = SessionReplayRecord()

    /// Which detector frame the record's parameters are expressed in — session
    /// state, never serialized (the sidecar's load specification carries the
    /// frame for a restored recipe; this tracks it once adopted, and merges to
    /// `.mixed` if steps are later recorded under a different one). Nil while
    /// the record is empty. Consulted once, by the replay executor.
    package private(set) var parameterFrame: ReplayParameterFrame?

    /// What a save should carry: the recipe with the lineage it is the
    /// projection of attached. **Nil when the lineage is empty** — writing
    /// nothing would erase whatever recipe the file already carries (the writer
    /// preserves the existing record when handed nil), and an empty session
    /// asserts nothing worth asserting. A session whose only runs were
    /// calibrations has an empty recipe but a lineage, and is saved as both.
    package var recordForSaving: SessionReplayRecord? {
        lineage.isEmpty ? nil : SessionReplayRecord(steps: record.steps, lineage: lineage)
    }

    /// One analysis completed with these parameters. A replayable kind
    /// (`SessionLineage.lineageOnlyKinds` says which are not) updates the
    /// linear recipe exactly as before — first run appends, a re-run updates in
    /// place, `SessionLineage.downstreamKinds` drops what the run supersedes —
    /// but by way of the lineage, whose collapse rule (R3) decides between
    /// replacing the active node of that kind and adding a branch.
    ///
    /// `downstream` is the caller's own statement of what it supersedes and is
    /// **not consulted**: the mapping lives in one table, and a run site that
    /// disagreed with it would fork the projection from the graph. The
    /// parameter stays so a call site keeps saying what it means.
    ///
    /// `external` names CIFs the run took from outside the session when the
    /// run's own parameters do not (`SessionLineage.externalInputs`);
    /// `extraInputs` are edges only the run site knows (an export's sources).
    @discardableResult
    package func record(kind: String, parameters: [String: String],
                invalidating downstream: [String] = [],
                external: [SessionLineage.External] = [],
                extraInputs: [SessionLineage.Input] = [],
                under frame: ReplayParameterFrame) -> String {
        let wasEmpty = record.isEmpty
        let nodeFrame: SessionLineage.Frame? = switch frame {
        case .detectorIdentity: SessionLineage.Frame()
        case .detectorReduced(let bin, let crop): SessionLineage.Frame(bin: bin, crop: crop)
        case .mixed, .unknown: nil
        }
        let id = lineage.recordRun(kind: kind, parameters: parameters, frame: nodeFrame,
                                   external: external, extraInputs: extraInputs)
        record = lineage.projection()
        // A calibration or a product node carries no recipe parameters, so it
        // says nothing about the frame the recipe is expressed in. A first
        // recipe step sets the frame; later steps merge — two different
        // detector frames in one record is `.mixed`, permanently, and the
        // replay refuses detector-frame steps rather than guessing which
        // frame each number meant.
        if !SessionLineage.lineageOnlyKinds.contains(kind) {
            parameterFrame = wasEmpty ? frame : parameterFrame?.merging(frame) ?? frame
        }
        return id
    }

    /// A run's product was saved under this result node name: its node stops
    /// being collapsible (R3).
    package func markProduct(step id: String, as name: String) {
        lineage.markProduct(step: id, as: name)
    }

    package func restoreProduct(step id: String, to previous: String?) {
        lineage.restoreProduct(step: id, to: previous)
    }

    /// A sidecar restore produced a recipe (and the lineage it projects from,
    /// synthesized in memory from v1): it becomes this session's starting
    /// point, so a later save round-trips a colleague's recipe instead of
    /// replacing it with only this session's steps. Nil (no recorded recipe in
    /// the file) leaves the current record alone — absence is absence.
    /// `recordedOn` is the frame the restored record's parameters are
    /// expressed in — the sidecar's own load specification, or a captured
    /// pre-promote frame on the promote path.
    ///
    /// A `restoredLineage` is taken only when its projection IS the restored
    /// record (the loader guarantees it; the promote path restates its own
    /// pair). Anything else is a record with no graph behind it: the graph is
    /// synthesized from the record, `source: "v1"`, inputs absent.
    package func adopt(_ restored: SessionReplayRecord?, lineage restoredLineage: SessionLineage? = nil,
                       recordedOn frame: ReplayParameterFrame?) {
        if let restoredLineage, !restoredLineage.isEmpty,
           restored == nil || SessionLineage.sameSteps(restoredLineage.projection().steps, restored?.steps ?? []) {
            lineage = restoredLineage
            record = lineage.projection()
        } else if let restored {
            let nodeFrame: SessionLineage.Frame? = switch frame {
            case .detectorIdentity?: SessionLineage.Frame()
            case .detectorReduced(let bin, let crop)?: SessionLineage.Frame(bin: bin, crop: crop)
            default: nil
            }
            lineage = SessionLineage.synthesized(from: restored, frame: nodeFrame)
            record = SessionReplayRecord(steps: restored.steps)
        } else {
            return
        }
        if !record.isEmpty { parameterFrame = frame }
    }

    /// Dataset change: the recipe belongs to the session it was built in.
    package func reset() {
        lineage = SessionLineage()
        record = SessionReplayRecord()
        parameterFrame = nil
    }
}
