import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Imaging's sidebar (v2.5 step 7c slice 3, plan §11d): the virtual detector
/// and the reciprocal region, whichever pane is active. Imaging has one task
/// (`.virtualDetector`), so nothing here switches on the task. One file per
/// workspace sidebar.
struct ImageSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        ComputePatternStatisticsSection()
        if appState.activePane == .diffraction {
            Section("Detector → real space") {
                // The shape picker gets the row's full width — an inline
                // "Shape" label left four segments fighting over what was
                // left of a 292pt column.
                Picker("Detector shape", selection: $appState.virtualShape) {
                    ForEach(VirtualShapeMode.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Detector shape")

                // One compact row of conventional STEM abbreviations, not
                // three stacked full-width buttons. Full names stay in the
                // tooltip and in the accessibility label.
                HStack(spacing: 6) {
                    Text("Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                        Button(Self.shortName(preset)) {
                            appState.applyDetectorPreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Set the detector to a \(preset.rawValue) annulus")
                        .accessibilityLabel("Apply \(preset.rawValue) preset")
                        .accessibilityIdentifier(
                            "detector.preset.\(Self.shortName(preset).lowercased())"
                        )
                    }
                }
            }
            .help("Drag the detector on the diffraction pane; the real-space image updates live.")
        } else {
            Section("Region → diffraction") {
                Picker("Region shape", selection: $appState.realSpaceShape) {
                    ForEach(RegionShape.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Region shape")

                if appState.realSpaceShape != .point, let d = appState.descriptor {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Radius").font(.caption)
                            Spacer()
                            Text("\(Int(appState.realSpaceRadius)) px")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $appState.realSpaceRadius,
                               in: 1...Float(max(d.rx, d.ry) / 2))
                        .accessibilityLabel("Region radius in pixels")
                    }
                }
                Text(appState.realSpaceShape == .point
                     ? "Drag on the real-space image to scrub the diffraction pattern."
                     : "Drag the region on the real-space image; the summed pattern updates live.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Conventional STEM abbreviations, so three presets fit one sidebar row.
    /// Lives here rather than on `DetectorPreset` because that type is in
    /// `Core/`, which stays free of presentation concerns.
    static func shortName(_ preset: DetectorPreset) -> String {
        switch preset {
        case .brightField: "BF"
        case .adf: "ADF"
        case .haadf: "HAADF"
        case .custom: "Custom"
        }
    }
}
