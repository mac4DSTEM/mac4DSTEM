//
//  StemImageView.swift
//  Role: The real-space result viewer. Shows whatever the current analysis
//        produced — a virtual-detector image, and later DPC / disk maps.
//        Zoom/pan (see ZoomPanModifier); click a pixel to make it the scan
//        position (which updates the diffraction pane).
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct StemImageView: View {
    @Environment(AppState.self) private var app
    @State private var zp = ZoomPanState()
    @State private var cursorSample: ProductSample?

    /// Name of the image+overlay container's coordinate space. The scan-marker
    /// handle reads its drag here rather than in `.local`, which for a
    /// `.position`ed view is that view's own frame, not the image's.
    private static let imageSpace = "realSpaceImage"

    /// Zoomed in means pan owns a plain drag and the marker owns its handle
    /// (backlog #35). See `RealSpacePointerPolicy` for why zooming *out* is
    /// deliberately still the scrub mode.
    private var isZoomed: Bool {
        RealSpacePointerPolicy.mode(zoom: zp.effectiveZoom) == .panAndGrab
    }

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

    /// Size of whichever result (scalar or RGBA) is active. While a quality
    /// field is being inspected, its own dimensions take precedence — it is
    /// scan-shaped like the result, but the view should never assume they
    /// match exactly.
    private var resultSize: (width: Int, height: Int)? {
        if let field = app.displayedQualityField {
            return (field.image.width, field.image.height)
        }
        if let r = app.displayedResultRGBA { return (r.width, r.height) }
        if let r = app.displayedResultImage { return (r.width, r.height) }
        return nil
    }

    private var mapsScanPositions: Bool {
        guard app.displayedProduct?.domain == .scan,
              let dims = resultSize, let descriptor = app.descriptor,
              dims.width == descriptor.rx, dims.height == descriptor.ry else {
            return false
        }
        return true
    }

    /// Everything in this row is single-line on purpose. A wrapping title or a
    /// wrapping cursor readout changes the header's *height*, which moves both
    /// image panes — the pane header is not a place to let content decide
    /// layout. The title yields first because it is the one thing also named by
    /// the workspace header directly above.
    private var header: some View {
        HStack {
            Text(app.displayedResultName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(app.displayedResultName)
                .accessibilityIdentifier("result.title")
            statusBadge
            staleBadge
            qualityToggle
            orientationControl
            zoomModeBadge
            Spacer(minLength: 8)
            if let r = resultSize {
                Text("\(r.width) × \(r.height)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if app.displayedProduct?.domain == .detector {
                Text("qᵧ →  ·  qₓ ↓")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("App detector columns are py4DSTEM qy; rows are qx.")
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

    /// Zooming in changes who owns a drag (#35), and a mode nobody can see is
    /// just confusing — so the pane says which one it is in, and how to leave.
    @ViewBuilder
    private var zoomModeBadge: some View {
        if isZoomed, mapsScanPositions {
            Text("PAN · ×\(zp.effectiveZoom, specifier: "%.1f")")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.85), in: Capsule())
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

    /// Persistent, colored badge naming the displayed result's interpretation
    /// status — or, while a quality field is being inspected, a neutral badge
    /// naming that field instead of relabeling the scientific result.
    @ViewBuilder
    private var statusBadge: some View {
        if let field = app.displayedQualityField {
            statusCapsule(text: "quality · \(field.name) (\(field.units))", color: .gray)
                .accessibilityLabel("Inspecting quality field \(field.name), units \(field.units)")
        } else if let status = app.displayedProduct?.quantitativeStatus {
            statusCapsule(text: status.rawValue.capitalized, color: statusColor(status))
                .accessibilityLabel("Interpretation status: \(status.rawValue.capitalized)")
        }
    }

    /// The displayed Bragg-vector map was produced by settings the Bragg panel
    /// no longer holds (backlog #34).
    ///
    /// The app already knew this — `diskDetectionSettingsAreStale` gates strain
    /// and ACOM, and the sidebar says "Full-scan peaks use earlier settings" —
    /// but the *result pane* said nothing, so a map left over from an earlier
    /// run (including one left behind by a cancelled re-run) read as the current
    /// one. A displayed result has to carry its own validity (ROADMAP P1.1);
    /// being correct in a panel the user is not looking at does not count.
    @ViewBuilder
    private var staleBadge: some View {
        if app.navigation.analysisMode == .disks, app.diskDetectionSettingsAreStale,
           app.displayedResultKind == "bragg_vector_map" {
            statusCapsule(text: "Earlier settings", color: .orange)
                .help("This map was produced by the previous detection settings. "
                      + "Run Detect All Disks again to bring it up to date.")
                .accessibilityLabel(
                    "Stale: this map was produced by earlier detection settings"
                )
                .accessibilityIdentifier("result.staleBadge")
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

    private func statusCapsule(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.85), in: Capsule())
            .help("Interpretation status of the displayed result")
            .accessibilityIdentifier("result.statusBadge")
    }

    /// Toggle to swap the viewer to the displayed product's paired quality
    /// field (strain ↔ fit residual, ACOM ↔ reliability). Display-only — it
    /// never touches the retained product, exports, or persistence. Hidden
    /// entirely when the displayed result carries no quality field.
    @ViewBuilder
    private var qualityToggle: some View {
        if app.displayedProduct?.qualityFields.isEmpty == false {
            Toggle(isOn: Bindable(app).inspectQualityField) {
                Image(systemName: app.inspectQualityField
                      ? "exclamationmark.magnifyingglass" : "checkmark.seal")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Inspect the quality field paired with this result (display only — exports and saved products are unchanged)")
            .accessibilityLabel(app.inspectQualityField
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
    /// than "rotate", so it cannot be read as the scientific rotation.
    @ViewBuilder
    private var orientationControl: some View {
        if app.displayedProduct?.domain == .scan {
            Menu {
                // S22b (O4): the picker's own label carries the display-only
                // claim, and the former full-sentence menu item is gone — a
                // long single-line Text inside a Menu set the whole flyout's
                // width, covering a quarter of the window for five items
                // (owner screenshot, 2026-09-01). The full sentence lives in
                // `.help` below; the wording still says "orientation …
                // display only" rather than "rotate" so it cannot be read as
                // the measured R–Q rotation.
                Picker("View orientation — display only", selection: Bindable(app).realSpaceDisplayOrientation) {
                    ForEach(RealSpaceDisplayOrientation.allCases) { orientation in
                        Text(orientation.displayName).tag(orientation)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Mirror horizontally", isOn: Bindable(app).realSpaceDisplayMirrored)
            } label: {
                Image(systemName: isOrientationDefault
                      ? "rotate.right" : "rotate.right.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
            .help("View orientation of the real-space image — display only. "
                  + "This is not the measured R–Q rotation calibration.")
            .accessibilityLabel(
                "View orientation, display only, currently "
                    + app.realSpaceDisplayOrientation.displayName
                    + (app.realSpaceDisplayMirrored ? ", mirrored horizontally" : "")
            )
            .accessibilityIdentifier("result.viewOrientation")
        }
    }

    private var isOrientationDefault: Bool { app.realSpaceDisplayIsDefault }

    /// The display orientation applies to scan-domain products only, so a
    /// detector-domain result shown in this same viewer is never transformed.
    /// Shared with the export path so the figure and the screen can never
    /// disagree about what "as displayed" means.
    private var orientation: RealSpaceDisplayOrientation {
        app.effectiveRealSpaceDisplayOrientation
    }

    private var mirrored: Bool { app.effectiveRealSpaceDisplayMirrored }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if let dims = resultSize {
            let orientation = self.orientation
            let imageAspect = CGFloat(dims.width) / CGFloat(dims.height)
            // `box` is the footprint ON SCREEN, so it uses the rotated aspect;
            // `imageBox` is the container the image and its overlays are laid
            // out in, which stays in image orientation. A quarter turn swaps
            // one into the other.
            let box = fitted(
                in: size, aspect: orientation.swapsAxes ? 1 / imageAspect : imageAspect
            )
            let imageBox = orientation.swapsAxes
                ? CGSize(width: box.height, height: box.width) : box
            // Quality inspection swaps the viewer to the paired quality field
            // (display only) — a distinct version space so the texture cache
            // re-uploads on toggle instead of reusing the scientific result's.
            let qualityField = app.displayedQualityField
            let norm = qualityField != nil
                ? app.normalizedQualityPixels() : app.normalizedResultPixels()   // cached per resultVersion
            let effZoom = max(0.25, zp.effectiveZoom)

            ZStack {
                // Image + overlays share ONE scaled container, so the
                // crosshair / ROI / click mapping stay aligned at any zoom
                // (SwiftUI maps hit-testing through the transform).
                //
                // The display orientation (#17b) is applied to that same shared
                // container, and the cursor/selection mapping lives INSIDE it.
                // So the inverse transform is applied by SwiftUI's own hit
                // testing: the inspector keeps reporting true scan indices
                // rather than following the rotation, without this view ever
                // hand-rolling an inversion that could drift from the forward
                // transform.
                ZStack {
                    MetalImageView(pixels: norm,
                                   width: dims.width, height: dims.height,
                                   contentVersion: qualityField != nil
                                       ? app.displayedResultVersion &+ 0x4000_0000
                                       : app.displayedResultVersion,
                                   colormap: qualityField != nil ? .viridis : app.displayedResultColormap,
                                   zoom: 1, offset: .zero,
                                   rgba: qualityField != nil ? nil : app.displayedResultRGBA?.rgba,
                                   displayLo: qualityField != nil ? 0 : app.displayedResultRangeLo,
                                   displayHi: qualityField != nil ? 1 : app.displayedResultRangeHi,
                                   gamma: qualityField != nil ? 1 : app.displayedResultGamma)
                        .frame(width: imageBox.width, height: imageBox.height)
                        .background(Color.black)

                    // Who owns a plain drag here depends on zoom (#35). At zoom
                    // 1 the whole pane scrubs, exactly as before. Zoomed in, the
                    // scrub layer is not mounted at all — that is what lets the
                    // drag fall through to `zoomPan` and finally makes a zoomed
                    // real-space image pannable — and the marker gets its own
                    // grab handle instead.
                    if mapsScanPositions, !isZoomed {
                        selectionLayer(box: imageBox, imgW: dims.width, imgH: dims.height)
                            .frame(width: imageBox.width, height: imageBox.height)
                    }

                    // Crosshair at the current scan position.
                    if mapsScanPositions {
                        crosshair(box: imageBox, imgW: dims.width, imgH: dims.height)
                    }

                    // Region-of-interest for virtual diffraction (sum patterns).
                    if mapsScanPositions, app.realSpaceShape != .point,
                       app.realSpaceROIIsRelevant {
                        regionOverlay(box: imageBox, imgW: dims.width, imgH: dims.height)
                            .frame(width: imageBox.width, height: imageBox.height)
                    }
                }
                .frame(width: imageBox.width, height: imageBox.height)
                .coordinateSpace(name: Self.imageSpace)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let x = min(dims.width - 1, max(0,
                            Int(location.x / max(imageBox.width, 1) * CGFloat(dims.width))))
                        let y = min(dims.height - 1, max(0,
                            Int(location.y / max(imageBox.height, 1) * CGFloat(dims.height))))
                        cursorSample = app.displayedProduct?.sample(x: x, y: y)
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
                // Same pointer conventions as the diffraction pane: pinch or
                // mouse wheel to zoom, drag or two-finger scroll to pan,
                // double-click to reset. This pane previously had zoom but no
                // pan at all, so zooming in stranded the user (2026-08-05).
                .zoomPan($zp)

                if app.displayedProduct?.domain != .scan,
                   let navigator = app.scanNavigationImage {
                    scanNavigator(navigator)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topLeading)
                }

                // Coordinate-aware scale bar (px fallback), re-quantized with
                // zoom. The bar is horizontal on screen and does NOT rotate, so
                // it must be computed against whichever image axis a quarter
                // turn has put along the displayed horizontal — for a
                // non-square scan that is a different R pixel size and a
                // different pixel count, so a bar that merely re-rendered at
                // the same length would be wrong (#17b).
                //
                // The bar and whichever legend the result calls for share ONE
                // bottom row (v2 S18): on a tall, narrow map they used to be
                // independent bottom-leading / bottom-trailing overlays and
                // drew straight through each other.
                let pixel = app.displayedResultPixelMetadata
                let sampling = orientation.swapsAxes
                    ? (pixel.row ?? pixel.column) : (pixel.column ?? pixel.row)
                let pixelsAcross = orientation.swapsAxes ? dims.height : dims.width
                PaneBottomOverlay {
                    ScaleBarView(
                        unitsPerPoint: (sampling ?? 1) * Double(pixelsAcross)
                            / Double(box.width) / Double(effZoom),
                        unitLabel: sampling != nil ? (pixel.units ?? "px") : "px")
                } trailing: {
                    // Order preserved from the separate overlays this
                    // replaced. **At most one of these three ever renders**, and
                    // the stack claims no benefit from that: `displayedResultKind`
                    // is one String, so it cannot equal "dpc_color" AND contain
                    // "ipf_z" (AppState.swift:620); the quality-field colorbar
                    // needs `qualityField != nil` where both legends need it nil;
                    // and the result colorbar needs `displayedResultImage != nil`,
                    // which an RGBA result rules out because `resultImage` and
                    // `resultRGBA` are always assigned as an exclusive pair
                    // (ResultExport.swift:770-783, AppState.swift:2925-2926).
                    // A VStack rather than a Group only so the trailing slot has
                    // one child and the order stays readable. (An earlier comment
                    // here said stacking makes "two that match at once both
                    // legible" — that state cannot occur, and claiming a benefit
                    // that never fires is the same defect S3 removed when it
                    // dropped Residency's dead String conformance. Gate A,
                    // 2026-08-27.)
                    VStack(alignment: .trailing, spacing: 6) {
                        // Direction legend for the DPC color wheel. Suppressed
                        // while inspecting a quality field — the viewer is
                        // showing a scalar viridis map, not the
                        // color-wheel-encoded result.
                        if qualityField == nil, app.displayedResultKind == "dpc_color" {
                            colorWheelLegend
                                .frame(width: 54, height: 54)
                                .padding(2)
                        }

                        // Substring, not equality: the kind now always carries
                        // a scope (`acom_full_ipf_z`, `acom_preview_ipf_z`).
                        // Equality matched only the un-suffixed full-scan
                        // spelling, so preview and region IPF maps never got
                        // their colour key — and it also keeps kinds saved
                        // before that change working on reopen.
                        if qualityField == nil, app.displayedResultKind.contains("ipf_z") {
                            Group {
                                if app.orientationMap?.symmetry == .hexagonal {
                                    HexagonalIPFLegendView()
                                } else {
                                    CubicIPFLegendView()
                                }
                            }
                            .padding(7)
                            .background(Color.black.opacity(0.48),
                                        in: RoundedRectangle(cornerRadius: 4))
                        }

                        if let field = qualityField, let range = app.displayedQualityValueRange {
                            ScalarColorbarView(
                                colormap: .viridis,
                                low: range.low,
                                high: range.high,
                                unitLabel: field.units,
                                gamma: 1,
                                marksZero: false,
                                showsMasked: false
                            )
                            .allowsHitTesting(false)   // plain chip: no control behind it (R23)
                        } else if app.displayedResultImage != nil,
                           let range = app.resultDisplayedValueRange {
                            // D3: the chip IS the colormap control — click it.
                            // (The quality-field chip above stays plain: its
                            // map is fixed by design.)
                            ColormapChipMenu(pane: .result) {
                                ScalarColorbarView(
                                    colormap: app.displayedResultColormap,
                                    low: range.low,
                                    high: range.high,
                                    unitLabel: app.displayedResultValueUnits,
                                    gamma: app.displayedResultGamma,
                                    marksZero: app.displayedResultColormap.isDiverging,
                                    showsMasked: app.displayedResultHasMaskedPixels()
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: box.width, height: box.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(app.displayedResultName)
            .accessibilityIdentifier("result.viewer")
            .accessibilityValue(cursorSample?.accessibilityText ?? (mapsScanPositions
                ? "Selected scan X \(app.selectedScan.x), Y \(app.selectedScan.y); \(dims.width) by \(dims.height) pixels"
                : "\(dims.width) by \(dims.height) pixels"))
            .accessibilityHint(mapsScanPositions
                ? "Use arrow keys to move the selected scan position; Shift moves ten pixels"
                : "Scientific image; scan-position selection is unavailable")
        } else {
            placeholder
        }
    }

    private func scanNavigator(_ image: FloatImage) -> some View {
        let width: CGFloat = 118
        let height = width * CGFloat(image.height) / CGFloat(max(image.width, 1))
        return ZStack {
            MetalImageView(
                pixels: image.normalized(), width: image.width, height: image.height,
                contentVersion: app.scanNavigationVersion, colormap: .viridis,
                zoom: 1, offset: .zero, rgba: nil,
                displayLo: 0, displayHi: 1, gamma: 1
            )
            .frame(width: width, height: height)
            let x = (CGFloat(app.selectedScan.x) + 0.5) / CGFloat(image.width) * width
            let y = (CGFloat(app.selectedScan.y) + 0.5) / CGFloat(image.height) * height
            Circle().stroke(.white, lineWidth: 1.5)
                .background(Circle().stroke(.black, lineWidth: 3))
                .frame(width: 9, height: 9).position(x: x, y: y)
        }
        .frame(width: width, height: height)
        .background(.black)
        .overlay(alignment: .topLeading) {
            Text("SCAN").font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white).padding(3)
        }
        .border(.white.opacity(0.55))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let x = Int(value.location.x / width * CGFloat(image.width))
            let y = Int(value.location.y / max(height, 1) * CGFloat(image.height))
            app.scrubTo(x: x, y: y)
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan navigator")
        .accessibilityValue("Selected scan X \(app.selectedScan.x), Y \(app.selectedScan.y)")
        .accessibilityHint("Click or drag to update the diffraction pattern")
        .accessibilityIdentifier("result.scanNavigator")
    }

    /// Hue wheel matching DPC.colorWheelRGBA (hue = atan2(cy,cx)/2π + 0.5),
    /// brightness growing with magnitude → dark center.
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
    /// gesture that a user makes a hundred times a session, unchanged.
    private func selectionLayer(box: CGSize, imgW: Int, imgH: Int) -> some View {
        // Drag (or click) to move the scan position live — the diffraction pane
        // streams the pattern as you go. minimumDistance 0 → a click also works.
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        // Same mapping the marker handle uses, so a click and a
                        // handle drag can never disagree about which pixel a
                        // point is in.
                        let scan = RealSpacePointerPolicy.scanPosition(
                            at: value.location,
                            imageWidth: imgW, imageHeight: imgH, box: box
                        )
                        app.scrubTo(x: scan.x, y: scan.y)
                    }
            )
    }

    @ViewBuilder
    private func crosshair(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let center = RealSpacePointerPolicy.markerCenter(
            scan: app.selectedScan, imageWidth: imgW, imageHeight: imgH, box: box
        )
        // Double-stroke marker so it reads on any colormap / brightness.
        // Zoomed in it is also the *only* way to move the scan position, so it
        // gains a filled centre and a larger target — the same white centre
        // handle vocabulary `ApertureControl` uses in the diffraction pane.
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
                    app.scrubTo(x: scan.x, y: scan.y)
                },
            including: isZoomed ? .all : .none
        )
        .allowsHitTesting(isZoomed)
        .accessibilityLabel("Scan position marker")
        .accessibilityValue("X \(app.selectedScan.x), Y \(app.selectedScan.y)")
        .accessibilityHint(
            "Adjust to move horizontally, or use the named actions to move in any direction"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                app.scrubTo(x: app.selectedScan.x + 1, y: app.selectedScan.y)
            case .decrement:
                app.scrubTo(x: app.selectedScan.x - 1, y: app.selectedScan.y)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: "Move scan left") {
            app.scrubTo(x: app.selectedScan.x - 1, y: app.selectedScan.y)
        }
        .accessibilityAction(named: "Move scan right") {
            app.scrubTo(x: app.selectedScan.x + 1, y: app.selectedScan.y)
        }
        .accessibilityAction(named: "Move scan up") {
            app.scrubTo(x: app.selectedScan.x, y: app.selectedScan.y - 1)
        }
        .accessibilityAction(named: "Move scan down") {
            app.scrubTo(x: app.selectedScan.x, y: app.selectedScan.y + 1)
        }
        .accessibilityIdentifier("result.scanMarkerHandle")
    }

    /// Rectangle / circle ROI centered on the selected scan position, with a
    /// resize handle. Summed patterns from inside it feed the diffraction pane.
    private func regionOverlay(box: CGSize, imgW: Int, imgH: Int) -> some View {
        let scaleX = box.width / CGFloat(imgW)
        let scaleY = box.height / CGFloat(imgH)
        let radiusScale = (scaleX + scaleY) / 2
        let center = CGPoint(x: (CGFloat(app.selectedScan.x) + 0.5) * scaleX,
                             y: (CGFloat(app.selectedScan.y) + 0.5) * scaleY)
        let r = CGFloat(app.realSpaceRadius) * radiusScale
        return ZStack {
            Group {
                if app.realSpaceShape == .circle {
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
                .position(x: center.x + r, y: app.realSpaceShape == .circle ? center.y : center.y + r)
                .gesture(
                    DragGesture(coordinateSpace: .local)
                        .onChanged { value in
                            let dx = abs(value.location.x - center.x)
                            let dy = abs(value.location.y - center.y)
                            let newR = app.realSpaceShape == .circle ? hypot(dx, dy) : max(dx, dy)
                            app.realSpaceRadius = max(1, Float((newR / radiusScale).rounded()))
                        }
                )
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(app.hasDataset ? pendingInstruction : "Open a 4DSTEM .h5 file to begin")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// S22e: the empty pane names the action that produces ITS result — the
    /// old single string told a pane titled "Bragg vector map" to "adjust the
    /// aperture", which cannot produce one (2026-09-01 drive finding,
    /// confirmed in source).
    private var pendingInstruction: String {
        switch app.navigation.analysisMode {
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
        }
    }

    private func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        } else {
            return CGSize(width: size.width, height: size.width / aspect)
        }
    }
}
