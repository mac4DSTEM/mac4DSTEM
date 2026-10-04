import SwiftUI

/// The inspector's row vocabulary — one kit for every room (owner rule): a
/// layout fix belongs here, never hand-rolled in a room file.
///
/// Built to Apple's own inspector guidance: a `Form` "renders as a vertical
/// stack" on macOS, not boxed cards, so sections are flat — a title with a
/// LEADING disclosure triangle (HIG, Disclosure controls), rows, a hairline;
/// status colour lives on symbols, text stays in the system label colours
/// (HIG, Labels/Color); at most one prominent button per view (HIG, Buttons)
/// and that one is the room's verb in the toolbar, so every inspector button
/// is a plain bordered push button; buttons in a set share one width
/// (`.buttonSizing(.flexible)`); controls `.regular`. One alignment rule, the
/// owner's (Pixelmator's): label leading, control or value at the trailing
/// edge. Presentation only — no `AppState`, `OperationCenter` or `Session`
/// reference here, and no number that isn't a `LayoutPolicy` constant or one
/// of this file's own, explained constants.

/// The room or tab an `InspectorSection` renders in.
///
/// A section remembers its own expansion by title alone unless scoped —
/// which left unrelated sections that happen to share a title ("Dataset" in
/// the Info tab and "Dataset" among the Settings tab's own actions, "Result"
/// in two rooms) collapsing together, since they wrote the same
/// `@SceneStorage` key. `WorkspaceInspector` sets this once per tab ("info"),
/// and `WorkspaceSettings` again, more specifically, per task's room file
/// within the Settings tab ("settings.map", "settings.phase", …), so the key
/// each section remembers its state under is scoped to where it actually
/// lives. Default "" so a section built outside that scaffolding (a preview,
/// a test) still gets a stable, if unscoped, key.
private struct InspectorScopeKey: EnvironmentKey {
    static let defaultValue: String = ""
}

/// Vertical rhythm this file's section chrome owns.
private enum InspectorSectionMetrics {
    /// Above and below a section's content, inside its hairlines.
    static let sectionPadding: CGFloat = 8
}

extension EnvironmentValues {
    var inspectorScope: String {
        get { self[InspectorScopeKey.self] }
        set { self[InspectorScopeKey.self] = newValue }
    }
}

/// A collapsible group of inspector rows — the pane's basic unit.
///
/// The whole title row is the disclosure control (the owner: "disclosure on
/// the label, not the chevron"), with the triangle at the leading edge where
/// macOS puts it. A hairline closes each section. When the caller passes no
/// `expanded` binding, the section remembers its own state, scoped by
/// `inspectorScope` and title, via `@SceneStorage`, defaulting to expanded.
///
/// `icon` and `emphasized` serve the one header that needs more: a parallax
/// stage row with an always-visible status glyph, bolder while it is the
/// active step.
struct InspectorSection<Content: View>: View {
    private let title: String
    private let icon: Image?
    private let emphasized: Bool
    private let externalExpanded: Binding<Bool>?
    private let content: Content
    @Environment(\.inspectorScope) private var scope

    init(
        _ title: String,
        icon: Image? = nil,
        emphasized: Bool = false,
        expanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.emphasized = emphasized
        self.externalExpanded = expanded
        self.content = content()
    }

    /// The `@SceneStorage` key a title-only section (no `expanded:` binding)
    /// remembers its own state under. A `static func`, not inline in `body`,
    /// so the scoping rule is testable without hosting a view.
    static func sceneStorageKey(scope: String, title: String) -> String {
        "inspector.section.\(scope).\(title)"
    }

    var body: some View {
        if let externalExpanded {
            InspectorSectionBody(title: title, icon: icon, emphasized: emphasized,
                                  isExpanded: externalExpanded, content: content)
        } else {
            InspectorSectionRemembering(
                key: Self.sceneStorageKey(scope: scope, title: title),
                title: title, icon: icon, emphasized: emphasized, content: content)
        }
    }
}

