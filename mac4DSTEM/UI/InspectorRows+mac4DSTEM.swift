//
//  InspectorRows+mac4DSTEM.swift
//  Role: the inspector rows only mac4DSTEM uses and the room-specific VoiceOver strings. The shared row kit (sections, rows, sliders,
//        notes, warnings, `RoomAccessibilityText`'s common half) is ShellInspector's (suite task 8, MacEMUI); these stay here
//        because macTEM uses none of them (docs/split-reports/inspector.md section 4). Moved out of UI/InspectorRows.swift unchanged.
//

import ShellLayout
import ShellMetal
import SwiftUI
import ShellControls
import ShellInspector

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

/// A section action that never truncates: the full `Label` when the button
/// has room, the symbol alone when it does not, with the title kept on
/// `.help` and as the accessibility label. `ViewThatFits` is the durable
/// pattern for this, not a stopgap. A glass push button (`.glass`) — the
/// room's one prominent action is its toolbar verb (HIG, Buttons).
struct InspectorAdaptiveButton: View {
    private let title: String
    private let systemImage: String
    private let help: String?
    private let hint: String?
    private let role: ButtonRole?
    private let action: () -> Void

    /// `help` is the tooltip and may run long; `hint` is the one-phrase VoiceOver hint (`help(_:)` is also the hint, and Apple asks
    /// for "a brief phrase"). Without `hint`, the hint is the first sentence of `help` when that is short enough, else none.
    init(
        _ title: String,
        systemImage: String,
        help: String? = nil,
        hint: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.hint = hint
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
        .buttonStyle(.glass)   // Liquid Glass like Xcode's buttons (owner 2026-10-07); the toolbar verb is `.glassProminent`
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? RoomAccessibilityText.briefHint(from: help))
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
    private let hint: String?

    /// The status symbol's slot and the gap after it. `childIndent` is where
    /// the title text starts: a row's own controls (a manual value, a
    /// re-measure button) indent to it, so they read as belonging to that
    /// row rather than to the section.
    static let symbolWidth: CGFloat = 16
    static let symbolSpacing: CGFloat = 8
    static var childIndent: CGFloat { symbolWidth + symbolSpacing }

    init(title: String, systemImage: String, tint: Color = .secondary, detail: String? = nil, status: String,
         hint: String? = nil) {
        self.hint = hint
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
        // On the element that takes focus: a hint on a `.contain` parent is not what VoiceOver reads from the child.
        .accessibilityHint(hint ?? "")
    }
}

// MARK: - Glass chips

/// How a `GlassChipGroup` answers a tap: `single` is a picker (one chip on, a tap on the one that is on keeps it), `multi` is a
/// set of toggles.
nonisolated enum GlassChipMode: Sendable { case single, multi }

/// The selection logic of a chip group, pure so a test can hold it without a host.
nonisolated enum GlassChipSelection {
    /// The chips that are on after a tap on `id`. A disabled chip does nothing; in `single` mode the tapped chip becomes the only
    /// one on (and stays on when it already was: a picker has no empty state); in `multi` mode it toggles.
    static func tapped<ID: Hashable>(_ id: ID, on: Set<ID>, mode: GlassChipMode, enabled: Bool = true) -> Set<ID> {
        guard enabled else { return on }
        switch mode {
        case .single: return [id]
        case .multi:
            var next = on
            if next.remove(id) == nil { next.insert(id) }
            return next
        }
    }

    /// A single-choice value as the set a group reads and writes: the value alone on the way in; on the way out the chip tapped.
    /// `Sendable`: the Binding's closures are `@Sendable` and capture the value and its metatype (four Swift 6 warnings without it).
    static func single<ID: Hashable & Sendable>(_ value: Binding<ID>) -> Binding<Set<ID>> {
        Binding(get: { [value.wrappedValue] }, set: { if let chosen = $0.first { value.wrappedValue = chosen } })
    }
}

/// One chip: what it says, what it is called to VoiceOver, and the colour it lights in.
struct GlassChip<ID: Hashable>: Identifiable {
    let id: ID
    var title: String
    /// False for a chip that is its symbol alone (the region tools); the title is then its accessibility label.
    var showsTitle = true
    /// An SF Symbol drawn before the title, in `symbolColor` when that is set (a curve's own colour: the legend).
    var symbol: String?
    var symbolColor: Color?
    /// The glass tint while the chip is on; nil lights it in the accent colour (a plain choice).
    var tint: Color?
    var help: String?
    var enabled = true
    var accessibilityID: String?
}

