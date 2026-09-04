//
//  UI2PaneOverlays.swift
//  Role: everything UI2 draws ON TOP of a scientific image — the pane footer
//        that carries the scale bar and the colour legend, the interactive
//        virtual-detector overlay, the Bragg-disk and fit-verification marks,
//        and the two inverse-pole-figure keys.
//
//  This is the ONE UI2 file where custom drawing is expected. Every number in
//  it is DRAWING GEOMETRY, not layout: the length of a quantized scale bar,
//  the 132 x 9 pt colour strip, the 116 x 62 pt IPF triangle, a 12 pt drag
//  handle, a 4 pt cross arm. None of it is chrome, and none of it sizes text
//  for a form — UI2Metrics still owns every layout number in UI2.
//
//  Geometry is science. The detector-coordinate map (pixel CENTRES, the
//  `dx = Float(x) - centerX` convention `VirtualDetector`'s mask uses) is
//  `PeakOverlayGeometry`, shared verbatim with the old panes; the drag
//  handles, their hit targets, the snap-and-clamp chokepoint and the fit
//  overlay's colour vocabulary (orange prediction / red calibration /
//  green measured) are ported without re-derivation.
//

import SwiftUI
import simd
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// MARK: - Pane footer

/// The bottom overlay row of an image pane: the scale bar at the leading edge,
/// the colour legend at the trailing edge.
///
/// Both used to be independent `bottomLeading` / `bottomTrailing` overlays in
/// the same ZStack, each unaware of the other. On a tall, narrow pane there is
/// not enough width for both — a 200x50 scan with a display rotation applied
/// put the `-0.04145 0 0.04145` colorbar straight through the `20 [pix]` scale
/// bar (found on a Track B drive; fixed in v2 S18). The legend is 146pt wide
/// before its label, and the bar is quantized to ~70pt of *drawn* length plus
/// its own caption, so the collision is a property of the width of the **drawn
/// image box** — `UI2Metrics.fitted(in:aspect:)`, which this overlay sits
/// inside — and NOT of the pane. For a square pattern in a pane taller than it
/// is wide the two coincide; for a rotated tall-narrow scan the box stays
/// narrow at any divider position, so that pane is stacked always and
/// correctly.
///
/// `ViewThatFits` picks side-by-side while both ideal widths fit and stacks
/// them otherwise, which keeps the wide case pixel-identical to what shipped
/// and makes the narrow case legible instead of overlapping.
struct UI2PaneFooter<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            // Legend above bar: the legend is the taller, fixed-width block, so
            // stacking it on top keeps the bar against the pane's bottom-left
            // corner where it sits in the wide case.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) { Spacer(minLength: 0); trailing }
                leading
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Scale bar

/// Calibrated scale bar overlay for the image panes. Picks a "nice" 1-2-5
/// length near a target on-screen size, so it re-quantizes as the user zooms.
/// Falls back to pixel units when no calibration exists — an uncalibrated bar
/// labelled "px" is still honest and useful.
struct UI2ScaleBar: View {
    /// Physical units per screen POINT at the current zoom
    /// (= pixelSize * imagePixels / (fittedWidthPoints * zoom)).
    let unitsPerPoint: Double
    /// Unit label ("nm", "1/nm", "px", …).
    let unitLabel: String

    private static let targetPoints = 70.0

    var body: some View {
        if unitsPerPoint > 0, unitsPerPoint.isFinite {
            let nice = Self.nice125(unitsPerPoint * Self.targetPoints)
            let lengthPt = CGFloat(nice / unitsPerPoint)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Self.format(nice)) \(unitLabel)")
                Rectangle()
                    .frame(width: lengthPt, height: 2)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            // Legibility plate: this sits on top of arbitrary scientific
            // image data, where white-on-white is unreadable. Not chrome.
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
            .allowsHitTesting(false)
        }
    }

    /// Round to the nearest 1 / 2 / 5 × 10ⁿ.
    static func nice125(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let exponent = floor(log10(value))
        let base = pow(10, exponent)
        let mantissa = value / base
        let nice: Double = mantissa < 1.5 ? 1 : (mantissa < 3.5 ? 2 : (mantissa < 7.5 ? 5 : 10))
        return nice * base
    }

    static func format(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f", value) }
        if value >= 1 { return String(format: "%g", value) }
        return String(format: "%.3g", value)
    }
}

