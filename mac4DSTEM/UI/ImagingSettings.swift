import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Imaging's inspector Settings tab: the virtual detector and the reciprocal
/// region, whichever direction is chosen. UI rule 7 forbids reading
/// `AppState.activePane` silently, so the first row is an explicit `Picker`
/// bound to it. Body is inspector-vocabulary rows (`UI/InspectorRows.swift`);
/// the untitled top row stays a bare row with no `Section` header.
struct ImagingSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        @Bindable var resultPresentation = appState.resultPresentation

        Group {
        // Segmented control; the geometry each choice applies is its own
        // glyph (owner decision). A four-segment menu once needed 250 pt in
        // a 283 pt column; this row has two segments and the inspector
        // starts at 280 pt, so a segmented control fits directly. The pane
        // it drives also carries an accent outline, so the setting and the
        // pane agree on screen. Headerless card: a bare row above the first
        // card read as loose (driven, 2026-09-22).
        InspectorGroup {
            InspectorRow("Direction") {
                Picker("Direction", selection: $appState.activePane) {
                    // Words, not shape glyphs: what the drag controls must
                    // read at a glance.
                    Text("Detector")
                        .accessibilityLabel("Detector to real space")
                        .tag(ActivePane.diffraction)
                    Text("Region")
                        .accessibilityLabel("Region to diffraction")
                        .tag(ActivePane.realSpace)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("What dragging on the panes controls: the virtual detector that produces the real-space image, or the scan region that produces the diffraction pattern.")
                .accessibilityIdentifier("imaging.direction")
            }
        }

        if appState.activePane == .diffraction {
            InspectorSection("Detector → real space") {
                InspectorRow("Shape") {
                    Picker("Detector shape", selection: $resultPresentation.virtualShape) {
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
                    // The hidden title is the spoken name; an .accessibilityLabel is appended to it ("Shape, Detector shape").
                }
                // Conventional STEM abbreviations; full names in the
                // buttons' help and accessibility labels.
                InspectorRow("Preset") {
                    // Glyph + abbreviation when the column has room, the
                    // abbreviation alone when it does not — never "A…" /
                    // "H…" (915-pt drive, 2026-09-22): the letters name the
                    // detector, the ring only illustrates it.
                    ViewThatFits(in: .horizontal) {
                        presetButtons(showsGlyph: true)
                        presetButtons(showsGlyph: false)
                    }
                    .labelsHidden()
                }
                if let descriptor = appState.descriptor {
                    apertureRows(shape: resultPresentation.virtualShape, descriptor: descriptor)
                }
                InspectorNote("Drag the detector on the diffraction pane, or type its centre and radii; the real-space image updates live.")
                if appState.presetProbeRadius == nil {
                    InspectorNote("Presets use detector fractions — measure the beam in Prepare to fit them.")
                }
            }
        } else {
            InspectorSection("Region to diffraction") {
                InspectorRow("Shape") {
                    Picker("Region shape", selection: $appState.realSpaceShape) {
                        // Words, not glyphs: three segments fit, and a bare square or circle names neither the point nor the
                        // region it selects (design review 2026-10-21).
                        ForEach(RegionShape.allCases) { shape in
                            Text(shape.rawValue)
                                .tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("The scan region summed into the diffraction pattern: "
                          + "one position, a rectangle, or a circle.")
                }

                if appState.realSpaceShape != .point, let d = appState.descriptor {
                    AdjustmentSlider(
                        appState.realSpaceShape == .rectangle ? "Half-width" : "Radius",
                        value: Binding(
                            get: { Double(appState.realSpaceRadius) },
                            set: { appState.realSpaceRadius = Float($0) }
                        ),
                        in: 1...Double(max(d.rx, d.ry) / 2),
                        format: .number.precision(.fractionLength(0)),
                        unit: "px"
                    )
                    .accessibilityLabel(appState.realSpaceShape == .rectangle ? "Region half-width in pixels" : "Region radius in pixels")
                }
                InspectorNote(appState.realSpaceShape == .point
                     ? "Drag on the real-space image to scrub the diffraction pattern."
                     : "Drag the region on the real-space image; the summed pattern updates live.")
            }
        }
        }
        .disabledWhileRunning(appState)
    }

    /// The detector's centre and radii as numbers, for the shape chosen: the keyboard's way to what the handles do. A typed
    /// value or a stepper click takes the drag's own path (`ApertureEntry`: the same snap, then the same two `AppState` calls),
    /// so 70.4 typed is 70 dragged. The field commits on Return or focus loss (`NumericField`, locale-safe entry through
    /// `DecimalEntryFormat`), never per keystroke: a recompute of the image per digit would run on every partial number. The
    /// stepper moves one pixel a click (a deliberate edit each, so each commits), and stops at the detector's edge.
    @ViewBuilder
    private func apertureRows(shape: VirtualShapeMode, descriptor: DatasetDescriptor) -> some View {
        ForEach(ApertureEntry.fields(for: shape), id: \.self) { field in
            let name = ApertureEntry.spokenName(for: field, shape: shape)
            let value = Binding(
                get: { ApertureEntry.value(of: field, in: appState.aperture) },
                set: { ApertureEntry.apply($0, to: field, in: appState,
                                           patternWidth: descriptor.qx, patternHeight: descriptor.qy) })
            InspectorRow(ApertureEntry.label(for: field, shape: shape)) {
                HStack(spacing: 4) {
                    NumericField(name, value: value, format: .number.precision(.fractionLength(0...1)), unit: "px")
                        .labelsHidden()
                    // Named through its hidden title: on macOS a titled Stepper APPENDS an accessibilityLabel to it ("X, X").
                    Stepper(name, value: value,
                            in: ApertureEntry.range(of: field, in: appState.aperture,
                                                    patternWidth: descriptor.qx, patternHeight: descriptor.qy),
                            step: 1)
                        .labelsHidden()
                }
            }
            .accessibilityIdentifier("imaging.aperture.\(field)")
        }
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

    /// The three preset buttons; `showsGlyph` false is the narrow fallback.
    @ViewBuilder
    private func presetButtons(showsGlyph: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach([DetectorPreset.brightField, .adf, .haadf]) { preset in
                Button {
                    appState.applyDetectorPreset(preset)
                } label: {
                    // The abbreviation AND the geometry it sets: BF, ADF and
                    // HAADF differ only by radii, so the ring each one draws
                    // is the fastest read.
                    if showsGlyph {
                        Label {
                            Text(Self.shortName(preset))
                        } icon: {
                            Image(systemName: Self.symbol(preset))
                        }
                    } else {
                        Text(Self.shortName(preset))
                    }
                }
                .controlSize(.small)
                .fixedSize()
                .help("Set the detector to \(preset.rawValue)")
                .accessibilityLabel("Apply \(preset.rawValue) preset")
                .accessibilityIdentifier(
                    "detector.preset.\(Self.shortName(preset).lowercased())"
                )
            }
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
