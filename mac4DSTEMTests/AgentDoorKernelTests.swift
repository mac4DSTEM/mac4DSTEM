//
//  AgentDoorKernelTests.swift
//  The agent door's probe-kernel tools (App/AgentDoor/AgentDoorKernel.swift, issue #207), asked through a real door over MCP:
//  the kernel and detector are readable; the setters wait for "Let agents run analyses", refuse what the window cannot do, and
//  change the same state as the Probe kernel and Detector rows.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorKernelTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        defaultsSuite = "agent-door-kernel-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools + Mac4DSTEMAgentDoor.kernelTools)
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

    func testTheKernelIsReadableBeforeAnyIsBuilt() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let read = try await call("get_probe_kernel")
        XCTAssertFalse(read.refused, read.text)
        let summary = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(read.text.utf8)) as? [String: Any])
        XCTAssertTrue(summary["kernel"] is NSNull, "no kernel until one is built")
        XCTAssertTrue(summary["probe_radius_px"] is NSNull)
        XCTAssertEqual(summary["detector"] as? String, "classical")
        withExtendedLifetime(state) {}
    }

    /// Mutation: the detector tool ignores its argument, or skips the gate - red.
    func testTheDetectorWaitsForThePersonAndThenFollowsTheAgent() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let gated = try await call("set_detector", ["detector": "neural_net"])
        XCTAssertTrue(gated.refused)
        XCTAssertTrue(gated.text.contains("Let agents run analyses"), gated.text)
        XCTAssertEqual(state.learnedDetection.detectorClass, .classical)

        door.runsAllowed = true
        let learned = try await call("set_detector", ["detector": "neural_net", "threshold": 0.45])
        XCTAssertFalse(learned.refused, learned.text)
        XCTAssertEqual(state.learnedDetection.detectorClass, .learned)
        XCTAssertEqual(state.learnedDetection.threshold, 0.45, accuracy: 1e-6)
        let classical = try await call("set_detector", ["detector": "classical"])
        XCTAssertFalse(classical.refused, classical.text)
        XCTAssertEqual(state.learnedDetection.detectorClass, .classical)
        let outOfRange = try await call("set_detector", ["detector": "neural_net", "threshold": 2])
        XCTAssertTrue(outOfRange.refused, "the threshold's range is checked before the tool runs")
        withExtendedLifetime(state) {}
    }

    func testRadiusAndKernelRefuseAWindowWithoutADataset() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true
        let radius = try await call("set_probe_radius", ["radius": 2.5])
        XCTAssertTrue(radius.refused)
        XCTAssertTrue(radius.text.contains("no dataset"), radius.text)
        let built = try await call("build_probe_kernel", ["source": "synthetic"])
        XCTAssertTrue(built.refused)
        XCTAssertTrue(built.text.contains("no dataset"), built.text)
        let unknown = try await call("build_probe_kernel", ["source": "vacuum"])
        XCTAssertTrue(unknown.refused, "the source is one of the listed choices")
        XCTAssertNil(state.probeKernel)
        withExtendedLifetime(state) {}
    }

    func testTheRadiusRuleIsTheProbeRadiusRowsRule() {
        XCTAssertNil(ProbeRadiusEntry.radius(typed: 0, descriptor: nil))
        XCTAssertEqual(ProbeRadiusEntry.radius(typed: 2.5, descriptor: nil), 2.5)
    }
}
