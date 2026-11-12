//
//  AgentDoorPhases.swift
//  Role: The agent door's phase list tools (issue #192): an agent puts the phases of Map Phases together from CIFs in the Agent
//        folder, marks the matrix, sets a phase's own excitation slab (and, with typed zone axes, its zone axis and relationship
//        to the matrix), and takes a phase out — what the phase list's Add Phase menu, matrix picker, fields and minus button do.
//        Map Phases then runs by run_task, and get_window's phase_mapping.last_run says what the map found.
//
//  A phase is named by its index in get_window's phase_mapping.phases (from 0), since the same structure can be in the list twice
//  (typed zone axes). Every change writes an Output line that names the agent and the phase.
//

import Foundation
import ShellAgentDoor
import DiffractoOrientation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let phaseTools: [AgentTool] = [
        AgentTool(name: "add_phase", title: "Add phase from CIF",
                  summary: "Adds a phase to Map Phases' phase list from a CIF file in the Agent folder, as Add Phase > From CIF file "
                      + "does. The first phase in an empty list is the matrix; is_matrix true makes this one the matrix instead. "
                      + "Answers the phase list (get_window's phase_mapping).",
                  input: .window,
                  parameters: [
                      AgentParameter("path", .text, summary: "The CIF, relative to the Agent folder, as list_agent_folder names it.",
                                     required: true),
                      AgentParameter("is_matrix", .boolean, summary: "Make this phase the matrix (default false)."),
                  ],
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
            let model: CrystalModel
            do {
                model = try state.importCrystalModelOrThrow(from: file)
            } catch {
                return .refusal(status: 422, message: "\(file.lastPathComponent) is not a usable CIF: "
                    + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
            state.addPhaseMappingSlot(model)
            let product = state.phaseMapping
            if call.arguments["is_matrix"] == "true" { markMatrix(product.phases.count - 1, in: product) }
            let role = product.phases.last?.isMatrix == true ? " as the matrix" : ""
            state.statusText = "An agent added the phase \(model.displayName)\(role) from \(file.lastPathComponent)."
            return .json(phaseMappingSettings(of: state))
        },
        AgentTool(name: "set_phase", title: "Change a phase",
                  summary: "Changes one phase of Map Phases' phase list, as its row and the matrix picker do; only what is given. "
                      + "The excitation slab is how far from the Bragg condition this phase's reflections still count as excited: "
                      + "a thin plate or needle needs more than the bulk (empty is the default, py4DSTEM's 0.06 Å⁻¹ for a structures "
                      + "run). Zone axis and relationship are used only with typed zone axes (set_phase_mapping orientation_source).",
                  input: .window,
                  parameters: [
                      AgentParameter("index", .integer(0...999), summary: "The phase, by its index in get_window's "
                                         + "phase_mapping.phases (from 0).", required: true),
                      AgentParameter("is_matrix", .boolean, summary: "true makes this phase the matrix (exactly one is). To "
                                         + "change the matrix, mark the other phase."),
                      AgentParameter("excitation_slab_inv_angstrom", .number(0.001...1), summary: "This phase's own "
                                         + "excitation slab, Å⁻¹."),
                      AgentParameter("clear_excitation_slab", .boolean, summary: "true goes back to the default slab."),
                      AgentParameter("zone_axis", .text, summary: "Typed zone axes: the beam direction as \"u v w\", e.g. \"0 0 1\"."),
                      AgentParameter("orientation_relationship", .text, summary: "Typed zone axes: parallel lattice vectors to "
                                         + "the matrix as a paper states them, e.g. \"(002) ∥ (200)\"; empty is any rotation."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let product = state.phaseMapping
            guard let index = call.arguments["index"].flatMap(Int.init), product.phases.indices.contains(index) else {
                return .refusal(status: 404, message: noPhase(call.arguments["index"], product))
            }
            if call.arguments["is_matrix"] == "false", product.phases[index].isMatrix {
                return .refusal(status: 409, message: "Exactly one phase is the matrix; mark another phase as the matrix instead.")
            }
            if call.arguments["clear_excitation_slab"] == "true", call.arguments["excitation_slab_inv_angstrom"] != nil {
                return .refusal(status: 400, message: "Give excitation_slab_inv_angstrom or clear_excitation_slab, not both.")
            }
            var axis: SIMD3<Int>?
            if let text = call.arguments["zone_axis"] {
                guard let parsed = PhaseMappingSlot.parseZoneAxis(text) else {
                    return .refusal(status: 400, message: "zone_axis must be three whole numbers like \"0 0 1\", not \(text).")
                }
                axis = parsed
            }
            if let text = call.arguments["orientation_relationship"],
               PhaseMappingSlot.parseOrientationRelationships(text) == nil {
                return .refusal(status: 400, message: "orientation_relationship must be pairs like \"(002) ∥ (200)\", not \(text).")
            }
            let id = product.phases[index].id
            product.updatePhase(id: id) { slot in
                if let value = call.arguments["excitation_slab_inv_angstrom"].flatMap(Double.init) {
                    slot.excitationSlabInvAngstrom = value
                }
                if call.arguments["clear_excitation_slab"] == "true" { slot.excitationSlabInvAngstrom = nil }
                if let axis { slot.u = axis.x; slot.v = axis.y; slot.w = axis.z }
                if let text = call.arguments["orientation_relationship"] { slot.orientationRelationshipText = text }
            }
            if call.arguments["is_matrix"] == "true" { markMatrix(index, in: product) }
            var changes = call.arguments
            changes["index"] = nil
            state.statusText = agentChangeLine("the phase \(product.phases[index].model.displayName)", changes)
            return .json(phaseMappingSettings(of: state))
        },
        AgentTool(name: "remove_phase", title: "Remove phase",
                  summary: "Takes a phase out of Map Phases' phase list, as its minus button does (Edit > Undo puts it back). "
                      + "Removing the matrix makes the first remaining phase the matrix.",
                  input: .window,
                  parameters: [AgentParameter("index", .integer(0...999), summary: "The phase, by its index in get_window's "
                                                  + "phase_mapping.phases (from 0).", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let product = state.phaseMapping
            guard let index = call.arguments["index"].flatMap(Int.init), product.phases.indices.contains(index) else {
                return .refusal(status: 404, message: noPhase(call.arguments["index"], product))
            }
            let slot = product.phases[index]
            state.removePhaseMappingSlot(slotID: slot.slotID)
            state.statusText = "An agent removed the phase \(slot.model.displayName)."
            return .json(phaseMappingSettings(of: state))
        },
    ]

    /// The matrix picker's rule: exactly one phase is the matrix.
    static func markMatrix(_ index: Int, in product: PhaseMappingProduct) {
        for i in product.phases.indices { product.phases[i].isMatrix = i == index }
    }

    private static func noPhase(_ given: String?, _ product: PhaseMappingProduct) -> String {
        product.phases.isEmpty
            ? "The phase list is empty; add_phase adds one."
            : "There is no phase \(given ?? "") in the list; the indexes are 0 to \(product.phases.count - 1)."
    }

    /// What the last Map Phases run found, as an agent judges it: how many positions each phase won, the matrix, the positions
    /// nothing explained, where the orientations came from, the relationships a structures run learned and the slab each phase
    /// was searched with, whether the settings moved since, and the evidence at the selected scan position. Null before a run.
    static func phaseMappingLastRun(of state: AppState) -> Any {
        let product = state.phaseMapping
        guard let map = product.map, let run = product.lastRun else { return NSNull() }
        let counts = map.phaseCounts
        let perPhase: [[String: Any]] = map.phaseNames.indices.map { i in
            ["name": map.phaseNames[i], "is_matrix": i == map.matrixPhaseIndex,
             "positions": counts.indices.contains(i) ? counts[i] : 0] as [String: Any]
        }
        return [
            "orientation_source": run.orientationSource.rawValue,
            "positions": map.width * map.height,
            "phases": perPhase,
            "matrix": map.count(of: .matrix),
            "indexed": map.count(of: .indexed),
            "not_indexed": map.count(of: .notIndexed),
            "no_data": map.count(of: .noData),
            "learned_relationships": run.learnedRelationships,
            "excitation_slabs": run.excitationSlabs,
            "reach_inv_angstrom": AgentJSON.number(run.libraryKMaxInvAngstrom),
            "worst_chance_match_percent": AgentJSON.number(run.worstChanceMatchPercent),
            "settings_changed_since": product.isStale,
            "selected_position": AgentJSON.orNull(state.phaseMappingEvidenceLine),
        ] as [String: Any]
    }
}
