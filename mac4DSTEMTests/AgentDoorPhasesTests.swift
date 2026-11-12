//
//  AgentDoorPhasesTests.swift
//  The agent door's phase list tools (App/AgentDoor/AgentDoorPhases.swift, issue #192), asked through a real door over MCP: a CIF
//  in the Agent folder becomes a phase, the matrix stays exactly one, a phase's own excitation slab is set and cleared, a phase
//  leaves the list, the orientation source is switched, and get_window's phase_mapping.last_run says what a map found.
//

import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorPhasesTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private var root: URL!
    private let session = URLSession(configuration: .ephemeral)

    private static func cif(_ name: String, _ a: Double, _ b: Double, _ c: Double, _ atoms: String) -> String {
        """
        data_\(name)
        _cell_length_a \(a)
        _cell_length_b \(b)
        _cell_length_c \(c)
        _cell_angle_alpha 90
        _cell_angle_beta 90
        _cell_angle_gamma 90
        loop_
        _atom_site_label
        _atom_site_type_symbol
        _atom_site_fract_x
        _atom_site_fract_y
        _atom_site_fract_z
        \(atoms)
        """
    }

    override func setUp() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("agent-phases-\(UUID().uuidString)")
        root = scratch.appendingPathComponent("Agent")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.cif("gold", 4.078, 4.078, 4.078, "Au1 Au 0.0 0.0 0.0\nAu2 Au 0.5 0.5 0.0\nAu3 Au 0.5 0.0 0.5\nAu4 Au 0.0 0.5 0.5")
            .write(to: root.appendingPathComponent("gold.cif"), atomically: true, encoding: .utf8)
        try Self.cif("ortho", 5, 6, 7, "Fe1 Fe 0 0 0")
            .write(to: root.appendingPathComponent("ortho.cif"), atomically: true, encoding: .utf8)
        try "not a cif".write(to: root.appendingPathComponent("broken.cif"), atomically: true, encoding: .utf8)

        defaultsSuite = "agent-door-phases-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.taskTools + Mac4DSTEMAgentDoor.phaseTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
        Mac4DSTEMAgentDoor.folder.use(folder: root)
    }

    override func tearDown() async throws {
        Mac4DSTEMAgentDoor.folder.use(folder: nil)
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        if let root { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String) {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ])
        let (data, _) = try await session.data(for: request)
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (result["isError"] as? Bool ?? true, text)
    }

    private func phases(_ text: String) throws -> [[String: Any]] {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        return try XCTUnwrap((object["phase_mapping"] as? [String: Any])?["phases"] as? [[String: Any]], text)
    }

    private func enrolledState() -> AppState {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        return state
    }

    /// Mutation: add_phase ignores is_matrix, leaves two matrices, or opens the modal on a bad CIF - red.
    func testACIFInTheFolderBecomesAPhase() async throws {
        let state = enrolledState()
        let first = try await call("add_phase", ["path": "gold.cif"])
        XCTAssertFalse(first.refused, first.text)
        XCTAssertEqual(try phases(first.text).map { $0["is_matrix"] as? Bool }, [true], "the first phase is the matrix")

        let second = try await call("add_phase", ["path": "ortho.cif", "is_matrix": true])
        XCTAssertFalse(second.refused, second.text)
        let list = try phases(second.text)
        XCTAssertEqual(list.map { $0["index"] as? Int }, [0, 1])
        XCTAssertEqual(list.map { $0["is_matrix"] as? Bool }, [false, true], "exactly one matrix, the one asked for")
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent added the phase") && $0.contains("as the matrix") },
                      "\(state.activityLog.messages.suffix(3))")

        let broken = try await call("add_phase", ["path": "broken.cif"])
        XCTAssertTrue(broken.refused)
        XCTAssertTrue(broken.text.contains("not a usable CIF"), broken.text)
        let outside = try await call("add_phase", ["path": "../gold.cif"])
        XCTAssertTrue(outside.refused, "only the Agent folder")
        let missing = try await call("add_phase", ["path": "none.cif"])
        XCTAssertTrue(missing.refused)
        XCTAssertEqual(state.phaseMapping.phases.count, 2, "a refusal adds nothing")
        withExtendedLifetime(state) {}
    }

    /// Mutation: set_phase writes the wrong phase, cannot clear the slab, or lets the matrix go unmarked - red.
    func testAPhaseIsChangedByItsIndex() async throws {
        let state = enrolledState()
        _ = try await call("add_phase", ["path": "gold.cif"])
        _ = try await call("add_phase", ["path": "ortho.cif"])

        let slab = try await call("set_phase", ["index": 1, "excitation_slab_inv_angstrom": 0.3, "zone_axis": "1 0 0"])
        XCTAssertFalse(slab.refused, slab.text)
        XCTAssertEqual(try XCTUnwrap(state.phaseMapping.phases[1].excitationSlabInvAngstrom), 0.3, accuracy: 1e-12)
        XCTAssertEqual(state.phaseMapping.phases[1].zoneAxis, SIMD3(1, 0, 0))
        XCTAssertNil(state.phaseMapping.phases[0].excitationSlabInvAngstrom, "the other phase is left alone")
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent set the phase") && $0.contains("excitation_slab_inv_angstrom 0.3") },
                      "\(state.activityLog.messages.suffix(3))")

        let cleared = try await call("set_phase", ["index": 1, "clear_excitation_slab": true])
        XCTAssertFalse(cleared.refused, cleared.text)
        XCTAssertNil(state.phaseMapping.phases[1].excitationSlabInvAngstrom)

        let unmark = try await call("set_phase", ["index": 0, "is_matrix": false])
        XCTAssertTrue(unmark.refused, "the matrix moves by marking another phase")
        let mark = try await call("set_phase", ["index": 1, "is_matrix": true])
        XCTAssertFalse(mark.refused, mark.text)
        XCTAssertEqual(state.phaseMapping.phases.map(\.isMatrix), [false, true])

        let badAxis = try await call("set_phase", ["index": 1, "zone_axis": "one"])
        XCTAssertTrue(badAxis.refused)
        let noSuch = try await call("set_phase", ["index": 5, "excitation_slab_inv_angstrom": 0.1])
        XCTAssertTrue(noSuch.refused)
        XCTAssertTrue(noSuch.text.contains("0 to 1"), noSuch.text)
        withExtendedLifetime(state) {}
    }

    /// Mutation: remove_phase removes the wrong phase or leaves no matrix - red.
    func testRemovingTheMatrixPromotesTheFirstPhase() async throws {
        let state = enrolledState()
        _ = try await call("add_phase", ["path": "gold.cif"])
        _ = try await call("add_phase", ["path": "ortho.cif"])
        let removed = try await call("remove_phase", ["index": 0])
        XCTAssertFalse(removed.refused, removed.text)
        XCTAssertEqual(state.phaseMapping.phases.map(\.model.displayName), [try XCTUnwrap(try phases(removed.text).first?["name"] as? String)])
        XCTAssertEqual(state.phaseMapping.phases.map(\.isMatrix), [true])
        let empty = try await call("remove_phase", ["index": 0])
        XCTAssertFalse(empty.refused, empty.text)
        let none = try await call("remove_phase", ["index": 0])
        XCTAssertTrue(none.refused)
        XCTAssertTrue(none.text.contains("empty"), none.text)
        withExtendedLifetime(state) {}
    }

    /// Mutation: orientation_source is ignored, or last_run is missing or miscounts - red.
    func testTheOrientationSourceAndTheLastRunAreTheAgents() async throws {
        let state = enrolledState()
        let typed = try await call("set_phase_mapping", ["orientation_source": "typedZones"])
        XCTAssertFalse(typed.refused, typed.text)
        XCTAssertEqual(state.phaseMapping.orientationSource, .typedZones)
        let back = try await call("set_phase_mapping", ["orientation_source": "structures"])
        XCTAssertEqual(state.phaseMapping.orientationSource, .structures)
        let before = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(back.text.utf8)) as? [String: Any])
        let settings = try XCTUnwrap(before["phase_mapping"] as? [String: Any])
        XCTAssertEqual(settings["orientation_source"] as? String, "structures")
        XCTAssertEqual(try XCTUnwrap(settings["default_excitation_slab_inv_angstrom"] as? Double), 0.06, accuracy: 1e-12)
        XCTAssertTrue(settings["last_run"] is NSNull, "no run yet")

        var map = PhaseMap(width: 4, height: 4, matrixEntryIndex: 0, phaseNames: ["Al", "T1"], matrixPhaseIndex: 0)
        for i in map.results.indices { map.results[i].verdict = .matrix; map.results[i].phaseIndex = 0 }
        for i in [5, 6, 9] { map.results[i].verdict = .indexed; map.results[i].phaseIndex = 1 }
        map.results[15].verdict = .notIndexed; map.results[15].phaseIndex = -1
        state.phaseMapping.publish(map, ranWith: PhaseMappingProduct.RunRecord(
            phaseSignature: "fixture", reference: PhaseReferenceSettings(), matching: PhaseVectorSettings(), libraryEntryCount: 1,
            matrixEntryIndex: 0, matrixInPlaneDegrees: .nan, worstChanceMatchPercent: 0, invAngstromPerPixel: 0.01,
            qScaleIsPhysical: true, peakCount: 0,
            calibration: PhaseMappingProduct.CalibrationStamp(calibration: Calibration(), referenceOrigin: (0, 0)),
            orientationSource: .structures, learnedRelationships: ["T1: learned"], excitationSlabs: ["T1: 0.06"]))
        let after = try await call("set_phase_mapping", [:])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(after.text.utf8)) as? [String: Any])
        let run = try XCTUnwrap((object["phase_mapping"] as? [String: Any])?["last_run"] as? [String: Any], after.text)
        XCTAssertEqual(run["positions"] as? Int, 16)
        XCTAssertEqual(run["matrix"] as? Int, 12)
        XCTAssertEqual(run["indexed"] as? Int, 3)
        XCTAssertEqual(run["not_indexed"] as? Int, 1)
        XCTAssertEqual((run["phases"] as? [[String: Any]])?.map { $0["positions"] as? Int }, [12, 3])
        XCTAssertEqual(run["orientation_source"] as? String, "structures")
        XCTAssertEqual(run["learned_relationships"] as? [String], ["T1: learned"])
        XCTAssertEqual(run["excitation_slabs"] as? [String], ["T1: 0.06"])
        // Every colour on the picture is named: a legend row per phase and per verdict that is not a phase.
        let legend = try XCTUnwrap(run["legend"] as? [[String: Any]], after.text)
        XCTAssertEqual(legend.map { $0["label"] as? String }, ["Al (matrix)", "T1", "Not indexed"])
        XCTAssertEqual(legend.map { $0["positions"] as? Int }, [12, 3, 1])

        // The numbers behind the phase map, per position, for export_result data.
        XCTAssertNil(state.phaseMapDataExportMaps(), "only while the phase map is the product shown")
        state.publishPhaseMapProduct()
        let fields = try XCTUnwrap(state.phaseMapDataExportMaps())
        XCTAssertEqual(fields.map(\.kind), ["phase_label", "phase_verdict", "phase_distance", "phase_contrast", "phase_matched"])
        let labels = fields[0].pixels
        XCTAssertEqual(labels.count, 16)
        XCTAssertEqual(labels[0], 0, "matrix")
        XCTAssertEqual([labels[5], labels[6], labels[9]], [1, 1, 1], "T1")
        XCTAssertEqual(labels[15], -1, "not indexed has no phase")
        XCTAssertEqual(fields[1].pixels[15], Float(PhaseVerdict.notIndexed.rawValue))
        XCTAssertEqual(fields[0].provenance["phase_names"], "Al\nT1")
        withExtendedLifetime(state) {}
    }
}
