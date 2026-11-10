// SPDX-License-Identifier: GPL-3.0-only
//
//  MCPServer.swift
//  Role: The Model Context Protocol side of the bridge: JSON-RPC 2.0 messages, one per line (the stdio transport), answered
//        from mac4DSTEM's agent door. Tools only; each tool is one GET to the door, so the bridge holds no state and decides
//        nothing about the science.
//
//  Read-only, like the door it speaks to: every tool looks, none changes the app.
//

import Foundation

public struct MCPServer {
    /// The protocol revisions this server speaks, newest first. A client that asks for one of them gets it; any other gets the newest.
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverVersion = "0.1.0"

    let door: Door

    public init(door: Door) {
        self.door = door
    }

    // MARK: Messages

    /// Answers one line from the client. nil for a notification (a message without an id) and for a blank line: nothing is written.
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let message = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"] as [String: Any]])
        }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        guard let method = message["method"] as? String else {
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "Invalid request"] as [String: Any]])
        }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return Self.result(id, initialize(params))
        case "ping":
            return Self.result(id, [String: Any]())
        case "tools/list":
            return Self.result(id, ["tools": Self.tools.map(\.description)])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = Self.tools.first(where: { $0.name == name }) else {
                return Self.encode(["jsonrpc": "2.0", "id": id,
                                    "error": ["code": -32602, "message": "Unknown tool: \(params["name"] as? String ?? "")"] as [String: Any]])
            }
            return Self.result(id, call(tool, arguments: params["arguments"] as? [String: Any] ?? [:]))
        default:
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"] as [String: Any]])
        }
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let asked = params["protocolVersion"] as? String ?? ""
        return [
            "protocolVersion": Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0],
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "mac4dstem", "title": "mac4DSTEM", "version": Self.serverVersion],
            "instructions": Self.instructions,
        ]
    }

    static let instructions = """
        mac4DSTEM is a macOS app for 4D-STEM analysis. These tools look at what its open windows show; they change nothing. \
        Start with list_windows, then get_window for the dataset, its calibration, the current task and its settings. \
        Judge results by the pictures (get_result_image, get_pattern_image), not by counts alone: get_pattern_image draws the \
        detected Bragg disks over the diffraction pattern while the window is in the Disks task. \
        If a tool says the agent door is not open, ask the person to turn it on in mac4DSTEM's Settings > Agents.
        """

    // MARK: Tools

    struct Tool {
        var name: String
        var title: String
        var summary: String
        /// The door's path for this tool, after `/v1/windows/<window>`; nil for the window list.
        var leaf: String?
        var isImage = false

        var description: [String: Any] {
            var properties: [String: Any] = [:]
            if leaf != nil {
                properties["window"] = [
                    "type": "string",
                    "description": "The window's id from list_windows (w1, w2, ...). Leave out while exactly one window is open.",
                ]
            }
            if isImage {
                properties["scale"] = ["type": "integer", "minimum": 1, "maximum": 3,
                                       "description": "Pixels per point: 1 (default), 2 or 3 for a sharper picture."] as [String: Any]
            }
            return [
                "name": name,
                "title": title,
                "description": summary,
                "inputSchema": ["type": "object", "properties": properties, "additionalProperties": false] as [String: Any],
                "annotations": ["title": title, "readOnlyHint": true, "openWorldHint": false] as [String: Any],
            ]
        }
    }

    static let tools: [Tool] = [
        Tool(name: "list_windows", title: "List windows",
             summary: "The open mac4DSTEM windows, one line each: id, file, current workspace and task, whether a run is in progress.",
             leaf: nil),
        Tool(name: "get_window", title: "Window state",
             summary: "Everything one window shows: the dataset and its loaded view, calibration and whether results are quantitative, "
                + "the workspace, task and its settings, the running operation, the displayed result and its provenance, "
                + "disk-detection parameters and statistics, saved results and the recipe's steps.",
             leaf: ""),
        Tool(name: "get_result_image", title: "Result picture",
             summary: "The displayed result (virtual image, strain or orientation map, phase map, ...) as the figure the app exports: "
                + "colour scale, scale bar and a caption naming units, calibration status and provenance.",
             leaf: "/result.png", isImage: true),
        Tool(name: "get_pattern_image", title: "Diffraction pattern picture",
             summary: "The diffraction pattern as its pane shows it (current scan position, mean or max), with its scale bar. In the Virtual "
                + "Detector task the detector is outlined; in the Disks task the detected Bragg disks are drawn over the pattern, "
                + "which is how to judge a detection.",
             leaf: "/pattern.png", isImage: true),
        Tool(name: "get_detected_disks", title: "Detected disks",
             summary: "The detected Bragg disks of the pattern on screen: position in detector pixels and correlation intensity.",
             leaf: "/disks"),
        Tool(name: "get_lineage", title: "Recipe and lineage",
             summary: "The recorded analysis steps with their parameters (the recipe) and the run graph they come from.",
             leaf: "/lineage"),
        Tool(name: "get_precipitate_objects", title: "Precipitate objects",
             summary: "The precipitate object table: per object its phase, size, shape, orientation and, where joined, composition, "
                + "strain and variant; per phase the number density.",
             leaf: "/objects"),
        Tool(name: "get_log", title: "Output log",
             summary: "The window's Output lines: what ran, what finished, what was refused and why.",
             leaf: "/log"),
    ]

    /// The door's path for `tool` with these arguments, or the sentence that says what is wrong with them.
    static func path(for tool: Tool, arguments: [String: Any]) -> Result<String, DoorError> {
        guard let leaf = tool.leaf else { return .success("/v1/windows") }
        let window = arguments["window"] as? String ?? "current"
        guard !window.isEmpty, window.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return .failure(DoorError("Not a window id: \(window). Use an id from list_windows."))
        }
        var path = "/v1/windows/\(window)\(leaf)"
        if tool.isImage, let scale = arguments["scale"] as? Int, (1...3).contains(scale) { path += "?scale=\(scale)" }
        return .success(path)
    }

    /// Runs one tool: a GET to the door, its answer as MCP content. A refusal is a result with `isError`, so the agent reads the
    /// reason and can act on it; it is never a protocol error.
    func call(_ tool: Tool, arguments: [String: Any]) -> [String: Any] {
        let answer: DoorAnswer
        do {
            answer = try door.get(try Self.path(for: tool, arguments: arguments).get())
        } catch let error as DoorError {
            return Self.refusal(error.message)
        } catch {
            return Self.refusal(DoorError.closed.message)
        }
        guard answer.status == 200 else {
            let stated = ((try? JSONSerialization.jsonObject(with: answer.body)) as? [String: Any])?["error"] as? String
            if answer.status == 401 || answer.status == 403 {
                return Self.refusal("mac4DSTEM refused the bridge (\(stated ?? "status \(answer.status)")). Turn the agent door off and on again in Settings > Agents.")
            }
            return Self.refusal(stated ?? "mac4DSTEM answered with status \(answer.status).")
        }
        if answer.contentType.hasPrefix("image/png") {
            return ["content": [["type": "image", "data": answer.body.base64EncodedString(), "mimeType": "image/png"]], "isError": false]
        }
        return ["content": [["type": "text", "text": String(decoding: answer.body, as: UTF8.self)]], "isError": false]
    }

    static func refusal(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    // MARK: JSON

    static func result(_ id: Any, _ result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    /// One line of JSON: no newline inside it (the transport's frame is the line).
    static func encode(_ message: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"error":{"code":-32603,"message":"Internal error"},"id":null,"jsonrpc":"2.0"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