// MARK: - Colorbar

/// Numeric scalar legend for the exact colormap and contrast window displayed
/// by a pane. Pre-colored scientific images use their own directional keys.
struct UI2Colorbar: View {
    let colormap: ColormapKind
    let low: Double
    let high: Double
    let unitLabel: String
    var gamma: Float = 1
    var marksZero = false
    /// True when the displayed image contains masked (no-data) pixels, which
    /// render as neutral gray; adds a swatch so the gray is self-explanatory.
    var showsMasked = false

    /// Drawing geometry: the width of the colour strip and of the numeric row
    /// under it, which must agree so the end labels sit at the strip's ends.
    private static let stripWidth: CGFloat = 132
    private static let stripHeight: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                let lut = Colormaps.lutRGBA(colormap, count: 128)
                let stripWidth = size.width / 128
                for index in 0..<128 {
                    let fraction = Float(index) / 127
                    let mapped = pow(fraction, 1 / max(gamma, 0.05))
                    let lutIndex = min(127, Int((mapped * 127).rounded()))
                    let offset = lutIndex * 4
                    let color = Color(
                        red: Double(lut[offset]) / 255,
                        green: Double(lut[offset + 1]) / 255,
                        blue: Double(lut[offset + 2]) / 255
                    )
                    context.fill(Path(CGRect(x: CGFloat(index) * stripWidth, y: 0,
                                             width: stripWidth + 0.5, height: size.height)),
                                 with: .color(color))
                }
                if marksZero, low < 0, high > 0 {
                    let fraction = CGFloat(-low / (high - low))
                    let x = fraction * size.width
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }, with: .color(.white), lineWidth: 1)
                }
            }
            .frame(width: Self.stripWidth, height: Self.stripHeight)
            .overlay(RoundedRectangle(cornerRadius: 1)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5))

            HStack(spacing: 4) {
                Text(Self.format(low))
                Spacer()
                if marksZero, low < 0, high > 0 { Text("0") }
                Spacer()
                Text(Self.format(high))
            }
            .frame(width: Self.stripWidth)
            if !unitLabel.isEmpty {
                Text(unitLabel)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if showsMasked {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        // The exact neutral gray the renderer writes for a
                        // masked (no-fit) pixel — a scientific key, not a tint.
                        .fill(Color(red: 0.32, green: 0.32, blue: 0.34))
                        .frame(width: 10, height: 7)
                        .overlay(RoundedRectangle(cornerRadius: 1)
                            .stroke(Color.white.opacity(0.45), lineWidth: 0.5))
                    Text("masked · no fit")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        // Legibility plate over the image, as on the scale bar.
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
        // R23 (2026-09-02, diagnosed live): this view is the LABEL of
        // `UI2ColormapChip`'s button. `.allowsHitTesting(false)` here made the
        // button's whole area transparent to real clicks — AXPress opened the
        // popover, a click inside the button's own 146×51 pt frame did not.
        // Plain (non-button) uses opt out at their call site instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color scale from \(Self.format(low)) to \(Self.format(high)) \(unitLabel)"
                            + (showsMasked ? ", gray marks masked pixels with no fit" : ""))
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 10_000 || magnitude < 0.001 {
            return String(format: "%.2e", value)
        }
        return String(format: "%.4g", value)
    }
}

// MARK: - Colormap chip

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
struct UI2ColormapChip<Chip: View>: View {
    @Environment(AppState.self) private var appState
    @State private var isPresented = false

