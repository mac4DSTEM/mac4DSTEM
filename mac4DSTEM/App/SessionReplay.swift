//
//  SessionReplay.swift
//  Role: The live half of the replay record — the recipe of this session's
//        analyses as they run, adopted from the sidecar on restore, handed to
//        the writer on every save.
//
//  This is v2 S5's `AppState` seam (docs/development-process.md §7): the state
//  the stage ADDS, in its own `@Observable` type that `AppState` holds — the
//  `DatasetResidency` / `PendingLoad` precedent, no forwarding properties.
//  The serialized format lives in `Core/Data/SessionReplayRecord.swift`; this
//  type owns the session-lifetime mutations and nothing else.
//

import Foundation

@Observable
final class SessionReplay {

    /// The recipe as currently known. Starts empty; `adopt` replaces it with
    /// a restored record; analyses append/update through `record(kind:...)`.
    private(set) var record = SessionReplayRecord()

    /// Which detector frame the record's parameters are expressed in — session
    /// state, never serialized (the sidecar's load specification carries the
    /// frame for a restored recipe; this tracks it once adopted, and merges to
    /// `.mixed` if steps are later recorded under a different one). Nil while
    /// the record is empty. Consulted once, by S6's replay executor. // v2 S6
    private(set) var parameterFrame: ReplayParameterFrame?

    /// What a save should carry. **Nil when empty** — writing an empty record
    /// would erase whatever recipe the file already carries (the writer
    /// preserves the existing record when handed nil), and an empty record
    /// asserts nothing worth asserting.
    var recordForSaving: SessionReplayRecord? {
        record.isEmpty ? nil : record
    }

    /// One analysis completed with these parameters. First run of a kind
    /// appends; a re-run updates in place; `invalidating` names downstream
    /// kinds whose recorded steps were built on the state this run replaces
    /// (`SessionReplayRecord.record`).
    func record(kind: String, parameters: [String: String],
                invalidating downstream: [String] = [],
                under frame: ReplayParameterFrame) {
        let wasEmpty = record.isEmpty
        record.record(kind: kind, parameters: parameters, invalidating: downstream)
        // A first step sets the frame; later steps merge — two different
        // detector frames in one record is `.mixed`, permanently, and the
        // replay refuses detector-frame steps rather than guessing which
        // frame each number meant. // v2 S6
        parameterFrame = wasEmpty ? frame : parameterFrame?.merging(frame) ?? frame
    }

    /// A sidecar restore produced a recipe: it becomes this session's
    /// starting point, so a later save round-trips a colleague's recipe
    /// instead of replacing it with only this session's steps. Nil (no
    /// recorded recipe in the file) leaves the current record alone —
    /// absence is absence. `recordedOn` is the frame the restored record's
    /// parameters are expressed in — the sidecar's own load specification,
    /// or a captured pre-promote frame on the promote path. // v2 S6
    func adopt(_ restored: SessionReplayRecord?, recordedOn frame: ReplayParameterFrame?) {
        guard let restored else { return }
        record = restored
        parameterFrame = frame
    }

    /// Dataset change: the recipe belongs to the session it was built in.
    func reset() {
        record = SessionReplayRecord()
        parameterFrame = nil
    }
}
