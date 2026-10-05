import SwiftUI

/// The periodic table of the Elements & maps inspector (mock screen 4). Click toggles
/// Quantify/Off; right-click gives Quantify · Fit only · Off · Lines ▸ K/L/M. Cell look:
/// filled colour = Quantify, outlined = Fit only, dotted + "?" = suggested (with its
/// reason as help), plain = Off, faint = unavailable.
struct PeriodicTableView: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var fBlockOpen = false

    static let cell: CGFloat = 16, gap: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            suggestionBubbles
            ZStack(alignment: .topLeading) {
                ForEach(1...118, id: \.self) { z in
                    let p = PeriodicLayout.position(z)
                    if !PeriodicLayout.isFBlock(z) || fBlockOpen {
                        cell(z).offset(x: CGFloat(p.column) * (Self.cell + Self.gap),
                                       y: (p.row > 6 ? Double(p.row) + 0.5 : Double(p.row)) * (Self.cell + Self.gap))
                    }
                }
            }
            .frame(width: 18 * (Self.cell + Self.gap), height: (fBlockOpen ? 9.5 : 7) * (Self.cell + Self.gap), alignment: .topLeading)
            DisclosureGroup(isExpanded: $fBlockOpen) { EmptyView() } label: {
                Text("Lanthanides · actinides").font(.caption2).foregroundStyle(.secondary)
            }.font(.caption2)
            legend
        }
    }

    @ViewBuilder private var suggestionBubbles: some View {
        let s = model.elements.suggestions
        if !s.isEmpty {
            HStack(spacing: 4) {
                ForEach(s, id: \.z) { Text($0.reason).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.1))) }
            }
        }
    }

    private func cell(_ z: Int) -> some View {
        let state = model.elements.cellState(z)
        let sym = PeriodicLayout.symbol(z)
        return Text(sym)
            .font(.system(size: 8.5, weight: .semibold))
            .frame(width: Self.cell, height: Self.cell)
            .foregroundStyle(Self.ink(state))
            .background(RoundedRectangle(cornerRadius: 3).fill(Self.fill(state, z)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Self.border(state), style: Self.borderStyle(state)))
            .overlay(alignment: .topTrailing) {
                if case .suggested = state { Text("?").font(.system(size: 7, weight: .bold)).foregroundStyle(.orange).offset(x: 2, y: -4) }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.elements.click(z) }
            .contextMenu {
                if PeriodicLayout.isAvailable(z) {
                    ForEach(ElementRole.allCases, id: \.self) { r in
                        Toggle(r.title, isOn: Binding(get: { model.elements.role(z) == r },
                                                       set: { _ in model.elements.set(z, r) }))
                    }
                    Divider()
                    Menu("Lines") {
                        ForEach(LineFamily.allCases, id: \.self) { f in
                            Toggle(f.rawValue, isOn: Binding(get: { model.elements.family(z) == f },
                                                              set: { _ in model.elements.setFamily(z, f) }))
                        }
                    }
                } else { Text(ElementSelection.unavailableReason(z: z) ?? "") }
            }
            .help(Self.help(state, sym))
            .accessibilityLabel("\(sym), \(Self.describe(state))")
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(.quantify, "Quantify"); legendItem(.fitOnly, "Fit only")
            legendItem(.suggested(""), "Suggested ?"); legendItem(.off, "Off")
        }.font(.caption2).foregroundStyle(.secondary)
    }
    private func legendItem(_ s: PeriodicCellState, _ t: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(Self.fill(s, 12))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Self.border(s), style: Self.borderStyle(s)))
                .frame(width: 9, height: 9)
            Text(t)
        }
    }

    static func fill(_ s: PeriodicCellState, _ z: Int) -> Color {
        switch s {
        case .quantify: ElementPalette.color(z)
        case .fitOnly, .suggested: Color.clear
        case .off: Color.primary.opacity(0.06)
        case .unavailable: .clear
        }
    }
    static func ink(_ s: PeriodicCellState) -> Color {
        switch s { case .quantify: .white; case .unavailable: Color.primary.opacity(0.25); default: .primary }
    }
    static func border(_ s: PeriodicCellState) -> Color {
        switch s { case .fitOnly: Color.primary.opacity(0.6); case .suggested: Color.primary.opacity(0.6)
                   case .off: Color.primary.opacity(0.12); default: .clear }
    }
    static func borderStyle(_ s: PeriodicCellState) -> StrokeStyle {
        if case .suggested = s { return StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5]) }
        return StrokeStyle(lineWidth: 1.2)
    }
    static func help(_ s: PeriodicCellState, _ sym: String) -> String {
        switch s {
        case .suggested(let r): "\(r) — click to quantify"
        case .unavailable(let r): "\(sym): \(r)"
        default: "\(sym) · \(describe(s)) — click toggles, right-click for more"
        }
    }
    static func describe(_ s: PeriodicCellState) -> String {
        switch s { case .quantify: "quantify"; case .fitOnly: "fit only"; case .off: "off"
                   case .suggested(let r): "suggested, \(r)"; case .unavailable: "unavailable" }
    }
}

extension PeriodicLayout {
    static func isAvailable(_ z: Int) -> Bool { ElementSelection.unavailableReason(z: z) == nil }
}

#Preview("Periodic table") { PeriodicTableView(model: .fixture).padding().frame(width: 320) }
