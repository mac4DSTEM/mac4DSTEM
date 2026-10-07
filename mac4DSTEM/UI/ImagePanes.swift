import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

// MARK: - Diffraction (CBED)

/// The noun for the pattern on screen, shared by the diffraction pane and the
/// inspector's statistics rows, so "Pattern min" can never silently describe a
/// mean, a max or a region sum.
enum PatternSourceLabel {
    static func noun(mode: PatternDisplayMode, roiSummed: Bool) -> String {
        switch mode {
        case .current: roiSummed ? "ROI-sum pattern" : "Pattern"
        case .mean: "Mean pattern"
        case .max: "Max pattern"
        }
    }
}

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
/// **Two migration fixes** (owner findings):
/// - The fitted image is pinned to the TOP of the available space rather than
///   centred, so the header sits directly above the image instead of across a
///   band of slack.
/// - Zoom is SwiftUI's own `scaleEffect`/`offset`; `MetalImageView` no longer
///   takes a zoom or an offset, so there is one transform rather than two that
///   can disagree.
struct DiffractionPane: View {
    @Environment(AppState.self) private var appState
    /// "Show scale bar" (session S21, `Session/AppPreferences.swift`) — read
    /// directly from the environment rather than through `AppState`, since
    /// nothing but this pane's own footer (and `RealSpacePane`'s) needs it.
    @Environment(AppPreferences.self) private var preferences
    @State private var zp = ZoomPan()
    /// "Show claimed disks" (phase-mapping task): a per-viewer display
    /// preference, so it lives with the view and not in `AppState`.
    @AppStorage("phaseMapping.showClaimedDisks") private var showClaimedDisks = true

    /// The claimed-disks overlay exists once a phase map has run.
    private var claimedDisksAvailable: Bool {
        appState.navigation.analysisMode == .phaseMapping && appState.phaseMapping.map != nil
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
        // `PaneSplit` hands a pane an explicit width rather than refusing
        // to go below its minimum the way `HSplitView` did, so the header
        // is compressible (`ViewThatFits`) and the clip is the backstop:
        // whatever still does not fit stays inside the pane instead of
        // overprinting the divider and its neighbour.
        .clipped()
        .contentShape(Rectangle())
        .overlay { ActivePaneOutline(pane: .diffraction) }
        .selectsPaneOnClick(.diffraction)
    }

