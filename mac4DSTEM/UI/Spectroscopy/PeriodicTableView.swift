import SwiftUI

/// The periodic table of the Elements section (ADR 056, mock v2.1): two bands, main groups over transition metals, the rest
/// folded. States by fill only, no legend: mapped (accent fill), proposed (accent outline), fit only (hollow), off (a quiet
/// well), not detectable (dim). Click toggles Quantify / Off, or accepts a proposal; right-click gives the role and the line
/// family; the state and its reason are the cell's help.
struct PeriodicTableView: View {
    @Bindable var model: SpectroscopyRoomModel
    @State private var foldedOpen = false

    /// A 10-column band of 22-pt cells and 2-pt gaps is 238 pt, inside the inspector's narrowest content column, 248 pt
    /// (`InspectorWidthBudgetTests`); ADR 056 asked for about 22 pt, symbols 11 pt (UX lane DE #9).
    enum Metrics {
        static let cell: CGFloat = 22, gap: CGFloat = 2, corner: CGFloat = 4, symbolSize: CGFloat = 11
        static var bandWidth: CGFloat { CGFloat(PeriodicLayout.transitionColumns) * (cell + gap) - gap }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            band(PeriodicLayout.mainGroup, columns: PeriodicLayout.mainGroupColumns)
            band(PeriodicLayout.transition, columns: PeriodicLayout.transitionColumns)
            // The fold is a row in the inspector sections' own vocabulary: leading chevron, secondary label, the whole row toggles.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { foldedOpen.toggle() }
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
                let perRow = PeriodicLayout.transitionColumns
                ForEach(Array(stride(from: 0, to: PeriodicLayout.folded.count, by: perRow)), id: \.self) { start in
                    HStack(spacing: Metrics.gap) {
                        ForEach(PeriodicLayout.folded[start..<min(start + perRow, PeriodicLayout.folded.count)], id: \.self) { cell($0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectroscopy.periodicTable")
    }

    private func band(_ rows: [[Int?]], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Metrics.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, z in
                        if let z { cell(z) } else { Color.clear.frame(width: Metrics.cell, height: Metrics.cell) }
                    }
                }
            }
        }
        .frame(width: Metrics.bandWidth, alignment: .center)
    }

    private func cell(_ z: Int) -> some View {
        let state = model.elements.cellState(z)
        let sym = PeriodicLayout.symbol(z)
        return Text(sym)
            .font(.system(size: Metrics.symbolSize, weight: .semibold))
            .frame(width: Metrics.cell, height: Metrics.cell)
            .foregroundStyle(Self.ink(state))
            .background(RoundedRectangle(cornerRadius: Metrics.corner).fill(Self.fill(state)))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner).strokeBorder(Self.border(state), lineWidth: 1.2))
            .contentShape(Rectangle())
            .onTapGesture { model.elements.click(z) }
            .contextMenu {
                if PeriodicLayout.isAvailable(z) {
                    ForEach(ElementRole.allCases, id: \.self) { r in
                        Toggle(r.title, isOn: Binding(get: { model.elements.role(z) == r }, set: { _ in model.elements.set(z, r) }))
                    }
                    Divider()
                    Menu("Lines") {
                        ForEach(LineFamily.allCases, id: \.self) { f in
                            Toggle(f.rawValue, isOn: Binding(get: { model.elements.family(z) == f }, set: { _ in model.elements.setFamily(z, f) }))
                        }
                    }
                } else { Text(ElementSelection.unavailableReason(z: z) ?? "") }
            }
            .help(Self.help(state, sym, proposed: model.elements.suggestions.first { $0.z == z }?.proposedRole))
            .accessibilityLabel("\(sym), \(Self.describe(state))")
            .accessibilityAddTraits(.isButton)
    }

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

#Preview("Periodic table") { PeriodicTableView(model: .fixture).padding().frame(width: 280) }