    enum Pane { case diffraction, result }

    let pane: Pane
    private let chip: Chip

    init(pane: Pane, @ViewBuilder chip: () -> Chip) {
        self.pane = pane
        self.chip = chip()
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            chip
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
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(width: UI2Metrics.popoverWidth)
        }
    }

    /// The chip's popover as a grouped Form: the swatch rows the owner asked
    /// for (D3), the IPF confidence gate, and the diffraction display
    /// options, as system rows.
    @ViewBuilder
    private var popoverContent: some View {
        @Bindable var appState = appState
        let selection = pane == .diffraction
            ? $appState.patternColormap : $appState.resultColormap
        Form {
            Section("Colormap") {
                ForEach(ColormapKind.allCases) { kind in
                    Button {
                        selection.wrappedValue = kind
                    } label: {
                        LabeledContent {
                            if selection.wrappedValue == kind {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        } label: {
                            Label {
                                Text(kind.displayName)
                            } icon: {
                                swatch(kind)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selection.wrappedValue == kind ? .isSelected : []
                    )
                }
            }
            if pane == .result, appState.navigation.analysisMode == .acom,
               appState.acomSession.display == .ipfZ, appState.acomSession.orientationMap != nil {
                // v2.5 step 7 (plan §3 item 2): the IPF map's confidence gate
                // lives with the map's colours. Nil = automatic (10th percentile).
                let effective = appState.acomEffectiveReliabilityThreshold ?? 0
                let kept = appState.acomSession.orientationMap?
                    .fractionOfMatchedPositions(withReliabilityAtLeast: effective)
                Section("Confidence gate") {
                    Slider(
                        value: Binding(
                            get: { Double(effective) },
                            set: { appState.acomSession.reliabilityThreshold = Float($0) }),
                        in: 0...1
                    ) {
                        Text(String(format: "Threshold, %.2f", effective))
                    }
                    .accessibilityLabel("Reliability threshold")
                    .accessibilityIdentifier("pane.acom.reliabilityThreshold")
                    if let kept {
                        Text(String(format: "%.0f %% of matched positions kept", kept * 100))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if appState.acomSession.reliabilityThreshold != nil {
                        Button("Automatic") { appState.acomSession.reliabilityThreshold = nil }
                    }
                }
            }
            if pane == .diffraction {
                Section("Display") {
                    Toggle("Log display", isOn: $appState.logScale)
                    if appState.patternScaleMradAvailable {
                        Picker("Q-scale units", selection: $appState.patternScaleUnit) {
                            ForEach(PatternScaleUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                    }
                }
            }
        }
    }

    /// `Colormaps.swatch` is built with AppKit drawing, so this one line is
    /// the file's only platform split; everything else here is portable.
    @ViewBuilder
    private func swatch(_ kind: ColormapKind) -> some View {
        #if os(macOS)
        Image(nsImage: Colormaps.swatch(kind))
            .clipShape(RoundedRectangle(cornerRadius: 2))
        #else
        Image(uiImage: Colormaps.swatch(kind))
            .clipShape(RoundedRectangle(cornerRadius: 2))
        #endif
    }
}

// MARK: - Virtual detector overlay

/// Interactive detector overlay on the CBED view. Renders and lets you drag the
/// active virtual-detector geometry: an annulus (inner/outer radius), a square
/// (half-extent = outer), or a single point. The shape matches the selected
/// `VirtualShapeMode` so what you see is what the kernel integrates.
struct UI2ApertureOverlay: View {
    let aperture: Aperture
    let shape: VirtualShapeMode
    let patternWidth: Int
    let patternHeight: Int
    var onEdited: (Aperture) -> Void
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / CGFloat(max(patternWidth, 1))
            let scaleY = geometry.size.height / CGFloat(max(patternHeight, 1))
            let radiusScale = (scaleX + scaleY) / 2
            // Detector coordinates name pixel CENTRES — `VirtualDetector`'s
            // mask computes `dx = Float(x) - centerX` over integer pixel
            // indices. This used to be a bare `centerX * scaleX`, which drew
            // the aperture at the pixel's top-left corner and read as visibly
            // off-axis on a small detector (reported 2026-08-05). Routed
            // through PeakOverlayGeometry so the half-pixel convention has one
            // definition shared with the Bragg-peak overlay.
            let center = PeakOverlayGeometry.center(
                x: aperture.centerX, y: aperture.centerY,
                patternWidth: patternWidth, patternHeight: patternHeight,
                box: geometry.size
            )

            ZStack {
                switch shape {
                case .circle:    circle(center: center, scaleX: scaleX, scaleY: scaleY, radiusScale: radiusScale)
                case .annulus:   annulus(center: center, scaleX: scaleX, scaleY: scaleY, radiusScale: radiusScale)
                case .rectangle: rectangle(center: center, scaleX: scaleX, scaleY: scaleY, radiusScale: radiusScale)
                case .point:     point(center: center, scaleX: scaleX, scaleY: scaleY)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Virtual detector \(shape.rawValue.lowercased())")
        .accessibilityValue(String(
            format: "center X %.0f, Y %.0f, inner radius %.0f, outer radius %.0f pixels",
            aperture.centerX, aperture.centerY, aperture.inner, aperture.outer
        ))
        .accessibilityRepresentation {
            VStack {
                accessibleSlider("Aperture center X", value: aperture.centerX,
                                 range: 0...Float(max(0, patternWidth - 1))) { $0.centerX = $1 }
                accessibleSlider("Aperture center Y", value: aperture.centerY,
                                 range: 0...Float(max(0, patternHeight - 1))) { $0.centerY = $1 }
                if shape == .annulus {
                    accessibleSlider("Aperture inner radius", value: aperture.inner,
                                     range: 0...max(0, aperture.outer)) { $0.inner = $1 }
                }
                if shape != .point {
                    accessibleSlider("Aperture outer radius", value: aperture.outer,
                                     range: max(1, aperture.inner)...Float(max(patternWidth, patternHeight))) { $0.outer = $1 }
                }
            }
        }
    }

    // MARK: Shapes

    @ViewBuilder
    private func circle(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat, radiusScale: CGFloat) -> some View {
        let outer = CGFloat(aperture.outer) * radiusScale
        Circle()
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
            .frame(width: outer * 2, height: outer * 2)
            .position(center)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
        handle(color: .yellow)
            .position(x: center.x + outer, y: center.y)
            .gesture(circleRadiusDrag(center: center, scale: radiusScale))
    }

    @ViewBuilder
    private func annulus(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat, radiusScale: CGFloat) -> some View {
        let inner = CGFloat(aperture.inner) * radiusScale
        let outer = CGFloat(aperture.outer) * radiusScale
        Circle()
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
            .frame(width: outer * 2, height: outer * 2)
            .position(center)
        Circle()
            .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: inner * 2, height: inner * 2)
            .position(center)
            .opacity(aperture.inner > 0 ? 1 : 0.35)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
        handle(color: .yellow)
            .position(x: center.x + outer, y: center.y)
            .gesture(radiusDrag(center: center, scale: radiusScale, isInner: false))
        handle(color: .cyan)
            .position(x: center.x + inner, y: center.y)
            .gesture(radiusDrag(center: center, scale: radiusScale, isInner: true))
    }

    @ViewBuilder
    private func rectangle(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat, radiusScale: CGFloat) -> some View {
        // The mask kernel uses `outer` as the half-extent of a square detector.
        let half = CGFloat(aperture.outer) * radiusScale
        Rectangle()
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
            .frame(width: half * 2, height: half * 2)
            .position(center)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
        handle(color: .yellow)
            .position(x: center.x + half, y: center.y + half)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        let dx = abs(value.location.x - center.x)
                        let dy = abs(value.location.y - center.y)
                        var updated = aperture
                        updated.outer = max(1, Float(max(dx, dy) / radiusScale))
                        emit(updated)
                    }
                    .onEnded { _ in onCommit() }
            )
    }

    @ViewBuilder
    private func point(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) -> some View {
        // Crosshair marking the single detector pixel.
        Path { p in
            p.move(to: CGPoint(x: center.x - 8, y: center.y)); p.addLine(to: CGPoint(x: center.x + 8, y: center.y))
            p.move(to: CGPoint(x: center.x, y: center.y - 8)); p.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        }
        .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
    }

    // MARK: Handles

    private func centerHandle(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) -> some View {
        handle(color: .white)
            .position(center)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        var updated = aperture
                        // Exact inverse of the draw map, so a drag puts the
                        // centre under the cursor rather than half a pixel up
                        // and to the left of it.
                        let p = PeakOverlayGeometry.pixel(
                            at: value.location,
                            patternWidth: patternWidth, patternHeight: patternHeight,
                            box: CGSize(width: CGFloat(patternWidth) * scaleX,
                                        height: CGFloat(patternHeight) * scaleY)
                        )
                        updated.centerX = min(max(0, p.x), Float(patternWidth))
                        updated.centerY = min(max(0, p.y), Float(patternHeight))
                        emit(updated)
                    }
                    .onEnded { _ in onCommit() }
            )
    }

    /// Snap the geometry to whole detector pixels before publishing — a
    /// virtual detector sums whole pixels, so fractional edges are meaningless.
    ///
    /// **Every handle drag goes through here.** The radius handles used to call
    /// `onEdited` directly, so dragging an inner/outer radius published
    /// fractional pixels while dragging the centre snapped — one control, two
    /// contracts, and the inspector's "Inner r / Outer r" rows showed whichever
    /// handle you happened to have touched last.
    private func emit(_ a: Aperture) {
        var s = a
        // ui-08 (S22e): clamp AFTER rounding. The drag path clamped the raw
        // point to `width`, and rounding the exact right edge (width − 0.5)
        // then published `width` — one past the last pixel, which
        // `VirtualDetector` silently answers with an empty mask. The
        // accessibility sliders already stop at width − 1; now every route
        // through this chokepoint agrees with them.
        s.centerX = min(max(0, s.centerX.rounded()), Float(patternWidth - 1))
        s.centerY = min(max(0, s.centerY.rounded()), Float(patternHeight - 1))
        s.inner = s.inner.rounded()
        s.outer = s.outer.rounded()
        onEdited(s)
    }

    private func handle(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            .shadow(radius: 1)
    }

    private func accessibleSlider(
        _ label: String, value: Float, range: ClosedRange<Float>,
        update: @escaping (inout Aperture, Float) -> Void
    ) -> some View {
        Slider(value: Binding(
            get: { value },
            set: { newValue in
                var changed = aperture
                update(&changed, newValue.rounded())
                onEdited(changed)
                onCommit()
            }
        ), in: range, step: 1)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) pixels")
    }

    private func radiusDrag(center: CGPoint, scale: CGFloat, isInner: Bool) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let radius = Float(hypot(dx, dy) / scale)
                var updated = aperture
                if isInner {
                    updated.inner = max(0, min(radius, updated.outer))
                } else {
                    updated.outer = max(updated.inner, radius)
                }
                emit(updated)
            }
            .onEnded { _ in onCommit() }
    }

    private func circleRadiusDrag(center: CGPoint, scale: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var updated = aperture
                updated.outer = max(1, Float(hypot(dx, dy) / scale))
                emit(updated)
            }
            .onEnded { _ in onCommit() }
    }
}

