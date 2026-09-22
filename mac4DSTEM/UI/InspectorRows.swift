import SwiftUI

/// The inspector's row vocabulary (ADR 034, owner 2026-09-21): originally
/// "Lightroom adjustment panel meets Xcode utility pane" — flat, dense,
/// collapsible sections with hairline separators. Superseded 2026-09-22
/// (owner, driving the Prepare card draft: "make it look like the other
/// panels, make everything the same, then improve from there"): sections are
/// now `GroupBox` cards with a `.headline` title row, not flat hairline
/// dividers — the rest of the vocabulary (label column, row spacing) is
/// unchanged. Every fixed point below comes from `LayoutPolicy`, or from a
/// `static let` declared here for chrome `LayoutPolicy` has no opinion on
/// (card spacing); nothing here invents an unexplained number.
///
/// `WorkspaceInspector.swift` and the room files (`PrepareSettings`,
/// `ImagingSettings`, `MapSettings`, `PhaseMappingSettings`, `PhaseSettings`,
/// `AIAnalysisSettings`, `ResultsSettings`, `DiffractionGroupsSettings`,
/// `CalibrationReadinessRow`) build the inspector's contents from the types
/// in this file — `InspectorSection`/`InspectorGroup` (the cards),
/// `InspectorRow`/`InspectorValueRow`/`AdjustmentSlider`/`InspectorNote`
/// (rows inside a card), and `InspectorActionRow`/`InspectorAdaptiveButton`/
/// `InspectorStatusRow` (buttons and the calibration-style status line). One
/// kit for all rooms (owner rule, 2026-09-22): a room-specific layout fix
/// belongs here, not hand-rolled in one room file. This file is presentation
/// only: it holds no `AppState`, `OperationCenter` or `Session` reference,
/// and no fixed number that isn't a `LayoutPolicy` constant or one of this
/// file's own, explained `static let`s.

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

/// Layout constants this file's card chrome owns — not `LayoutPolicy`'s,
/// since nothing outside `InspectorSection`/`InspectorGroup` depends on them
/// (the other agent's file, per the room brief, stays untouched).
private enum InspectorCardMetrics {
    /// The gap after one card, so adjacent sections separate even where the
    /// caller stacks them as bare siblings with no spacing of its own
    /// (`WorkspaceInspector`'s per-room `Group`s concatenate several
    /// `InspectorSection`s inline; its own `inspectorSectionSpacing` applies
    /// only between its named top-level groups — `RequirementsSection`,
    /// `workspaceSettings`, … — not the individual sections inside one of
    /// them, so each card must space itself rather than rely on that
    /// spacing to separate it from its neighbour).
    static let cardSpacing: CGFloat = 10
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
/// The header is a `GroupBox` label: the title in `.headline`, sentence
/// case, with a trailing disclosure chevron that rotates and toggles the
/// section open or closed. Card, not hairline: two cards sitting back to
/// back read as separated by their own borders, so the chrome below adds
/// `InspectorCardMetrics.cardSpacing` after each one rather than depending
/// on the caller's stack to space every section apart (`WorkspaceInspector`
/// concatenates several rooms' sections as bare siblings with no spacing of
/// its own between them — see that file's own `inspectorSectionSpacing`,
/// applied only between its named top-level groups, not the individual
/// sections inside one). Rows inside are spaced
/// `LayoutPolicy.inspectorRowSpacing`. When the caller passes no `expanded`
/// binding, the section remembers its own open/closed state, scoped by
/// `inspectorScope` and title, via `@SceneStorage`, defaulting to expanded —
/// the inspector reads, at a glance, the way the old always-visible `Form`
/// sections did until the user collapses one.
///
/// `icon` (an `Image`) and `systemImage` (a system symbol name) are two ways
/// to give the header an icon; `icon` wins if both are set. `emphasized`
/// covers the one header this vocabulary did not otherwise have room for: a
/// stage row that carries an always-visible status glyph and reads bolder
/// while it is the active step (the parallax pipeline's four stages). None
/// set, most sections draw the plain title header above.
struct InspectorSection<Content: View>: View {
    private let title: String
    private let icon: Image?
    private let systemImage: String?
    private let emphasized: Bool
    private let externalExpanded: Binding<Bool>?
    private let content: Content
    @Environment(\.inspectorScope) private var scope

    init(
        _ title: String,
        icon: Image? = nil,
        systemImage: String? = nil,
        emphasized: Bool = false,
        expanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
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
            InspectorSectionBody(title: title, icon: icon, systemImage: systemImage, emphasized: emphasized,
                                  isExpanded: externalExpanded, content: content)
        } else {
            InspectorSectionRemembering(
                key: Self.sceneStorageKey(scope: scope, title: title),
                title: title, icon: icon, systemImage: systemImage, emphasized: emphasized, content: content)
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
    private let systemImage: String?
    private let emphasized: Bool
    @SceneStorage private var isExpanded: Bool
    private let content: Content

    init(key: String, title: String, icon: Image?, systemImage: String?, emphasized: Bool, content: Content) {
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
        self.emphasized = emphasized
        self._isExpanded = SceneStorage(wrappedValue: true, key)
        self.content = content
    }

    var body: some View {
        InspectorSectionBody(title: title, icon: icon, systemImage: systemImage, emphasized: emphasized,
                              isExpanded: $isExpanded, content: content)
    }
}

/// The section's actual chrome — a `GroupBox` card whose label is a header
/// button (title + disclosure chevron) — shared by the remembered-state and
/// explicit-binding paths.
private struct InspectorSectionBody<Content: View>: View {
    let title: String
    let icon: Image?
    let systemImage: String?
    let emphasized: Bool
    let isExpanded: Binding<Bool>
    let content: Content

