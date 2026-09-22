import SwiftUI
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

/// UI's whole number budget, in one file.
///
/// The rule UI is built on: **SwiftUI decides size, we decide bounds.** A
/// control is as wide as its content, a column is as wide as the user dragged
/// it, and spare space is margin. The only numbers here are the ones a
/// container genuinely cannot infer — a split column's range, a scientific
/// image's floor, and the width of a field holding six digits. Nothing in
/// UI may declare a `.frame(width:)`/`minWidth:` outside these constants;
/// the science panes are the one exception, and they take their floor from
/// `imagePaneMinimum` / `resultPaneMinimum` rather than spelling a number.
enum LayoutPolicy {
    static let datasetWindowMinimumSize = CGSize(width: 640, height: 640)
    static let datasetWindowIdealSize = CGSize(width: 1280, height: 800)

    /// The navigation column. Narrow on purpose: it holds five words and a
    /// task list, never a control.
    static let sidebarWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (190, 230, 320)

    /// The inspector: the workspace's settings and the dataset/product
    /// descriptor. Wider than the sidebar because forms live here.
    static let inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (280, 320, 460)

    /// Science: a diffraction or real-space pane below this stops being an
    /// image and becomes a smudge.
    static let imagePaneMinimum: CGFloat = 180
    static let sciencePaneDividerWidth: CGFloat = 1
    static let splitColumnDividerAllowance: CGFloat = 2

    /// Science: the Results pane shows one product at reading size.
    static let resultPaneMinimum = CGSize(width: 360, height: 300)

    /// Science: one panel of the A / B / A−B comparison row.
    static let comparisonPaneMinimum: CGFloat = 120

    /// Science: the rotation-curve diagnostic plot.
    static let diagnosticPlotHeight: CGFloat = 90

    /// The status bar's elapsed-and-ETA readout slot, reserved.
    ///
    /// Nothing inside a split's hosted content may repeatedly change its own
    /// minimum size — that loop crashed the app on a real dataset, 2026-09-04
    /// (`open-items.md`, the constraint-loop entry), and a ticking string is
    /// the easiest way to do it by accident. So the line is laid out at a
    /// width that never moves and truncates inside it.
    ///
    /// **116, measured 2026-09-12, not chosen.** The widest string
    /// `OperationMetricsFormat.line` can produce is "5999:59 · ETA 5999:59"
    /// at 113.59 pt in the strip's own 10 pt `caption2` monospaced-digit font
    /// — a hundred hours in both fields. It replaces a 190 pt reservation that
    /// was sized for a throughput token no longer printed, and which spent
    /// most of its width blank: during a DATASET LOAD `activeOperationMetrics`
    /// is nil outright, so 190 pt of the strip was guaranteed empty beside a
    /// loading column that has its own spinner.
    static let operationReadoutWidth: CGFloat = 116

    /// About six digits. A numeric field is never as wide as its row.
    static let numericFieldWidth: CGFloat = 72

    /// A colour key square, beside a legend row or a phase in a list. Square
    /// and small on purpose: it identifies a colour, it is not a preview, and
    /// growing it with the column would make the list read as a palette.
    static let legendSwatch: CGFloat = 12

    /// A ceiling, not a size: a thumbnail grows with its column and stops
    /// here, so a square preview in a wide inspector is bounded by the
    /// column, not by this.
    static let thumbnailMaximumHeight: CGFloat = 320

    // Bottom workspace + status strip + inspector vocabulary (ADR 034, owner
    // 2026-09-21): the inspector holds durable state, the bottom pane live
    // state. Every fixed point in that surface is named here.

    /// The header row of each process pane (Output · Lineage).
    static let bottomTabBarHeight: CGFloat = 26

    /// The permanent status strip — the infobar. Phase 1 (window-design.md
    /// §4–§6) made this row the centre column's own divider. 22 → 28 pt on
    /// 2026-09-22 evening ("wider, like Xcode's"), and 34 pt the same night
    /// when it took the Run tab's live numbers at 12-pt text with a Stop
    /// button (§9.2, §9.3).
    static let statusStripHeight: CGFloat = 34
    static let infobarHorizontalPadding: CGFloat = 10
    static let infobarItemSpacing: CGFloat = 12
    static let infobarProgressSpacing: CGFloat = 8

