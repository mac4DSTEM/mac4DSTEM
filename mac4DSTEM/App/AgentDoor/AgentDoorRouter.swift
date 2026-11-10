//
//  AgentDoorRouter.swift
//  Role: Which answer a request gets (`AgentDoor.respond`). Step one is read-only, so every route is a GET:
//
//    /v1                              what this API is and what it answers
//    /v1/windows                      the open windows, one line each
//    /v1/windows/<id>                 everything the window shows: dataset, calibration, task, result, disks, session
//    /v1/windows/<id>/result.png      the result figure File > Export writes (?scale=1...3)
//    /v1/windows/<id>/pattern.png     the diffraction pattern as the pane shows it, detector or detected disks drawn (?scale=1...3)
//    /v1/windows/<id>/disks           the detected disks of the pattern on screen
//    /v1/windows/<id>/lineage         the recipe and its run graph
//    /v1/windows/<id>/objects         the precipitate object table
//    /v1/windows/<id>/log             the Output lines
//
//  `<id>` is `w1`, `w2`, ... from /v1/windows, or `current` while exactly one window is open.
//  A refusal is a status and one sentence (`{"error": ...}`) that says what to do instead.
//

import CoreGraphics
import Foundation
import ShellLayout
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

enum AgentDoorRouter {
    struct Window {
        var id: String
        var state: AppState
    }

    static func respond(to request: AgentHTTPRequest, windows: [Window]) -> AgentHTTPResponse {
        guard request.method == "GET" else {
            return .error(405, "This version of the door is read-only: every route is a GET.")
        }
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == "v1" else { return .error(404, "Unknown path. Start at /v1.") }
        switch parts.count {
        case 1:
            return .json(index)
        case 2 where parts[1] == "windows":
            return .json(["windows": windows.map { $0.state.agentSummary(id: $0.id) }])
        case 3 where parts[1] == "windows":
            return resolve(parts[2], in: windows) { .json($0.state.agentSnapshot(id: $0.id)) }
        case 4 where parts[1] == "windows":
            return resolve(parts[2], in: windows) { leaf(parts[3], of: $0, query: request.query) }
        default:
            return .error(404, "Unknown path. GET /v1 lists what this door answers.")
        }
    }

    /// The window `id` names, handed to `answer`; or the refusal that says which windows there are.
    private static func resolve(_ id: String, in windows: [Window], _ answer: (Window) -> AgentHTTPResponse) -> AgentHTTPResponse {
        if id == "current" {
            if windows.count == 1 { return answer(windows[0]) }
            if windows.isEmpty { return .error(404, "No mac4DSTEM window is open.") }
            let names = windows.map { "\($0.id) (\($0.state.descriptor?.fileName ?? "no dataset"))" }.joined(separator: ", ")
            return .error(409, "Several windows are open; name one: \(names).")
        }
        guard let window = windows.first(where: { $0.id == id }) else {
            return .error(404, "No window \(id). GET /v1/windows lists the open windows.")
        }
        return answer(window)
    }

    private static func leaf(_ name: String, of window: Window, query: [String: String]) -> AgentHTTPResponse {
        let state = window.state
        switch name {
        case "result.png":
            do { return png(try state.resultExportImage(scale: scale(query)).image) } catch { return .error(404, error.localizedDescription) }
        case "pattern.png":
            do { return png(try state.agentPatternImage(scale: scale(query))) } catch { return .error(404, error.localizedDescription) }
        case "disks":
            return .json(state.agentPeaks)
        case "lineage":
            guard let data = AgentJSON.encoded(state.agentLineage) else { return .error(500, "The lineage could not be written as JSON.") }
            return .json(encoded: data)
        case "objects":
            guard let report = state.precipitateObjectReport else {
                return .error(404, "No precipitate objects yet: the table exists once a phase map has been classified.")
            }
            guard let data = AgentJSON.encoded(report) else { return .error(500, "The object table could not be written as JSON.") }
            return .json(encoded: data)
        case "log":
            return .json(["lines": state.activityLog.messages])
        default:
            return .error(404, "Unknown path. GET /v1 lists what this door answers.")
        }
    }

    /// `?scale=` 1, 2 or 3 pixels per point (the export's image sizes); anything else is 1.
    static func scale(_ query: [String: String]) -> Int {
        guard let stated = query["scale"].flatMap({ Int($0) }), (1...3).contains(stated) else { return 1 }
        return stated
    }

    private static func png(_ image: CGImage) -> AgentHTTPResponse {
        guard let data = AgentJSON.png(image) else { return .error(500, "The picture could not be written as PNG.") }
        return .png(data)
    }

    /// What the door is, for an agent that has only the port.
    static var index: [String: Any] {
        [
            "app": "mac4DSTEM",
            "app_version": FeedbackLinks.appVersion,
            "api": AgentDoor.apiVersion,
            "access": "read-only",
            "window_ids": "w1, w2, ... from /v1/windows, or 'current' while exactly one window is open",
            "routes": [
                "/v1/windows": "the open windows, one line each",
                "/v1/windows/<id>": "everything the window shows: dataset, calibration, task, result, disk detection, session",
                "/v1/windows/<id>/result.png": "the result figure as File > Export writes it; ?scale=1...3",
                "/v1/windows/<id>/pattern.png": "the diffraction pattern as the pane shows it, with the detector or the detected disks; ?scale=1...3",
                "/v1/windows/<id>/disks": "the detected disks of the pattern on screen",
                "/v1/windows/<id>/lineage": "the recipe and its run graph",
                "/v1/windows/<id>/objects": "the precipitate object table",
                "/v1/windows/<id>/log": "the Output lines",
            ],
        ]
    }
}
