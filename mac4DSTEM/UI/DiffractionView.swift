//
//  DiffractionView.swift
//  Role: The live CBED (diffraction) pattern viewer. Shows the pattern at the
//        currently-selected scan position, with optional log scaling.
//
//  ZOOM/PAN: magnify to zoom, drag the background to pan, double-click to
//  reset. The image and the aperture / peak overlays live in ONE transformed
//  container, so overlays and their drag handles stay pixel-accurate at any
//  zoom (SwiftUI maps hit-testing through the transform; handle drags win
//  over the background pan).
//

import SwiftUI

struct DiffractionView: View {
    @Environment(AppState.self) private var app
    @State private var zp = ZoomPanState()

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
            if app.fitOverlayIsAvailable {
                Toggle("Fit overlay", isOn: Bindable(app).showFitOverlay)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .help("Draw the fitted model (origin/ellipse, strain lattice, or matched template) over the pattern.")
            }
            if let p = app.displayedPattern {
                Text("\(p.qx) × \(p.qy)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        // Mean/max become meaningful once calibration computes them; the picker
        // is centered over the pattern rather than crammed against the size.
        .overlay {
            if app.meanPattern != nil {
                Picker("", selection: Bindable(app).patternDisplayMode) {
                    ForEach(PatternDisplayMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let pattern = app.displayedPattern {
            let qx = pattern.qx, qy = pattern.qy
            let box = fitted(in: size, aspect: CGFloat(qx) / CGFloat(qy))
            let norm = app.normalizedPatternPixels()   // cached per patternVersion

            ZStack {
                ZStack {
                    MetalImageView(pixels: norm,
                                   width: qx, height: qy,
                                   contentVersion: app.patternVersion,
                                   colormap: app.patternColormap,
                                   zoom: 1, offset: .zero,
                                   displayLo: app.patternDisplayRangeLo,
                                   displayHi: app.patternDisplayRangeHi,
                                   gamma: app.patternGamma)
                        .frame(width: box.width, height: box.height)
                        .background(Color.black)

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

                    // Fit-verification overlays: measured peaks vs the fitted
                    // model (strain lattice / ACOM template / origin+ellipse).
                    let fitStrain = app.strainFitOverlay
                    let fitTemplate = app.acomFitOverlay
                    let fitOrigin = app.originFitOverlayPoint
                    let fitEllipse = app.ellipseFitOverlayPolyline
                    if fitStrain != nil || fitTemplate != nil
                        || fitOrigin != nil || !fitEllipse.isEmpty {
                        PatternFitOverlayView(
                            strain: fitStrain,
                            template: fitTemplate,
                            originPoint: fitOrigin,
                            ellipse: fitEllipse,
                            measuredPeaks: (fitStrain != nil || fitTemplate != nil)
                                ? app.storedPeaksAtSelection : [],
                            probeRadius: app.probeKernel?.probeRadius ?? 3,
                            patternWidth: qx, patternHeight: qy, box: box
                        )
                    }
                }
                .frame(width: box.width, height: box.height)
                .scaleEffect(max(0.25, zp.effectiveZoom))
                .offset(zp.effectiveOffset)
                .frame(width: box.width, height: box.height)
                .clipped()
                .contentShape(Rectangle())
                .border(Color.white.opacity(0.08))
                .zoomPan($zp)

                // Calibrated q-space scale bar (px fallback), zoom-aware.
                // mrad mode shows the direct scattering angle, but falls back
                // to the reciprocal/px behavior automatically if the Q
                // calibration or voltage needed for it disappears.
                let qSize = app.calibration.qPixelSize
                if app.patternScaleUnit == .milliradians,
                   let mradPerPixel = app.dpcMilliradiansPerDetectorPixel {
                    ScaleBarView(
                        unitsPerPoint: Double(mradPerPixel) * Double(qx)
                            / Double(box.width) / Double(max(0.25, zp.effectiveZoom)),
                        unitLabel: "mrad")
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                } else {
                    ScaleBarView(
                        unitsPerPoint: (qSize ?? 1) * Double(qx)
                            / Double(box.width) / Double(max(0.25, zp.effectiveZoom)),
                        unitLabel: qSize != nil ? (app.calibration.qPixelUnits ?? "1/nm") : "px")
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .bottomLeading)
                }

                if let range = app.patternDisplayedValueRange {
                    ScalarColorbarView(
                        colormap: app.patternColormap,
                        low: range.low,
                        high: range.high,
                        unitLabel: logScaleLabel,
                        gamma: app.patternGamma
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
                }
            }
            .frame(width: box.width, height: box.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Diffraction pattern")
            .accessibilityValue("Scan X \(app.selectedScan.x), Y \(app.selectedScan.y); \(qx) by \(qy) detector pixels")
            .accessibilityHint("Pinch to zoom, drag to pan, or double click to reset")
        } else {
            placeholder
        }
    }

    private var logScaleLabel: String {
        app.logScale ? "intensity · log display" : "intensity"
    }

    /// Circles at the detected disk positions, sized to the probe radius.
    private func peakOverlay(box: CGSize, qx: Int, qy: Int) -> some View {
        let r = PeakOverlayGeometry.radius(
            probeRadius: app.probeKernel?.probeRadius ?? 3,
            patternWidth: qx,
            patternHeight: qy,
            box: box
        )
        return ZStack {
            ForEach(Array(app.currentPeaks.enumerated()), id: \.offset) { _, p in
                Circle()
                    .stroke(Color.green, lineWidth: 1.2)
                    .frame(width: 2 * r, height: 2 * r)
                    .position(PeakOverlayGeometry.center(
                        x: p.x,
                        y: p.y,
                        patternWidth: qx,
                        patternHeight: qy,
                        box: box
                    ))
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