    /// The toolbar's centre display — Xcode's activity viewer: the file,
    /// the room and the scan size when idle; the running operation, its
    /// bar and its elapsed/ETA when busy (owner, 2026-09-22 evening, §8.1;
    /// the breadcrumb row it replaces is gone). A constant width, the
    /// `operationReadoutWidth` rule: a ticking string never reflows the
    /// toolbar (011).
    static let toolbarDisplayWidth: CGFloat = 380
    static let toolbarDisplaySpacing: CGFloat = 8

    /// The process area's share of the centre column the infobar's toggle
    /// (and ⌃⌘L) restores when nothing has ever been dragged — the owner's
    /// "default ideal" (window-design.md §6).
    static let processAreaIdealFraction: Double = 0.3

    /// The engine · memory · residency glance slot in the infobar — a
    /// constant width, like the metrics slot (011), so a changing figure
    /// never reflows the strip. Widened 2026-09-22 late for the engine's
    /// name ("Apple M3 Max · 1.4 GB · resident").
    static let statusGlanceWidth: CGFloat = 250

    /// The live run's readout in the infobar — done / total · rate · elapsed
    /// · ETA — at 12-pt monospaced digits, the `operationReadoutWidth` rule.
    /// **396, measured 2026-09-22, not chosen:** the widest line
    /// `OperationMetricsFormat.runLine` produces, "9,999,999 / 9,999,999 ·
    /// 9999.9 positions/s · 5999:59 · ETA 5999:59", is 390.5 pt at the
    /// callout font's monospaced digits; `StatusBarMetricsTests` sweeps it.
    static let runReadoutWidth: CGFloat = 396

    /// A card's own inner padding beyond `GroupBox`'s (the Prepare steps).
    static let cardPadding: CGFloat = 4

    /// The Run tab's label column.
    static let runMonitorLabelWidth: CGFloat = 110

    /// The inspector's utility-pane label column and its rhythm.
    static let inspectorLabelWidth: CGFloat = 96
    static let inspectorRowSpacing: CGFloat = 6
    static let inspectorSectionSpacing: CGFloat = 12

    /// The inspector's header row — the Settings · Info segmented control in
    /// a row of its own (window-design.md §6.3, 2026-09-22).
    static let inspectorHeaderHorizontalPadding: CGFloat = 12
    static let inspectorHeaderVerticalPadding: CGFloat = 8

    /// The editable value field beside an `AdjustmentSlider`.
    static let adjustmentValueWidth: CGFloat = 64

    /// A control popover (the colorbar chip).
    static let popoverWidth: CGFloat = 280

    /// Readable line length for prose on an otherwise empty workspace.
    static let readableWidth: CGFloat = 560

    /// Sheets: an ideal size and a floor, so a short display shrinks the
    /// sheet instead of pushing its footer off screen.
    static let configuratorSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 720, height: 500), CGSize(width: 880, height: 720))
    static let exportSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 540, height: 460), CGSize(width: 600, height: 700))
    /// The Materials Project fetch sheet: three fields, a result card, a
    /// footer — shorter than `exportSheet`, which carries a live output
    /// preview besides its own footer.
    static let materialsProjectSheet: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 460, height: 380), CGSize(width: 520, height: 480))
    /// The Settings window (session S21, `ROADMAP.md` "Settings window,
    /// Xcode-style sidebar"): a `NavigationSplitView` — the old
    /// `materialsProjectSettingsWidth` (one `Form` section, width only)
    /// stopped fitting once a sidebar of five sections joined it, and is
    /// replaced rather than kept alongside it.
    static let settingsWindow: (min: CGSize, ideal: CGSize) =
        (CGSize(width: 560, height: 380), CGSize(width: 660, height: 460))

    /// An inline progress bar beside its status text.
    static let inlineProgressWidth: CGFloat = 110

    // `progressPercentWidth` (36 pt) was here and is DELETED, 2026-09-12 —
    // with the label it reserved. A numeric percentage beside a progress bar
    // is the same fact drawn twice: `ProgressView` has no percentage API,
    // `NSProgressIndicator` has none, the HIG never asks for one, and this
    // app's own loading card a screen away already draws a determinate bar
    // with no numeral. The number now reaches VoiceOver on the bar's
    // `.accessibilityValue`, where it is useful and cannot wrap.
    // `operationMetricsWidth` (190 pt) is replaced by `operationReadoutWidth`
    // (116) above, re-measured after throughput left the line.

    /// The grabbable width of a thin divider, centred on the drawn line. A
    /// 1 pt zone put the drag on the focus ring (owner finding (c),
    /// 2026-09-03); this is the same 9 pt the AppKit columns use.
    static let dividerGrabWidth: CGFloat = 9

    /// Largest box with `aspect` (width / height) that fits inside `size`.
    /// Letterboxing is the pane's job everywhere an image is drawn: a
    /// scientific image that is stretched to its container is a wrong image.
    static func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        return size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
    }
}

