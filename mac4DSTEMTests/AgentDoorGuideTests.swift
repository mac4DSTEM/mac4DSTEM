//
//  AgentDoorGuideTests.swift
//  The agent door's workflow guide (App/AgentDoor/AgentDoorGuide.swift, issue #236), asked through a real door over MCP: every
//  topic answers, the overview comes by default, and every tool the guide names is one the door registers, so the guide cannot
//  send an agent to a tool that is gone.
//

import XCTest
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorGuideTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        defaultsSuite = "agent-door-guide-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.allTools)
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

    /// Mutation: a topic answers empty, or the guide needs the second switch - red.
    func testEveryTopicAnswersWithoutTheRunSwitch() async throws {
        XCTAssertFalse(door.runsAllowed, "the guide only reads")
        let overview = try await call("get_workflow_guide")
        XCTAssertFalse(overview.refused, overview.text)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(overview.text.utf8)) as? [String: Any])
        XCTAssertEqual(object["topic"] as? String, "overview")
        for topic in Mac4DSTEMAgentDoor.Guide.allCases {
            let answer = try await call("get_workflow_guide", ["topic": topic.rawValue])
            XCTAssertFalse(answer.refused, answer.text)
            let guide = (try JSONSerialization.jsonObject(with: Data(answer.text.utf8)) as? [String: Any])?["guide"] as? String ?? ""
            XCTAssertGreaterThan(guide.count, 300, "\(topic.rawValue) says something")
        }
    }

    /// Mutation: the guide names a tool that is not registered (renamed or removed) - red.
    func testEveryToolTheGuideNamesExists() throws {
        let registered = Set(Mac4DSTEMAgentDoor.allTools.map(\.name)).union(["list_windows"])   // list_windows is the door's own
        let named = try NSRegularExpression(pattern: "`([a-z]+_[a-z_]+)`")
        var seen = Set<String>()
        for topic in Mac4DSTEMAgentDoor.Guide.allCases {
            let text = topic.text
            for match in named.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                seen.insert(String(text[range]))
            }
        }
        XCTAssertGreaterThan(seen.count, 10, "the guide names the tools it means in backticks")
        XCTAssertEqual(seen.subtracting(registered), [], "the guide names tools the door does not register")
    }
}