/// Owns the `@SceneStorage` for a section with no explicit `expanded:`
/// binding.
///
/// Split out from `InspectorSection` because the storage key needs
/// `inspectorScope`, an `@Environment` value — not yet readable inside
/// `InspectorSection`'s own `init`, before it is attached to the view
/// hierarchy, so it is resolved in `InspectorSection.body` instead (where
/// `@Environment` reads are ordinary) and handed to this view as a plain
/// `init` parameter, where `@SceneStorage` can use it immediately.
private struct InspectorSectionRemembering<Content: View>: View {
    private let title: String
    private let icon: Image?
    private let emphasized: Bool
    @SceneStorage private var isExpanded: Bool
    private let content: Content

    init(key: String, title: String, icon: Image?, emphasized: Bool, content: Content) {
        self.title = title
        self.icon = icon
        self.emphasized = emphasized
        self._isExpanded = SceneStorage(wrappedValue: true, key)
        self.content = content
    }

    var body: some View {
        InspectorSectionBody(title: title, icon: icon, emphasized: emphasized,
                              isExpanded: $isExpanded, content: content)
    }
}

/// The section's chrome, shared by the remembered-state and explicit-binding
/// paths: a title row that is itself the disclosure control, the rows, a
/// hairline. Collapsed, only the title row and the hairline remain.
private struct InspectorSectionBody<Content: View>: View {
    let title: String
    let icon: Image?
    let emphasized: Bool
    let isExpanded: Binding<Bool>
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                    content
                }
                .padding(.top, InspectorSectionMetrics.sectionPadding)
            }
        }
        .padding(.vertical, InspectorSectionMetrics.sectionPadding)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .accessibilityHidden(true)
                if let icon {
                    icon
                        .foregroundStyle(emphasized ? .primary : .secondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline.weight(emphasized ? .bold : .semibold))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
    }
}

/// A non-collapsible run of rows — no title, no disclosure, no
/// `@SceneStorage` — for content that never had a name of its own (a room's
/// mode switch, a matcher's run button). Same rhythm and hairline as
/// `InspectorSection`.
struct InspectorGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
            content
        }
        .padding(.vertical, InspectorSectionMetrics.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// One labelled control: the label at the leading edge in the primary label
/// colour, the control at the trailing edge — the owner's one alignment rule
/// (Pixelmator: "label left, control right, value at the edge"). The label
/// is one line at its own width, never compressed; the control takes what
/// is left and adapts. No fixed label column. Hiding a control's own label is the caller's
/// job. `emphasized` sets the label semibold (a ranked list's top row).
struct InspectorRow<Content: View>: View {
    private let label: String
    private let emphasized: Bool
    private let content: Content

    init(_ label: String, emphasized: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.emphasized = emphasized
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // One line, never compressed: with the control given priority
            // the label wrapped to one character per line ("Pr / es / et")
            // when this shared a fixed width with the control. Labels are
            // short by design; the control adapts instead (`ViewThatFits`,
            // compressing pickers).
            Text(label)
                .fontWeight(emphasized ? .semibold : .regular)
                .fixedSize()
            Spacer(minLength: 0)
            content
        }
        .controlSize(.regular)
    }
}

/// `InspectorRow`'s anatomy for a label that is DATA — a phase's name from a
/// CIF or a Materials Project entry, of any length. `InspectorRow`'s label is
/// fixed-size, right for a literal word, but a data-derived one has no bound
/// and its width would set the inspector's minimum: a 53-character phase name
/// measured 395 pt against the 248 a 280-pt inspector gives its content (Gate D
/// 2026-09-29, `InspectorWidthBudgetTests`). Here the label truncates in the
/// middle, one line, and the full text is the row's help.
struct InspectorDataRow<Content: View>: View {
    private let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            content
        }
        .controlSize(.regular)
        .help(label)
    }
}

