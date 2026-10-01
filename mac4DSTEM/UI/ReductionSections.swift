//
//  ReductionSections.swift
//  Role: the pieces the load configurator and the preprocessing sheet share —
//        the three preview panes (drag to crop, click to pick a pattern), the
//        diffraction-binning section and the size rows both sheets open with.
//        They were `LoadConfigurator`'s own; extracted, not copied, so the two
//        sheets cannot drift apart (X3, 2026-10-01). Wording, identifiers and
//        every number are unchanged.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// MARK: - The preview panes

/// The preview panes of a `PendingLoad`: scan, max pattern, one real pattern.
struct ReductionPreviewPanes: View {
    let pending: PendingLoad

    var body: some View {
        previews
    }

    /// All three panes draw pixels `PendingLoad` normalised when the data
    /// landed — `MetalImageView`'s contract. `realSpace` holds the *sum* of
    /// every detector pixel at a scan position (10⁴–10⁸ on a real cube) and
    /// the fragment shader
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

                    // One REAL pattern beside the max. Same crop binding as
                    // the max pane — both draw the same detector rectangle,
                    // and a drag on either sets it.
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
                            Group {
                            if let failure = pending.singleDPFailure {
                                Text("Could not load this pattern: \(failure)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .frame(
                                    minHeight: LayoutPolicy.imagePaneMinimum,
                                    maxHeight: LayoutPolicy.thumbnailMaximumHeight
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
            let reason = pending.previewFailure.map { " (\($0))" } ?? ""
            Text("No preview available for this dataset.\(reason) The sizes below are still exact.")
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
                // dragging a visually SQUARE box gets a non-square crop: a
                // 100x98pt drag on sim_Au produces `63 x 45`, 54% of width by
                // 63% of height (measured 2026-08-27) even though the crop
                // arithmetic itself is correct.
                //
                // Sizing the ZStack to `box` also fixes the gestures for free —
                // tap and drag then work in the box's own coordinate space, so
                // no letterbox offset has to be subtracted anywhere.
                let box = LayoutPolicy.fitted(
                    in: geometry.size,
                    aspect: CGFloat(image.width) / CGFloat(max(image.height, 1))
                )
                ZStack(alignment: .topLeading) {
                    MetalImageView(
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
                minHeight: LayoutPolicy.imagePaneMinimum,
                maxHeight: LayoutPolicy.thumbnailMaximumHeight
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

}

// MARK: - Bin factor

/// "Diffraction binning": the bin factor and what it does to counts and edges.
struct ReductionBinSection: View {
    let pending: PendingLoad


    var body: some View {
        Section("Diffraction binning") {
            // Crop and bin trade against DIFFERENT things; both mirror
            // py4DSTEM (crop_data_diffraction / bin_data_diffraction).
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

}

// MARK: - What it costs

/// The size rows both sheets open with: what is stored, and what it would be
/// whole. Callers add their own rows under it (the configurator its load
/// selection and memory switch, the preprocessing sheet its output).
struct ReductionSizeRows: View {
    let pending: PendingLoad

    var body: some View {
        // Axis-labelled in the inspector's own convention, so this is not
        // a third ordering variant.
        ReductionSizeRow("Scan (Rx × Ry)", "\(pending.source.rx) × \(pending.source.ry)")
        ReductionSizeRow("Detector (Qx × Qy)", "\(pending.source.qx) × \(pending.source.qy)")
        if let fileBytes = pending.fileByteCount {
            ReductionSizeRow("File on disk", displayByteString(fileBytes))
        }
        ReductionSizeRow("Whole cube (f32)", displayByteString(pending.fullExtentByteCount))
    }
}

struct ReductionSizeRow: View {
    private let label: String
    private let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        LabeledContent(label) {
            Text(value).monospacedDigit()
        }
    }
}
