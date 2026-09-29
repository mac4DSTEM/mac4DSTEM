//
//  SessionLineage.swift
//  Role: The session record, version 2 — a graph whose nodes are RUNS
//        (docs/decisions/047-lineage-graph-record-v2.md, phase L1). Pure
//        data and pure rules: no SwiftUI, no AppState, no HDF5.
//
//  WHAT IT ADDS to `SessionReplayRecord`. The linear record keeps one step per
//  kind and overwrites; this keeps every run that mattered, with an id
//  (`s1`, `s2`, … from `next_id`, never reused), the runs it consumed (`inputs`
//  with a role), the CIFs that came from outside the session (`external`, a
//  file name and a content fingerprint, never a path), the detector frame it
//  ran under, and its parameters — the same flat string-to-string snapshot the
//  record holds.
//
//  THE LINEAR RECORD STAYS, DERIVED (R6). `projection()` is the record an older
//  build reads: the active node of each replayable kind, in the order
//  `SessionReplayRecord.record` gives — first-run order, a re-run in place, and
//  the downstream kinds of a re-detection dropped (`downstreamKinds`, the
//  former `invalidating:` list). `SessionLineageTests` runs every sequence the
//  record's own tests run through both and compares.
//
//  THE COLLAPSE RULE (R3). A re-run of kind K whose inputs equal the active K
//  node's REPLACES it when it has no children and no saved product, so slider
//  exploration stays one node (the v2 S5 "not a keystroke log" rule); anything
//  else is a new node that becomes active, and the old node stays as another
//  branch. There is no rewind in L1 (R4 is L4): "active" is derived by the
//  fold in `activeNodes()`, from the nodes alone, so a file needs no flag.
//
//  ABSENCE IS ABSENCE (R7). `inputs` is optional: nil (key omitted) is a v1
//  node whose inputs the file never said; `[]` is a node known to consume
//  nothing. The two are never equal, so a v1 node is never collapsed into by a
//  live run and never drawn as a chain.
//
//  READING IS GUARDED (R8). `validated(_:)` refuses, by named reason, a string
//  over 4 MiB, more than 2 000 nodes, a duplicate id, an input id that is not
//  a node, a cycle, a `head` or `next_id` that contradicts the nodes (or a
//  `next_id` above 1 000 000). An unknown `kind` is kept as an opaque node.
//  Never a partial graph. A VERSION this build does not know is named
//  (`unsupportedVersion`) but is not a refusal of the file: the sidecar reader
//  reads it as v1, with a note. THE WRITER runs the same checks on the way out
//  (`writable`): a file this build writes is a file this build reads.
//

import Foundation

