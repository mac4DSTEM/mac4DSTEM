import SwiftUI
import DSTEMCore
import DSTEMSession

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

                // S22e: the entry points come BEFORE the feature cards — they
                // used to sit below them and opened below the fold, so the
                // first screen of the app showed marketing and hid the doors
                // (Track B drive finding, 2026-09-01).
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button("Open Dataset…") { appState.requestOpenDataset() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .disabled(appState.isBusy)
                        // The configured open is a SECOND door, not a mode on
                        // the first: "Open Dataset…" behaves exactly as it
                        // always has (release owner, 2026-08-18). Crop and bin
                        // are something you go looking for, not a step in front
                        // of every open.
                        Button("Open with Options…") {
                            appState.requestOpenDatasetWithOptions()
                        }
                        .controlSize(.large)
                        .disabled(appState.isBusy)
                        .help("Preview the dataset and choose a crop or binning before loading")
                        .accessibilityIdentifier("welcome.openWithOptions")
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

                // S22 feedback R2 (2026-09-01): three compact cards SIDE BY
                // SIDE, always — the ViewThatFits fallback stacked them as
                // "large empty boxes" filling the first screen.
                HStack(alignment: .top, spacing: 12) { welcomeCards }
                    .frame(maxWidth: 780)

                if !appState.recents.entries.isEmpty {
                    // Stored on the seam and recomputed only on mutation, so
                    // the O(n^2) disambiguation never runs during a redraw.
                    let locations = appState.recents.locationLabels
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent datasets")
                            .font(.headline)
                        ForEach(appState.recents.entries.prefix(5)) { recent in
                            HStack(spacing: 10) {
                                Button { appState.openRecent(recent) } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(Color.accentColor)
                                        // NAME AND LOCATION, because the name
                                        // alone is not an identifier. Two copies
                                        // of one cube — a NAS share and a local
                                        // backup — rendered as identical rows on
                                        // a list whose only job is choosing
                                        // between them (Track B, 2026-08-18).
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(recent.displayName)
                                                .lineLimit(1)
                                            if let location = locations[recent.id] {
                                                Text(location)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.head)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    locations[recent.id].map { "\(recent.displayName), on \($0)" }
                                        ?? recent.displayName
                                )
                                .accessibilityHint("Reopens this dataset and its saved session")
                                Button { appState.removeRecent(recent) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from Recents")
                                .accessibilityLabel("Remove \(recent.displayName) from Recents")
                            }
                            if recent.id != appState.recents.entries.prefix(5).last?.id {
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
                Spacer(minLength: 8)
                // Next to the progress it cancels, not in a menu. Opening the
                // wrong multi-gigabyte file used to leave quitting the app as
                // the only way out, and the open is the longest uninterruptible
                // wait in the product.
                if appState.canCancelDatasetLoad {
                    Button("Cancel") { appState.cancelDatasetLoad() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityIdentifier("welcome.cancelDatasetLoad")
                        .accessibilityHint("Stops loading this dataset and returns to the welcome screen")
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
        // Sized by content (S22 feedback R2): the old 112pt floor was mostly
        // empty box.
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            for: appState.navigation.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    private var qualityGuidance: [String] {
        ProductWorkflow.guidance(
            for: appState.navigation.analysisMode,
            readiness: appState.productWorkflowReadiness
        )
    }

    private var isTaskWorkspace: Bool {
        appState.navigation.workspaceArea != .prepare && appState.navigation.workspaceArea != .results
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
                    if appState.navigation.workspaceArea == .reconstruct
                        && appState.navigation.analysisMode.isAdvanced {
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
        switch appState.navigation.workspaceArea {
        case .prepare, .results: appState.navigation.workspaceArea.title
        case .image, .map, .reconstruct: appState.navigation.analysisMode.productTitle
        }
    }

    private var headerSubtitle: String {
        switch appState.navigation.workspaceArea {
        case .prepare: "Confirm the dataset, center the probe, and establish physical scales."
        case .results: "Review, preserve, and export the products from this dataset."
        case .image, .map, .reconstruct: appState.navigation.analysisMode.productSubtitle
        }
    }

    private var headerIcon: String {
        switch appState.navigation.workspaceArea {
        case .prepare, .results: appState.navigation.workspaceArea.systemImage
        case .image, .map, .reconstruct: appState.navigation.analysisMode.systemImage
        }
    }

    private var primaryActionTitle: String? {
        switch appState.navigation.workspaceArea {
        case .prepare:
            if !appState.calibration.hasFittedOrigin { "Calibrate Origin" }
            else if !appState.calibration.hasRotation { "Calibrate Rotation" }
            else { nil }
        case .image:
            "Update Image"
        case .map:
            switch appState.navigation.analysisMode {
            case .disks: "Detect All Disks"
            case .strain: "Compute Strain"
            case .acom: appState.acomPrimaryActionTitle
            default: nil
            }
        case .reconstruct:
            if appState.navigation.analysisMode == .dpc { "Run DPC" }
            else if appState.parallaxPreprocess == nil { "Prepare Preview" }
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
        switch appState.navigation.workspaceArea {
        case .prepare:
            appState.calibration.hasFittedOrigin
                ? "Solves scan-to-detector rotation for quantitative vector output."
                : "Fits the unscattered-beam origin across the scan."
        case .image: "Runs the selected imaging task with the current settings."
        case .map:
            appState.navigation.analysisMode == .acom
                ? "Runs the selected orientation area and quality shown in the tools panel."
                : "Runs the selected whole-scan mapping task."
        case .reconstruct:
            appState.navigation.analysisMode == .dpc
                ? "Maps beam deflection across the scan and integrates projected phase."
                : "Runs the next incomplete reconstruction stage."
        case .results: "Adds the visible result to the reusable dataset session."
        }
    }

    private var primaryActionEnabled: Bool {
        guard appState.hasDataset, !appState.isBusy else { return false }
        if appState.navigation.workspaceArea != .prepare && appState.navigation.workspaceArea != .results {
            guard ProductWorkflow.prerequisites(
                for: appState.navigation.analysisMode,
                readiness: appState.productWorkflowReadiness
            ).isEmpty else { return false }
        }
        if appState.navigation.workspaceArea == .reconstruct,
           appState.navigation.analysisMode == .ptychography {
            // Parallax staging gates only its own chain — DPC (S22c: now in
            // Phase) is a plain run and must not inherit this.
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
            if appState.strain.map != nil || appState.hasOrientationMap {
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

/// One comparison panel's already-rendered pixels and the version that
/// identifies them, built ONCE per product rather than per body evaluation.
///
/// Two defects lived in the three lines this replaced (v2 S18):
///
/// 1. **The texture was frozen.** `MetalImageView` re-uploads only when
///    `contentVersion` changes, and the comparison panel passed the literal
///    `0`. The coordinator starts at `Int.min`, so the FIRST image uploaded and
///    every later one was silently dropped — swapping which saved product sits
///    in slot A left the pane showing the previous product's pixels under the
///    new product's name. Exactly the class S4 fixed for the configurator and
///    the inspector; this call site was missed.
/// 2. **It re-normalized on every mouse move.** The payload rendering and
///    `ProductComparison.difference` ran inside `body`, and `body` re-runs on
///    each `onContinuousHover` cursor update and each zoom frame — three
///    O(width x height) normalizations plus a full image subtraction per
///    pointer move.
///
/// A type rather than a method on the view so the version rule is reachable
/// from `ComparisonPanelVersionTests`: a private helper inside a private
/// `View` can only be checked by looking at it.
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
        self.contentVersion = Self.version(
            pixels: pixels, rgba: rgba, width: product.width, height: product.height
        )
    }

    /// Hash what the pane will actually draw — the payload, not the product's
    /// name or kind. Two saved products can share a kind, and one product can be
    /// re-saved with new pixels under the same name; only the values
    /// distinguish them, which is the argument S4's
    /// `contentVersion(of:width:height:)` was written for.
    ///
    /// **The RGBA bytes are folded in separately, and they have to be.** An
    /// RGBA payload renders through `rgba` and carries a `pixels` array that is
    /// all zeros, so hashing `pixels` alone gives every same-sized RGBA product
    /// the SAME version — an IPF map and a DPC colour wheel of equal dimensions
    /// would be indistinguishable, and swapping one for the other would leave
    /// the first one's texture on screen. That is defect 1 again, one payload
    /// case further in.
    static func version(pixels: [Float], rgba: [UInt8]?, width: Int, height: Int) -> Int {
        let base = MetalImageView.contentVersion(of: pixels, width: width, height: height)
        guard let rgba else { return base }
        return rgba.withUnsafeBytes { bytes -> Int in
            var hash = UInt64(bitPattern: Int64(base))
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
            return Int(bitPattern: UInt(truncatingIfNeeded: hash))
        }
    }
}

private struct ProductComparisonView: View {
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

    private func panel(_ rendered: ComparisonPanel) -> some View {
        let product = rendered.product
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(rendered.label) · \(product.displayName)")
                .font(.caption.weight(.semibold)).lineLimit(1)
            GeometryReader { geometry in
                let size = geometry.size
                MetalImageView(
                    pixels: rendered.pixels, width: product.width, height: product.height,
                    contentVersion: rendered.contentVersion,
                    colormap: rendered.colormap, zoom: 1, offset: .zero,
                    rgba: rendered.rgba, displayLo: 0, displayHi: 1, gamma: 1
                )
                // LETTERBOX before zooming. Without this the panel stretched
                // each product to the pane, so two products being COMPARED were
                // both distorted — in the view whose entire purpose is
                // comparing them, and where a difference map is offered beside
                // them. Found 2026-08-27 by sweeping every `MetalImageView`
                // call site after the same defect turned up in the configurator
                // panes and the inspector thumbnails; this was the fourth
                // instance, and it survived a rewrite of this very function
                // earlier the same day because the rewrite was looking at
                // `contentVersion`, not at aspect.
                .aspectRatio(
                    CGFloat(product.width) / CGFloat(max(product.height, 1)),
                    contentMode: .fit
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
                            // ui-06 (S22e): invert the letterbox + zoom the
                            // pane actually draws with; over letterbox the
                            // readout goes quiet instead of clamping to a
                            // wrong edge pixel.
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
        .accessibilityLabel("Comparison \(rendered.label), \(product.displayName)")
    }
}
