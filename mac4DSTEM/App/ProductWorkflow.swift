import Foundation
import DSTEMCore
import DSTEMSession

/// The product-level information architecture. Scientific algorithms remain
/// represented by `AnalysisMode`; these areas describe the outcome a user is
/// trying to reach and keep implementation details out of primary navigation.
enum WorkspaceArea: String, CaseIterable, Identifiable, Sendable {
    case prepare
    case image
    case map
    case reconstruct
    case results

    var id: String { rawValue }

    // S22c: the five steps are re-cut along the physics
    // (docs/s22-ux-design.md §4.2). Case names and raw values deliberately
    // keep their v1 identities — `image`/`map`/`reconstruct` — so persisted
    // recovery records and any stored selection survive the re-cut; only the
    // presented names and the task assignment change.
    var title: String {
        switch self {
        case .prepare: "Prepare"
        case .image: "Imaging"
        // D1 (owner, 2026-09-01): named by its OUTCOMES — "Bragg" put the
        // method's name four times in one sidebar column.
        case .map: "Strain & ACOM"
        case .reconstruct: "Phase"
        case .results: "Results"
        }
    }

    var subtitle: String {
        switch self {
        case .prepare: "Inspect and calibrate the dataset"
        case .image: "Form BF, ADF, or custom virtual images"
        case .map: "Detect Bragg disks, then strain and orientation"
        case .reconstruct: "DPC, parallax, and ptychography"
        case .results: "Review, save, and export products"
        }
    }

    var systemImage: String {
        switch self {
        case .prepare: "scope"
        case .image: "camera.filters"
        case .map: "map"
        case .reconstruct: "waveform.path.ecg.rectangle"
        case .results: "square.grid.2x2"
        }
    }

    var analysisModes: [AnalysisMode] {
        switch self {
        case .prepare, .results: []
        case .image: [.virtualDetector]
        // The Bragg path in its pipeline order: disks produce the vectors
        // the other two consume.
        case .map: [.disks, .strain, .acom]
        // The phase-contrast family, together — every member needs only
        // voltage and geometry, none needs Bragg vectors (§3.3 grammar).
        case .reconstruct: [.dpc, .ptychography]
        }
    }

    var defaultAnalysisMode: AnalysisMode? { analysisModes.first }

    /// This workspace's tasks, grouped into their prerequisite families in
    /// `TaskPrerequisiteFamily.allCases` order. Empty families are dropped, so
    /// the count of the result is the number of families actually present.
    var taskFamilyGroups: [TaskFamilyGroup] {
        TaskPrerequisiteFamily.allCases.compactMap { family in
            let modes = analysisModes.filter { $0.prerequisiteFamily == family }
            return modes.isEmpty ? nil : TaskFamilyGroup(family: family, modes: modes)
        }
    }

    /// Whether the family captions (#4) earn their place here.
    ///
    /// A caption's job is to *distinguish* families. With only one family
    /// present there is nothing to distinguish, so the caption states something
    /// the workspace already implies and is pure noise — which is what
    /// Reconstruct (one task) and Image (two tasks, one family) both looked
    /// like. Keyed on family count rather than task count for that reason.
    var showsTaskFamilyLabels: Bool { taskFamilyGroups.count > 1 }
}

/// Display-only orientation of the **real-space** image (backlog #17b).
///
/// Quarter turns only: a multiple of 90° is exact and needs no interpolation,
/// so every displayed pixel still corresponds one-to-one to a scan position.
/// An arbitrary angle would resample the scan grid and produce an image that
/// looks like data but no longer maps to scan indices.
///
/// **Never offered for the diffraction pattern.** The app carries a *measured*
/// R–Q rotation calibration, and a display rotation of the CBED would be
/// indistinguishable from it on screen.
enum RealSpaceDisplayOrientation: Int, CaseIterable, Identifiable, Sendable {
    case identity = 0
    case quarterTurn = 1
    case halfTurn = 2
    case threeQuarterTurn = 3

    var id: Int { rawValue }
    var degrees: Double { Double(rawValue) * 90 }

    /// Whether this turn exchanges the displayed horizontal and vertical axes.
    /// For a non-square scan that decides which R pixel size drives the scale
    /// bar, so it must never be inferred from the angle at the call site.
    var swapsAxes: Bool { rawValue % 2 == 1 }

    var displayName: String {
        switch self {
        case .identity: "0°"
        case .quarterTurn: "90°"
        case .halfTurn: "180°"
        case .threeQuarterTurn: "270°"
        }
    }
}

/// One prerequisite family and the tasks a workspace has in it.
struct TaskFamilyGroup: Identifiable, Sendable {
    let family: TaskPrerequisiteFamily
    let modes: [AnalysisMode]
    var id: TaskPrerequisiteFamily { family }
}

