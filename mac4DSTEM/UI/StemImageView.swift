//
//  StemImageView.swift
//  Role: The real-space result viewer. Shows whatever the current analysis
//        produced — a virtual-detector image, and later DPC / disk maps.
//        Magnify to zoom; click a pixel to make that the selected scan
//        position (which updates the diffraction pane).
//

import SwiftUI

struct StemImageView: View {
    @Environment(AppState.self) private var app
    @State private var zoom: CGFloat = 1
    @State private var liveZoom: CGFloat = 1
    @State private var cursorSample: ProductSample?

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geo in
                content(in: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
    }

    /// Size of whichever result (scalar or RGBA) is active.
    private var resultSize: (width: Int, height: Int)? {
        if let r = app.displayedResultRGBA { return (r.width, r.height) }
        if let r = app.displayedResultImage { return (r.width, r.height) }
        return nil
    }

    private var mapsScanPositions: Bool {
        guard app.displayedProduct?.domain == .scan,
              let dims = resultSize, let descriptor = app.descriptor,
              dims.width == descriptor.rx, dims.height == descriptor.ry else {
            return false
        }
        return true
    }

    private var header: some View {
        HStack {
            Text(app.displayedResultName)
                .font(.headline)
                .accessibilityIdentifier("result.title")
            Spacer()
            if let r = resultSize {
                Text("\(r.width) × \(r.height)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if app.displayedProduct?.domain == .detector {
                Text("qᵧ →  ·  qₓ ↓")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .help("App detector columns are py4DSTEM qy; rows are qx.")
                    .accessibilityLabel("Detector axes: q y increases right, q x increases down")
            }
            if let sample = cursorSample {
                Text(sample.accessibilityText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("result.cursorReadout")
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let dims = resultSize {
            let box = fitted(in: size, aspect: CGFloat(dims.width) / CGFloat(dims.height))
            let norm = app.normalizedResultPixels()   // cached per resultVersion
            let effZoom = max(1, zoom * liveZoom)

            ZStack {
                // Image + overlays share ONE scaled container, so the
                // crosshair / ROI / click mapping stay aligned at any zoom
                // (SwiftUI maps hit-testing through the transform).
                ZStack {
                    MetalImageView(pixels: norm,
                                   width: dims.width, height: dims.height,
                                   contentVersion: app.displayedResultVersion,
                                   colormap: app.displayedResultColormap,
                                   zoom: 1, offset: .zero,
                                   rgba: app.displayedResultRGBA?.rgba,
                                   displayLo: app.displayedResultRangeLo,
                                   displayHi: app.displayedResultRangeHi,
                                   gamma: app.displayedResultGamma)
                        .frame(width: box.width, height: box.height)
                        .background(Color.black)

                    // Transparent hit layer for click-to-select scan position.
                    if mapsScanPositions {
                        selectionLayer(box: box, imgW: dims.width, imgH: dims.height)
                            .frame(width: box.width, height: box.height)
                    }

                    // Crosshair at the current scan position.
                    if mapsScanPositions {
                        crosshair(box: box, imgW: dims.width, imgH: dims.height)
                    }

                    // Region-of-interest for virtual diffraction (sum patterns).
                    if mapsScanPositions, app.realSpaceShape != .point,
                       app.realSpaceROIIsRelevant {
                        regionOverlay(box: box, imgW: dims.width, imgH: dims.height)
                            .frame(width: box.width, height: box.height)
                    }
                }
                .frame(width: box.width, height: box.height)
                .scaleEffect(effZoom)
                .frame(width: box.width, height: box.height)
                .clipped()
                .contentShape(Rectangle())
                .border(Color.white.opacity(0.08))
                .gesture(
                    MagnificationGesture()
                        .onChanged { liveZoom = $0 }
                        .onEnded { zoom = min(max(1, zoom * $0), 64); liveZoom = 1 }
                )
                .onTapGesture(count: 2) { zoom = 1; liveZoom = 1 }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let x = min(dims.width - 1, max(0,
                            Int(location.x / max(box.width, 1) * CGFloat(dims.width))))
                        let y = min(dims.height - 1, max(0,
                            Int(location.y / max(box.height, 1) * CGFloat(dims.height))))
                        cursorSample = app.displayedProduct?.sample(x: x, y: y)
                    case .ended:
                        cursorSample = nil
                    }
                }

                // Direction legend for the DPC color wheel.
                if app.displayedResultKind == "dpc_color" {
                    colorWheelLegend
                        .frame(width: 54, height: 54)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomTrailing)
                }

                if app.displayedResultKind == "acom_ipf_z" {
                    Group {
                        if app.orientationMap?.symmetry == .hexagonal {
                            HexagonalIPFLegendView()
                        } else {
                            CubicIPFLegendView()
                        }
                    }
                        .padding(7)
                        .background(Color.black.opacity(0.48),
                                    in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomTrailing)
                }

                if app.displayedResultImage != nil,
                   let range = app.resultDisplayedValueRange {
                    ScalarColorbarView(
                        colormap: app.displayedResultColormap,
                        low: range.low,
                        high: range.high,
                        unitLabel: app.displayedResultValueUnits,
                        gamma: app.displayedResultGamma,
                        marksZero: app.displayedResultColormap.isDiverging,
                        showsMasked: app.displayedResultHasMaskedPixels()
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
                }

                if app.displayedProduct?.domain != .scan,
                   let navigator = app.scanNavigationImage {
                    scanNavigator(navigator)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                }

                // Coordinate-aware scale bar (px fallback), re-quantized with zoom.
                let pixel = app.displayedResultPixelMetadata
                let sampling = pixel.column ?? pixel.row
                ScaleBarView(
                    unitsPerPoint: (sampling ?? 1) * Double(dims.width)
                        / Double(box.width) / Double(effZoom),
                    unitLabel: sampling != nil ? (pixel.units ?? "px") : "px")
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomLeading)
            }
            .frame(width: box.width, height: box.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(app.displayedResultName)
            .accessibilityIdentifier("result.viewer")
            .accessibilityValue(cursorSample?.accessibilityText ?? (mapsScanPositions
                ? "Selected scan X \(app.selectedScan.x), Y \(app.selectedScan.y); \(dims.width) by \(dims.height) pixels"
                : "\(dims.width) by \(dims.height) pixels"))
            .accessibilityHint(mapsScanPositions
                ? "Use arrow keys to move the selected scan position; Shift moves ten pixels"
                : "Scientific image; scan-position selection is unavailable")
        } else {
            placeholder
        }
    }

    private func scanNavigator(_ image: FloatImage) -> some View {
        let width: CGFloat = 118
        let height = width * CGFloat(image.height) / CGFloat(max(image.width, 1))
        return ZStack {
            MetalImageView(
                pixels: image.normalized(), width: image.width, height: image.height,
                contentVersion: app.scanNavigationVersion, colormap: .viridis,
                zoom: 1, offset: .zero, rgba: nil,
                displayLo: 0, displayHi: 1, gamma: 1
            )
            .frame(width: width, height: height)
            let x = (CGFloat(app.selectedScan.x) + 0.5) / CGFloat(image.width) * width
            let y = (CGFloat(app.selectedScan.y) + 0.5) / CGFloat(image.height) * height
            Circle().stroke(.white, lineWidth: 1.5)
                .background(Circle().stroke(.black, lineWidth: 3))
                .frame(width: 9, height: 9).position(x: x, y: y)
        }
        .frame(width: width, height: height)
        .background(.black)
        .overlay(alignment: .topLeading) {
            Text("SCAN").font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white).padding(3)
        }
        .border(.white.opacity(0.55))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let x = Int(value.location.x / width * CGFloat(image.width))
            let y = Int(value.location.y / max(height, 1) * CGFloat(image.height))
            app.scrubTo(x: x, y: y)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan navigator")
        .accessibilityValue("Selected scan X \(app.selectedScan.x), Y \(app.selectedScan.y)")
        .accessibilityHint("Click or drag to update the diffraction pattern")
        .accessibilityIdentifier("result.scanNavigator")
    }

    /// Hue wheel matching DPC.colorWheelRGBA (hue = atan2(cy,cx)/2π + 0.5),
    /// brightness growing with magnitude → dark center.
    private var colorWheelLegend: some View {
        let stops = (0...12).map { i in
            Gradient.Stop(color: Color(hue: (0.5 + Double(i) / 12)
                                            .truncatingRemainder(dividingBy: 1),
                                       saturation: 1, brightness: 1),
                          location: Double(i) / 12)
        }
        return ZStack {
            Circle().fill(AngularGradient(gradient: Gradient(stops: stops), center: .center))
            Circle().fill(RadialGradient(colors: [.black, .clear],
                                         center: .center, startRadius: 0, endRadius: 27))
            Circle().stroke(Color.white.opacity(0.4), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func selectionLayer(box: CGSize, imgW: Int, imgH: Int) -> some View {
        // Drag (or click) to move the scan position live — the diffraction pane
        // streams the pattern as you go. minimumDistance 0 → a click also works.
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let fx = value.location.x / box.width
                        let fy = value.location.y / box.height
                        let x = Int((fx * CGFloat(imgW)).rounded(.down))
                        let y = Int((fy * CGFloat(imgH)).rounded(.down))
                        app.scrubTo(x: x, y: y)
                    }
            )
    }

    @ViewBuilder
    private func crosshair(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let px = (CGFloat(app.selectedScan.x) + 0.5) / CGFloat(imgW) * box.width
        let py = (CGFloat(app.selectedScan.y) + 0.5) / CGFloat(imgH) * box.height
        // Double-stroke marker so it reads on any colormap / brightness.
        ZStack {
            Circle().stroke(Color.black.opacity(0.75), lineWidth: 3.5)
            Circle().stroke(Color.white, lineWidth: 1.5)
        }
        .frame(width: 11, height: 11)
        .position(x: px, y: py)
        .allowsHitTesting(false)
    }

    /// Rectangle / circle ROI centered on the selected scan position, with a
    /// resize handle. Summed patterns from inside it feed the diffraction pane.
    private func regionOverlay(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let scaleX = box.width / CGFloat(imgW)
        let scaleY = box.height / CGFloat(imgH)
        let radiusScale = (scaleX + scaleY) / 2
        let center = CGPoint(x: (CGFloat(app.selectedScan.x) + 0.5) * scaleX,
                             y: (CGFloat(app.selectedScan.y) + 0.5) * scaleY)
        let r = CGFloat(app.realSpaceRadius) * radiusScale
        return ZStack {
            Group {
                if app.realSpaceShape == .circle {
                    Circle().stroke(Color.orange, lineWidth: 1.5)
                } else {
                    Rectangle().stroke(Color.orange, lineWidth: 1.5)
                }
            }
            .frame(width: r * 2, height: r * 2)
            .position(center)

            Circle()
                .fill(Color.orange)
                .frame(width: 11, height: 11)
                .position(x: center.x + r, y: app.realSpaceShape == .circle ? center.y : center.y + r)
                .gesture(
                    DragGesture(coordinateSpace: .local)
                        .onChanged { value in
                            let dx = abs(value.location.x - center.x)
                            let dy = abs(value.location.y - center.y)
                            let newR = app.realSpaceShape == .circle ? hypot(dx, dy) : max(dx, dy)
                            app.realSpaceRadius = max(1, Float((newR / radiusScale).rounded()))
                        }
                )
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(app.hasDataset
                 ? "Adjust the aperture or pick a detector preset to generate an image"
                 : "Open a 4DSTEM .h5 file to begin")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        } else {
            return CGSize(width: size.width, height: size.width / aspect)
        }
    }
}