/// Width budget for the native side columns and two scientific images
/// (window-design.md §1: "below that the side panels collapse before a pane
/// ever shrinks past it"). SwiftUI performs the collapse; this policy only
/// decides when to request it, as a function of the WINDOW width alone — a
/// decision read off the centre column's own width would feed back into
/// itself (collapsing widens the centre, which then fits, which reopens).
///
/// **Budgeted at the IDEAL column widths, not the maxima** (2026-09-22, the
/// first on-screen look at phase 1). Summing the maxima demanded 1143 pt
/// with both panels open, so an 1100-pt window on a 13-inch display lost
/// its inspector and greyed the toggle; the ideal widths — the ones the app
/// itself asks for — need 915, and the panes still sit at their floor
/// there. A user who drags a column wider than its ideal is asking for a
/// wider window; the budget is a safety net for the layout the app sets,
/// not an enforcement against every drag.
///
/// The decision is a request, not a mutation: `WorkspaceNavigation` keeps
/// the user's intent (`showInspectorPane`) and derives what is on screen
/// (`inspectorIsVisible`) from intent AND this budget, so a panel closed by
/// a narrow window comes back on its own when the window widens.
enum WindowAnatomyPolicy {
    static var scienceMinimum: CGFloat {
        LayoutPolicy.imagePaneMinimum * 2 + LayoutPolicy.sciencePaneDividerWidth
    }

    /// The inspector collapses first: it is the wider column, and navigation
    /// is what a narrow window still needs.
    static func collapseInspector(at width: CGFloat, navigatorVisible: Bool) -> Bool {
        let navigator = navigatorVisible ? LayoutPolicy.sidebarWidth.ideal + LayoutPolicy.splitColumnDividerAllowance : 0
        return width < navigator + LayoutPolicy.inspectorWidth.ideal
            + LayoutPolicy.splitColumnDividerAllowance + scienceMinimum
    }

    /// Below the dataset window's own minimum width today (593 < 640), so
    /// this never fires; kept so the rule is stated in one place should the
    /// minimum ever drop.
    static func collapseNavigator(at width: CGFloat) -> Bool {
        width < LayoutPolicy.sidebarWidth.ideal
            + LayoutPolicy.splitColumnDividerAllowance + scienceMinimum
    }
}

/// Pure layout math for the centre column's process area (window-design.md
/// §4–§6, decided 2026-09-22, phase 1): the infobar is the column's own
/// divider, draggable anywhere along its whole width from the column's
/// bottom edge (process area hidden) to its top edge (canvas hidden) —
/// Xcode's two extremes. Free of `@State`/`@Bindable` so it is tested
/// directly: `WorkspaceView` reads `heights` every layout pass, the
/// infobar's drag gesture reads `fraction(afterDrag:)`, and its toggle
/// button reads `toggled(from:last:)`. `WorkspaceNavigation.showLogPane`'s
/// own setter reimplements the same rule for the ⌃⌘L menu item — see its
/// doc comment for why that one setter cannot call into UI/.
enum ProcessAreaLayout {
    /// `fraction` is the process area's share of `available` — the centre
    /// column's height with the canvas header and the infobar already
    /// removed. 0 hides the process area entirely; 1 hides the canvas
    /// entirely.
    static func heights(fraction: Double, available: CGFloat) -> (canvas: CGFloat, process: CGFloat) {
        let clampedFraction = min(max(fraction, 0), 1)
        let usable = max(available, 0)
        let process = usable * CGFloat(clampedFraction)
        return (usable - process, process)
    }