    /// Collapsed, the card is its header alone: an empty `GroupBox` still
    /// draws its rounded box, which read on screen as a stray dot under the
    /// title (first macOS 27 look, 2026-09-22).
    var body: some View {
        Group {
            if isExpanded.wrappedValue {
                GroupBox {
                    VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                        content
                    }
                    .padding(.top, LayoutPolicy.inspectorRowSpacing)
                    // Full column width: a `GroupBox` hugs its content, so a
                    // card of short rows came out narrower than its siblings.
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    header
                }
            } else {
                header
            }
        }
        .padding(.bottom, InspectorCardMetrics.cardSpacing)
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                headerLabel
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isExpanded.wrappedValue ? [.isHeader] : [.isHeader, .isButton])
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    @ViewBuilder
    private var headerLabel: some View {
        // Primary, not secondary: a secondary headline over a card read as a
        // disabled control on screen. `emphasized` stays a weight change.
        let text = Text(title)
            .font(.headline.weight(emphasized ? .bold : .semibold))
            .foregroundStyle(.primary)
        if let icon {
            Label {
                text
            } icon: {
                icon
                    .foregroundStyle(emphasized ? .primary : .secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        } else if let systemImage {
            Label {
                text
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(emphasized ? .primary : .secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        } else {
            text
        }
    }
}

/// A non-collapsible run of rows — no title header, no chevron, no
/// `@SceneStorage` — for content that was never a titled `Section` at HEAD.
///
/// Two rooms invented a title converting into this vocabulary (a matcher's
/// untitled run button became "Run", which also collides with the bottom
/// pane's own Run tab; a parallax product picker became "Product", which
/// collided with the Info tab's own "Product"); `InspectorGroup` is what
/// they convert to instead, so nothing acquires a name — or a persisted
/// expansion state — it never had. Same card chrome and row spacing as
/// `InspectorSection`, minus the header and the disclosure.
struct InspectorGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: LayoutPolicy.inspectorRowSpacing) {
                content
            }
            .padding(.top, LayoutPolicy.inspectorRowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, InspectorCardMetrics.cardSpacing)
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
///
/// `ViewThatFits` between the original flush-right `HStack` and a
/// trailing-aligned `VStack`: at the inspector's narrowest widths several
/// small buttons side by side can run out of room and clip, the same
/// failure mode `InspectorAdaptiveButton` exists to avoid for one button —
/// wrapping this row to a column, rather than truncating, is the fallback.
/// A single `InspectorAdaptiveButton` inside this row still degrades to its
/// own icon-only form first, before this row ever needs to wrap, so callers
/// with one action are better served composing `InspectorAdaptiveButton`
/// directly. API is unchanged — same `init`, same `Content`.
struct InspectorActionRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Spacer(minLength: 0)
                content
            }
            VStack(alignment: .trailing, spacing: LayoutPolicy.inspectorRowSpacing) {
                content
            }
        }
        .controlSize(.small)
    }
}

/// A button that gives up its text label, not its meaning, when the column
/// is too narrow: `ViewThatFits` between the full `Label(title:systemImage:)`
/// and a bare `Image(systemName:)`, both wired to the same `help` tooltip
/// and the same accessibility label.
///
/// Built for a failure this vocabulary had without it: a narrow inspector
/// column truncates a `Label`'s text mid-word ("Compute M…"), which drops
/// the missing part of the word silently — nothing on screen says a
/// character is missing. The icon-only fallback loses nothing the tooltip
/// didn't already say, and is a whole, legible button rather than a clipped
/// one. This is the durable pattern for every button that must survive the
/// inspector's minimum width, not a one-room stopgap.
struct InspectorAdaptiveButton: View {
    private let title: String
    private let systemImage: String
    private let prominent: Bool
    private let help: String?
    private let role: ButtonRole?
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        help: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.help = help
        self.role = role
        self.action = action
    }

    var body: some View {
        Group {
            // `ButtonStyle` is a protocol: `.borderedProminent` and
            // `.bordered` are different concrete types, so the choice
            // between them branches here rather than in a ternary.
            if prominent {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        .help(help ?? title)
        .accessibilityLabel(title)
    }

    private var button: some View {
        Button(role: role, action: action) {
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: systemImage)
                Image(systemName: systemImage)
            }
        }
    }
}

/// A status line whose short status word can never wrap and whose longer
/// explanation never has to: the status word alone, `.fixedSize()`, pinned
/// to the trailing edge, and the (often longer)
/// detail text under the title on the leading side instead.
///
/// Built for the other failure the Prepare card draft found: an earlier
/// layout put both the status word and the wrapping detail line in the
/// trailing column together. At any width the short status word floated
/// flush-right with a gap after it, disconnected from the label, because
/// the wrapped detail line below it filled most of the row and read as
/// left-aligned; narrower still, that trailing column had no floor to stop
/// the status word itself wrapping mid-word. Splitting the two — status
/// word alone, fixed, trailing; detail prose leading, under the title — is
/// the durable fix, not a width this one row happened to need.
struct InspectorStatusRow: View {
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let detail: String?
    private let status: String
    private let statusTint: Color

    init(
        title: String,
        systemImage: String,
        tint: Color = .primary,
        detail: String? = nil,
        status: String,
        statusTint: Color = .secondary
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.detail = detail
        self.status = status
        self.statusTint = statusTint
    }

    var body: some View {
        // An explicit HStack + Spacer, not `LabeledContent`: outside a
        // `Form`, `LabeledContent` sets its value right after the label, so
        // the status word floated mid-row at a different x on every row
        // (first macOS 27 look, 2026-09-22). The spacer pins it trailing.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(tint)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(status)
                .fixedSize()
                .foregroundStyle(statusTint)
        }
        .accessibilityElement(children: .combine)
        .controlSize(.regular)
    }
}
