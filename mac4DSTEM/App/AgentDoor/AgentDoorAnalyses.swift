//
//  AgentDoorAnalyses.swift
//  Role: The agent door's settings for Strain (#225), ACOM (#226) and Diffraction groups (#227): an agent sets what each task's
//        panel sets, only the fields it names, and reads what the last run found as numbers. run_task runs the task.
//
//  A choice is named by its Swift case (`wholeScan`, `ipfZ`, `exx`, ...), the same word in the answer as in the call. Every change
//  writes an Output line that names the agent.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// A case's own name, the word an agent uses for it.
    static func caseName<T>(_ value: T) -> String { String(describing: value) }

    /// The case of `T` an agent named, or nil.
    static func named<T: CaseIterable>(_ text: String?, _: T.Type) -> T? {
        guard let text else { return nil }
        return T.allCases.first { caseName($0) == text }
    }

    static func caseNames<T: CaseIterable>(_: T.Type) -> [String] { T.allCases.map { caseName($0) } }

    static let analysisTools: [AgentTool] = [
        // MARK: Strain (#225)
        AgentTool(name: "set_strain", title: "Strain settings",
                  summary: "Sets Strain's panel, only what is given: the reference (wholeScan, or selectedRegion: the real-space ROI "
                      + "around the selected scan position, set by set_imaging's region and select_scan_position; the answer's "
                      + "reference_region says its extent), the basis (automatic consensus, or manual "
                      + "with g1_x, g1_y, g2_x, g2_y in detector pixels), and the component the map shows. Answers the settings and, "
                      + "after a run, the fit diagnostics (get_window's task_settings has the run's signature).",
                  input: .window,
                  parameters: [
                      AgentParameter("reference", .choice(caseNames(StrainReferenceMode.self)), summary: "What counts as zero strain."),
                      AgentParameter("basis", .choice(caseNames(StrainBasisMode.self)), summary: "automatic or manual g1/g2."),
                      AgentParameter("g1_x", .number(-1000...1000), summary: "Manual basis: g1 x, detector pixels."),
                      AgentParameter("g1_y", .number(-1000...1000), summary: "Manual basis: g1 y, detector pixels."),
                      AgentParameter("g2_x", .number(-1000...1000), summary: "Manual basis: g2 x, detector pixels."),
                      AgentParameter("g2_y", .number(-1000...1000), summary: "Manual basis: g2 y, detector pixels."),
                      AgentParameter("component", .choice(caseNames(StrainComponent.self)), summary: "The map shown: exx, eyy, exy, "
                                         + "theta (rotation), residual or indexed."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let strain = state.strain
            if let mode = named(call.arguments["reference"], StrainReferenceMode.self) { strain.referenceMode = mode }
            if let mode = named(call.arguments["basis"], StrainBasisMode.self) { strain.basisMode = mode }
            if let v = call.arguments["g1_x"].flatMap(Float.init) { strain.g1X = v }
            if let v = call.arguments["g1_y"].flatMap(Float.init) { strain.g1Y = v }
            if let v = call.arguments["g2_x"].flatMap(Float.init) { strain.g2X = v }
            if let v = call.arguments["g2_y"].flatMap(Float.init) { strain.g2Y = v }
            if let component = named(call.arguments["component"], StrainComponent.self) { strain.component = component }
            state.statusText = agentChangeLine("Strain", call.arguments)
            return .json(strainSettings(of: state))
        },

        // MARK: ACOM (#226)
        AgentTool(name: "set_acom", title: "ACOM settings",
                  summary: "Sets ACOM's panel, only what is given: the phase model from a CIF in the Agent folder (as Import CIF "
                      + "does), the area (preview, selectedRegion around the selected scan position with region_radius, or "
                      + "fullScan), quality, engine, in-plane refinement, the map shown and the IPF map's confidence gate "
                      + "(reliability_threshold 0 to 1; clear_reliability_threshold goes back to automatic). Answers the settings "
                      + "and, after a run, how many positions matched and how many pass the gate. The Q calibration is Prepare's "
                      + "(set_calibration).",
                  input: .window,
                  parameters: [
                      AgentParameter("phase_cif", .text, summary: "A CIF in the Agent folder, as list_agent_folder names it."),
                      AgentParameter("scope", .choice(caseNames(ACOMRunScope.self)), summary: "preview, selectedRegion or fullScan."),
                      AgentParameter("region_radius", .integer(4...4096), summary: "selectedRegion: half-size in scan pixels."),
                      AgentParameter("quality", .choice(caseNames(ACOMQualityPreset.self)), summary: "fast, balanced or best."),
                      AgentParameter("engine", .choice(caseNames(ACOMMatchingBackend.self)), summary: "automatic, cpu or metal."),
                      AgentParameter("refine_in_plane", .boolean, summary: "Refine the in-plane angle past the 128-bin step."),
                      AgentParameter("display", .choice(caseNames(ACOMDisplayMode.self)), summary: "The map shown."),
                      AgentParameter("reliability_threshold", .number(0...1), summary: "IPF map: positions below this are greyed."),
                      AgentParameter("clear_reliability_threshold", .boolean, summary: "true: the automatic gate (10th percentile)."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            if let path = call.arguments["phase_cif"] {
                switch importCIF(path, into: state) {
                case .success: break
                case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
                }
            }
            let session = state.acomSession
            if let scope = named(call.arguments["scope"], ACOMRunScope.self) { session.scope = scope }
            if let radius = call.arguments["region_radius"].flatMap(Int.init) {
                let most = state.descriptor.map { max(4, min($0.rx, $0.ry) / 2) } ?? 4096
                session.regionRadius = min(max(radius, 4), most)
            }
            if let quality = named(call.arguments["quality"], ACOMQualityPreset.self) { session.quality = quality }
            if let engine = named(call.arguments["engine"], ACOMMatchingBackend.self) { session.backend = engine }
            if let refine = call.arguments["refine_in_plane"] { session.refinesInPlaneAngle = refine == "true" }
            if let display = named(call.arguments["display"], ACOMDisplayMode.self) { state.selectACOMDisplay(display) }
            if let threshold = call.arguments["reliability_threshold"].flatMap(Float.init) { session.reliabilityThreshold = threshold }
            if call.arguments["clear_reliability_threshold"] == "true" { session.reliabilityThreshold = nil }
            state.statusText = agentChangeLine("ACOM", call.arguments)
            return .json(acomSettings(of: state))
        },

        // MARK: Diffraction groups (#227)
        AgentTool(name: "set_diffraction_groups", title: "Diffraction groups settings",
                  summary: "Sets Diffraction groups' panel, only what is given: the binned pattern size (8, 16 or 32), the principal "
                      + "components kept and the k-means group count (each 2 to 32). run_task groups the patterns.",
                  input: .window,
                  parameters: [
                      AgentParameter("binned_size", .choice(["8", "16", "32"]), summary: "Pixels per side after box-binning."),
                      AgentParameter("components", .integer(2...32), summary: "Principal components kept."),
                      AgentParameter("groups", .integer(2...32), summary: "k-means groups."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            var settings = state.diffractionGroups.settings
            if let size = call.arguments["binned_size"].flatMap(Int.init) { settings.binnedSize = size }
            if let n = call.arguments["components"].flatMap(Int.init) { settings.components = n }
            if let n = call.arguments["groups"].flatMap(Int.init) { settings.groups = n }
            state.diffractionGroups.settings = settings
            state.statusText = agentChangeLine("Diffraction groups", call.arguments)
            return .json(["binned_size": settings.binnedSize, "components": settings.components, "groups": settings.groups,
                          "has_result": state.diffractionGroups.result != nil])
        },
        AgentTool(name: "find_similar_patterns", title: "Find similar to current position",
                  summary: "Maps how similar every position's pattern is to the selected scan position's (cosine similarity), "
                      + "against the last grouping, as Find similar to current position does. Needs a grouping (run_task in "
                      + "Diffraction groups); get_result_image shows the map.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.diffractionGroups.result != nil else {
                return .refusal(status: 409, message: "There is no grouping yet; run Diffraction groups first (run_task).")
            }
            if case .failed(let reason) = state.showSimilarityToCurrentPosition() {
                return .refusal(status: 409, message: reason)
            }
            state.statusText = "An agent pressed Find similar to (\(state.selectedScan.x), \(state.selectedScan.y))."
            return .json(["reference": ["x": state.selectedScan.x, "y": state.selectedScan.y]])
        },
    ]

    struct ToolRefusal: Error { let status: Int; let message: String }

    /// A CIF from the Agent folder, imported as Import CIF does (it becomes ACOM's phase model and is offered to Map Phases).
    static func importCIF(_ path: String, into state: AppState) -> Result<CrystalModel, ToolRefusal> {
        let file: URL
        switch folder.resolve(path) {
        case .success(let url): file = url
        case .failure(let refusal): return .failure(ToolRefusal(status: 404, message: refusal.message))
        }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return .failure(ToolRefusal(status: 404, message: noFileMessage(file)))
        }
        do {
            return .success(try state.importCrystalModelOrThrow(from: file))
        } catch {
            return .failure(ToolRefusal(status: 422, message: "\(file.lastPathComponent) is not a usable CIF: "
                + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)))
        }
    }

    static func strainSettings(of state: AppState) -> [String: Any] {
        let strain = state.strain
        var out: [String: Any] = [
            "reference": caseName(strain.referenceMode),
            "basis": caseName(strain.basisMode),
            "manual_basis_px": ["g1": [strain.g1X, strain.g1Y], "g2": [strain.g2X, strain.g2Y]],
            "component": caseName(strain.component),
            "frame": state.strainPresentationFrame.displayLabel,
        ]
        // The region selectedRegion takes as zero strain, as set_imaging and select_scan_position set it.
        if strain.referenceMode == .selectedRegion, let descriptor = state.descriptor {
            out["reference_region"] = ["shape": caseName(state.realSpaceShape), "radius": Double(state.realSpaceRadius),
                                       "center": ["x": state.selectedScan.x, "y": state.selectedScan.y],
                                       "positions": state.realSpaceRegionMask(descriptor).filter { $0 }.count] as [String: Any]
        }
        switch strain.failureCause {
        case .starvedInput(let median, let empty)?:
            out["failure"] = "Too few peaks: median \(numberText(median)) per pattern, \(empty) % empty. Lower the detection "
                + "thresholds, not the reference."
        case .illConditionedBasis?:
            out["failure"] = "No single lattice fits the whole reference: use a region on an unstrained area as the reference, "
                + "or a manual basis."
        default:
            out["failure"] = NSNull()
        }
        if let map = strain.map {
            let d = map.diagnostics
            out["last_run"] = [
                "indexed_fraction": AgentJSON.number(map.indexedFraction),
                "reference_positions": map.referencePositionCount,
                "reference_candidates": d.referenceCandidateCount,
                "basis_automatic": d.automaticBasis,
                "basis_support_fraction": AgentJSON.number(d.basisSupportFraction),
                "basis_rms_px": AgentJSON.number(d.basisResidualPixels),
                "basis_condition_number": AgentJSON.number(d.basisConditionNumber),
                "local_rms_median_px": AgentJSON.number(d.localResidualMedianPixels),
                "reference_basis_px": ["g1": [map.refG1.x, map.refG1.y], "g2": [map.refG2.x, map.refG2.y]],
            ] as [String: Any]
        } else {
            out["last_run"] = NSNull()
        }
        return out
    }

    static func acomSettings(of state: AppState) -> [String: Any] {
        let session = state.acomSession
        var out: [String: Any] = [
            "phase_model": AgentJSON.orNull(state.resolvedACOMModel?.displayName),
            "phase_model_issue": AgentJSON.orNull(session.modelSelectionIssue),
            "scope": caseName(session.scope),
            "region_radius": session.regionRadius,
            "quality": caseName(session.quality),
            "engine": caseName(session.backend),
            "refine_in_plane": session.refinesInPlaneAngle,
            "display": caseName(session.display),
            "reliability_threshold": AgentJSON.number(session.reliabilityThreshold),
            "effective_reliability_threshold": AgentJSON.number(session.effectiveReliabilityThreshold),
            "full_scan_suggestion": AgentJSON.orNull(state.acomFullScanSuggestion),
        ]
        if let map = session.orientationMap {
            let gate = session.effectiveReliabilityThreshold ?? 0
            out["last_run"] = [
                "width": map.width, "height": map.height, "templates": map.templateCount,
                "fraction_kept_by_gate": AgentJSON.number(map.fractionOfMatchedPositions(withReliabilityAtLeast: gate)),
            ] as [String: Any]
        } else {
            out["last_run"] = NSNull()
        }
        return out
    }
}