/// Which side of the Bragg-vector dependency a task sits on.
///
/// Two families of analysis have very different prerequisites: the Bragg path
/// (disks → strain/ACOM) needs disk detection and crystal calibration, while
/// the phase-contrast path (DPC, parallax, ptychography) needs only energy and
/// geometry. S22c aligned the workspaces with these families (Bragg and Phase
/// are now workspaces); the per-task grouping remains for any future task mix.
///
/// Deliberately three cases, not two: `.disks` *produces* the vectors that
/// `.strain` and `.acom` consume, so a single "requires Bragg vectors" label
/// spanning all of Map would be wrong about the one task that satisfies it.
///
/// `allCases` order is the order groups are presented in.
enum TaskPrerequisiteFamily: CaseIterable, Identifiable, Sendable {
    case producesBraggVectors
    case requiresBraggVectors
    case phaseContrast

    var id: Self { self }

    var groupLabel: String {
        switch self {
        case .producesBraggVectors: "Produces Bragg vectors"
        case .requiresBraggVectors: "Requires Bragg vectors"
        case .phaseContrast: "No Bragg vectors required"
        }
    }

    var accessibilitySuffix: String {
        switch self {
        case .producesBraggVectors: "producesBragg"
        case .requiresBraggVectors: "requiresBragg"
        case .phaseContrast: "phaseContrast"
        }
    }
}

extension AnalysisMode {
    var prerequisiteFamily: TaskPrerequisiteFamily {
        switch self {
        case .disks: .producesBraggVectors
        case .strain, .acom: .requiresBraggVectors
        case .virtualDetector, .dpc, .ptychography: .phaseContrast
        }
    }

    var workspaceArea: WorkspaceArea {
        switch self {
        case .virtualDetector: .image
        case .disks, .strain, .acom: .map
        // DPC sits with its prerequisite family (S22c): it shares the
        // voltage-only contract with parallax/ptychography, not the
        // zero-prerequisite contract of virtual imaging.
        case .dpc, .ptychography: .reconstruct
        }
    }

    var productTitle: String {
        switch self {
        case .virtualDetector: "Virtual imaging"
        case .dpc: "DPC & iDPC"
        case .disks: "Bragg disks"
        case .strain: "Strain"
        case .ptychography: "Parallax & ptychography"
        case .acom: "Orientation"
        }
    }

    var productSubtitle: String {
        switch self {
        case .virtualDetector: "Form BF, ADF, HAADF, or custom detector images"
        case .dpc: "Map beam deflection and integrate projected phase"
        case .disks: "Detect reciprocal-lattice peaks across the scan"
        case .strain: "Measure lattice distortion from indexed Bragg peaks"
        case .ptychography: "Reconstruct phase, amplitude, aberrations, and depth"
        case .acom: "Match crystal orientation and reliability"
        }
    }

    var systemImage: String {
        switch self {
        case .virtualDetector: "circle.dotted"
        case .dpc: "arrow.up.and.down.and.arrow.left.and.right"
        case .disks: "circle.grid.cross"
        case .strain: "arrow.up.left.and.arrow.down.right"
        case .ptychography: "waveform.path.ecg"
        case .acom: "cube.transparent"
        }
    }
}

/// Pure, testable guidance used by the sidebar and empty/result states.
struct ProductWorkflowReadiness: Equatable, Sendable {
    var hasOriginProbe = false
    var hasRotation = false
    var hasQScale = false
    var hasRScale = false
    var hasVoltage = false
    var hasBraggVectors = false
    var hasACOMMaterial = false
    var hasSupportedACOMMaterial = false
    var hasPhysicalACOMScale = false
}

/// One requirement of a task, with its live status and where the satisfying
/// control lives. `title` for an unmet item is byte-identical to the legacy
/// `prerequisites(for:)` string, so gating text cannot drift between surfaces.
struct TaskPrerequisite: Equatable, Identifiable, Sendable {
    /// Where the control that satisfies this prerequisite lives, so UI can
    /// link (navigate) or point (hint) without task-specific special cases.
    enum Resolution: Equatable, Sendable {
        /// Satisfied from the Prepare workspace (calibration checklist).
        case prepare
        /// Satisfied by running another analysis task first.
        case task(AnalysisMode)
        /// Satisfied by a control inside the current task's own tools panel;
        /// the string is a short pointer to it.
        case taskPanel(String)
    }

    /// Stable machine-readable key (used for accessibility identifiers).
    let id: String
    let title: String
    let isSatisfied: Bool
    let resolution: Resolution
}

