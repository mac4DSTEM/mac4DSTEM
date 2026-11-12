//
//  AgentDoorActions.swift
//  Role: The agent door's remaining single buttons of Disks and Phase mapping (issue #230): Compare Detectors, Reset Recommended
//        Settings, and Find Matrix Zone Axis, each as its button does.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let actionTools: [AgentTool] = [
        AgentTool(name: "compare_detectors", title: "Compare Detectors",
                  summary: "Publishes a scan map of the peaks the neural net and the classical detector do not share at each "
                      + "position (paired within 2 px), as Compare Detectors does. Needs Detect All Disks run with each detector "
                      + "on this dataset (set_detector, run_task). get_result_image shows the map.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            if case .failed(let reason) = state.runDiskDisagreement() { return .refusal(status: 409, message: reason) }
            state.statusText = "An agent pressed Compare Detectors."
            return .json(["published": true])
        },
        AgentTool(name: "reset_disk_detection", title: "Reset Recommended Settings",
                  summary: "Puts every disk detection setting back to the recommended defaults, as Reset Recommended Settings does. "
                      + "Answers the settings.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            state.resetDiskDetectionParams()
            state.statusText = "An agent reset disk detection to the recommended settings."
            return .json(diskSettings(of: state))
        },
        AgentTool(name: "find_matrix_zone_axis", title: "Find Matrix Zone Axis",
                  summary: "Ranks the matrix phase's zone axes against the detected disks, as Find Matrix Zone Axis does (typed "
                      + "zone axes): symmetry-equivalent axes should tie exactly. It answers at once; get_window's "
                      + "phase_mapping.zone_axis_fits lists the ranking with the chance level, and the best axis is written into the "
                      + "matrix row.",
                  input: .window, acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            if let refusal = state.matrixZoneAxisRefusal { return .refusal(status: 409, message: refusal) }
            state.statusText = "An agent pressed Find Matrix Zone Axis."
            Task { _ = await state.findMatrixZoneAxis() }
            return .json(["started": true])
        },
    ]
}
