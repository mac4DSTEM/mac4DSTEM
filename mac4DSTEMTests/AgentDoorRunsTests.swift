//
//  AgentDoorRunsTests.swift
//  The agent door's tools that act (App/AgentDoor/AgentDoorRuns.swift), each asked through a real door over MCP, as Claude asks:
//  refused until the person allows runs, refused while the window is busy or has nothing to act on, and changing the same
//  settings the window's own controls change.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorRunsTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        defaultsSuite = "agent-door-runs-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
    }

    override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    /// One MCP message through the open door; the JSON-RPC answer.
    private func mcp(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (data, _) = try await session.data(for: request)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A tool call's result: whether it was refused, and its text.
    private func call(_ name: String, _ arguments: [String: Any] = [:]) async throws -> (refused: Bool, text: String) {
        let answer = try await mcp("tools/call", ["name": name, "arguments": arguments])
        let result = try XCTUnwrap(answer["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (result["isError"] as? Bool ?? true, text)
    }

    func testTheToolsThatActAreListedAsNotReadOnly() async throws {
        let listed = try await mcp("tools/list")
        let tools = try XCTUnwrap((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        for name in ["select_scan_position", "set_disk_detection", "run_task", "stop_run"] {
            let tool = try XCTUnwrap(tools.first { $0["name"] as? String == name }, name)
            XCTAssertEqual((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, false, name)
        }
        let get = try XCTUnwrap(tools.first { $0["name"] as? String == "get_window" })
        XCTAssertEqual((get["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
    }

    /// Until the person turns on "Let agents run analyses", nothing changes; then the settings change as the sliders change them.
    /// Mutation: the tool ignores an argument, or writes it to another field - red.
    func testTuningTheDiskDetectionWaitsForThePersonAndChangesTheSlidersSettings() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let before = state.diskDetection.diskParams
        let refused = try await call("set_disk_detection", ["min_peak_spacing": 25])
        XCTAssertTrue(refused.refused)
        XCTAssertTrue(refused.text.contains("Let agents run analyses"))
        XCTAssertEqual(state.diskDetection.diskParams.minPeakSpacing, before.minPeakSpacing, "nothing changed")

        door.runsAllowed = true
        let tuned = try await call("set_disk_detection", ["min_peak_spacing": 25, "min_relative_intensity": 0.01, "sigma_cc": 1.5,
                                                         "corr_power": 0.5, "edge_boundary": 8, "max_peaks": 40])
        XCTAssertFalse(tuned.refused, tuned.text)
        let params = state.diskDetection.diskParams
        XCTAssertEqual(params.minPeakSpacing, 25)
        XCTAssertEqual(params.minRelativeIntensity, 0.01, accuracy: 1e-7)
        XCTAssertEqual(params.sigmaCC, 1.5)
        XCTAssertEqual(params.corrPower, 0.5)
        XCTAssertEqual(params.edgeBoundary, 8)
        XCTAssertEqual(params.maxNumPeaks, 40)
        XCTAssertEqual(params.upsampleFactor, before.upsampleFactor, "a setting not named stays as it was")
        XCTAssertTrue(tuned.text.contains("\"max_peaks\":40"), "the answer says the settings now in force")
        XCTAssertTrue(tuned.text.contains("Build Kernel"), "without a probe kernel the answer says why nothing is detected yet")

        let outOfRange = try await call("set_disk_detection", ["min_relative_intensity": 3])
        XCTAssertTrue(outOfRange.refused)
        XCTAssertEqual(state.diskDetection.diskParams.minRelativeIntensity, 0.01, accuracy: 1e-7)
        withExtendedLifetime(state) {}
    }

    /// The other tools refuse what the window cannot do, with a sentence that says why.
    func testRunAndStopAndSelectRefuseWhatTheWindowCannotDo() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        let run = try await call("run_task")
        XCTAssertTrue(run.refused)
        XCTAssertTrue(run.text.contains("no dataset"), run.text)
        let stop = try await call("stop_run")
        XCTAssertTrue(stop.refused)
        XCTAssertEqual(stop.text, "Nothing is running.")
        let select = try await call("select_scan_position", ["x": 1, "y": 2])
        XCTAssertTrue(select.refused)
        XCTAssertTrue(select.text.contains("no 4D-STEM scan"), select.text)
        let missing = try await call("select_scan_position", ["x": 1])
        XCTAssertTrue(missing.text.contains("y is required"), missing.text)
        withExtendedLifetime(state) {}
    }
}
