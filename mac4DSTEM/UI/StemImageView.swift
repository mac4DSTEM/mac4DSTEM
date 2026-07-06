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
        if let r = app.resultRGBA { return (r.width, r.height) }
        if let r = app.resultImage { return (r.width, r.height) }
        return nil
    }

    private var header: some View {
        HStack {
            Text(app.analysisMode.rawValue + " — real space")
                .font(.headline)
            Spacer()
            if let r = resultSize {
                Text("\(r.width) × \(r.height)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
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
                                   contentVersion: app.resultVersion,
                                   colormap: app.colormap,
                                   zoom: 1, offset: .zero,
                                   rgba: app.resultRGBA?.rgba,
                                   displayLo: app.displayRangeLo,
                                   displayHi: app.displayRangeHi)
                        .frame(width: box.width, height: box.height)
                        .background(Color.black)

                    // Transparent hit layer for click-to-select scan position.
                    selectionLayer(box: box, imgW: dims.width, imgH: dims.height)
                        .frame(width: box.width, height: box.height)

                    // Crosshair at the current scan position.
                    crosshair(box: box, imgW: dims.width, imgH: dims.height)

                    // Region-of-interest for virtual diffraction (sum patterns).
                    if app.realSpaceShape != .point {
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

                // Direction legend for the DPC color wheel.
                if app.resultRGBA != nil {
                    colorWheelLegend
                        .frame(width: 54, height: 54)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomTrailing)
                }

                // Calibrated scale bar (px fallback), re-quantized with zoom.
                let rSize = app.calibration.rPixelSize
                ScaleBarView(
                    unitsPerPoint: (rSize ?? 1) * Double(dims.width)
                        / Double(box.width) / Double(effZoom),
                    unitLabel: rSize != nil ? (app.calibration.rPixelUnits ?? "nm") : "px")
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomLeading)
            }
            .frame(width: box.width, height: box.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder
        }
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