// MARK: - Bragg-disk overlay

/// Circles at the detected disk positions, sized to the probe radius. Lifted
/// verbatim out of the old `DiffractionView.peakOverlay(box:qx:qy:)`, which
/// is where this drawing lived; the caller passes the peaks and the drawn box
/// so the overlay never reaches into `AppState` itself.
struct UI2PeakOverlay: View {
    let peaks: [BraggPeak]
    let probeRadius: Float
    let patternWidth: Int
    let patternHeight: Int
    let box: CGSize

    var body: some View {
        let r = PeakOverlayGeometry.radius(
            probeRadius: probeRadius,
            patternWidth: patternWidth,
            patternHeight: patternHeight,
            box: box
        )
        ZStack {
            ForEach(Array(peaks.enumerated()), id: \.offset) { _, p in
                Circle()
                    .stroke(Color.green, lineWidth: 1.2)
                    .frame(width: 2 * r, height: 2 * r)
                    .position(PeakOverlayGeometry.center(
                        x: p.x,
                        y: p.y,
                        patternWidth: patternWidth,
                        patternHeight: patternHeight,
                        box: box
                    ))
            }
        }
    }
}

// MARK: - Fit-verification overlay

/// Draws fit-verification overlays on the diffraction pane — measured peaks vs
/// the model the app fitted (strain lattice, matched ACOM template, calibrated
/// origin/ellipse). Rendering only; the geometry comes from `FitOverlays` (raw
/// detector px) and is mapped to view points with the same fitted-box math as
/// the disk-peak overlay, so marks stay pixel-accurate at any zoom.
///
/// Visual vocabulary (kept consistent across modes):
///   green circle  = measured Bragg peak (same as Disks mode)
///   orange cross  = model prediction (local lattice point / template spot)
///   orange arrow  = fitted local lattice vector
///   dashed white  = reference lattice vector
///   red           = calibration (origin marker, fitted ellipse)
struct UI2FitOverlay: View {
    let strain: FitOverlays.StrainOverlay?
    let template: FitOverlays.TemplateOverlay?
    let originPoint: (x: Float, y: Float)?
    let ellipse: [FitOverlays.Marker]
    let measuredPeaks: [BraggPeak]
    let probeRadius: Float
    let patternWidth: Int
    let patternHeight: Int
    let box: CGSize

