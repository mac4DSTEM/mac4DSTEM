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
/// in the Map room and in the AI Analysis room) collapsing together, since
/// they wrote the same `@SceneStorage` key. `WorkspaceInspector` sets this
/// once per tab ("info"), and again, more specifically, per workspace room
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

/// A read-only fact: label leading, the value trailing in the secondary
/// label colour, selectable (a value the reader may paste into a notebook)
/// and in monospaced digits so a column of these keeps its numerals aligned.
/// `mono` sets the whole value monospaced — a path or a shape string. The
/// value wraps (trailing-aligned) rather than truncating.
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .fixedSize()
            Spacer(minLength: 0)
            Text(value)
                .monospacedDigit()
                .fontDesign(mono ? .monospaced : .default)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .layoutPriority(1)
        }
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

    @FocusState private var fieldIsFocused: Bool

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
                TextField(label, value: $value, format: format)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: LayoutPolicy.adjustmentValueWidth)
                    .focused($fieldIsFocused)
                    .onSubmit(commit)
                    .onChange(of: fieldIsFocused) { _, isFocused in
                        if !isFocused { commit() }
                    }
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

    private func commit() {
        value = Self.clamp(value, to: range)
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
