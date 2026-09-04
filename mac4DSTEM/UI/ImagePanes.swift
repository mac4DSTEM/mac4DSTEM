import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// MARK: - Diffraction (CBED)

/// The live CBED pane: the pattern at the selected scan position (or the ROI
/// sum, or the mean/max pattern), with the aperture, disk and fit overlays.
///
/// **Structure**, unchanged from the view this replaces: a compact single-line
/// header, a `GeometryReader` letterboxing the pattern with
/// `LayoutPolicy.fitted(in:aspect:)`, the image and every overlay in ONE
/// transformed container so SwiftUI maps hit-testing through the transform
/// (overlay handles stay pixel-accurate at any zoom), and a `PaneFooter`
/// carrying the scale bar and the colorbar chip.
///
/// **Two migration fixes** (owner findings, 2026-09-04):
/// - The fitted image is pinned to the TOP of the available space rather than
///   centred, so the header sits directly above the image instead of across a
///   band of slack.
/// - Zoom is SwiftUI's own `scaleEffect`/`offset`; `MetalImageView` no longer
///   takes a zoom or an offset, so there is one transform rather than two that
///   can disagree.
struct DiffractionPane: View {
    @Environment(AppState.self) private var appState
    @State private var zp = ZoomPan()

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geometry in
                content(in: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        // A pane header is ~420 pt of `.fixedSize()` controls, and
        // `PaneSplit` hands a pane an explicit width rather than refusing
        // to go below its minimum the way `HSplitView` did. At the window's
        // own 1080 pt floor with both side columns wide, a pane can be
        // narrower than its header — clipping keeps that inside the pane
        // instead of overprinting the divider and its neighbour. The header
        // still needs to become compressible; recorded in `open-items.md`.
        .clipped()
        .contentShape(Rectangle())
        // `activePane` is the ROI direction's storage, and clicking a pane is
        // how the user chooses it. UI has no pane focus model at all — the
        // retired one was an inspector-routing rule, not this.
        .onTapGesture { appState.activePane = .diffraction }
        .overlay { ActivePaneOutline(pane: .diffraction) }
    }

