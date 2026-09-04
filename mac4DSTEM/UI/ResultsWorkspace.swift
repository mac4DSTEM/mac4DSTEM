import SwiftUI
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

    private var hasVisibleResult: Bool {
        appState.resultImage != nil || appState.resultRGBA != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasVisibleResult {
                // No scan marker here: Results has no diffraction pane
                // for it to drive (owner, 2026-09-04).
                RealSpacePane(allowsScanSelection: false)
                    // No minimum announced upward. The Results branch is the
                    // one place left where a content-derived minimum reaches
                    // the `NavigationSplitView` host directly — it flips on
                    // and off with `hasVisibleResult` — and the launch crash's
                    // mechanism is NOT established well enough to call that
                    // safe (Gate D refuter, 2026-09-04). The pane's reading
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

            if let a = appState.comparisonProductA, let b = appState.comparisonProductB {
                Divider()
                ProductComparisonView(a: a, b: b)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What the visible product is, and the three ways out of the app. The
    /// units and the kind are shown as saved — the kind's underscores are
    /// spaced for reading and nothing else is rewritten.
    private var currentResultSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.currentResultDisplayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    if let image = appState.resultImage {
                        Text("\(image.width) × \(image.height)")
                    } else if let image = appState.resultRGBA {
                        Text("\(image.width) × \(image.height)")
                    }
                    Text(appState.currentResultValueUnits)
                    Text(appState.currentResultKind.replacingOccurrences(of: "_", with: " "))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.exportResultImage()
            } label: {
                Label("Export PNG", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("result.exportPNG")
            // The bundle is a strain/orientation artefact: offered only when
            // one of those maps exists, exactly as before.
            if appState.strain.map != nil || appState.acomSession.hasOrientationMap {
                Button {
                    appState.exportScientificBundle()
                } label: {
                    Label("Export Bundle", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isBusy)
                .accessibilityIdentifier("result.exportBundle")
            }
            Button {
                appState.saveCurrentResultToSessionSidecar()
            } label: {
                Label("Save to Results", systemImage: "archivebox")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isBusy)
            .accessibilityIdentifier("result.saveSession")
        }
        .padding()
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

    init(_ product: DisplayedProduct, label: String, colormap: ColormapKind) {
        self.id = label
        self.product = product
        self.label = label
        self.colormap = colormap
        switch product.payload {
        case .scalar(let image):
            self.pixels = image.normalized(symmetric: colormap.isDiverging)
            self.rgba = nil
        case .rgba(let image):
            self.pixels = [Float](repeating: 0, count: image.width * image.height)
            self.rgba = image.rgba
        }
        self.contentVersion = MetalImageView.contentVersion(
            of: pixels, rgba: rgba, width: product.width, height: product.height
        )
    }
}

/// A and B side by side, with A − B beside them when the two products are
/// numerically comparable at all.
///
/// The zoom is shared and magnification-only. UI's `ZoomPan` is
/// deliberately NOT used here: it adds a pan offset, and
/// `ComparisonHoverMapping.sourcePixel` inverts a centre-anchored fit plus
/// zoom and nothing else, so a panned pane would report the value of a pixel
/// the pointer is not over. A wrong number is worse than a missing gesture.
struct ProductComparisonView: View {
    let a: DisplayedProduct
    let b: DisplayedProduct

    @State private var zoom: CGFloat = 1
    @State private var liveZoom: CGFloat = 1
    @State private var cursor: (x: Int, y: Int)?

    private let panels: [ComparisonPanel]

    init(a: DisplayedProduct, b: DisplayedProduct) {
        self.a = a
        self.b = b
        var built = [
            ComparisonPanel(a, label: "A", colormap: .viridis),
            ComparisonPanel(b, label: "B", colormap: .viridis),
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
            HStack {
                Text("Compare saved products").font(.headline)
                Spacer()
                Text("Shared zoom ×\(zoom * liveZoom, specifier: "%.1f")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
                        Text("\(change.key): \(change.left ?? "—")  ↔  \(change.right ?? "—")")
                            .font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .accessibilityIdentifier("result.comparison")
    }

    private func panel(_ rendered: ComparisonPanel) -> some View {
        let product = rendered.product
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(rendered.label) · \(product.displayName)")
                .font(.caption.weight(.semibold)).lineLimit(1)
            GeometryReader { geometry in
                let size = geometry.size
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
                // beside them.
                .aspectRatio(
                    CGFloat(product.width) / CGFloat(max(product.height, 1)),
                    contentMode: .fit
                )
                .scaleEffect(max(1, zoom * liveZoom))
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { liveZoom = $0.magnification }
                        .onEnded { value in
                            zoom = min(
                                ZoomPan.maximumZoom,
                                max(1, zoom * value.magnification)
                            )
                            liveZoom = 1
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if coordinatesCompatible {
                            // Invert the letterbox + zoom the pane actually
                            // draws with; over letterbox the readout goes
                            // quiet instead of clamping to a wrong edge pixel.
                            cursor = ComparisonHoverMapping.sourcePixel(
                                pointer: point, paneSize: size,
                                imageWidth: product.width,
                                imageHeight: product.height,
                                zoom: zoom * liveZoom
                            )
                        }
                    case .ended: cursor = nil
                    }
                }
            }
            .frame(minHeight: LayoutPolicy.comparisonPaneMinimum)   // science: a comparison pane
            if let cursor, let sample = product.sample(x: cursor.x, y: cursor.y) {
                Text(sample.accessibilityText).font(.caption2.monospacedDigit()).lineLimit(1)
            } else {
                Text("\(product.domain.rawValue) · \(product.valueUnits)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparison \(rendered.label), \(product.displayName)")
    }
}
