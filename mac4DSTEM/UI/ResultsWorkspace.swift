import ShellControls
import ShellLayout
import SwiftUI
import ShellMetal
import ShellInspector
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The Results workspace: the visible product, what it is, what can be done
/// with it, and — when two saved products are loaded into A and B — the
/// comparison row beneath.
///
/// The saved-product chooser lives in the inspector's Settings tab
/// (`ResultsSettings`) and the product descriptor in its Info tab; this
/// surface owns only the science pane and the three actions that move a
/// result out of the app.
struct ResultsWorkspace: View {
    @Environment(AppState.self) private var appState
    /// The comparison's "Same scale", kept here so it outlives the comparison view being rebuilt for each new product.
    @State private var comparisonSameScale = false

    private var hasVisibleResult: Bool {
        appState.resultPresentation.resultImage != nil || appState.resultPresentation.resultRGBA != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasVisibleResult {
                // No scan marker here: Results has no diffraction pane
                // for it to drive (owner decision).
                RealSpacePane(allowsScanSelection: false)
                    // No minimum announced upward. The Results branch is the
                    // one place left where a content-derived minimum reaches
                    // the `NavigationSplitView` host directly — it flips on
                    // and off with `hasVisibleResult` — and the launch
                    // crash's mechanism is not established well enough to
                    // call that safe (Gate D refuter). The pane's reading
                    // size is the window's to give.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                currentResultSummary
            } else {
                ContentUnavailableView {
                    Label("No Results Yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("Create an image, map, or reconstruction. It will appear here ready to review and save.")
                } actions: {
                    Button("Create an Image") { appState.selectWorkspace(.image) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Owner card P4 (b): the Quantify steps of this window's 4D session, one row each. No row without a 4D cube.
            let quantifications = appState.quantificationRows
            if !quantifications.isEmpty {
                Divider()
                QuantificationRowsList(rows: quantifications)
            }

            if let a = appState.comparisonProductA, let b = appState.comparisonProductB {
                Divider()
                ProductComparisonView(a: a, b: b, sameScale: $comparisonSameScale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What the visible product is, and the ways out of the app. The units and the kind are shown as saved — the kind's
    /// underscores are spaced for reading and nothing else is rewritten.
    ///
    /// Two layouts, the first that fits wins (`ViewThatFits`): every export as its own button, or — when the window is too
    /// narrow for them — one Export menu holding the same items, Save to Results kept visible. Nothing clips either way.
    private var currentResultSummary: some View {
        ViewThatFits(in: .horizontal) {
            summaryRow(exportsAsMenu: false)
            summaryRow(exportsAsMenu: true)
        }
        .padding()
    }

    private func summaryRow(exportsAsMenu: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.currentResultDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let image = appState.resultPresentation.resultImage {
                        Text("\(image.width) × \(image.height)")
                    } else if let image = appState.resultPresentation.resultRGBA {
                        Text("\(image.width) × \(image.height)")
                    }
                    Text(appState.currentResultValueUnits)
                    Text(appState.currentResultKind.replacingOccurrences(of: "_", with: " "))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            if exportsAsMenu {
                Menu {
                    exportItems
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Export this result")
                .accessibilityIdentifier("result.exportMenu")
            } else {
                exportItems
                    .buttonStyle(.bordered)
            }
            Button {
                appState.saveCurrentResultToSessionSidecar()
            } label: {
                Label("Save to Results", systemImage: "archivebox")
            }
            .buttonStyle(.borderedProminent)
            // C4(a): the sidecar-rewrite gate, beside busy — see
            // `SaveResultButton` in `WorkspaceView.swift`.
            .disabled(saveToResultsReason != nil)
            .accessibilityValue(saveToResultsReason ?? "")
            .accessibilityIdentifier("result.saveSession")
        }
    }

    /// The export actions, one name each ("Export <what> …", the File menu's too), as buttons in a row or as the items of the
    /// Export menu.
    @ViewBuilder
    private var exportItems: some View {
        Button {
            appState.exportResultImage()
        } label: {
            Label("Export Result PNG…", systemImage: "photo")
        }
        .accessibilityIdentifier("result.exportPNG")
        // Owner card S8 (b): the float map behind the view, as an EMD RealSlice .h5.
        Button {
            appState.exportProductData()
        } label: {
            Label("Export Data…", systemImage: "tablecells")
        }
        .disabled(exportDataReason != nil)
        .help(appState.productIsColourImageOnly
              ? "This view is a colour image; export the scalar maps it is made from"
              : "Save the numbers behind this view as an HDF5 (EMD) file")
        // VoiceOver hears the reason on the dimmed button; nothing is drawn.
        .accessibilityValue(exportDataReason ?? "")
        .accessibilityIdentifier("result.exportData")
        // The bundle is a strain/orientation artefact: offered only when
        // one of those maps exists, exactly as before.
        if appState.strain.map != nil || appState.acomSession.hasOrientationMap {
            Button {
                appState.exportScientificBundle()
            } label: {
                Label("Export Bundle…", systemImage: "square.stack.3d.up")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("result.exportBundle")
        }
    }

    /// The same conditions that disable Export Data, as a reason (nil when enabled).
    private var exportDataReason: String? {
        ResultsActionReason.exportData(
            isBusy: appState.isBusy,
            hasResultImage: appState.resultPresentation.resultImage != nil)
    }

    /// The same conditions that disable Save to Results, as a reason (nil when enabled).
    /// The refusal is the gate's own text: `mayWriteSidecar` is `sidecarRewriteRefusal() == nil`.
    private var saveToResultsReason: String? {
        ResultsActionReason.saveToResults(
            isBusy: appState.isBusy,
            sidecarRefusal: appState.gates.sidecarRewriteRefusal())
    }
}

/// The Quantify steps recorded in this window's session, newest first: what was quantified, the method, the at% the Spectroscopy
/// room's table showed, the unvalidated badge, and the step's readable keys behind a disclosure. Read from the record; no fit runs here.
struct QuantificationRowsList: View {
    let rows: [QuantificationRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quantifications").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(row.title).fontWeight(.semibold)
                                if row.unvalidated { UnvalidatedBadge() }
                            }
                            Text(row.result).font(.callout.monospacedDigit()).selectableText(row.result)
                            Text(row.method).font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Parameters") {
                                ForEach(row.parameters, id: \.key) { entry in
                                    let line = "\(entry.key): \(entry.value)"
                                    Text(line).font(.caption2.monospaced()).selectableText(line)
                                }
                            }
                            .font(.caption)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .accessibilityIdentifier("result.quantifications")
    }
}

/// Why Export Data and Save to Results are disabled, in words VoiceOver can
/// speak on the dimmed button. nil when the button is enabled. The buttons'
/// `.disabled` binds to the same nil-ness, so the reason and the state cannot
/// drift apart.
nonisolated enum ResultsActionReason {
    static let busy = "Unavailable while another task is running."

    /// Export Data is disabled when no result image exists yet (a colour-only
    /// view has no scalar map, but its image is still a result).
    static func exportData(isBusy: Bool, hasResultImage: Bool) -> String? {
        if isBusy { return busy }
        return hasResultImage ? nil : "No result to export yet."
    }

    /// Save to Results takes the gate's own refusal text, so the reason and the
    /// gate cannot disagree in wording.
    static func saveToResults(isBusy: Bool, sidecarRefusal: String?) -> String? {
        if isBusy { return busy }
        return sidecarRefusal
    }

    /// The toolbar's Save to Session, in the order its `.disabled` checked them (drive 14: it dimmed with no reason).
    static func saveToSession(isLoading: Bool, hasDisplayedProduct: Bool, isBusy: Bool, sidecarRefusal: String?) -> String? {
        if isLoading { return "Unavailable while the dataset loads." }
        if !hasDisplayedProduct { return "No result is displayed yet: compute one first." }
        if isBusy { return busy }
        return sidecarRefusal
    }
}

/// The colour range of the comparison's A and B panels. Each panel windows its own minimum to its own maximum, so the same
/// colour in A and in B can mean different values; "Same scale" gives both one window. Pure and display-only: the saved
/// products and their numbers are never touched, only which value the colours span.
nonisolated enum ComparisonColourScale {
    /// The lowest and highest finite value over both products, when a shared scale means something: both are scalar maps in the
    /// same units. nil otherwise (a colour image has no range; different units cannot share one).
    static func sharedRange(_ a: DisplayedProduct, _ b: DisplayedProduct) -> (low: Float, high: Float)? {
        guard case .scalar(let imageA) = a.payload, case .scalar(let imageB) = b.payload,
              a.valueUnits == b.valueUnits else { return nil }
        let (loA, hiA) = imageA.minMax, (loB, hiB) = imageB.minMax
        return (min(loA, loB), max(hiA, hiB))
    }

    /// True when a shared scale is on offer and the panels' own ranges are not already the same (so the header says so).
    static func rangesDiffer(_ a: DisplayedProduct, _ b: DisplayedProduct) -> Bool {
        guard sharedRange(a, b) != nil,
              case .scalar(let imageA) = a.payload, case .scalar(let imageB) = b.payload else { return false }
        let (loA, hiA) = imageA.minMax, (loB, hiB) = imageB.minMax
        return loA != loB || hiA != hiB
    }

    /// `FloatImage.normalized()` on a given window instead of the image's own; non-finite pixels stay "no data".
    static func normalized(_ image: FloatImage, low: Float, high: Float) -> [Float] {
        let invalid = FloatImage.invalidDisplayValue
        let span = high - low
        guard span > 0 else { return image.pixels.map { $0.isFinite ? 0 : invalid } }
        return image.pixels.map { $0.isFinite ? ($0 - low) / span : invalid }
    }
}

/// One comparison panel's already-rendered pixels and the version that
/// identifies them, built ONCE per product rather than per body evaluation.
///
/// Two defects lived in the three lines this replaced (v2 S18), and both are
/// structural rather than cosmetic — this type exists to keep them dead:
///
/// 1. **The texture froze.** `MetalImageView` re-uploads only when
///    `contentVersion` changes and the old panel passed the literal `0`. The
///    coordinator starts at `Int.min`, so the first image uploaded and every
///    later one was silently dropped — swapping which saved product sits in
///    slot A left the pane showing the previous product's pixels under the
///    new product's name.
/// 2. **It re-normalised on every mouse move.** The payload rendering and
///    `ProductComparison.difference` ran inside `body`, and `body` re-runs on
///    each `onContinuousHover` cursor update and each zoom frame — three
///    O(width × height) normalisations plus a full image subtraction per
///    pointer move.
///
/// The version folds in the RGBA bytes as well as the float pixels, and it
/// has to: an RGBA payload renders through `rgba` and carries an all-zero
/// `pixels` array, so hashing `pixels` alone gives every same-sized RGBA
/// product the SAME version — an IPF map and a DPC colour wheel of equal
/// dimensions would be indistinguishable and one would keep the other's
/// texture. That is defect 1 again, one payload case further in.
/// `MetalImageView.contentVersion(of:rgba:width:height:)` is exactly that rule.
struct ComparisonPanel: Identifiable {
    let id: String
    let product: DisplayedProduct
    let label: String
    let colormap: ColormapKind
    let pixels: [Float]
    let rgba: [UInt8]?
    let contentVersion: Int
    /// The value window the normalised pixels span — what the panel's
    /// colorbar prints. A diverging map is symmetric about zero, exactly as
    /// `normalized(symmetric:)` scales it, so the bar's zero mark is where
    /// the map's neutral colour is. nil for an RGBA payload, which has no
    /// scalar window.
    let valueRange: (low: Double, high: Double)?
    /// True when the payload holds pixels the map cannot colour (no data).
    let hasMasked: Bool

    /// `sharedRange`: when given, a scalar payload is windowed on it (lowest to highest value over BOTH A and B,
    /// `ComparisonColourScale.sharedRange`) instead of on its own minimum and maximum. Display only: the product's
    /// pixels are untouched, and the colorbar prints the window the colours really span.
    init(_ product: DisplayedProduct, label: String, colormap: ColormapKind,
         sharedRange: (low: Float, high: Float)? = nil) {
        self.id = label
        self.product = product
        self.label = label
        self.colormap = colormap
        switch product.payload {
        case .scalar(let image):
            self.rgba = nil
            if let shared = sharedRange, !colormap.isDiverging {
                self.pixels = ComparisonColourScale.normalized(image, low: shared.low, high: shared.high)
                self.valueRange = (Double(shared.low), Double(shared.high))
                self.hasMasked = product.validityMask.contains(false)
                self.contentVersion = MetalImageView.contentVersion(
                    of: pixels, rgba: rgba, width: product.width, height: product.height)
                return
            }
            self.pixels = image.normalized(symmetric: colormap.isDiverging)
            let (lo, hi) = image.minMax
            if colormap.isDiverging {
                let magnitude = Double(max(abs(lo), abs(hi)))
                self.valueRange = (-magnitude, magnitude)
            } else {
                self.valueRange = (Double(lo), Double(hi))
            }
            self.hasMasked = product.validityMask.contains(false)
        case .rgba(let image):
            self.pixels = [Float](repeating: 0, count: image.width * image.height)
            self.rgba = image.rgba
            self.valueRange = nil
            self.hasMasked = false
        }
        self.contentVersion = MetalImageView.contentVersion(
            of: pixels, rgba: rgba, width: product.width, height: product.height
        )
    }
}

/// A pixel position in one comparison panel's own product.
struct ComparisonSamplePoint: Equatable {
    let x: Int
    let y: Int
}

/// The VoiceOver-only sample cursor of a comparison panel. It is drawn
/// nowhere: it starts at the panel's centre and moves in steps of a twentieth
/// of the image (at least one pixel), clamped inside it. Pure, so the step and
/// the clamp are pinned by a unit test.
nonisolated enum ComparisonSampleCursor {
    enum Direction: Equatable { case left, right, up, down }

    static func centre(width: Int, height: Int) -> ComparisonSamplePoint {
        ComparisonSamplePoint(x: max(0, min(width - 1, width / 2)),
                              y: max(0, min(height - 1, height / 2)))
    }

    static func stepped(_ point: ComparisonSamplePoint, _ direction: Direction,
                        width: Int, height: Int) -> ComparisonSamplePoint {
        guard width > 0, height > 0 else { return ComparisonSamplePoint(x: 0, y: 0) }
        let dx = max(1, width / 20), dy = max(1, height / 20)
        var x = point.x, y = point.y
        switch direction {
        case .left: x -= dx
        case .right: x += dx
        case .up: y -= dy
        case .down: y += dy
        }
        return ComparisonSamplePoint(x: min(max(x, 0), width - 1),
                                     y: min(max(y, 0), height - 1))
    }
}

/// A and B side by side, with A − B beside them when the two products are
/// numerically comparable at all.
///
/// The zoom and the pan are shared: one `PaneZoomModel` drives every panel, so the same pixel sits under the same place in A, B
/// and A − B. It is the model the image panes use (pinch about the pointer, drag to pan, double-click to fit, the same clamp
/// and badge), and the hover readout inverts the whole chain, offset included (`ComparisonHoverMapping.sourcePixel`), so a
/// panned panel still names the pixel the pointer is over. The pinch and the drag act on the fitted image's own rectangle, not
/// on the letterbox around it.
struct ProductComparisonView: View {
    let a: DisplayedProduct
    let b: DisplayedProduct
    /// "Same scale" (owned by the room, so it survives this view being rebuilt when a product changes).
    @Binding var sameScale: Bool
    @Environment(AppState.self) private var appState

    /// The one zoom and pan of all panels. View-local: it is how this comparison is looked at, not a result.
    @State private var zoomModel = PaneZoomModel()
    /// The fitted image box last laid out (the panels share a size, bar products of other shapes, which have no readout), for the
    /// accessibility pan step: the actions sit outside the `GeometryReader` that measures it.
    @State private var fittedBox: CGSize = .zero
    @State private var cursor: (x: Int, y: Int)?
    /// VoiceOver's sample cursor per panel, keyed by the panel's label. Absent
    /// until first moved, when it sits at the panel centre.
    @State private var sampleCursors: [String: ComparisonSamplePoint] = [:]

    private let panels: [ComparisonPanel]

    init(a: DisplayedProduct, b: DisplayedProduct, sameScale: Binding<Bool>) {
        self.a = a
        self.b = b
        self._sameScale = sameScale
        let shared = sameScale.wrappedValue ? ComparisonColourScale.sharedRange(a, b) : nil
        var built = [
            ComparisonPanel(a, label: "A", colormap: .viridis, sharedRange: shared),
            ComparisonPanel(b, label: "B", colormap: .viridis, sharedRange: shared),
        ]
        if let difference = ProductComparison.difference(a, b) {
            built.append(ComparisonPanel(difference, label: "A \u{2212} B", colormap: .rdbu))
        }
        self.panels = built
    }

    /// The readout is only meaningful when one pixel index means the same
    /// place in both products.
    private var coordinatesCompatible: Bool {
        a.domain == b.domain && a.width == b.width && a.height == b.height
            && a.sampling == b.sampling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !sameScale, ComparisonColourScale.rangesDiffer(a, b) {
                Text("A and B each use their own colour range, so the same colour can mean different values. Same scale gives both one range.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("result.comparison.rangeNote")
            }
            HStack(spacing: 8) {
                ForEach(panels) { panel($0) }
            }
            // Why the difference is or is not on offer — the one sentence a
            // reader cannot infer from the panels themselves.
            switch ProductComparison.compatibility(a, b) {
            case .compatible:
                Text("Numeric difference enabled: domain, dimensions, units, sampling, and quantitative status match.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .incompatible(let reason):
                Label("Difference unavailable: \(reason)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let changes = ProductComparison.provenanceDifferences(a, b)
            if !changes.isEmpty {
                DisclosureGroup("Provenance differences (\(changes.count))") {
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                        let line = "\(change.key): \(change.left ?? "—")  ↔  \(change.right ?? "—")"
                        Text(line)
                            .font(.caption2.monospaced()).selectableText(line)
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        // A sample cursor is a pixel index into one product; a new product in
        // either slot makes the old cursor meaningless, so it starts again at centre.
        .onChange(of: [a, b].map { "\($0.kind)|\($0.displayName)|\($0.width)x\($0.height)" }) { _, _ in
            sampleCursors = [:]
        }
        .accessibilityIdentifier("result.comparison")
    }

    /// Title; "Same scale" (when it means something) and the shared zoom (−, +, the badge once it is not 1×, Reset); Clear.
    /// Two rows below the width the single row needs, so nothing clips.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                title
                Spacer(minLength: 12)
                scaleToggle
                zoomControls
                clearButton
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    title
                    Spacer(minLength: 12)
                    clearButton
                }
                HStack(spacing: 12) {
                    scaleToggle
                    zoomControls
                }
            }
        }
    }

    @ViewBuilder
    private var scaleToggle: some View {
        if ComparisonColourScale.sharedRange(a, b) != nil {
            Toggle("Same scale", isOn: $sameScale)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .fixedSize()
                .help("Colour A and B with one range, from the lowest to the highest value in either")
                .accessibilityIdentifier("result.comparison.sameScale")
        }
    }

    private var clearButton: some View {
        Button("Clear") { appState.clearComparison() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Remove A and B from the comparison; the saved products stay in the session")
            .accessibilityIdentifier("result.comparison.clear")
    }

    private var title: some View {
        Text("Compare saved products").font(.headline).lineLimit(1)
    }

    private var zoomControls: some View {
        let state = zoomModel.state
        return HStack(spacing: 6) {
            if let text = ZoomPan.badgeText(zoom: state.effectiveZoom),
               let spoken = ZoomPan.badgeSpoken(zoom: state.effectiveZoom) {
                Text(text)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .fixedSize()
                    .help("\(spoken), all panels together. Drag to pan; double-click, or Reset, to see the whole image.")
                    .accessibilityLabel(spoken)
                    .accessibilityIdentifier("result.comparison.zoomBadge")
            }
            Button { zoomModel.zoomOut() } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .help("Zoom out all panels")
            .accessibilityIdentifier("result.comparison.zoomOut")
            Button { zoomModel.zoomIn() } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .help("Zoom in all panels")
            .accessibilityIdentifier("result.comparison.zoomIn")
            Button("Reset") { zoomModel.fit() }
                .disabled(state.zoom == 1 && state.offset == .zero)
                .help("Fit the whole image in every panel again")
                .accessibilityIdentifier("result.comparison.zoomReset")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    /// The panel's static caption, shown when no sample is under the pointer.
    private func staticCaption(_ product: DisplayedProduct) -> String {
        "\(product.domain.rawValue) · \(product.valueUnits)"
    }

    /// The VoiceOver value of a panel: the sample at its sample cursor, else the caption.
    private func voSampleText(_ rendered: ComparisonPanel) -> String {
        let product = rendered.product
        let point = sampleCursors[rendered.id]
            ?? ComparisonSampleCursor.centre(width: product.width, height: product.height)
        return product.sample(x: point.x, y: point.y)?.accessibilityText ?? staticCaption(product)
    }

    private func moveSampleCursor(_ rendered: ComparisonPanel, _ direction: ComparisonSampleCursor.Direction) {
        let product = rendered.product
        let current = sampleCursors[rendered.id]
            ?? ComparisonSampleCursor.centre(width: product.width, height: product.height)
        sampleCursors[rendered.id] = ComparisonSampleCursor.stepped(
            current, direction, width: product.width, height: product.height)
    }

    private var zp: ZoomPan { zoomModel.state }

    private func panel(_ rendered: ComparisonPanel) -> some View {
        let product = rendered.product
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(rendered.label) · \(product.displayName)")
                .font(.caption.weight(.semibold)).lineLimit(1)
            GeometryReader { geometry in
                let size = geometry.size
                let fitted = ComparisonHoverMapping.fittedSize(
                    paneSize: size, imageWidth: product.width, imageHeight: product.height)
                MetalImageView(
                    pixels: rendered.pixels,
                    width: product.width, height: product.height,
                    contentVersion: rendered.contentVersion,
                    colormap: rendered.colormap,
                    rgba: rendered.rgba,
                    displayLo: 0, displayHi: 1, gamma: 1
                )
                // LETTERBOX before zooming. Without this the panel stretched
                // each product to the pane, so the two things being COMPARED
                // were both distorted — in the view whose entire purpose is
                // comparing them, and where a difference map is offered
                // beside them. The fit and the centre-anchored zoom are done
                // by the shader (`MetalDisplayTransform`), not by a SwiftUI
                // `scaleEffect`: that would grow the drawable with the zoom.
                .displayTransform(MetalDisplayTransform(
                    paneSize: size, imageBox: fitted,
                    zoom: zp.drawZoom, offset: zp.effectiveOffset))
                .frame(width: size.width, height: size.height)
                .clipped()
                .onChange(of: fitted, initial: true) { fittedBox = fitted }
                // The pinch, the drag and the double-click live on the fitted image's own rectangle (centred, so its
                // centre is the pane's centre, where the shader zooms), which is the box `ZoomPan` measures its clamp
                // and its anchors against. The hover is read there too, once, through `zoomPan`'s `onHover`.
                .overlay {
                    Color.clear
                        .frame(width: fitted.width, height: fitted.height)
                        .contentShape(Rectangle())
                        .zoomPan(zoomModel, box: fitted) { phase in
                            switch phase {
                            case .active(let location):
                                if coordinatesCompatible {
                                    // Invert the letterbox, zoom and pan the pane actually draws with; over letterbox
                                    // the readout goes quiet instead of clamping to a wrong edge pixel.
                                    let pointer = CGPoint(x: location.x + (size.width - fitted.width) / 2,
                                                          y: location.y + (size.height - fitted.height) / 2)
                                    cursor = ComparisonHoverMapping.sourcePixel(
                                        pointer: pointer, paneSize: size,
                                        imageWidth: product.width, imageHeight: product.height,
                                        zoom: zp.effectiveZoom, offset: zp.effectiveOffset)
                                }
                            case .ended: cursor = nil
                            }
                        }
                }
                // The legend the main pane's footer carries, on the same
                // plate: value range, units, a zero mark on a diverging map.
                if let range = rendered.valueRange {
                    Colorbar(
                        colormap: rendered.colormap,
                        low: range.low, high: range.high,
                        unitLabel: product.valueUnits,
                        marksZero: rendered.colormap.isDiverging,
                        showsMasked: rendered.hasMasked
                    )
                    .padding(6)
                    .allowsHitTesting(false)
                    .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
                    .accessibilityIdentifier("result.comparison.colorbar.\(rendered.id)")
                }
            }
            .frame(minHeight: LayoutPolicy.comparisonPaneMinimum)   // science: a comparison pane
            // The panel's own VoiceOver element. MetalImageView exposes nothing, so without this the
            // value and actions below land on the colorbar or on nothing. `.contain`, not `.ignore`:
            // the colorbar's range and units are spoken content, so it stays reachable beneath.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(rendered.label) · \(product.displayName)")
            // The pinch has no keyboard or VoiceOver twin otherwise: the same zoom, pan and reset actions as the image
            // panes, acting on the one shared model. (`zoomPanAccessibilityActions` lists "Zoom in", "Zoom out", the four
            // "Pan" actions and "Reset zoom".) The system zoom action maps onto the same step.
            .zoomPanAccessibilityActions(zoomModel, box: fittedBox)
            .accessibilityZoomAction { action in
                switch action.direction {
                case .zoomIn: zoomModel.zoomIn()
                case .zoomOut: zoomModel.zoomOut()
                @unknown default: break
                }
            }
            // The pointer's readout, for VoiceOver too: the sample at the VO-only
            // cursor, through the same `product.sample` the hover readout uses.
            .accessibilityValue(voSampleText(rendered))
            .accessibilityAction(named: "Move sample cursor left") { moveSampleCursor(rendered, .left) }
            .accessibilityAction(named: "Move sample cursor right") { moveSampleCursor(rendered, .right) }
            .accessibilityAction(named: "Move sample cursor up") { moveSampleCursor(rendered, .up) }
            .accessibilityAction(named: "Move sample cursor down") { moveSampleCursor(rendered, .down) }
            if let cursor, let sample = product.sample(x: cursor.x, y: cursor.y) {
                Text(sample.accessibilityText).font(.caption2.monospacedDigit()).lineLimit(1)
            } else {
                Text(staticCaption(product))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparison \(rendered.label), \(product.displayName)")
    }
}
