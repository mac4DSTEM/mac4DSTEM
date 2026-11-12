//
//  AgentDoorResults.swift
//  Role: The agent door's saving, exporting and comparing (issue #229): Save to Session, the data, bundle and figure exports into
//        the Agent folder, the A/B comparison of saved results, the quality field, Rewind to Here and Reopen at Full Extent.
//
//  Exports go only into the Agent folder, behind "Let agents save results there", and never replace a file; they use the writers
//  the Export menu uses, so a file means the same whichever door wrote it.
//

import Foundation
import ShellAgentDoor
import ShellSpectroscopy
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {

    /// A new file's place in the Agent folder: the name made by `fileName`, refused when anything of that name exists.
    static func newAgentFolderTarget(_ given: String?, default fallback: String, extension ext: String) -> Result<URL, ToolRefusal> {
        guard savesAllowed else {
            return .failure(ToolRefusal(status: 403, message: "Saving is off. Ask the person to turn on \"Let agents save results "
                + "there\" in mac4DSTEM's Settings > Agents."))
        }
        guard let root = folder.url else { return .failure(ToolRefusal(status: 404, message: AgentFolder.noFolder)) }
        switch fileName(given, default: fallback, extension: ext) {
        case .failure(let refusal): return .failure(ToolRefusal(status: 400, message: refusal.message))
        case .success(let name):
            let target = root.appendingPathComponent(name)
            guard (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil else {
                return .failure(ToolRefusal(status: 409, message: "\(name) exists in the Agent folder and is never replaced: choose another name."))
            }
            return .success(target)
        }
    }

    static let resultTools: [AgentTool] = [
        AgentTool(name: "save_to_session", title: "Save to Session",
                  summary: "Keeps the displayed result with this dataset in its session sidecar, as Save to Session does: it appears "
                      + "in Results and survives reopening. get_window's session lists the saved results.",
                  input: .window,
                  parameters: [AgentParameter("ask_person", .boolean, summary: "true: when this dataset's sidecar has no place yet "
                                                  + "and the dataset is outside the Agent folder, the Mac's Save dialog asks the person.")],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            if let reason = ResultsActionReason.saveToSession(
                isLoading: state.datasetSession.isLoading, hasDisplayedProduct: state.displayedProduct != nil,
                isBusy: state.isBusy, sidecarRefusal: state.gates.sidecarRewriteRefusal()) {
                return .refusal(status: 409, message: reason)
            }
            if let refusal = prepareSidecarPlace(state, askPerson: call.arguments["ask_person"] == "true") {
                return .refusal(status: refusal.status, message: refusal.message)
            }
            state.saveCurrentResultToSessionSidecar()
            state.statusText = "An agent saved the result to the session. " + state.statusText
            // The write runs on; the new result is listed once it lands (get_window's session, when busy is false).
            return .json(["saving": AgentJSON.orNull(state.displayedProduct?.kind), "saved_before": savedResults(of: state)])
        },
        AgentTool(name: "export_result", title: "Export result",
                  summary: "Writes the displayed result into the Agent folder as the Export menu does: data (the numbers behind "
                      + "the view, an EMD RealSlice .h5), bundle (every strain and orientation field of the session, one .h5) or "
                      + "figure (the result and the pattern side by side, in the format Settings names). Needs \"Let agents save "
                      + "results there\"; never replaces a file. A long write answers at once; get_log says when it is done.",
                  input: .window,
                  parameters: [
                      AgentParameter("what", .choice(["data", "bundle", "figure"]), summary: "What to write.", required: true),
                      AgentParameter("name", .text, summary: "The file name, without folders; the extension is added."),
                      AgentParameter("figure_panels", .text, summary: "Figure only: the panels, comma-separated ids (result, pattern, "
                                         + "map.eds); leave out for every panel there is."),
                      AgentParameter("figure_detector", .boolean, summary: "Figure only: outline the virtual detector on the pattern."),
                      AgentParameter("figure_format", .choice(caseNames(ExportFigureFormat.self)),
                                     summary: "Figure only: png, pdf or tiff. Kept for later figures, as the picker keeps it."),
                      AgentParameter("figure_size", .choice(ExportImageScale.allCases.map(\.rawValue)),
                                     summary: "Figure only: 1x, 2x or 3x pixels. Kept, as the picker keeps it."),
                      AgentParameter("figure_regions", .boolean, summary: "Figure only: outline the selected region on the EDS maps."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard let descriptor = state.descriptor else { return .refusal(status: 404, message: "This window has no dataset open.") }
            let what = call.arguments["what"] ?? ""
            if what == "figure" {
                let choices = state.figureChoices
                var chosen = Set(choices.filter(\.isDefault).map(\.id))
                if let wanted = call.arguments["figure_panels"] {
                    chosen = Set(wanted.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                    let unknown = chosen.subtracting(choices.map(\.id))
                    guard unknown.isEmpty, !chosen.isEmpty else {
                        return .refusal(status: 404, message: "This window's figure panels are "
                            + choices.map(\.id).joined(separator: ", ") + ".")
                    }
                }
                guard !chosen.isEmpty else { return .refusal(status: 409, message: "There is nothing to put in a figure yet.") }
                if let v = named(call.arguments["figure_format"], ExportFigureFormat.self) { state.preferences.figureFormat = v }
                if let v = call.arguments["figure_size"].flatMap(ExportImageScale.init(rawValue:)) { state.preferences.exportScale = v }
                if let v = call.arguments["figure_regions"], state.hasSpectrumImage { state.edxRoom.exportRegions = v == "true" }
                let detector = call.arguments["figure_detector"].map { $0 == "true" }
                let file: FigureFile
                do { file = try state.figureFile(chosen: chosen, detector: detector) } catch {
                    return .refusal(status: 409, message: error.localizedDescription)
                }
                let ext = caseName(file.format)
                let stem = (file.suggestedName as NSString).deletingPathExtension
                switch saveNewFile(file.data, named: call.arguments["name"], default: stem, extension: ext) {
                case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
                case .success(let name):
                    state.statusText = "An agent exported the figure → \(name) in the Agent folder."
                    return .json(["saved": name])
                }
            }
            let maps: [ScalarResultMap]
            let fallback: String
            if what == "bundle" {
                guard let bundle = state.scientificBundleMaps() else {
                    return .refusal(status: 409, message: "Compute a strain or orientation map before exporting a bundle.")
                }
                maps = bundle; fallback = state.exportBaseName + "_scientific_bundle"
            } else {
                guard let map = state.productDataExportMap() else {
                    return .refusal(status: 409, message: "This view has no scalar data to export.")
                }
                maps = [map]; fallback = state.exportBaseName + "_" + String(map.kind.map { $0.isLetter || $0.isNumber ? $0 : "_" })
            }
            let target: URL
            switch newAgentFolderTarget(call.arguments["name"], default: fallback, extension: "h5") {
            case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
            case .success(let url): target = url
            }
            let calibration = state.sessionPixelCalibration(descriptor: descriptor)
            let token = state.beginCancellableOperation("Export data", status: "Writing \(target.lastPathComponent)…", totalUnits: maps.count)
            let source = descriptor.filePath
            Task { @MainActor in
                defer { state.finishCancellableOperation(token) }
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try BraggVectorEMDWriter.writeScientificBundle(maps: maps, calibration: calibration, to: target,
                                                                       sourcePath: source, cancellation: token)
                    }.value
                    guard state.isCurrentOperation(token) else { return }
                    state.recordExportRun(format: what == "bundle" ? "emd_scientific_bundle" : "emd_realslice",
                                          fileName: target.lastPathComponent, productKind: maps.first?.kind)
                    state.statusText = "An agent exported \(maps.count) field(s) → \(target.lastPathComponent) in the Agent folder."
                } catch {
                    state.statusText = "An agent's export failed: \(error.localizedDescription)"
                }
            }
            return .json(["writing": target.lastPathComponent, "fields": maps.map(\.kind)])
        },
        AgentTool(name: "compare_results", title: "Compare saved results",
                  summary: "Loads saved results of this session into the comparison's A and B, as Set as A and Set as B do, or clears "
                      + "it. Name a result by its id or display name, as get_window's session.saved_results lists them. Nothing "
                      + "is recomputed; select_task workspace results shows the comparison and get_result_image draws it.",
                  input: .window,
                  parameters: [
                      AgentParameter("a", .text, summary: "The saved result for A."),
                      AgentParameter("b", .text, summary: "The saved result for B."),
                      AgentParameter("clear", .boolean, summary: "true empties the comparison."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            if call.arguments["clear"] == "true" { state.clearComparison() }
            let saved = state.sessionInventory.results
            let slots: [(String, ComparisonSlot)] = [("a", .a), ("b", .b)]
            var loads: [(SessionResultDescriptor, ComparisonSlot)] = []
            for (key, slot) in slots {
                guard let wanted = call.arguments[key] else { continue }
                guard let result = saved.first(where: { $0.id == wanted }) ?? saved.first(where: { $0.displayName == wanted }) else {
                    return .refusal(status: 404, message: "No saved result \(wanted); this session has "
                        + (saved.isEmpty ? "none (save_to_session)." : saved.map(\.displayName).joined(separator: ", ") + "."))
                }
                loads.append((result, slot))
            }
            state.statusText = agentChangeLine("the comparison", call.arguments)
            Task { for (result, slot) in loads { await state.loadSavedSessionResult(result, into: slot) } }
            return .json(["loading": loads.map { ["slot": $0.1 == .a ? "a" : "b", "id": $0.0.id] },
                          "saved_results": savedResults(of: state)])
        },
        AgentTool(name: "show_quality_field", title: "Inspect quality field",
                  summary: "Shows the quality field paired with the displayed result instead of the result (true) or the result "
                      + "again (false), as the pane's toggle does. Display only: exports and saved products do not change.",
                  input: .window,
                  parameters: [AgentParameter("show", .boolean, summary: "true shows the quality field.", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            state.resultPresentation.inspectQualityField = call.arguments["show"] == "true"
            state.statusText = "An agent " + (state.resultPresentation.inspectQualityField ? "showed" : "hid") + " the quality field."
            return .json(["quality_field_shown": state.resultPresentation.inspectQualityField])
        },
        AgentTool(name: "rewind_lineage", title: "Rewind to Here",
                  summary: "Puts the settings of a recorded step back, as Rewind to Here does: name the step by its id from get_lineage. "
                      + "Later steps stay recorded; their tasks re-run them. It answers at once.",
                  input: .window,
                  parameters: [AgentParameter("step", .text, summary: "The step's id, from get_lineage.", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let step = call.arguments["step"] ?? ""
            if case .failure(let refusal) = state.replay.lineage.rewindPlan(to: step) {
                return .refusal(status: 404, message: refusal.description)
            }
            Task { await state.rewindLineage(to: step) }
            return .json(["rewinding_to": step, "note": "get_window's status says when it is done, or why it was refused."])
        },
        AgentTool(name: "reopen_full_extent", title: "Reopen at Full Extent",
                  summary: "Reopens a cropped or binned dataset at its full extent and replays the recorded recipe on it, as Reopen at "
                      + "Full Extent does. It answers at once; get_window says busy until the replay is done.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            state.statusText = "An agent pressed Reopen at Full Extent."
            Task { await state.promoteAndReplayRecipe() }
            return .json(["started": true])
        },
    ]

    /// Where Save to Session writes when this dataset's sidecar has no place yet (the app would ask with a Save panel, and a
    /// panel must never hold a door call): beside a dataset inside the Agent folder while saves are allowed, the Save panel when
    /// the agent says the person is asked, else a refusal that says so. nil when the save may go ahead.
    static func prepareSidecarPlace(_ state: AppState, askPerson: Bool) -> ToolRefusal? {
        guard let descriptor = state.descriptor, state.sessionSidecar.grant(for: descriptor) == nil else { return nil }
        let derived = state.sessionSidecar.derivedLocation(forSourcePath: descriptor.filePath)
        if let root = folder.url, savesAllowed,
           derived.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") {
            state.sessionSidecar.adopt(derived, for: descriptor)
            return nil
        }
        if askPerson { return nil }
        return ToolRefusal(status: 409, message: "This dataset's session sidecar has no place yet and the dataset is outside the "
            + "Agent folder" + (savesAllowed ? "" : " (or saving there is off)") + ". Ask the person, then call again with ask_person "
            + "true so the Save dialog asks where, or open a copy that sits in the Agent folder.")
    }

    static func savedResults(of state: AppState) -> [[String: Any]] {
        state.sessionInventory.results.map { ["id": $0.id, "name": $0.displayName, "kind": $0.kind] }
    }
}
