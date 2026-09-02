//
//  SessionReplayRecord.swift
//  Role: The serialized half of v2's replay record — which analyses ran, with
//        which parameters, in which order. This is what turns the session
//        sidecar into a full recipe (docs/v2-release.md §1, commitment 3), and
//        what S6's unattended promote replays at full extent.
//
//  WHAT THIS IS NOT. Per-result controls already travel in
//  `SessionResultDescriptor.provenance` (`SessionControlRehydration`) — that
//  mechanism answers "what settings produced THIS saved image". The replay
//  record answers the question that mechanism structurally cannot: the ordered
//  PIPELINE — including steps whose own results were never saved but whose
//  downstream products were (disk detection feeding a saved strain map is the
//  canonical case).
//
//  SEMANTICS, decided v2 S5 (2026-08-24): one step per analysis kind, in
//  FIRST-RUN order; re-running a kind updates its parameters in place. The
//  recipe is "the pipeline you built, with the parameters you settled on" —
//  not a keystroke log (fifty exploratory runs replayed overnight would be a
//  bug, not fidelity). Known limit, stated: two same-kind runs with different
//  parameters keep only the latest; extending to multi-instance steps is
//  S6's call if the owner wants it.
//
//  ABSENCE IS ABSENCE. A sidecar without the attribute yields NO record —
//  never an empty-but-asserted one. This is the `?? .fullExtent` lesson
//  (docs/open-items.md, fabricated provenance): the app must not state a
//  recipe a file does not carry.
//

import Foundation

/// The recorded analysis pipeline of a session. Serialized as a JSON root
/// attribute on the sidecar (`SessionSidecarFormat.replayRecordAttribute`).
package nonisolated struct SessionReplayRecord: Codable, Equatable, Sendable {

    /// One analysis in the pipeline. `kind` matches the result-kind vocabulary
    /// used by `SessionResultDescriptor`; `parameters` is the same flat
    /// string-to-string convention as result provenance, so the two carriers
    /// stay mutually legible.
    package struct Step: Codable, Equatable, Sendable {
        package var kind: String
        package var parameters: [String: String]
        /// When this step's parameters were last settled. Informational — the
        /// ORDER of `steps` is the pipeline order, not the timestamps.
        package var recorded: Date

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(kind: String, parameters: [String: String], recorded: Date) {
            self.kind = kind
            self.parameters = parameters
            self.recorded = recorded
        }
    }

    package var steps: [Step] = []

    package var isEmpty: Bool { steps.isEmpty }

    /// Record a run: first run of a kind appends, a re-run updates that
    /// kind's parameters IN PLACE — first-run order is the pipeline order.
    ///
    /// `invalidating` removes downstream kinds first: a step recorded against
    /// state this run replaces (strain built on superseded disk detection) is
    /// not part of a coherent pipeline any more — keeping it would produce a
    /// recipe that replays neither the saved maps nor anything the user built
    /// (Gate B-lite F4). Re-running the downstream analysis re-records it.
    package mutating func record(kind: String, parameters: [String: String], at date: Date = Date(),
                         invalidating downstream: [String] = []) {
        if !downstream.isEmpty {
            steps.removeAll { downstream.contains($0.kind) }
        }
        if let index = steps.firstIndex(where: { $0.kind == kind }) {
            steps[index].parameters = parameters
            steps[index].recorded = date
        } else {
            steps.append(Step(kind: kind, parameters: parameters, recorded: date))
        }
    }

    // MARK: - Serialization (same conventions as LoadSpecification)

    /// Deterministic JSON: sorted keys and fixed-format dates, so re-encoding
    /// a decoded record is byte-stable — the property `tools/load-spec-roundtrip`
    /// pins for the specification, extended to this record by the same harness.
    package var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        // try? OK (v2 S7 audit): every stored property is Codable-synthesized
        // over strings, numbers and dates — there is no encodable state that
        // can fail to encode, and nil falls through to "write no attribute".
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a record written by `jsonString`. Nil for malformed input —
    /// the caller decides whether that is "no record" or a named failure.
    /// The one production caller (`BraggVectorEMDWriter.loadSession`) REFUSES
    /// on nil for a present attribute (`WriterError.malformedAttribute`) —
    /// a mangled recipe must not read as "no recipe". // v2 S7
    package static func parse(_ json: String) -> SessionReplayRecord? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(SessionReplayRecord.self, from: data)
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(steps: [Step] = []) {
        self.steps = steps
    }
}