    private static let predictionColor = Color.orange
    private static let calibrationColor = Color.red
    private static let measuredColor = Color.green

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawEllipse(context)
                drawMeasuredPeaks(context)
                if let strain { drawStrain(strain, context) }
                if let template { drawTemplate(template, context) }
                if let originPoint {
                    drawOriginMarker(at: point(originPoint.x, originPoint.y),
                                     context)
                }
            }
            .frame(width: box.width, height: box.height)

            legend
                .padding(6)
        }
        .frame(width: box.width, height: box.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fit overlay")
        .accessibilityValue(legendText)
    }

    // MARK: - Coordinate mapping

    private func point(_ x: Float, _ y: Float) -> CGPoint {
        PeakOverlayGeometry.center(
            x: x, y: y,
            patternWidth: patternWidth, patternHeight: patternHeight, box: box
        )
    }

    // MARK: - Marks

    private func drawMeasuredPeaks(_ context: GraphicsContext) {
        guard !measuredPeaks.isEmpty else { return }
        let r = PeakOverlayGeometry.radius(
            probeRadius: probeRadius,
            patternWidth: patternWidth, patternHeight: patternHeight, box: box
        )
        for peak in measuredPeaks {
            let c = point(peak.x, peak.y)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            context.stroke(Path(ellipseIn: rect),
                           with: .color(Self.measuredColor), lineWidth: 1.2)
        }
    }

    private func drawStrain(_ overlay: FitOverlays.StrainOverlay,
                            _ context: GraphicsContext) {
        drawVector(overlay.referenceG1, context,
                   color: .white.opacity(0.7), dash: [4, 3])
        drawVector(overlay.referenceG2, context,
                   color: .white.opacity(0.7), dash: [4, 3])
        if let g1 = overlay.localG1 {
            drawVector(g1, context, color: Self.predictionColor)
        }
        if let g2 = overlay.localG2 {
            drawVector(g2, context, color: Self.predictionColor)
        }
        for marker in overlay.predicted {
            drawCross(at: point(marker.x, marker.y), context,
                      color: Self.predictionColor, opacity: 1)
        }
        drawOriginMarker(at: point(overlay.originX, overlay.originY), context)
    }

    private func drawTemplate(_ overlay: FitOverlays.TemplateOverlay,
                              _ context: GraphicsContext) {
        for marker in overlay.predicted {
            drawCross(at: point(marker.x, marker.y), context,
                      color: Self.predictionColor,
                      opacity: 0.35 + 0.65 * Double(marker.weight))
        }
        drawOriginMarker(at: point(overlay.originX, overlay.originY), context)
    }

    private func drawEllipse(_ context: GraphicsContext) {
        guard ellipse.count > 2 else { return }
        var path = Path()
        path.move(to: point(ellipse[0].x, ellipse[0].y))
        for marker in ellipse.dropFirst() {
            path.addLine(to: point(marker.x, marker.y))
        }
        context.stroke(path, with: .color(Self.calibrationColor.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
    }

    private func drawCross(at c: CGPoint, _ context: GraphicsContext,
                           color: Color, opacity: Double) {
        let arm: CGFloat = 4
        var path = Path()
        path.move(to: CGPoint(x: c.x - arm, y: c.y - arm))
        path.addLine(to: CGPoint(x: c.x + arm, y: c.y + arm))
        path.move(to: CGPoint(x: c.x - arm, y: c.y + arm))
        path.addLine(to: CGPoint(x: c.x + arm, y: c.y - arm))
        context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1.4)
    }

    private func drawOriginMarker(at c: CGPoint, _ context: GraphicsContext) {
        let arm: CGFloat = 6
        var path = Path()
        path.move(to: CGPoint(x: c.x - arm, y: c.y))
        path.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - arm))
        path.addLine(to: CGPoint(x: c.x, y: c.y + arm))
        // Black halo first, so the marker reads on any colormap.
        context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: 3)
        context.stroke(path, with: .color(Self.calibrationColor), lineWidth: 1.2)
    }

    private func drawVector(_ vector: FitOverlays.Vector,
                            _ context: GraphicsContext,
                            color: Color, dash: [CGFloat] = []) {
        let from = point(vector.fromX, vector.fromY)
        let to = point(vector.toX, vector.toY)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)

        // Arrowhead: two short strokes back from the tip.
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength: CGFloat = 7
        for side in [CGFloat(1), -1] {
            let a = angle + .pi + side * 0.45
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x + headLength * cos(a),
                                     y: to.y + headLength * sin(a)))
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.3, dash: dash))
    }

    // MARK: - Legend

    private var legendText: String {
        if let strain {
            if let residual = strain.localResidualPixels {
                return String(
                    format: "● measured  ✕ local fit  ⇢ reference · residual %.3g px",
                    residual
                )
            }
            return "● measured · no local fit at this position"
        }
        if let template {
            return String(
                format: "● measured  ✕ template · reliability %.2f",
                template.reliability
            )
        }
        var parts: [String] = []
        if originPoint != nil { parts.append("✚ fitted origin") }
        if !ellipse.isEmpty { parts.append("◌ fitted ellipse") }
        return parts.joined(separator: " · ")
    }

    private var legend: some View {
        Text(legendText)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            // Legibility plate over the pattern, as on the scale bar: this
            // key is read against arbitrary diffraction intensity.
            .background(Color.black.opacity(0.48), in: Capsule())
    }
}

