import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// The periodic table's own shape (spec 2 D-9): 18 columns, periods 1 to 6, the lanthanide slot in period 6 column 3 left empty
/// as the fold's place; the f-block and period 7 stay folded below (`PeriodicLayout.folded`, unchanged). Data and metrics are
/// pure so a test can hold them; `PeriodicLayout` (lane C's file) is not edited.
nonisolated enum PeriodicTableGrid {
    static let columns = 18
    static let gap: CGFloat = 2
    /// Period 1 to 6, group 1 to 18 (0-based columns); nil is an empty place. Period 6 column 2 is the lanthanide slot.
    static let rows: [[Int?]] = [
        [1] + [Int?](repeating: nil, count: 16) + [2],
        [3, 4] + [Int?](repeating: nil, count: 10) + Array(5...10).map { Optional($0) },
        [11, 12] + [Int?](repeating: nil, count: 10) + Array(13...18).map { Optional($0) },
        Array(19...36).map { Optional($0) },
        Array(37...54).map { Optional($0) },
        [55, 56, nil] + Array(72...86).map { Optional($0) },
    ]
    /// The narrowest width the grid asks for (a 10-pt cell); the inspector's narrowest content column is 248 pt, so it always
    /// fits. Below this the cells would not hold a symbol; above it they grow with the width.
    static let minimumWidth: CGFloat = 18 * 10 + 17 * 2
    /// The width a parent that proposes none (a probe, a preview) gets: the inspector's narrowest content column.
    static let idealWidth: CGFloat = 248

    /// cell = (width - 17 gaps) / 18.
    static func cellSize(width: CGFloat) -> CGFloat { (max(width, minimumWidth) - CGFloat(columns - 1) * gap) / CGFloat(columns) }
    /// 0.5 x the cell, clamped to 9...13 pt. The floor is 9 pt, not the app's 10: the owner's wish for this table (2026-10-06).
    static func symbolSize(cell: CGFloat) -> CGFloat { min(max(0.5 * cell, 9), 13) }
    /// The height of `rowCount` rows of square cells at this width.
    static func height(width: CGFloat, rowCount: Int) -> CGFloat {
        rowCount > 0 ? CGFloat(rowCount) * cellSize(width: width) + CGFloat(rowCount - 1) * gap : 0
    }
}

/// Lays its subviews out in `columns` columns of square cells that fill the proposed width (`PeriodicTableGrid`).
struct PeriodicGridLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PeriodicTableGrid.idealWidth
        let width = max(w, PeriodicTableGrid.minimumWidth)
        let rows = (subviews.count + PeriodicTableGrid.columns - 1) / PeriodicTableGrid.columns
        return CGSize(width: width, height: PeriodicTableGrid.height(width: width, rowCount: rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = PeriodicTableGrid.cellSize(width: bounds.width)
        for (i, view) in subviews.enumerated() {
            let col = i % PeriodicTableGrid.columns, row = i / PeriodicTableGrid.columns
            view.place(at: CGPoint(x: bounds.minX + CGFloat(col) * (cell + PeriodicTableGrid.gap),
                                   y: bounds.minY + CGFloat(row) * (cell + PeriodicTableGrid.gap)),
                       proposal: ProposedViewSize(width: cell, height: cell))
        }
    }
}

/// What a right-click on an element lists under "Lines" for one family: a checkable item per line the table has for it.
nonisolated enum ElementLines {
    struct Item: Equatable { var id: String; var title: String }

    /// A line weaker than this against its family's alpha is not offered: its window would hold noise (the same 1 % bar the window
    /// conflict check uses for candidate lines).
    static let minimumWeight = 0.01

    /// "Kα 1,487 keV" per line, the table's order (alpha first), the energy in the person's locale (3 decimals); empty when
    /// the family has no line for this element (the menu then leaves the family out).
    static func items(family: LineFamily, z: Int, locale: Locale = .current) -> [Item] {
        XRayLines.lines(of: PeriodicLayout.symbol(z))
            .filter { $0.family.rawValue == family.rawValue && $0.weight >= minimumWeight }
            .map { Item(id: $0.id, title: "\(ElementWindows.shortLabel(ofLineID: $0.id)) \(SpectrumReadout.energy($0.energy, locale: locale)) keV") }
    }
}

