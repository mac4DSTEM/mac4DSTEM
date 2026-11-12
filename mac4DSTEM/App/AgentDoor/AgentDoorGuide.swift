//
//  AgentDoorGuide.swift
//  Role: The agent door's workflow guide (issue #236): how a person works through a 4D-STEM scan in mac4DSTEM and the checks
//        they make at each step, so an agent does not have to bring its own crystallography to judge a disk detection. The
//        first real-agent run (Thronsen A, 12 Nov 2026) found the door enough to act but silent on what "good" looks like.
//
//  The guide names methods, not numbers for one dataset: no value here is tuned to a sample (no presets). Every tool it names is
//  a registered tool (`AgentDoorGuideTests`).
//

import Foundation
import ShellAgentDoor

extension Mac4DSTEMAgentDoor {
    static let guideTools: [AgentTool] = [
        AgentTool(name: "get_workflow_guide", title: "Workflow guide",
                  summary: "Read this first. How a person evaluates a 4D-STEM scan in mac4DSTEM, step by step, which tool does each "
                      + "step and how to judge the result (what a good disk detection looks like, how to find the noise floor). "
                      + "topic: " + Guide.allCases.map(\.rawValue).joined(separator: ", ") + "; overview by default.",
                  input: .noWindow,
                  parameters: [AgentParameter("topic", .choice(Guide.allCases.map(\.rawValue)), summary: "The part to read.")]) { call in
            let topic = call.arguments["topic"].flatMap(Guide.init(rawValue:)) ?? .overview
            return .json(["topic": topic.rawValue, "guide": topic.text,
                          "other_topics": Guide.allCases.filter { $0 != topic }.map(\.rawValue)])
        },
    ]

    /// The guide's parts, as `get_workflow_guide` hands them out.
    enum Guide: String, CaseIterable {
        case overview
        case calibration
        case disks
        case phaseMapping = "phase_mapping"

        var text: String {
            switch self {
            case .overview: Self.overviewText
            case .calibration: Self.calibrationText
            case .disks: Self.disksText
            case .phaseMapping: Self.phaseMappingText
            }
        }

        private static let overviewText = """
            How a person works through a 4D-STEM scan in mac4DSTEM (the order the sidebar follows):

            1. Look. `get_window` says what is open, what the calibration lacks (calibration.items, verdict) and why a step \
            cannot run yet. `get_scan_map` shows a virtual image of the scan with the pixel-to-position rule; \
            `select_scan_position` then `get_pattern_image` shows the diffraction pattern there. Look at a few positions \
            first: the matrix, a feature (a precipitate, a grain boundary), vacuum if there is any.
            2. Calibrate (Prepare). See topic calibration. What the file carries is read already; never guess a voltage or a \
            pixel size: ask the person.
            3. Detect disks (Bragg Disks). See topic disks. Tune on single patterns, check on a feature and on the matrix, \
            then `run_task` detects the whole scan.
            4. Map (Map, Strain, Phase mapping, ...). `select_task`, read the task's settings in `get_window`, set them, \
            `run_task`; judge the map with `get_result_image` against the scan map. See topic phase_mapping.

            Ways of working the person expects:
            - Change one setting at a time and look at the picture after each change. Numbers alone mislead; the pictures \
            are drawn by the same code that draws the person's screen.
            - Every change shows in the person's Output as "An agent ...". When a tool moves a setting you did not name, \
            the Output says so (`get_log`).
            - Do not run the whole scan, or anything long, until the person says so. `stop_run` cancels.
            - Say what you saw, and mark a reading as yours (for example "fits a T1-type superlattice") unless the data \
            proves it.
            - When a tool refuses, its message says why and what would make it possible; do that or ask the person.
            """

        private static let calibrationText = """
            Calibration (Prepare). `get_window` calibration.items lists each part, its state and where it came from:

            - Q pixel size (Å⁻¹ or mrad per detector pixel) and R pixel size (scan step): read from the file when it carries \
            them. When it does not, ask the person; `set_calibration` types a value they give. A Q size from a known crystal \
            is the person's step (Prepare's Q from crystal).
            - Voltage: from the file or the person. Without it mrad and Å⁻¹ cannot be converted.
            - Origin & probe: `run_calibration` step origin (origin_method centreOfMass, or friedel when a beamstop hides the direct beam) finds the beam's \
            centre per position and the probe radius. On a spot pattern from a crystal the Origin & probe row may point to \
            step origin_from_bragg_peaks instead: detect the disks over the scan first, then run it.
            - Ellipse: step ellipse fits the elliptical distortion of the detector on a ring of disks or an amorphous ring \
            between fit_inner_px and fit_outer_px (detector pixels from the origin). Choose the annulus around a ring that is \
            present in every pattern.
            - R–Q rotation: step rotation, needed only for maps that mix real and diffraction directions (strain, DPC).

            The verdict says whether results are quantitative. A map from an uncalibrated scan is still useful for finding \
            features; say that its numbers are in pixels.
            """

