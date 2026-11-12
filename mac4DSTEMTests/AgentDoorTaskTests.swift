//
//  AgentDoorTaskTests.swift
//  The agent door's room-and-task tools (App/AgentDoor/AgentDoorTask.swift, issue #209), asked through a real door over MCP:
//  select_task moves the window as the sidebar does; Phase mapping's settings are readable in get_window and settable, and Scale
//  to This Detector waits for a physical Q pixel size.
//

import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorTaskTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        defaultsSuite = "agent-door-task-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools + Mac4DSTEMAgentDoor.kernelTools
                      + Mac4DSTEMAgentDoor.taskTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
    }

    override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
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

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// Mutation: select_task ignores its task, or skips the gate - red.
    func testSelectTaskMovesTheWindowAsTheSidebarDoes() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let gated = try await call("select_task", ["task": "Phase mapping"])
        XCTAssertTrue(gated.refused)
        XCTAssertTrue(gated.text.contains("Let agents run analyses"), gated.text)
        XCTAssertEqual(state.navigation.workspaceArea, .prepare)

        door.runsAllowed = true
        let phases = try await call("select_task", ["task": "Phase mapping"])
        XCTAssertFalse(phases.refused, phases.text)
        XCTAssertEqual(state.navigation.workspaceArea, .map)
        XCTAssertEqual(state.navigation.analysisMode, .phaseMapping)
        XCTAssertEqual(try object(phases.text)["task"] as? String, "Phase mapping")

        let disks = try await call("select_task", ["workspace": "braggDisks"])
        XCTAssertFalse(disks.refused, disks.text)
        XCTAssertEqual(state.navigation.workspaceArea, .braggDisks)
        XCTAssertEqual(state.navigation.analysisMode, .disks, "a workspace alone opens its first task")

        let prepare = try await call("select_task", ["workspace": "prepare"])
        XCTAssertFalse(prepare.refused, prepare.text)
        XCTAssertTrue(try object(prepare.text)["task"] is NSNull, "Prepare has no task")

        let mismatch = try await call("select_task", ["task": "Strain", "workspace": "image"])
        XCTAssertTrue(mismatch.refused, "a task outside the named workspace is refused")
        let neither = try await call("select_task")
        XCTAssertTrue(neither.refused)
        XCTAssertTrue(neither.text.contains("Name a task or a workspace"), neither.text)
        let unknown = try await call("select_task", ["task": "Tomography"])
        XCTAssertTrue(unknown.refused, "the task is one of the listed choices")
        XCTAssertEqual(state.navigation.workspaceArea, .prepare)
        withExtendedLifetime(state) {}
    }

    /// Mutation: get_window reads task_settings from the replay signature alone (null for Phase mapping) - red.
    func testPhaseMappingSettingsAreInGetWindow() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        state.changeMode(.phaseMapping)
        let window = try await call("get_window")
        XCTAssertFalse(window.refused, window.text)
        let view = try XCTUnwrap(try object(window.text)["view"] as? [String: Any])
        let phase = try XCTUnwrap(view["task_settings"] as? [String: Any], "Phase mapping's settings are not null")
        XCTAssertEqual((phase["phases"] as? [Any])?.count, 0)
        let settings = try XCTUnwrap(phase["settings"] as? [String: Any])
        XCTAssertEqual(settings["classifier"] as? String, "search")
        XCTAssertEqual(try XCTUnwrap(settings["pair_radius_inv_angstrom"] as? Double), 0.02, accuracy: 1e-12)
        XCTAssertTrue(phase["on_this_detector"] is NSNull, "no Q pixel size, so no pixels")
        XCTAssertFalse(phase["run_refusal"] is NSNull, "no phases, so it cannot run")

        state.changeMode(.diffractionGroups)
        let groups = try await call("get_window")
        let groupsView = try XCTUnwrap(try object(groups.text)["view"] as? [String: Any])
        let groupSettings = try XCTUnwrap(groupsView["task_settings"] as? [String: Any])
        XCTAssertEqual(groupSettings["groups"] as? Int, state.diffractionGroups.settings.groups)
        withExtendedLifetime(state) {}
    }

    /// Mutation: set_phase_mapping writes the wrong field, or the classifier keeps the old intensity floor - red.
    func testPhaseMappingSettingsFollowTheAgent() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        let set = try await call("set_phase_mapping", ["pair_radius_inv_angstrom": 0.031, "vectors_per_orientation": 24,
                                                       "classifier": "knownVariants", "residual_cutoff_inv_angstrom": 0.05])
        XCTAssertFalse(set.refused, set.text)
        let matching = state.phaseMapping.matching
        XCTAssertEqual(matching.pairRadiusInvAngstrom, 0.031, accuracy: 1e-12)
        XCTAssertEqual(matching.matrixToleranceInvAngstrom, 0.02, accuracy: 1e-12, "a field not given is left alone")
        XCTAssertEqual(matching.classificationRule, .knownVariants)
        XCTAssertEqual(matching.residualCutoffInvAngstrom, 0.05, accuracy: 1e-12)
        XCTAssertEqual(state.phaseMapping.reference.maximumVectorsPerEntry, 24)
        XCTAssertEqual(state.phaseMapping.reference.minimumIntensityFraction,
                       PhaseMappingRuleDefaults.minimumIntensityFraction(for: .knownVariants), "as the picker resets it")

        let floor = try await call("set_phase_mapping", ["classifier": "knownVariants", "min_intensity_fraction": 0.2])
        XCTAssertFalse(floor.refused, floor.text)
        XCTAssertEqual(state.phaseMapping.reference.minimumIntensityFraction, 0.2, accuracy: 1e-12,
                       "the same classifier again does not reset a floor given with it")
        let outOfRange = try await call("set_phase_mapping", ["pair_radius_inv_angstrom": 5])
        XCTAssertTrue(outOfRange.refused, "the range is checked before the tool runs")
        withExtendedLifetime(state) {}
    }

    /// Mutation: the tool scales without a physical Q scale, or does not scale - red.
    func testScaleToThisDetectorWaitsForAQPixelSize() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        let refused = try await call("scale_phase_matching_to_detector")
        XCTAssertTrue(refused.refused)
        XCTAssertTrue(refused.text.contains("Q pixel"), refused.text)
        XCTAssertEqual(state.phaseMapping.matching.pairRadiusInvAngstrom, 0.02, accuracy: 1e-12)

        state.calibrationSession.calibration.qPixelSize = 0.026
        state.calibrationSession.calibration.qPixelUnits = "A^-1"
        let scaled = try await call("scale_phase_matching_to_detector")
        XCTAssertFalse(scaled.refused, scaled.text)
        XCTAssertEqual(state.phaseMapping.matching.pairRadiusInvAngstrom, 0.026, accuracy: 1e-12)
        XCTAssertEqual(state.phaseMapping.matching.matrixToleranceInvAngstrom, 0.026, accuracy: 1e-12)
        XCTAssertEqual(state.phaseMapping.matching.notIndexedAboveInvAngstrom, 0.0195, accuracy: 1e-12)
        let onDetector = try XCTUnwrap((try object(scaled.text)["phase_mapping"] as? [String: Any])?["on_this_detector"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(onDetector["pair_radius_px"] as? Double), 1, accuracy: 1e-9)
        withExtendedLifetime(state) {}
    }
}
