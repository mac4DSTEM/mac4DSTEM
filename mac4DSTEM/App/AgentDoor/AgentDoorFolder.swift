//
//  AgentDoorFolder.swift
//  Role: The agent door's folder tools (issue #191): an agent works through the files of the one Agent folder the person chose in
//        Settings > Agents (`AgentFolder`): it lists them, opens one in a window as File > Open does, and saves the displayed
//        result there as File > Export > Result Image does. Batch work is a loop of these with the run tools
//        (`AgentDoorRuns.swift`).
//
//  Listing only looks. Opening acts, so it needs "Let agents run analyses"; saving also needs "Let agents save results there"
//  (`AppPreferences.agentFolderSavesEnabled`), off by default. A save never replaces a file: a name that exists is refused.
//  Nothing outside the folder is listed, opened or written.
//

import CoreGraphics
import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// The Agent folder the tools work in.
    static let folder = AgentFolder()

    /// Whether the person lets agents write into the Agent folder (Settings > Agents).
    static var savesAllowed = false

    static let folderTools: [AgentTool] = [
        AgentTool(name: "list_agent_folder", title: "Agent folder files",
                  summary: "The files in the Agent folder the person chose in Settings > Agents (and its subfolders): path relative to "
                      + "the folder, size in bytes, modification date. open_file opens one; save_result_image saves into the folder.",
                  input: .noWindow) { _ in
            guard let listed = folder.listing() else { return .refusal(status: 404, message: AgentFolder.noFolder) }
            return .json(["folder": folder.url?.lastPathComponent ?? "", "files": listed.files, "truncated": listed.truncated])
        },
        AgentTool(name: "open_file", title: "Open file",
                  summary: "Opens a file of the Agent folder in the window, as File > Open does, replacing the dataset it shows. It "
                      + "starts the open and answers at once; get_window says busy until the dataset is in, and get_log says if it failed.",
                  input: .window,
                  parameters: [AgentParameter("path", .text, summary: "The file, relative to the Agent folder, as list_agent_folder "
                                                  + "names it.", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let file: URL
            switch folder.resolve(call.arguments["path"] ?? "") {
            case .success(let url): file = url
            case .failure(let refusal): return .refusal(status: 404, message: refusal.message)
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
                return .refusal(status: 404, message: "There is no file \(folder.relativePath(of: file)) in the Agent folder.")
            }
            state.statusText = "An agent opened \(file.lastPathComponent)."
            Task { await state.openFileAsync(url: file) }
            return .json(["opening": folder.relativePath(of: file)])
        },
        AgentTool(name: "save_result_image", title: "Save result picture",
                  summary: "Saves the displayed result into the Agent folder as File > Export > Result Image does: a PNG with the "
                      + "colour scale, scale bar and caption drawn in and the full provenance record in its metadata. Never replaces "
                      + "a file: a name that exists is refused.",
                  input: .window,
                  parameters: [AgentParameter("name", .text, summary: "The file name, without folders; .png is added. Leave out for "
                                                  + "the dataset's name followed by _result.")],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard savesAllowed else {
                return .refusal(status: 403, message: "Saving is off. Ask the person to turn on \"Let agents save results there\" in "
                    + "mac4DSTEM's Settings > Agents.")
            }
            guard !state.isBusy else { return busyRefusal }
            guard let root = folder.url else { return .refusal(status: 404, message: AgentFolder.noFolder) }
            let name: String
            switch fileName(call.arguments["name"], default: state.exportBaseName + "_result") {
            case .success(let made): name = made
            case .failure(let refusal): return .refusal(status: 400, message: refusal.message)
            }
            let target = root.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                return .refusal(status: 409, message: "\(name) exists in the Agent folder and is never replaced: choose another name.")
            }
            let scale = state.preferences.exportScale.pixelScale
            let made: (image: CGImage, product: DisplayedProduct)
            do { made = try state.resultExportImage(scale: scale) } catch {
                return .refusal(status: 404, message: error.localizedDescription)
            }
            let properties = AppState.pngProperties(title: state.currentResultDisplayName,
                                                    record: state.exportedImageProvenanceRecord(), pixelScale: scale)
            guard AppState.writePNG(made.image, to: target, properties: properties) else {
                return .refusal(status: 500, message: "Writing \(name) failed.")
            }
            state.statusText = "An agent saved \(name) in the Agent folder."
            state.recordExportRun(format: "png", fileName: name, productKind: made.product.kind,
                                  productStep: made.product.provenance["lineage_step"])
            return .json(["saved": name, "width": made.image.width, "height": made.image.height])
        },
    ]

    /// A save's file name: letters, digits, spaces, `-`, `_` and `.`, no folders, ending in .png.
    static func fileName(_ given: String?, default fallback: String) -> Result<String, AgentFolderRefusal> {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        var name = (given ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {   // the dataset's own name may hold any character: those outside the rule become _
            var kept = String.UnicodeScalarView()
            for scalar in fallback.unicodeScalars { kept.append(allowed.contains(scalar) ? scalar : Unicode.Scalar("_")) }
            name = String(kept)
            while name.hasPrefix(".") { name = "_" + String(name.dropFirst()) }
        }
        if name.lowercased().hasSuffix(".png") { name = String(name.dropLast(4)) }
        guard !name.isEmpty, !name.hasPrefix("."), name.unicodeScalars.allSatisfy(allowed.contains) else {
            return .failure(AgentFolderRefusal("A file name is letters, digits, spaces, - _ and . only, without folders, and does "
                + "not start with a dot."))
        }
        return .success(name + ".png")
    }
}
