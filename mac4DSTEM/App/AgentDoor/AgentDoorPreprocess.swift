//
//  AgentDoorPreprocess.swift
//  Role: The agent door's open options and preprocessing (issue #230; Paul, 12 Nov: "Prepress and ask where to store eg a binned
//        version and I could prompt it to continue with the binned dataset").
//
//  - `open_file_with_options` opens a file of the Agent folder in the load configurator, as File > Open with Options… does;
//    `set_open_options` sets its scan crop, detector crop, detector bin and keep-in-memory, and loads it or discards it.
//  - `preprocess` writes a reduced copy of the open dataset (crop, bin, scan stride, hot-pixel filter) as a new py4DSTEM DataCube,
//    the writer File > Preprocess Raw Data… uses. Where it goes: a new file in the Agent folder, named as the person said in the
//    chat (behind "Let agents save results there"), or `ask_person` true puts the Save dialog on the Mac so the person picks the
//    place. `open_after` opens the copy in the window when it is written, so the analysis carries on with it.
//  Nothing is ever replaced: the Agent folder write refuses a name that exists; the Save dialog asks the person as it always does.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {

    /// The crop and bin parameters both tools share.
    static let reductionParameters: [AgentParameter] = [
        AgentParameter("scan_x", .integer(0...1_000_000), summary: "Scan crop: first column."),
        AgentParameter("scan_y", .integer(0...1_000_000), summary: "Scan crop: first row."),
        AgentParameter("scan_width", .integer(1...1_000_000), summary: "Scan crop: columns."),
        AgentParameter("scan_height", .integer(1...1_000_000), summary: "Scan crop: rows."),
        AgentParameter("detector_x", .integer(0...1_000_000), summary: "Detector crop: first column."),
        AgentParameter("detector_y", .integer(0...1_000_000), summary: "Detector crop: first row."),
        AgentParameter("detector_width", .integer(1...1_000_000), summary: "Detector crop: columns."),
        AgentParameter("detector_height", .integer(1...1_000_000), summary: "Detector crop: rows."),
        AgentParameter("detector_bin", .integer(1...64), summary: "Detector binning factor (1 none)."),
        AgentParameter("full_extent", .boolean, summary: "true drops every crop and the binning first (Reset)."),
    ]

    /// The crop and bin an agent named, applied to a load configuration; the refusal when the result is not a valid view.
    static func applyReduction(_ a: [String: String], to configuration: inout LoadConfiguration) -> String? {
        if a["full_extent"] == "true" {
            configuration.scanCrop = nil; configuration.detectorCrop = nil; configuration.detectorBin = 1
        }
        func crop(_ prefix: String, _ current: AxisCrop?, height fullH: Int, width fullW: Int) -> AxisCrop?? {
            let keys = ["x", "y", "width", "height"].map { prefix + "_" + $0 }
            guard keys.contains(where: { a[$0] != nil }) else { return .none }
            let x = a[keys[0]].flatMap(Int.init) ?? current?.xOffset ?? 0
            let y = a[keys[1]].flatMap(Int.init) ?? current?.yOffset ?? 0
            let w = a[keys[2]].flatMap(Int.init) ?? current?.width ?? (fullW - x)
            let h = a[keys[3]].flatMap(Int.init) ?? current?.height ?? (fullH - y)
            return .some(AxisCrop(yOffset: y, xOffset: x, height: h, width: w))
        }
        let source = configuration.source
        if let scan = crop("scan", configuration.scanCrop, height: source.ry, width: source.rx) { configuration.scanCrop = scan }
        if let det = crop("detector", configuration.detectorCrop, height: source.qy, width: source.qx) { configuration.detectorCrop = det }
        if let bin = a["detector_bin"].flatMap(Int.init) { configuration.detectorBin = bin }
        guard configuration.view != nil else {
            return "That crop and binning do not fit the dataset (\(source.ry)×\(source.rx) scan, \(source.qy)×\(source.qx) detector)."
        }
        return nil
    }

    static func reductionSummary(_ configuration: LoadConfiguration) -> [String: Any] {
        let s = configuration.source
        func crop(_ c: AxisCrop?) -> Any {
            guard let c else { return NSNull() }
            return ["x": c.xOffset, "y": c.yOffset, "width": c.width, "height": c.height]
        }
        return ["source_scan": [s.ry, s.rx], "source_detector": [s.qy, s.qx],
                "scan_crop": crop(configuration.scanCrop), "detector_crop": crop(configuration.detectorCrop),
                "detector_bin": configuration.detectorBin, "bytes": AgentJSON.orNull(configuration.byteCount)]
    }

    static let preprocessTools: [AgentTool] = [
        AgentTool(name: "open_file_with_options", title: "Open with options",
                  summary: "Opens a file of the Agent folder in the load configurator, as File > Open with Options… does: nothing "
                      + "is loaded until set_open_options says load. get_window's pending_open shows it once its preview is in.",
                  input: .window,
                  parameters: [AgentParameter("path", .text, summary: "The file, relative to the Agent folder.", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            switch folder.resolve(call.arguments["path"] ?? "") {
            case .failure(let refusal): return .refusal(status: 404, message: refusal.message)
            case .success(let url):
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return .refusal(status: 404, message: "There is no file \(folder.relativePath(of: url)) in the Agent folder.")
                }
                state.statusText = "An agent opened \(url.lastPathComponent) with options."
                state.openFileForConfiguration(url: url)
                return .json(["configuring": folder.relativePath(of: url)])
            }
        },
        AgentTool(name: "set_open_options", title: "Open options",
                  summary: "Sets the load configurator's scan crop, detector crop and binning (in source pixels) and keep in memory, "
                      + "then, with action load, loads that view into the window (as Load does), or with action discard drops it. "
                      + "The direct beam must stay inside the detector crop.",
                  input: .window,
                  parameters: reductionParameters + [
                      AgentParameter("keep_in_memory", .boolean, summary: "Read the whole view into memory (refused when too large)."),
                      AgentParameter("action", .choice(["set", "load", "discard"]), summary: "set (default), load or discard."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard let pending = state.promotionRun.pendingLoad, pending.preprocess == nil else {
                return .refusal(status: 409, message: "Nothing is waiting in the load configurator; open_file_with_options first.")
            }
            if call.arguments["action"] == "discard" {
                state.discardPendingLoad()
                return .json(["discarded": true])
            }
            var configuration = pending.configuration
            if let refusal = applyReduction(call.arguments, to: &configuration) { return .refusal(status: 400, message: refusal) }
            pending.configuration = configuration
            if let keep = call.arguments["keep_in_memory"] { pending.keepInMemory = keep == "true" }
            var answer = reductionSummary(configuration)
            answer["keep_in_memory"] = pending.effectiveKeepInMemory
            answer["direct_beam_refusal"] = AgentJSON.orNull(pending.directBeamRefusal)
            if call.arguments["action"] == "load" {
                if let refusal = pending.directBeamRefusal ?? pending.refusalReason {
                    return .refusal(status: 409, message: refusal)
                }
                guard pending.preview != nil else {
                    return .refusal(status: 409, message: "The preview is still being sampled; ask again in a moment.")
                }
                state.statusText = agentChangeLine("the open options", call.arguments)
                state.commitPendingLoad()
                answer["loading"] = true
            }
            return .json(answer)
        },
        AgentTool(name: "preprocess", title: "Preprocess",
                  summary: "Writes a reduced copy of the open dataset as a new py4DSTEM DataCube (.h5), as File > Preprocess Raw Data… "
                      + "does: scan and detector crop, detector binning, scan stride and the hot-pixel filter. The source never "
                      + "changes. Where: ask the person in the chat first. Then either name (a new file in the Agent folder; needs "
                      + "\"Let agents save results there\") or ask_person true (the Mac's Save dialog, the person picks). open_after "
                      + "true opens the copy in this window when it is written. It answers at once; get_window says busy until done.",
                  input: .window,
                  parameters: reductionParameters + [
                      AgentParameter("scan_stride", .integer(1...1024), summary: "Keep every n-th scan position."),
                      AgentParameter("hot_pixels", .boolean, summary: "Filter hot pixels."),
                      AgentParameter("hot_pixel_threshold", .number(1...1000), summary: "Hot-pixel threshold (default 8)."),
                      AgentParameter("name", .text, summary: "A new file in the Agent folder; .h5 is added."),
                      AgentParameter("ask_person", .boolean, summary: "true: the Save dialog asks the person where."),
                      AgentParameter("open_after", .boolean, summary: "true: open the copy when written and carry on with it."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard let descriptor = state.descriptor, let pending = state.makeCurrentViewPending(descriptor: descriptor) else {
                return .refusal(status: 404, message: "This window has no dataset open to preprocess.")
            }
            let a = call.arguments
            var configuration = pending.configuration
            if let refusal = applyReduction(a, to: &configuration) { return .refusal(status: 400, message: refusal) }
            pending.configuration = configuration
            if let stride = a["scan_stride"].flatMap(Int.init) { pending.preprocess?.scanStride = stride }
            if let hot = a["hot_pixels"] { pending.preprocess?.hotPixelsEnabled = hot == "true" }
            if let threshold = a["hot_pixel_threshold"].flatMap(Double.init) { pending.preprocess?.hotPixelThreshold = threshold }

            let suggested = PreprocessDraft.suggestedFileName(forSource: descriptor.fileName)
            let destination: URL
            if a["ask_person"] == "true" {
                guard let chosen = state.choosePreprocessDestination(suggestedName: suggested) else {
                    return .refusal(status: 409, message: "The person cancelled the Save dialog; nothing was written.")
                }
                destination = chosen
            } else {
                guard a["name"] != nil else {
                    return .refusal(status: 400, message: "Say where: ask the person, then give name (Agent folder) or ask_person true.")
                }
                guard savesAllowed else {
                    return .refusal(status: 403, message: "Saving is off. Ask the person to turn on \"Let agents save results "
                        + "there\" in Settings > Agents, or use ask_person true.")
                }
                guard let root = folder.url else { return .refusal(status: 404, message: AgentFolder.noFolder) }
                switch fileName(a["name"], default: suggested, extension: "h5") {
                case .failure(let refusal): return .refusal(status: 400, message: refusal.message)
                case .success(let name):
                    let target = root.appendingPathComponent(name)
                    guard (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil else {
                        return .refusal(status: 409, message: "\(name) exists in the Agent folder and is never replaced: choose another name.")
                    }
                    destination = target
                }
            }
            let openAfter = a["open_after"] == "true"
            state.statusText = "An agent started preprocessing into \(destination.lastPathComponent)."
            state.writePreprocessed(pending: pending, to: destination) { outcome in
                switch outcome {
                case .wrote(let message):
                    state.statusText = "An agent preprocessed: " + message
                    if openAfter { Task { await state.openFileAsync(url: destination) } }
                case .failed(let message):
                    state.statusText = "An agent's preprocessing failed: " + message
                case .cancelled:
                    state.statusText = "An agent's preprocessing was cancelled."
                }
            }
            var answer = reductionSummary(configuration)
            answer["writing"] = destination.lastPathComponent
            answer["open_after"] = openAfter
            return .json(answer)
        },
    ]
}
