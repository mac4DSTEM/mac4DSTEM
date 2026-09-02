import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// S22a: the sixteen stacked sections this view had accreted are regrouped
/// into the four approved by `docs/s22-ux-design.md` §4.3 — Dataset, Live,
/// Diagnostics, Products — and the view now lives in a system inspector
/// column, so everything here sizes to the column width the user drags.
/// Shown while no pane claims the focus ring or a live pane does; the Results
/// pane gets `ProductInspector` instead (v2.5 step 7c, `WorkspaceInspector`).
struct DatasetInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if let descriptor = appState.descriptor {
                datasetGroup(descriptor)
                liveGroup
                InspectorDiagnosticsGroup()   // shared with ProductInspector (7c)
                Section("Products") {
                    ProductsView()
                }
            } else {
                Text("No dataset loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Dataset (file, dimensions, preview, loaded view)

    @ViewBuilder
    private func datasetGroup(_ descriptor: DatasetDescriptor) -> some View {
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

            subheader("Dimensions")
            row("Scan (Ry x Rx)", "\(descriptor.ry) x \(descriptor.rx)")
            row("Detector (Qy x Qx)", "\(descriptor.qy) x \(descriptor.qx)")
            if let acceleratingVoltage = appState.calibrationSession.acceleratingVoltage {
                row("Accel. voltage", String(format: "%.0f kV", acceleratingVoltage))
            }

            if let preview = appState.datasetPreview {
                // INVARIANT I4: a sampled preview is not a result. The
                // summary states the stride and is drawn FIRST, above the
                // images, so nothing here can be read as a virtual image.
                // A strided preview and a real virtual image will differ,
                // and a user comparing them will file a bug — this label is
                // the thing that pre-empts it.
                subheader("Preview")
                Text(preview.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            // WHAT IS ACTUALLY LOADED, and what that cost the calibration.
            //
            // L4's "state them in the UI" and "label the result" (invariant
            // I3): a cropped or binned cube is a DIFFERENT MEASUREMENT, and
            // until this section existed the app knew that and never said
            // it. `LoadedView`'s whole display surface had no reader.
            //
            // Absent at full extent, deliberately — a permanent row reading
            // "no crop" on every dataset is noise, and the block's
            // presence is itself the signal that something was reduced.
            if !appState.loadedView.isFullExtent {
                subheader("Loaded view")
                if let summary = appState.loadedView.summary {
                    Text(summary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
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
                // block because the block exists exactly when
                // promotion is meaningful: a reduced view is loaded.
                // Promotion is a reopen of the SOURCE at full extent —
                // removing the specification, never re-deriving from
                // reduced data — so the cost stated is the whole
                // cube's, which is the number the user is deciding
                // about.
                VStack(alignment: .leading, spacing: 4) {
                    Button("Reopen at Full Extent") {
                        // The one-action promote (v2 S6): with a
                        // recorded recipe this reopens AND replays;
                        // with none it is the plain S3 reopen.
                        Task { await appState.promoteAndReplayRecipe() }
                    }
                    .disabled(appState.isLoadingDataset
                              || appState.replayRun.isRunning)
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
                    PromoteRunCaption(
                        record: appState.replay.record,
                        frame: appState.replay.parameterFrame
                    )
                }
            }
        }
    }

    // MARK: - Live (scan position, aperture, histograms)

    @ViewBuilder
    private var liveGroup: some View {
        Section("Live") {
            subheader("Current scan position")
            row("x (Rx)", "\(appState.selectedScan.x)")
            row("y (Ry)", "\(appState.selectedScan.y)")
            if let (lowerBound, upperBound) = appState.patternMinMax {
                row("Pattern min", String(format: "%.3g", lowerBound))
                row("Pattern max", String(format: "%.3g", upperBound))
            }

            // v2.5 step 7c: the focused pane's descriptor decides. With no
            // claim yet (workspaces before their slice) the 7b per-task
            // conditions stand in — an adapter that expires at slice 5.
            let pane = appState.navigation.focusedPane
            let showsAperture = pane?.showsAperture ?? appState.inspectorShowsAperture
            let showsDiffractionHistogram =
                pane?.showsDiffractionHistogram ?? appState.inspectorShowsDiffractionHistogram
            let showsRealSpaceHistogram = pane?.showsRealSpaceHistogram ?? true

            if showsAperture {
                subheader("Aperture (detector px)")
                row("Center x", String(format: "%.1f", appState.aperture.centerX))
                row("Center y", String(format: "%.1f", appState.aperture.centerY))
                row("Inner r", String(format: "%.1f", appState.aperture.inner))
                row("Outer r", String(format: "%.1f", appState.aperture.outer))
            }

            if showsRealSpaceHistogram, let image = appState.resultImage {
                subheader("Histogram (real space)")
                HistogramView(pixels: image.pixels, version: appState.resultVersion,
                              rangeLo: Bindable(appState).displayRangeLo,
                              rangeHi: Bindable(appState).displayRangeHi)
                Text("Drag the handles to clip which intensities map into the image.")
                    .font(.caption2).foregroundStyle(.tertiary)
                gammaControl("Gamma", value: Bindable(appState).resultGamma)
            }

            if showsDiffractionHistogram, let pattern = appState.displayedPattern {
                subheader("Histogram (diffraction)")
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
    }

    // MARK: - Shared row/label helpers

    /// A labelled block boundary inside one of the four groups. Sub-blocks
    /// were previously sixteen top-level `Section`s; the caps style keeps
    /// them scannable without sixteen headers' worth of chrome.
    private func subheader(_ title: String) -> some View { inspectorSubheader(title) }

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

    /// One preview thumbnail, filling the inspector column's width (S22a):
    /// dragging the inspector wider is how the preview grows — the fixed
    /// 120pt cap this replaces is what made the preview permanently tiny
    /// (owner playthrough 2026-09-01, finding O5).
    private func previewImage(
        _ label: String, pixels: [Float], width: Int, height: Int,
        colormap: ColormapKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            MetalImageView(
                pixels: pixels, width: width, height: height,
                // `datasetPreview` is written exactly once per open, so the
                // dataset epoch IS this image's version — it changes precisely
                // when the preview does, including a same-shape swap (the
                // defect the old dims-only hash could not see), and it is O(1)
                // in a sidebar body that re-evaluates on every AppState
                // change. // v2 S4
                contentVersion: appState.datasetEpoch,
                colormap: colormap, zoom: 1, offset: .zero
            )
            // LETTERBOX. `MetalImageView` maps the image to normalized view
            // UVs, so a height-only frame stretches it to the sidebar's full
            // width: a 128x128 mean or max pattern was drawn about 300x120,
            // i.e. 2.5x wider than tall, and every Bragg disk rendered as a
            // horizontal ellipse — in the app that has an ellipse-calibration
            // feature for measuring exactly that distortion. The 200x50 real
            // space preview was squashed the other way. Reported by the release
            // owner from the inspector on 2026-08-27, same root cause as the
            // configurator panes fixed the same day; this is the third call
            // site of the class, after those and the main window (which was
            // already correct).
            .aspectRatio(
                CGFloat(width) / CGFloat(max(height, 1)), contentMode: .fit
            )
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("preview.\(label.replacingOccurrences(of: " ", with: ""))")
        }
        .padding(.vertical, 2)
    }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        inspectorRow(label, value, mono: mono)
    }

    private func byteString(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1024 {
            return String(format: "%.2f GB", megabytes / 1024)
        }
        return String(format: "%.1f MB", megabytes)
    }
}

/// The promote button's replay price tag (v2 S6). Its own view so the plan is
/// re-derived only when the recipe or its frame changes, not on every
/// cursor-driven inspector invalidation — and so the caption and the executor
/// read the SAME pure plan: a promise the run is already known to break is
/// stated as the halt it will be, before the click (Gate A findings B5/E3,
/// 2026-08-25).
private struct PromoteRunCaption: View {
    let record: SessionReplayRecord
    let frame: ReplayParameterFrame?

    var body: some View {
        if !record.steps.isEmpty {
            let planned = ReplayPlanner.plan(record, frame: frame ?? .unknown)
            let titles = planned.map(\.title).joined(separator: ", ")
            let count = planned.count
            // The keep-awake honesty limit is stated where the decision is
            // made: an idle-sleep assertion does not survive a closed lid.
            Text("Then replays this session's \(count) recorded "
                 + (count == 1 ? "analysis" : "analyses")
                 + " in order (\(titles)), keeping this Mac awake while it "
                 + "runs (lid open). A step that fails halts the run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.promoteReplayCaption")
            // A re-referenced replay is never a silent substitution: the
            // numbers the entry points will receive are exact re-expressions
            // of the rehearsal's, and the caption says so BEFORE the click —
            // shown only when a step actually carries detector numbers, so a
            // DPC-only recipe does not claim a mapping it never uses. // v2 S10
            if let note = frame?.reReferenceDescription,
               planned.contains(where: {
                   if case .success(let plan) = $0.result {
                       plan.usesDetectorFrameParameters
                   } else { false }
               }) {
                Text("Recipe \(note) — the exact inverse of the load-time re-reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.promoteReplayReReference")
            }
            if let firstRefused = planned.firstIndex(where: {
                if case .failure = $0.result { true } else { false }
            }), case .failure(let refusal) = planned[firstRefused].result {
                Text(firstRefused == 0
                     ? "This recipe cannot replay here — \(planned[0].title): \(refusal.reason). The button reopens at full extent and re-runs the current analysis instead."
                     : "The run will halt at step \(firstRefused + 1) (\(planned[firstRefused].title)): \(refusal.reason)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.promoteReplayRefusal")
            }
        }
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