/// The recorded lineage of a session. Serialized as one JSON root attribute
/// (`SessionSidecarFormat.lineageAttribute`).
package nonisolated struct SessionLineage: Codable, Equatable, Sendable {

    // MARK: - Limits (R8)

    package static let currentVersion = 2
    /// The reader's length cap for the attribute, in UTF-8 bytes.
    package static let maximumJSONBytes = 4 * 1024 * 1024
    package static let maximumNodes = 2000
    /// The reader's bound on `next_id`, and the recorder's on minting: a run
    /// mints an id only while `nextID < maximumNextID`, so the value a file
    /// carries after any mint is still one the reader accepts. A million runs
    /// in one session is not a session; the bound exists so a hostile
    /// `next_id` cannot make the next `+= 1` trap.
    package static let maximumNextID = 1_000_000

    // MARK: - Vocabulary

    /// An edge to a node this run consumed. `role` is one of `peaks`,
    /// `calibration`, `phases`, `objects` (a foreign role is kept as written).
    package nonisolated struct Input: Codable, Equatable, Sendable {
        package var step: String
        package var role: String

        package nonisolated init(step: String, role: String) {
            self.step = step
            self.role = role
        }
    }

    /// A file from outside the session — a CIF by NAME and content
    /// fingerprint, never an absolute path (the repo is public, sidecars travel).
    package nonisolated struct External: Codable, Equatable, Sendable {
        package var name: String
        package var fingerprint: String

        package nonisolated init(name: String, fingerprint: String) {
            self.name = name
            self.fingerprint = fingerprint
        }
    }

    /// The detector frame a run's pixel-valued parameters are expressed in.
    package nonisolated struct Frame: Codable, Equatable, Sendable {
        package var bin: Int
        package var crop: AxisCrop?

        package nonisolated init(bin: Int = 1, crop: AxisCrop? = nil) {
            self.bin = bin
            self.crop = crop
        }

        /// The frame a load specification puts detector-pixel parameters in.
        package nonisolated init(_ specification: LoadSpecification) {
            self.init(bin: specification.detectorBin, crop: specification.detectorCrop)
        }
    }

    /// One completed run.
    package nonisolated struct Node: Codable, Equatable, Sendable {
        package var id: String
        /// The result-kind vocabulary of `SessionReplayRecord.Step.kind`, plus
        /// `calibration_origin`, `calibration_ellipse`, `calibration_q`,
        /// `diffraction_groups`, `phase_mapping`, `precipitate_objects`, `export`.
        /// An unknown kind is opaque, not an error.
        package var kind: String
        /// Runs this one consumed. **Nil = the file never said** (v1); `[]` =
        /// consumed nothing.
        package var inputs: [Input]?
        package var external: [External]
        /// Nil when the frame is unknown (a v1 record from a file with no
        /// recorded specification is identity, so nil only follows a live
        /// run under a mixed or unknown frame).
        package var frame: Frame?
        package var parameters: [String: String]
        /// The saved result node this run produced, once it is saved. Nil until then.
        package var product: String?
        package var recorded: Date
        /// `live` (recorded by this build) or `v1` (synthesized from a linear record).
        package var source: String

        package nonisolated init(
            id: String, kind: String, inputs: [Input]?, external: [External] = [],
            frame: Frame?, parameters: [String: String], product: String? = nil,
            recorded: Date, source: String
        ) {
            self.id = id
            self.kind = kind
            self.inputs = inputs
            self.external = external
            self.frame = frame
            self.parameters = parameters
            self.product = product
            self.recorded = recorded
            self.source = source
        }
    }

    package private(set) var version: Int = SessionLineage.currentVersion
    /// The next id to hand out. Never decreases, so an id is never reused.
    package private(set) var nextID: Int = 1
    /// The node recorded (or collapsed into) last. Not "the active path" — that is derived.
    package private(set) var head: String?
    package private(set) var nodes: [Node] = []

    private enum CodingKeys: String, CodingKey {
        case version, head, nodes
        case nextID = "next_id"
    }

    package var isEmpty: Bool { nodes.isEmpty }

    package nonisolated init() {}

    // MARK: - The kind tables

    /// Kinds that exist only in the lineage. The linear record — which an older
    /// build feeds to `ReplayPlanner`, which refuses a kind it cannot run —
    /// carries none of these. Any other kind, known or not, projects.
    package static let lineageOnlyKinds: Set<String> = [
        "calibration_origin", "calibration_ellipse", "calibration_q",
        "diffraction_groups", "phase_mapping", "precipitate_objects", "export",
    ]

    /// What a re-run of a kind takes off the active path: **the mapping that
    /// replaces `invalidating:`**. Detecting disks again supersedes the strain
    /// and ACOM steps built on the old peaks (Gate B-lite F4) — and, in the
    /// lineage, the phase map and objects built on them. Deliberately no
    /// calibration kind here: the record has never dropped a step because a
    /// calibration was refitted, and the projection must equal it (R6).
    package static let downstreamKinds: [String: [String]] = [
        "disk_detection": ["strain", "acom", "phase_mapping", "precipitate_objects"],
        "phase_mapping": ["precipitate_objects"],
    ]

    package nonisolated struct Dependency: Sendable {
        package let role: String
        package let kind: String
    }

    /// Which active node a new run of a kind consumes, and in which role.
    /// The edges are recorded at run time from what is active THEN.
    package static let inputPolicy: [String: [Dependency]] = [
        "calibration_ellipse": [Dependency(role: "calibration", kind: "calibration_origin")],
        "calibration_q": [Dependency(role: "peaks", kind: "disk_detection"),
                          Dependency(role: "calibration", kind: "calibration_origin")],
        "disk_detection": [Dependency(role: "calibration", kind: "calibration_origin")],
        "dpc": [Dependency(role: "calibration", kind: "calibration_origin")],
        "strain": [Dependency(role: "peaks", kind: "disk_detection"),
                   Dependency(role: "calibration", kind: "calibration_origin"),
                   Dependency(role: "calibration", kind: "calibration_ellipse")],
        "acom": [Dependency(role: "peaks", kind: "disk_detection"),
                 Dependency(role: "calibration", kind: "calibration_origin"),
                 Dependency(role: "calibration", kind: "calibration_ellipse"),
                 Dependency(role: "calibration", kind: "calibration_q")],
        "phase_mapping": [Dependency(role: "peaks", kind: "disk_detection"),
                          Dependency(role: "calibration", kind: "calibration_origin"),
                          Dependency(role: "calibration", kind: "calibration_ellipse"),
                          Dependency(role: "calibration", kind: "calibration_q")],
        "precipitate_objects": [Dependency(role: "phases", kind: "phase_mapping")],
    ]

    /// The CIFs a run took from outside the session, when its own parameters
    /// say so (ACOM records an imported model's id — the file stem — and its
    /// content fingerprint). A run whose parameters do not say has none here;
    /// the run site passes what only it knows (phase mapping's phase list).
    package static func externalInputs(kind: String, parameters: [String: String]) -> [External] {
        guard kind == "acom", let name = parameters["material"],
              let fingerprint = parameters["material_fingerprint"] else { return [] }
        return [External(name: name, fingerprint: fingerprint)]
    }

    // MARK: - The active nodes and the projection (R6)

    /// The active node of each kind, in record order. Folded over the nodes in
    /// id order with exactly the semantics of `SessionReplayRecord.record`: a
    /// node of a kind already active replaces it IN PLACE; a new kind appends;
    /// and a node first takes its `downstreamKinds` off the path (a removed
    /// kind that returns later is appended, as a deleted step was).
    package func activeNodes() -> [Node] { Self.activeNodes(in: nodes) }

    private static func activeNodes(in nodes: [Node]) -> [Node] {
        var order: [String] = []
        var latest: [String: Int] = [:]
        for (index, node) in nodes.enumerated() {
            for downstream in downstreamKinds[node.kind] ?? [] {
                if latest.removeValue(forKey: downstream) != nil {
                    order.removeAll { $0 == downstream }
                }
            }
            if latest[node.kind] == nil { order.append(node.kind) }
            latest[node.kind] = index
        }
        return order.compactMap { latest[$0].map { nodes[$0] } }
    }

    /// The linear record an older build reads: the active node of each
    /// replayable kind. Carries no lineage of its own.
    package func projection() -> SessionReplayRecord {
        SessionReplayRecord(steps: activeNodes()
            .filter { !Self.lineageOnlyKinds.contains($0.kind) }
            .map { SessionReplayRecord.Step(kind: $0.kind, parameters: $0.parameters,
                                            recorded: $0.recorded) })
    }

    package func node(id: String) -> Node? { nodes.first { $0.id == id } }

    package func hasChildren(_ id: String) -> Bool {
        nodes.contains { ($0.inputs ?? []).contains { $0.step == id } }
    }

    // MARK: - Recording (R1–R3)

    /// One run completed. Returns the id of the node that now stands for it
    /// (an existing id when the run collapsed, R3). `extraInputs` are edges only
    /// the run site knows (an export's source); the policy supplies the rest.
    @discardableResult
    package mutating func recordRun(
        kind: String, parameters: [String: String], frame: Frame?,
        external: [External] = [], extraInputs: [Input] = [], at date: Date = Date()
    ) -> String {
        let active = activeNodes()
        var inputs: [Input] = []
        for dependency in Self.inputPolicy[kind] ?? [] {
            if let upstream = active.first(where: { $0.kind == dependency.kind }) {
                inputs.append(Input(step: upstream.id, role: dependency.role))
            }
        }
        inputs.append(contentsOf: extraInputs)
        let external = external.isEmpty ? Self.externalInputs(kind: kind, parameters: parameters)
                                        : external

        if let previous = active.first(where: { $0.kind == kind }),
           let index = nodes.firstIndex(where: { $0.id == previous.id }),
           nodes[index].inputs == inputs, nodes[index].external == external,
           nodes[index].product == nil, !hasChildren(previous.id) {
            nodes[index].parameters = parameters
            nodes[index].frame = frame
            nodes[index].recorded = date
            nodes[index].source = "live"
            head = previous.id
            return previous.id
        }
        if nodes.count >= Self.maximumNodes { pruneToFit() }
        guard nodes.count < Self.maximumNodes, nextID < Self.maximumNextID else {
            // Full, and nothing prunable (every node is active or an ancestor of
            // one, or the ids are spent). Unreachable by any session this app
            // can run; what it must not do is write a file its own reader
            // refuses or trap on the counter. The run replaces the active node
            // of its kind in place, or — with none — leaves the graph as it was.
            if let previous = active.first(where: { $0.kind == kind }),
               let index = nodes.firstIndex(where: { $0.id == previous.id }) {
                nodes[index].parameters = parameters
                nodes[index].frame = frame
                nodes[index].recorded = date
                nodes[index].source = "live"
                head = previous.id
                return previous.id
            }
            return head ?? ""
        }
        let id = "s\(nextID)"
        nextID += 1   // < maximumNextID, so this cannot overflow
        nodes.append(Node(id: id, kind: kind, inputs: inputs, external: external, frame: frame,
                          parameters: parameters, recorded: date, source: "live"))
        head = id
        return id
    }

    /// A run's product was saved under this result node name. The node is no
    /// longer collapsible (R3) — a saved map must keep its parameters.
    package mutating func markProduct(step id: String, as name: String) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].product = name
    }

    /// Put a node's product back as it was (nil = none) — the undo of
    /// `markProduct` when the save it announced did not happen.
    package mutating func restoreProduct(step id: String, to previous: String?) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].product = previous
    }

    /// The lineage kind whose run produces a result of this product kind
    /// (`virtual_annular` ← `virtual_detector`, `strain_exx` ← `strain`, …), or
    /// nil for a product no recorded run stands behind.
    package static func lineageKind(forProductKind kind: String) -> String? {
        if kind.hasPrefix("virtual_") { return "virtual_detector" }
        if kind.hasPrefix("strain") { return "strain" }
        if kind.hasPrefix("acom") { return "acom" }
        if kind.hasPrefix("dpc") || kind.hasPrefix("idpc") { return "dpc" }
        if kind == "phase_map" || kind == "phase_match_distance" { return "phase_mapping" }
        if kind == "precipitate_objects" { return "precipitate_objects" }
        if kind == "diffraction_groups" { return "diffraction_groups" }
        if kind == "bragg_vector_map" { return "disk_detection" }
        return nil
    }

    /// Room for one more node without exceeding the reader's cap: drop inactive
    /// leaves (nothing consumes them), oldest first, repeating as parents
    /// become leaves; saved products go last. A node goes only if the active
    /// list — its members AND their order — is unchanged by its going: an
    /// earlier same-kind node is what holds a kind's position in the fold
    /// (`disks, dpc, …, disks` is `[disks, dpc]`; without the first `disks` it
    /// would be `[dpc, disks]`), and the projection must not reorder.
    private mutating func pruneToFit() {
        for protectProducts in [true, false] {
            var changed = true
            while nodes.count >= Self.maximumNodes && changed {
                changed = false
                let active = Self.activeNodes(in: nodes).map(\.id)
                let activeIDs = Set(active)
                let consumed = Set(nodes.flatMap { ($0.inputs ?? []).map(\.step) })
                for index in nodes.indices {
                    let node = nodes[index]
                    guard !activeIDs.contains(node.id), !consumed.contains(node.id),
                          !(protectProducts && node.product != nil) else { continue }
                    var trial = nodes
                    trial.remove(at: index)
                    if Self.activeNodes(in: trial).map(\.id) == active {
                        nodes = trial
                        changed = true
                        break
                    }
                }
            }
        }
    }

    // MARK: - v1 sidecars (R7)

    /// Nodes synthesized IN MEMORY from a linear record: ids in record order,
    /// `source: "v1"`, `inputs` absent. Nothing here asserts an edge the file
    /// never said, and nothing writes until the first save.
    package static func synthesized(from record: SessionReplayRecord, frame: Frame?) -> SessionLineage {
        var lineage = SessionLineage()
        for step in record.steps {
            // A linear record longer than the reader's node cap is no session
            // this app wrote; keep the ones that fit rather than trap or write
            // a graph the reader refuses.
            guard lineage.nodes.count < maximumNodes else { break }
            let id = "s\(lineage.nextID)"
            lineage.nextID += 1
            lineage.nodes.append(Node(
                id: id, kind: step.kind, inputs: nil,
                external: externalInputs(kind: step.kind, parameters: step.parameters),
                frame: frame, parameters: step.parameters, recorded: step.recorded, source: "v1"))
            lineage.head = id
        }
        return lineage
    }

    // MARK: - Serialization (R5)

    /// Deterministic JSON — sorted keys, dates in seconds — so re-encoding a
    /// decoded lineage is byte-stable, the property `tools/load-spec-roundtrip`
    /// pins for the specification and the record.
    package var jsonString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        // try? OK: every stored property is Codable-synthesized over strings,
        // numbers and dates — there is no encodable state that can fail, and
        // nil falls through to "write no attribute".
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Why the reader refused an attribute. The caller turns any of these into
    /// `WriterError.malformedAttribute(name:)`; the reason is for tests and logs.
    package nonisolated enum Refusal: Error, Equatable, CustomStringConvertible {
        case tooLarge(bytes: Int)
        case undecodable
        case unsupportedVersion(Int)
        case tooManyNodes(Int)
        case emptyID
        case duplicateID(String)
        case danglingInput(step: String, from: String)
        case cycle
        case badHead(String)
        case badNextID(nextID: Int, maxNumericID: Int)

        package var description: String {
            switch self {
            case .tooLarge(let bytes): "the lineage is \(bytes) bytes, over the \(SessionLineage.maximumJSONBytes)-byte cap"
            case .undecodable: "the lineage is not a decodable lineage object"
            case .unsupportedVersion(let version): "the lineage version \(version) is not one this build reads"
            case .tooManyNodes(let count): "the lineage has \(count) nodes, over the \(SessionLineage.maximumNodes)-node cap"
            case .emptyID: "a lineage node has an empty id"
            case .duplicateID(let id): "the lineage id \(id) appears twice"
            case .danglingInput(let step, let from): "node \(from) consumes \(step), which is not a node"
            case .cycle: "the lineage has a cycle"
            case .badHead(let id): "the lineage head \(id) is not a node"
            case .badNextID(let next, let maximum): "next_id \(next) is not above the highest id (s\(maximum)) and within \(SessionLineage.maximumNextID)"
            }
        }
    }

    /// Decode and validate. Never a partial graph: the first failed check refuses.
    package static func validated(_ json: String) -> Result<SessionLineage, Refusal> {
        let byteCount = json.utf8.count
        guard byteCount <= maximumJSONBytes else { return .failure(.tooLarge(bytes: byteCount)) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        // The version first, from a probe that reads nothing else: a future
        // version may reshape its nodes, and must be recognised as FUTURE, not
        // refused as undecodable (the caller reads such a file as v1).
        struct VersionProbe: Decodable { let version: Int }
        guard let data = json.data(using: .utf8),
              let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            return .failure(.undecodable)
        }
        guard probe.version == currentVersion else { return .failure(.unsupportedVersion(probe.version)) }
        guard let lineage = try? decoder.decode(SessionLineage.self, from: data) else {
            return .failure(.undecodable)
        }
        guard lineage.nodes.count <= maximumNodes else {
            return .failure(.tooManyNodes(lineage.nodes.count))
        }
        var seen = Set<String>()
        var maximumNumeric = 0
        for node in lineage.nodes {
            guard !node.id.isEmpty else { return .failure(.emptyID) }
            guard seen.insert(node.id).inserted else { return .failure(.duplicateID(node.id)) }
            if node.id.hasPrefix("s"), let number = Int(node.id.dropFirst()) {
                maximumNumeric = max(maximumNumeric, number)
            }
        }
        for node in lineage.nodes {
            for input in node.inputs ?? [] where !seen.contains(input.step) {
                return .failure(.danglingInput(step: input.step, from: node.id))
            }
        }
        if let head = lineage.head, !seen.contains(head) { return .failure(.badHead(head)) }
        guard lineage.nextID > maximumNumeric, lineage.nextID <= maximumNextID else {
            return .failure(.badNextID(nextID: lineage.nextID, maxNumericID: maximumNumeric))
        }
        guard !lineage.hasCycle() else { return .failure(.cycle) }
        return .success(lineage)
    }

    /// Why a lineage was left out of a write.
    package nonisolated enum Omission: Error, Equatable, CustomStringConvertible {
        case invalid(Refusal)
        case disagreesWithRecord

        package var description: String {
            switch self {
            case .invalid(let refusal):
                "The lineage was not saved — it would not read back: \(refusal.description)."
            case .disagreesWithRecord:
                "The lineage was not saved — it does not match the replay recipe written beside it (the recipe is kept as it was)."
            }
        }
    }

    /// May this lineage text be written beside this record? It must pass the
    /// reader's validation, and its projection must equal the record's steps —
    /// the invariant the reader checks on the way back in, checked on the way out.
    package static func writable(
        _ json: String, alongside record: SessionReplayRecord?
    ) -> Result<SessionLineage, Omission> {
        switch validated(json) {
        case .failure(let refusal):
            return .failure(.invalid(refusal))
        case .success(let lineage):
            guard Self.sameSteps(lineage.projection().steps, record?.steps ?? []) else {
                return .failure(.disagreesWithRecord)
            }
            return .success(lineage)
        }
    }

    /// Kinds and parameters exactly; dates to a millisecond. A JSON round
    /// trip (seconds since 1970, a Double) can move a `Date` by its last bit,
    /// so exact `Date` equality refused every agreeing pair (gate, 2026-09-30).
    package static func sameSteps(_ a: [SessionReplayRecord.Step], _ b: [SessionReplayRecord.Step]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { x, y in
            x.kind == y.kind && x.parameters == y.parameters
                && abs(x.recorded.timeIntervalSince(y.recorded)) < 0.001
        }
    }

    /// Nil for anything `validated` refuses.
    package static func parse(_ json: String) -> SessionLineage? {
        if case .success(let lineage) = validated(json) { return lineage }
        return nil
    }

    /// Kahn's algorithm over the input edges.
    private func hasCycle() -> Bool {
        var remaining: [String: Int] = [:]          // unresolved inputs per node
        var consumers: [String: [String]] = [:]     // input id -> nodes that consume it
        for node in nodes {
            let inputs = node.inputs ?? []
            remaining[node.id] = inputs.count
            for input in inputs { consumers[input.step, default: []].append(node.id) }
        }
        var ready = remaining.filter { $0.value == 0 }.map(\.key)
        var resolved = 0
        while let id = ready.popLast() {
            resolved += 1
            for consumer in consumers[id] ?? [] {
                remaining[consumer, default: 0] -= 1
                if remaining[consumer] == 0 { ready.append(consumer) }
            }
        }
        return resolved != nodes.count
    }
}
