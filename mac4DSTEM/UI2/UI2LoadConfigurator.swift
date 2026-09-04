//
//  UI2LoadConfigurator.swift
//  Role: L5's configurator in UI2 — decide what to load, while the decision is
//        still cheap, from a preview of the actual data.
//
//  The migration of `UI/LoadConfiguratorView` into UI2. Every number, every
//  refusal, every caption that states a scientific consequence and every
//  accessibility identifier is carried over unchanged; only the platform
//  bridge (`UI2MetalImage`, which takes no zoom) and the layout helper
//  (`UI2Metrics.fitted`) differ.
//
//  VOCABULARY (L5 item 4, plan §1). Everything here says **crop**, and a crop
//  is not an ROI. A crop changes what data exists in the loaded view; an ROI
//  selects among data already loaded. They are never in the same section, and
//  this screen is not reachable once a dataset is open — by construction,
//  since it exists only before one is.
//
//  WHAT THE COPY MUST NOT IMPLY (plan §6, L5). Loading into memory does not
//  make the load faster: #30 measured the cost as the link, not the algorithm.
//  It makes the waiting happen once, at a moment the user chose. Copy that
//  promised speed would make the feature read as broken.
//
//  THE TRAP PRE-EMPTED IN THE LABELS. A strided preview and a real virtual
//  image WILL differ, and a user comparing them will file a bug.
//  `DatasetPreview` states its own stride and the caption below repeats that
//  these are samples — scoped per pane, because the single-position pattern is
//  exact and a blanket caveat would teach the user to distrust the one pane
//  that is not a sample.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct UI2LoadConfigurator: View {
    @Environment(AppState.self) private var appState
    let pending: PendingLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Divider()
            // The previews are the science and take the space; the choices
            // under them are a grouped Form, which scrolls when the sheet is
            // short so the footer — Load and its refusal — stays on screen.
            previews
                .padding(.horizontal)
                .padding(.top)
            Form {
                binSection
                sizeSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        // A band, not a fixed size: the 2026-08-18 fixed 900x760 sheet
        // overflowed a display shorter than ~790pt and pushed its own footer
        // off screen.
        .frame(
            minWidth: UI2Metrics.configuratorSheet.min.width,
            idealWidth: UI2Metrics.configuratorSheet.ideal.width,
            minHeight: UI2Metrics.configuratorSheet.min.height,
            idealHeight: UI2Metrics.configuratorSheet.ideal.height
        )
    }

    // MARK: - Title

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Load \(pending.url.lastPathComponent)")
                .font(.headline)
            // The one permanent caption here: that a crop never touches the
            // file is a consequence the user cannot infer from the controls.
            Text("Crop before loading. The source file is never changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - The preview panes

    /// All three panes draw pixels `PendingLoad` normalised when the data
    /// landed — `UI2MetalImage`'s contract, and the one the old view broke
    /// until 2026-08-18. `realSpace` holds the *sum* of every detector pixel
    /// at a scan position (10⁴–10⁸ on a real cube) and the fragment shader
    /// clamps to [0,1], so raw values collapse to the top LUT entry and both
    /// panes render one flat colour. The diffraction panes are log-normalised
    /// for the same reason the rest of the app logs a max-DP: linear, it is
    /// the central beam and nothing else.
    @ViewBuilder
    private var previews: some View {
        if let preview = pending.preview,
           let realSpace = pending.realSpaceDisplay,
           let maxDP = pending.maxDPDisplay {
            VStack(alignment: .leading, spacing: 8) {
                Text(preview.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configurator.previewSummary")

                // One closure for BOTH detector panes: they set the same crop,
                // and two hand-written copies of the drag→crop conversion is
                // how the two panes end up drawing the same rectangle while
                // setting different ones.
                let setDetectorCrop: (DragRectangle) -> Void = { rectangle in
                    pending.configuration.detectorCrop = LoadConfiguration.detectorCrop(
                        from: rectangle, source: pending.source
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    cropPane(
                        title: "Scan — real space",
                        subtitle: "Drag to crop · click to pick a pattern",
                        image: realSpace,
                        colormap: .gray,
                        identifier: "configurator.scanCrop",
                        crop: pending.configuration.scanCrop,
                        cropSpaceWidth: pending.source.rx,
                        cropSpaceHeight: pending.source.ry,
                        onTap: { imageX, imageY in
                            // The preview owns its own stride, so IT does the
                            // sampled-grid → source conversion — the view
                            // hand-rolling the multiplication is the F1.10
                            // defect class.
                            let position = preview.sourcePosition(
                                forSampledX: Int(imageX), sampledY: Int(imageY)
                            )
                            pending.fetchSingleDP(ry: position.ry, rx: position.rx)
                        }
                    ) { rectangle in
                        pending.configuration.scanCrop = LoadConfiguration.scanCrop(
                            from: rectangle,
                            strideY: preview.strideY, strideX: preview.strideX,
                            source: pending.source
                        )
                    }

                    cropPane(
                        title: "Diffraction — max",
                        subtitle: "Sets which detector pixels load",
                        image: maxDP,
                        colormap: .viridis,
                        identifier: "configurator.detectorCrop",
                        crop: pending.configuration.detectorCrop,
                        cropSpaceWidth: pending.source.qx,
                        cropSpaceHeight: pending.source.qy,
                        onDrag: setDetectorCrop
                    )

                    // One REAL pattern beside the max (owner request,
                    // 2026-08-18). Same crop binding as the max pane — both
                    // draw the same detector rectangle, and a drag on either
                    // sets it.
                    if let singleDP = pending.singleDPDisplay {
                        cropPane(
                            title: "Diffraction — single position",
                            subtitle: singlePatternCaption,
                            image: singleDP,
                            colormap: .viridis,
                            identifier: "configurator.singleDP",
                            crop: pending.configuration.detectorCrop,
                            cropSpaceWidth: pending.source.qx,
                            cropSpaceHeight: pending.source.qy,
                            onDrag: setDetectorCrop
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diffraction — single position")
                                .font(.callout.weight(.medium))
                            Text(singlePatternCaption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .frame(
                                    minHeight: UI2Metrics.imagePaneMinimum,
                                    maxHeight: UI2Metrics.thumbnailMaximumHeight
                                )
                                .accessibilityIdentifier("configurator.singleDPPlaceholder")
                        }
                    }
                }

                // Scoped per pane on purpose: the sampling caveat is TRUE for
                // the strided panes and FALSE for the single-position pane,
                // which shows the recorded pattern exactly — a blanket "all
                // images are samples" would teach the user to distrust the one
                // pane that is exact (invariant I4 works because the label is
                // accurate, not merely present).
                Text("Real-space and max previews are sampled. The single-position pattern is exact.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("No preview available for this dataset. The sizes below are still exact.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The single-DP pane's caption: names the position the pattern came from,
    /// because an unlabelled "some pattern" invites comparing it with the wrong
    /// scan position and filing the difference as a bug.
    private var singlePatternCaption: String {
        if let position = pending.singleDPPosition {
            return "Pattern at scan (\(position.ry), \(position.rx)) — click the scan preview to change"
        }
        return "Click the scan preview to pick a position"
    }

    /// One draggable preview. The rectangle is reported in the image's own
    /// pixel coordinates; converting those to a crop is `LoadConfiguration`'s
    /// job, and the two conversions differ — the real-space preview is on the
    /// sampled grid and the diffraction preview is not.
    ///
    /// `onTap`, when given, receives a plain click in the same image-pixel
    /// coordinates. A click below `DragGesture`'s minimum distance never starts
    /// a drag, so the two gestures do not compete.
    private func cropPane(
        title: String,
        subtitle: String,
        image: PendingLoad.DisplayImage,
        colormap: ColormapKind,
        identifier: String,
        crop: AxisCrop?,
        cropSpaceWidth: Int,
        cropSpaceHeight: Int,
        onTap: ((Double, Double) -> Void)? = nil,
        onDrag: @escaping (DragRectangle) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geometry in
                // LETTERBOX, do not stretch. The display shader maps the image
                // to normalized view UVs, so handing it the full pane draws
                // e.g. an 84x100 scan into a 270x227 box — a circular
                // diffraction disk renders elliptical and, worse, a user
                // dragging a visually SQUARE box gets a non-square crop.
                // Measured on screen 2026-08-27: a 100x98pt drag on sim_Au
                // produced `63 x 45`, exactly 54% of width by 63% of height.
                // The crop arithmetic was right; the picture was lying about
                // what was being selected.
                //
                // Sizing the ZStack to `box` also fixes the gestures for free —
                // tap and drag then work in the box's own coordinate space, so
                // no letterbox offset has to be subtracted anywhere.
                let box = UI2Metrics.fitted(
                    in: geometry.size,
                    aspect: CGFloat(image.width) / CGFloat(max(image.height, 1))
                )
                ZStack(alignment: .topLeading) {
                    UI2MetalImage(
                        pixels: image.pixels,
                        width: image.width, height: image.height,
                        // The version was computed once, when the pixels were
                        // produced (`PendingLoad.DisplayImage`) — value- and
                        // dimension-dependent, and O(1) here, so a drag tick
                        // costs no per-frame hashing.
                        contentVersion: image.version,
                        colormap: colormap
                    )
                    .frame(width: box.width, height: box.height)
                    .background(Color.black)

                    if let crop {
                        // Drawn from the CROP, not from the drag — so what is
                        // outlined is what will actually load, including the
                        // clamping and the bin trim the crop went through.
                        let scaleX = box.width / CGFloat(max(cropSpaceWidth, 1))
                        let scaleY = box.height / CGFloat(max(cropSpaceHeight, 1))
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                            .frame(
                                width: CGFloat(crop.width) * scaleX,
                                height: CGFloat(crop.height) * scaleY
                            )
                            .offset(
                                x: CGFloat(crop.xOffset) * scaleX,
                                y: CGFloat(crop.yOffset) * scaleY
                            )
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: box.width, height: box.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard let onTap, box.width > 0, box.height > 0 else { return }
                    onTap(Double(location.x) * Double(image.width) / Double(box.width),
                          Double(location.y) * Double(image.height) / Double(box.height))
                }
                .gesture(
                    // 8pt, not 2: with a tap gesture on the same pane, a click
                    // whose cursor drifts a few points during the press must
                    // stay a CLICK — at 2pt it became a drag, silently setting
                    // a one-preview-pixel crop while the pattern pick appeared
                    // to do nothing. 8pt is still far below any deliberate
                    // crop drag.
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            onDrag(rectangle(from: value, in: box,
                                             width: image.width, height: image.height))
                        }
                )
                // Centre the letterboxed box in the pane it no longer fills.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Science: a preview below this stops being an image; above the cap
            // it stops leaving room for the arithmetic underneath.
            .frame(
                minHeight: UI2Metrics.imagePaneMinimum,
                maxHeight: UI2Metrics.thumbnailMaximumHeight
            )
            .accessibilityIdentifier(identifier)
        }
    }

    /// Convert a drag in view points to the image's pixel coordinates.
    ///
    /// Clamping to the image happens in `LoadConfiguration`, not here — a drag
    /// that leaves the view is a normal gesture and the model already treats
    /// "past the edge" as "to the edge".
    private func rectangle(
        from value: DragGesture.Value, in size: CGSize, width: Int, height: Int
    ) -> DragRectangle {
        guard size.width > 0, size.height > 0 else {
            return DragRectangle(startX: 0, startY: 0, endX: 0, endY: 0)
        }
        let scaleX = Double(width) / Double(size.width)
        let scaleY = Double(height) / Double(size.height)
        return DragRectangle(
            startX: Double(value.startLocation.x) * scaleX,
            startY: Double(value.startLocation.y) * scaleY,
            endX: Double(value.location.x) * scaleX,
            endY: Double(value.location.y) * scaleY
        )
    }

    // MARK: - Bin factor

    private var binSection: some View {
        Section("Diffraction binning") {
            // Crop and bin trade against DIFFERENT things (release owner's
            // question, 2026-08-19); both mirror py4DSTEM
            // (crop_data_diffraction / bin_data_diffraction).
            Text("Crop limits angular range. Binning keeps the range but coarsens disk positions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Bin factor", selection: Binding(
                get: { pending.configuration.detectorBin },
                set: { pending.configuration.detectorBin = $0 }
            )) {
                Text("None").tag(1)
                ForEach(LoadSpecification.availableBinFactors, id: \.self) { factor in
                    Text("\(factor)x").tag(factor)
                }
            }
            .accessibilityIdentifier("configurator.binFactor")
            if pending.configuration.detectorBin > 1 {
                // The intensity consequence, before the load rather than after.
                Text("Counts become \(pending.configuration.detectorBin * pending.configuration.detectorBin)x larger; reciprocal pixels become \(pending.configuration.detectorBin)x coarser. Recheck absolute thresholds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let edge = pending.discardedEdge {
                Text("Trims \(edge.rows) row(s) and \(edge.columns) column(s) from the bottom/right edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configurator.edgeTrim")
            }
        }
    }

    // MARK: - What it costs

    private var sizeSection: some View {
        Section("Size") {
            // Axis-labelled in the inspector's own convention (owner request,
            // 2026-08-18), so this is not a third ordering variant.
            sizeRow("Scan (Rx × Ry)", "\(pending.source.rx) × \(pending.source.ry)")
            sizeRow("Detector (Qx × Qy)", "\(pending.source.qx) × \(pending.source.qy)")
            if let fileBytes = pending.fileByteCount {
                sizeRow("File on disk", ui2ByteString(fileBytes))
            }
            sizeRow("Whole cube (f32)", ui2ByteString(pending.fullExtentByteCount))
            if let loaded = pending.loadedByteCount {
                sizeRow(
                    "This selection (f32)",
                    ui2ByteString(loaded)
                        + (pending.reductionSummary.map { " · \($0)" } ?? "")
                )
            }
            if let shape = pending.loadedShapeString {
                sizeRow("Loaded shape", shape)
            }
            // NOT a budget for this load: `recommendedMaxWorkingSetSize` is a
            // hardware property (~65% of physical RAM on Apple Silicon); the
            // old "GPU budget" label under the load sizes invited a load that
            // would get an 8 GB Mac killed. The memory a load actually uses is
            // bounded in `FourDArray.scanTileRows`.
            sizeRow("GPU working-set limit",
                    String(format: "%.0f MB", SystemMonitor.gpuWorkingSetMB))
            // Reads return float32 whatever the file stores, so a uint16 file
            // costs twice its own size — the surprise this screen exists to
            // remove.
            Text("Float32 expansion can exceed file size. Loading into memory moves the wait upfront; analyses still stream in bounded tiles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sizeRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).monospacedDigit()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        // One read of each predicate per body pass: the refusal the user sees
        // and the disabled state of the button must come from the SAME
        // evaluation, or a future dependency that mutates mid-pass shows a
        // refusal beside an enabled Load. (`commitPendingLoad` re-checks the
        // gate model-side regardless.)
        let beamRefusal = pending.directBeamRefusal
        let refusal = pending.refusalReason ?? beamRefusal
        return VStack(alignment: .leading, spacing: 12) {
            if let refusal {
                // Its own row, not squeezed between Reset and Cancel: these are
                // whole sentences naming detector rows and columns, and a
                // refusal the user cannot read is not a refusal.
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("configurator.refusal")
            }
            HStack {
                Button("Reset") {
                    pending.configuration.scanCrop = nil
                    pending.configuration.detectorCrop = nil
                    pending.configuration.detectorBin = 1
                }
                .disabled(pending.configuration.specification.isFullExtent)
                .accessibilityIdentifier("configurator.reset")
                Spacer()
                Button("Cancel") { appState.discardPendingLoad() }
                    .keyboardShortcut(.cancelAction)
                Button("Load") { appState.commitPendingLoad() }
                    .keyboardShortcut(.defaultAction)
                    // The beam guard REFUSES the load, it does not warn: on a
                    // first open there is no calibration for the re-reference
                    // refusal to fire on, so this is the only gate.
                    .disabled(pending.view == nil || beamRefusal != nil)
                    .accessibilityIdentifier("configurator.load")
            }
        }
        .padding()
    }
}
