//
//  LoadConfiguratorView.swift
//  Role: L5's configurator — decide what to load, while the decision is still
//        cheap, from a preview of the actual data.
//
//  VOCABULARY (L5 item 4, plan §1). Everything here says **crop**, and a crop is
//  not an ROI. A crop changes what data exists in the loaded view; an ROI
//  (`realSpaceShape`, `acomRegionRadius`, strain's "current real-space ROI")
//  selects among data already loaded. They are never in the same section, and
//  this screen is not reachable once a dataset is open — by construction, since
//  it exists only before one is.
//
//  WHAT THE COPY MUST NOT IMPLY (plan §6, L5). Loading into memory does not make
//  the load faster: #30 measured the cost as the link, not the algorithm. It
//  makes the waiting happen once, at a moment the user chose. Copy that promised
//  speed would make the feature read as broken.
//
//  THE TRAP PRE-EMPTED IN THE LABELS. A strided preview and a real virtual image
//  WILL differ, and a user comparing them will file a bug. `DatasetPreview`
//  states its own stride and the caption below repeats that these are samples.
//

import SwiftUI

struct LoadConfiguratorView: View {
    @Environment(AppState.self) private var appState
    let pending: PendingLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previews
                    binPicker
                    sizeArithmetic
                }
                .padding(20)
            }
            Divider()
            footer
        }
        // 900×760: sized so the standing content fits WITHOUT scrolling — the
        // 720×640 sheet scrolled and clipped its own headers (open item,
        // 2026-08-18). Honest limit: a FIXED height means that on a display
        // shorter than ~790pt the sheet itself overflows and the footer (with
        // the Load button and the refusal text) is what gets pushed off — the
        // inner ScrollView cannot help with that, it only scrolls content
        // *inside* the frame. Every supported Mac's built-in panel is taller;
        // scaled external displays may not be. Recorded on Track B row F1.17;
        // a content-driven sheet height is the real fix if it ever bites.
        // // v2 S4
        .frame(width: 900, height: 760)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Load \(pending.url.lastPathComponent)")
                .font(.headline)
            Text("Drag on either preview to load only part of the dataset. The source file is never changed, and removing a crop later reloads the whole thing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    // MARK: - The two previews

    /// Both panes MUST pass normalized pixels — `MetalImageView`'s contract, and
    /// the one this view broke until 2026-08-18. `realSpace` holds the *sum* of
    /// every detector pixel at a scan position (10⁴–10⁸ on a real cube) and the
    /// fragment shader clamps to [0,1], so raw values collapsed to the top LUT
    /// entry and both panes rendered one flat colour. It reads as "no image",
    /// not as "wrong scaling", which is why it survived a Track B pass.
    /// The diffraction pane needs `useLog: true` as well: linear-normalized, a
    /// max-DP is the central beam and nothing else — drawing, but useless for
    /// choosing a detector crop.
    private var previews: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = pending.preview,
               let realSpace = pending.realSpaceDisplay,
               let maxDP = pending.maxDPDisplay {
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
                                .font(.caption2).foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                                .frame(height: 220)
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
                Text("Real-space and max are built from the sampled positions only — they will not match a virtual image pixel for pixel. The single-position pane is the recorded pattern at that scan position, exactly.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No preview available for this dataset. The sizes below are still exact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    /// One draggable preview. The rectangle is reported in the image's own pixel
    /// coordinates; converting those to a crop is `LoadConfiguration`'s job, and
    /// the two conversions differ — the real-space preview is on the sampled
    /// grid and the diffraction preview is not.
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
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    MetalImageView(
                        pixels: image.pixels, width: image.width, height: image.height,
                        // The version was computed once, when the pixels were
                        // produced (`PendingLoad.DisplayImage`) — value- and
                        // dimension-dependent, and O(1) here, so a drag tick
                        // costs no per-frame hashing. // v2 S4
                        contentVersion: image.version,
                        colormap: colormap, zoom: 1, offset: .zero
                    )
                    if let crop {
                        // Drawn from the CROP, not from the drag — so what is
                        // outlined is what will actually load, including the
                        // clamping and the bin trim the crop went through.
                        let scaleX = size.width / CGFloat(cropSpaceWidth)
                        let scaleY = size.height / CGFloat(cropSpaceHeight)
                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .background(Color.accentColor.opacity(0.12))
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
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard let onTap, size.width > 0, size.height > 0 else { return }
                    onTap(Double(location.x) * Double(image.width) / Double(size.width),
                          Double(location.y) * Double(image.height) / Double(size.height))
                }
                .gesture(
                    // 8pt, not 2: with a tap gesture on the same pane, a click
                    // whose cursor drifts a few points during the press must
                    // stay a CLICK — at 2pt it became a drag, silently setting
                    // a one-preview-pixel crop while the pattern pick appeared
                    // to do nothing. 8pt is still far below any deliberate
                    // crop drag. // v2 S4
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            onDrag(rectangle(from: value, in: size,
                                             width: image.width, height: image.height))
                        }
                )
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private var binPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diffraction binning").font(.callout.weight(.medium))
            // Crop and bin are siblings on this panel but they trade against
            // DIFFERENT things (release owner's question, 2026-08-19: "why is
            // cropping in there at all, instead of only binning?"). Both
            // mirror py4DSTEM (crop_data_diffraction / bin_data_diffraction);
            // the panel owes the user the difference. // v2 S4
            Text("A detector crop and a bin reduce different things. A crop cuts the angular range — scattering outside the box is never loaded, so crop when the disks you need sit in a small part of the detector. Binning keeps the full range but coarsens it, which costs sub-pixel disk-position precision — the quantity strain mapping is fitted from.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Diffraction binning", selection: Binding(
                get: { pending.configuration.detectorBin },
                set: { pending.configuration.detectorBin = $0 }
            )) {
                Text("None").tag(1)
                ForEach(LoadSpecification.availableBinFactors, id: \.self) { factor in
                    Text("\(factor)x").tag(factor)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("configurator.binFactor")
            if pending.configuration.detectorBin > 1 {
                // The intensity consequence, before the load rather than after.
                Text("Binning sums the pixels it merges, so intensities become \(pending.configuration.detectorBin * pending.configuration.detectorBin)x larger and the reciprocal pixel size \(pending.configuration.detectorBin)x coarser. Absolute-intensity thresholds from an unbinned run will not carry over.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let edge = pending.discardedEdge {
                Text("The detector does not divide evenly: \(edge.rows) row(s) and \(edge.columns) column(s) will be trimmed from the far edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("configurator.edgeTrim")
            }
        }
    }

    // MARK: - What it costs

    private var sizeArithmetic: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Size").font(.callout.weight(.medium))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                // The cube's dimensions, stated in the dialog (owner request,
                // 2026-08-18). Axis-labelled in the inspector's own
                // convention, so this does not become a third ordering variant
                // of the two-orders display already under S18.
                sizeRow("Scan (Ry x Rx)", "\(pending.source.ry) x \(pending.source.rx)")
                sizeRow("Detector (Qy x Qx)", "\(pending.source.qy) x \(pending.source.qx)")
                if let fileBytes = pending.fileByteCount {
                    sizeRow("File on disk", SystemMonitor.byteString(fileBytes))
                }
                sizeRow("Whole cube (f32)", SystemMonitor.byteString(pending.fullExtentByteCount))
                if let loaded = pending.loadedByteCount {
                    sizeRow(
                        "This selection (f32)",
                        SystemMonitor.byteString(loaded)
                            + (pending.reductionSummary.map { " · \($0)" } ?? "")
                    )
                }
                if let shape = pending.loadedShapeString {
                    sizeRow("Loaded shape", shape)
                }
                sizeRow("GPU budget", String(format: "%.0f MB", SystemMonitor.gpuWorkingSetMB))
            }
            .font(.callout)
            // Reads return float32 whatever the file stores, so a uint16 file
            // costs twice its own size. Said here because the file size is
            // right above it and the difference otherwise looks like an error.
            Text("Data is read as float32 regardless of how the file stores it, so the cube can be larger than the file. Loading into memory does not make the load faster — it makes the waiting happen once, when you choose.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sizeRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        // One read of each predicate per body pass: the refusal the user sees
        // and the disabled state of the button must come from the SAME
        // evaluation, or a future dependency that mutates mid-pass shows a
        // refusal beside an enabled Load. (`commitPendingLoad` re-checks the
        // gate model-side regardless.) // v2 S4
        let beamRefusal = pending.directBeamRefusal
        return HStack {
            Button("Reset") {
                pending.configuration.scanCrop = nil
                pending.configuration.detectorCrop = nil
                pending.configuration.detectorBin = 1
            }
            .disabled(pending.configuration.specification.isFullExtent)
            .accessibilityIdentifier("configurator.reset")
            if let refusal = pending.refusalReason ?? beamRefusal {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .accessibilityIdentifier("configurator.refusal")
            }
            Spacer()
            Button("Cancel") { appState.discardPendingLoad() }
                .keyboardShortcut(.cancelAction)
            Button("Load") { appState.commitPendingLoad() }
                .keyboardShortcut(.defaultAction)
                // The beam guard REFUSES the load, it does not warn: on a
                // first open there is no calibration for the re-reference
                // refusal to fire on, so this is the only gate. // v2 S4
                .disabled(pending.view == nil || beamRefusal != nil)
                .accessibilityIdentifier("configurator.load")
        }
        .padding(20)
    }
}
