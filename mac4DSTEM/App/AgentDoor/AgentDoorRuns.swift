//
//  AgentDoorRuns.swift
//  Role: The agent door's tools that act ("run and tune", 5.3.0): an agent moves to a scan position, tunes the disk detection and
//        presses the window's Run, as the person would with the same controls. Each goes through the entry point the control
//        uses (`selectScan`, `diskDetection.diskParams`, `runPrimaryWorkspaceTask`, `cancelActiveOperation`), so the result, the
//        recipe and the Output lines are the ones the button makes.
//
//  The door runs these only while Settings > Agents > "Let agents run analyses" is on (`AppPreferences.agentRunsEnabled`), only
//  through MCP, and the agent's client asks the person before each call (MacEMUI's `AgentTool(acts:)`). One run at a time: a tool
//  is refused while the window is busy, and Stop (or `stop_run`) cancels the run. Nothing here deletes or overwrites a file.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let busyRefusal = AgentToolOutput.refusal(
        status: 409, message: "The window is busy. Wait until get_window says busy is false, or call stop_run.")

    static let runTools: [AgentTool] = [
        AgentTool(name: "select_scan_position", title: "Select scan position",
                  summary: "Shows the diffraction pattern at scan position (x, y), as a click on the scan map does. In the Disks task "
                      + "the detected disks of that pattern are drawn on get_pattern_image.",
                  input: .window,
                  parameters: [AgentParameter("x", .integer(0...100_000), summary: "Scan column, from 0.", required: true),
                               AgentParameter("y", .integer(0...100_000), summary: "Scan row, from 0.", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard let descriptor = state.descriptor, descriptor.is4D else {
                return .refusal(status: 404, message: "This window has no 4D-STEM scan.")
            }
            let x = Int(call.arguments["x"] ?? "") ?? -1, y = Int(call.arguments["y"] ?? "") ?? -1
            guard (0..<descriptor.rx).contains(x), (0..<descriptor.ry).contains(y) else {
                return .refusal(status: 400, message: "The scan is \(descriptor.rx) × \(descriptor.ry): x is 0...\(descriptor.rx - 1), "
                    + "y is 0...\(descriptor.ry - 1).")
            }
            state.selectScan(x: x, y: y)
            state.statusText = "An agent selected scan position (\(x), \(y))."
            return .json(["scan_position": ["x": x, "y": y]])
        },
        AgentTool(name: "set_disk_detection", title: "Tune disk detection",
                  summary: "Changes the Disks task's detection settings, as its sliders do; only the ones given. The detection on the "
                      + "shown pattern follows at once: judge it with get_pattern_image before run_task detects the whole scan.",
                  input: .window,
                  parameters: DiskSetting.all.map(\.parameter) + [subpixelParameter],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            var params = state.diskDetection.diskParams
            if let mode = call.arguments["subpixel"].flatMap(subpixelMode(named:)) { params.subpixel = mode }
            for setting in DiskSetting.all {
                if let text = call.arguments[setting.parameter.name], let value = Double(text) { setting.apply(value, &params) }
            }
            state.diskDetection.diskParams = params
            state.statusText = agentChangeLine("disk detection", call.arguments)
            var answer = diskSettings(of: state)
            if state.probeKernel == nil {
                answer["note"] = "The settings are kept, but no disks are detected yet: this window has no probe kernel. "
                    + "Ask the person to press Build Kernel in the Disks task; the detection then follows these settings."
            }
            return .json(answer)
        },
        AgentTool(name: "run_task", title: "Run",
                  summary: "Presses the window's Run for its current task (Compute Image, Detect Disks on the whole scan, Map Strain, ...), "
                      + "as the toolbar button does. It starts the run and answers at once; get_window says busy until it finishes, "
                      + "and get_log says how it ended.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            guard state.hasPrimaryWorkspaceTask else {
                return .refusal(status: 409, message: "The current task has nothing to run (\(state.navigation.analysisMode.rawValue)).")
            }
            let task = state.navigation.analysisMode.rawValue
            state.statusText = "An agent started Run (\(task))."
            Task { await state.runPrimaryWorkspaceTask() }
            return .json(["started": task])
        },
        AgentTool(name: "stop_run", title: "Stop",
                  summary: "Cancels the run in progress, as the window's Stop button does.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard state.isBusy else { return .refusal(status: 409, message: "Nothing is running.") }
            state.statusText = "An agent pressed Stop."
            state.cancelActiveOperation()
            return .json(["stopping": true])
        },
    ]

    /// The disk detection settings an agent may tune, as `get_window`-style JSON with the problems the sliders would show.
    static func diskSettings(of state: AppState) -> [String: Any] {
        let params = state.diskDetection.diskParams
        var out: [String: Any] = [:]
        for setting in DiskSetting.all { out[setting.parameter.name] = setting.read(params) }
        out["subpixel"] = params.subpixel.provenanceID
        return ["disk_detection": out]
    }

    /// The Subpixel picker, by the recipe's names (issue #235).
    static let subpixelParameter = AgentParameter(
        "subpixel", .choice(SubpixelMode.allCases.map(\.provenanceID)),
        summary: "How each disk is located: pixel (fastest), poly (parabolic, quick) or multicorr (the default: Fourier upsampling, "
            + "strain-grade; upsample_factor applies).")

    static func subpixelMode(named name: String) -> SubpixelMode? {
        SubpixelMode.allCases.first { $0.provenanceID == name }
    }

    /// One slider of the Disks task, as an agent names it.
    struct DiskSetting {
        let parameter: AgentParameter
        let read: (DiskDetectionParams) -> Double
        let apply: (Double, inout DiskDetectionParams) -> Void

        static let all: [DiskSetting] = [
            DiskSetting(parameter: AgentParameter("min_peak_spacing", .number(0...10_000), summary: "Smallest distance between two disks, detector pixels."),
                        read: { Double($0.minPeakSpacing) }, apply: { $1.minPeakSpacing = Float($0) }),
            DiskSetting(parameter: AgentParameter("min_relative_intensity", .number(0...1), summary: "Weakest disk kept, as a fraction of the strongest."),
                        read: { Double($0.minRelativeIntensity) }, apply: { $1.minRelativeIntensity = Float($0) }),
            DiskSetting(parameter: AgentParameter("sigma_cc", .number(0...50), summary: "Gaussian smoothing of the correlation, pixels."),
                        read: { Double($0.sigmaCC) }, apply: { $1.sigmaCC = Float($0) }),
            DiskSetting(parameter: AgentParameter("corr_power", .number(0...1), summary: "1 cross-correlation, 0 phase correlation, between: hybrid."),
                        read: { Double($0.corrPower) }, apply: { $1.corrPower = Float($0) }),
            DiskSetting(parameter: AgentParameter("edge_boundary", .integer(0...10_000), summary: "Disks this close to the detector edge are dropped, pixels."),
                        read: { Double($0.edgeBoundary) }, apply: { $1.edgeBoundary = Int($0) }),
            DiskSetting(parameter: AgentParameter("max_peaks", .integer(1...10_000), summary: "Most disks kept per pattern."),
                        read: { Double($0.maxNumPeaks) }, apply: { $1.maxNumPeaks = Int($0) }),
            // Issue #235: the rest of the Disks task's fields.
            DiskSetting(parameter: AgentParameter("sigma_dp", .number(0...10), summary: "Gaussian smoothing of the pattern before "
                            + "the correlation, pixels; 0 is none."),
                        read: { Double($0.sigmaDP) }, apply: { $1.sigmaDP = Float($0) }),
            DiskSetting(parameter: AgentParameter("upsample_factor", .integer(4...64), summary: "For subpixel multicorr: the "
                            + "Fourier upsampling factor; a disk is located to 1/factor of a pixel."),
                        read: { Double($0.upsampleFactor) }, apply: { $1.upsampleFactor = Int($0) }),
            DiskSetting(parameter: AgentParameter("min_absolute_intensity", .number(0...1e12), summary: "Weakest disk kept, in "
                            + "correlation units (the CC field); 0 turns it off."),
                        read: { Double($0.minAbsoluteIntensity) }, apply: { $1.minAbsoluteIntensity = Float($0) }),
            DiskSetting(parameter: AgentParameter("relative_to_peak", .integer(0...10_000), summary: "min_relative_intensity is "
                            + "measured against the candidate of this intensity rank, from 0 (the brightest; Reference peak #1)."),
                        read: { Double($0.relativeToPeak) }, apply: { $1.relativeToPeak = Int($0) }),
            DiskSetting(parameter: AgentParameter("relative_reference_min_radius_px", .number(0...10_000), summary: "The relative "
                            + "filter's reference is the brightest candidate at least this many pixels from the brightest one, so a "
                            + "saturated direct beam does not set the scale; 0 keeps py4DSTEM's rule (the brightest anywhere)."),
                        read: { Double($0.relativeReferenceMinimumRadiusPx) },
                        apply: { $1.relativeReferenceMinimumRadiusPx = Float($0) }),
        ]
    }
}