    /// Everything here is single-line on purpose: a wrapping title or readout
    /// changes the header's height, which moves the image below it. The title
    /// yields first — the window title already names the task.
    private var header: some View {
        @Bindable var appState = appState
        return HStack {
            Text("Diffraction (CBED)")
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(-1)

            // A summed pattern must never look like a single-position one:
            // the ROI sum silently drives the probe kernel and the current-CBED
            // peak count (#24).
            if appState.patternDisplayMode == .current,
               appState.realSpaceShape != .point,
               appState.virtualDiffractionPattern != nil {
                Text("ROI sum")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize()
                    .help("This pattern is the sum over the real-space region, "
                          + "not the pattern at one scan position. Set the "
                          + "region shape to Point to see a single position.")
                    .accessibilityLabel("Showing a region-summed pattern, not a single scan position")
                    .accessibilityIdentifier("pattern.roiSumBadge")
            }

            Spacer(minLength: 8)

            // Mean/max become meaningful once calibration computes them.
            if appState.meanPattern != nil {
                Picker("Pattern source", selection: $appState.patternDisplayMode) {
                    ForEach(PatternDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Pattern source")
                .accessibilityIdentifier("pattern.displayMode")
            }

            if appState.fitOverlayIsAvailable {
                Toggle("Fit overlay", isOn: $appState.showFitOverlay)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Draw the fitted model (origin/ellipse, strain lattice, or matched template) over the pattern.")
            }

            if let pattern = appState.displayedPattern {
                Text("\(pattern.qx) × \(pattern.qy)")
                    .help("Detector Qx × Qy — columns × rows.")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let pattern = appState.displayedPattern {
            let qx = pattern.qx, qy = pattern.qy
            let box = LayoutPolicy.fitted(in: size, aspect: CGFloat(qx) / CGFloat(qy))
            let norm = appState.normalizedPatternPixels()   // cached per patternVersion

            ZStack {
                ZStack {
                    MetalImageView(
                        pixels: norm,
                        width: qx, height: qy,
                        contentVersion: appState.patternVersion,
                        colormap: appState.patternColormap,
                        displayLo: appState.patternDisplayRangeLo,
                        displayHi: appState.patternDisplayRangeHi,
                        gamma: appState.patternGamma
                    )
                    .frame(width: box.width, height: box.height)
                    .background(Color.black)

                    // Interactive annular aperture (Virtual Detector only).
                    if appState.navigation.analysisMode == .virtualDetector {
                        ApertureOverlay(
                            aperture: appState.aperture,
                            shape: appState.virtualShape,
                            patternWidth: qx, patternHeight: qy,
                            onEdited: { appState.updateAperture($0) },
                            onCommit: { appState.commitApertureChange() }
                        )
                    }

                    // Detected Bragg disks for the current pattern (Disks mode).
                    if appState.navigation.analysisMode == .disks,
                       !appState.currentPeaks.isEmpty {
                        PeakOverlay(
                            peaks: appState.currentPeaks,
                            probeRadius: appState.probeKernel?.probeRadius ?? 3,
                            patternWidth: qx, patternHeight: qy,
                            box: box
                        )
                        .allowsHitTesting(false)
                    }

                    // Fit verification: measured peaks against the fitted model
                    // (strain lattice / ACOM template / origin + ellipse).
                    let fitStrain = appState.strainFitOverlay
                    let fitTemplate = appState.acomFitOverlay
                    let fitOrigin = appState.originFitOverlayPoint
                    let fitEllipse = appState.ellipseFitOverlayPolyline
                    if fitStrain != nil || fitTemplate != nil
                        || fitOrigin != nil || !fitEllipse.isEmpty {
                        PatternFitOverlay(
                            strain: fitStrain,
                            template: fitTemplate,
                            originPoint: fitOrigin,
                            ellipse: fitEllipse,
                            measuredPeaks: (fitStrain != nil || fitTemplate != nil)
                                ? appState.storedPeaksAtSelection : [],
                            probeRadius: appState.probeKernel?.probeRadius ?? 3,
                            patternWidth: qx, patternHeight: qy,
                            box: box
                        )
                    }
                }
                .frame(width: box.width, height: box.height)
                .scaleEffect(zp.drawZoom)
                .offset(zp.effectiveOffset)
                .frame(width: box.width, height: box.height)
                .clipped()
                .contentShape(Rectangle())
                .border(Color.white.opacity(0.08))
                .zoomPan($zp, box: box)

                // Calibrated q-space scale bar (px fallback), zoom-aware, and
                // the intensity legend — one bottom row so they cannot collide
                // on a narrow pane.
                //
                // mrad shows the direct scattering angle, but falls back to the
                // reciprocal/px behaviour automatically if the Q calibration or
                // the voltage it needs disappears.
                PaneFooter {
                    if appState.patternScaleUnit == .milliradians,
                       let mradPerPixel = appState.dpcMilliradiansPerDetectorPixel {
                        ScaleBar(
                            unitsPerPoint: Double(mradPerPixel) * Double(qx)
                                / Double(box.width) / Double(zp.drawZoom),
                            unitLabel: "mrad")
                    } else {
                        let bar = appState.calibrationSession.calibration.diffractionScaleBar
                        ScaleBar(
                            unitsPerPoint: bar.perPixel * Double(qx)
                                / Double(box.width) / Double(zp.drawZoom),
                            unitLabel: bar.unitLabel)
                    }
                } trailing: {
                    if let range = appState.patternDisplayedValueRange {
                        // The chip IS the colormap control — click it.
                        ColormapChip(pane: .diffraction) {
                            Colorbar(
                                colormap: appState.patternColormap,
                                low: range.low,
                                high: range.high,
                                unitLabel: logScaleLabel,
                                gamma: appState.patternGamma
                            )
                        }
                    }
                }
            }
            .frame(width: box.width, height: box.height)
            // The image is pinned to the top of the pane, not centred in it,
            // so the header sits directly above it.
            // Centred, as Preview centres a photo. Top-pinning was tried
            // first (a review note about the header sitting far from the
            // image) and looked broken on screen: a square pattern in a tall,
            // narrow pane left ~400 pt of dead space below it, measured
            // 2026-09-04 in a 1470 pt window.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Diffraction pattern")
            .accessibilityValue("Scan X \(appState.selectedScan.x), Y \(appState.selectedScan.y); \(qx) by \(qy) detector pixels")
            .accessibilityHint("Pinch to zoom, drag to pan, or double click to reset")
        } else {
            ContentUnavailableView(
                "No Diffraction Pattern",
                systemImage: "circle.dashed",
                description: Text("Open a 4DSTEM .h5 file to view diffraction patterns")
            )
        }
    }

    private var logScaleLabel: String {
        appState.logScale ? "intensity · log display" : "intensity"
    }
}

// MARK: - Real space (the result viewer)

/// The real-space pane: whatever the current analysis produced — a virtual
/// detector image, a DPC map, a Bragg-vector map, strain, an IPF map — with
/// the scan-position selection, the ROI, and the legends the result calls for.
///
/// Same structure and the same two migration fixes as `DiffractionPane`.
struct RealSpacePane: View {
    /// Whether this pane offers the scan-position marker and click-to-scrub.
    ///
    /// False in Results (owner, 2026-09-04): the marker moves the position the
    /// DIFFRACTION pane reads, and Results has no diffraction pane, so it drew
    /// a control whose effect was invisible from where it was drawn.
    var allowsScanSelection = true

    @Environment(AppState.self) private var appState
    @State private var zp = ZoomPan()
    @State private var cursorSample: ProductSample?

    /// Name of the image+overlay container's coordinate space. The scan-marker
    /// handle reads its drag here rather than in `.local`, which for a
    /// `.position`ed view is that view's own frame, not the image's.
    private static let imageSpace = "realSpaceImage"

    /// The DPC colour wheel is scientific drawing, and a legend that is not
    /// round is not this legend — so it takes a size, as the pane's other
    /// scientific overlays do. Same size as the view this replaces.
    private static let colorWheelLegendSize: CGFloat = 54

    /// The scan navigator is a scientific thumbnail of the scan, not a control:
    /// it has to stay small and out of the result's way. Same width as before.
    private static let scanNavigatorWidth: CGFloat = 118

    /// Zoomed in means pan owns a plain drag and the marker owns its handle
    /// (backlog #35). See `RealSpacePointerPolicy` for why zooming *out* is
    /// deliberately still the scrub mode.
    private var isZoomed: Bool {
        RealSpacePointerPolicy.mode(zoom: zp.effectiveZoom) == .panAndGrab
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geometry in
                content(in: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        // A pane header is ~420 pt of `.fixedSize()` controls, and
        // `PaneSplit` hands a pane an explicit width rather than refusing
        // to go below its minimum the way `HSplitView` did. At the window's
        // own 1080 pt floor with both side columns wide, a pane can be
        // narrower than its header — clipping keeps that inside the pane
        // instead of overprinting the divider and its neighbour. The header
        // still needs to become compressible; recorded in `open-items.md`.
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { appState.activePane = .realSpace }
        .overlay { ActivePaneOutline(pane: .realSpace) }
        // Arrow-key scan stepping is NOT here. It has exactly one owner —
        // `WorkspaceView`, on the container holding both panes, which is where
        // the old window had it and which is what lets the keys work while
        // either pane holds focus. A second handler on this pane would be a
        // second copy of a scientific selection rule.
    }

    // MARK: Geometry of the displayed product

    /// Size of whichever result (scalar or RGBA) is active. While a quality
    /// field is being inspected, its own dimensions take precedence — it is
    /// scan-shaped like the result, but the view should never assume they
    /// match exactly.
    private var resultSize: (width: Int, height: Int)? {
        if let field = appState.displayedQualityField {
            return (field.image.width, field.image.height)
        }
        if let rgba = appState.displayedResultRGBA { return (rgba.width, rgba.height) }
        if let image = appState.displayedResultImage { return (image.width, image.height) }
        return nil
    }

    private var mapsScanPositions: Bool {
        guard allowsScanSelection,
              appState.displayedProduct?.domain == .scan,
              let dims = resultSize, let descriptor = appState.descriptor,
              dims.width == descriptor.rx, dims.height == descriptor.ry else {
            return false
        }
        return true
    }

    /// The display orientation applies to scan-domain products only, so a
    /// detector-domain result shown in this same viewer is never transformed.
    /// Shared with the export path so the figure and the screen can never
    /// disagree about what "as displayed" means.
    private var orientation: RealSpaceDisplayOrientation {
        appState.effectiveRealSpaceDisplayOrientation
    }

    private var mirrored: Bool { appState.effectiveRealSpaceDisplayMirrored }

    // MARK: Header

    /// Single-line on purpose: a wrapping title or cursor readout changes the
    /// header's height, which moves the image. The title yields first.
    private var header: some View {
        HStack {
            Text(appState.displayedResultName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(appState.displayedResultName)
                .accessibilityIdentifier("result.title")
            statusBadge
            staleBadge
            qualityToggle
            orientationControl
            zoomModeBadge

            Spacer(minLength: 8)

            if let dims = resultSize {
                Text("\(dims.width) × \(dims.height)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if appState.displayedProduct?.domain == .detector {
                // NAMED, because the app and py4DSTEM disagree about which
                // axis "qx" is: the file's order is [Ry, Rx, Qy, Qx], so the
                // app's qx is the columns, while py4DSTEM's qx is the rows.
                // Unnamed, these two glyphs contradicted the "Qx × Qy" printed
                // inches away and nobody could tell which convention was meant
                // (review, 2026-09-04).
                Text("py4DSTEM qᵧ →  ·  qₓ ↓")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("py4DSTEM's detector axes: its qy runs along the app's "
                          + "detector columns, its qx down the rows. The app's own "
                          + "Qx × Qy, shown elsewhere, is columns × rows.")
                    .accessibilityLabel("Detector axes: q y increases right, q x increases down")
            }
            if let sample = cursorSample {
                Text(sample.accessibilityText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("result.cursorReadout")
            }
        }
    }

    /// Persistent, coloured badge naming the displayed result's interpretation
    /// status — or, while a quality field is being inspected, a neutral badge
    /// naming that field instead of relabeling the scientific result.
    @ViewBuilder
    private var statusBadge: some View {
        if let field = appState.displayedQualityField {
            badge(text: "quality · \(field.name) (\(field.units))", color: .gray)
                .help("Interpretation status of the displayed result")
                .accessibilityLabel("Inspecting quality field \(field.name), units \(field.units)")
                .accessibilityIdentifier("result.statusBadge")
        } else if let status = appState.displayedProduct?.quantitativeStatus {
            badge(text: status.rawValue.capitalized, color: statusColor(status))
                .help("Interpretation status of the displayed result")
                .accessibilityLabel("Interpretation status: \(status.rawValue.capitalized)")
                .accessibilityIdentifier("result.statusBadge")
        }
    }

    /// The displayed Bragg-vector map was produced by settings the Bragg panel
    /// no longer holds (backlog #34). The app already knew this — the same flag
    /// gates strain and ACOM — but the *result pane* said nothing, so a map left
    /// over from an earlier run (including one left behind by a cancelled
    /// re-run) read as the current one. A displayed result has to carry its own
    /// validity; being correct in a panel the user is not looking at does not
    /// count.
    @ViewBuilder
    private var staleBadge: some View {
        if appState.navigation.analysisMode == .disks,
           appState.diskDetectionSettingsAreStale,
           appState.displayedResultKind == "bragg_vector_map" {
            badge(text: "Earlier settings", color: .orange)
                .help("This map was produced by the previous detection settings. "
                      + "Run Detect All Disks again to bring it up to date.")
                .accessibilityLabel(
                    "Stale: this map was produced by earlier detection settings"
                )
                .accessibilityIdentifier("result.staleBadge")
        }
    }

    /// Zooming in changes who owns a drag (#35), and a mode nobody can see is
    /// just confusing — so the pane says which one it is in, and how to leave.
    @ViewBuilder
    private var zoomModeBadge: some View {
        if isZoomed, mapsScanPositions {
            Text("Pan ×\(zp.effectiveZoom, specifier: "%.1f")")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .fixedSize()
                .help("Zoomed in: drag to pan, drag the white marker to move the "
                      + "scan position, double-click to reset. At 1× a click "
                      + "anywhere moves the scan position.")
                .accessibilityLabel(
                    "Zoomed to \(String(format: "%.1f", zp.effectiveZoom)) times; "
                        + "dragging pans, and the scan position moves by its marker handle"
                )
                .accessibilityIdentifier("result.zoomModeBadge")
        }
    }

    private func statusColor(_ status: ProductQuantitativeStatus) -> Color {
        switch status {
        case .quantitative: .green
        case .relative: .blue
        case .exploratory: .orange
        case .categorical: .purple
        }
    }

    /// A badge is a word in its colour, not a capsule; `fixedSize` so a narrow
    /// pane header never wraps it.
    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize()
    }

    /// Swap the viewer to the displayed product's paired quality field
    /// (strain ↔ fit residual, ACOM ↔ reliability). Display-only — it never
    /// touches the retained product, exports, or persistence. Hidden entirely
    /// when the displayed result carries no quality field.
    @ViewBuilder
    private var qualityToggle: some View {
        @Bindable var appState = appState
        if appState.displayedProduct?.qualityFields.isEmpty == false {
            Toggle(isOn: $appState.inspectQualityField) {
                Image(systemName: appState.inspectQualityField
                      ? "exclamationmark.magnifyingglass" : "checkmark.seal")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Inspect the quality field paired with this result (display only — exports and saved products are unchanged)")
            .accessibilityLabel(appState.inspectQualityField
                ? "Showing quality field; toggle to show the result"
                : "Inspect the quality field paired with this result")
            .accessibilityIdentifier("result.qualityToggle")
        }
    }

    /// View orientation for the real-space image (backlog #17b). Offered only
    /// for scan-domain products: the diffraction pattern must never get one,
    /// because the app already carries a measured R–Q rotation and a display
    /// rotation of the CBED would be indistinguishable from it.
    ///
    /// The wording deliberately says "View orientation … display only" rather
    /// than "rotate", so it cannot be read as the scientific rotation. The
    /// full sentence lives in `.help`: a long single-line `Text` inside a menu
    /// sets the whole flyout's width.
    @ViewBuilder
    private var orientationControl: some View {
        @Bindable var appState = appState
        if appState.displayedProduct?.domain == .scan {
            Menu {
                Picker("View orientation — display only",
                       selection: $appState.realSpaceDisplayOrientation) {
                    ForEach(RealSpaceDisplayOrientation.allCases) { orientation in
                        Text(orientation.displayName).tag(orientation)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Mirror horizontally", isOn: $appState.realSpaceDisplayMirrored)
            } label: {
                Image(systemName: appState.realSpaceDisplayIsDefault
                      ? "rotate.right" : "rotate.right.fill")
            }
            // `.borderlessButton` is deprecated; this is its documented
            // replacement, and unlike it, it exists on both platforms.
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .controlSize(.small)
            .help("View orientation of the real-space image — display only. "
                  + "This is not the measured R–Q rotation calibration.")
            .accessibilityLabel(
                "View orientation, display only, currently "
                    + appState.realSpaceDisplayOrientation.displayName
                    + (appState.realSpaceDisplayMirrored ? ", mirrored horizontally" : "")
            )
            .accessibilityIdentifier("result.viewOrientation")
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let dims = resultSize {
            let orientation = self.orientation
            let imageAspect = CGFloat(dims.width) / CGFloat(dims.height)
            // `box` is the footprint ON SCREEN, so it uses the rotated aspect;
            // `imageBox` is the container the image and its overlays are laid
            // out in, which stays in image orientation. A quarter turn swaps
            // one into the other.
            let box = LayoutPolicy.fitted(
                in: size, aspect: orientation.swapsAxes ? 1 / imageAspect : imageAspect
            )
            let imageBox = orientation.swapsAxes
                ? CGSize(width: box.height, height: box.width) : box
            // Quality inspection swaps the viewer to the paired quality field
            // (display only) — a distinct version space so the texture cache
            // re-uploads on toggle instead of reusing the scientific result's.
            let qualityField = appState.displayedQualityField
            let norm = qualityField != nil
                ? appState.normalizedQualityPixels() : appState.normalizedResultPixels()
            let effZoom = zp.drawZoom

            ZStack {
                // Image + overlays share ONE scaled container, so the marker,
                // ROI and click mapping stay aligned at any zoom (SwiftUI maps
                // hit-testing through the transform).
                //
                // The display orientation (#17b) is applied to that same shared
                // container, and the cursor/selection mapping lives INSIDE it.
                // So the inverse transform is applied by SwiftUI's own hit
                // testing: the inspector keeps reporting true scan indices
                // rather than following the rotation, without this view ever
                // hand-rolling an inversion that could drift from the forward
                // transform.
                ZStack {
                    MetalImageView(
                        pixels: norm,
                        width: dims.width, height: dims.height,
                        contentVersion: qualityField != nil
                            ? appState.displayedResultVersion &+ 0x4000_0000
                            : appState.displayedResultVersion,
                        colormap: qualityField != nil ? .viridis : appState.displayedResultColormap,
                        rgba: qualityField != nil ? nil : appState.displayedResultRGBA?.rgba,
                        displayLo: qualityField != nil ? 0 : appState.displayedResultRangeLo,
                        displayHi: qualityField != nil ? 1 : appState.displayedResultRangeHi,
                        gamma: qualityField != nil ? 1 : appState.displayedResultGamma
                    )
                    .frame(width: imageBox.width, height: imageBox.height)
                    .background(Color.black)

                    // Who owns a plain drag here depends on zoom (#35). At zoom
                    // 1 the whole pane scrubs, exactly as before. Zoomed in, the
                    // scrub layer is not mounted at all — that is what lets the
                    // drag fall through to the zoom/pan gesture and makes a
                    // zoomed real-space image pannable — and the marker gets its
                    // own grab handle instead.
                    if mapsScanPositions, !isZoomed {
                        selectionLayer(box: imageBox, imgW: dims.width, imgH: dims.height)
                            .frame(width: imageBox.width, height: imageBox.height)
                    }

                    // Marker at the current scan position.
                    if mapsScanPositions {
                        crosshair(box: imageBox, imgW: dims.width, imgH: dims.height)
                    }

                    // Region of interest for virtual diffraction (sum patterns).
                    if mapsScanPositions, appState.realSpaceShape != .point,
                       appState.realSpaceROIIsRelevant {
                        regionOverlay(box: imageBox, imgW: dims.width, imgH: dims.height)
                            .frame(width: imageBox.width, height: imageBox.height)
                    }
                }
                .frame(width: imageBox.width, height: imageBox.height)
                .coordinateSpace(.named(Self.imageSpace))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let x = min(dims.width - 1, max(0,
                            Int(location.x / max(imageBox.width, 1) * CGFloat(dims.width))))
                        let y = min(dims.height - 1, max(0,
                            Int(location.y / max(imageBox.height, 1) * CGFloat(dims.height))))
                        cursorSample = appState.displayedProduct?.sample(x: x, y: y)
                    case .ended:
                        cursorSample = nil
                    }
                }
                .rotationEffect(.degrees(orientation.degrees))
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .frame(width: box.width, height: box.height)
                .scaleEffect(effZoom)
                .offset(zp.effectiveOffset)
                .frame(width: box.width, height: box.height)
                .clipped()
                .contentShape(Rectangle())
                .border(Color.white.opacity(0.08))
                .zoomPan($zp, box: box)

                if appState.displayedProduct?.domain != .scan,
                   let navigator = appState.scanNavigationImage {
                    scanNavigator(navigator)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                }

                footer(dims: dims, box: box, orientation: orientation,
                       qualityField: qualityField, effZoom: effZoom)
            }
            .frame(width: box.width, height: box.height)
            // Pinned to the top of the pane, not centred in it, so the header
            // sits directly above the image.
            // Centred, as Preview centres a photo. Top-pinning was tried
            // first (a review note about the header sitting far from the
            // image) and looked broken on screen: a square pattern in a tall,
            // narrow pane left ~400 pt of dead space below it, measured
            // 2026-09-04 in a 1470 pt window.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(appState.displayedResultName)
            .accessibilityIdentifier("result.viewer")
            .accessibilityValue(cursorSample?.accessibilityText ?? (mapsScanPositions
                ? "Selected scan X \(appState.selectedScan.x), Y \(appState.selectedScan.y); \(dims.width) by \(dims.height) pixels"
                : "\(dims.width) by \(dims.height) pixels"))
            .accessibilityHint(mapsScanPositions
                ? "Use arrow keys to move the selected scan position; Shift moves ten pixels"
                : "Scientific image; scan-position selection is unavailable")
        } else if appState.hasDataset {
            ContentUnavailableView(
                "No Result Yet",
                systemImage: "square.grid.3x3",
                description: Text(pendingInstruction)
            )
        } else {
            ContentUnavailableView(
                "No Dataset Open",
                systemImage: "square.grid.3x3",
                description: Text("Open a 4DSTEM .h5 file to begin")
            )
        }
    }

    /// The scale bar and whichever legend the result calls for, in ONE bottom
    /// row: as independent bottom-leading / bottom-trailing overlays they drew
    /// straight through each other on a tall, narrow map.
    ///
    /// The bar is horizontal on screen and does NOT rotate, so it is computed
    /// against whichever image axis a quarter turn has put along the displayed
    /// horizontal — for a non-square scan that is a different R pixel size and
    /// a different pixel count, so a bar that merely re-rendered at the same
    /// length would be wrong (#17b).
    @ViewBuilder
    private func footer(
        dims: (width: Int, height: Int),
        box: CGSize,
        orientation: RealSpaceDisplayOrientation,
        qualityField: ProductQualityField?,
        effZoom: CGFloat
    ) -> some View {
        let pixel = appState.displayedResultPixelMetadata
        let sampling = orientation.swapsAxes
            ? (pixel.row ?? pixel.column) : (pixel.column ?? pixel.row)
        let pixelsAcross = orientation.swapsAxes ? dims.height : dims.width

        PaneFooter {
            ScaleBar(
                unitsPerPoint: (sampling ?? 1) * Double(pixelsAcross)
                    / Double(box.width) / Double(effZoom),
                unitLabel: sampling != nil ? (pixel.units ?? "px") : "px")
        } trailing: {
            // Order preserved from the separate overlays this replaced. **At
            // most one of these three ever renders**, and the stack claims no
            // benefit from that: `displayedResultKind` is one String, so it
            // cannot equal "dpc_color" AND contain "ipf_z"; the quality-field
            // colorbar needs `qualityField != nil` where both legends need it
            // nil; and the result colorbar needs `displayedResultImage != nil`,
            // which an RGBA result rules out because `resultImage` and
            // `resultRGBA` are always assigned as an exclusive pair. A VStack
            // rather than a Group only so the trailing slot has one child and
            // the order stays readable.
            VStack(alignment: .trailing, spacing: 6) {
                // Direction legend for the DPC colour wheel. Suppressed while
                // inspecting a quality field — the viewer is then showing a
                // scalar viridis map, not the colour-wheel-encoded result.
                if qualityField == nil, appState.displayedResultKind == "dpc_color" {
                    colorWheelLegend
                        .frame(width: Self.colorWheelLegendSize,
                               height: Self.colorWheelLegendSize)
                        .padding(2)
                }

                // Substring, not equality: the kind always carries a scope
                // (`acom_full_ipf_z`, `acom_preview_ipf_z`). Equality matched
                // only the un-suffixed full-scan spelling, so preview and
                // region IPF maps never got their colour key — and the
                // substring also keeps kinds saved before that change working
                // on reopen.
                if qualityField == nil, appState.displayedResultKind.contains("ipf_z") {
                    // The key's corner labels sit directly on scientific image
                    // data, so this plate is legibility, not chrome — the
                    // scale bar and the colorbar carry the same one. Without
                    // it "001 / 111 / 101" renders in the ambient label colour
                    // over an arbitrary orientation map.
                    Group {
                        if appState.acomSession.orientationMap?.symmetry == .hexagonal {
                            HexagonalIPFLegend()
                        } else {
                            CubicIPFLegend()
                        }
                    }
                    .padding(7)
                    .background(Color.black.opacity(0.48),
                                in: RoundedRectangle(cornerRadius: 4))
                }

                if let field = qualityField,
                   let range = appState.displayedQualityValueRange {
                    Colorbar(
                        colormap: .viridis,
                        low: range.low,
                        high: range.high,
                        unitLabel: field.units,
                        gamma: 1,
                        marksZero: false,
                        showsMasked: false
                    )
                    .allowsHitTesting(false)   // plain chip: no control behind it
                } else if appState.displayedResultImage != nil,
                          let range = appState.resultDisplayedValueRange {
                    // The chip IS the colormap control — click it. (The
                    // quality-field chip above stays plain: its map is fixed
                    // by design.)
                    ColormapChip(pane: .result) {
                        Colorbar(
                            colormap: appState.displayedResultColormap,
                            low: range.low,
                            high: range.high,
                            unitLabel: appState.displayedResultValueUnits,
                            gamma: appState.displayedResultGamma,
                            marksZero: appState.displayedResultColormap.isDiverging,
                            showsMasked: appState.displayedResultHasMaskedPixels()
                        )
                    }
                }
            }
        }
    }

    // MARK: Overlays

    /// A detector-domain result cannot be clicked to pick a scan position, so
    /// the scan gets its own small map to scrub in.
    private func scanNavigator(_ image: FloatImage) -> some View {
        let width = Self.scanNavigatorWidth
        let height = width * CGFloat(image.height) / CGFloat(max(image.width, 1))
        return ZStack {
            MetalImageView(
                pixels: image.normalized(),
                width: image.width, height: image.height,
                contentVersion: appState.scanNavigationVersion,
                colormap: .viridis
            )
            .frame(width: width, height: height)
            let x = (CGFloat(appState.selectedScan.x) + 0.5) / CGFloat(image.width) * width
            let y = (CGFloat(appState.selectedScan.y) + 0.5) / CGFloat(image.height) * height
            Circle().stroke(.white, lineWidth: 1.5)
                .background(Circle().stroke(.black, lineWidth: 3))
                .frame(width: 9, height: 9)
                .position(x: x, y: y)
        }
        .frame(width: width, height: height)
        .background(.black)
        .overlay(alignment: .topLeading) {
            Text("SCAN")
                // Fixed, not Dynamic Type: the navigator it labels is a fixed
                // scientific thumbnail, so a growing label would overrun it.
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(3)
        }
        .border(.white.opacity(0.55))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let x = Int(value.location.x / width * CGFloat(image.width))
            let y = Int(value.location.y / max(height, 1) * CGFloat(image.height))
            appState.scrubTo(x: x, y: y)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan navigator")
        .accessibilityValue("Selected scan X \(appState.selectedScan.x), Y \(appState.selectedScan.y)")
        .accessibilityHint("Click or drag to update the diffraction pattern")
        .accessibilityIdentifier("result.scanNavigator")
    }

    /// Hue wheel matching `DPC.colorWheelRGBA` (hue = atan2(cy,cx)/2π + 0.5),
    /// brightness growing with magnitude → dark centre.
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

    /// Whole-pane click/drag scrubbing. Mounted only at zoom 1 (#35) — the
    /// gesture a user makes a hundred times a session, unchanged.
    private func selectionLayer(box: CGSize, imgW: Int, imgH: Int) -> some View {
        // Drag (or click) to move the scan position live — the diffraction pane
        // streams the pattern as you go. minimumDistance 0 → a click also works.
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        // The same mapping the marker handle uses, so a click
                        // and a handle drag can never disagree about which
                        // pixel a point is in.
                        let scan = RealSpacePointerPolicy.scanPosition(
                            at: value.location,
                            imageWidth: imgW, imageHeight: imgH, box: box
                        )
                        appState.scrubTo(x: scan.x, y: scan.y)
                    }
            )
    }

    @ViewBuilder
    private func crosshair(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let center = RealSpacePointerPolicy.markerCenter(
            scan: appState.selectedScan, imageWidth: imgW, imageHeight: imgH, box: box
        )
        // Double-stroke marker so it reads on any colormap / brightness. Zoomed
        // in it is also the *only* way to move the scan position, so it gains a
        // filled centre and a larger target — the same white centre handle
        // vocabulary the aperture overlay uses in the diffraction pane.
        ZStack {
            if isZoomed {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .frame(width: 12, height: 12)
            }
            Circle().stroke(Color.black.opacity(0.75), lineWidth: 3.5)
            Circle().stroke(Color.white, lineWidth: 1.5)
        }
        .frame(width: isZoomed ? 20 : 11, height: isZoomed ? 20 : 11)
        .contentShape(Circle())
        .position(x: center.x, y: center.y)
        // Reading the drag in the image container's own named space rather than
        // `.local` — `.local` on a `.position`ed view is that view's own 20pt
        // frame, which would make the mapping below silently wrong.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.imageSpace))
                .onChanged { value in
                    let scan = RealSpacePointerPolicy.scanPosition(
                        at: value.location,
                        imageWidth: imgW, imageHeight: imgH, box: box
                    )
                    appState.scrubTo(x: scan.x, y: scan.y)
                },
            including: isZoomed ? .all : .none
        )
        .allowsHitTesting(isZoomed)
        .accessibilityLabel("Scan position marker")
        .accessibilityValue("X \(appState.selectedScan.x), Y \(appState.selectedScan.y)")
        .accessibilityHint(
            "Adjust to move horizontally, or use the named actions to move in any direction"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                appState.scrubTo(x: appState.selectedScan.x + 1, y: appState.selectedScan.y)
            case .decrement:
                appState.scrubTo(x: appState.selectedScan.x - 1, y: appState.selectedScan.y)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: "Move scan left") {
            appState.scrubTo(x: appState.selectedScan.x - 1, y: appState.selectedScan.y)
        }
        .accessibilityAction(named: "Move scan right") {
            appState.scrubTo(x: appState.selectedScan.x + 1, y: appState.selectedScan.y)
        }
        .accessibilityAction(named: "Move scan up") {
            appState.scrubTo(x: appState.selectedScan.x, y: appState.selectedScan.y - 1)
        }
        .accessibilityAction(named: "Move scan down") {
            appState.scrubTo(x: appState.selectedScan.x, y: appState.selectedScan.y + 1)
        }
        .accessibilityIdentifier("result.scanMarkerHandle")
    }

    /// Rectangle / circle ROI centred on the selected scan position, with a
    /// resize handle. Summed patterns from inside it feed the diffraction pane.
    private func regionOverlay(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let scaleX = box.width / CGFloat(imgW)
        let scaleY = box.height / CGFloat(imgH)
        let radiusScale = (scaleX + scaleY) / 2
        let center = CGPoint(x: (CGFloat(appState.selectedScan.x) + 0.5) * scaleX,
                             y: (CGFloat(appState.selectedScan.y) + 0.5) * scaleY)
        let r = CGFloat(appState.realSpaceRadius) * radiusScale
        return ZStack {
            Group {
                if appState.realSpaceShape == .circle {
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
                .position(x: center.x + r,
                          y: appState.realSpaceShape == .circle ? center.y : center.y + r)
                .gesture(
                    DragGesture(coordinateSpace: .local)
                        .onChanged { value in
                            let dx = abs(value.location.x - center.x)
                            let dy = abs(value.location.y - center.y)
                            let newR = appState.realSpaceShape == .circle
                                ? hypot(dx, dy) : max(dx, dy)
                            appState.realSpaceRadius = max(1, Float((newR / radiusScale).rounded()))
                        }
                )
        }
    }

    // MARK: Keyboard


    /// The empty pane names the action that produces ITS result — the old
    /// single string told a pane titled "Bragg vector map" to "adjust the
    /// aperture", which cannot produce one.
    private var pendingInstruction: String {
        switch appState.navigation.analysisMode {
        case .virtualDetector:
            "Adjust the aperture or pick a detector preset to generate an image"
        case .dpc:
            "Run DPC to map beam deflection across the scan"
        case .disks:
            "Run Detect All Disks to produce the Bragg vector map"
        case .strain:
            "Compute Strain after detecting Bragg disks"
        case .acom:
            "Run ACOM after detecting Bragg disks and choosing a material"
        case .ptychography, .singleslicePtychography:
            "Prepare the parallax preview to begin reconstruction"
        }
    }
}

// MARK: - Which pane the Direction control drives

/// An accent outline on the pane the Imaging Direction currently drives.
///
/// Owner, 2026-09-04: "the app needs an indicator which the active plane is
/// because the settings plane changes and it is confusing when setting the
/// detector." This is NOT the retired pane focus model — it routes nothing and
/// writes nothing. It draws the answer to one question the Settings tab
/// already asks: which of the two panes does dragging act on. It therefore
/// appears only in Imaging, the one workspace where that choice exists;
/// elsewhere `activePane` decides nothing and an outline would be noise.
struct ActivePaneOutline: View {
    @Environment(AppState.self) private var appState
    let pane: ActivePane

    var body: some View {
        if appState.navigation.workspaceArea == .image,
           appState.hasDataset,
           appState.activePane == pane {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