    /// The infobar's own toggle button: open → always shuts (0); shut →
    /// restores `last` (the fraction remembered from before it was last
    /// shut), or the default ideal when nothing has ever been dragged.
    static func toggled(from fraction: Double, last: Double) -> Double {
        fraction > 0 ? 0 : (last > 0 ? last : LayoutPolicy.processAreaIdealFraction)
    }

    /// A drag on the infobar. SwiftUI's `translation` grows downward, and
    /// the process area sits BELOW the bar, so dragging down shrinks it —
    /// the delta is subtracted from the fraction the drag started at.
    static func fraction(afterDrag translation: CGFloat, available: CGFloat, from start: Double) -> Double {
        guard available > 0 else { return start }
        let delta = Double(translation) / Double(available)
        return min(max(start - delta, 0), 1)
    }
}

/// A numeric text field with an optional unit, for the trailing side of a
/// `LabeledContent` row — the one place a UI form control takes a width.
struct NumericField<Value, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    @Binding var value: Value
    let format: Format
    var unit: String?

    init(
        _ title: String,
        value: Binding<Value>,
        format: Format,
        unit: String? = nil
    ) {
        self.title = title
        self._value = value
        self.format = format
        self.unit = unit
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, value: $value, format: format)
                // Labelled by the row it sits in; the title stays for
                // VoiceOver.
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: LayoutPolicy.numericFieldWidth)
            if let unit {
                // The unit is part of the number's meaning: it never
                // truncates and never wraps.
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityLabel(title)
    }
}

