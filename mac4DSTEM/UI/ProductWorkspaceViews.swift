import SwiftUI

struct WelcomeWorkspace: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "circle.grid.cross.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .accessibilityHidden(true)
                    Text("Turn 4D-STEM data into answers")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("A native Mac workspace for calibrated imaging, quantitative maps, and phase reconstruction.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 660)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { welcomeCards }
                    VStack(spacing: 12) { welcomeCards }
                }
                .frame(maxWidth: 780)

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Open Dataset…") { appState.requestOpenDataset() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .disabled(appState.isBusy)
                        if appState.recoveryRecord != nil {
                            Button("Reopen Last Dataset") { appState.reopenLastDataset() }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .disabled(appState.isBusy)
                        }
                        Button("Try Demo Data") {
                            Task { await appState.openDemoFixture() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(appState.isBusy)
                        .accessibilityIdentifier("welcome.demoButton")
                    }
                    if appState.isLoadingDataset {
                        loadingStatus
                    }
                    Text("The demo is a small synthetic 4D-STEM dataset — every workspace works, and nothing on disk is touched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Guidance, not a warning: analyses stream the whole cube,
                    // so a network source costs minutes on every pass. Measured
                    // at ~3.3 MB/s over a NAS — ~30x below gigabit, and
                    // latency-dominated rather than bandwidth-limited.
                    Label(
                        "Work from a local disk. Datasets opened over a network share stream far more slowly on every whole-cube pass.",
                        systemImage: "internaldrive"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 560)
                    .accessibilityIdentifier("welcome.localStorageNotice")
                }

                if !appState.recentDatasets.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent datasets")
                            .font(.headline)
                        ForEach(appState.recentDatasets.prefix(5)) { recent in
                            HStack(spacing: 10) {
                                Button { appState.openRecent(recent) } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(Color.accentColor)
                                        Text(recent.displayName)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Reopens this dataset and its saved session")
                                Button { appState.removeRecent(recent) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from Recents")
                                .accessibilityLabel("Remove \(recent.displayName) from Recents")
                            }
                            if recent.id != appState.recentDatasets.prefix(5).last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 560)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.quaternary, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
        }
        .background(
            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
        )
    }

    private var loadingStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loading dataset")
                        .font(.subheadline.weight(.semibold))
                    // Two lines, because the measured phase reports patterns
                    // AND bytes and middle-truncating that would cut exactly
                    // the quantities the line exists to show.
                    Text(appState.datasetLoadingStatus ?? "Opening dataset…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            // A determinate bar only where the denominator is real. Metadata
            // phases show the spinner above and no bar, rather than a fraction
            // invented to keep something moving.
            if let progress = appState.datasetLoadingProgress {
                ProgressView(value: progress)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                ProgressView()
            }
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.loadingStatus")
    }

    @ViewBuilder
    private var welcomeCards: some View {
        welcomeCard(
            icon: "scope", title: "Prepare",
            detail: "Inspect dimensions and establish trustworthy calibration."
        )
        welcomeCard(
            icon: "camera.filters", title: "Analyze",
            detail: "Build images, strain and orientation maps, or reconstructions."
        )
        welcomeCard(
            icon: "archivebox", title: "Preserve",
            detail: "Save reproducible results beside the source dataset."
        )
    }

    private func welcomeCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

struct ProductWorkspaceHeader: View {
    @Environment(AppState.self) private var appState