/// The periodic table of the Elements section (ADR 056, spec 2 D-9). States by fill only, no legend: mapped (accent fill),
/// proposed (accent outline), fit only (hollow), off (a quiet well), not detectable (dim). Click toggles Quantify / Off; right-click
/// gives the role and, per line family, its lines to check (what the maps sum and the spectrum marks); hovering a cell highlights that element's lines in the spectrum.
struct PeriodicTableView: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var foldedOpen = false
    /// The grid's laid-out width, for the symbol size (the cell size follows it, `PeriodicTableGrid`).
    @State private var width = PeriodicTableGrid.idealWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rotorSpace

    var body: some View {
        VStack(alignment: .leading, spacing: PeriodicTableGrid.gap) {
            PeriodicGridLayout {
                ForEach(Array(PeriodicTableGrid.rows.joined().enumerated()), id: \.offset) { _, z in
                    if let z { cell(z) } else { Color.clear }
                }
            }
            // The fold is a row in the inspector sections' own vocabulary: leading chevron, secondary label, the whole row toggles.
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { foldedOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(foldedOpen ? 90 : 0))
                        .accessibilityHidden(true)
                    Text("Lanthanides and actinides")
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityValue(foldedOpen ? "Expanded" : "Collapsed")
            .padding(.top, 4)
            .help("Lanthanides, and period 7 with the actinides")
            if foldedOpen {
                PeriodicGridLayout {
                    ForEach(PeriodicLayout.folded, id: \.self) { cell($0) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectroscopy.periodicTable")
        // VoiceOver rotor: jump between the mapped elements of a 90-cell table.
        .accessibilityRotor("Mapped") {
            ForEach(model.elements.quantified, id: \.self) { z in
                AccessibilityRotorEntry(Text(PeriodicLayout.symbol(z)), id: z, in: rotorSpace)
            }
        }
    }

    private func cell(_ z: Int) -> some View {
        let state = model.elements.cellState(z)
        let sym = PeriodicLayout.symbol(z)
        let size = PeriodicTableGrid.symbolSize(cell: PeriodicTableGrid.cellSize(width: width))
        // A native Button: Tab (Full Keyboard Access) reaches every cell and Space presses it; the 90+ tab stops are accepted. The
        // plain style adds no padding or hover fill, so the cell looks as it did. An unavailable cell stays enabled on purpose:
        // `.disabled` would dim its own ink and could drop the hover and the right-click reason; its click is already inert in
        // `ElementSelection.click` / `.set`, and it offers no VoiceOver role actions.
        return Button { model.elements.click(z) } label: {
            Text(sym)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.8)   // a two-letter symbol at 9 pt in the narrowest cell (11.9 pt) sits on the edge
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Self.ink(state))
                .background(RoundedRectangle(cornerRadius: Self.corner).fill(Self.fill(state)))
                .overlay(RoundedRectangle(cornerRadius: Self.corner).strokeBorder(Self.border(state), lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { model.highlightedZ = z } else if model.highlightedZ == z { model.highlightedZ = nil }
        }
        .contextMenu {
            if PeriodicLayout.isAvailable(z) {
                ForEach(ElementRole.allCases, id: \.self) { r in
                    Toggle(r.title, isOn: Binding(get: { model.elements.role(z) == r }, set: { _ in model.elements.set(z, r) }))
                }
                Divider()
                Menu("Lines") {
                    ForEach(LineFamily.allCases, id: \.self) { f in
                        let items = ElementLines.items(family: f, z: z)
                        if !items.isEmpty {
                            // The family row sets the family (the fit takes whole families either way); under it the lines the maps sum
                            // and the spectrum marks.
                            Toggle("\(f.rawValue) lines", isOn: Binding(get: { model.elements.family(z) == f }, set: { _ in model.elements.setFamily(z, f) }))
                            ForEach(items, id: \.id) { item in
                                Toggle(item.title, isOn: Binding(get: { model.elements.checkedLines(z).contains(item.id) },
                                                                 set: { _ in model.elements.toggleLine(z, item.id) }))
                            }
                            Divider()
                        }
                    }
                    Button("Default lines") { model.elements.resetLines(z) }.disabled(!model.elements.hasChosenLines(z))
                }
            } else { Text(ElementSelection.unavailableReason(z: z) ?? "") }
        }
        .help(Self.help(state, sym, proposed: model.elements.suggestions.first { $0.z == z }?.proposedRole))
        .accessibilityLabel(sym)
        .accessibilityValue(Self.describe(state))
        // The right-click roles, as VoiceOver actions (the menu's Lines submenu stays right-click).
        .accessibilityActions {
            ForEach(Self.roleActions(z: z), id: \.self) { r in Button(r.title) { model.elements.set(z, r) } }
        }
        .accessibilityRotorEntry(id: z, in: rotorSpace)
    }

    /// The role actions VoiceOver offers on a cell: the context menu's role rows (none on a not-detectable element).
    static func roleActions(z: Int) -> [ElementRole] {
        PeriodicLayout.isAvailable(z) ? ElementRole.allCases : []
    }

    private static let corner: CGFloat = 3

    // MARK: look

    static func fill(_ s: PeriodicCellState) -> Color {
        switch s {
        case .quantify: .accentColor
        case .off: Color.primary.opacity(0.06)
        case .fitOnly, .suggested, .unavailable: .clear
        }
    }
    static func ink(_ s: PeriodicCellState) -> Color {
        switch s {
        case .quantify: .white
        case .unavailable: Color.primary.opacity(0.25)
        default: .primary
        }
    }
    static func border(_ s: PeriodicCellState) -> Color {
        switch s {
        case .suggested: .accentColor
        case .fitOnly: Color.primary.opacity(0.6)
        default: .clear
        }
    }
    static func help(_ s: PeriodicCellState, _ sym: String, proposed: ElementRole? = nil) -> String {
        switch s {
        case .suggested(let r): "\(sym) · proposed (\(r)) — click to map"
        case .unavailable(let r): "\(sym): \(r)"
        default: "\(sym) · \(describe(s)) — click toggles, right-click for more"
        }
    }
    static func describe(_ s: PeriodicCellState) -> String {
        switch s {
        case .quantify: "mapped"
        case .fitOnly: "fit only"
        case .off: "off"
        case .suggested(let r): "proposed, \(r)"
        case .unavailable: "not detectable"
        }
    }
}

extension PeriodicLayout {
    static func isAvailable(_ z: Int) -> Bool { ElementSelection.unavailableReason(z: z) == nil }
}

#Preview("Periodic table") { PeriodicTableView(model: .fixture).padding().frame(width: 320) }
