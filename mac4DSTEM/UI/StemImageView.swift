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
            let norm = app.resultImage?.normalized(symmetric: app.colormap.isDiverging) ?? []
            let effZoom = max(0.1, zoom * liveZoom)

            ZStack {
                MetalImageView(pixels: norm,
                               width: dims.width, height: dims.height,
                               contentVersion: app.resultVersion,
                               colormap: app.colormap,
                               zoom: effZoom, offset: .zero,
                               rgba: app.resultRGBA?.rgba)
                    .frame(width: box.width, height: box.height)
                    .background(Color.black)
                    .border(Color.white.opacity(0.08))
                    .gesture(
                        MagnificationGesture()
                            .onChanged { liveZoom = $0 }
                            .onEnded { zoom = max(0.1, zoom * $0); liveZoom = 1 }
                    )
                    .onTapGesture(count: 2) { zoom = 1; liveZoom = 1 }

                // Transparent hit layer for click-to-select scan position.
                selectionLayer(box: box, imgW: dims.width, imgH: dims.height)
                    .frame(width: box.width, height: box.height)

                // Crosshair at the current scan position.
                crosshair(box: box, imgW: dims.width, imgH: dims.height)
            }
            .frame(width: box.width, height: box.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder
        }
    }

    private func selectionLayer(box: CGSize, imgW: Int, imgH: Int) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        let fx = value.location.x / box.width
                        let fy = value.location.y / box.height
                        let x = Int((fx * CGFloat(imgW)).rounded(.down))
                        let y = Int((fy * CGFloat(imgH)).rounded(.down))
                        app.selectScan(x: x, y: y)
                    }
            )
    }

    @ViewBuilder
    private func crosshair(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let px = (CGFloat(app.selectedScan.x) + 0.5) / CGFloat(imgW) * box.width
        let py = (CGFloat(app.selectedScan.y) + 0.5) / CGFloat(imgH) * box.height
        Circle()
            .stroke(Color.white, lineWidth: 1.5)
            .frame(width: 10, height: 10)
            .position(x: px, y: py)
            .allowsHitTesting(false)
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