    /// Everything here is single-line on purpose: a wrapping title or readout
    /// changes the header's height, which moves the image below it. The title
    /// yields first — the window title already names the task.
    ///
    /// Two layouts, the first that fits wins (`PaneSplit` residual (a)): the
    /// full row, or — below the width its `.fixedSize()` controls need — the
    /// title, the ROI badge and one overflow menu holding the same controls.
    /// Neither announces a minimum width upward, which is the constraint-loop
    /// rule (`open-items.md`).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            fullHeader
            compactHeader
        }
        // One constant height for both panes' headers: the diffraction
        // header's regular-size picker made it taller than the real-space
        // one, so the two images, each centred below its header, sat a few
        // points apart (observed on a real cube).
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    private var title: some View {
        Text("Diffraction (CBED)")
            .font(.headline)
            .lineLimit(1)
            .layoutPriority(-1)
    }

    /// A summed pattern must never look like a single-position one: the ROI
    /// sum silently drives the probe kernel and the current-CBED peak count
    /// (#24).
    @ViewBuilder
    private var roiSumBadge: some View {
        if appState.patternDisplayMode == .current,
           appState.realSpaceShape != .point,
           appState.resultPresentation.virtualDiffractionPattern != nil {
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
    }

    private var compactHeader: some View {
        @Bindable var appState = appState
        return HStack {
            title
            roiSumBadge
            Spacer(minLength: 8)
            if appState.meanPattern != nil || appState.fitOverlays.isAvailable
                || claimedDisksAvailable {
                Menu {
                    if appState.meanPattern != nil {
                        Picker("Pattern source", selection: $appState.patternDisplayMode) {
                            ForEach(PatternDisplayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    if appState.fitOverlays.isAvailable {
                        Toggle("Fit overlay", isOn: $appState.showFitOverlay)
                    }
                    if claimedDisksAvailable {
                        Toggle("Show claimed disks", isOn: $showClaimedDisks)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .fixedSize()
                .help("Pattern source and overlay controls — the pane is too narrow to show them in the header")
                .accessibilityLabel("Pattern display controls")
                .accessibilityIdentifier("pattern.compactControls")
            }
        }
    }

    private var fullHeader: some View {
        @Bindable var appState = appState
        return HStack {
            title
            roiSumBadge

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

            if appState.fitOverlays.isAvailable {
                Toggle("Fit overlay", isOn: $appState.showFitOverlay)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel("Fit overlay")
                    .help("Draw the fitted model (origin/ellipse, strain lattice, or matched template) over the pattern. In Prepare it also greys, in the real-space image, the scan positions the origin fit's robust trim excluded.")
            }

            if claimedDisksAvailable {
                Toggle("Show claimed disks", isOn: $showClaimedDisks)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel("Show claimed disks")
                    .help("Ring each detected disk at this scan position in the colour of the phase that claimed it: the matrix, a precipitate phase, or unexplained.")
                    .accessibilityIdentifier("pattern.showClaimedDisks")
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
            // Fit verification: read once for the overlay (in the zoomed layer) and its key chip (outside it).
            let fit = appState.fitOverlays
            // Each of these is computed on read (geometry is rebuilt), so they
            // are read ONCE per body and shared by the overlay and its key.
            let fitStrain = fit.strain
            let fitTemplate = fit.template
            let fitOrigin = fit.originPoint
            let fitEllipse = fit.ellipse
            let fitLegend = PatternFitOverlay.legendText(
                strain: fitStrain, template: fitTemplate,
                originPoint: fitOrigin, ellipse: fitEllipse)

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
                            shape: appState.resultPresentation.virtualShape,
                            patternWidth: qx, patternHeight: qy,
                            onEdited: { appState.updateAperture($0) },
                            onCommit: { appState.commitApertureChange() }
                        )
                        .equatable()
                    }

                    // Detected Bragg disks for the current pattern (Disks mode).
                    if appState.navigation.analysisMode == .disks,
                       !appState.currentPeaks.isEmpty {
                        PeakOverlay(
                            peaks: appState.currentPeaks,
                            probeRadius: appState.probeKernel?.probeRadius,
                            patternWidth: qx, patternHeight: qy,
                            box: box
                        )
                        .allowsHitTesting(false)
                    }

                    // Hand-clicked disk-centre labels (Disks mode only —
                    // labelling is one scan position at a time). Shown once
                    // there is something to show, or while the click-mode
                    // toggle is on so the user can see where a click would
                    // land.
                    if appState.navigation.analysisMode == .disks {
                        let labels = appState.diskCentreLabels
                        let centres = labels.centres(
                            ry: appState.selectedScan.y, rx: appState.selectedScan.x
                        )
                        if labels.labelling || !centres.isEmpty {
                            CentreLabelOverlay(
                                centres: centres, patternWidth: qx, patternHeight: qy, box: box
                            )
                            .allowsHitTesting(false)
                        }
                        if labels.labelling {
                            // `.simultaneousGesture`, not `.gesture`: this
                            // view sits inside the same ZStack `.zoomPan`
                            // attaches to (pinch/pan/double-tap-to-reset),
                            // so labelling must coexist with those gestures.
                            Color.clear
                                .frame(width: box.width, height: box.height)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    SpatialTapGesture().onEnded { value in
                                        let px = PeakOverlayGeometry.pixel(
                                            at: value.location,
                                            patternWidth: qx, patternHeight: qy, box: box
                                        )
                                        _ = appState.toggleDiskCentre(atPatternRow: px.y, col: px.x)
                                    }
                                )
                        }
                    }

                    // Phase mapping: which phase claimed each detected disk here.
                    if claimedDisksAvailable, showClaimedDisks {
                        PhaseClaimLayer(patternWidth: qx, patternHeight: qy, box: box)
                    }

                    // Fit verification: measured peaks against the fitted model
                    // (strain lattice / ACOM template / origin + ellipse).
                    if fitStrain != nil || fitTemplate != nil
                        || fitOrigin != nil || !fitEllipse.isEmpty {
                        PatternFitOverlay(
                            strain: fitStrain,
                            template: fitTemplate,
                            originPoint: fitOrigin,
                            ellipse: fitEllipse,
                            measuredPeaks: (fitStrain != nil || fitTemplate != nil)
                                ? fit.storedPeaksAtSelection : [],
                            probeRadius: appState.probeKernel?.probeRadius,
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

                // The scan navigator, for a result whose pixels cannot be clicked to choose a
                // scan position (a Bragg-vector map, a reconstruction): top-trailing, beside the
                // pattern it drives, and OUTSIDE the zoomed, clipped layer so it keeps its size
                // and its corner at any zoom and a drag on it never pans the pattern. It used to
                // cover the result map (owner card Q3 a, 2026-10-04).
                if ScanNavigatorPlacement.isShown(domain: appState.displayedProduct?.domain,
                                                  hasImage: appState.scanNavigationImage != nil),
                   let navigator = appState.scanNavigationImage {
                    ScanNavigatorInset(image: navigator)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                }

                // Calibrated q-space scale bar (px fallback), zoom-aware, and
                // the intensity legend — one bottom row so they cannot collide
                // on a narrow pane.
                //
                // mrad shows the direct scattering angle, but falls back to the
                // reciprocal/px behaviour automatically if the Q calibration or
                // the voltage it needs disappears.
                PaneFooter {
                    if preferences.showScaleBar {
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
                                unitLabel: CalibrationUnitConversion.displayLabel(bar.unitLabel))
                        }
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

                // The fit overlay's key, at the pane's top-leading corner and OUTSIDE the zoomed, clipped
                // layer: drawn in image space it was scaled and clipped away when zoomed (P7b). The
                // diffraction pane has nothing else in this corner (the scale bar and colorbar are at the
                // bottom; the SCAN navigator, when shown, is at the opposite, top-trailing corner).
                if !fitLegend.isEmpty {
                    PatternFitLegend(text: fitLegend)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: box.width, height: box.height)
            // Centred, as Preview centres a photo. Top-pinning was tried
            // first (a review note about the header sitting far from the
            // image) and looked broken on screen: a square pattern in a tall,
            // narrow pane left ~400 pt of dead space below it (measured in a
            // 1470 pt window).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Diffraction pattern")
            .accessibilityValue("Scan X \(appState.selectedScan.x), Y \(appState.selectedScan.y); \(qx) by \(qy) detector pixels")
            .accessibilityHint("Pinch to zoom, drag to pan, or double click to reset. The Zoom in, Zoom out and Reset zoom actions do the same.")
            .zoomPanAccessibilityActions($zp, box: box)
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

/// A small map of the scan with the selected position marked, to click or drag
/// in: a detector-domain or reconstruction result cannot be clicked to pick a
/// scan position, so the scan gets one of its own (`ScanNavigatorPlacement`
/// decides when). Drawn by `DiffractionPane`, at its top-trailing corner, beside
/// the pattern it drives; in the real-space pane it covered the result's data
/// (the lattice of a reconstruction, the upper right of a Bragg-vector map:
/// polish drive 2026-10-01; owner card Q3 a, 2026-10-04).
///
/// A scientific thumbnail of the scan, not a control: it stays small and out of
/// the pattern's way, at the scan's aspect ratio inside one fixed box (its longer
/// side is `ScanNavigatorPlacement.maxSide`; a 17 x 77 scan once drew 534 pt tall).
struct ScanNavigatorInset: View {
    @Environment(AppState.self) private var appState
    let image: FloatImage

    var body: some View {
        let size = ScanNavigatorPlacement.size(rx: image.width, ry: image.height)
        let width = size.width, height = size.height
        ZStack {
            MetalImageView(
                pixels: appState.normalizedScanNavigationPixels(of: image),
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
            let at = ScanNavigatorPlacement.scanPosition(at: value.location, in: size,
                                                         rx: image.width, ry: image.height)
            appState.scrubTo(x: at.x, y: at.y)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan navigator")
        .accessibilityValue("Selected scan X \(appState.selectedScan.x), Y \(appState.selectedScan.y)")
        .accessibilityHint("Click or drag to update the diffraction pattern")
        .accessibilityIdentifier("result.scanNavigator")
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
    /// False in Results: the marker moves the position the DIFFRACTION pane
    /// reads, and Results has no diffraction pane, so it drew a control
    /// whose effect was invisible from where it was drawn.
    var allowsScanSelection = true

    @Environment(AppState.self) private var appState
    /// "Show scale bar" (session S21, `Session/AppPreferences.swift`).
    @Environment(AppPreferences.self) private var preferences
    /// The object table's selection (nil where no app scene provides it).
    @Environment(PrecipitateTableSelection.self) private var tableSelection: PrecipitateTableSelection?
    @State private var zp = ZoomPan()
    /// The pointer's sample lives in a reference holder that THIS view never
    /// reads: a hover tick writes it, and only `CursorReadout` and
    /// `CursorAccessibilityValue` (which read it) re-evaluate. As `@State`
    /// value it re-ran the whole pane body — overlays, caches, legend — on
    /// every pointer move (review 2026-10-07, F1).
    @State private var cursor = CursorSampleModel()

    /// Name of the image+overlay container's coordinate space. The scan-marker
    /// handle reads its drag here rather than in `.local`, which for a
    /// `.position`ed view is that view's own frame, not the image's.
    private static let imageSpace = "realSpaceImage"

    /// The DPC colour wheel is scientific drawing, and a legend that is not
    /// round is not this legend — so it takes a size, as the pane's other
    /// scientific overlays do. Same size as the view this replaces.
    private static let colorWheelLegendSize: CGFloat = 54

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
        // `PaneSplit` hands a pane an explicit width rather than refusing
        // to go below its minimum the way `HSplitView` did, so the header
        // is compressible (`ViewThatFits`) and the clip is the backstop:
        // whatever still does not fit stays inside the pane instead of
        // overprinting the divider and its neighbour.
        .clipped()
        .contentShape(Rectangle())
        .overlay { ActivePaneOutline(pane: .realSpace) }
        .selectsPaneOnClick(.realSpace)
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

    /// The origin trim's mask when it is this scan's and Prepare is judging it
    /// (`FitOverlayPresentation.originTrim` decides; the pane only draws).
    private func originTrim(matching dims: (width: Int, height: Int))
        -> FitOverlays.OriginTrimOverlay? {
        // `appState.originTrimOverlay` is `fitOverlays.originTrim`, remembered
        // against the origin mask instead of re-walked on every body.
        guard let trim = appState.originTrimOverlay,
              trim.width == dims.width, trim.height == dims.height else { return nil }
        return trim
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
    ///
    /// Two layouts, the first that fits wins (`PaneSplit` residual (a)): the
    /// full row, or — below the ~420 pt its `.fixedSize()` controls need —
    /// title, badges, cursor readout and one overflow menu holding the
    /// quality toggle and the view orientation. Neither layout announces a
    /// minimum width upward (the constraint-loop rule).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            fullHeader
            compactHeader
        }
        // One constant height for both panes' headers: the diffraction
        // header's regular-size picker made it taller than the real-space
        // one, so the two images, each centred below its header, sat a few
        // points apart (observed on a real cube).
        .frame(height: LayoutPolicy.paneHeaderHeight)
    }

    private var title: some View {
        Text(appState.displayedResultName)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(appState.displayedResultName)
            .accessibilityIdentifier("result.title")
    }

    private var cursorReadout: some View {
        CursorReadout(model: cursor)
    }

    private var compactHeader: some View {
        HStack {
            title
            statusBadge
            staleBadge
            zoomModeBadge
            Spacer(minLength: 8)
            cursorReadout
            compactControls
        }
    }

    /// The same controls as `qualityToggle` and `orientationControl`, bound
    /// to the same state, as menu items.
    @ViewBuilder
    private var compactControls: some View {
        @Bindable var appState = appState
        @Bindable var resultPresentation = appState.resultPresentation
        let hasQuality = appState.displayedProduct?.qualityFields.isEmpty == false
        let isScan = appState.displayedProduct?.domain == .scan
        if hasQuality || isScan {
            Menu {
                if hasQuality {
                    Toggle("Inspect quality field", isOn: $resultPresentation.inspectQualityField)
                }
                if isScan {
                    Picker("View orientation — display only",
                           selection: $appState.realSpaceDisplayOrientation) {
                        ForEach(RealSpaceDisplayOrientation.allCases) { orientation in
                            Text(orientation.displayName).tag(orientation)
                        }
                    }
                    .pickerStyle(.inline)
                    Toggle("Mirror horizontally", isOn: $appState.realSpaceDisplayMirrored)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .fixedSize()
            .help("Display controls — the pane is too narrow to show them in the header")
            .accessibilityLabel("More display controls")
            .accessibilityIdentifier("result.compactControls")
        }
    }

    private var fullHeader: some View {
        HStack {
            title
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
                // inches away and nobody could tell which convention was meant.
                Text("py4DSTEM qᵧ →  ·  qₓ ↓")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("py4DSTEM's detector axes: its qy runs along the app's "
                          + "detector columns, its qx down the rows. The app's own "
                          + "Qx × Qy, shown elsewhere, is columns × rows.")
                    .accessibilityLabel("Detector axes: q y increases right, q x increases down")
            }
            cursorReadout
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
        @Bindable var resultPresentation = appState.resultPresentation
        if appState.displayedProduct?.qualityFields.isEmpty == false {
            Toggle(isOn: $resultPresentation.inspectQualityField) {
                Image(systemName: appState.resultPresentation.inspectQualityField
                      ? "exclamationmark.magnifyingglass" : "checkmark.seal")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Inspect the quality field paired with this result (display only — exports and saved products are unchanged)")
            .accessibilityLabel(appState.resultPresentation.inspectQualityField
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
            // Read once per body; the legend (footer) takes the same value.
            let trim = mapsScanPositions ? originTrim(matching: dims) : nil

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

                    // Positions the origin fit's robust trim excluded (S23):
                    // a wash in the shared container, so it follows zoom,
                    // rotation and mirroring with the image it marks.
                    if let trim {
                        OriginTrimWash(overlay: trim)
                            .frame(width: imageBox.width, height: imageBox.height)
                            .allowsHitTesting(false)
                    }

                    // Objects selected in the object table (an overlay, not a
                    // published product: never saved or compared).
                    if let tableSelection {
                        let edges = appState.cachedPrecipitateHighlightOutline(for: tableSelection)
                        if !edges.isEmpty {
                            objectHighlight(edges, box: imageBox, imgW: dims.width,
                                            imgH: dims.height, zoom: effZoom)
                                .allowsHitTesting(false)
                        }
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
                        cursor.sample = appState.displayedProduct?.sample(x: x, y: y)
                    case .ended:
                        cursor.sample = nil
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

                footer(dims: dims, box: box, orientation: orientation,
                       qualityField: qualityField, effZoom: effZoom, trim: trim)
            }
            .frame(width: box.width, height: box.height)
            // Centred, as Preview centres a photo. Top-pinning was tried
            // first (a review note about the header sitting far from the
            // image) and looked broken on screen: a square pattern in a tall,
            // narrow pane left ~400 pt of dead space below it (measured in a
            // 1470 pt window).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(appState.displayedResultName)
            .accessibilityIdentifier("result.viewer")
            .modifier(CursorAccessibilityValue(
                model: cursor,
                fallback: mapsScanPositions
                    ? "Selected scan X \(appState.selectedScan.x), Y \(appState.selectedScan.y); \(dims.width) by \(dims.height) pixels"
                    : "\(dims.width) by \(dims.height) pixels"))
            .accessibilityHint(mapsScanPositions
                ? "Use arrow keys to move the selected scan position; Shift moves ten pixels"
                : "Scientific image; scan-position selection is unavailable")
            .zoomPanAccessibilityActions($zp, box: box)
        } else if appState.hasDataset {
            ContentUnavailableView(
                "No Result Yet",
                systemImage: "square.grid.3x3",
                description: Text(Self.pendingInstruction(for: appState.navigation.analysisMode))
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
        effZoom: CGFloat,
        trim: FitOverlays.OriginTrimOverlay?
    ) -> some View {
        let pixel = appState.displayedResultPixelMetadata
        let sampling = ScaleBar.footerSampling(
            row: pixel.row, column: pixel.column, units: pixel.units,
            swapsAxes: orientation.swapsAxes)
        let pixelsAcross = orientation.swapsAxes ? dims.height : dims.width

        PaneFooter {
            if preferences.showScaleBar {
                ScaleBar(
                    unitsPerPoint: sampling.perPixel * Double(pixelsAcross)
                        / Double(box.width) / Double(effZoom),
                    unitLabel: sampling.label)
            }
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
                if let trim {
                    OriginTrimLegend(caption: trim.legend)
                }

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

                // Categorical maps are keyed by swatches, not a colorbar: their
                // values are labels (a phase, a group), so "0 … 5 group" read
                // as a quantity and sat illegibly over the map.
                if qualityField == nil, appState.displayedResultKind == "phase_map",
                   let map = appState.phaseMapping.map {
                    CategoricalLegend(title: nil, rows: CategoricalLegendRows.phaseMap(map))
                }
                let groupRows = qualityField == nil && appState.displayedResultKind == "diffraction_groups"
                    ? appState.diffractionGroups.result.flatMap { result in
                        appState.resultDisplayedValueRange.map { range in
                            CategoricalLegendRows.groups(
                                count: result.groupCount, colormap: appState.displayedResultColormap,
                                low: range.low, high: range.high, gamma: appState.displayedResultGamma)
                        }
                    } : nil
                if let groupRows {
                    CategoricalLegend(title: "Group", rows: groupRows, compactColumns: 6)
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
                } else if groupRows == nil, appState.displayedResultImage != nil,
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

    /// The outline of the table-selected objects: a dark halo under a white
    /// line reads on the light and the dark colours of the objects picture, and
    /// widths are divided by the zoom so it stays thin when zoomed in.
    private func objectHighlight(_ edges: [PrecipitateHighlight.Edge], box: CGSize,
                                 imgW: Int, imgH: Int, zoom: CGFloat) -> some View {
        Canvas { context, size in
            let sx = size.width / CGFloat(imgW), sy = size.height / CGFloat(imgH)
            var path = Path()
            for e in edges {
                path.move(to: CGPoint(x: CGFloat(e.x0) * sx, y: CGFloat(e.y0) * sy))
                path.addLine(to: CGPoint(x: CGFloat(e.x1) * sx, y: CGFloat(e.y1) * sy))
            }
            context.stroke(path, with: .color(.black.opacity(0.85)), lineWidth: 3 / zoom)
            context.stroke(path, with: .color(.white), lineWidth: 1 / zoom)
        }
        .frame(width: box.width, height: box.height)
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
    static func pendingInstruction(for mode: AnalysisMode) -> String {
        switch mode {
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
        case .ptychography:
            "Prepare the parallax preview to begin reconstruction"
        case .singleslicePtychography:
            // Review e7: single-slice is its own task — it needs the datacube
            // and calibration, never a parallax stage.
            "Run Reconstruct Object to reconstruct the object and probe from the full datacube"
        case .diffractionGroups:
            "Run Group Patterns to sort scan positions by diffraction similarity"
        case .phaseMapping:
            "Add phases and run Map Phases after detecting Bragg disks"
        }
    }
}

// MARK: - Which pane the Direction control drives

/// An accent outline on the pane the Imaging Direction currently drives.
///
/// This is NOT the retired pane focus model — it routes nothing and writes
/// nothing. It draws the answer to one question the Settings tab already
/// asks: which of the two panes does dragging act on. It therefore appears
/// only in Imaging, the one workspace where that choice exists; elsewhere
/// `activePane` decides nothing and an outline would be noise. Click a pane
/// to select it — the outline moves and the Settings tab follows.
///
/// Owner decision, reversing an earlier retirement of this click path: a
/// picture doing nothing on click is not how a Mac app behaves, and the
/// accent outline already looks exactly like a selection. Selection driving
/// the inspector is the Xcode/Keynote idiom, not a violation of it — what
/// made the earlier behaviour confusing was that nothing showed WHAT had
/// been selected, and `ActivePaneOutline` now does.
///
/// `simultaneousGesture` so it composes with the detector drag, the scan
/// scrub and the ROI handles rather than swallowing them; `TapGesture` so a
/// drag that merely passes over a pane does not steal the selection. Writing
/// `activePane` directly is the same idiom the ROI handles already use, and
/// keeps this out of `AppState`, whose line budget `inventory` measures.
private struct SelectsPaneOnClick: ViewModifier {
    @Environment(AppState.self) private var appState
    let pane: ActivePane

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded {
            guard appState.hasDataset, appState.activePane != pane else { return }
            appState.activePane = pane
        })
    }
}

extension View {
    func selectsPaneOnClick(_ pane: ActivePane) -> some View {
        modifier(SelectsPaneOnClick(pane: pane))
    }
}

struct ActivePaneOutline: View {
    @Environment(AppState.self) private var appState
    let pane: ActivePane

    var body: some View {
        if appState.navigation.analysisMode == .virtualDetector,
           appState.navigation.workspaceArea == .image,
           appState.hasDataset,
           appState.activePane == pane {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Cursor readout

/// The real-space pointer's current sample. A reference, so the pane can hold
/// it without reading it; see `RealSpacePane.cursor`.
@Observable
final class CursorSampleModel {
    var sample: ProductSample?
}

/// The header's pointer readout: the only view (besides the accessibility
/// value) that re-evaluates when the pointer moves.
private struct CursorReadout: View {
    let model: CursorSampleModel

    var body: some View {
        if let sample = model.sample {
            Text(sample.accessibilityText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("result.cursorReadout")
        }
    }
}

/// VoiceOver value of the viewer: the sample under the pointer, else the
/// pane's static description. A modifier so the read happens here, not in the
/// pane's body.
private struct CursorAccessibilityValue: ViewModifier {
    let model: CursorSampleModel
    let fallback: String

    func body(content: Content) -> some View {
        content.accessibilityValue(model.sample?.accessibilityText ?? fallback)
    }
}
