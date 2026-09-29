//
//  SessionLineageTests.swift
//  ADR 047, phase L1 — the run graph's rules, without a file: the projection
//  onto today's linear record, the collapse rule, the edges, the ids, the
//  reader's refusals, and the `SessionReplay` seam that owns the live graph.
//  The file-level half is `SessionLineageSidecarTests`.
//
//  Every test names the mutation it catches. Break each one before trusting it.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SessionLineageTests: XCTestCase {

    private let identity = SessionLineage.Frame()

    private func date(_ index: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(index)) }

    // MARK: - R6: the projection IS today's record

    /// The mapping `AppState+DiskDetection` states at its call site.
    private let menu: [(kind: String, invalidating: [String])] = [
        ("virtual_detector", []), ("dpc", []),
        ("disk_detection", ["strain", "acom"]), ("strain", []), ("acom", []),
    ]

    /// Every sequence of one to six runs over the five replayable kinds —
    /// 19 530 of them, which contains each hand-written sequence in
    /// `SessionReplayTests` and `ReplayPlanTests` — is recorded twice: by
    /// `SessionReplayRecord.record` (today's record, with the call site's
    /// `invalidating:` list) and by `SessionLineage.recordRun` (no list). The
    /// lineage's projection must equal the record: kinds, parameters, dates,
    /// order.
    ///
    /// Mutation it catches: empty `SessionLineage.downstreamKinds` (the
    /// `invalidating` mapping dropped) — strain and ACOM then survive a
    /// re-detection in the projection and the sequence `disks, strain, disks`
    /// goes red. Also: make a re-run append instead of replacing in place, or
    /// collapse across the mapping.
    func testTheProjectionEqualsTodaysRecordOnEverySequenceUpToLengthSix() {
        var compared = 0
        var invalidationMattered = 0
        func run(_ sequence: [Int]) {
            var record = SessionReplayRecord()
            var control = SessionReplayRecord()      // the same runs, mapping dropped
            var lineage = SessionLineage()
            for (index, choice) in sequence.enumerated() {
                let entry = menu[choice]
                let parameters = ["n": String(index)]
                record.record(kind: entry.kind, parameters: parameters, at: date(index),
                              invalidating: entry.invalidating)
                control.record(kind: entry.kind, parameters: parameters, at: date(index))
                lineage.recordRun(kind: entry.kind, parameters: parameters, frame: identity,
                                  at: date(index))
            }
            compared += 1
            if record != control { invalidationMattered += 1 }
            XCTAssertEqual(lineage.projection(), record, "sequence \(sequence.map { menu[$0].kind })")
        }
        func extend(_ prefix: [Int], to length: Int) {
            if prefix.count == length { run(prefix); return }
            for choice in menu.indices { extend(prefix + [choice], to: length) }
        }
        for length in 1...6 { extend([], to: length) }
        XCTAssertEqual(compared, 19_530)
        // Guard against a vacuous pass: the mapping must actually change the
        // outcome on a large share of these sequences, or "equal" proves nothing.
        XCTAssertGreaterThan(invalidationMattered, 3_000)
    }

    /// The two named sequences of `SessionReplayTests`, asserted on values, not
    /// only against the other implementation.
    func testTheNamedS5SequencesProjectAsTheRecordTestsExpect() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "2.0"], frame: identity)
        lineage.recordRun(kind: "strain", parameters: ["basis_mode": "consensus"], frame: identity)
        lineage.recordRun(kind: "acom", parameters: ["material": "library:au_fcc"], frame: identity)
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "4.0"], frame: identity)
        XCTAssertEqual(lineage.projection().steps.map(\.kind), ["disk_detection"],
                       "Downstream steps built on superseded peaks must not survive")
        XCTAssertEqual(lineage.projection().steps.first?.parameters["sigma_cc"], "4.0")
        XCTAssertEqual(lineage.nodes.count, 4, "…but nothing is deleted from the graph: the old branch stays")
        lineage.recordRun(kind: "strain", parameters: ["basis_mode": "consensus"], frame: identity)
        XCTAssertEqual(lineage.projection().steps.map(\.kind), ["disk_detection", "strain"])
    }

    /// Mutation it catches: put a calibration kind in `downstreamKinds`, or
    /// let a calibration node's replacement deactivate its dependents — the
    /// record would then lose ACOM when Q is re-measured, which today it never does.
    func testARefittedCalibrationNeverDropsARecipeStep() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit_function": "Plane"], frame: identity)
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "2"], frame: identity)
        lineage.recordRun(kind: "calibration_q", parameters: ["q_pixel_size": "0.01"], frame: identity)
        lineage.recordRun(kind: "acom", parameters: ["material": "library:au_fcc"], frame: identity)
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit_function": "Parabola"], frame: identity)
        lineage.recordRun(kind: "calibration_q", parameters: ["q_pixel_size": "0.02"], frame: identity)
        XCTAssertEqual(lineage.projection().steps.map(\.kind), ["disk_detection", "acom"])
    }

    /// Mutation it catches: drop `lineageOnlyKinds` — the linear record an older
    /// build feeds to `ReplayPlanner` would then carry kinds it refuses.
    func testLineageOnlyKindsAreNodesButNeverRecipeSteps() {
        var lineage = SessionLineage()
        for kind in ["calibration_origin", "calibration_ellipse", "calibration_q",
                     "diffraction_groups", "phase_mapping", "precipitate_objects", "export"] {
            lineage.recordRun(kind: kind, parameters: ["k": kind], frame: identity)
        }
        XCTAssertEqual(lineage.nodes.count, 7)
        XCTAssertTrue(lineage.projection().isEmpty)
    }

    // MARK: - R3: the collapse rule

    /// Mutation it catches: remove the collapse — ten slider positions become
    /// ten nodes (the log v2 S5 refused).
    func testSliderExplorationStaysOneNode() {
        var lineage = SessionLineage()
        for index in 0..<10 {
            lineage.recordRun(kind: "virtual_detector", parameters: ["outer": String(index)],
                              frame: identity, at: date(index))
        }
        XCTAssertEqual(lineage.nodes.count, 1)
        XCTAssertEqual(lineage.nodes[0].id, "s1")
        XCTAssertEqual(lineage.nodes[0].parameters["outer"], "9", "the settled value wins")
        XCTAssertEqual(lineage.nodes[0].recorded, date(9))
        XCTAssertEqual(lineage.nextID, 2, "a collapse must not spend an id")
    }

    /// Mutation it catches: drop the `hasChildren` clause — the re-detection
    /// overwrites the node the strain map was computed from, and s2's edge
    /// points at parameters it never used.
    func testAReRunWithChildrenBranchesAndTheOldBranchStays() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "2"], frame: identity)
        lineage.recordRun(kind: "strain", parameters: ["basis_mode": "consensus"], frame: identity)
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "4"], frame: identity)
        XCTAssertEqual(lineage.nodes.map(\.id), ["s1", "s2", "s3"])
        XCTAssertEqual(lineage.node(id: "s1")?.parameters["sigma_cc"], "2", "the old detection is still there")
        XCTAssertEqual(lineage.node(id: "s2")?.inputs, [SessionLineage.Input(step: "s1", role: "peaks")])
        XCTAssertEqual(lineage.activeNodes().map(\.id), ["s3"], "strain left the active path with the peaks it used")
        XCTAssertEqual(lineage.head, "s3")
    }

    /// Mutation it catches: compare kind only, not inputs — a strain run on new
    /// peaks would overwrite the strain run on the old ones.
    func testAReRunWhoseInputsChangedBranches() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit": "a"], frame: identity)   // s1
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma": "2"], frame: identity)     // s2 <- s1
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit": "b"], frame: identity)   // s3 (s1 has a child)
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma": "2"], frame: identity)     // inputs now s3
        XCTAssertEqual(lineage.nodes.map(\.id), ["s1", "s2", "s3", "s4"])
        XCTAssertEqual(lineage.node(id: "s4")?.inputs, [SessionLineage.Input(step: "s3", role: "calibration")])
        XCTAssertEqual(lineage.node(id: "s2")?.inputs, [SessionLineage.Input(step: "s1", role: "calibration")])
    }

    /// Mutation it catches: drop the `product == nil` clause — a saved map's
    /// parameters would be overwritten by the next slider position.
    func testASavedProductIsNeverCollapsedInto() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "10"], frame: identity)
        lineage.markProduct(step: "s1", as: "virtual_annular")
        lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "12"], frame: identity)
        XCTAssertEqual(lineage.nodes.count, 2)
        XCTAssertEqual(lineage.node(id: "s1")?.parameters["outer"], "10")
        XCTAssertEqual(lineage.node(id: "s1")?.product, "virtual_annular")
        XCTAssertNil(lineage.node(id: "s2")?.product)
    }

    /// Mutation it catches: treat absent inputs as `[]` — a live run would
    /// collapse into a v1 node whose inputs the file never said.
    func testAV1NodeIsNeverCollapsedIntoByALiveRun() {
        var record = SessionReplayRecord()
        record.record(kind: "virtual_detector", parameters: ["outer": "6"], at: date(1))
        var lineage = SessionLineage.synthesized(from: record, frame: identity)
        lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "7"], frame: identity, at: date(2))
        XCTAssertEqual(lineage.nodes.map(\.id), ["s1", "s2"])
        XCTAssertNil(lineage.node(id: "s1")?.inputs)
        XCTAssertEqual(lineage.node(id: "s2")?.inputs, [])
        lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "8"], frame: identity, at: date(3))
        XCTAssertEqual(lineage.nodes.count, 2, "…and from then on the live node collapses as usual")
    }

    // MARK: - R1/R2: ids, edges, externals

    /// Mutation it catches: reuse an id after a prune or a collapse (derive
    /// `next_id` from `nodes.count`).
    func testIdsAreNeverReusedAndTheGraphStaysUnderTheReadersCap() {
        var lineage = SessionLineage()
        for index in 0..<1_100 {
            lineage.recordRun(kind: "disk_detection", parameters: ["n": String(index)], frame: identity)
            lineage.recordRun(kind: "strain", parameters: ["n": String(index)], frame: identity)
        }
        // Each detection after the first has a strain child, so each is a new
        // node; 2 200 were made and the cap is 2 000.
        XCTAssertLessThanOrEqual(lineage.nodes.count, SessionLineage.maximumNodes)
        XCTAssertEqual(lineage.nextID, 2_201, "ids ran s1…s2200 without a repeat")
        XCTAssertEqual(Set(lineage.nodes.map(\.id)).count, lineage.nodes.count)
        XCTAssertEqual(lineage.projection().steps.map(\.kind), ["disk_detection", "strain"])
        XCTAssertEqual(lineage.projection().steps.first?.parameters["n"], "1099",
                       "pruning took inactive leaves, never the active path")
        guard let json = lineage.jsonString else { return XCTFail("did not encode") }
        XCTAssertNotNil(SessionLineage.parse(json), "what the recorder makes, the reader must accept")
    }

    /// Mutation it catches: take the role from the wrong kind, or skip the
    /// external for an imported phase.
    func testEdgesCarryTheirRolesAndAnImportedPhaseIsAnExternalByNameAndFingerprint() {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: [:], frame: identity)              // s1
        lineage.recordRun(kind: "disk_detection", parameters: [:], frame: identity)                  // s2
        lineage.recordRun(kind: "calibration_q", parameters: ["q_pixel_size": "0.01"], frame: identity) // s3
        lineage.recordRun(kind: "acom", parameters: ["material": "imported_theta", "material_fingerprint": "00ff"],
                          frame: identity)                                                            // s4
        let acom = try? XCTUnwrap(lineage.node(id: "s4"))
        XCTAssertEqual(acom?.inputs, [
            SessionLineage.Input(step: "s2", role: "peaks"),
            SessionLineage.Input(step: "s1", role: "calibration"),
            SessionLineage.Input(step: "s3", role: "calibration"),
        ])
        XCTAssertEqual(acom?.external, [SessionLineage.External(name: "imported_theta", fingerprint: "00ff")])
        lineage.recordRun(kind: "phase_mapping", parameters: [:], frame: identity,
                          external: [SessionLineage.External(name: "imported_t1", fingerprint: "aa")])  // s5
        lineage.recordRun(kind: "precipitate_objects", parameters: [:], frame: identity)              // s6
        XCTAssertEqual(lineage.node(id: "s6")?.inputs, [SessionLineage.Input(step: "s5", role: "phases")])
        XCTAssertEqual(lineage.node(id: "s5")?.external.first?.name, "imported_t1")
        for node in lineage.nodes {
            XCTAssertFalse(node.external.contains { $0.name.contains("/") },
                           "an external is a file NAME, never a path")
        }
    }

    // MARK: - R5: the format

    private func sampleLineage() -> SessionLineage {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "calibration_origin", parameters: ["fit_function": "Plane"],
                          frame: identity, at: Date(timeIntervalSince1970: 5.25))
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "2.0", "max_peaks": "40"],
                          frame: SessionLineage.Frame(bin: 2, crop: AxisCrop(yOffset: 4, xOffset: 8, height: 32, width: 64)),
                          at: Date(timeIntervalSince1970: 10))
        lineage.recordRun(kind: "strain", parameters: ["basis_mode": "automatic"], frame: nil,
                          at: Date(timeIntervalSince1970: 20))
        lineage.markProduct(step: "s3", as: "strain")
        return lineage
    }

    /// Mutation it catches: an unsorted encoder, an encoder that writes the
    /// date as text, a decoder that drops a field (frame, product, external).
    func testReEncodingIsByteIdenticalAndTheKeysAreTheADRs() throws {
        let lineage = sampleLineage()
        let json = try XCTUnwrap(lineage.jsonString)
        let decoded = try XCTUnwrap(SessionLineage.parse(json))
        XCTAssertEqual(decoded, lineage)
        XCTAssertEqual(decoded.jsonString, json, "re-encode must be byte-identical")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "next_id", "head", "nodes"])
        XCTAssertEqual(object["version"] as? Int, 2)
        XCTAssertEqual(object["next_id"] as? Int, 4)
        XCTAssertEqual(object["head"] as? String, "s3")
        let nodes = try XCTUnwrap(object["nodes"] as? [[String: Any]])
        XCTAssertEqual(Set(nodes[0].keys),
                       ["id", "kind", "inputs", "external", "frame", "parameters", "recorded", "source"])
        XCTAssertEqual(nodes[0]["recorded"] as? Double, 5.25, "dates are seconds")
        XCTAssertNotNil(nodes[2]["product"])
        XCTAssertNil(nodes[2]["frame"], "an unknown frame is an absent key, not a guess")
    }

    /// Mutation it catches: encode a nil `inputs` as `[]` — the v1 node would
    /// then assert "consumed nothing", which the file never said (R7).
    func testAV1NodeWritesNoInputsKeyAndAnEmptyLiveNodeWritesAnEmptyArray() throws {
        var record = SessionReplayRecord()
        record.record(kind: "dpc", parameters: ["origin_reference": "global center"], at: date(3))
        let v1 = SessionLineage.synthesized(from: record, frame: identity)
        let v1JSON = try XCTUnwrap(v1.jsonString)
        XCTAssertFalse(v1JSON.contains("\"inputs\""))
        XCTAssertEqual(v1.nodes.first?.source, "v1")
        XCTAssertEqual(SessionLineage.parse(v1JSON)?.jsonString, v1JSON)
        XCTAssertEqual(v1.projection(), record, "a synthesized lineage projects to the record it came from")

        var live = SessionLineage()
        live.recordRun(kind: "virtual_detector", parameters: [:], frame: identity)
        XCTAssertTrue(try XCTUnwrap(live.jsonString).contains("\"inputs\":[]"))
    }

    /// Mutation it catches: refuse an unknown kind (a newer build's node would
    /// brick the file), or drop it on the way through.
    func testAnUnknownKindIsKeptAsAnOpaqueNode() throws {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "thickness_map", parameters: ["a": "b"], frame: identity)
        let json = try XCTUnwrap(lineage.jsonString)
        let decoded = try XCTUnwrap(SessionLineage.parse(json))
        XCTAssertEqual(decoded.nodes.first?.kind, "thickness_map")
        XCTAssertEqual(decoded.jsonString, json)
    }

    // MARK: - R8: hostile input refuses by name

    private func nodeJSON(id: String, inputs: [String] = [], kind: String = "strain") -> String {
        let edges = inputs.map { "{\"role\":\"peaks\",\"step\":\"\($0)\"}" }.joined(separator: ",")
        return "{\"external\":[],\"id\":\"\(id)\",\"inputs\":[\(edges)],\"kind\":\"\(kind)\",\"parameters\":{},\"recorded\":1,\"source\":\"live\"}"
    }

    private func lineageJSON(nodes: [String], head: String? = nil, nextID: Int = 100, version: Int = 2) -> String {
        let headText = head.map { "\"\($0)\"" } ?? "null"
        return "{\"head\":\(headText),\"next_id\":\(nextID),\"nodes\":[\(nodes.joined(separator: ","))],\"version\":\(version)}"
    }

    private func refusal(_ text: String) -> SessionLineage.Refusal? {
        if case .failure(let refusal) = SessionLineage.validated(text) { return refusal }
        return nil
    }

    /// Mutation it catches: delete the matching check in `validated` — each
    /// assertion below goes red on exactly its own.
    func testEveryHostileShapeIsRefusedForItsOwnReason() {
        XCTAssertEqual(refusal(""), .undecodable)
        XCTAssertEqual(refusal("[]"), .undecodable, "an array")
        XCTAssertEqual(refusal("2.5"), .undecodable, "a number")
        XCTAssertEqual(refusal("null"), .undecodable)
        XCTAssertEqual(refusal(lineageJSON(nodes: [], version: 3)), .unsupportedVersion(3))
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1", inputs: ["s9"])])),
                       .danglingInput(step: "s9", from: "s1"))
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1"), nodeJSON(id: "s1")])),
                       .duplicateID("s1"))
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "")])), .emptyID)
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1", inputs: ["s2"]),
                                                   nodeJSON(id: "s2", inputs: ["s1"])])), .cycle)
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1", inputs: ["s1"])])), .cycle,
                       "a node that consumes itself")
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1")], head: "s7")), .badHead("s7"))
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s5")], nextID: 3)),
                       .badNextID(nextID: 3, maxNumericID: 5))
        let many = (1...2_001).map { nodeJSON(id: "s\($0)") }
        XCTAssertEqual(refusal(lineageJSON(nodes: many, nextID: 3_000)), .tooManyNodes(2_001))
        let padded = lineageJSON(nodes: []) + String(repeating: " ", count: SessionLineage.maximumJSONBytes)
        if case .tooLarge? = refusal(padded) {} else { XCTFail("over 4 MiB must be tooLarge, got \(String(describing: refusal(padded)))") }
        // …and the well-formed neighbours of each are accepted, so the
        // refusals above are not the parser refusing everything.
        XCTAssertNil(refusal(lineageJSON(nodes: [nodeJSON(id: "s1"), nodeJSON(id: "s2", inputs: ["s1"])], head: "s2")))
        XCTAssertNil(refusal(lineageJSON(nodes: (1...2_000).map { nodeJSON(id: "s\($0)") }, nextID: 2_001)))
    }

    // MARK: - Gate B fixes (ADR 047 L1 review)

    /// Mutation it catches: drop the upper bound on `next_id` — `Int.max`
    /// validates and the next run traps on `nextID += 1`.
    func testAHostileNextIDRefusesByName() {
        for hostile in [Int.max, 1_000_001, 2_000_000_000] {
            XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1")], nextID: hostile)),
                           .badNextID(nextID: hostile, maxNumericID: 1), "next_id \(hostile)")
        }
        XCTAssertNil(refusal(lineageJSON(nodes: [nodeJSON(id: "s1")], nextID: SessionLineage.maximumNextID)),
                     "the bound itself is a legal value")
        XCTAssertEqual(refusal(lineageJSON(nodes: [nodeJSON(id: "s1")], nextID: 0)),
                       .badNextID(nextID: 0, maxNumericID: 1))
    }

    /// A lineage one id below the bound: the last mint succeeds, the file it
    /// makes still reads, and every run after it is absorbed instead of trapping.
    /// Mutation it catches: mint without the `nextID < maximumNextID` guard
    /// (the file written after the last mint carries a `next_id` the reader
    /// refuses), or an unchecked increment.
    func testARunAtTheIdBoundDoesNotTrapAndTheFileStaysReadable() throws {
        var lineage = try XCTUnwrap(SessionLineage.parse(
            lineageJSON(nodes: [nodeJSON(id: "s1", kind: "dpc")], head: "s1",
                        nextID: SessionLineage.maximumNextID - 1)))
        let last = lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "1"], frame: identity)
        XCTAssertEqual(last, "s\(SessionLineage.maximumNextID - 1)")
        XCTAssertEqual(lineage.nextID, SessionLineage.maximumNextID)
        XCTAssertNotNil(SessionLineage.parse(try XCTUnwrap(lineage.jsonString)),
                        "what the recorder made at the bound, the reader accepts")
        // Ids are spent: a same-kind run replaces its active node in place …
        lineage.markProduct(step: last, as: "saved")   // even a saved one — the alternative is a trap
        XCTAssertEqual(lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "2"], frame: identity), last)
        XCTAssertEqual(lineage.node(id: last)?.parameters["outer"], "2")
        // … and a run of a kind with no active node leaves the graph as it was.
        let count = lineage.nodes.count
        lineage.recordRun(kind: "strain", parameters: [:], frame: identity)
        XCTAssertEqual(lineage.nodes.count, count)
        XCTAssertEqual(lineage.nextID, SessionLineage.maximumNextID)
        XCTAssertNotNil(SessionLineage.parse(try XCTUnwrap(lineage.jsonString)))
    }

    /// Mutation it catches: prune the oldest inactive leaf without checking the
    /// fold — the first `disk_detection` holds the kind's position, and
    /// dropping it turns `[disk_detection, dpc, …]` into `[dpc, disk_detection, …]`.
    /// The run below goes past the cap; the projection is compared with
    /// `SessionReplayRecord.record` after EVERY step, not only at the end.
    func testPruningAtTheCapNeverReordersTheProjection() {
        var lineage = SessionLineage()
        var record = SessionReplayRecord()
        func both(_ kind: String, _ index: Int, invalidating: [String] = []) {
            let parameters = ["n": String(index)]
            lineage.recordRun(kind: kind, parameters: parameters, frame: identity, at: date(index))
            record.record(kind: kind, parameters: parameters, at: date(index), invalidating: invalidating)
            XCTAssertEqual(lineage.projection(), record, "step \(index) (\(kind))")
        }
        both("disk_detection", 0, invalidating: ["strain", "acom"])
        both("dpc", 1)
        for index in 2..<1_200 {
            both("strain", 2 * index)
            both("disk_detection", 2 * index + 1, invalidating: ["strain", "acom"])
        }
        XCTAssertGreaterThan(lineage.nextID, SessionLineage.maximumNodes + 100, "the run went past the cap")
        XCTAssertLessThanOrEqual(lineage.nodes.count, SessionLineage.maximumNodes)
        XCTAssertEqual(lineage.projection().steps.map(\.kind), ["disk_detection", "dpc"])
    }

    /// Mutation it catches: decode the whole lineage before looking at its
    /// version — a v3 file whose nodes are shaped differently comes back
    /// `undecodable`, a refusal instead of "newer than this build reads".
    func testAFutureVersionIsRecognisedAsFutureWhateverItsNodesLookLike() {
        XCTAssertEqual(refusal("{\"version\":3,\"graph\":{\"vertices\":[1,2,3]},\"nodes\":\"reshaped\"}"),
                       .unsupportedVersion(3))
        XCTAssertEqual(refusal("{\"version\":\"two\"}"), .undecodable)
        XCTAssertEqual(refusal("{\"nodes\":[]}"), .undecodable)
    }

    /// Mutation it catches: drop the empty-recipe guard — a calibration-only
    /// session (recordForSaving non-nil, parameterFrame nil) reports a
    /// "different detector frame" omission for a recipe that does not exist;
    /// or forward the lineage into the reduced file's record.
    func testAnEmptyRecipeReportsNoExportOmissionAndTheLineageIsNotForwarded() {
        var calibrationOnly = SessionLineage()
        calibrationOnly.recordRun(kind: "calibration_origin", parameters: [:], frame: identity)
        let empty = SessionReplayRecord(steps: [], lineage: calibrationOnly)
        let none = ReplayRecordFrameMap.exportableRecipe(
            record: empty, recordedFrame: nil, currentSpecification: .fullExtent, exportBin: 1)
        XCTAssertNil(none.record)
        XCTAssertNil(none.omission, "nothing to omit, nothing to explain")

        var lineage = SessionLineage()
        lineage.recordRun(kind: "virtual_detector", parameters: ["outer": "6"], frame: identity)
        let full = ReplayRecordFrameMap.exportableRecipe(
            record: SessionReplayRecord(steps: lineage.projection().steps, lineage: lineage),
            recordedFrame: .detectorIdentity, currentSpecification: .fullExtent, exportBin: 1)
        XCTAssertNil(full.omission)
        XCTAssertEqual(full.record?.steps.map(\.kind), ["virtual_detector"])
        XCTAssertNil(full.record?.lineage, "the reduced file stamps the recipe, not the sidecar's graph")
    }

    /// Mutation it catches: `writable` without the projection comparison (a
    /// calibration-only lineage would be written beside an older recipe), or
    /// without validation (an over-cap lineage would be written).
    func testWritableRequiresAValidLineageWhoseProjectionIsTheRecordBeingWritten() throws {
        var lineage = SessionLineage()
        lineage.recordRun(kind: "disk_detection", parameters: ["sigma": "2"], frame: identity)
        let json = try XCTUnwrap(lineage.jsonString)
        let record = lineage.projection()
        if case .failure = SessionLineage.writable(json, alongside: record) { XCTFail("agreeing pair refused") }
        XCTAssertEqual(SessionLineage.writable(json, alongside: nil).failureValue, .disagreesWithRecord)
        var other = SessionReplayRecord()
        other.record(kind: "dpc", parameters: [:])
        XCTAssertEqual(SessionLineage.writable(json, alongside: other).failureValue, .disagreesWithRecord)
        XCTAssertEqual(SessionLineage.writable("{}", alongside: record).failureValue, .invalid(.undecodable))
        var calibrationOnly = SessionLineage()
        calibrationOnly.recordRun(kind: "calibration_origin", parameters: [:], frame: identity)
        XCTAssertEqual(SessionLineage.writable(try XCTUnwrap(calibrationOnly.jsonString), alongside: record).failureValue,
                       .disagreesWithRecord, "a calibration-only graph beside a real recipe")
        if case .failure = SessionLineage.writable(try XCTUnwrap(calibrationOnly.jsonString), alongside: nil) {
            XCTFail("a calibration-only graph beside no recipe is fine")
        }
    }

    func testProductKindsMapToTheRunsThatMadeThem() {
        XCTAssertEqual(SessionLineage.lineageKind(forProductKind: "virtual_annular"), "virtual_detector")
        XCTAssertEqual(SessionLineage.lineageKind(forProductKind: "strain_exx"), "strain")
        XCTAssertEqual(SessionLineage.lineageKind(forProductKind: "acom_full_ipf"), "acom")
        XCTAssertEqual(SessionLineage.lineageKind(forProductKind: "dpc_magnitude"), "dpc")
        XCTAssertEqual(SessionLineage.lineageKind(forProductKind: "phase_map"), "phase_mapping")
        XCTAssertNil(SessionLineage.lineageKind(forProductKind: "something_else"))
    }

    // MARK: - The live seam: SessionReplay owns the graph

    @MainActor
    func testTheLiveSeamRecordsARunOnceAndTheRecordIsTheProjection() {
        let replay = SessionReplay()
        let id = replay.record(kind: "disk_detection", parameters: ["sigma_cc": "2"],
                               invalidating: ["strain", "acom"], under: .detectorIdentity)
        replay.record(kind: "strain", parameters: ["basis_mode": "automatic"], under: .detectorIdentity)
        XCTAssertEqual(id, "s1")
        XCTAssertEqual(replay.lineage.nodes.map(\.kind), ["disk_detection", "strain"])
        XCTAssertEqual(replay.record, replay.lineage.projection())
        XCTAssertNil(replay.record.lineage, "the live record is the projection, not the graph")
        let saved = replay.recordForSaving
        XCTAssertEqual(saved?.lineage, replay.lineage, "a save carries the graph the record projects")
        XCTAssertEqual(saved?.steps, replay.record.steps)
    }

    /// Mutation it catches: let a lineage-only kind set `parameterFrame`, or
    /// return nil from `recordForSaving` when the recipe is empty but the graph
    /// is not (a calibration-only session would be saved as nothing).
    @MainActor
    func testACalibrationOnlySessionHasNoRecipeButIsSaved() {
        let replay = SessionReplay()
        replay.record(kind: "calibration_origin", parameters: ["fit_function": "Plane"],
                      under: .detectorReduced(bin: 2, crop: nil))
        XCTAssertTrue(replay.record.isEmpty)
        XCTAssertNil(replay.parameterFrame, "a calibration says nothing about the recipe's frame")
        let saved = replay.recordForSaving
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved?.isEmpty ?? false)
        XCTAssertEqual(saved?.lineage?.nodes.first?.frame, SessionLineage.Frame(bin: 2, crop: nil))
        replay.record(kind: "virtual_detector", parameters: [:], under: .detectorIdentity)
        XCTAssertEqual(replay.parameterFrame, .detectorIdentity, "the first recipe step still sets the frame")
    }

    @MainActor
    func testAdoptingARecordAloneSynthesizesV1AndTheNextRunContinuesTheIds() {
        var record = SessionReplayRecord()
        record.record(kind: "disk_detection", parameters: ["sigma_cc": "2"], at: date(1))
        record.record(kind: "strain", parameters: ["basis_mode": "consensus"], at: date(2))
        let replay = SessionReplay()
        replay.adopt(record, recordedOn: .detectorIdentity)
        XCTAssertEqual(replay.lineage.nodes.map(\.source), ["v1", "v1"])
        XCTAssertEqual(replay.lineage.nodes.map(\.inputs), [nil, nil], "absent, not a chain")
        XCTAssertEqual(replay.record, record)
        let id = replay.record(kind: "virtual_detector", parameters: [:], under: .detectorIdentity)
        XCTAssertEqual(id, "s3")
        XCTAssertEqual(replay.recordForSaving?.lineage?.nodes.map(\.source), ["v1", "v1", "live"],
                       "the first save writes those nodes still marked v1")
    }

    @MainActor
    func testAdoptingALineageTakesItOnlyWhenItProjectsToTheRecord() {
        var source = SessionLineage()
        source.recordRun(kind: "calibration_origin", parameters: [:], frame: identity)
        source.recordRun(kind: "disk_detection", parameters: ["sigma_cc": "2"], frame: identity)
        let replay = SessionReplay()
        replay.adopt(source.projection(), lineage: source, recordedOn: .detectorIdentity)
        XCTAssertEqual(replay.lineage, source)

        var other = SessionReplayRecord()
        other.record(kind: "dpc", parameters: [:], at: date(9))
        let disagreeing = SessionReplay()
        disagreeing.adopt(other, lineage: source, recordedOn: .detectorIdentity)
        XCTAssertEqual(disagreeing.record, other, "the record wins a disagreement")
        XCTAssertEqual(disagreeing.lineage.nodes.map(\.source), ["v1"], "…and the graph is rebuilt from it as v1")

        let untouched = SessionReplay()
        untouched.record(kind: "dpc", parameters: [:], under: .detectorIdentity)
        untouched.adopt(nil, lineage: nil, recordedOn: nil)
        XCTAssertEqual(untouched.record.steps.map(\.kind), ["dpc"], "absence is absence")
        untouched.reset()
        XCTAssertTrue(untouched.lineage.isEmpty)
        XCTAssertNil(untouched.recordForSaving)
    }

    // MARK: - Wiring (AppState)

    /// The R3 hook the sidecar save calls: the run that made a saved map stops
    /// being collapsible, and a failed save puts the node back.
    /// Mutation it catches: never mark (slider exploration overwrites a saved
    /// map's parameters), or mark and never undo (a failed save leaves a false
    /// "saved" on the node).
    @MainActor
    func testASavedProductsNodeIsNotCollapsedIntoAndAFailedSaveUndoesTheMark() {
        let state = AppState()
        state.replay.record(kind: "virtual_detector", parameters: ["outer": "10"], under: .detectorIdentity)
        let failed = state.markLineageProductSaved(productKind: "virtual_annular")
        XCTAssertEqual(state.replay.lineage.node(id: "s1")?.product,
                       BraggVectorEMDWriter.resultNodeName(forKind: "virtual_annular"))
        state.undoLineageProductMark(failed)
        XCTAssertNil(state.replay.lineage.node(id: "s1")?.product, "a failed save is not a saved product")

        state.replay.record(kind: "virtual_detector", parameters: ["outer": "11"], under: .detectorIdentity)
        XCTAssertEqual(state.replay.lineage.nodes.count, 1, "unsaved: still collapses")
        _ = state.markLineageProductSaved(productKind: "virtual_annular")
        state.replay.record(kind: "virtual_detector", parameters: ["outer": "12"], under: .detectorIdentity)
        XCTAssertEqual(state.replay.lineage.nodes.map(\.id), ["s1", "s2"])
        XCTAssertEqual(state.replay.lineage.node(id: "s1")?.parameters["outer"], "11")
        XCTAssertNil(state.markLineageProductSaved(productKind: "something_else"))
    }

    /// Mutation it catches: record no export, or let two exports collapse into one node.
    @MainActor
    func testEachExportIsASinkNodeWithAnEdgeToTheRunItWrote() throws {
        let state = AppState()
        state.replay.record(kind: "strain", parameters: ["basis_mode": "automatic"], under: .detectorIdentity)
        let first = try XCTUnwrap(state.recordExportRun(format: "png", fileName: "a.png", productKind: "strain_exx"))
        let second = try XCTUnwrap(state.recordExportRun(format: "png", fileName: "b.png", productKind: "strain_exx"))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(state.replay.lineage.node(id: first)?.inputs, [SessionLineage.Input(step: "s1", role: "product")])
        XCTAssertEqual(state.replay.lineage.node(id: first)?.parameters["file_name"], "a.png")
        XCTAssertEqual(state.replay.record.steps.map(\.kind), ["strain"], "an export is not a recipe step")
        let datacube = try XCTUnwrap(state.recordExportRun(format: "py4dstem_datacube", fileName: "c.h5"))
        XCTAssertEqual(state.replay.lineage.node(id: datacube)?.inputs, [], "source data: no recorded run behind it")
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
