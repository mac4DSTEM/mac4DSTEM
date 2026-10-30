//
//  LayoutPolicy+mac4DSTEM.swift
//  Role: what is mac4DSTEM's of the layout vocabulary. `LayoutPolicy` (the window's numbers), `ProcessAreaLayout`, `OperationMetricsFormat` (plain values)
//        and `displayByteString` are ShellLayout's (suite task 8, MacEMUI); here are the constants only 4D rooms use, the wrappers that keep
//        the call sites word for word (`AnalysisOperationMetrics` in, plain values out), and the two phase-model labels.
//

import ShellMetal
import SwiftUI
import ShellLayout
import DSTEMCore
import DSTEMSession

extension LayoutPolicy {
    /// The colour dot before a region's name in the EDS room's regions table (macTEM's value).
    static let regionSwatchSize: CGFloat = 9

    /// Science: one panel of the A / B / A−B comparison row.
    static let comparisonPaneMinimum: CGFloat = 120

    /// Science: the rotation-curve diagnostic plot.
    static let diagnosticPlotHeight: CGFloat = 90

    /// A colour key square, beside a legend row or a phase in a list. Square
    /// and small on purpose: it identifies a colour, it is not a preview, and
    /// growing it with the column would make the list read as a palette.
    static let legendSwatch: CGFloat = 12

    /// A ceiling, not a size: a thumbnail grows with its column and stops
    /// here, so a square preview in a wide inspector is bounded by the
    /// column, not by this.
    static let thumbnailMaximumHeight: CGFloat = 320

    /// Sheets: an ideal size and a floor, so a short display shrinks the
    /// sheet instead of pushing its footer off screen.
    static let configuratorSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 720, height: 500), CGSize(width: 880, height: 720))

    /// The Materials Project fetch sheet: three fields, a result card, a
    /// footer.
    static let materialsProjectSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 460, height: 380), CGSize(width: 520, height: 480))

    /// The Settings window (session S21, `ROADMAP.md` "Settings window,
    /// Xcode-style sidebar"): a `NavigationSplitView` — the old
    /// `materialsProjectSettingsWidth` (one `Form` section, width only)
    /// stopped fitting once a sidebar of five sections joined it, and is
    /// replaced rather than kept alongside it.
    static let settingsWindow: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 560, height: 380), CGSize(width: 660, height: 460))
}

extension OperationMetricsFormat {
    /// The virtual detector walks patterns; everything else walks scan positions. Keyed on the operation's own name, as it always was.
    static func throughputUnit(for operation: String?) -> String {
        operation == "Virtual detector" ? "patterns/s" : "positions/s"
    }

    static func throughput(_ rate: Double, for operation: String?) -> String {
        throughput(rate, unit: throughputUnit(for: operation))
    }

    /// The infobar's elapsed-and-ETA line of a run's metrics (throughput is not in it; see ShellLayout's `line`). `for operation:` is kept
    /// so the call sites and the tests that pin this wording read as before.
    static func line(_ metrics: AnalysisOperationMetrics, for operation: String?) -> String {
        _ = operation
        return line(elapsed: metrics.elapsed, eta: metrics.eta)
    }

    static func runLine(done: Int?, total: Int?, metrics: AnalysisOperationMetrics?, for operation: String?) -> String {
        runLine(done: done, total: total, elapsed: metrics?.elapsed, eta: metrics?.eta, rate: metrics?.unitsPerSecond,
                unit: throughputUnit(for: operation))
    }

    /// The glance with the engine in front: "Apple M3 · 1.4 GB · resident".
    static func glance(engine: String, residentMB: Double, residency isResident: Bool) -> String {
        "\(engine) · " + glance(residentMB: residentMB, residency: isResident)
    }
}

/// How an already-imported phase model is labelled in the ACOM picker and
/// the Phase Mapping "Add Phase" menu (`UI/MapSettings.swift`,
/// `UI/PhaseMappingSettings.swift`) — one spelling shared by both, cheap
/// (no computation, just the fields the model already carries): a Materials
/// Project fetch names its mp-id, a CIF import stays labelled the way it
/// always was.
func importedCrystalModelLabel(_ model: CrystalModel) -> String {
    switch model.source {
    case .materialsProject: return "Materials Project \(model.id) — \(model.displayName)"
    default: return "Imported: \(model.displayName)"
    }
}

/// The ACOM "Phase model" row's value text: the CURRENT selection's name,
/// tagged with where it came from — e.g. "Aluminium (mp-134)" for a
/// Materials Project fetch, "β″ (CIF)" for an imported CIF
/// (`UI/MapSettings.swift`). Distinct from `importedCrystalModelLabel`
/// above, which labels one row of a *list* (the switch-between-imports
/// menu); this labels the single active choice next to "Phase model". A
/// `.library`/`.customCubic` resolution — replay/tests only, never offered
/// in that row — prints its bare name, since neither carries an import
/// provenance to tag.
func acomPhaseModelValueText(_ model: CrystalModel) -> String {
    switch model.source {
    case .materialsProject: return "\(model.displayName) (\(model.id))"
    case .imported: return "\(model.displayName) (CIF)"
    case .builtIn, .custom: return model.displayName
    }
}

extension View {
    /// A preview image fills its column's width up to the one height cap.
    func thumbnailCapped() -> some View {
        frame(maxWidth: .infinity, maxHeight: LayoutPolicy.thumbnailMaximumHeight)
    }

    /// C4(a): a whole panel's parameter form disables as one unit while its
    /// task is running, instead of repeating `appState.isBusy` at each of its
    /// Sliders, Steppers, TextFields, Pickers and Toggles — none of which
    /// were disabled mid-run before this (§4 finding 1: "a map can land
    /// already stale against the controls on screen"). Applied once, to the
    /// panel body `MapSettings`/`ReconstructionSettings`/`PrepareSettings`/
    /// `ImagingSettings` return, not to each control.
    func disabledWhileRunning(_ appState: AppState) -> some View {
        disabled(appState.isBusy)
    }
}