/// A read-only fact: label leading, the value trailing in the secondary
/// label colour, selectable (a value the reader may paste into a notebook)
/// and in monospaced digits so a column of these keeps its numerals aligned.
/// `mono` sets the whole value monospaced — a path or a shape string.
///
/// On one line when label and value fit side by side; otherwise the label
/// takes its own line and the value wraps, trailing-aligned, beneath it (as
/// Xcode's inspectors do). Info labels are often DATA — a provenance key such
/// as "relative_reference_minimum_radius_px" — and a fixed-size row raised
/// the inspector's minimum past its column and aborted the app at a 915-pt
/// window (Gate D 2026-09-29, `InspectorWidthBudgetTests`). The stacked form
/// keeps the row's minimum width at a few characters WHATEVER the value
/// says, so a live value (the scan position) can never move the inspector's
/// minimum — the constraint-loop shape. Squeezing both onto one line failed
/// on screen twice (2026-09-30): a long key left "3.92" one character wide,
/// and an even split cut short values in half.
struct InspectorValueRow: View {
    private let label: String
    private let value: String
    private let mono: Bool

    init(_ label: String, _ value: String, mono: Bool = false) {
        self.label = label
        self.value = value
        self.mono = mono
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .fixedSize()
                Spacer(minLength: 0)
                // Ahead of the spacer, or the row splits evenly and a value
                // that fits is cut in half (2026-09-30 drive).
                valueText
                    .layoutPriority(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(label)
                valueText
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var valueText: some View {
        // Mono rows carry provenance: a 17-digit decimal prints rounded, the
        // exact text on hover.
        Text(mono ? ProvenanceValueText.display(value) : value)
            .help(mono ? value : "")
            // Identifiers and provenance values stay on one line (middle
            // truncation keeps both ends); the full text is on hover.
            .lineLimit(mono ? 1 : nil)
            .truncationMode(.middle)
            .monospacedDigit()
            .fontDesign(mono ? .monospaced : .default)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
    }
}

/// The adjustment row: the label and an editable value (with an optional
/// unit) on one line, a filling `Slider` below.
///
/// The `TextField` above the slider is `LayoutPolicy.adjustmentValueWidth`
/// wide and shares the slider's binding; a typed value commits on Enter
/// (`.onSubmit`) or on focus loss, and either way is clamped into `range`
/// before it reaches `value` — never while the field is still being typed
/// in, so a value mid-edit (e.g. a bare "-" before more digits follow) is
/// not fought over. The clamp itself is `AdjustmentSlider.clamp(_:to:)`, a
/// pure static function so it can be unit-tested without hosting a view.
/// Double-clicking the label resets `value` to `defaultValue` (also
/// clamped) when one was given; with no `defaultValue` the label is inert.
struct AdjustmentSlider: View {
    private let label: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let format: FloatingPointFormatStyle<Double>
    private let unit: String?
    private let defaultValue: Double?


    init(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2)),
        unit: String? = nil,
        defaultValue: Double? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.unit = unit
        self.defaultValue = defaultValue
    }

    var body: some View {
        // Two lines, as Photos' Adjust panel does: label left and the
        // value at the edge (the one alignment rule), the slider below at
        // full width. A slider beside a fixed label column squeezed to
        // ~40 pt in a 280-pt popover.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                labelView
                Spacer(minLength: 0)
                NumberEntryField(title: label, value: value, format: format) {
                    if let typed = $0 { value = Self.clamp(typed, to: range) }
                }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: LayoutPolicy.adjustmentValueWidth)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            slider
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(Text(value, format: format))
    }

    @ViewBuilder
    private var labelView: some View {
        let text = Text(label)
            .fixedSize()
            .onTapGesture(count: 2, perform: resetToDefault)
        if defaultValue != nil {
            text.help("Double-click to reset")
        } else {
            text
        }
    }

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: $value, in: range, step: step)
        } else {
            Slider(value: $value, in: range)
        }
    }

    private func resetToDefault() {
        guard let defaultValue else { return }
        value = Self.clamp(defaultValue, to: range)
    }

    /// Pure on purpose: the only place a typed value can land outside
    /// `range` (the slider itself cannot), so it is the one piece of this
    /// view worth testing without hosting it.
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// A one-line secondary caption under a row — the vocabulary's replacement
/// for a bare `Text(...).font(.caption).foregroundStyle(.secondary)`. Wraps
/// rather than truncating, since it is explanatory prose, not a value.
struct InspectorNote: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A section's buttons: one row at one shared width, spanning the section
/// (`.buttonSizing(.flexible)`, macOS 26+) — HIG, Buttons: "Use style — not
/// size" to distinguish a choice, so buttons in a set match. When the row
/// cannot hold them side by side it stacks them, still full width. A lone
/// button spans the section too, never parked at one edge.
struct InspectorActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LayoutPolicy.inspectorRowSpacing) {
                content
            }
            VStack(spacing: LayoutPolicy.inspectorRowSpacing) {
                content
            }
        }
        .buttonSizing(.flexible)
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
    }
}

