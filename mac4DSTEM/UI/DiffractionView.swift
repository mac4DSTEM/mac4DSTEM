//
//  DiffractionView.swift
//  Role: The live CBED (diffraction) pattern viewer. Shows the pattern at the
//        currently-selected scan position, with optional log scaling.
//
//  MIGRATION NOTE: the interactive aperture overlay (Virtual Detector slice)
//  and the Bragg-peak overlay (Disk Detection slice) are intentionally absent
//  here — they depend on AppState members that arrive with those slices. This
//  is the display-only version: render the CBED, switch current/mean/max, and
//  scrub the scan position from the sidebar.
//
//  Kept at 1:1 (no pan/zoom) so a future SwiftUI aperture overlay stays
//  pixel-accurate against the GPU-rendered pattern.
//

import SwiftUI

struct DiffractionView: View {
    @Environment(AppState.self) private var app

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

    private var header: some View {
        HStack {
            Text("Diffraction (CBED)")
                .font(.headline)
            Spacer()
            // Mean/max become meaningful once calibration computes them; until
            // then the picker still works but falls back to the live pattern.
            if app.meanPattern != nil {
                Picker("", selection: Bindable(app).patternDisplayMode) {
                    ForEach(PatternDisplayMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if let p = app.displayedPattern {
                Text("\(p.qx) × \(p.qy)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let pattern = app.displayedPattern {
            let qx = pattern.qx, qy = pattern.qy
            let box = fitted(in: size, aspect: CGFloat(qx) / CGFloat(qy))
            let norm = pattern.normalized(useLog: app.logScale)

            ZStack {
                MetalImageView(pixels: norm,
                               width: qx, height: qy,
                               contentVersion: app.patternVersion,
                               colormap: app.colormap,
                               zoom: 1, offset: .zero)
                    .background(Color.black)
                    .border(Color.white.opacity(0.08))

                // Interactive annular aperture (Virtual Detector mode only).
                if app.analysisMode == .virtualDetector {
                    ApertureControl(
                        aperture: app.aperture,
                        shape: app.virtualShape,
                        patternWidth: qx, patternHeight: qy,
                        onEdited: { app.updateAperture($0) },
                        onCommit: { app.commitApertureChange() }
                    )
                }

                // Detected Bragg disks for the current pattern (Disks mode).
                if app.analysisMode == .disks, !app.currentPeaks.isEmpty {
                    peakOverlay(box: box, qx: qx, qy: qy)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: box.width, height: box.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder
        }
    }

    /// Circles at the detected disk positions, sized to the probe radius.
    private func peakOverlay(box: CGSize, qx: Int, qy: Int) -> some View {
        let r = CGFloat(app.probeKernel?.probeRadius ?? 3) / CGFloat(qx) * box.width
        return ZStack {
            ForEach(Array(app.currentPeaks.enumerated()), id: \.offset) { _, p in
                Circle()
                    .stroke(Color.green, lineWidth: 1.2)
                    .frame(width: 2 * r, height: 2 * r)
                    .position(x: (CGFloat(p.x) + 0.5) / CGFloat(qx) * box.width,
                              y: (CGFloat(p.y) + 0.5) / CGFloat(qy) * box.height)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Open a 4DSTEM .h5 file to view diffraction patterns")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Largest size with the given aspect (w/h) that fits inside `size`.
    private func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        } else {
            return CGSize(width: size.width, height: size.width / aspect)
        }
    }
}
