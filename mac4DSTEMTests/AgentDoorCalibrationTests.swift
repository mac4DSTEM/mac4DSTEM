//
//  AgentDoorCalibrationTests.swift
//  The agent door's calibration tools (App/AgentDoor/AgentDoorCalibration.swift, issue #208), asked through a real door over MCP:
//  the typed scales and voltage land as Prepare's fields put them, and the measured steps start as their buttons do.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorCalibrationTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        defaultsSuite = "agent-door-calibration-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools + Mac4DSTEMAgentDoor.kernelTools
                      + Mac4DSTEMAgentDoor.calibrationTools)
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

    private var demoCrop: LoadSpecification {
        var spec = LoadSpecification()
        spec.scanCrop = AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 4)
        return spec
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    func testTheToolsWaitForThePersonAndForADataset() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let gated = try await call("set_calibration", ["voltage_kv": 200])
        XCTAssertTrue(gated.refused)
        XCTAssertTrue(gated.text.contains("Let agents run analyses"), gated.text)
        door.runsAllowed = true
        let empty = try await call("run_calibration", ["step": "origin"])
        XCTAssertTrue(empty.refused)
        XCTAssertTrue(empty.text.contains("no dataset"), empty.text)
        XCTAssertNil(state.calibrationSession.acceleratingVoltage)
        withExtendedLifetime(state) {}
    }

    /// Mutation: a unit is applied after its size (the size lands in the old unit), or a field is skipped - red.
    func testTypedScalesLandAsPreparesFieldsPutThem() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: demoCrop)
        XCTAssertTrue(state.hasDataset, state.statusText)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true

        let badUnit = try await call("set_calibration", ["q_pixel_size": 0.3, "q_units": "furlong"])
        XCTAssertTrue(badUnit.refused)
        XCTAssertTrue(badUnit.text.contains("q_units"), badUnit.text)

        let set = try await call("set_calibration", ["q_pixel_size": 0.25, "q_units": "mrad", "voltage_kv": 300,
                                                     "r_pixel_size": 4.5, "r_units": "A"])
        XCTAssertFalse(set.refused, set.text)
        let calibration = state.calibrationSession.calibration
        XCTAssertEqual(calibration.qPixelSize, 0.25)
        XCTAssertEqual(calibration.qPixelUnits, "mrad")
        XCTAssertEqual(state.calibrationSession.provenance.qScale, .manual)
        XCTAssertEqual(calibration.rPixelSize, 4.5)
        XCTAssertEqual(calibration.rPixelUnits, "Å")
        XCTAssertEqual(state.calibrationSession.acceleratingVoltage, 300)
        let answered = try XCTUnwrap(try object(set.text)["calibration"] as? [String: Any])
        XCTAssertEqual(answered["q_pixel_size"] as? Double, 0.25)
        XCTAssertEqual(answered["accelerating_voltage_kv"] as? Double, 300)

        let unitOnly = try await call("set_calibration", ["q_units": "1/A"])
        XCTAssertFalse(unitOnly.refused, unitOnly.text)
        XCTAssertEqual(state.calibrationSession.calibration.qPixelUnits, "Å⁻¹", "the unit alone changes, as the picker does")
        XCTAssertEqual(state.calibrationSession.calibration.qPixelSize, 0.25)
        withExtendedLifetime(state) {}
    }

    /// Mutation: run_calibration does not start the step, or ignores the annulus - red.
    func testTheMeasuredStepsStartAsTheirButtonsDo() async throws {
        let state = AppState()
        await state.openDemoFixture(specification: demoCrop)
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        door.runsAllowed = true

        let noDisks = try await call("run_calibration", ["step": "origin_from_bragg_peaks"])
        XCTAssertTrue(noDisks.refused)
        XCTAssertTrue(noDisks.text.contains("Detect All Disks"), noDisks.text)
        let annulus = try await call("run_calibration", ["step": "ellipse", "fit_inner_px": 30, "fit_outer_px": 20])
        XCTAssertTrue(annulus.refused, "an inner radius above the outer is refused")
        XCTAssertEqual(state.calibrationSession.ellipseFitInnerRadius, 10, "and nothing was changed")

        XCTAssertFalse(state.calibrationSession.calibration.hasFittedOrigin)
        let origin = try await call("run_calibration", ["step": "origin"])
        XCTAssertFalse(origin.refused, origin.text)
        XCTAssertEqual(try object(origin.text)["started"] as? String, "origin")
        for _ in 0..<500 where !state.calibrationSession.calibration.hasFittedOrigin || state.isBusy {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(state.calibrationSession.calibration.hasFittedOrigin, "Calibrate Origin ran: \(state.statusText)")
        XCTAssertNotNil(state.calibrationSession.calibration.probeRadius)
        withExtendedLifetime(state) {}
    }
}
