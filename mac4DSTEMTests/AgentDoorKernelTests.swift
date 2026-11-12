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

    // MARK: issue #232: an agent hears about the settings a tool moves on its own, and every action is in the Output

    /// Mutation: the line drops a setting, keeps the Mac's decimal comma, or speaks when nothing moved - red.
    func testTheChangeLineNamesWhatMovedWithAPoint() throws {
        var before = DiskDetectionParams()
        before.minPeakSpacing = 16
        var after = before
        XCTAssertNil(Mac4DSTEMAgentDoor.diskChangeLine(from: before, to: after, by: "Build Kernel"))
        after.minPeakSpacing = 4
        after.minRelativeIntensity = 0.0005
        let line = try XCTUnwrap(Mac4DSTEMAgentDoor.diskChangeLine(from: before, to: after, by: "Build Kernel"))
        XCTAssertTrue(line.hasPrefix("Build Kernel also changed disk detection: "), line)
        XCTAssertTrue(line.contains("min_peak_spacing 16 → 4"), line)
        XCTAssertTrue(line.contains("→ 0.0005"), "a Float setting reads as typed, with a point: \(line)")
        XCTAssertEqual(Mac4DSTEMAgentDoor.numberText(Double(Float(0.01904))), "0.01904")
    }

    /// Mutation: set_probe_radius moves min_peak_spacing silently, or select_scan_position leaves no Output line - red.
    func testTheProbeRadiusSaysWhichDiskSettingFollowedIt() async throws {
        let state = AppState()
        var crop = LoadSpecification()
        crop.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        await state.openDemoFixture(specification: crop)
        let descriptor = try XCTUnwrap(state.descriptor, state.statusText)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true

        // Nobody chose a spacing: the detector-scaled placeholder, which a measured probe replaces (DiskDetectionProduct).
        let placeholder = DiskDetectionParams.detectorAdapted(qy: descriptor.qy, qx: descriptor.qx, probeRadius: nil)
        state.diskDetection.diskParams.minPeakSpacing = placeholder.minPeakSpacing
        let expected = DiskDetectionParams.detectorAdapted(qy: descriptor.qy, qx: descriptor.qx, probeRadius: 2).minPeakSpacing
        try XCTSkipIf(expected == placeholder.minPeakSpacing, "the demo detector is too small for the spacing to move")

        let radius = try await call("set_probe_radius", ["radius": 2])
        XCTAssertFalse(radius.refused, radius.text)
        for _ in 0..<250 where state.diskDetection.diskParams.minPeakSpacing != expected { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(state.diskDetection.diskParams.minPeakSpacing, expected)
        let moved = "The probe radius also changed disk detection: min_peak_spacing "
            + "\(Mac4DSTEMAgentDoor.numberText(Double(placeholder.minPeakSpacing))) → \(Mac4DSTEMAgentDoor.numberText(Double(expected)))"
        for _ in 0..<250 where !state.activityLog.messages.contains(where: { $0.contains(moved) }) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains(moved) }, "\(state.activityLog.messages.suffix(4))")
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent set the probe radius: 2 px.") })

        let read = try await call("get_probe_kernel")
        let settings = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(read.text.utf8)) as? [String: Any])?["disk_detection"]
                                     as? [String: Any], read.text)
        XCTAssertEqual(settings["min_peak_spacing"] as? Double, Double(expected), "get_probe_kernel shows the disk settings")

        let select = try await call("select_scan_position", ["x": 1, "y": 2])
        XCTAssertFalse(select.refused, select.text)
        XCTAssertTrue(state.activityLog.messages.contains { $0.contains("An agent selected scan position (1, 2).") },
                      "\(state.activityLog.messages.suffix(3))")
        withExtendedLifetime(state) {}
    }
}
