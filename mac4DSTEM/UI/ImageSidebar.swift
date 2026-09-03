import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Imaging's sidebar (v2.5 step 7c slice 3, plan §11d): the virtual detector
/// and the reciprocal region, whichever pane is active. Imaging has one task
/// (`.virtualDetector`), so nothing here switches on the task. Sections of
/// the column's grouped `Form` (presentation contract rule 2). One file per
/// workspace sidebar.
struct ImageSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        ComputePatternStatisticsSection()
        if appState.activePane == .diffraction {
            Section("Detector → real space") {
                // A menu, not four segments: the segmented row held the
                // column at 283 pt (rule 5, measured 2026-09-03).
                Picker("Shape", selection: $appState.virtualShape) {
                    ForEach(VirtualShapeMode.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .accessibilityLabel("Detector shape")
                // Conventional STEM abbreviations; full names in the menu's
                // help and accessibility labels.
                LabeledContent("Preset") {
                    Menu {
                        ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                            Button("\(Self.shortName(preset)) — \(preset.rawValue)") {
                                appState.applyDetectorPreset(preset)
                            }
                            .accessibilityLabel("Apply \(preset.rawValue) preset")
                            .accessibilityIdentifier(
                                "detector.preset.\(Self.shortName(preset).lowercased())"
                            )
                        }
                    } label: {
                        Text("Apply")
                    }
                    .fixedSize()
                    .help("Set the detector to a bright-field, ADF or HAADF annulus")
                }
                Text("Drag the detector on the diffraction pane; the real-space image updates live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Region → diffraction") {
                Picker("Shape", selection: $appState.realSpaceShape) {
                    ForEach(RegionShape.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .accessibilityLabel("Region shape")

                if appState.realSpaceShape != .point, let d = appState.descriptor {
                    Slider(value: $appState.realSpaceRadius,
                           in: 1...Float(max(d.rx, d.ry) / 2)) {
                        Text("Radius, \(Int(appState.realSpaceRadius)) px")
                    }
                    .accessibilityLabel("Region radius in pixels")
                }
                Text(appState.realSpaceShape == .point
                     ? "Drag on the real-space image to scrub the diffraction pattern."
                     : "Drag the region on the real-space image; the summed pattern updates live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Conventional STEM abbreviations. Lives here rather than on
    /// `DetectorPreset` because that type is in `Core/`, which stays free of
    /// presentation concerns.
    static func shortName(_ preset: DetectorPreset) -> String {
        switch preset {
        case .brightField: "BF"
        case .adf: "ADF"
        case .haadf: "HAADF"
        case .custom: "Custom"
        }
    }
}
