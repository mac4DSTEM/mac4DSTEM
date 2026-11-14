//
//  AgentDoorTask.swift
//  Role: The agent door's tools for the room and the task (issue #209): an agent moves the window to a workspace and task, as the
//        sidebar does (`WorkspaceRoute`), so `run_task` runs the step it means; and it reads and sets Phase mapping's settings,
//        as the fields of `UI/PhaseMappingSettings.swift` do, and presses Scale to This Detector.
//
//  The phase list itself (adding a phase from a CIF) is mac4DSTEM#192's. The setters act, so they run only while "Let agents run
//  analyses" is on (`AgentDoorRuns.swift`'s rules).
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif
import DiffractoOrientation

extension Mac4DSTEMAgentDoor {
    static let taskTools: [AgentTool] = [
        AgentTool(name: "select_task", title: "Select task",
                  summary: "Moves the window to a task (\"Disks\", \"Phase mapping\", ...: get_window's view.task) or to a workspace "
                      + "(prepare, braggDisks, map, ...: get_window's view.workspace_id), as the sidebar does. A task opens its own "
                      + "workspace; a workspace alone opens its first task. Nothing runs: run_task then runs the task selected. can_run says "
                      + "whether the task has a Run at all (some tasks only show).",
                  input: .window,
                  parameters: [
                      AgentParameter("task", .choice(AnalysisMode.allCases.map(\.rawValue)), summary: "The task to select."),
                      AgentParameter("workspace", .choice(WorkspaceArea.allCases.map(\.rawValue)),
                                     summary: "The workspace to select, when no task is given."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let task = call.arguments["task"].flatMap(AnalysisMode.init(rawValue:))
            let named = call.arguments["workspace"].flatMap(WorkspaceArea.init(rawValue:))
            guard let area = task?.workspaceArea ?? named else {
                return .refusal(status: 400, message: "Name a task or a workspace.")
            }
            if let task, let named, named != task.workspaceArea {
                return .refusal(status: 400, message: "\(task.rawValue) is in the \(task.workspaceArea.rawValue) workspace, "
                    + "not \(named.rawValue).")
            }
            guard !state.isWorkspaceWithheld(area) else {
                return .refusal(status: 409, message: "\(area.title) has nothing to show in this window "
                    + (state.isSpectrumOnly ? "(it holds a spectrum image and no 4D scan)." : "(it holds no spectrum image)."))
            }
            // The sidebar's route (`WorkspaceRoute`): the room first, then the task.
            if state.navigation.workspaceArea != area { state.selectWorkspace(area) }
            if let task, state.navigation.analysisMode != task { state.changeMode(task) }
            state.statusText = "An agent selected \(area.title)" + (area.analysisModes.isEmpty ? "." : ", \(state.navigation.analysisMode.rawValue).")
            let selected: Any = area.analysisModes.isEmpty ? NSNull() : state.navigation.analysisMode.rawValue
            return .json(["workspace": state.navigation.workspaceArea.rawValue, "task": selected,
                          "can_run": state.hasPrimaryWorkspaceTask])
        },
        AgentTool(name: "set_phase_mapping", title: "Phase mapping settings",
                  summary: "Changes Phase mapping's reference-library and matching settings, as its fields do; only the ones given. "
                      + "Values in Å⁻¹ are met on the detector's pixel grid: get_window's phase_mapping.on_this_detector says how many "
                      + "pixels each tolerance is, and scale_phase_matching_to_detector sets them to one pixel. Changing the "
                      + "classifier resets min_intensity_fraction to the classifier's default, as the picker does. "
                      + "orientation_source is structures (orientations found from each phase's structure, the default) or "
                      + "typedZones (each phase matched at its typed zone axis). add_phase, set_phase and remove_phase change the "
                      + "phase list.",
                  input: .window,
                  parameters: PhaseSetting.all.map(\.parameter) + [
                      AgentParameter("orientation_source", .choice(PhaseOrientationSource.allCases.map(\.rawValue)),
                                     summary: "structures or typedZones, as Advanced > Typed zone axes does."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let product = state.phaseMapping
            if let rule = call.arguments["classifier"].flatMap(PhaseVectorSettings.ClassificationRule.init(rawValue:)),
               rule != product.matching.classificationRule {
                product.matching.classificationRule = rule
                product.reference.minimumIntensityFraction = PhaseMappingRuleDefaults.minimumIntensityFraction(for: rule)
            }
            if let source = call.arguments["orientation_source"].flatMap(PhaseOrientationSource.init(rawValue:)) {
                product.orientationSource = source
            }
            for setting in PhaseSetting.all where setting.parameter.name != "classifier" {
                if let text = call.arguments[setting.parameter.name], let value = Double(text) { setting.apply(value, product) }
            }
            // An Output line names what the agent set, so the person sees which values were not theirs.
            state.statusText = agentChangeLine("Phase mapping", call.arguments)
            return .json(phaseMappingSettings(of: state))
        },
        AgentTool(name: "scale_phase_matching_to_detector", title: "Scale to This Detector",
                  summary: "Sets Phase mapping's pair radius and matrix removal to one detector pixel and \"not indexed above\" to "
                      + "three quarters of one, as Scale to This Detector does. Needs a physical Q pixel size (Prepare).",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.phaseVectorResolution != nil else {
                return .refusal(status: 409, message: state.phaseMappingQScaleRefusal
                    ?? "The Q pixel size is not known, so a detector pixel has no size in Å⁻¹.")
            }
            state.scalePhaseMatchingToDetector()
            state.statusText = "An agent pressed Scale to This Detector: " + state.statusText
            return .json(phaseMappingSettings(of: state))
        },
    ]

    /// The Output line for settings an agent changed: "An agent set <what>: name value, ...", in the order the names sort.
    static func agentChangeLine(_ what: String, _ arguments: [String: String]) -> String {
        let pairs = arguments.keys.sorted().compactMap { name in arguments[name].map { "\(name) \($0)" } }
        return "An agent set \(what): " + (pairs.isEmpty ? "nothing" : pairs.joined(separator: ", ")) + "."
    }

    /// Phase mapping as an agent reads it: the phases, the settings, what the tolerances are in detector pixels, and why the task
    /// cannot run yet (or null).
    static func phaseMappingSettings(of state: AppState) -> [String: Any] {
        let product = state.phaseMapping
        var settings: [String: Any] = [:]
        for setting in PhaseSetting.all { settings[setting.parameter.name] = setting.read(product) }
        var onDetector: Any = NSNull()
        if let resolution = state.phaseVectorResolution {
            onDetector = [
                "inv_angstrom_per_pixel": resolution.invAngstromPerPixel,
                "pair_radius_px": AgentJSON.number(resolution.pairRadiusPixels),
                "matrix_removal_px": AgentJSON.number(resolution.matrixRemovalPixels),
                "not_indexed_above_px": AgentJSON.number(resolution.notIndexedAbovePixels),
                "advice": AgentJSON.orNull(resolution.advice),
            ] as [String: Any]
        }
        return ["phase_mapping": [
            "orientation_source": product.orientationSource.rawValue,
            "default_excitation_slab_inv_angstrom": product.orientationSource == .structures
                ? PhaseMappingProduct.structuresExcitationSlabDefault : product.reference.excitationSlabInvAngstrom,
            "phases": product.phases.enumerated().map { index, slot in
                ["index": index, "name": slot.model.displayName, "is_matrix": slot.isMatrix, "zone_axis": [slot.u, slot.v, slot.w],
                 "orientation_relationship": slot.orientationRelationshipText,
                 "excitation_slab_inv_angstrom": AgentJSON.number(slot.excitationSlabInvAngstrom)] as [String: Any]
            },
            "settings": settings,
            "on_this_detector": onDetector,
            "q_scale_refusal": AgentJSON.orNull(state.phaseMappingQScaleRefusal),
            "origin_refusal": AgentJSON.orNull(state.phaseMappingOriginRefusal),
            "run_refusal": AgentJSON.orNull(product.runRefusal),
            "last_run": phaseMappingLastRun(of: state),
            "zone_axis_fits": product.zoneAxisFits.map { fit in
                ["zone_axis": [fit.zoneAxis.x, fit.zoneAxis.y, fit.zoneAxis.z], "matched_vectors": fit.matchedVectors,
                 "total_vectors": fit.totalVectors, "chance_matched_vectors": AgentJSON.number(fit.chanceMatchedVectors),
                 "mean_distance_inv_angstrom": AgentJSON.number(fit.meanDistance)] as [String: Any]
            },
        ] as [String: Any]]
    }

    /// One field of the Phase mapping task (`UI/PhaseMappingSettings.swift`), as an agent names it. The classifier is a choice and
    /// is applied first, by `set_phase_mapping`.
    struct PhaseSetting {
        let parameter: AgentParameter
        let read: (PhaseMappingProduct) -> Any
        let apply: (Double, PhaseMappingProduct) -> Void

        private static func number(_ name: String, _ range: ClosedRange<Double>, _ summary: String,
                                   _ path: ReferenceWritableKeyPath<PhaseMappingProduct, Double>) -> PhaseSetting {
            PhaseSetting(parameter: AgentParameter(name, .number(range), summary: summary),
                         read: { $0[keyPath: path] }, apply: { $1[keyPath: path] = $0 })
        }

        private static func integer(_ name: String, _ range: ClosedRange<Int>, _ summary: String,
                                    _ path: ReferenceWritableKeyPath<PhaseMappingProduct, Int>) -> PhaseSetting {
            PhaseSetting(parameter: AgentParameter(name, .integer(range), summary: summary),
                         read: { $0[keyPath: path] }, apply: { $1[keyPath: path] = Int($0) })
        }

        static let all: [PhaseSetting] = [
            PhaseSetting(parameter: AgentParameter("classifier", .choice(PhaseVectorSettings.ClassificationRule.allCases.map(\.rawValue)),
                                                   summary: "search (the shipped rule) or knownVariants (Thronsen et al. 2024)."),
                         read: { $0.matching.classificationRule.rawValue }, apply: { _, _ in }),
            number("max_q_inv_angstrom", 0.1...10, "Reference library: reflections up to this |q|, Å⁻¹.", \.reference.kMaxInvAngstrom),
            number("in_plane_step_deg", 0.1...45, "Reference library: in-plane rotation step, degrees.", \.reference.inPlaneStepDeg),
            integer("vectors_per_orientation", 1...1000, "Reference library: strongest reflections kept per orientation.",
                    \.reference.maximumVectorsPerEntry),
            number("min_intensity_fraction", 0...1, "Reference library: reflections weaker than this fraction of the strongest are "
                       + "dropped.", \.reference.minimumIntensityFraction),
            number("excitation_slab_inv_angstrom", 0...1, "Reference library: excitation slab, Å⁻¹ (a phase's own value wins).",
                   \.reference.excitationSlabInvAngstrom),
            number("pair_radius_inv_angstrom", 0...1, "Matching: a peak and a reflection pair within this, Å⁻¹.",
                   \.matching.pairRadiusInvAngstrom),
            number("matrix_removal_inv_angstrom", 0...1, "Matching: peaks this close to a matrix reflection are the matrix's, Å⁻¹.",
                   \.matching.matrixToleranceInvAngstrom),
            number("not_indexed_above_inv_angstrom", 0...1, "search only: a best match farther than this is not indexed, Å⁻¹.",
                   \.matching.notIndexedAboveInvAngstrom),
            number("residual_cutoff_inv_angstrom", 0...1, "knownVariants only: a winner whose mean residual is above this is not "
                       + "indexed, Å⁻¹.", \.matching.residualCutoffInvAngstrom),
            integer("direct_matrix_max_vectors", 0...1000, "knownVariants only: positions with at most this many surviving peaks "
                        + "are the matrix.", \.matching.directMatrixMaximumVectors),
            integer("min_specific_reflections", 0...1000, "knownVariants only: a winner matching fewer reflections the matrix "
                        + "lacks falls back to the matrix; 0 turns it off.", \.matching.knownVariantsMinimumSpecificReflections),
            number("ignore_peaks_beyond_inv_angstrom", 0...10, "Peaks beyond this |q| are ignored, Å⁻¹; 0 is the detector's edge.",
                   \.matching.maximumVectorInvAngstrom),
        ]
    }
}