/// The chip rows' wrapping, pure so a test can hold it: chips left to right, a new row when the next would pass `maxWidth`. A
/// zero width gives one chip per row, so the widest chip is the row's minimum width (the inspector's width budget reads that).
nonisolated enum GlassChipFlow {
    static func arrange(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in sizes {
            if x > 0, x + s.width > maxWidth { x = 0; y += rowHeight + lineSpacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += s.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, s.height)
        }
        return (origins, CGSize(width: widest, height: sizes.isEmpty ? 0 : y + rowHeight))
    }
}

private struct GlassChipFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func arranged(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        GlassChipFlow.arrange(sizes: subviews.map { $0.sizeThatFits(.unspecified) },
                              maxWidth: proposal.width ?? .infinity, spacing: spacing, lineSpacing: lineSpacing)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arranged(proposal, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arranged(ProposedViewSize(width: bounds.width, height: nil), subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// A row of capsule chips on Liquid Glass, the way Apple describes glass on a custom control ("Applying Liquid Glass to custom
/// views"): quiet at rest — an untinted capsule — and alive under the pointer, which the system does (`interactive()`; nothing is
/// drawn by hand). A chip that is on takes a tint: its own colour, or the accent for a plain choice (the accent means selection).
///
/// One `GlassEffectContainer` per group and none nested: Apple's performance rule is few containers. The container's spacing is
/// less than the chips' own gap, so the capsules never blend at rest (a larger one would merge them). Chips are buttons, so Space
/// and Return work, and an `isSelected` trait says which are on. Text 12 pt (above the 10 pt floor).
struct GlassChipGroup<ID: Hashable>: View {
    let chips: [GlassChip<ID>]
    var mode: GlassChipMode = .single
    @Binding var selection: Set<ID>
    /// The group's own accessibility identifier; each chip keeps its `accessibilityID`.
    var identifier: String?

    /// The gap between chips, and the container's blend distance (smaller, so nothing merges at rest).
    static var gap: CGFloat { 8 }
    static var containerSpacing: CGFloat { 6 }
    static var minimumHeight: CGFloat { 24 }
    /// A tint over glass reads at about half strength; the full colour would swallow the label.
    static var tintOpacity: Double { 0.55 }

    /// What a tap does to the selection (the button's action; a test calls it).
    func tap(_ id: ID) {
        guard let chip = chips.first(where: { $0.id == id }) else { return }
        selection = GlassChipSelection.tapped(id, on: selection, mode: mode, enabled: chip.enabled)
    }

    var body: some View {
        GlassEffectContainer(spacing: Self.containerSpacing) {
            GlassChipFlowLayout(spacing: Self.gap, lineSpacing: 6) {
                ForEach(chips) { chip in
                    ChipButton(chip: chip, isOn: selection.contains(chip.id)) { tap(chip.id) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }

    private struct ChipButton: View {
        let chip: GlassChip<ID>
        let isOn: Bool
        let action: () -> Void

        private var glass: Glass {
            let base = Glass.regular
            guard isOn else { return base.interactive(chip.enabled) }
            return base.tint((chip.tint ?? .accentColor).opacity(GlassChipGroup.tintOpacity)).interactive(chip.enabled)
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    if let symbol = chip.symbol {
                        Image(systemName: symbol).symbolRenderingMode(.monochrome).foregroundStyle(chip.symbolColor ?? .primary)
                    }
                    if chip.showsTitle { Text(chip.title).fixedSize() }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(minHeight: GlassChipGroup.minimumHeight)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(glass, in: .capsule)
            .disabled(!chip.enabled)
            .help(chip.help ?? "")
            .accessibilityLabel(chip.title)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier(chip.accessibilityID ?? "")
        }
    }
}

/// The room-specific strings of `RoomAccessibilityText` (the shared ones are ShellInspector's).
extension RoomAccessibilityText {
    /// The upsampling factor the stepper shows as "16×".
    static func upsampleFactor(_ factor: Int) -> String { "\(factor) times" }

    /// The relative-reference peak the stepper shows as "#2" (the model stores it zero-based).
    static func referencePeak(zeroBasedIndex: Int) -> String { "peak \(zeroBasedIndex + 1)" }

    /// The Reconstruction stage status (was a value on the stage's container, where a header button's focus does not reach it).
    static func stageStatus(complete: Bool, active: Bool) -> String {
        complete ? "Complete" : (active ? "Current step" : "Pending")
    }

    /// The hint of a field that falls back to a global value when empty: the prompt that shows the value is grey text only.
    /// `globalText` is the value as the field would type it.
    static func globalFallbackHint(isEmpty: Bool, globalText: String, unit: String) -> String {
        isEmpty ? "Empty: using the global value \(globalText) \(unit)"
                : "Clear the field to use the global value \(globalText) \(unit)"
    }

    /// The exact text behind a rounded provenance value, or nil when the display shows it whole.
    static func exactValue(raw: String, displayed: String) -> String? { raw == displayed ? nil : raw }

    /// Announced when the ring-probe suggestion appears in Bragg Disks (a warning that shows up without any focus change).
    static func ringProbe(outerRadius: Double) -> String {
        "Ring-shaped probe: its outer edge is at \(pixels(outerRadius.rounded()))"
    }

    /// Announced when a Reconstruction stage turns complete.
    static func stageComplete(title: String) -> String { "\(title) complete" }

    /// The orange captions under the phase fields, one source for the screen and the announcement.
    static let zoneAxisMalformed = "A zone axis is three integers, like 0 1 0."
    static let relationshipMalformed = "A relationship is pairs like (002) ∥ (200); planes in parentheses, directions in square brackets."

    /// The caption a typed field shows (and VoiceOver announces) while its text does not parse; nil when empty or valid.
    static func malformedCaption(draft: String, parses: Bool, caption: String) -> String? {
        (!draft.isEmpty && !parses) ? caption : nil
    }

    /// The sample a history plot moves to for a step of `offset` (±1) along its finite samples, from `current` (the plot's selection,
    /// or the last sample when none is chosen). Clamped at both ends; nil when there is no finite sample. Shared by the adjustable
    /// action (VoiceOver) and the arrow keys (full keyboard access), so both move the same way.
    static func steppedSample(finiteIndices indices: [Int], current: Int?, offset: Int) -> Int? {
        guard !indices.isEmpty else { return nil }
        let from = current ?? indices[indices.count - 1]
        let position = indices.firstIndex(of: from) ?? indices.count - 1
        return indices[min(indices.count - 1, max(0, position + offset))]
    }

    /// The comparison panels' shared zoom after a VoiceOver / keyboard zoom step: doubled or halved, between 1 and `maximum`.
    static func steppedZoom(_ zoom: Double, zoomIn: Bool, maximum: Double) -> Double {
        min(maximum, max(1, zoomIn ? zoom * 2 : zoom / 2))
    }

    /// A saved product's state value: "Shown" for the product on screen, empty otherwise.
    static func shownValue(isCurrent: Bool) -> String { isCurrent ? "Shown" : "" }
}

extension View {
    /// A tooltip for the pointer and a separate one-phrase hint for VoiceOver (`help(_:)` alone speaks the whole tooltip as the hint).
    func tooltip(_ help: String, hint: String) -> some View {
        self.help(help).accessibilityHint(hint)
    }
}

/// Posts a VoiceOver announcement when `message` changes to a new, non-nil text; never on appearance and never for a repeat.
/// `delay` holds the announcement back and drops it if the message changes again meanwhile (a field being typed into).
/// Attach it to a view that stays on screen: a view that appears together with its message has no earlier value to differ from.
private struct AnnouncesChanges: ViewModifier {
    let message: String?
    let delay: Duration
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onChange(of: message) { _, new in
            pending?.cancel()
            guard let new else { return }
            pending = Task { @MainActor in
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                    if Task.isCancelled { return }
                }
                AccessibilityNotification.Announcement(new).post()
            }
        }
    }
}

extension View {
    func announcing(_ message: String?, after delay: Duration = .zero) -> some View {
        modifier(AnnouncesChanges(message: message, delay: delay))
    }
}
