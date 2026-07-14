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

                HStack(spacing: 10) {
                    Button("Open Dataset…") { appState.requestOpenDataset() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    if appState.recoveryRecord != nil {
                        Button("Reopen Last Dataset") { appState.reopenLastDataset() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
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
        VStack(alignment: .leading, spacing: 9) {
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: headerIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
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
                if appState.workspaceArea != .prepare,
                   appState.workspaceArea != .results,
                   let first = missingPrerequisites.first {
                    Label(first, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if appState.workspaceArea != .prepare,
                          appState.workspaceArea != .results,
                          let first = qualityGuidance.first {
                    Label(first, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.activeOperation ?? "Working…")
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
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
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
                    VStack(alignment: .leading, spacing: 3) {
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
