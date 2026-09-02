import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Live performance readout. The workspace header is the single progress and
/// cancellation surface; the inspector only provides supporting metrics.
struct PerformanceView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("Status", appState.isBusy
                    ? (appState.activeOperation ?? "Working…") : "Idle")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if let metrics = appState.activeOperationMetrics(at: context.date) {
                        labeled("Elapsed", duration(metrics.elapsed))
                        if let rate = metrics.unitsPerSecond {
                            labeled("Throughput", String(format: "%.1f %@", rate, throughputUnit))
                        }
                        if let eta = metrics.eta {
                            labeled("ETA", duration(eta))
                        }
                    }
                    labeled("App memory", String(format: "%.0f MB", SystemMonitor.residentMemoryMB()))
                }
            }
            if let descriptor = appState.descriptor {
                labeled("Full cube (f32)", SystemMonitor.byteString(descriptor.byteCountAsFloat32))
                // Which path the analyses are actually taking. Resident and
                // streaming produce identical numbers, so nothing else on
                // screen would tell the user which one they are on (L2.6).
                labeled("Cube memory", appState.residency.summary)
                if appState.residency.isResident {
                    Button("Release cube") {
                        Task { await appState.releaseResidentCube() }
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("performance.releaseCube")
                }
            }
            labeled("GPU", SystemMonitor.gpuName)
            // ui-07: the configurator's row was renamed by S9a; the two
            // surfaces a user compares must use one name.
            labeled("GPU working-set limit", String(format: "%.0f MB", SystemMonitor.gpuWorkingSetMB))
        }
        .padding(.vertical, 2)
    }

    private var throughputUnit: String {
        appState.activeOperation == "Virtual detector" ? "patterns/s" : "positions/s"
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            // Monospaced digits: these values refresh continuously, and
            // proportional digits make the whole column jitter.
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 60
            ? String(format: "%d:%02d", total / 60, total % 60)
            : "\(total) s"
    }
}

