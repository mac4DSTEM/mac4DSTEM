//
//  Mac4DSTEMAgentDoor.swift
//  Role: mac4DSTEM's half of the agent door (MacEMUI's `ShellAgentDoor`; MacEMUI docs/agent-door.md): the door this app opens and
//        the tools it hands it. The tools here look at what a window shows and change nothing; the ones that act, behind the
//        second switch, are in `AgentDoorRuns.swift`. What a tool
//        reads is in `AgentDoorSnapshot.swift`, from the export code and the readiness report, never a second rendering.
//
//  The switch is Settings > Agents (`AgentSettingsSection`), kept in `AppPreferences.agentDoorEnabled`. Each window enrols on
//  appear and withdraws on disappear; the door names them w1, w2, ...
//

import CoreGraphics
import Foundation
import ShellAgentDoor
import ShellLayout
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

enum Mac4DSTEMAgentDoor {
    /// mac4DSTEM's own port on 127.0.0.1 (macTEM's is 47812), so the copied connection command stays good; another when taken.
    static let port: UInt16 = 47811

    /// The app's one door.
    static let shared: AgentDoor = {
        let door = AgentDoor(appName: "mac4DSTEM", appVersion: FeedbackLinks.appVersion, preferredPort: port)
        door.register(Mac4DSTEMAgentDoor.tools + Mac4DSTEMAgentDoor.runTools + Mac4DSTEMAgentDoor.kernelTools
                      + Mac4DSTEMAgentDoor.scanMapTools + Mac4DSTEMAgentDoor.taskTools + Mac4DSTEMAgentDoor.folderTools)
        return door
    }()

    /// A window appeared: the door lists it, and opens when the person left it on.
    static func enroll(_ state: AppState, enabled: Bool, runsAllowed: Bool) {
        shared.enroll(state) { [weak state] in state?.agentSummary() ?? [:] }
        shared.runsAllowed = runsAllowed
        shared.setEnabled(enabled)
    }

    /// The Agent folder (Settings > Agents) and whether agents may save there (`AgentDoorFolder.swift`); at launch and on change.
    static func setFolder(bookmark: Data?, savesAllowed allowed: Bool) {
        if folderBookmark != bookmark || (bookmark != nil && folder.url == nil) {
            folderBookmark = bookmark
            folder.use(bookmark: bookmark)
        }
        savesAllowed = allowed
    }

    /// The bookmark `folder` was last opened from, so a window that appears does not open it again.
    private static var folderBookmark: Data?

    /// The second switch changed: whether the tools that act (`AgentDoorRuns.swift`) may run.
    static func setRunsAllowed(_ allowed: Bool) {
        shared.runsAllowed = allowed
    }

    /// A window closed.
    static func withdraw(_ state: AppState) {
        shared.withdraw(state)
    }

    /// The switch changed.
    static func setEnabled(_ enabled: Bool) {
        shared.setEnabled(enabled)
    }

    // MARK: Tools

    static let tools: [AgentTool] = [
        AgentTool(name: "get_window", title: "Window state",
                  summary: "Everything one window shows: the dataset and its loaded view, calibration and whether results are quantitative, "
                      + "the workspace, task and its settings, the running operation, the displayed result and its provenance, "
                      + "disk-detection parameters and statistics, saved results and the recipe's steps.",
                  input: .window) { call in
            guard let window = call.window, let state = window.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            var snapshot = state.agentSnapshot()
            snapshot["id"] = window.id
            return .json(snapshot)
        },
        AgentTool(name: "get_result_image", title: "Result picture",
                  summary: "The displayed result (virtual image, strain or orientation map, phase map, ...) as the figure the app exports: "
                      + "colour scale, scale bar and a caption naming units, calibration status and provenance.",
                  input: .windowPicture) { call in
            guard let state = call.window?.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            do { return AgentJSON.picture(try state.resultExportImage(scale: call.scale).image) } catch {
                return .refusal(status: 404, message: error.localizedDescription)
            }
        },
        AgentTool(name: "get_pattern_image", title: "Diffraction pattern picture",
                  summary: "The diffraction pattern as its pane shows it (current scan position, mean or max), with its scale bar. In the "
                      + "Virtual Detector task the detector is outlined; in the Disks task the detected Bragg disks are drawn over the "
                      + "pattern, which is how to judge a detection. Drawn at 2 pixels per point or more, as a Retina screen shows the pane.",
                  input: .windowPicture) { call in
            guard let state = call.window?.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            do { return AgentJSON.picture(try state.agentPatternImage(scale: call.scale)) } catch {
                return .refusal(status: 404, message: error.localizedDescription)
            }
        },
        AgentTool(name: "get_detected_disks", title: "Detected disks",
                  summary: "The detected Bragg disks of the pattern on screen: position in detector pixels and correlation intensity.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            return .json(state.agentPeaks)
        },
        AgentTool(name: "get_lineage", title: "Recipe and lineage",
                  summary: "The recorded analysis steps with their parameters (the recipe) and the run graph they come from.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            guard let data = AgentJSON.encoded(state.agentLineage) else {
                return .refusal(status: 500, message: "The lineage could not be written as JSON.")
            }
            return .encodedJSON(data)
        },
        AgentTool(name: "get_precipitate_objects", title: "Precipitate objects",
                  summary: "The precipitate object table: per object its phase, size, shape, orientation and, where joined, composition, "
                      + "strain and variant; per phase the number density.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            guard let report = state.precipitateObjectReport else {
                return .refusal(status: 404, message: "No precipitate objects yet: the table exists once a phase map has been classified.")
            }
            guard let data = AgentJSON.encoded(report) else {
                return .refusal(status: 500, message: "The object table could not be written as JSON.")
            }
            return .encodedJSON(data)
        },
        AgentTool(name: "get_log", title: "Output log",
                  summary: "The window's Output lines: what ran, what finished, what was refused and why.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return Mac4DSTEMAgentDoor.notAWindow }
            return .json(["lines": state.activityLog.messages])
        },
    ]

    static let notAWindow = AgentToolOutput.refusal(status: 500, message: "That window is not a mac4DSTEM window.")
}
