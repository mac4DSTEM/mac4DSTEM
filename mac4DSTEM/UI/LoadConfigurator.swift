//
//  LoadConfigurator.swift
//  Role: L5's configurator in UI — decide what to load, while the decision is
//        still cheap, from a preview of the actual data.
//
//  The migration of `UI/LoadConfiguratorView` into UI. Every number, every
//  refusal, every caption that states a scientific consequence and every
//  accessibility identifier is carried over unchanged; only the platform
//  bridge (`MetalImageView`, which takes no zoom) and the layout helper
//  (`LayoutPolicy.fitted`) differ.
//
//  VOCABULARY (L5 item 4, plan §1). Everything here says **crop**, and a crop
//  is not an ROI. A crop changes what data exists in the loaded view; an ROI
//  selects among data already loaded. They are never in the same section, and
//  this screen is not reachable once a dataset is open — by construction,
//  since it exists only before one is.
//
//  WHAT THE COPY MUST NOT IMPLY (plan §6, L5). Loading into memory does not
//  make the load faster: #30 measured the cost as the link, not the algorithm.
//  It makes the waiting happen once, at a moment the user chose. Copy that
//  promised speed would make the feature read as broken.
//
//  THE TRAP PRE-EMPTED IN THE LABELS. A strided preview and a real virtual
//  image WILL differ, and a user comparing them will file a bug.
//  `DatasetPreview` states its own stride and the caption below repeats that
//  these are samples — scoped per pane, because the single-position pattern is
//  exact and a blanket caveat would teach the user to distrust the one pane
//  that is not a sample.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct LoadConfigurator: View {
    @Environment(AppState.self) private var appState
    let pending: PendingLoad

    var body: some View {
        // The same pending open serves "Preprocess Raw Data…" (X3): the one
        // sheet builds on this layout and shares its panes, so the choice is
        // here rather than in the (frozen) host.
        if pending.preprocess != nil {
            PreprocessSheet(pending: pending, close: { appState.discardPendingLoad() },
                            chooseSource: { appState.chooseOtherPreprocessSource() })
        } else {
            loadSheet
        }
    }

    private var loadSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Divider()
            // The previews are the science and take the space; the choices
            // under them are a grouped Form, which scrolls when the sheet is
            // short so the footer — Load and its refusal — stays on screen.
            ReductionPreviewPanes(pending: pending)
                .padding(.horizontal)
                .padding(.top)
            Form {
                ReductionBinSection(pending: pending)
                sizeSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        .onChange(of: pending.singleDPFailure, initial: true) { _, failure in
            if let failure, appState.promotionRun.pendingLoad?.id == pending.id {
                appState.statusText = "Pattern preview unavailable: \(failure)"
            }
        }
        // A band, not a fixed size: a fixed 900x760 sheet overflows a display
        // shorter than ~790pt and pushes its own footer off screen.
        .frame(
            minWidth: LayoutPolicy.configuratorSheet.min.width,
            idealWidth: LayoutPolicy.configuratorSheet.ideal.width,
            minHeight: LayoutPolicy.configuratorSheet.min.height,
            idealHeight: LayoutPolicy.configuratorSheet.ideal.height
        )
    }

    // MARK: - Title

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Load \(pending.url.lastPathComponent)")
                .font(.headline)
            // The one permanent caption here: that a crop never touches the
            // file is a consequence the user cannot infer from the controls.
            Text("Crop before loading. The source file is never changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - What it costs

    private var sizeSection: some View {
        Section("Size") {
            ReductionSizeRows(pending: pending)
            if let loaded = pending.loadedByteCount {
                ReductionSizeRow(
                    "This selection (f32)",
                    displayByteString(loaded)
                        + (pending.reductionSummary.map { " · \($0)" } ?? "")
                )
            }
            if let shape = pending.loadedShapeString {
                ReductionSizeRow("Loaded shape", shape)
            }
            // NOT a budget for this load: `recommendedMaxWorkingSetSize` is a
            // hardware property (~65% of physical RAM on Apple Silicon); the
            // old "GPU budget" label under the load sizes invited a load that
            // would get an 8 GB Mac killed. The memory a load actually uses is
            // bounded in `FourDArray.scanTileRows`.
            ReductionSizeRow("GPU working-set limit", SystemMonitor.gpuWorkingSetText)
            // Reads return float32 whatever the file stores, so a uint16 file
            // costs twice its own size — the surprise this screen exists to
            // remove.
            keepInMemoryRow
            Text(pending.effectiveKeepInMemory
                 ? "Float32 expansion can exceed file size. The cube is read into memory once; analyses then run from it."
                 : "Float32 expansion can exceed file size. Analyses stream in bounded tiles.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var keepInMemoryRow: some View {
        let decision = pending.keepInMemoryDecision
        let cube = pending.loadedByteCount ?? 0
        Toggle(isOn: Binding(
            get: { pending.keepInMemory && decision != .refused },
            set: { pending.keepInMemory = $0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep in memory")
                Text(decision == .refused
                     ? KeepInMemoryDecision.refusalCaption(cubeBytes: cube,
                                                           bound: pending.keepInMemoryRefusalBound)
                     :"\(displayByteString(cube)) of \(displayByteString(Int(ProcessInfo.processInfo.physicalMemory))) RAM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(decision == .refused)
        .accessibilityIdentifier("configurator.keepInMemory")
        if decision == .warn && pending.keepInMemory {
            InspectorWarning("More than half of this Mac's memory; other apps may slow down.")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        // One read of each predicate per body pass: the refusal the user sees
        // and the disabled state of the button must come from the SAME
        // evaluation, or a future dependency that mutates mid-pass shows a
        // refusal beside an enabled Load. (`commitPendingLoad` re-checks the
        // gate model-side regardless.)
        let beamRefusal = pending.directBeamRefusal
        let refusal = pending.refusalReason ?? beamRefusal
        return VStack(alignment: .leading, spacing: 12) {
            if let refusal {
                // Its own row, not squeezed between Reset and Cancel: these are
                // whole sentences naming detector rows and columns, and a
                // refusal the user cannot read is not a refusal.
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("configurator.refusal")
            }
            HStack {
                Button("Reset") {
                    pending.configuration.scanCrop = nil
                    pending.configuration.detectorCrop = nil
                    pending.configuration.detectorBin = 1
                }
                .disabled(pending.configuration.specification.isFullExtent)
                .accessibilityIdentifier("configurator.reset")
                Spacer()
                Button("Cancel") { appState.discardPendingLoad() }
                    .keyboardShortcut(.cancelAction)
                Button("Load") { appState.commitPendingLoad() }
                    .keyboardShortcut(.defaultAction)
                    // The beam guard REFUSES the load, it does not warn: on a
                    // first open there is no calibration for the re-reference
                    // refusal to fire on, so this is the only gate.
                    .disabled(pending.view == nil || beamRefusal != nil)
                    .accessibilityIdentifier("configurator.load")
            }
        }
        .padding()
    }
}
