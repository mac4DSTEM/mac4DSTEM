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
        .frame(width: 720, height: 640)
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

    private var previews: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preview = pending.preview {
                Text(preview.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("configurator.previewSummary")
                HStack(alignment: .top, spacing: 16) {
                    cropPane(
                        title: "Scan — real space",
                        subtitle: "Sets which scan positions load",
                        pixels: preview.realSpace.pixels,
                        width: preview.realSpace.width,
                        height: preview.realSpace.height,
                        colormap: .gray,
                        identifier: "configurator.scanCrop",
                        crop: pending.configuration.scanCrop,
                        cropSpaceWidth: pending.source.rx,
                        cropSpaceHeight: pending.source.ry
                    ) { rectangle in
                        pending.configuration.scanCrop = LoadConfiguration.scanCrop(
                            from: rectangle,
                            strideY: preview.strideY, strideX: preview.strideX,
                            source: pending.source
                        )
                    }
                    cropPane(
                        title: "Diffraction — detector",
                        subtitle: "Sets which detector pixels load",
                        pixels: preview.maxDP.pixels,
                        width: preview.maxDP.qx,
                        height: preview.maxDP.qy,
                        colormap: .viridis,
                        identifier: "configurator.detectorCrop",
                        crop: pending.configuration.detectorCrop,
                        cropSpaceWidth: pending.source.qx,
                        cropSpaceHeight: pending.source.qy
                    ) { rectangle in
                        pending.configuration.detectorCrop = LoadConfiguration.detectorCrop(
                            from: rectangle, source: pending.source
                        )
                    }
                }
                Text("Both images are samples, not results — they will not match a virtual image pixel for pixel.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No preview available for this dataset. The sizes below are still exact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One draggable preview. The rectangle is reported in the image's own pixel
    /// coordinates; converting those to a crop is `LoadConfiguration`'s job, and
    /// the two conversions differ — the real-space preview is on the sampled
    /// grid and the diffraction preview is not.
    private func cropPane(
        title: String,
        subtitle: String,
        pixels: [Float],
        width: Int,
        height: Int,
        colormap: ColormapKind,
        identifier: String,
        crop: AxisCrop?,
        cropSpaceWidth: Int,
        cropSpaceHeight: Int,
        onDrag: @escaping (DragRectangle) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    MetalImageView(
                        pixels: pixels, width: width, height: height,
                        contentVersion: pixels.count &+ width &* 31 &+ height,
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
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            onDrag(rectangle(from: value, in: size,
                                             width: width, height: height))
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
        HStack {
            Button("Reset") {
                pending.configuration.scanCrop = nil
                pending.configuration.detectorCrop = nil
                pending.configuration.detectorBin = 1
            }
            .disabled(pending.configuration.specification.isFullExtent)
            .accessibilityIdentifier("configurator.reset")
            if let refusal = pending.refusalReason {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { appState.discardPendingLoad() }
                .keyboardShortcut(.cancelAction)
            Button("Load") { appState.commitPendingLoad() }
                .keyboardShortcut(.defaultAction)
                .disabled(pending.view == nil)
                .accessibilityIdentifier("configurator.load")
        }
        .padding(20)
    }
}