// MARK: - IPF legends

/// Compact sampled m-3m inverse-pole-figure key. The map and legend share the
/// same color function, keeping the on-screen key aligned with exported pixels.
struct UI2CubicIPFLegend: View {
    var body: some View {
        VStack(spacing: 1) {
            Canvas { context, size in
                let left = SIMD2<Double>(4, Double(size.height - 3))
                let right = SIMD2<Double>(Double(size.width - 4), Double(size.height - 3))
                let top = SIMD2<Double>(Double(size.width / 2), 3)
                let steps = 36
                let radius = max(1.4, Double(size.width) / Double(steps) * 0.65)
                // Triangle corners as named constants: the one-expression blend
                // exceeds Xcode 26.6's type-checker budget (CI run #1) even
                // though Xcode 27 accepts it.
                let dir001 = SIMD3<Double>(0, 0, 1)
                let dir101 = simd_normalize(SIMD3<Double>(1, 0, 1))
                let dir111 = simd_normalize(SIMD3<Double>(1, 1, 1))
                for topIndex in 0...steps {
                    for rightIndex in 0...(steps - topIndex) {
                        let wt = Double(topIndex) / Double(steps)
                        let wr = Double(rightIndex) / Double(steps)
                        let wl = 1 - wt - wr
                        let point = left * wl + right * wr + top * wt
                        let blended = dir001 * wl + dir101 * wr + dir111 * wt
                        let direction = simd_normalize(blended)
                        let rgb = CubicOrientationSymmetry.ipfColor(direction: direction)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(
                            red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)
                        )))
                    }
                }
            }
            .frame(width: Self.triangleSize.width, height: Self.triangleSize.height)
            HStack {
                Text("001")
                Spacer()
                Text("111")
                Spacer()
                Text("101")
            }
            .font(.caption2.monospacedDigit())
            // Drawing geometry, not a text layout: the corner labels are part
            // of the key and must sit under the triangle's corners.
            .frame(width: Self.labelRowWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cubic inverse pole figure color key: 001 red, 101 green, 111 blue")
    }

    private static let triangleSize = CGSize(width: 116, height: 62)
    private static let labelRowWidth: CGFloat = 132
}