/// A section action that never truncates: the full `Label` when the button
/// has room, the symbol alone when it does not, with the title kept on
/// `.help` and as the accessibility label. `ViewThatFits` is the durable
/// pattern for this, not a stopgap. A plain bordered push button — the
/// room's one prominent action is its toolbar verb (HIG, Buttons).
struct InspectorAdaptiveButton: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let role: ButtonRole?
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        help: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: systemImage)
                Image(systemName: systemImage)
            }
        }
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// The adaptive button's menu twin: a pull-down whose label is the full
/// `Label` when the row has room and the symbol alone when it does not, with
/// the title kept on `.help` and as the accessibility label — the same
/// `ViewThatFits` rule as `InspectorAdaptiveButton`, so a menu and a button
/// in one `InspectorActionRow` size alike. The caller adds its own
/// accessibility identifier.
struct InspectorAdaptiveMenu<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let content: Content

    init(
        _ title: String,
        systemImage: String,
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: systemImage)
                Image(systemName: systemImage)
            }
        }
        .help(help ?? title)
        .accessibilityLabel(title)
    }
}

/// A warning note: the caption-size orange `Label` every room hand-rolled
/// (`Label(text, systemImage:).font(.caption).foregroundStyle(.orange)`),
/// named once. Wraps like any `Label`; the symbol defaults to the filled
/// triangle and a note whose meaning is not "beware" (a refusal, a stale
/// result) passes its own.
struct InspectorWarning: View {
    private let text: String
    private let systemImage: String

