//
//  AgentDoorImaging.swift
//  Role: The agent door's Imaging and Reconstruction controls (issue #224): the virtual detector's shape, preset and numbers, what
//        a drag controls, the scan region summed into the pattern, the pattern pane's source, DPC's display, the single-slice
//        ptychography and parallax fields, and each parallax stage's button.
//
//  The detector's numbers take the typed path of the Settings tab (`ApertureEntry.apply`: the drag's snap, then the live image
//  update and the final pass). A stage runs as its button does and answers at once; get_window says busy until it is done.
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {

    /// One field of the Reconstruction panel as an agent names it.
    struct ReconstructionField {
        let parameter: AgentParameter
        let read: (AppState) -> Any
        let apply: (String, AppState) -> Void

        static func number<Root: AnyObject, V: BinaryFloatingPoint>(
            _ name: String, _ range: ClosedRange<Double>, _ summary: String,
            _ root: @escaping (AppState) -> Root, _ path: ReferenceWritableKeyPath<Root, V>
        ) -> ReconstructionField {
            ReconstructionField(parameter: AgentParameter(name, .number(range), summary: summary),
                                read: { Double(root($0)[keyPath: path]) },
                                apply: { text, state in if let v = Double(text) { root(state)[keyPath: path] = V(v) } })
        }

        static func integer<Root: AnyObject>(
            _ name: String, _ range: ClosedRange<Int>, _ summary: String,
            _ root: @escaping (AppState) -> Root, _ path: ReferenceWritableKeyPath<Root, Int>
        ) -> ReconstructionField {
            ReconstructionField(parameter: AgentParameter(name, .integer(range), summary: summary),
                                read: { root($0)[keyPath: path] },
                                apply: { text, state in if let v = Int(text) { root(state)[keyPath: path] = v } })
        }

        static func boolean<Root: AnyObject>(
            _ name: String, _ summary: String,
            _ root: @escaping (AppState) -> Root, _ path: ReferenceWritableKeyPath<Root, Bool>
        ) -> ReconstructionField {
            ReconstructionField(parameter: AgentParameter(name, .boolean, summary: summary),
                                read: { root($0)[keyPath: path] },
                                apply: { text, state in root(state)[keyPath: path] = text == "true" })
        }

        static let all: [ReconstructionField] = {
            let p: (AppState) -> PtychographySettings = { $0.ptychography }
            let x: (AppState) -> PhaseContrastProduct = { $0.phaseContrast }
            return [
                ReconstructionField(parameter: AgentParameter("dpc_display", .choice(caseNames(DPCDisplayMode.self)),
                                                              summary: "DPC: the map shown."),
                                    read: { caseName($0.dpc.dpcDisplay) },
                                    apply: { text, state in
                                        if let mode = named(text, DPCDisplayMode.self) { state.dpc.dpcDisplay = mode }
                                    }),
                number("ptycho_defocus_angstrom", -1e6...1e6, "Ptychography: the probe's defocus, Å (py4DSTEM's defocus; C10 = -defocus).", p, \.defocusAngstrom),
                number("ptycho_c12a_angstrom", -1e6...1e6, "Ptychography: astigmatism C12a, Å.", p, \.c12aAngstrom),
                number("ptycho_c12b_angstrom", -1e6...1e6, "Ptychography: astigmatism C12b, Å.", p, \.c12bAngstrom),
                integer("ptycho_iterations", 1...1000, "Ptychography: iterations.", p, \.iterations),
                number("ptycho_step", 0...10, "Ptychography: gradient step size.", p, \.stepSize),
                number("ptycho_norm_min", 0...1e6, "Ptychography: normalization minimum.", p, \.normalizationMinimum),
                boolean("ptycho_fix_probe", "Ptychography: keep the probe fixed.", p, \.fixProbe),
                boolean("ptycho_limit_object_transmission", "Ptychography: limit object transmission to 1.", p, \.constrainObjectAmplitude),
                boolean("ptycho_pure_phase", "Ptychography: pure-phase object.", p, \.purePhaseObject),
                boolean("ptycho_recenter_probe", "Ptychography: recenter the probe each iteration.", p, \.fixProbeCenterOfMass),
                boolean("ptycho_constrain_probe_support", "Ptychography: constrain the probe's support.", p, \.constrainProbeAmplitude),
                number("ptycho_support_radius", 0...10, "Ptychography: probe support radius.", p, \.probeAmplitudeRadius),
                number("ptycho_support_edge", 0...10, "Ptychography: probe support edge width.", p, \.probeAmplitudeWidth),
                number("parallax_lowpass_inv_angstrom", 0...100, "Parallax stage 3: low-pass, Å⁻¹ (0 off).", x, \.parallaxQLowpassInvAngstrom),
                number("parallax_highpass_inv_angstrom", 0...100, "Parallax stage 3: high-pass, Å⁻¹ (0 off).", x, \.parallaxQHighpassInvAngstrom),
                number("parallax_kde_sigma_px", 0...100, "Parallax stage 4: KDE σ, pixels.", x, \.parallaxKDESigmaPixels),
                number("parallax_upsample_factor", 0...64, "Parallax stage 4: upsampling factor (0 automatic).", x, \.parallaxKDEUpsampleFactor),
                integer("parallax_lanczos_order", 0...16, "Parallax stage 4: Lanczos order (0 off).", x, \.parallaxKDELanczosOrder),
                integer("parallax_position_iterations", 0...1000, "Parallax stage 4: position-correction iterations.", x, \.parallaxPositionCorrectionIterations),
                boolean("parallax_sinc_lowpass", "Parallax stage 4: sinc low-pass.", x, \.parallaxKDELowpass),
                boolean("parallax_checkerboard_steps", "Parallax stage 4: checkerboard position steps.", x, \.parallaxPositionCorrectionCheckerboard),
                number("depth_start_angstrom", -1e6...1e6, "Depth stack: first plane, Å.", x, \.parallaxDepthStartAngstrom),
                number("depth_end_angstrom", -1e6...1e6, "Depth stack: last plane, Å.", x, \.parallaxDepthEndAngstrom),
                integer("depth_planes", 1...1000, "Depth stack: number of planes.", x, \.parallaxDepthPlaneCount),
                number("depth_info_limit", 0...1e6, "Depth stack: information limit (0 none).", x, \.parallaxDepthInformationLimit),
                number("depth_info_power", 0...100, "Depth stack: information power.", x, \.parallaxDepthInformationPower),
                boolean("depth_full_ctf", "Depth stack: use the full fitted CTF.", x, \.parallaxDepthUseFullFit),
            ]
        }()
    }

    /// A Reconstruction button an agent presses, by name.
    enum ReconstructionStep: String, CaseIterable {
        case preparePreview = "prepare_preview", alignNextLevel = "align_next_level", resetAlignment = "reset_alignment"
        case fitAberrations = "fit_aberrations", correctPhase = "correct_phase", upsampleBF = "upsample_bf"
        case depthStack = "depth_stack", useParallaxFit = "use_parallax_fit", reconstructObject = "reconstruct_object"
    }

    static let imagingTools: [AgentTool] = [
        AgentTool(name: "set_virtual_detector", title: "Virtual detector",
                  summary: "Sets Imaging's virtual detector as its Settings tab does, only what is given: shape (circle, annulus, "
                      + "rectangle, point), a preset (brightField, adf, haadf: sets the radii from the measured probe), and the numbers "
                      + "in detector pixels (center_x, center_y, inner, outer). The real-space image follows; get_result_image shows it.",
                  input: .window,
                  parameters: [
                      AgentParameter("shape", .choice(caseNames(VirtualShapeMode.self)), summary: "The detector geometry."),
                      AgentParameter("preset", .choice(["brightField", "adf", "haadf"]), summary: "BF, ADF or HAADF radii."),
                      AgentParameter("center_x", .number(0...100_000), summary: "Centre x, detector pixels."),
                      AgentParameter("center_y", .number(0...100_000), summary: "Centre y, detector pixels."),
                      AgentParameter("inner", .number(0...100_000), summary: "Annulus inner radius, detector pixels."),
                      AgentParameter("outer", .number(0...100_000), summary: "Outer radius (half-width for a rectangle), pixels."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard let descriptor = state.descriptor else { return .refusal(status: 404, message: "This window has no dataset open.") }
            if let shape = named(call.arguments["shape"], VirtualShapeMode.self), shape != state.resultPresentation.virtualShape {
                state.resultPresentation.virtualShape = shape   // the window's onChange commits it, as for the picker
            }
            if let preset = named(call.arguments["preset"], DetectorPreset.self) { state.applyDetectorPreset(preset) }
            let fields: [(String, ApertureEntry.Field)] = [("center_x", .centerX), ("center_y", .centerY), ("inner", .inner), ("outer", .outer)]
            for (name, field) in fields {
                if let value = call.arguments[name].flatMap(Double.init) {
                    ApertureEntry.apply(value, to: field, in: state, patternWidth: descriptor.qx, patternHeight: descriptor.qy)
                }
            }
            state.statusText = agentChangeLine("the virtual detector", call.arguments)
            return .json(imagingSettings(of: state))
        },
        AgentTool(name: "set_imaging", title: "Imaging view",
                  summary: "Sets what Imaging shows, only what is given: direction (detector: the virtual detector makes the "
                      + "real-space image; region: a scan region is summed into the pattern), the region's shape (point, rectangle, "
                      + "circle) and radius in scan pixels around the selected position, and the pattern pane's source (current "
                      + "position, mean or max pattern).",
                  input: .window,
                  parameters: [
                      AgentParameter("direction", .choice(["detector", "region"]), summary: "What a drag on the panes controls."),
                      AgentParameter("region_shape", .choice(caseNames(RegionShape.self)), summary: "The scan region's shape."),
                      AgentParameter("region_radius", .number(1...100_000), summary: "Radius or half-width, scan pixels."),
                      AgentParameter("pattern_shown", .choice(caseNames(PatternDisplayMode.self)), summary: "current, mean or max."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            if let direction = call.arguments["direction"] { state.activePane = direction == "region" ? .realSpace : .diffraction }
            if let shape = named(call.arguments["region_shape"], RegionShape.self), shape != state.realSpaceShape {
                state.realSpaceShape = shape   // the window's onChange sums the new region, as for the picker
            }
            if let radius = call.arguments["region_radius"].flatMap(Float.init) {
                let most = state.descriptor.map { Float(max(1, max($0.rx, $0.ry) / 2)) } ?? radius
                state.realSpaceRadius = min(max(radius, 1), most)
            }
            if let mode = named(call.arguments["pattern_shown"], PatternDisplayMode.self) {
                guard mode == .current || state.meanPattern != nil else {
                    return .refusal(status: 409, message: "The mean and max patterns exist once the origin is calibrated (run_calibration).")
                }
                state.patternDisplayMode = mode
            }
            state.statusText = agentChangeLine("Imaging", call.arguments)
            return .json(imagingSettings(of: state))
        },
        AgentTool(name: "set_reconstruction", title: "Reconstruction settings",
                  summary: "Sets the Reconstruct workspace's fields, only those given: DPC's display, single-slice ptychography's "
                      + "probe and options, and the parallax stages' filters, upsampling and depth stack. run_reconstruction_step "
                      + "presses a stage's button; run_task runs the current task's next step.",
                  input: .window,
                  parameters: ReconstructionField.all.map(\.parameter),
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            for field in ReconstructionField.all {
                if let text = call.arguments[field.parameter.name] { field.apply(text, state) }
            }
            state.statusText = agentChangeLine("Reconstruction", call.arguments)
            return .json(reconstructionSettings(of: state))
        },
        AgentTool(name: "run_reconstruction_step", title: "Reconstruction step",
                  summary: "Presses one of the Reconstruct workspace's buttons: the parallax stages in order (prepare_preview, "
                      + "align_next_level, reset_alignment, fit_aberrations, correct_phase, upsample_bf, depth_stack), "
                      + "use_parallax_fit (fills ptychography's probe from the parallax fit; check the rotation branch's sign), and "
                      + "reconstruct_object (single-slice ptychography). A long step answers at once; get_window says busy until it "
                      + "ends and get_log how.",
                  input: .window,
                  parameters: [AgentParameter("step", .choice(ReconstructionStep.allCases.map(\.rawValue)), summary: "The button.",
                                              required: true)],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.isBusy else { return busyRefusal }
            guard state.hasDataset else { return .refusal(status: 404, message: "This window has no dataset open.") }
            guard let step = call.arguments["step"].flatMap(ReconstructionStep.init(rawValue:)) else {
                return .refusal(status: 400, message: "Name a step.")
            }
            state.statusText = "An agent pressed \(step.rawValue) in Reconstruct."
            switch step {
            case .resetAlignment:
                state.resetParallaxAlignment()
            case .fitAberrations:
                if case .failed(let reason) = state.fitParallaxAberrations() { return .refusal(status: 409, message: reason) }
            case .useParallaxFit:
                guard state.phaseContrast.parallaxAberrationFit != nil else {
                    return .refusal(status: 409, message: "There is no parallax aberration fit yet (fit_aberrations).")
                }
                state.usePtychographyProbeFromParallaxFit()
            case .preparePreview: Task { _ = await state.prepareParallaxPreview() }
            case .alignNextLevel: Task { _ = await state.alignParallaxNextLevel() }
            case .correctPhase: Task { _ = await state.correctParallaxPhase() }
            case .upsampleBF: Task { _ = await state.upsampleParallaxBF() }
            case .depthStack: Task { _ = await state.computeParallaxDepthSections() }
            case .reconstructObject: Task { _ = await state.runSingleslicePtychography() }
            }
            return .json(["pressed": step.rawValue, "settings": reconstructionSettings(of: state)])
        },
    ]

    static func imagingSettings(of state: AppState) -> [String: Any] {
        let a = state.aperture
        return [
            "direction": state.activePane == .realSpace ? "region" : "detector",
            "detector": ["shape": caseName(state.resultPresentation.virtualShape),
                         "center_x": Double(a.centerX), "center_y": Double(a.centerY),
                         "inner": Double(a.inner), "outer": Double(a.outer)] as [String: Any],
            "region": ["shape": caseName(state.realSpaceShape), "radius": Double(state.realSpaceRadius),
                       "center": ["x": state.selectedScan.x, "y": state.selectedScan.y]] as [String: Any],
            "pattern_shown": caseName(state.patternDisplayMode),
        ]
    }

    static func reconstructionSettings(of state: AppState) -> [String: Any] {
        var out: [String: Any] = [:]
        for field in ReconstructionField.all { out[field.parameter.name] = field.read(state) }
        let x = state.phaseContrast
        out["parallax_stages_done"] = [
            "preview": x.parallaxPreprocess != nil,
            "aligned": x.parallaxAlignment?.isComplete == true,
            "aberrations_fitted": x.parallaxHigherOrderFit != nil,
            "phase_corrected": x.parallaxCorrection != nil,
        ]
        return out
    }
}
