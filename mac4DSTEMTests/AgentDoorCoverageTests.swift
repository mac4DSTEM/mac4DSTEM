//
//  AgentDoorCoverageTests.swift
//  The agent door's coverage table (App/AgentDoor/AgentDoorCoverage.swift, issue #223): every control in the UI sources has a
//  row, and every tool a row names is one the door registers. A new control fails here until someone decides how an agent
//  reaches it (a tool, already seen, left to the person, or a gap with its issue).
//

import XCTest
import ShellAgentDoor
@testable import mac4DSTEM

@MainActor
final class AgentDoorCoverageTests: XCTestCase {

    /// The `accessibilityIdentifier("…")` literals in mac4DSTEM/UI, as written.
    private func uiIdentifiers() throws -> Set<String> {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mac4DSTEM/UI")
        let walk = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        let files = walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no UI sources at \(ui.path)")
        let pattern = try NSRegularExpression(pattern: #"accessibilityIdentifier\("((?:[^"\\]|\\.|\\\([^)]*\))*)"\)"#)
        var found = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { found.insert(String(text[range])) }
            }
        }
        return found
    }

    /// Mutation: a control is added to the UI without a row - red.
    func testEveryControlHasARow() throws {
        let identifiers = try uiIdentifiers()
        XCTAssertGreaterThan(identifiers.count, 200, "the scan found too few controls to be the real UI")
        let missing = identifiers.subtracting(AgentDoorCoverage.controls.keys).sorted()
        XCTAssert(missing.isEmpty, "controls with no row in AgentDoorCoverage (say how an agent reaches each): \(missing)")
    }

    /// Mutation: a row names a tool the door does not register - red.
    func testEveryNamedToolExists() {
        let names = Set(Mac4DSTEMAgentDoor.allTools.map(\.name))
        for (control, reach) in AgentDoorCoverage.controls {
            if case .tool(let name) = reach { XCTAssert(names.contains(name), "\(control) names \(name), which the door does not have") }
        }
    }

    /// A row whose control is gone is stale.
    func testNoRowOutlivesItsControl() throws {
        let stale = Set(AgentDoorCoverage.controls.keys).subtracting(try uiIdentifiers()).sorted()
        XCTAssert(stale.isEmpty, "rows for controls that no longer exist: \(stale)")
    }
}
