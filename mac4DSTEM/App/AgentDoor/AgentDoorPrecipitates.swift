//
//  AgentDoorPrecipitates.swift
//  Role: The agent door's precipitate objects controls (issue #228): the overlays, the minimum counted size, which phase result
//        the pane shows (phase map, objects, match distance), the thickness behind N_V (typed, or its source words from macTEM's
//        EELS method file in the Agent folder), variant counting with its phase, orientation relationship, tolerance and
//        agreement, and the CSV export into the Agent folder. get_precipitate_objects reads the table.
//

import Foundation
import ShellAgentDoor
import DiffractoOrientation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let precipitateTools: [AgentTool] = [
        AgentTool(name: "set_precipitates", title: "Precipitate objects settings",
                  summary: "Sets the Precipitates section, only what is given: the overlays on the panes, the minimum counted size "
                      + "in scan pixels, which phase result the pane shows (phaseMap, objects, distance), the thickness behind N_V "
                      + "(nm, with σ and source words, or the source words from macTEM's EELS method JSON in the Agent folder; "
                      + "clear_thickness takes it away), and variant counting (count_variants, its phase, orientation relationship, "
                      + "angle tolerance in degrees and the least agreement). Needs a phase map. get_precipitate_objects reads the "
                      + "objects and N_V.",
                  input: .window,
                  parameters: [
                      AgentParameter("on_panes", .boolean, summary: "Draw the objects on the panes."),
                      AgentParameter("counted_only", .boolean, summary: "Draw only counted objects."),
                      AgentParameter("labels", .boolean, summary: "Draw labels."),
                      AgentParameter("colour_by", .choice(caseNames(PrecipitateColourBy.self)), summary: "phase, direction or variant."),
                      AgentParameter("minimum_size_px", .integer(1...1_000_000), summary: "Smaller objects are kept but not counted."),
                      AgentParameter("show", .choice(["phaseMap", "objects", "distance"]), summary: "The phase result on the pane."),
                      AgentParameter("thickness_nm", .number(0.001...1_000_000), summary: "Specimen thickness, nm."),
                      AgentParameter("thickness_sigma_nm", .number(0...1_000_000), summary: "Its σ, nm."),
                      AgentParameter("thickness_source", .text, summary: "Where the thickness comes from, in words."),
                      AgentParameter("thickness_source_json", .text, summary: "macTEM's EELS method JSON in the Agent folder: the "
                                         + "source words come from it; the thickness stays the number given."),
                      AgentParameter("clear_thickness", .boolean, summary: "true takes the thickness away."),
                      AgentParameter("count_variants", .boolean, summary: "Name each object's orientation-relationship variant."),
                      AgentParameter("variant_phase", .text, summary: "The candidate phase whose variants are counted, by name."),
                      AgentParameter("orientation_relationship", .choice(caseNames(OrientationRelationshipPreset.self)),
                                     summary: "The relationship whose variants are named."),
                      AgentParameter("angle_tolerance_deg", .number(0.001...90), summary: "A pixel votes only this near a variant."),
                      AgentParameter("agreement_min", .number(0.01...1), summary: "Least share of an object's pixels for its variant."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.phaseMapping.map != nil else {
                return .refusal(status: 409, message: "There is no phase map yet; precipitate objects come from Map Phases (run_task).")
            }
            let a = call.arguments
            if let v = a["on_panes"] { state.precipitateOverlay.onPanes = v == "true" }
            if let v = a["counted_only"] { state.precipitateOverlay.countedOnly = v == "true" }
            if let v = a["labels"] { state.precipitateOverlay.labels = v == "true" }
            if let v = named(a["colour_by"], PrecipitateColourBy.self) { state.precipitateOverlay.colourBy = v }
            if let v = a["minimum_size_px"].flatMap(Int.init) {
                state.precipitateClassification.minimumObjectAreaPx = v
                state.refreshPrecipitateObjectsProductIfShown()
            }
            if a["clear_thickness"] == "true" {
                state.setPrecipitateThickness(nil)
            } else if a["thickness_nm"] != nil || a["thickness_sigma_nm"] != nil || a["thickness_source"] != nil
                        || a["thickness_source_json"] != nil {
                let current = state.precipitateThickness
                guard let nm = a["thickness_nm"].flatMap(Double.init) ?? current?.nanometres else {
                    return .refusal(status: 400, message: "Give thickness_nm: the thickness is the person's or the agent's number.")
                }
                var source = a["thickness_source"] ?? current?.source ?? "typed value"
                var origin = current?.origin ?? .typed
                if let path = a["thickness_source_json"] {
                    switch readAgentText(path) {
                    case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
                    case .success(let text):
                        do {
                            let parsed = try ThicknessEntry.source(fromEELSMethodJSON: text)
                            source = parsed.text; origin = parsed.origin
                        } catch {
                            return .refusal(status: 422, message: "\(path) is not an EELS method file: \(error.localizedDescription)")
                        }
                    }
                }
                let entry = ThicknessEntry(nanometres: nm, sigmaNanometres: a["thickness_sigma_nm"].flatMap(Double.init)
                                               ?? current?.sigmaNanometres ?? 0, source: source, origin: origin)
                guard entry.isUsable else { return .refusal(status: 400, message: "That thickness is not usable: a positive nm and σ ≥ 0.") }
                state.setPrecipitateThickness(entry)
            }
            if let v = a["count_variants"] {
                let on = v == "true"
                if on != (state.precipitateVariantSettings != nil) { state.setPrecipitateVariantSettings(on ? VariantSettings() : nil) }
            }
            let variantKeys = ["variant_phase", "orientation_relationship", "angle_tolerance_deg", "agreement_min"]
            if variantKeys.contains(where: { a[$0] != nil }) {
                guard var next = state.precipitateVariantSettings else {
                    return .refusal(status: 409, message: "Variant counting is off; give count_variants true with these.")
                }
                if let phase = a["variant_phase"] {
                    let names = state.phaseMapping.map?.phaseNames ?? []
                    guard names.contains(phase) else {
                        return .refusal(status: 404, message: "No phase \(phase) in the map; it has \(names.joined(separator: ", ")).")
                    }
                    next.phaseName = phase
                }
                if let v = named(a["orientation_relationship"], OrientationRelationshipPreset.self) { next.orientationRelationship = v }
                if let v = a["angle_tolerance_deg"].flatMap(Double.init) { next.toleranceDegrees = v }
                if let v = a["agreement_min"].flatMap(Double.init) { next.agreementMinimum = v }
                state.setPrecipitateVariantSettings(next)
            }
            if let show = a["show"] {
                let pictures: [String: PhaseResultPicture] = ["phaseMap": .phaseMap, "objects": .objects, "distance": .distance]
                if let picture = pictures[show] { state.showPhaseResult(picture) }
            }
            state.statusText = agentChangeLine("Precipitates", a)
            return .json(precipitateSettings(of: state))
        },
        AgentTool(name: "export_precipitates_csv", title: "Export precipitate objects CSV",
                  summary: "Saves every precipitate object and the per-phase summary as CSV into the Agent folder, as Export CSV… "
                      + "does, with the settings and provenance in its header. Needs \"Let agents save results there\"; never "
                      + "replaces a file.",
                  input: .window,
                  parameters: [AgentParameter("name", .text, summary: "The file name, without folders; .csv is added. Leave out for "
                                                  + "the dataset's name followed by _objects.")],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard let report = state.precipitateObjectReport else {
                return .refusal(status: 409, message: "There are no precipitate objects yet; they come from Map Phases.")
            }
            switch saveNewFile(Data(report.csv().utf8), named: call.arguments["name"], default: state.exportBaseName + "_objects",
                               extension: "csv") {
            case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
            case .success(let name):
                state.statusText = "An agent exported precipitate objects → \(name) in the Agent folder."
                return .json(["saved": name])
            }
        },
    ]

    /// A text file of the Agent folder, read whole.
    static func readAgentText(_ path: String) -> Result<String, ToolRefusal> {
        switch folder.resolve(path) {
        case .failure(let refusal): return .failure(ToolRefusal(status: 404, message: refusal.message))
        case .success(let url):
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return .failure(ToolRefusal(status: 404, message: "There is no readable text file \(path) in the Agent folder."))
            }
            return .success(text)
        }
    }

    static func precipitateSettings(of state: AppState) -> [String: Any] {
        let overlay = state.precipitateOverlay
        var out: [String: Any] = [
            "on_panes": overlay.onPanes, "counted_only": overlay.countedOnly, "labels": overlay.labels,
            "colour_by": caseName(overlay.colourBy),
            "minimum_size_px": state.precipitateClassification.minimumObjectAreaPx,
            "shown": AgentJSON.orNull(state.displayedProduct?.kind),
        ]
        if let t = state.precipitateThickness {
            out["thickness"] = ["nm": t.nanometres, "sigma_nm": t.sigmaNanometres, "source": t.source] as [String: Any]
        } else {
            out["thickness"] = NSNull()
        }
        if let v = state.precipitateVariantSettings {
            out["variants"] = ["phase": AgentJSON.orNull(v.phaseName), "orientation_relationship": caseName(v.orientationRelationship),
                               "angle_tolerance_deg": AgentJSON.number(v.toleranceDegrees),
                               "agreement_min": v.agreementMinimum,
                               "unavailable": AgentJSON.orNull(state.precipitateObjectReport?.variantUnavailable)] as [String: Any]
        } else {
            out["variants"] = NSNull()
        }
        return out
    }
}