/// Native 6/mmm key sharing the production hexagonal color function.
struct UI2HexagonalIPFLegend: View {
    var body: some View {
        VStack(spacing: 1) {
            Canvas { context, size in
                let left = SIMD2<Double>(4, Double(size.height - 3))
                let right = SIMD2<Double>(Double(size.width - 4), Double(size.height - 3))
                let top = SIMD2<Double>(Double(size.width / 2), 3)
                let steps = 36
                let radius = max(1.4, Double(size.width) / Double(steps) * 0.65)
                for topIndex in 0...steps {
                    for rightIndex in 0...(steps - topIndex) {
                        let wt = Double(topIndex) / Double(steps)
                        let wr = Double(rightIndex) / Double(steps)
                        let wl = 1 - wt - wr
                        let point = left * wl + right * wr + top * wt
                        let direction = simd_normalize(
                            SIMD3(0.0, 0.0, 1.0) * wl
                                + SIMD3(1.0, 0.0, 0.0) * wr
                                + SIMD3(cos(.pi / 6), sin(.pi / 6), 0.0) * wt
                        )
                        let rgb = HexagonalOrientationSymmetry.ipfColor(direction: direction)
                        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(
                            red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)
                        )))
                    }
                }
            }
            .frame(width: Self.triangleSize.width, height: Self.triangleSize.height)
            HStack {
                Text("0001")
                Spacer()
                Text("11-20")
                Spacer()
                Text("10-10")
            }
            .font(.caption2.monospacedDigit())
            // Drawing geometry, as above; wider than the cubic key because
            // the hexagonal indices are four characters.
            .frame(width: Self.labelRowWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hexagonal inverse pole figure color key: 0001 red, 10-10 green, 11-20 blue")
    }

    private static let triangleSize = CGSize(width: 116, height: 62)
    private static let labelRowWidth: CGFloat = 142
}
