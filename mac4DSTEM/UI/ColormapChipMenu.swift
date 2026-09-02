import SwiftUI
import DSTEMCore
import DSTEMSession

/// D3 (owner decision, 2026-09-01: "colorbar click"): colormap choice lives
/// ON the colorbar chip in each pane — click the gradient you are already
/// looking at, pick from real swatches. This replaced the sidebar's Display
/// row entirely, and dissolves the old Results-workspace scoping problem
/// structurally: the chip exists wherever its pane exists.
///
/// **Popover, not Menu — R23.** The first version used the chip as a `Menu`
/// label; AppKit hosts a menu-button's label itself and does not render a
/// SwiftUI `Canvas` there, so the gradient vanished and the chip degraded to
/// a bare number (owner screenshots, 21:33). A `.popover` is presented
/// SwiftUI-side, so the chip and the swatches render exactly as authored.
struct ColormapChipMenu<Chip: View>: View {
    @Environment(AppState.self) private var appState
    @State private var isPresented = false

    enum Pane { case diffraction, result }
    let pane: Pane
    @ViewBuilder var chip: () -> Chip

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            chip()
        }
        .buttonStyle(.plain)
        .help(pane == .diffraction
              ? "Colormap and display options for the diffraction pattern"
              : "Colormap for the result image")
        .accessibilityLabel(pane == .diffraction
                            ? "Diffraction colormap and display options"
                            : "Result colormap")
        .accessibilityIdentifier(pane == .diffraction
                                 ? "pane.colormap.diffraction"
                                 : "pane.colormap.result")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popoverContent
                .padding(12)
                .frame(width: 230)
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 10) {
            let selection = pane == .diffraction
                ? $appState.patternColormap : $appState.resultColormap
            ForEach(ColormapKind.allCases) { kind in
                Button {
                    selection.wrappedValue = kind
                } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: Colormaps.swatch(kind))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        Text(kind.displayName)
                        Spacer(minLength: 4)
                        if selection.wrappedValue == kind {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selection.wrappedValue == kind ? .isSelected : []
                )
            }
            if pane == .diffraction {
                Divider()
                Toggle("Log display", isOn: $appState.logScale)
                if appState.patternScaleMradAvailable {
                    Picker("Q-scale units", selection: $appState.patternScaleUnit) {
                        ForEach(PatternScaleUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}