/// How a running operation's numbers are worded, in one place.
///
/// The status bar and the inspector's Performance rows both print elapsed,
/// throughput and ETA (owner, 2026-09-04: the numbers belong beside the
/// progress bar, not only one tab away). Two copies of "53 s" versus "0:53"
/// is exactly the drift this session spent its time removing, so both read
/// from here.
enum OperationMetricsFormat {
    /// Seconds as "53 s" below a minute, "2:35" above it.
    ///
    /// Above an hour it keeps counting minutes rather than growing an hours
    /// field: "119:59", not "1:59:59". The slot beside it is a constant, and a
    /// format that grows a field is a format whose width is not bounded by the
    /// sweep that measures it.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 60
            ? String(format: "%d:%02d", total / 60, total % 60)
            : "\(total) s"
    }

    /// The virtual detector walks patterns; everything else walks scan
    /// positions. Keyed on the operation's own name, as it always was.
    static func throughputUnit(for operation: String?) -> String {
        operation == "Virtual detector" ? "patterns/s" : "positions/s"
    }

    static func throughput(_ rate: Double, for operation: String?) -> String {
        String(format: "%.1f %@", rate, throughputUnit(for: operation))
    }

    /// The Run tab's idle "Last run" line: the run's name and how long it
    /// took — worded differently for a run that was stopped than one that
    /// finished, so Cancel never reads as if the run completed. Takes a
    /// plain `Bool` rather than `OperationCenter.Outcome` so this formatter
    /// stays free of the Session-module type; the call site translates.
    static func lastRun(_ name: String, elapsed: TimeInterval, cancelled: Bool) -> String {
        let durationText = duration(elapsed)
        return cancelled ? "\(name) — cancelled after \(durationText)" : "\(name) — \(durationText)"
    }

    /// The status bar's single line: elapsed, and an ETA once the run can
    /// estimate one. Elapsed is always real; an ETA it cannot yet estimate is
    /// absent rather than invented, because an invented ETA is a number the
    /// user will plan around.
    ///
    /// **THROUGHPUT IS NOT HERE, from 2026-09-12, and that narrows a decision
    /// the owner made on 2026-09-04** ("the numbers belong beside the progress
    /// bar, not only one tab away", `decisions.md`). Three things forced it and
    /// they are stated rather than assumed. Apple's own chrome carries no
    /// units-per-second anywhere — that is Activity Monitor's register, and the
    /// HIG asks only for "a description that provides additional context".
    /// It is the longest token in the line by far: the widest string this
    /// formatter could produce WITH it measured 180.9 pt, against 113.6
    /// without, so it alone was most of a 190 pt reservation in a strip the
    /// owner has now called cluttered. And it is derivable at a glance from
    /// the bar and the elapsed time beside it, which the two numbers kept here
    /// are not derivable from anything.
    ///
    /// `for operation:` is KEPT although this function no longer reads it.
    /// `throughputUnit(for:)` is still the inspector's, and the three tests
    /// that pin this wording pin a surface the status bar actually draws;
    /// dropping the parameter would repoint them at a formatter only the
    /// inspector calls.
    static func line(_ metrics: AnalysisOperationMetrics, for operation: String?) -> String {
        _ = operation
        var parts = [duration(metrics.elapsed)]
        if let eta = metrics.eta {
            parts.append("ETA " + duration(eta))
        }
        return parts.joined(separator: " · ")
    }

    /// The infobar's live run, one line (owner, 2026-09-22 late: the Run
    /// tab's numbers belong in the bar): done / total, the rate, then
    /// elapsed and ETA from `line`. A part that is not known yet is absent,
    /// never invented.
    static func runLine(done: Int?, total: Int?, metrics: AnalysisOperationMetrics?, for operation: String?) -> String {
        var parts: [String] = []
        if let done, let total {
            parts.append("\(SystemMonitor.count(done)) / \(SystemMonitor.count(total))")
        }
        if let rate = metrics?.unitsPerSecond {
            parts.append(throughput(rate, for: operation))
        }
        if let metrics {
            parts.append(line(metrics, for: operation))
        }
        return parts.joined(separator: " · ")
    }

    /// The glance with the engine in front: "Apple M3 · 1.4 GB · resident".
    static func glance(engine: String, residentMB: Double, residency isResident: Bool) -> String {
        "\(engine) · " + glance(residentMB: residentMB, residency: isResident)
    }

    /// The status strip's memory/residency glance (ADR 034): app resident
    /// memory beside whether the open cube is held in memory or streamed —
    /// "1.4 GB · resident", "612 MB · streaming". One style throughout UI
    /// (`displayByteString`/`SystemMonitor.byteString` are 1024-based too),
    /// but this slot is fixed-width and ticks every 2 s, so it takes the raw
    /// MB figure rather than a pre-formatted string, the same shape as
    /// `duration`/`throughput` above.
    static func glance(residentMB: Double, residency isResident: Bool) -> String {
        let value: String
        // GB before MB, TB before GB: `>=`, not `>`, at each boundary — a
        // dataset that lands EXACTLY on 1 GB or 1 TB reads in the coarser
        // unit rather than as "1024.0 MB"/"1024.0 GB". The TB branch exists
        // because the GB-only formatter used to read a two-terabyte cube as
        // "2048.0 GB" — a number no reader parses at a glance the way "2.0
        // TB" does.
        if residentMB >= 1024 * 1024 {
            value = String(format: "%.1f TB", residentMB / (1024 * 1024))
        } else if residentMB >= 1024 {
            value = String(format: "%.1f GB", residentMB / 1024)
        } else {
            value = String(format: "%.0f MB", residentMB)
        }
        return "\(value) · \(isResident ? "resident" : "streaming")"
    }
}

/// Every byte quantity UI prints, through one formatter.
///
/// UI had three (2026-09-04 review): two hand-rolled 1024-based ones that
/// disagreed on precision, and `ByteCountFormatter(.file)` at 1000. The same
/// float32 cube read 4.00 GB in the inspector and 4.29 GB in the export sheet
/// the user opens to decide whether to write it. Apple's own split — `.memory`
/// for RAM, `.file` for disk, both labelled "GB" — is defensible in isolation
/// and wrong here, because these numbers are read against each other across
/// surfaces. One style, and it is Finder's, because Finder is the reference
/// the user already has on screen.
func displayByteString(_ bytes: Int) -> String {
    bytes.formatted(.byteCount(style: .file))
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
    /// panel body `MapSettings`/`PhaseSettings`/`PrepareSettings`/
    /// `ImagingSettings` return, not to each control.
    func disabledWhileRunning(_ appState: AppState) -> some View {
        disabled(appState.isBusy)
    }
}
