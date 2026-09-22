import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Imaging's inspector Settings tab: the virtual detector and the reciprocal
/// region, whichever direction is chosen. The old `ImageSidebar` switched
/// between the two on `AppState.activePane` with no control the user could
/// see; UI rule 7 forbids reading that implicit mode silently, so the first
/// row here is an explicit `Picker` bound to it. Body is inspector-vocabulary
/// rows (`UI/InspectorRows.swift`) for the caller's inspector scroll
/// container; the untitled top row had no `Section` header before this
/// conversion either, so it stays a bare row rather than gaining one.
struct ImagingSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        @Bindable var resultPresentation = appState.resultPresentation

        Group {
        // Segmented, with the geometry each choice applies as its glyph
        // (owner, 2026-09-04). The old sidebar used a menu because a
        // four-segment row held a 250 pt column at 283 pt; the inspector
        // starts at 280 pt and this row has two segments, so the reason
        // is gone. The pane that this choice drives also carries an
        // accent outline, so the setting and the pane agree on screen.
        InspectorRow("Direction") {
            Picker("Direction", selection: $appState.activePane) {
                Image(systemName: "circle.dashed")
                    .accessibilityLabel("Detector to real space")
                    .tag(ActivePane.diffraction)
                Image(systemName: "square.dashed")
                    .accessibilityLabel("Region to diffraction")
                    .tag(ActivePane.realSpace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("What dragging on the panes controls: the virtual detector that produces the real-space image, or the scan region that produces the diffraction pattern.")
            .accessibilityIdentifier("imaging.direction")
        }

        if appState.activePane == .diffraction {
            InspectorSection("Detector → real space", systemImage: "circle.dashed") {
                InspectorRow("Shape") {
                    Picker("Shape", selection: $resultPresentation.virtualShape) {
                        ForEach(VirtualShapeMode.allCases) { shape in
                            Image(systemName: Self.symbol(shape))
                                .accessibilityLabel(shape.rawValue)
                                .tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("The detector geometry drawn on the diffraction pane: "
                          + "circle, annulus, rectangle, or a single pixel.")
                    .accessibilityLabel("Detector shape")
                }
                // Conventional STEM abbreviations; full names in the
                // buttons' help and accessibility labels.
                InspectorRow("Preset") {
                    HStack(spacing: 6) {
                        ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                            Button {
                                appState.applyDetectorPreset(preset)
                            } label: {
                                // The abbreviation AND the geometry it sets:
                                // BF, ADF and HAADF differ only by radii, so
                                // the ring each one draws is the fastest read.
                                Label {
                                    Text(Self.shortName(preset))
                                } icon: {
                                    Image(systemName: Self.symbol(preset))
                                }
                            }
                            .controlSize(.small)
                            .help("Set the detector to \(preset.rawValue)")
                            .accessibilityLabel("Apply \(preset.rawValue) preset")
                            .accessibilityIdentifier(
                                "detector.preset.\(Self.shortName(preset).lowercased())"
                            )
                        }
                    }
                    .labelsHidden()
                }
                InspectorNote("Drag the detector on the diffraction pane; the real-space image updates live.")
            }
        } else {
            InspectorSection("Region → diffraction", systemImage: "square.dashed") {
                InspectorRow("Shape") {
                    Picker("Shape", selection: $appState.realSpaceShape) {
                        ForEach(RegionShape.allCases) { shape in
                            Image(systemName: Self.symbol(shape))
                                .accessibilityLabel(shape.rawValue)
                                .tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("The scan region summed into the diffraction pattern: "
                          + "one position, a rectangle, or a circle.")
                    .accessibilityLabel("Region shape")
                }

                if appState.realSpaceShape != .point, let d = appState.descriptor {
                    AdjustmentSlider(
                        "Radius",
                        value: Binding(
                            get: { Double(appState.realSpaceRadius) },
                            set: { appState.realSpaceRadius = Float($0) }
                        ),
                        in: 1...Double(max(d.rx, d.ry) / 2),
                        format: .number.precision(.fractionLength(0)),
                        unit: "px"
                    )
                    .accessibilityLabel("Region radius in pixels")
                }
                InspectorNote(appState.realSpaceShape == .point
                     ? "Drag on the real-space image to scrub the diffraction pattern."
                     : "Drag the region on the real-space image; the summed pattern updates live.")
            }
        }
        }
        .disabledWhileRunning(appState)
    }

    /// The glyph for each geometry. Lives here rather than on the Core types
    /// because `Core/` stays free of presentation concerns.
    static func symbol(_ shape: VirtualShapeMode) -> String {
        switch shape {
        case .circle: "circle"
        case .annulus: "circle.circle"
        case .rectangle: "square"
        case .point: "smallcircle.filled.circle"
        }
    }

    static func symbol(_ shape: RegionShape) -> String {
        switch shape {
        case .point: "smallcircle.filled.circle"
        case .rectangle: "square"
        case .circle: "circle"
        }
    }

    /// Bright field is the central disk; ADF and HAADF are annuli at
    /// increasing angle, which is exactly what `DetectorPreset.radii` sets.
    static func symbol(_ preset: DetectorPreset) -> String {
        switch preset {
        case .brightField: "smallcircle.filled.circle"
        case .adf: "circle.circle"
        case .haadf: "circle.dashed.inset.filled"
        case .custom: "circle.dotted"
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
