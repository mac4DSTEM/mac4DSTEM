//
//  AgentDoorFolderTests.swift
//  The agent door's folder tools (App/AgentDoor/AgentDoorFolder.swift, issue #191), asked through a real door over MCP: only the
//  Agent folder is listed, opened or written; opening waits for "Let agents run analyses", saving also for "Let agents save
//  results there"; a save never replaces a file.
//

import XCTest
import DSTEMCore
import DSTEMSession
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorFolderTests: XCTestCase {

    private var door: AgentDoor!
    private var defaultsSuite = ""
    private var root: URL!
    private var outside: URL!
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("agent-folder-\(UUID().uuidString)")
        root = scratch.appendingPathComponent("Agent")
        outside = scratch.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appendingPathComponent("a.dm4"))
        try Data("bb".utf8).write(to: root.appendingPathComponent("sub/b.h5"))
        try Data("taken".utf8).write(to: root.appendingPathComponent("taken.png"))
        try Data("secret".utf8).write(to: outside.appendingPathComponent("secret.dm4"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.dm4"),
                                                   withDestinationURL: outside.appendingPathComponent("secret.dm4"))

        defaultsSuite = "agent-door-folder-tests-\(UUID().uuidString)"
        door = AgentDoor(appName: "mac4DSTEM", appVersion: "test", preferredPort: 0, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools + Mac4DSTEMAgentDoor.folderTools)
        door.setEnabled(true)
        for _ in 0..<250 where door.status == .starting { try await Task.sleep(for: .milliseconds(20)) }
        guard case .listening = door.status else { return XCTFail("the door did not open: \(String(describing: door.status))") }
    }

    override func tearDown() async throws {
        Mac4DSTEMAgentDoor.folder.use(folder: nil)
        Mac4DSTEMAgentDoor.savesAllowed = false
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

    /// Mutation: the listing walks out through a link, or the folder check is dropped - red.
    func testTheListingHoldsTheFolderAndNothingElse() async throws {
        let none = try await call("list_agent_folder")
        XCTAssertTrue(none.refused)
        XCTAssertTrue(none.text.contains("No Agent folder"), none.text)

        Mac4DSTEMAgentDoor.folder.use(folder: root)
        let listed = try await call("list_agent_folder")
        XCTAssertFalse(listed.refused, listed.text)
        let files = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(listed.text.utf8)) as? [String: Any])?["files"] as? [[String: Any]])
        XCTAssertEqual(files.compactMap { $0["path"] as? String }, ["a.dm4", "sub/b.h5", "taken.png"])
        XCTAssertEqual(files.first?["bytes"] as? Int, 1)
    }

    /// Opening acts: refused until runs are allowed, and refused for anything outside the folder or missing.
    func testOpeningStaysInsideTheFolder() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        Mac4DSTEMAgentDoor.folder.use(folder: root)

        let gated = try await call("open_file", ["path": "a.dm4"])
        XCTAssertTrue(gated.refused)
        XCTAssertTrue(gated.text.contains("Let agents run analyses"), gated.text)

        door.runsAllowed = true
        for path in ["../Elsewhere/secret.dm4", "link.dm4", "sub/../../Elsewhere/secret.dm4"] {
            let refused = try await call("open_file", ["path": path])
            XCTAssertTrue(refused.refused, path)
            XCTAssertTrue(refused.text.contains("outside the Agent folder"), "\(path): \(refused.text)")
        }
        let absolute = try await call("open_file", ["path": outside.appendingPathComponent("secret.dm4").path])
        XCTAssertTrue(absolute.refused)
        let missing = try await call("open_file", ["path": "missing.dm4"])
        XCTAssertTrue(missing.refused)
        XCTAssertTrue(missing.text.contains("There is no file"), missing.text)
        let aFolder = try await call("open_file", ["path": "sub"])
        XCTAssertTrue(aFolder.refused)
        withExtendedLifetime(state) {}
    }

    /// Saving needs its own switch and never replaces a file.
    func testSavingWaitsForItsSwitchAndNeverReplacesAFile() async throws {
        let state = AppState()
        door.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        Mac4DSTEMAgentDoor.folder.use(folder: root)
        door.runsAllowed = true

        let off = try await call("save_result_image", ["name": "new"])
        XCTAssertTrue(off.refused)
        XCTAssertTrue(off.text.contains("Let agents save results there"), off.text)

        Mac4DSTEMAgentDoor.savesAllowed = true
        let taken = try await call("save_result_image", ["name": "taken"])
        XCTAssertTrue(taken.refused)
        XCTAssertTrue(taken.text.contains("never replaced"), taken.text)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("taken.png")), Data("taken".utf8))

        let escape = try await call("save_result_image", ["name": "../Elsewhere/x"])
        XCTAssertTrue(escape.refused)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("x.png").path))

        let nothingShown = try await call("save_result_image", ["name": "new"])
        XCTAssertTrue(nothingShown.refused, "a window with no result has nothing to save")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.png").path))
        withExtendedLifetime(state) {}
    }

    func testFileNamesStayInTheFolder() {
        XCTAssertEqual(try? Mac4DSTEMAgentDoor.fileName("map 1", default: "x").get(), "map 1.png")
        XCTAssertEqual(try? Mac4DSTEMAgentDoor.fileName("map.PNG", default: "x").get(), "map.png")
        XCTAssertEqual(try? Mac4DSTEMAgentDoor.fileName(nil, default: "scan (2)/a_result").get(), "scan _2__a_result.png")
        XCTAssertEqual(try? Mac4DSTEMAgentDoor.fileName("", default: ".hidden").get(), "_hidden.png")
        XCTAssertNil(try? Mac4DSTEMAgentDoor.fileName("../x", default: "x").get())
        XCTAssertNil(try? Mac4DSTEMAgentDoor.fileName("a/b", default: "x").get())
        XCTAssertNil(try? Mac4DSTEMAgentDoor.fileName(".x", default: "x").get())
    }
}
