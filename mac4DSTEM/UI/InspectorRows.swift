import SwiftUI

/// The inspector's row vocabulary (ADR 034, owner 2026-09-21): "Lightroom
/// adjustment panel meets Xcode utility pane" — flat, dense, collapsible
/// sections with a consistent label column and hairline separators, in place
/// of the boxed `.grouped` `Form` the inspector used before. Every fixed
/// point below comes from `LayoutPolicy`; nothing here invents its own
/// number.
///
/// `WorkspaceInspector.swift` and the room files (`PrepareSettings`,
/// `ImagingSettings`, `MapSettings`, `PhaseMappingSettings`, `PhaseSettings`,
/// `AIAnalysisSettings`, `ResultsSettings`, `DiffractionGroupsSettings`,
/// `CalibrationReadinessRow`) build the inspector's contents from these six
/// types. This file is presentation only: it holds no `AppState`,
/// `OperationCenter` or `Session` reference, and no fixed number that isn't
/// a `LayoutPolicy` constant.

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

extension EnvironmentValues {
    var inspectorScope: String {
        get { self[InspectorScopeKey.self] }
        set { self[InspectorScopeKey.self] = newValue }
    }
}

/// A collapsible group of inspector rows — the utility pane's basic unit,
/// replacing a `Form` `Section`.
///
/// The header is an uppercase, semibold, secondary caption with the native
/// disclosure chevron a `DisclosureGroup` already draws; a hairline
/// `Divider()` closes the group below it, expanded or not, so collapsed
/// neighbours still separate. Rows inside are spaced
/// `LayoutPolicy.inspectorRowSpacing`. When the caller passes no `expanded`
/// binding, the section remembers its own open/closed state, scoped by
/// `inspectorScope` and title, via `@SceneStorage`, defaulting to expanded —
/// the inspector reads, at a glance, the way the old always-visible `Form`
/// sections did until the user collapses one.
///
/// `icon` and `emphasized` cover the one header this vocabulary did not
/// otherwise have room for: a stage row that carries an always-visible
/// status glyph and reads bolder while it is the active step (the parallax
/// pipeline's four stages). Neither is set, most sections draw the plain
/// caption header above.
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

/// The section's actual chrome — header, disclosure, rows, hairline —
/// shared by the remembered-state and explicit-binding paths.
private struct InspectorSectionBody<Content: View>: View {
    let title: String
    let icon: Image?
    let emphasized: Bool
    let isExpanded: Binding<Bool>
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                    content
                }
                .padding(.top, LayoutPolicy.inspectorRowSpacing)
            } label: {
                header
            }
            Divider()
        }
    }

    @ViewBuilder
    private var header: some View {
        let label = Text(title)
            .font(.caption.weight(emphasized ? .bold : .semibold))
            .foregroundStyle(emphasized ? .primary : .secondary)
            .textCase(.uppercase)
        if let icon {
            Label {
                label
            } icon: {
                icon
                    .foregroundStyle(emphasized ? .primary : .secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        } else {
            label
        }
    }
}

/// A non-collapsible run of rows — no caption header, no chevron, no
/// `@SceneStorage` — for content that was never a titled `Section` at HEAD.
///
/// Two rooms invented a title converting into this vocabulary (a matcher's
/// untitled run button became "Run", which also collides with the bottom
/// pane's own Run tab; a parallax product picker became "Product", which
/// collided with the Info tab's own "Product"); `InspectorGroup` is what
/// they convert to instead, so nothing acquires a name — or a persisted
/// expansion state — it never had. Same row spacing and trailing hairline as
/// `InspectorSection`, minus the header and the disclosure.
struct InspectorGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                content
            }
            Divider()
        }
    }
}

/// One label/control row: a trailing-aligned secondary caption in a fixed
/// column, then the control filling the rest.
///
/// The label sits at `LayoutPolicy.inspectorLabelWidth`, `.subheadline`,
/// secondary — the utility-pane column every row in a section lines up
/// against. `InspectorRow` applies `.controlSize(.small)` to its content;
/// hiding the control's own label (`.labelsHidden()`, when the control draws
/// one — a `Toggle`, a `Picker`, a `TextField`) is the caller's job, since
/// only the caller knows whether its content already has no label of its
/// own to hide.
///
/// `emphasized` promotes the label from secondary to primary — a ranked
/// list's top row (a zone-axis fit's rank 0) reading as the answer among
/// alternatives, not one caption among equals.
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
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: LayoutPolicy.inspectorLabelWidth, alignment: .trailing)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .font(.subheadline)
            content
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A read-only fact: label column, then a selectable value in monospaced
/// digits.
///
/// The value is always selectable (`.textSelection(.enabled)`) — an
/// inspector fact the reader may want to paste into a lab notebook — and
/// always `.monospacedDigit()`, so a column of these rows keeps its numerals
/// aligned whether or not the surrounding word wraps. `mono` additionally
/// sets the whole value's `.fontDesign(.monospaced)` — for a path or a shape
/// string, where every character (not only the digits) should line up.
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
        InspectorRow(label) {
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .fontDesign(mono ? .monospaced : .default)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
    }
}

/// The Lightroom row: label column, a filling `Slider`, an editable value
/// field, and an optional unit.
///
/// The `TextField` beside the slider is `LayoutPolicy.adjustmentValueWidth`
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
        HStack(alignment: .firstTextBaseline) {
            labelView
            slider
                .labelsHidden()
                .controlSize(.small)
            TextField(label, value: $value, format: format)
                .labelsHidden()
                .controlSize(.small)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(Text(value, format: format))
    }

    @ViewBuilder
    private var labelView: some View {
        let text = Text(label)
            .frame(width: LayoutPolicy.inspectorLabelWidth, alignment: .trailing)
            .foregroundStyle(.secondary)
            .font(.subheadline)
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

/// A trailing-aligned row of small buttons — the vocabulary's replacement
/// for a bare button (or button group) sitting at a `Section`'s end.
struct InspectorActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content
        }
        .controlSize(.small)
    }
}
