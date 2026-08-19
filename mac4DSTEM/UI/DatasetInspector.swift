import SwiftUI

struct DatasetInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if let descriptor = appState.descriptor {
                Section("Dataset") {
                    row("File", descriptor.fileName)
                    row("Path", descriptor.datasetPath, mono: true)
                    row("Shape", descriptor.shapeString, mono: true)
                    row("dtype", descriptor.dtypeDescription, mono: true)
                    row(
                        "Chunks",
                        descriptor.chunkShape.map { $0.map(String.init).joined(separator: " x ") } ?? "contiguous",
                        mono: true
                    )
                    row("Size (f32)", byteString(descriptor.byteCountAsFloat32))
                }

                if let preview = appState.datasetPreview {
                    // INVARIANT I4: a sampled preview is not a result. The
                    // summary states the stride and is drawn FIRST, above the
                    // images, so nothing here can be read as a virtual image.
                    // A strided preview and a real virtual image will differ,
                    // and a user comparing them will file a bug — this label is
                    // the thing that pre-empts it.
                    Section("Preview") {
                        Text(preview.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("preview.summary")
                        previewImage(
                            "Real space", pixels: preview.realSpace.normalized(),
                            width: preview.realSpace.width,
                            height: preview.realSpace.height, colormap: .gray
                        )
                        previewImage(
                            "Mean pattern", pixels: preview.meanDP.normalized(useLog: true),
                            width: preview.meanDP.qx, height: preview.meanDP.qy,
                            colormap: .viridis
                        )
                        previewImage(
                            "Max pattern", pixels: preview.maxDP.normalized(useLog: true),
                            width: preview.maxDP.qx, height: preview.maxDP.qy,
                            colormap: .viridis
                        )
                        if preview.isSampled {
                            Text("Not a result — cannot be exported or saved.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // WHAT IS ACTUALLY LOADED, and what that cost the calibration.
                //
                // L4's "state them in the UI" and "label the result" (invariant
                // I3): a cropped or binned cube is a DIFFERENT MEASUREMENT, and
                // until this section existed the app knew that and never said
                // it. `LoadedView`'s whole display surface had no reader.
                //
                // Absent at full extent, deliberately — a permanent row reading
                // "no crop" on every dataset is noise, and the section's
                // presence is itself the signal that something was reduced.
                if !appState.loadedView.isFullExtent {
                    Section("Loaded view") {
                        if let summary = appState.loadedView.summary {
                            Text(summary)
                                .font(.callout)
                                .accessibilityIdentifier("inspector.loadedViewSummary")
                        }
                        if let notice = appState.loadedView.binningNotice {
                            // The intensity consequence, said plainly: binning
                            // SUMS, so every absolute-intensity threshold moves
                            // with the factor.
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("inspector.binningNotice")
                        }
                        row("Source shape", appState.loadedView.sourceShapeString, mono: true)
                        row("Loaded shape", descriptor.shapeString, mono: true)
                        row("Size (f32)", byteString(descriptor.byteCountAsFloat32))

                        // THE PROMOTE CONTROL (v2 S3). It lives in this
                        // section because the section exists exactly when
                        // promotion is meaningful: a reduced view is loaded.
                        // Promotion is a reopen of the SOURCE at full extent —
                        // removing the specification, never re-deriving from
                        // reduced data — so the cost stated is the whole
                        // cube's, which is the number the user is deciding
                        // about.
                        VStack(alignment: .leading, spacing: 4) {
                            Button("Reopen at Full Extent") {
                                Task { await appState.promoteToFullExtent() }
                            }
                            .disabled(appState.isLoadingDataset)
                            .accessibilityIdentifier("inspector.promoteToFullExtent")
                            if let source = appState.loadView?.source {
                                // SystemMonitor.byteString, deliberately: the
                                // configurator prices this same quantity
                                // ("Whole cube (f32)") through it, and the two
                                // surfaces a user compares when deciding to
                                // promote must not render the same cube with
                                // different precision.
                                Text("Reloads the whole cube — "
                                     + SystemMonitor.byteString(source.byteCountAsFloat32)
                                     + " as float32. Analyses re-run against the full dataset.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                // Calibration values that could NOT be carried into this view.
                // Shown separately from the summary above because these are
                // refusals, not descriptions: something the file provided is now
                // absent, and the reason is the actionable part.
                if !appState.loadedView.invalidatedCalibration.isEmpty {
                    Section("Not carried into this view") {
                        ForEach(appState.loadedView.invalidatedCalibration) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.field.rawValue)
                                    .font(.callout.weight(.medium))
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .accessibilityIdentifier("inspector.invalidatedCalibration")
                }

                Section("Dimensions") {
                    row("Scan (Ry x Rx)", "\(descriptor.ry) x \(descriptor.rx)")
                    row("Detector (Qy x Qx)", "\(descriptor.qy) x \(descriptor.qx)")
                    if let acceleratingVoltage = appState.acceleratingVoltage {
                        row("Accel. voltage", String(format: "%.0f kV", acceleratingVoltage))
                    }
                }

                Section("Current scan position") {
                    row("x (Rx)", "\(appState.selectedScan.x)")
                    row("y (Ry)", "\(appState.selectedScan.y)")
                    if let (lowerBound, upperBound) = appState.patternMinMax {
                        row("Pattern min", String(format: "%.3g", lowerBound))
                        row("Pattern max", String(format: "%.3g", upperBound))
                    }
                }

                Section("Aperture (detector px)") {
                    row("Center x", String(format: "%.1f", appState.aperture.centerX))
                    row("Center y", String(format: "%.1f", appState.aperture.centerY))
                    row("Inner r", String(format: "%.1f", appState.aperture.inner))
                    row("Outer r", String(format: "%.1f", appState.aperture.outer))
                }

                if let image = appState.resultImage {
                    Section("Histogram (real space)") {
                        HistogramView(pixels: image.pixels, version: appState.resultVersion,
                                      rangeLo: Bindable(appState).displayRangeLo,
                                      rangeHi: Bindable(appState).displayRangeHi)
                        Text("Drag the handles to clip which intensities map into the image.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        gammaControl("Gamma", value: Bindable(appState).resultGamma)
                    }
                }

                if let pattern = appState.displayedPattern {
                    Section("Histogram (diffraction)") {
                        HistogramView(
                            pixels: pattern.contrastPixels(useLog: appState.logScale),
                            version: appState.patternVersion,
                            rangeLo: Bindable(appState).patternDisplayRangeLo,
                            rangeHi: Bindable(appState).patternDisplayRangeHi
                        )
                        Text(appState.logScale
                             ? "Contrast is selected on the log10(1 + intensity) axis."
                             : "Drag the handles to set the CBED intensity window.")
                            .font(.caption2).foregroundStyle(.tertiary)
                        gammaControl("Gamma", value: Bindable(appState).patternGamma)
                    }
                }

                if let rotation = appState.lastRotationResult {
                    Section("Rotation diagnostics") {
                        RotationCurveView(result: rotation)
                            .frame(height: 90)
                        Text("Mean |curl| vs angle — solid: as-is, dashed: transposed. The marker is the chosen minimum.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Section("Performance") {
                    PerformanceView()
                }

                // PROVENANCE (L6 item 3). A result restored from a session
                // was computed under some view; if the app is now showing a
                // different one, the numbers on screen and the numbers in the
                // sidecar are about different data. Said in the existing
                // provenance vocabulary rather than a second one (I3).
                if let recorded = appState.sessionLoadSpecification,
                   recorded != appState.loadedView.specification {
                    Section("Session provenance") {
                        Text("The saved session was computed on a different view of this file.")
                            .font(.callout)
                        row("Session view", recorded.provenanceSummary ?? "whole file")
                        row("Loaded view",
                            appState.loadedView.specification.provenanceSummary ?? "whole file")
                        Text("Restored results describe the session's view, not the one loaded now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("inspector.sessionProvenanceMismatch")
                }

                // A SIDECAR THAT IS THERE AND UNREADABLE (v2 S1). Distinct from
                // the mismatch above, and it has to be: that one compares two
                // KNOWN views, while this is the case where the recorded view is
                // unknown because the file could not be opened. The dataset then
                // loaded at full extent, which looks exactly like a dataset that
                // never had a session — so without this the user's only signal
                // is a status line that the load itself overwrites within
                // milliseconds (measured, Gate D 2026-08-19).
                if let reason = appState.sessionSidecar.unreadableReason {
                    Section("Session sidecar") {
                        Text("A saved session sits beside this dataset and could not be read.")
                            .font(.callout)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The whole file is loaded. If that session recorded a crop, what is on screen is a different extent from what it saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("inspector.sessionSidecarUnreadable")
                }

                Section("Files & products") {
                    ProductsView()
                }
            } else {
                Text("No dataset loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 240)
    }

    private func gammaControl(_ label: String, value: Binding<Float>) -> some View {
        HStack {
            Text(label).font(.caption)
            Slider(value: value, in: 0.2...3)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: "%.2f", value.wrappedValue))
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }

    /// One preview thumbnail. Fixed square frame with the image scaled to fit:
    /// the sampled real-space grid and the detector have unrelated aspect
    /// ratios, and the point here is recognisability, not measurement.
    private func previewImage(
        _ label: String, pixels: [Float], width: Int, height: Int,
        colormap: ColormapKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            MetalImageView(
                pixels: pixels, width: width, height: height,
                contentVersion: pixels.count &+ width &* 31 &+ height,
                colormap: colormap, zoom: 1, offset: .zero
            )
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("preview.\(label.replacingOccurrences(of: " ", with: ""))")
        }
        .padding(.vertical, 2)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(mono ? .caption.monospaced() : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func byteString(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1024 {
            return String(format: "%.2f GB", megabytes / 1024)
        }
        return String(format: "%.1f MB", megabytes)
    }
}

/// Line plot of the rotation-calibration objective curves — the data was
/// always computed by RotationCalibration.solve; now it's actually shown, so
/// a flat or multi-minimum curve (an untrustworthy calibration) is visible.
struct RotationCurveView: View {
    let result: RotationCalibration.Result

    var body: some View {
        Canvas { context, size in
            let all = result.objectiveCurve + result.objectiveCurveTransposed
            guard let lo = all.min(), let hi = all.max(), hi > lo,
                  result.anglesDeg.count > 1 else { return }
            let n = result.anglesDeg.count

            func path(_ curve: [Float]) -> Path {
                Path { p in
                    for i in 0..<n {
                        let x = CGFloat(i) / CGFloat(n - 1) * size.width
                        let y = size.height * (1 - CGFloat((curve[i] - lo) / (hi - lo)))
                        i == 0 ? p.move(to: CGPoint(x: x, y: y))
                               : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            context.stroke(path(result.objectiveCurve),
                           with: .color(.accentColor), lineWidth: 1.2)
            context.stroke(path(result.objectiveCurveTransposed),
                           with: .color(.secondary),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

            // Marker at the chosen angle.
            let chosenDeg = result.rotationRad * 180 / .pi
            if let first = result.anglesDeg.first, let last = result.anglesDeg.last, last > first {
                let fx = CGFloat((chosenDeg - first) / (last - first)) * size.width
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: fx, y: 0))
                        p.addLine(to: CGPoint(x: fx, y: size.height))
                    },
                    with: .color(.red.opacity(0.7)), lineWidth: 1)
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rotation calibration objective")
        .accessibilityValue(String(
            format: "chosen angle %.2f degrees, %@ detector axes",
            result.rotationRad * 180 / .pi,
            result.transpose ? "transposed" : "untransposed"
        ))
    }
}
