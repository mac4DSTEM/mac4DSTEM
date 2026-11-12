//
//  AgentDoorKernel.swift
//  Role: The agent door's probe-kernel tools (issue #207): the rows above the Disks task's sliders. Before any slider matters the
//        task needs a probe kernel; an agent reads it (`get_probe_kernel`), sets the probe radius, builds the kernel and picks the
//        detector, through the same entry points as Probe radius, Build Kernel and Detector (`UI/MapSettings.swift`).
//
//  The setters act, so they run only while "Let agents run analyses" is on (`AgentDoorRuns.swift`'s rules). The vacuum-scan
//  kernel needs a second file and stays with the person.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    static let kernelTools: [AgentTool] = [
        AgentTool(name: "get_probe_kernel", title: "Probe kernel",
                  summary: "The Disks task's probe kernel and detector: the probe radius in detector pixels and where it came from "
                      + "(measured by Calibrate Origin, or typed), the kernel built (source, mode, radius) or null while none is, the "
                      + "detector (classical or neural net) and the neural net's threshold. No disks are detected until a kernel is built.",
                  input: .window) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            return .json(kernelSummary(of: state))
        },
        AgentTool(name: "set_probe_radius", title: "Set probe radius",
                  summary: "Sets the probe radius the synthetic kernel is built at, as typing it into Probe radius does (recorded as "
                      + "manual). A synthetic kernel already built is rebuilt at it and the detection follows. Compare the disks on "
                      + "get_pattern_image: the radius is the Bragg disk's, not the whole pattern's. " + diskDefaultsNote,
                  input: .window,
                  parameters: [AgentParameter("radius", .number(0.1...10_000), summary: "Radius in detector pixels; at most half the "
                                                  + "detector's smaller side.", required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            guard let typed = Double(call.arguments["radius"] ?? ""),
                  let radius = ProbeRadiusEntry.radius(typed: typed, descriptor: state.descriptor) else {
                let limit = state.descriptor.map { " (at most \(min($0.qy, $0.qx) / 2) px here)" } ?? ""
                return .refusal(status: 400, message: "The radius is a positive number of pixels that fits the detector\(limit).")
            }
            state.statusText = "An agent set the probe radius: \(numberText(Double(radius))) px."
            Task { await noteDiskSettingChanges(of: state, by: "The probe radius") { await state.useProbeRadius(radius) } }
            return .json(["probe_radius_px": Double(radius),
                          "rebuilds_kernel": state.probeKernel?.source == .synthetic])
        },
        AgentTool(name: "build_probe_kernel", title: "Build kernel",
                  summary: "Builds the probe kernel, as Build Kernel does: synthetic (a disk at the probe radius), current_pattern (the "
                      + "pattern on screen, best on vacuum) or file_probe (the probe image the file carries). Without a probe radius "
                      + "Calibrate Origin measures one first. It answers at once; get_probe_kernel says when the kernel is in, and the "
                      + "detection on the pattern on screen follows. " + diskDefaultsNote,
                  input: .window,
                  parameters: [
                      AgentParameter("source", .choice(KernelChoice.allCases.map(\.rawValue)), summary: "Where the kernel comes from.",
                                     required: true),
                      AgentParameter("mode", .choice(ModeChoice.allCases.map(\.rawValue)), summary: "For current_pattern and "
                                         + "file_probe: flat uses the probe as it is (bullseye and structured probes); "
                                         + "sigmoid_trench follows the disk edge. Default flat."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            guard let source = KernelChoice(rawValue: call.arguments["source"] ?? "") else {
                return .refusal(status: 400, message: "source is synthetic, current_pattern or file_probe.")
            }
            let mode = (ModeChoice(rawValue: call.arguments["mode"] ?? "") ?? .flat).mode
            if source == .currentPattern, state.displayedPattern == nil {
                return .refusal(status: 404, message: "No pattern is on screen to build the kernel from.")
            }
            state.statusText = "An agent pressed Build Kernel (\(source.rawValue))."
            Task {
                await noteDiskSettingChanges(of: state, by: "Build Kernel") {
                    switch source {
                    case .synthetic: await state.generateProbeKernel()
                    case .currentPattern: await state.generateMeasuredProbeKernel(mode: mode)
                    case .fileProbe: await state.generateFileProbeKernel(mode: mode)
                    }
                }
            }
            return .json(["building": source.rawValue, "mode": source == .synthetic ? "sigmoid_trench" : ModeChoice(mode).rawValue])
        },
        AgentTool(name: "set_detector", title: "Choose detector",
                  summary: "Chooses the Disks task's detector, as the Detector picker does: classical (correlation with the probe "
                      + "kernel) or neural_net (the learned detector proposes, classical refinement measures each), and the neural "
                      + "net's pick threshold. The detection on the pattern on screen follows.",
                  input: .window,
                  parameters: [
                      AgentParameter("detector", .choice(["classical", "neural_net"]), summary: "The detector.", required: true),
                      AgentParameter("threshold", .number(0.3...0.99), summary: "For neural_net: the pick threshold, lower accepts more."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            let learned = call.arguments["detector"] == "neural_net"
            if learned, !state.preferences.offerLearnedDetector {
                return .refusal(status: 403, message: "The neural net is not offered: the person turned it off in Settings > Analysis.")
            }
            state.learnedDetection.detectorClass = learned ? .learned : .classical
            if let text = call.arguments["threshold"], let value = Float(text), value.isFinite {
                state.learnedDetection.threshold = min(max(value, 0.3), 0.99)
            }
            state.statusText = "An agent chose the \(learned ? "neural net" : "classical") detector"
                + (learned ? ", threshold \(numberText(Double(state.learnedDetection.threshold)))." : ".")
            Task { await state.detectCurrentPattern() }
            return .json(kernelSummary(of: state))
        },
    ]

    /// What `get_probe_kernel` and `set_detector` answer.
    static func kernelSummary(of state: AppState) -> [String: Any] {
        let calibration = state.calibrationSession
        var kernel: Any = NSNull()
        if let built = state.probeKernel {
            kernel = ["source": built.source.rawValue, "mode": ModeChoice(built.mode).rawValue,
                      "radius_px": Double(built.probeRadius)]
        }
        let detector = state.learnedDetection.detectorClass
        return [
            "probe_radius_px": AgentJSON.number(calibration.calibration.probeRadius),
            "probe_radius_from": calibration.calibration.probeRadius == nil ? NSNull() as Any : (calibration.provenance.probe?.rawValue ?? "unknown") as Any,
            "kernel": kernel,
            "detector": detector == .learned ? "neural_net" : "classical",
            "threshold": Double(state.learnedDetection.threshold),
            "disk_detection": diskSettings(of: state)["disk_detection"] ?? NSNull(),
        ]
    }

    /// What the kernel tools' texts say about the disk settings that follow the probe (issue #232).
    static let diskDefaultsNote = "Measuring the probe sets min_peak_spacing to fit the probe when nobody has chosen one, as it "
        + "does for the person; get_probe_kernel shows the disk settings and get_log names any change."

    /// Runs `work` and, when it moved a disk detection setting the agent did not name, writes an Output line saying which and how
    /// (issue #232: Build Kernel set min_peak_spacing 16 → 4 without a word).
    static func noteDiskSettingChanges(of state: AppState, by action: String, _ work: () async -> Void) async {
        let before = state.diskDetection.diskParams
        await work()
        if let line = diskChangeLine(from: before, to: state.diskDetection.diskParams, by: action) { state.statusText = line }
    }

    /// A number as door text: six significant digits with a point, never the Mac's decimal comma (`String(format:)` without a
    /// locale is POSIX), so a Float setting reads 0.0005, not 0.000500000024.
    static func numberText(_ value: Double) -> String { String(format: "%.6g", value) }

    /// "<action> also changed disk detection: name old → new, ...", or nil when nothing changed.
    static func diskChangeLine(from before: DiskDetectionParams, to after: DiskDetectionParams, by action: String) -> String? {
        let changes = DiskSetting.all.compactMap { setting -> String? in
            let old = setting.read(before), new = setting.read(after)
            return old == new ? nil : "\(setting.parameter.name) \(numberText(old)) → \(numberText(new))"
        }
        return changes.isEmpty ? nil : "\(action) also changed disk detection: " + changes.joined(separator: ", ") + "."
    }

    /// Build Kernel's sources an agent can use (the vacuum scan needs a second file).
    enum KernelChoice: String, CaseIterable {
        case synthetic
        case currentPattern = "current_pattern"
        case fileProbe = "file_probe"
    }

    /// The measured kernel's modes, by an agent's names.
    enum ModeChoice: String, CaseIterable {
        case flat
        case sigmoidTrench = "sigmoid_trench"

        var mode: ProbeKernelMode { self == .flat ? .flat : .sigmoidTrench }
        init(_ mode: ProbeKernelMode) { self = mode == .flat ? .flat : .sigmoidTrench }
    }
}
