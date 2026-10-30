//
//  ReplayContract.swift
//  Role: The replay contract in one table. For every step kind a recording
//        site writes into the recipe (`AppState.recordReplayStep`): the keys it
//        writes, and for each key how it moves between detector frames, whether
//        the staleness check compares it, and whether the replay reads it back;
//        plus the parser that turns the step into a plan.
//
//  Three readers used to keep their own copy of this: the staleness signature
//  (`ProductWorkflow.currentReplaySignature`), the frame-role table
//  (`ReplayRecordFrameMap.role`) and the parser (`ReplayPlanner.parse`). They
//  now all read this table, and `ReplayContractTests` walks every row against
//  the recording sites' own builders, so a key added at one site and missed at
//  another fails a test instead of a promote.
//
//  The table FOLLOWS the recording sites, never leads them: a new key starts at
//  the site, then gets its row here.
//

import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif

package enum ReplayContract {

    /// Whether the staleness check (`ProductWorkflow.stalenessVerdict`) compares
    /// a key against current settings.
    package enum Signature: Equatable {
        /// An input the user sets: a change makes the product stale.
        case compared
        /// Recorded but not a setting: a fit output (strain's `resolved_g*`) or
        /// a rewind-only input (`input_g*`). Comparing an output would call a
        /// map stale for having been computed at all.
        case notCompared
    }

    /// Whether `ReplayPlanner.parse` reads a key into the plan the replay runs.
    package enum Replay: Equatable {
        /// Read (and validated) by the parser, in the step that carries it.
        case read
        /// Recorded, and not read by the replay. Every such key says why in the
        /// table below; the contract test holds the parser to it.
        case notRead
    }

    package struct Key: Equatable {
        package let role: ReplayRecordFrameMap.Role
        package let signature: Signature
        package let replay: Replay

        package init(_ role: ReplayRecordFrameMap.Role, _ signature: Signature, _ replay: Replay) {
            self.role = role
            self.signature = signature
            self.replay = replay
        }
    }

    package struct Entry {
        /// `SessionReplayRecord.Step.kind`.
        package let kind: String
        /// The step's name in the replay summary and progress.
        package let title: String
        /// Every key a recording site may write for this kind.
        package let keys: [String: Key]
        /// The step back as the typed plan its entry point takes, or a refusal.
        package let parse: (SessionReplayRecord.Step) -> Result<ReplayStepPlan, ReplayRefusal>

        /// The keys the staleness check compares.
        package var signatureKeys: Set<String> {
            Set(keys.filter { $0.value.signature == .compared }.keys)
        }
    }

    /// The contract, in pipeline order.
    package static let entries: [Entry] = [
        Entry(
            kind: "virtual_detector", title: "Virtual detector",
            // `Aperture.replayParameters(shape:aperture:)`.
            keys: [
                "shape": Key(.invariant, .compared, .read),
                "center_x": Key(.positionX, .compared, .read),
                "center_y": Key(.positionY, .compared, .read),
                "inner": Key(.length, .compared, .read),
                "outer": Key(.length, .compared, .read),
            ],
            parse: ReplayPlanner.parseVirtualDetector),
        Entry(
            kind: "dpc", title: "DPC",
            // `runDPC`: the origin class only; the CoM takes no aperture.
            keys: ["origin_reference": Key(.invariant, .compared, .read)],
            parse: ReplayPlanner.parseDPC),
        Entry(
            kind: "disk_detection", title: "Bragg disk detection",
            // `DiskDetectionParams.replayParameters(kernel:)` merged with
            // `LearnedDetectionSession.replayParameters(for:threshold:model:)`.
            keys: [
                "corr_power": Key(.invariant, .compared, .read),
                "sigma_dp": Key(.length, .compared, .read),
                "sigma_cc": Key(.length, .compared, .read),
                "subpixel": Key(.invariant, .compared, .read),
                "upsample_factor": Key(.invariant, .compared, .read),
                "min_absolute_intensity": Key(.absoluteIntensity, .compared, .read),
                "min_relative_intensity": Key(.invariant, .compared, .read),
                "relative_to_peak": Key(.invariant, .compared, .read),
                // Absent before 2026-09-15; absence parses as 0, the rule then.
                "relative_reference_minimum_radius_px": Key(.length, .compared, .read),
                "min_peak_spacing": Key(.length, .compared, .read),
                "edge_boundary": Key(.lengthInt, .compared, .read),
                "max_peaks": Key(.invariant, .compared, .read),
                "kernel_source": Key(.invariant, .compared, .read),
                // Not read: the parser replays only a synthetic kernel, and a
                // synthetic kernel is always the sigmoid-trench form, so the
                // mode follows from `kernel_source`.
                "kernel_mode": Key(.invariant, .compared, .notRead),
                // Not read: empty for a synthetic kernel; a file-probe or
                // vacuum-scan kernel refuses, naming the path.
                "kernel_probe_path": Key(.invariant, .compared, .notRead),
                // Absent before the learned detector; absence parses as classical.
                "detector_class": Key(.invariant, .compared, .read),
                "learned_threshold": Key(.invariant, .compared, .read),
                "learned_model_sha256": Key(.invariant, .compared, .read),
                // Not read: the replay finds a fine-tuned model by its hash,
                // which names it; origin and parent describe it.
                "learned_model_origin": Key(.invariant, .compared, .notRead),
                "learned_model_parent_sha256": Key(.invariant, .compared, .notRead),
            ],
            parse: ReplayPlanner.parseDiskDetection),
        Entry(
            kind: "strain", title: "Strain mapping",
            // `StrainProduct.recordedParameters`.
            keys: [
                "reference_mode": Key(.invariant, .compared, .read),
                "basis_mode": Key(.invariant, .compared, .read),
                // The lattice the run found: a fit output. A manual-basis
                // replay indexes with it; a consensus replay re-derives it.
                "resolved_g1_x": Key(.length, .notCompared, .read),
                "resolved_g1_y": Key(.length, .notCompared, .read),
                "resolved_g2_x": Key(.length, .notCompared, .read),
                "resolved_g2_y": Key(.length, .notCompared, .read),
                // A manual run's input basis: only the lineage rewind reads it.
                "input_g1_x": Key(.length, .notCompared, .notRead),
                "input_g1_y": Key(.length, .notCompared, .notRead),
                "input_g2_x": Key(.length, .notCompared, .notRead),
                "input_g2_y": Key(.length, .notCompared, .notRead),
            ],
            parse: ReplayPlanner.parseStrain),
        Entry(
            kind: "acom", title: "ACOM orientation mapping",
            // `ReplayStepPlan.ACOMReplayPlan.recordedParameters`.
            keys: [
                "material": Key(.invariant, .compared, .read),
                "scale_inv_angstrom_per_pixel": Key(.perPixelScale, .compared, .read),
                // Not read: the replay matches on the backend the session
                // chooses; the backends agree within the float32 tolerance.
                "matching_backend": Key(.invariant, .compared, .notRead),
                "scope": Key(.invariant, .compared, .read),
                "quality": Key(.invariant, .compared, .read),
                // lattice_a is in Å, so frame-invariant (custom phases only).
                "lattice_a": Key(.invariant, .compared, .read),
                "material_fingerprint": Key(.invariant, .compared, .read),
                "refines_in_plane": Key(.invariant, .compared, .read),
            ],
            parse: ReplayPlanner.parseACOM),
    ]

    /// The row for a recorded kind; nil for a kind this build does not record.
    package static func entry(kind: String) -> Entry? {
        entries.first { $0.kind == kind }
    }
}