    private var missingPrerequisites: [String] {
        ProductWorkflow.prerequisites(
            for: appState.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    private var qualityGuidance: [String] {
        ProductWorkflow.guidance(
            for: appState.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    private var isTaskWorkspace: Bool {
        appState.workspaceArea != .prepare && appState.workspaceArea != .results
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            // One surface owns readiness: unmet prerequisites AND the
            // "ready, limited interpretation" guidance both render inside the
            // checklist (design pass 2026-08-05, backlog #21).
            if isTaskWorkspace, !missingPrerequisites.isEmpty || !qualityGuidance.isEmpty {
                Divider()
                TaskPrerequisiteChecklist()
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: headerIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(headerTitle)
                        .font(.title3.weight(.semibold))
                    if appState.workspaceArea.isAdvanced {
                        Text("ADVANCED")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // Prerequisites and guidance both render as the checklist below
                // the header row (TaskPrerequisiteChecklist), never as a
                // one-line summary here — one owner, one place.
            }

            Spacer(minLength: 16)

            if appState.isBusy {
                operationProgress
            } else if let actionTitle = primaryActionTitle {
                Button(actionTitle) { runPrimaryAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!primaryActionEnabled)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityHint(primaryActionHint)
                    .accessibilityIdentifier("workspace.primaryAction")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var headerTitle: String {
        switch appState.workspaceArea {
        case .prepare, .results: appState.workspaceArea.title
        case .image, .map, .reconstruct: appState.analysisMode.productTitle
        }
    }

    private var headerSubtitle: String {
        switch appState.workspaceArea {
        case .prepare: "Confirm the dataset, center the probe, and establish physical scales."
        case .results: "Review, preserve, and export the products from this dataset."
        case .image, .map, .reconstruct: appState.analysisMode.productSubtitle
        }
    }

    private var headerIcon: String {
        switch appState.workspaceArea {
        case .prepare, .results: appState.workspaceArea.systemImage
        case .image, .map, .reconstruct: appState.analysisMode.systemImage
        }
    }

    private var primaryActionTitle: String? {
        switch appState.workspaceArea {
        case .prepare:
            if !appState.calibration.hasFittedOrigin { "Calibrate Origin" }
            else if !appState.calibration.hasRotation { "Calibrate Rotation" }
            else { nil }
        case .image:
            appState.analysisMode == .dpc ? "Run DPC" : "Update Image"
        case .map:
            switch appState.analysisMode {
            case .disks: "Detect All Disks"
            case .strain: "Compute Strain"
            case .acom: appState.acomPrimaryActionTitle
            default: nil
            }
        case .reconstruct:
            if appState.parallaxPreprocess == nil { "Prepare Preview" }
            else if appState.parallaxAlignment?.isComplete != true { "Align Next Level" }
            else if appState.parallaxHigherOrderFit == nil { "Fit Aberrations" }
            else if appState.parallaxCorrection == nil { "Correct Phase" }
            else if appState.parallaxSubpixel == nil { "Upsample BF" }
            else { "Reconstruction Ready" }
        case .results:
            nil
        }
    }

    private var primaryActionHint: String {
        switch appState.workspaceArea {
        case .prepare:
            appState.calibration.hasFittedOrigin
                ? "Solves scan-to-detector rotation for quantitative vector output."
                : "Fits the unscattered-beam origin across the scan."
        case .image: "Runs the selected imaging task with the current settings."
        case .map:
            appState.analysisMode == .acom
                ? "Runs the selected orientation area and quality shown in the tools panel."
                : "Runs the selected whole-scan mapping task."
        case .reconstruct: "Runs the next incomplete reconstruction stage."
        case .results: "Adds the visible result to the reusable dataset session."
        }
    }

    private var primaryActionEnabled: Bool {
        guard appState.hasDataset, !appState.isBusy else { return false }
        if appState.workspaceArea != .prepare && appState.workspaceArea != .results {
            guard ProductWorkflow.prerequisites(
                for: appState.analysisMode,
                readiness: appState.productWorkflowReadiness
            ).isEmpty else { return false }
        }
        if appState.workspaceArea == .reconstruct {
            return appState.parallaxCorrection == nil || appState.parallaxSubpixel == nil
        }
        return true
    }

    private var operationProgress: some View {
        HStack(spacing: 10) {
            ProgressView(value: appState.progress)
                .frame(width: 110)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.activeOperation ?? appState.statusText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let progress = appState.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if appState.canCancelActiveOperation {
                Button("Cancel", role: .cancel) { appState.cancelActiveOperation() }
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func runPrimaryAction() {
        Task {
            await appState.runPrimaryWorkspaceTask()
        }
    }
}

struct ResultsWorkspace: View {
    @Environment(AppState.self) private var appState

    private var hasVisibleResult: Bool {
        appState.resultImage != nil || appState.resultRGBA != nil
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if hasVisibleResult {
                    StemImageView()
                        .frame(minWidth: 420, minHeight: 360)
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
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

            savedProducts
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

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
            if appState.strainMap != nil || appState.hasOrientationMap {
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
                Label("Save to Session", systemImage: "archivebox")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isBusy)
            .accessibilityIdentifier("result.saveSession")
        }
        .padding(14)
        .background(.bar)
    }

    private var savedProducts: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved products")
                    .font(.headline)
                Text("Stored with this dataset and available after reopening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            if let a = appState.comparisonProductA, let b = appState.comparisonProductB {
                ProductComparisonView(a: a, b: b)
                    .frame(minHeight: 230, idealHeight: 300)
                Divider()
            }

            if appState.sessionInventory.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Nothing saved yet")
                        .font(.subheadline.weight(.medium))
                    Text("Save the visible result to build a reusable product history for this dataset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.sessionInventory.results) { result in
                            savedProductCard(result)
                        }
                    }
                    .padding(12)
                }
            }

            if let controls = appState.selectedSavedControlRehydration {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved settings available")
                            .font(.caption.weight(.medium))
                        Text(controls.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Apply") { appState.applySelectedSavedControls() }
                        .buttonStyle(.bordered)
                }
                .padding(12)
            }
        }
        .background(.background)
    }

    private func savedProductCard(_ result: SessionResultDescriptor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await appState.selectSavedSessionResult(result) }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.storage == .rgba8 ? "paintpalette" : "map")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text("\(result.width) × \(result.height) · \(result.valueUnits)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let sampling = SessionResultPresentation.sampling(
                            row: result.pixelSizeRow,
                            column: result.pixelSizeColumn,
                            units: result.pixelUnits
                        ) {
                            Text(sampling)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Displays this saved result")

            VStack(spacing: 4) {
                Button("A") { Task { await appState.loadSavedSessionResult(result, into: .a) } }
                    .help("Load into comparison A")
                    .accessibilityLabel("Load \(result.displayName) into comparison A")
                Button("B") { Task { await appState.loadSavedSessionResult(result, into: .b) } }
                    .help("Load into comparison B")
                    .accessibilityLabel("Load \(result.displayName) into comparison B")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                Task { await appState.removeSavedSessionResult(result) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(appState.isBusy)
            .help("Remove saved result")
        }
        .padding(10)
        .background(
            result.id == appState.sessionInventory.currentResultID
                ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .accessibilityIdentifier("session.savedResult")
    }
}

private struct ProductComparisonView: View {
    let a: DisplayedProduct
    let b: DisplayedProduct
    @State private var zoom: CGFloat = 1
    @State private var liveZoom: CGFloat = 1
    @State private var cursor: (x: Int, y: Int)?

    private var difference: DisplayedProduct? { ProductComparison.difference(a, b) }
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
                panel(a, label: "A", colormap: .viridis)
                panel(b, label: "B", colormap: .viridis)
                if let difference { panel(difference, label: "A − B", colormap: .rdbu) }
            }
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
        .padding(12)
        .accessibilityIdentifier("result.comparison")
    }

    private func panel(
        _ product: DisplayedProduct, label: String, colormap: ColormapKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label) · \(product.displayName)").font(.caption.weight(.semibold)).lineLimit(1)
            GeometryReader { geometry in
                let size = geometry.size
                let rendered = renderPayload(product, colormap: colormap)
                MetalImageView(
                    pixels: rendered.pixels, width: product.width, height: product.height,
                    contentVersion: 0, colormap: colormap, zoom: 1, offset: .zero,
                    rgba: rendered.rgba, displayLo: 0, displayHi: 1, gamma: 1
                )
                .scaleEffect(max(1, zoom * liveZoom))
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(MagnificationGesture()
                    .onChanged { liveZoom = $0 }
                    .onEnded { zoom = min(64, max(1, zoom * $0)); liveZoom = 1 })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        if coordinatesCompatible {
                            cursor = (
                                min(product.width - 1, max(0, Int(point.x / max(size.width, 1) * CGFloat(product.width)))),
                                min(product.height - 1, max(0, Int(point.y / max(size.height, 1) * CGFloat(product.height))))
                            )
                        }
                    case .ended: cursor = nil
                    }
                }
            }
            .frame(minHeight: 120)
            if let cursor, let sample = product.sample(x: cursor.x, y: cursor.y) {
                Text(sample.accessibilityText).font(.caption2.monospacedDigit()).lineLimit(1)
            } else {
                Text("\(product.domain.rawValue) · \(product.valueUnits)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comparison \(label), \(product.displayName)")
    }

    private func renderPayload(_ product: DisplayedProduct, colormap: ColormapKind)
        -> (pixels: [Float], rgba: [UInt8]?) {
        switch product.payload {
        case .scalar(let image):
            return (image.normalized(symmetric: colormap.isDiverging), nil)
        case .rgba(let image):
            return ([Float](repeating: 0, count: image.width * image.height), image.rgba)
        }
    }
}