    init(_ text: String, systemImage: String = "exclamationmark.triangle.fill") {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

/// A status line: a tinted status symbol, the title in the primary label
/// colour with its detail under it in secondary, and the short status word
/// at the trailing edge, `.fixedSize()` so it never wraps. Colour lives on
/// the symbol only (HIG, Color: never the sole carrier of meaning; Labels:
/// system label colours for text) — the word says the same thing in text.
struct InspectorStatusRow: View {
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let detail: String?
    private let status: String

    /// The status symbol's slot and the gap after it. `childIndent` is where
    /// the title text starts: a row's own controls (a manual value, a
    /// re-measure button) indent to it, so they read as belonging to that
    /// row rather than to the section.
    static let symbolWidth: CGFloat = 16
    static let symbolSpacing: CGFloat = 8
    static var childIndent: CGFloat { symbolWidth + symbolSpacing }

    init(title: String, systemImage: String, tint: Color = .secondary, detail: String? = nil, status: String) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.detail = detail
        self.status = status
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.symbolSpacing) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: Self.symbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text(status)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Number entry

/// How every numeric field reads and shows a number (Gate D, 2026-09-30,
/// Session queue S3). The system's lenient parse, in a region whose decimal
/// separator is a comma, read a typed period as grouping: `0.0275` became
/// 275 and `0.2` became 0 — silently, in the calibration fields. So:
/// - the value is shown without grouping (`1600`, never `1.600`), so a shown
///   number committed unchanged can never be re-read as another;
/// - in a decimal field one `.` or `,` typed is the decimal point, whichever
///   the region uses (declared trade-off: a US `1,600` is 1.6 here);
/// - anything else is grouping only in valid groups — 1–3 digits, then
///   exactly 3 (`1.234,5`, `1,234.5`, `1.000.000`); an integer field takes
///   separators only as grouping (`1.600` is 1600);
/// - every other placement is refused — the field keeps its value — so a
///   typo like `0.0.275` or `300.5.` can never become 275 or 3005.
nonisolated struct DecimalEntryFormat<Inner: ParseableFormatStyle>: ParseableFormatStyle
where Inner.FormatOutput == String {
    var inner: Inner
    var locale: Locale

    init(_ inner: Inner, locale: Locale = .autoupdatingCurrent) {
        self.inner = inner
        self.locale = locale
    }

    func format(_ value: Inner.FormatInput) -> String {
        Self.ungrouped(inner.format(value), locale: locale)
    }

    var parseStrategy: Strategy { Strategy(inner: inner, locale: locale) }

    struct Strategy: ParseStrategy {
        var inner: Inner
        var locale: Locale

        func parse(_ value: String) throws -> Inner.FormatInput {
            let integer = Inner.FormatInput.self is any BinaryInteger.Type
            return try inner.parseStrategy.parse(
                DecimalEntryFormat.normalized(value, locale: locale, integer: integer))
        }
    }

    struct Refused: Error {}

    static func ungrouped(_ text: String, locale: Locale) -> String {
        guard let grouping = locale.groupingSeparator, !grouping.isEmpty else { return text }
        return text.replacingOccurrences(of: grouping, with: "")
    }

    /// The typed text rewritten in `locale`'s own convention, ungrouped, or
    /// `Refused` when its separators have no one reading.
    static func normalized(_ raw: String, locale: Locale, integer: Bool = false) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let decimal = locale.decimalSeparator ?? "."
        let separators = text.filter { $0 == "." || $0 == "," }
        guard let last = separators.last else { return text }
        if !integer && separators.count == 1 {
            return text.replacingOccurrences(of: String(last), with: decimal)
        }
        // Several separators, or any in an integer: all but a decimal point
        // must be grouping, and grouping must be well formed.
        let point: Character? = integer || Set(separators).count == 1 ? nil : last
        let grouping: Character = point.map { $0 == "." ? "," : "." } ?? last
        let whole = point.map { p in String(text[..<text.lastIndex(of: p)!]) } ?? text
        guard !whole.contains(where: { $0 == point }) else { throw Refused() }
        let groups = whole.drop { $0 == "-" || $0 == "+" || $0 == "\u{2212}" }
            .split(separator: grouping, omittingEmptySubsequences: false)
        guard groups.count > 1, (1...3).contains(groups[0].count),
              groups.dropFirst().allSatisfy({ $0.count == 3 }),
              groups.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { throw Refused() }
        let ungroupedText = text.filter { $0 != grouping }
        return point.map { ungroupedText.replacingOccurrences(of: String($0), with: decimal) } ?? ungroupedText
    }
}

/// Edits typed into a `NumberEntryField` and not yet committed. Every UI
/// action that starts work goes through `run`, which commits them first —
/// the SwiftUI stand-in for AppKit's `commitEditing()`.
@MainActor
enum PendingEdits {
    private static var commits: [UUID: () -> Void] = [:]

    static func register(_ id: UUID, commit: @escaping () -> Void) { commits[id] = commit }
    static func forget(_ id: UUID) { commits[id] = nil }

    static func commitAll() {
        let pending = commits
        commits.removeAll()
        for commit in pending.values { commit() }
    }

    /// Commit every pending edit, then start `work`.
    static func run(_ work: @escaping @MainActor () async -> Void) {
        commitAll()
        Task { await work() }
    }
}

/// The one text field every number is typed into: it owns its text and
/// commits on Return or focus loss — never per keystroke. Drive 2026-09-30:
/// SwiftUI's `TextField(value:format:)` committed each parseable prefix as it
/// was typed, so `0.0` on the way to `0.02` cleared the file's Q (the setter's
/// ≤ 0 branch) and a typo ended at its last good prefix (`300.5.` → 300,5).
/// A committed text that does not parse reverts; an empty one reverts, or
/// clears the value when `emptyClears`.
struct NumberEntryField<Value: Equatable, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    let value: Value?
    let format: Format
    var prompt: String?
    var emptyClears = false
    let onCommit: (Value?) -> Void