enum ProductWorkflow {
    /// The full requirement list for a task — met and unmet — in the same
    /// order `prerequisites(for:)` has always reported the unmet subset.
    static func prerequisiteItems(
        for mode: AnalysisMode,
        readiness: ProductWorkflowReadiness
    ) -> [TaskPrerequisite] {
        switch mode {
        case .virtualDetector, .dpc, .disks:
            return []
        case .ptychography:
            return [
                TaskPrerequisite(
                    id: "originProbe", title: "Calibrate the diffraction origin",
                    isSatisfied: readiness.hasOriginProbe, resolution: .prepare
                ),
                TaskPrerequisite(
                    id: "rotation", title: "Calibrate the R–Q rotation",
                    isSatisfied: readiness.hasRotation, resolution: .prepare
                ),
                TaskPrerequisite(
                    id: "qScale", title: "Set the Q pixel scale",
                    isSatisfied: readiness.hasQScale, resolution: .prepare
                ),
                TaskPrerequisite(
                    id: "rScale", title: "Set the R pixel scale",
                    isSatisfied: readiness.hasRScale, resolution: .prepare
                ),
                TaskPrerequisite(
                    id: "voltage", title: "Set the accelerating voltage",
                    // S22c: the field moved to Prepare's Calibration section,
                    // so the checklist can navigate there like every other
                    // calibration prerequisite instead of describing a panel.
                    isSatisfied: readiness.hasVoltage, resolution: .prepare
                )
            ]
        case .strain:
            return [
                TaskPrerequisite(
                    id: "braggVectors", title: "Detect Bragg disks first",
                    isSatisfied: readiness.hasBraggVectors, resolution: .task(.disks)
                )
            ]
        case .acom:
            return [
                TaskPrerequisite(
                    id: "braggVectors", title: "Detect Bragg disks first",
                    isSatisfied: readiness.hasBraggVectors, resolution: .task(.disks)
                ),
                TaskPrerequisite(
                    id: "acomMaterial",
                    title: !readiness.hasACOMMaterial || readiness.hasSupportedACOMMaterial
                        ? "Choose an ACOM material model"
                        : "The selected ACOM material is not supported",
                    isSatisfied: readiness.hasACOMMaterial
                        && readiness.hasSupportedACOMMaterial,
                    resolution: .taskPanel(
                        "Select the material in the ACOM controls in the tools panel."
                    )
                )
            ]
        }
    }

    static func prerequisites(
        for mode: AnalysisMode,
        readiness: ProductWorkflowReadiness
    ) -> [String] {
        prerequisiteItems(for: mode, readiness: readiness)
            .filter { !$0.isSatisfied }
            .map(\.title)
    }

    /// Non-blocking scientific context. These messages explain the units or
    /// correction level of an operation that is valid to run now; they must
    /// never be presented as a contradictory disabled-state prerequisite.
    static func guidance(
        for mode: AnalysisMode,
        readiness: ProductWorkflowReadiness
    ) -> [String] {
        switch mode {
        case .virtualDetector, .disks, .ptychography:
            return []
        case .dpc:
            var missing: [String] = []
            if !readiness.hasOriginProbe { missing.append("origin") }
            if !readiness.hasRotation { missing.append("R–Q rotation") }
            if !readiness.hasQScale { missing.append("Q scale") }
            if !readiness.hasRScale { missing.append("R scale") }
            if !readiness.hasVoltage { missing.append("voltage") }
            guard !missing.isEmpty else { return [] }
            return ["Runs in qualitative units; add \(missing.joined(separator: ", ")) for quantitative DPC/iDPC."]
        case .strain:
            return readiness.hasOriginProbe
                ? []
                : ["Uses the current detector origin; calibrate it for corrected Bragg vectors."]
        case .acom:
            return readiness.hasPhysicalACOMScale
                ? []
                : ["Exploratory matching only: set physical Q sampling for quantitative orientation output."]
        }
    }

    /// One forward pointer for the current workspace — what a first-time user
    /// would sensibly do next, so the dependency chain is walkable without
    /// already knowing it.
    ///
    /// Deliberately silent in three situations, because a hint that repeats
    /// something already on screen is noise rather than guidance:
    /// - Prepare with calibration still incomplete — the readiness checklist
    ///   already names each missing field and its action.
    /// - Map before disks exist — the task group labels
    ///   (`TaskPrerequisiteFamily`) already say which tasks need Bragg vectors.
    /// - Results and Reconstruct — terminal for this purpose; nothing to point at.
    static func nextStepHint(
        for area: WorkspaceArea,
        readiness: ProductWorkflowReadiness,
        calibrationReady: Bool
    ) -> String? {
        switch area {
        case .prepare:
            return calibrationReady
                ? "Next: create an image, or detect Bragg disks in Strain & ACOM."
                : nil
        case .image:
            return readiness.hasBraggVectors
                ? nil
                : "Next: detect Bragg disks in Strain & ACOM to unlock its maps."
        case .map:
            return readiness.hasBraggVectors
                ? "Next: review and export in Results."
                : nil
        case .reconstruct, .results:
            return nil
        }
    }

    static func recommendedNextArea(
        calibrationReady: Bool,
        hasResult: Bool
    ) -> WorkspaceArea {
        if !calibrationReady { return .prepare }
        if !hasResult { return .image }
        return .results
    }
}
