import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

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
        case .reconstruct: [.dpc, .ptychography, .singleslicePtychography]
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
        case .virtualDetector, .dpc, .ptychography, .singleslicePtychography: .phaseContrast
        }
    }

    /// The `SessionReplayRecord.Step.kind` this task's product is recorded
    /// under (C4(b)) — nil for the two kinds with no recorder (ptychography,
    /// parallax): a mode with no kind here is never judged stale, whatever
    /// its retained product.
    var replayKind: String? {
        switch self {
        case .virtualDetector: "virtual_detector"
        case .dpc: "dpc"
        case .disks: "disk_detection"
        case .strain: "strain"
        case .acom: "acom"
        case .ptychography, .singleslicePtychography: nil
        }
    }

    var workspaceArea: WorkspaceArea {
        switch self {
        case .virtualDetector: .image
        case .disks, .strain, .acom: .map
        // DPC sits with its prerequisite family (S22c): it shares the
        // voltage-only contract with parallax/ptychography, not the
        // zero-prerequisite contract of virtual imaging.
        case .dpc, .ptychography, .singleslicePtychography: .reconstruct
        }
    }

    var productTitle: String {
        switch self {
        case .virtualDetector: "Virtual imaging"
        case .dpc: "DPC & iDPC"
        case .disks: "Bragg disks"
        case .strain: "Strain"
        case .ptychography: "Parallax"
        case .singleslicePtychography: "Single-slice ptychography"
        case .acom: "Orientation"
        }
    }

    var productSubtitle: String {
        switch self {
        case .virtualDetector: "Form BF, ADF, HAADF, or custom detector images"
        case .dpc: "Map beam deflection and integrate projected phase"
        case .disks: "Detect reciprocal-lattice peaks across the scan"
        case .strain: "Measure lattice distortion from indexed Bragg peaks"
        case .ptychography: "Align bright-field images, fit aberrations, correct phase, section depth"
        case .singleslicePtychography: "Iterative object and probe reconstruction from the full datacube"
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
        case .singleslicePtychography: "circle.hexagongrid"
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
    /// v2.5 step 5a: the disk-detection settings carry no errors — the same
    /// predicate the tools panel used alone (`diskDetectionConfigurationIsValid`).
    var hasValidDiskDetectionSettings = true   // no errors is the default; the app feeds the real predicate
    var hasBraggVectors = false
    var hasACOMMaterial = false
    var hasSupportedACOMMaterial = false
    var hasPhysicalACOMScale = false
    /// C7 session 2: the Disk detection picker has the neural net selected.
    var wantsLearnedDetector = false
    /// Whether the bundled learned-detector asset is present in this build.
    /// Default true so a caller that never sets it (most readiness states)
    /// does not manufacture a missing-asset prerequisite out of nowhere.
    var hasLearnedDetectorAsset = true
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

/// What a task's retained product is worth right now — ONE verdict, shared by
/// the sidebar's task rows and the inspector's "Computed this session" rows.
/// Until 2026-09-05 the sidebar's green check ignored stale disk settings by
/// design while the inspector and the result pane both flagged them, and a
/// strain or orientation map stayed green after the disk settings that fed
/// it had changed (UI review 2026-09-04, finding f).
enum TaskProductState: Equatable, Sendable {
    /// Nothing retained for this task.
    case none
    /// Retained, and its inputs have not changed since.
    case current
    /// Retained, but computed from settings (this task's own, or an upstream
    /// task's — disk detection re-run invalidates strain/ACOM) that have
    /// since changed, or whose recorded step no longer exists at all.
    case stale(reason: String)

    var isProduced: Bool { self != .none }

    /// The reason text when stale, nil otherwise — lets a caller ask "is this
    /// stale, and if so why" without repeating the pattern match at each of
    /// the three surfaces that render it.
    var staleReason: String? {
        if case .stale(let reason) = self { reason } else { nil }
    }
}

/// C4(b): generalized staleness, beside `productState` below. `.stale`'s
/// `changedKeys` names exactly the keys that differ (sorted, for a stable
/// UI string) — never the keys `currentSignature` does not carry, so a
/// recorded step's own output-only keys (strain's `resolved_g*`) never
/// participate.
enum StalenessVerdict: Equatable, Sendable {
    /// No signature builder exists for this kind (ptychography, parallax),
    /// or the recorded step matches current settings on every key it names.
    case current
    /// The recorded step is missing keys current settings would record, or
    /// the recorded step itself is gone though the product survives it
    /// (an upstream re-run invalidated it).
    case stale(changedKeys: [String])
    /// No product and no recorded step: the question does not apply.
    case unknown
}

enum ProductWorkflow {
    /// Compare the recipe step a product was computed from against the
    /// signature current settings would record, restricted to the keys
    /// `currentSignature` names.
    static func stalenessVerdict(
        recordedStep: SessionReplayRecord.Step?,
        currentSignature: [String: String]?,
        hasProduct: Bool
    ) -> StalenessVerdict {
        guard let currentSignature else { return .current }
        guard let recordedStep else {
            return hasProduct ? .stale(changedKeys: []) : .unknown
        }
        let changedKeys = currentSignature.keys
            .filter { recordedStep.parameters[$0] != currentSignature[$0] }
            .sorted()
        return changedKeys.isEmpty ? .current : .stale(changedKeys: changedKeys)
    }

    /// The UI-facing sentence for a stale verdict — replaces the fixed
    /// `staleDiskSettingsHelp` string with one naming what changed. Empty
    /// `changedKeys` is the "recorded step is gone" case: there is nothing to
    /// name, the recipe moved on without this task.
    static func staleReason(changedKeys: [String]) -> String {
        changedKeys.isEmpty
            ? "Computed from a step that is no longer part of the recipe. Run this task again to bring it up to date."
            : "Computed with different \(changedKeys.joined(separator: ", ")). Run this task again to bring it up to date."
    }

    static func productState(
        for mode: AnalysisMode, hasProduct: Bool,
        recordedStep: SessionReplayRecord.Step?, currentSignature: [String: String]?
    ) -> TaskProductState {
        guard hasProduct else { return .none }
        switch stalenessVerdict(recordedStep: recordedStep, currentSignature: currentSignature, hasProduct: hasProduct) {
        case .current, .unknown: return .current
        case .stale(let changedKeys): return .stale(reason: staleReason(changedKeys: changedKeys))
        }
    }

    /// The recorded step this mode's product came from, by kind — nil if
    /// never recorded, or removed by a later analysis's own invalidation
    /// (disk re-detection invalidates strain/ACOM).
    static func recordedReplayStep(for mode: AnalysisMode, in steps: [SessionReplayRecord.Step]) -> SessionReplayRecord.Step? {
        guard let kind = mode.replayKind else { return nil }
        return steps.first { $0.kind == kind }
    }

    /// What current settings would record for this mode right now, mirroring
    /// exactly what each kind's own `recordReplayStep` call writes — nil for
    /// a kind with no recorder, or (ACOM) no resolved signature yet. Pure:
    /// AppState gathers the live ingredients (probe kernel, aperture, the
    /// resolved crystal model, …); this only decides which of them applies
    /// to `mode`, so it is testable with synthetic values, no `AppState`.
    static func currentReplaySignature(
        for mode: AnalysisMode,
        virtualDetectorShape: String, aperture: Aperture,
        dpcOriginReference: String,
        diskKernel: ProbeKernel?, diskParams: DiskDetectionParams, learnedDetectorParameters: [String: String],
        strainSignature: [String: String],
        acomSignature: [String: String]?
    ) -> [String: String]? {
        switch mode {
        case .virtualDetector:
            return Aperture.replayParameters(shape: virtualDetectorShape, aperture: aperture)
        case .dpc:
            return ["origin_reference": dpcOriginReference]
        case .disks:
            guard let diskKernel else { return nil }
            return diskParams.replayParameters(kernel: diskKernel)
                .merging(learnedDetectorParameters) { _, new in new }
        case .strain:
            return strainSignature
        case .acom:
            return acomSignature
        case .ptychography, .singleslicePtychography:
            return nil
        }
    }

    /// The full requirement list for a task — met and unmet — in the same
    /// order `prerequisites(for:)` has always reported the unmet subset.
    static func prerequisiteItems(
        for mode: AnalysisMode,
        readiness: ProductWorkflowReadiness
    ) -> [TaskPrerequisite] {
        switch mode {
        case .virtualDetector, .dpc:
            return []
        case .disks:
            // v2.5 step 5a: the tools panel's private gate joins the one list,
            // so the header's primary action and the panel button agree. A
            // row exists only while unmet: a satisfied "fix the settings" row
            // is noise, and the Strain & ACOM sidebar has no height to spare
            // (SidebarLayoutTests measures it). C7 session 2 adds a second,
            // independent row for the learned asset — both may appear.
            var items: [TaskPrerequisite] = []
            if !readiness.hasValidDiskDetectionSettings {
                items.append(TaskPrerequisite(
                    id: "diskSettings", title: "Fix the disk-detection settings",
                    isSatisfied: false,
                    resolution: .taskPanel(
                        "Resolve the errors listed in the Bragg disk controls in the tools panel."
                    )
                ))
            }
            if readiness.wantsLearnedDetector, !readiness.hasLearnedDetectorAsset {
                items.append(TaskPrerequisite(
                    id: "learnedAsset", title: "The neural-net model is not in this build",
                    isSatisfied: false,
                    resolution: .taskPanel("Choose Classical under Detector in the Disk detection section.")
                ))
            }
            return items
        case .ptychography, .singleslicePtychography:   // shared calibration list, separate state
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

    /// v2.5 step 5a: the ONE answer to "may this task run" — the primary
    /// action, the checklist and the replay executor all ask it.
    enum TaskReadiness: Equatable {
        case ready
        case unavailable(reason: String)

        var isReady: Bool { self == .ready }
    }

    static func readiness(
        for mode: AnalysisMode, readiness: ProductWorkflowReadiness
    ) -> TaskReadiness {
        let unmet = prerequisites(for: mode, readiness: readiness)
        return unmet.isEmpty ? .ready
            : .unavailable(reason: unmet.joined(separator: "; "))
    }

    /// C4(a): the ONE composition every run/compute control binds to — this
    /// task's readiness, plus "not already running", and nothing else. A
    /// panel button that checked its own fragment of a prerequisite (or
    /// skipped the check `PrimaryActionButton` already makes) is the exact
    /// drift `docs/consolidation-plan.md` §4 finding 2 found between the
    /// toolbar and "Reconstruct Object" / "Prepare Parallax Preview".
    static func mayRun(
        _ mode: AnalysisMode, readiness state: ProductWorkflowReadiness, isBusy: Bool
    ) -> Bool {
        !isBusy && readiness(for: mode, readiness: state).isReady
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
        case .virtualDetector, .ptychography, .singleslicePtychography:
            return []
        case .disks:
            return readiness.wantsLearnedDetector
                ? ["Candidates come from the neural net; the classical refinement still measures each one."]
                : []
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