/// A file-tree-style view of the source, in-memory products, and supported
/// objects discovered in the stable companion sidecar.
struct ProductsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let descriptor = appState.descriptor {
                treeRow(icon: "doc.text", text: descriptor.fileName, indent: 0)
                treeRow(icon: "cylinder", text: descriptor.datasetPath, indent: 1, mono: true)
            }

            Text("Computed this session")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 6)

            product("Origin calibration", done: appState.calibrationSession.calibration.hasFittedOrigin)
            product("R–Q rotation", done: appState.calibrationSession.calibration.hasRotation)
            product(
                "Bragg disks",
                done: appState.hasCurrentBraggVectors,
                detail: appState.diskDetectionSettingsAreStale
                    ? "settings changed · rerun"
                    : appState.braggPeakCount.map { "\($0) peaks" }
            )
            // Clickable when retained: these are held in memory simultaneously,
            // so bringing one back needs no recompute (backlog #28).
            showableProduct(.strain, done: appState.strain.map != nil)
            showableProduct(.orientation, done: appState.acomSession.hasOrientationMap)

            Text("Saved session sidecar")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 6)

            if let descriptor = appState.descriptor, appState.sessionInventory.hasSidecar {
                // Through the seam. This site derived the path itself, so once
                // any bookmark resolved to a sidecar the user had RENAMED in the
                // save panel, the inspector named a file the app was not reading.
                // Harmless before S1 only because no bookmark ever resolved —
                // the same "arms itself the moment one does" shape as the
                // warm-cache defect. Found by Gate D. // v2 S1
                let sidecar = appState.sessionSidecar.location(for: descriptor)
                HStack(spacing: 4) {
                    treeRow(icon: "externaldrive", text: sidecar.lastPathComponent, indent: 0)
                    // Rename/relocate, offered where the user is already
                    // looking at the filename — once a grant exists the save
                    // panel never reappears on its own (F1.3i). // v2 S4
                    Button("Ignore…") { appState.reopenIgnoringSessionSidecar() }
                        .help("Reopen this dataset without restoring the saved session; the sidecar file stays on disk")
                        .accessibilityIdentifier("products.reopenWithoutSession")
                    Button("Change…") { appState.saveSessionSidecarAs() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        // Never truncated: `treeRow`'s filename text yields
                        // (it middle-truncates) — a clipped action label in a
                        // narrow inspector column reads as debris.
                        .fixedSize()
                        .disabled(appState.isBusy)
                        .help("Choose a new name or location for the session sidecar. Existing saved results are copied across.")
                        .accessibilityIdentifier("inspector.changeSidecar")
                }
                if appState.sessionInventory.hasCalibration {
                    treeRow(icon: "scope", text: "Calibration", indent: 1)
                }
                if appState.sessionInventory.hasBraggVectors {
                    treeRow(icon: "circle.grid.cross", text: "BraggVectors", indent: 1)
                }
                ForEach(appState.sessionInventory.results) { result in
                    HStack(spacing: 4) {
                        Button {
                            Task { await appState.selectSavedSessionResult(result) }
                        } label: {
                            savedResultRow(
                                result,
                                isCurrent: result.id == appState.sessionInventory.currentResultID
                            )
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            Task { await appState.removeSavedSessionResult(result) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.isBusy)
                        .help("Remove this saved result from the session sidecar")
                    }
                }
                if let controls = appState.selectedSavedControlRehydration {
                    Button {
                        appState.applySelectedSavedControls()
                    } label: {
                        Label("Apply Saved Controls", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(appState.isBusy)
                    .help("Apply \(controls.summary). This does not rerun or restore transient arrays.")
                }
            } else {
                Text("No companion results saved yet.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func treeRow(icon: String, text: String, indent: Int, mono: Bool = false) -> some View {
        HStack(spacing: 8) {
            if indent > 0 { Spacer().frame(width: CGFloat(indent) * 12) }
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
            Text(text)
                .font(mono ? .caption2.monospaced() : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
    }

    /// A computed product that can be put back in the viewer on click.
    @ViewBuilder
    private func showableProduct(
        _ kind: AppState.ComputedProduct, done: Bool
    ) -> some View {
        if done {
            Button {
                appState.showComputedProduct(kind)
            } label: {
                product(kind.displayName, done: true, detail: "show")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Display this result again — it is still in memory, nothing is recomputed")
            .accessibilityIdentifier("computed.\(kind.rawValue)")
        } else {
            product(kind.displayName, done: false)
        }
    }

    private func product(_ name: String, done: Bool, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.5))
            Text(name).font(.caption)
            Spacer()
            if let detail {
                Text(detail).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private func savedResultRow(_ result: SessionResultDescriptor, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer().frame(width: 12)
            Image(systemName: isCurrent ? "eye.fill" : (result.storage == .rgba8 ? "paintpalette" : "map"))
                .font(.caption2)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName).font(.caption).lineLimit(1)
                Text("\(result.width)×\(result.height) · \(result.storage == .rgba8 ? "RGBA8" : "float32") · \(result.valueUnits)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let sampling = SessionResultPresentation.sampling(
                    row: result.pixelSizeRow, column: result.pixelSizeColumn,
                    units: result.pixelUnits
                ) {
                    Text(sampling)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let provenance = SessionResultPresentation.provenance(result.provenance) {
                    Text(provenance)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .help("\(result.kind) · \(result.id)")
    }
}

/// v2.5 step 7c: the inspector column. Which inspector it holds follows the
/// pane with the focus ring (`WorkspaceNavigation.focusedPane`) — the Results
/// product pane gets the product descriptor, every live pane the dataset.
struct WorkspaceInspector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.navigation.inspectorContent {
        case .dataset: DatasetInspector()
        case .product: ProductInspector()
        }
    }
}

/// The Diagnostics group both inspectors show (7c): promote run, calibration
/// not carried into the view, rotation curve, performance, and the
/// session-vs-view warnings — the ones that matter most beside a result.
struct InspectorDiagnosticsGroup: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Diagnostics") {
            // THE PROMOTE RUN (v2 S6) — live progress while the recipe
            // replays, and the morning summary afterwards. Outside the
            // reduced-view condition above on purpose: a finished promote
            // IS full extent, and the summary is exactly what the user
            // reads then. Cleared on dataset change (`clearUnlessRunning`).
            if appState.replayRun.phase != .idle {
                subheader("Promote run")
                if let headline = appState.replayRun.summaryHeadline {
                    Text(headline)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.promoteRunHeadline")
                }
                if let halt = appState.replayRun.haltReason {
                    Text("Halted — \(halt)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.promoteRunHalt")
                }
                if let note = appState.replayRun.frameNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("inspector.promoteRunFrameNote")
                }
                ForEach(appState.replayRun.steps) { step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(step.index + 1). \(step.title)  \(symbol(for: step.outcome))")
                            .font(.caption.weight(.medium))
                        if let detail = detail(for: step.outcome) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Calibration values that could NOT be carried into this view.
            // Shown separately from the loaded-view summary because these are
            // refusals, not descriptions: something the file provided is now
            // absent, and the reason is the actionable part.
            if !appState.loadedView.invalidatedCalibration.isEmpty {
                Group {
                    subheader("Not carried into this view")
                    ForEach(appState.loadedView.invalidatedCalibration) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.field.rawValue)
                                .font(.callout.weight(.medium))
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .accessibilityIdentifier("inspector.invalidatedCalibration")
            }

            if let rotation = appState.lastRotationResult {
                subheader("Rotation diagnostics")
                RotationCurveView(result: rotation)
                    .frame(height: 90)
                Text("Mean |curl| vs angle — solid: as-is, dashed: transposed. The marker is the chosen minimum.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            subheader("Performance")
            PerformanceView()

            // PROVENANCE (L6 item 3). A result restored from a session
            // was computed under some view; if the app is now showing a
            // different one, the numbers on screen and the numbers in the
            // sidecar are about different data. Said in the existing
            // provenance vocabulary rather than a second one (I3).
            if let recorded = appState.sessionLoadSpecification,
               recorded != appState.loadedView.specification {
                Group {
                    subheader("Session provenance")
                    Text("The saved session was computed on a different view of this file.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    row("Session view", recorded.provenanceSummary ?? "whole file")
                    row("Loaded view",
                        appState.loadedView.specification.provenanceSummary ?? "whole file")
                    Text("Restored results describe the session's view, not the one loaded now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // D4: the way OUT — a clean reopen with the session
                    // skipped. The sidecar file is untouched.
                    Button("Reopen Without This Session") {
                        appState.reopenIgnoringSessionSidecar()
                    }
                    .controlSize(.small)
                    .help("Reopens this dataset without restoring the saved session. "
                          + "The sidecar file stays on disk; results you save afterwards "
                          + "still go to the same sidecar.")
                    .accessibilityIdentifier("inspector.reopenWithoutSession")
                }
                .accessibilityIdentifier("inspector.sessionProvenanceMismatch")
            }

            // A SIDECAR THAT IS THERE AND UNREADABLE (v2 S1). Distinct from
            // the mismatch above, and it has to be: that one compares two
            // KNOWN views, while this is the case where the recorded view is
            // unknown because the file could not be opened. The dataset then
            // loaded at full extent, which looks exactly like a dataset that
            // never had a session — so without this the user's only signal
            // is a status line that the load itself overwrites within
            // milliseconds (measured, Gate D 2026-08-19).
            if let reason = appState.sessionSidecar.unreadableReason {
                Group {
                    subheader("Session sidecar")
                    Text("A saved session sits beside this dataset and could not be read.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The whole file is loaded. If that session recorded a crop, what is on screen is a different extent from what it saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("inspector.sessionSidecarUnreadable")
            }

            // A RECORDED VIEW THIS FILE DOES NOT HAVE (v2 S7). The
            // unreadable case above already renders through the locator;
            // this is the sibling failure — the sidecar was READ, and the
            // region it records does not fit the file (replaced dataset,
            // or a sidecar copied beside a different cube). Before S7 its
            // only signal was a status line the load overwrites, the
            // exact channel defect S1 measured for the branch above.
            // While either failure stands, sidecar rewrites are refused
            // (`SessionGates.sidecarRewriteRefusal`).
            if appState.sessionSidecar.unreadableReason == nil,
               let failure = appState.gates.sidecarRestoreFailure,
               failure.kind == .doesNotFit {
                Group {
                    subheader("Session sidecar")
                    Text("The saved session beside this dataset describes a region this file does not have.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The whole file is loaded, and session saves are disabled so the sidecar's recorded view and results are not relabelled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("inspector.sessionSidecarDoesNotFit")
            }
        }
    }

    // MARK: - Promote run rendering (v2 S6)

    private func symbol(for outcome: ReplayRun.Outcome) -> String {
        switch outcome {
        case .notReached: "· not reached"
        case .running: "… running"
        case .succeeded: "✓"
        case .failed: "✕ failed"
        case .cancelled: "⊘ cancelled"
        case .refused: "— refused"
        }
    }

    private func detail(for outcome: ReplayRun.Outcome) -> String? {
        switch outcome {
        case .notReached, .running, .cancelled:
            nil
        case .succeeded(let detail, let seconds):
            seconds >= 1
                ? "\(detail)  (\(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))))"
                : detail
        case .failed(let reason), .refused(let reason):
            reason
        }
    }

    private func subheader(_ title: String) -> some View { inspectorSubheader(title) }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        inspectorRow(label, value, mono: mono)
    }
}

// MARK: - Shared inspector rows

/// A labelled block boundary inside an inspector group. Sub-blocks were
/// previously sixteen top-level `Section`s; the caps style keeps them
/// scannable without sixteen headers' worth of chrome.
func inspectorSubheader(_ title: String) -> some View {
    Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.top, 8)
}

func inspectorRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
    LabeledContent(label) {
        Text(value)
            .font(mono ? .caption.monospaced() : .callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
            // Wrap, never truncate (S22a) — the inspector's fixed rows
            // were part of the read-blocking truncation the owner
            // reported; a long path or provenance string grows the row.
            .fixedSize(horizontal: false, vertical: true)
    }
}