    @State private var text = ""
    @State private var editID = UUID()
    @FocusState private var isFocused: Bool

    private var entry: DecimalEntryFormat<Format> { DecimalEntryFormat(format) }
    private var shown: String { value.map { entry.format($0) } ?? "" }

    var body: some View {
        TextField(title, text: $text, prompt: prompt.map { Text($0) })
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            // Escape abandons the edit, as in any Mac text field.
            .onExitCommand { PendingEdits.forget(editID); text = shown }
            .onAppear { text = shown }
            // Torn down mid-edit (task or room switch): the edit still lands.
            .onDisappear(perform: commit)
            // Only a commit or an outside change moves `value` now, so the
            // text follows it even while the field keeps focus.
            .onChange(of: value) { _, _ in text = shown }
            // A click on a toolbar or inspector button does not take focus
            // from a Mac text field, so an uncommitted edit is registered and
            // every action that starts work commits it first
            // (`PendingEdits.run`, Fable review 2026-09-30).
            .onChange(of: text) { _, typed in
                if typed == shown {
                    PendingEdits.forget(editID)
                } else {
                    PendingEdits.register(editID) { [value, emptyClears, entry, onCommit] in
                        if case .set(let newValue) = Self.resolve(typed: typed, current: value,
                                                                  emptyClears: emptyClears, entry: entry) {
                            onCommit(newValue)
                        }
                    }
                }
            }
    }

    private func commit() {
        PendingEdits.forget(editID)
        if case .set(let newValue) = Self.resolve(typed: text, current: value,
                                                  emptyClears: emptyClears, entry: entry) {
            onCommit(newValue)
        }
        text = shown
    }

    enum Resolution: Equatable { case keep, set(Value?) }

    /// What a committed text does — pure, so the rule is testable without a
    /// host: empty keeps (or clears, when `emptyClears`); the text the field
    /// shows for the current value keeps; a text that does not parse keeps; the
    /// same value keeps (no provenance flip); else sets.
    ///
    /// The shown text is not an edit (Gate D 2026-10-04): the field commits on
    /// blur, Return and teardown, and a format that shows fewer digits than the
    /// value has (a Defocus of 12.346 shown 12,3; a Float-backed 0.3, which is
    /// 0.30000001) would otherwise store its own rounding every time the field
    /// was merely left — and an Exploratory scale dragged to 0.0125597 lost its
    /// ACOM result to the 0.0126 it showed. Declared trade-off: while a finer
    /// value is stored, typing exactly the shown text is a no-op (`0,030` or
    /// `0.03` still set it).
    static func resolve(typed raw: String, current: Value?, emptyClears: Bool,
                        entry: DecimalEntryFormat<Format>) -> Resolution {
        let typed = raw.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return emptyClears && current != nil ? .set(nil) : .keep }
        if let current, typed == entry.format(current) { return .keep }
        guard let parsed = try? entry.parseStrategy.parse(typed), parsed != current else { return .keep }
        return .set(parsed)
    }
}

/// `NumericField` for a value that may be unset: empty shows `prompt`, and an
/// emptied field commits nothing — the value in effect stays (S3: an emptied
/// or unparsed entry must never clear a calibration the file supplied).
struct OptionalNumericField<Value: Equatable, Format: ParseableFormatStyle>: View
where Format.FormatInput == Value, Format.FormatOutput == String {
    let title: String
    let value: Value?
    let format: Format
    var unit: String?
    var prompt: String = "Not set"
    let onCommit: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            NumberEntryField(title: title, value: value, format: format, prompt: prompt) {
                if let entered = $0 { onCommit(entered) }
            }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: LayoutPolicy.numericFieldWidth)
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityLabel(title)
    }
}
