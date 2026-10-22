import ShellInspector
import ShellSpectroscopy
import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import SpectroCore
import SpectroEDX
#endif

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

/// The periodic table of the Elements section (ADR 056, spec 2 D-9), MacEMUI's `PeriodicTable` answered from the room: states by fill only, no legend; click toggles
/// Quantify / Off; right-click gives the role and, per line family, its lines to check (what the maps sum and the spectrum marks); hovering a cell highlights that
/// element's lines in the spectrum.
struct SpectroscopyPeriodicTable: View {
    @Bindable var model: SpectroscopyRoomModel

    var body: some View {
        PeriodicTable(actions: Self.actions(model))
            .accessibilityIdentifier("spectroscopy.periodicTable")
    }

    /// Every question the table asks and every change it reports, in the room's words.
    static func actions(_ model: SpectroscopyRoomModel) -> PeriodicTableActions {
        PeriodicTableActions(
            state: { cellState(model.elements.cellState($0)) },
            role: { ElementRoleChoice(rawValue: model.elements.role($0).rawValue) ?? .off },
            click: { pick(model, $0) },
            setRole: { z, choice in model.elements.set(z, ElementRole(rawValue: choice.rawValue) ?? .off) },
            hover: { z in
                model.highlightedZ = z
            },
            families: { z in
                LineFamily.allCases.compactMap { f in
                    let items = ElementLines.items(family: f, z: z)
                    guard !items.isEmpty else { return nil }
                    return ElementLineFamily(family: f.rawValue, isSelected: model.elements.family(z) == f,
                                             lines: items.map { ElementLineChoice(id: $0.id, title: $0.title, isChecked: model.elements.checkedLines(z).contains($0.id)) })
                }
            },
            setFamily: { z, family in if let f = LineFamily(rawValue: family) { model.elements.setFamily(z, f) } },
            toggleLine: { z, id in model.elements.toggleLine(z, id) },
            resetLines: { model.elements.resetLines($0) },
            hasChosenLines: { model.elements.hasChosenLines($0) },
            mapped: { model.elements.quantified })
    }

    /// The room's cell state as MacEMUI's.
    static func cellState(_ s: PeriodicCellState) -> ShellSpectroscopy.PeriodicCellState {
        switch s {
        case .quantify: .quantify
        case .fitOnly: .fitOnly
        case .off: .off
        case .suggested(let r): .suggested(r)
        case .unavailable(let r): .unavailable(r)
        }
    }

    /// A click on a cell: its role flips as before, and the element becomes the selected one (the rows under the table) when it can
    /// be picked at all.
    static func pick(_ model: SpectroscopyRoomModel, _ z: Int) {
        model.elements.click(z)
        if PeriodicLayout.isAvailable(z) { model.selectedElement = z }
    }
}

/// "Lines": per line family, the family row and a checkable item per line the table has, then "Default lines". The right-click
/// menu's submenu and the Selected element rows' menu are this one view.
struct ElementLinesMenu: View {
    @Bindable var model: SpectroscopyRoomModel
    let z: Int
    var title = "Lines"
    var body: some View {
        Menu(title) {
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
    }
}

/// The Elements section's "selected element" rows: the right-click menu's role and lines as rows, so Fit only and the per-line
/// choice are reachable without a secondary click (HIG, Context menus: every menu command also has a visible home).
struct SelectedElementRows: View {
    @Bindable var model: SpectroscopyRoomModel

    /// The element the rows act on: the last clicked, while it can still be picked.
    static func shown(_ model: SpectroscopyRoomModel) -> Int? {
        model.selectedElement.flatMap { PeriodicLayout.isAvailable($0) ? $0 : nil }
    }
    /// "default" until the person chose a family or lines for this element.
    static func linesSummary(_ model: SpectroscopyRoomModel, _ z: Int) -> String {
        guard model.elements.hasChosenLines(z) else { return "Default" }
        return "\(model.elements.family(z).rawValue) \u{00B7} \(model.elements.checkedLines(z).count)"
    }

    var body: some View {
        if let z = Self.shown(model) {
            let sym = PeriodicLayout.symbol(z)
            InspectorRow("\(sym) role") {
                Picker("\(sym) role", selection: Binding(get: { model.elements.role(z) }, set: { model.elements.set(z, $0) })) {
                    ForEach(ElementRole.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
                .help("Quantify: mapped and given an at%. Fit only: its lines are modelled, it gets no at%. Off: neither.")
                .accessibilityIdentifier("spectroscopy.selectedElement.role")
            }
            InspectorRow("\(sym) lines") {
                ElementLinesMenu(model: model, z: z, title: Self.linesSummary(model, z))
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Which lines the maps sum and the spectrum marks; the fit takes whole families.")
                    .accessibilityIdentifier("spectroscopy.selectedElement.lines")
            }
        }
    }
}

extension PeriodicLayout {
    static func isAvailable(_ z: Int) -> Bool { ElementSelection.unavailableReason(z: z) == nil }
}

#Preview("Periodic table") { SpectroscopyPeriodicTable(model: .fixture).padding().frame(width: 320) }
