// SPDX-License-Identifier: GPL-3.0-only
//
//  The bridge without a port: a door that records what it was asked and answers what the test hands it.
//

import Foundation
import XCTest
@testable import AgentBridgeCore

final class RecordingDoor: Door {
    var answers: [String: DoorAnswer] = [:]
    var failure: DoorError?
    private(set) var asked: [String] = []

    func get(_ path: String) throws -> DoorAnswer {
        asked.append(path)
        if let failure { throw failure }
        return answers[path] ?? DoorAnswer(status: 404, contentType: "application/json", body: Data(#"{"error":"Unknown path."}"#.utf8))
    }
}

final class MCPServerTests: XCTestCase {

    private func json(_ line: String?) throws -> [String: Any] {
        let line = try XCTUnwrap(line)
        XCTAssertFalse(line.contains("\n"), "one message, one line")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    private func call(_ server: MCPServer, _ tool: String, _ arguments: String = "{}") throws -> [String: Any] {
        let line = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"\#(tool)","arguments":\#(arguments)}}"#
        let answer = try json(server.handle(line: line))
        XCTAssertEqual(answer["id"] as? Int, 7)
        return try XCTUnwrap(answer["result"] as? [String: Any])
    }

    // MARK: The protocol

    func testInitializeAnswersWithTheAskedVersionWhenItIsKnown() throws {
        let server = MCPServer(door: RecordingDoor())
        let known = try json(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
        let result = try XCTUnwrap(known["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "mac4dstem")
        let unknown = try json(server.handle(line: #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        XCTAssertEqual(unknown["id"] as? String, "a", "the id comes back as it was sent")
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.protocolVersions[0])
    }

    func testNotificationsGetNoAnswerAndUnknownMethodsAnError() throws {
        let server = MCPServer(door: RecordingDoor())
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(server.handle(line: "   "))
        let parse = try json(server.handle(line: "not json"))
        XCTAssertEqual((parse["error"] as? [String: Any])?["code"] as? Int, -32700)
        let unknown = try json(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"resources/list"}"#))
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let ping = try json(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#))
        XCTAssertNotNil(ping["result"] as? [String: Any])
        let tool = try json(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"delete_everything"}}"#))
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    /// Every tool is listed with a schema and says it only reads.
    func testEveryToolIsListedAsReadOnly() throws {
        let server = MCPServer(door: RecordingDoor())
        let list = try json(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, MCPServer.tools.count)
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }).count, tools.count, "no name twice")
        for tool in tools {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
            XCTAssertEqual((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
            XCTAssertFalse((tool["description"] as? String ?? "").isEmpty)
        }
    }

    // MARK: The tools

    func testAToolAsksTheDoorForItsPath() throws {
        let door = RecordingDoor()
        door.answers["/v1/windows"] = DoorAnswer(status: 200, contentType: "application/json; charset=utf-8", body: Data(#"{"windows":[]}"#.utf8))
        door.answers["/v1/windows/current"] = DoorAnswer(status: 200, contentType: "application/json", body: Data("{}".utf8))
        door.answers["/v1/windows/w2/disks"] = DoorAnswer(status: 200, contentType: "application/json", body: Data("{}".utf8))
        let server = MCPServer(door: door)
        let list = try call(server, "list_windows")
        XCTAssertEqual(list["isError"] as? Bool, false)
        XCTAssertEqual((list["content"] as? [[String: Any]])?.first?["text"] as? String, #"{"windows":[]}"#)
        _ = try call(server, "get_window")
        _ = try call(server, "get_detected_disks", #"{"window":"w2"}"#)
        XCTAssertEqual(door.asked, ["/v1/windows", "/v1/windows/current", "/v1/windows/w2/disks"])
    }

    /// A picture comes back as MCP image content, base64, at the asked scale. Mutation: the scale is dropped from the path - red.
    func testAPictureIsImageContent() throws {
        let door = RecordingDoor()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        door.answers["/v1/windows/w1/result.png?scale=2"] = DoorAnswer(status: 200, contentType: "image/png", body: png)
        door.answers["/v1/windows/current/pattern.png"] = DoorAnswer(status: 200, contentType: "image/png", body: png)
        let server = MCPServer(door: door)
        let result = try call(server, "get_result_image", #"{"window":"w1","scale":2}"#)
        let content = try XCTUnwrap((result["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(content["type"] as? String, "image")
        XCTAssertEqual(content["mimeType"] as? String, "image/png")
        XCTAssertEqual(Data(base64Encoded: content["data"] as? String ?? ""), png)
        XCTAssertEqual(try call(server, "get_pattern_image", #"{"scale":9}"#)["isError"] as? Bool, false, "a scale outside 1...3 is left out")
        XCTAssertEqual(door.asked.last, "/v1/windows/current/pattern.png")
    }

    /// What goes wrong is said to the agent in a sentence it can act on, as a tool result, never as a protocol error.
    func testRefusalsAreSentencesInTheResult() throws {
        let door = RecordingDoor()
        let server = MCPServer(door: door)
        func text(_ result: [String: Any]) -> String { (result["content"] as? [[String: Any]])?.first?["text"] as? String ?? "" }

        door.answers["/v1/windows/current/objects"] = DoorAnswer(status: 404, contentType: "application/json",
                                                                 body: Data(#"{"error":"No precipitate objects yet."}"#.utf8))
        let missing = try call(server, "get_precipitate_objects")
        XCTAssertEqual(missing["isError"] as? Bool, true)
        XCTAssertEqual(text(missing), "No precipitate objects yet.")

        door.answers["/v1/windows/current/log"] = DoorAnswer(status: 401, contentType: "application/json", body: Data(#"{"error":"Wrong token."}"#.utf8))
        XCTAssertTrue(text(try call(server, "get_log")).contains("Settings > Agents"))

        let before = door.asked.count
        let injected = try call(server, "get_window", #"{"window":"../../v1"}"#)
        XCTAssertEqual(injected["isError"] as? Bool, true)
        XCTAssertEqual(door.asked.count, before, "a window id that is not an id never reaches the door")

        door.failure = .closed
        let closed = try call(server, "list_windows")
        XCTAssertEqual(closed["isError"] as? Bool, true)
        XCTAssertTrue(text(closed).contains("Settings > Agents"))
    }

    // MARK: Finding the door

    func testTheDoorIsFoundFromItsFileOrTheEnvironment() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertThrowsError(try DoorAddress.find(environment: [:], home: home)) { XCTAssertEqual($0 as? DoorError, .closed) }

        let plain = DoorAddress.candidateFiles(home: home)[1], contained = DoorAddress.candidateFiles(home: home)[0]
        try FileManager.default.createDirectory(at: plain.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"api":1,"port":5001,"token":"plain"}"#.utf8).write(to: plain)
        XCTAssertEqual(try DoorAddress.find(environment: [:], home: home), DoorAddress(port: 5001, token: "plain"))

        try FileManager.default.createDirectory(at: contained.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"api":1,"port":5002,"token":"contained"}"#.utf8).write(to: contained)
        XCTAssertEqual(try DoorAddress.find(environment: [:], home: home), DoorAddress(port: 5002, token: "contained"), "the sandboxed app's file first")

        XCTAssertEqual(try DoorAddress.find(environment: ["MAC4DSTEM_AGENT_DOOR": plain.path], home: home).token, "plain")
        XCTAssertEqual(try DoorAddress.find(environment: ["MAC4DSTEM_AGENT_PORT": "6000", "MAC4DSTEM_AGENT_TOKEN": "env"], home: home),
                       DoorAddress(port: 6000, token: "env"))
        XCTAssertNil(DoorAddress.parse(Data(#"{"port":0,"token":"x"}"#.utf8)))
        XCTAssertNil(DoorAddress.parse(Data(#"{"port":5000,"token":""}"#.utf8)))
        XCTAssertNil(DoorAddress.parse(Data("not json".utf8)))
    }
}
