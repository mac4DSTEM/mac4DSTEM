//
//  AgentDoorTests.swift
//  mac4DSTEM's tools on the agent door (App/AgentDoor; the door itself is MacEMUI's ShellAgentDoor and is tested there): what a
//  window says about itself, the two pictures, the lists, each asked through a real door on the loopback address.
//
//  The pictures are checked on their pixels and every answer through a real connection: a tool that returned 200 with the wrong
//  bytes would pass any test that stopped at the function call.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ImageIO
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    /// A door of its own (its token in a throwaway suite, any free port) with the app's tools, open.
    override func setUp() async throws {
        defaultsSuite = "mac4DSTEM.AgentDoorTests.\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
    }

    override func tearDown() async throws {
        door?.setEnabled(false)
        door = nil
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    private struct Answer {
        let status: Int
        let contentType: String?
        let body: Data
    }

    /// Runs one tool through the open door, as the bridge does.
    private func ask(_ tool: String, _ query: [String: String] = [:]) async throws -> Answer {
        guard case .listening(let port) = door.status else { throw XCTSkip("door not open") }
        var parts = try XCTUnwrap(URLComponents(string: "http://127.0.0.1:\(port)/v1/tools/\(tool)"))
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: try XCTUnwrap(parts.url))
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return Answer(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), body: data)
    }

    private func object(_ answer: Answer) throws -> [String: Any] {
        XCTAssertEqual(answer.status, 200, String(decoding: answer.body, as: UTF8.self))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: answer.body) as? [String: Any])
    }

    private func windowWithResultAndPattern() -> AppState {
        let state = AppState()
        state.publishProduct(kind: "virtual_annulus", displayName: "Virtual image", valueUnits: "intensity",
                             payload: .scalar(FloatImage(width: 12, height: 10, pixels: (0..<120).map(Float.init))))
        state.currentPattern = DiffractionPattern(qy: 32, qx: 32, pixels: [Float](repeating: 5, count: 1024))   // flat: no green of its own
        return state
    }

    /// The door lists the app's tools after its own, each with a description an agent reads.
    func testTheDoorOffersTheAppsTools() async throws {
        guard case .listening(let port) = door.status else { return XCTFail("door not open") }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/tools")))
        request.setValue("Bearer \(door.token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        let tools = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String },
                       ["list_windows", "get_window", "get_result_image", "get_pattern_image", "get_detected_disks", "get_lineage",
                        "get_precipitate_objects", "get_log"])
        XCTAssertEqual(Mac4DSTEMAgentDoor.port, 47811, "the connection command a person copied names this port")
    }

    /// A window with nothing in it and one with a result both answer in valid JSON, and the result is named as the app names it.
    func testAWindowSaysWhatItShows() async throws {
        let empty = AppState()
        XCTAssertTrue(JSONSerialization.isValidJSONObject(empty.agentSnapshot()), "an empty window")
        let state = windowWithResultAndPattern()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let snapshot = try object(try await ask("get_window"))
        XCTAssertEqual(snapshot["id"] as? String, "w1")
        let result = try XCTUnwrap(snapshot["result"] as? [String: Any])
        XCTAssertEqual(result["kind"] as? String, "virtual_annulus")
        XCTAssertEqual(result["name"] as? String, "Virtual image")
        XCTAssertEqual(result["width"] as? Int, 12)
        XCTAssertEqual(result["image"] as? String, "get_result_image")
        let pattern = try XCTUnwrap(snapshot["pattern"] as? [String: Any])
        XCTAssertEqual(pattern["width"] as? Int, 32)
        XCTAssertNotNil(snapshot["calibration"] as? [String: Any])
        XCTAssertNotNil((snapshot["disk_detection"] as? [String: Any])?["parameters"] as? [String: Any])
        XCTAssertTrue(snapshot["dataset"] is NSNull, "no file is open in this window")
        withExtendedLifetime(state) {}
    }

    // MARK: The pictures

    private func decoded(_ answer: Answer) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        XCTAssertEqual(answer.status, 200, String(decoding: answer.body, as: UTF8.self))
        XCTAssertEqual(answer.contentType, "image/png")
        XCTAssertEqual(Array(answer.body.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(answer.body as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: pixels, count: image.width * image.height * 4))   // the top row first
        return (image.width, image.height, bytes)
    }

    /// The result picture is the export's figure: the same pixels `resultExportImage` makes, at the asked scale.
    func testTheResultPictureIsTheExportedFigure() async throws {
        let empty = AppState()
        door.enroll(empty) { [weak empty] in empty?.agentSummary() ?? [:] }
        let nothing = try await ask("get_result_image")
        XCTAssertEqual(nothing.status, 404, "no result yet is said, not drawn")
        door.withdraw(empty)
        let state = windowWithResultAndPattern()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let expected = try state.resultExportImage(scale: 1).image
        let one = try decoded(try await ask("get_result_image"))
        XCTAssertEqual(one.width, expected.width); XCTAssertEqual(one.height, expected.height)
        let two = try decoded(try await ask("get_result_image", ["scale": "2"]))
        XCTAssertEqual(two.width, 2 * expected.width)
        let odd = try decoded(try await ask("get_result_image", ["scale": "40"]))
        XCTAssertEqual(odd.width, expected.width, "a scale outside 1...3 is 1")
        withExtendedLifetime((empty, state)) {}
    }

    /// In the Disks task the pattern carries the detected disks where the pane draws them, and in no other task, at a Retina
    /// screen's two pixels per point (#185: at one the rings blurred into the disks).
    /// Mutation: `agentPatternOverlays` drops the peaks, or ignores the task, or the picture drops to one pixel per point - red.
    func testThePatternPictureCarriesTheDetectedDisksInTheDisksTask() async throws {
        let state = windowWithResultAndPattern()
        state.currentPeaks = [BraggPeak(x: 8, y: 24, intensity: 1)]
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        state.navigation.analysisMode = .strain   // a task whose pane draws nothing over the pattern
        let bare = try decoded(try await ask("get_pattern_image"))
        state.navigation.analysisMode = .disks
        let marked = try decoded(try await ask("get_pattern_image"))
        XCTAssertEqual(marked.width, 1024, "a 32 px pattern is enlarged 16x, at 2 pixels per point although the agent asked for 1")
        XCTAssertEqual(bare.rgba.count, marked.rgba.count)
        // The pixels the Disks task added: the cross at the disk's centre (no probe kernel, so no radius to draw).
        var count = 0, sumX = 0.0, sumY = 0.0, greenest = 0
        for y in 0..<marked.height {
            for x in 0..<marked.width {
                let i = (y * marked.width + x) * 4
                guard marked.rgba[i] != bare.rgba[i] || marked.rgba[i + 1] != bare.rgba[i + 1] || marked.rgba[i + 2] != bare.rgba[i + 2] else { continue }
                count += 1; sumX += Double(x); sumY += Double(y)
                greenest = max(greenest, Int(marked.rgba[i + 1]) - Int(marked.rgba[i]))
            }
        }
        XCTAssertGreaterThan(count, 10, "the detected disk is drawn")
        XCTAssertLessThan(count, 800, "a cross, not a filled disc")
        XCTAssertEqual(sumX / Double(max(count, 1)), 8.5 * 32, accuracy: 3)
        XCTAssertEqual(sumY / Double(max(count, 1)), 24.5 * 32, accuracy: 3, "y down, as the pane draws it")
        XCTAssertGreaterThan(greenest, 30, "in the pane's green")
        state.navigation.analysisMode = .virtualDetector
        let detector = try decoded(try await ask("get_pattern_image"))
        XCTAssertNotEqual(detector.rgba, bare.rgba, "the Virtual Detector task draws its detector instead")
        let disks = try object(try await ask("get_detected_disks"))
        XCTAssertEqual((disks["disks"] as? [[String: Any]])?.first?["x"] as? Double, 8)
    }

    func testTheListsAnswerInJSON() async throws {
        let state = windowWithResultAndPattern()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        let lineage = try object(try await ask("get_lineage"))
        XCTAssertNotNil(lineage["recipe"] as? [Any])
        XCTAssertNotNil(lineage["lineage"])
        let log = try object(try await ask("get_log"))
        XCTAssertNotNil(log["lines"] as? [String])
        let objects = try await ask("get_precipitate_objects")
        XCTAssertEqual(objects.status, 404, "no phase map classified")
        withExtendedLifetime(state) {}
    }
}