        private static let disksText = """
            Disk detection (Bragg Disks task). The detector correlates each pattern with a probe kernel and keeps the \
            correlation peaks that pass the settings (template matching as in py4DSTEM, Savitzky et al. 2021, Microsc. \
            Microanal. 27, 712; hybrid correlation, Pekin et al. 2017, Ultramicroscopy 176, 170).

            Steps:
            1. `build_probe_kernel` (synthetic needs a probe radius; Calibrate Origin measures one when missing). It can move \
            min_peak_spacing to fit the probe; the Output says so. `get_probe_kernel` shows the kernel and the disk settings.
            2. Pick a position on a feature and one in the matrix (`get_scan_map`, `select_scan_position`).
            3. `get_pattern_image` draws the detected disks as circles; `get_detected_disks` lists them.
            4. Change one setting with `set_disk_detection`, look again, on both positions.

            What a good detection looks like:
            - Every circle sits on a disk and its radius matches the disk. Circles bigger or smaller than the disks: the \
            probe radius is wrong (`set_probe_radius`).
            - No circles on empty background. Lower min_relative_intensity until false disks appear on the background of \
            the matrix position (or near vacuum); that is the noise floor. Set it just above.
            - Weak disks that matter (superlattice, precipitate, ordering reflections) sit on a lattice. Take the basis from \
            two strong disks and check the weak ones lie at sums or simple fractions of it; disks at random positions are \
            noise. A reflection present on the feature and absent on the matrix belongs to the feature.
            - Disks are not lost in pairs: min_peak_spacing must stay below the distance between the closest real disks.
            - Disks cut by the detector edge are dropped by edge_boundary; that is expected.

            Settings in brief:
            - min_relative_intensity: weakest disk kept, as a fraction of the reference disk (relative_to_peak, from 0 the \
            brightest). When a saturated direct beam sets the scale, relative_reference_min_radius_px measures against the \
            brightest disk outside that radius instead.
            - min_absolute_intensity: a floor on the correlation itself; 0 turns it off.
            - corr_power: 1 cross-correlation (robust on noisy data), 0 phase correlation (sharp, for patterned probes), \
            between them the hybrid.
            - sigma_cc and sigma_dp: smoothing of the correlation and of the pattern, for noisy data.
            - subpixel: poly by default; multicorr (with upsample_factor) for strain-grade positions, slower.
            - max_peaks: the most disks kept per pattern.

            There is no single right value for any of these: the defaults are scaled to the detector, and the right \
            threshold depends on the dataset's dynamic range. Find it by looking, as above, and say what you chose and why. \
            Only then, with the person's word, `run_task` over the whole scan; `get_window` disk_detection.scan_summary \
            then gives disks per position, positions without disks and positions at max_peaks.
            """

        private static let phaseMappingText = """
            Phase mapping (Map workspace). It matches each position's detected disks to reference libraries of the phases \
            in the list, so disks must be detected over the whole scan first (topic disks).

            - `select_task` task "Phase mapping", then `get_window` task_settings shows the phases, the settings, what each \
            tolerance is in detector pixels (on_this_detector) and run_refusal: why the task cannot run yet.
            - The phases: `add_phase` takes a CIF from the Agent folder (the first is the matrix), `set_phase` marks the \
            matrix and sets a phase's own excitation slab, `remove_phase` takes one out. The orientations are found from \
            the structures (default); `set_phase_mapping` orientation_source typedZones uses typed zone axes instead.
            - A thin plate or needle stays excited further from the Bragg condition than the bulk: if a known phase is \
            missed, raise its own excitation slab (a plate seen edge-on can need several times the default) and compare last_run.
            - Tolerances are in Å⁻¹ and met on the detector's pixel grid: `scale_phase_matching_to_detector` sets pair radius \
            and matrix removal to one detector pixel; on_this_detector.advice says when a value is below a pixel.
            - `set_phase_mapping` changes the library and matching settings; changing the classifier resets \
            min_intensity_fraction to that classifier's default, as the picker does.
            - After `run_task`, `get_window` phase_mapping.last_run gives positions per phase, not indexed and the learned \
            relationships. Judge the map with `get_result_image` against `get_scan_map`: a phase should sit where the \
            features are, with its known shape, and not on the matrix. Check a few called positions with \
            `select_scan_position` and `get_pattern_image`.
            """
    }
}
