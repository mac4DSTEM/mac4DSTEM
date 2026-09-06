//
//  DiffractionGroupsSettings.swift
//  Role: the classical diffraction-grouping panel (docs/ai-ml/README.md §6) —
//        run controls for `DiffractionEmbedding`'s PCA + k-means baseline,
//        and a readout of what the last run found. A bare `Section` for the
//        caller's grouped `Form`, matching `ImagingSettings`'/`MapSettings`'
//        style. Not wired into `ImagingSettings` here — see the session
//        report for the insertion point.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct DiffractionGroupsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Section("Diffraction groups") {
            Picker("Binned size", selection: binnedSizeBinding(appState)) {
                Text("8 × 8").tag(8)
                Text("16 × 16").tag(16)
                Text("32 × 32").tag(32)
            }
            .help("Each diffraction pattern is log-scaled, per-pattern normalised, "
                  + "and box-binned to this many pixels per side before grouping.")
            .accessibilityIdentifier("groups.binnedSize")

            Stepper(
                value: intBinding(appState, \.components, in: 2...32),
                in: 2...32
            ) {
                Text("Components  \(appState.diffractionGroups.settings.components)")
            }
            .help("Principal components kept from the box-binned patterns.")
            .accessibilityIdentifier("groups.components")

            Stepper(
                value: intBinding(appState, \.groups, in: 2...32),
                in: 2...32
            ) {
                Text("Groups  \(appState.diffractionGroups.settings.groups)")
            }
            .help("k-means group count over the principal-component coordinates.")
            .accessibilityIdentifier("groups.groups")

            Button {
                Task { await appState.runDiffractionGroups() }
            } label: {
                // "Group Patterns", matching the toolbar's primary action for
                // this task (`WorkspaceView.primaryActionTitle`) and every
                // other toolbar verb — "Detect All Disks", "Compute Strain",
                // "Update Image". The two spellings of one action read as two
                // actions (owner's drive 2026-09-06, `drive-groups` defect 7).
                Label("Group Patterns", systemImage: "circle.grid.3x3")
            }
            .disabled(appState.isBusy || appState.descriptor == nil)
            .help("Run PCA and k-means over every scan position's diffraction pattern.")
            .accessibilityIdentifier("groups.run")

            Button {
                appState.showSimilarityToCurrentPosition()
            } label: {
                Label("Find similar to current position", systemImage: "wand.and.rays")
            }
            .disabled(appState.isBusy || appState.diffractionGroups.result == nil)
            .help("Cosine-similarity map to the diffraction pattern at the currently "
                  + "selected scan position, against the last grouping result.")
            .accessibilityIdentifier("groups.similarity")

            // The reference the similarity map was computed against, named
            // where the button that produces it is. `referencePosition` existed
            // "so the settings panel can name it" and the panel never read it;
            // only the pane title carried the coordinate, and a rerun used to
            // nil it while the published similarity product stayed in Results
            // (owner's drive 2026-09-06, `drive-groups` defect 4).
            if let position = appState.diffractionGroups.referencePosition,
               let result = appState.diffractionGroups.result, result.scanWidth > 0 {
                LabeledContent(
                    "Reference",
                    value: "(\(position % result.scanWidth), \(position / result.scanWidth))"
                )
                .accessibilityIdentifier("groups.referencePosition")
            }

            if let result = appState.diffractionGroups.result {
                // The readout describes the LAST RUN, and the controls above it
                // can have moved since. Saying which run it came from is the
                // repo's `TaskProductState` verdict expressed in words: a
                // retained product whose inputs changed is stale, not current
                // (owner's drive 2026-09-06, `drive-groups` defect 5 — the k=4
                // group sizes sat under `Groups 8` unmarked).
                if appState.diffractionGroups.isStale {
                    Label(
                        "From an earlier run — the settings above have changed. "
                            + "Run Group Patterns again.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("groups.staleReadout")
                }

                let firstThreePercent = result.explainedVariance.prefix(3).reduce(0, +) * 100
                Text("First 3 components explain \(String(format: "%.1f", firstThreePercent)) % of variance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("groups.explainedVariance")

                let sizes = groupSizes(result)
                Text("Group sizes: " + sizes.enumerated()
                    .map { "\($0.offset): \($0.element)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("groups.sizes")

                // The run's own provenance. `publishProduct` writes all of it
                // into the product and the sidecar, and NOTHING showed it —
                // not the Settings tab, not Info, not Results (owner's drive
                // 2026-09-06, `drive-groups` defect 3). Read from the owner
                // type rather than from `publishedProduct.provenance`, because
                // the displayed product is whatever was published LAST (the
                // similarity map, a virtual image) and need not be this run's.
                if let ran = appState.diffractionGroups.lastRunSettings {
                    Text("Run: \(ran.binnedSize) × \(ran.binnedSize) binned · "
                         + "\(result.componentCount) of \(ran.components) components · "
                         + "k = \(result.groupCount) · seed \(ran.seed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("The settings this readout was computed with: the box-binned "
                              + "pattern size, the principal components actually kept (clamped "
                              + "down for a low-rank dataset), the k-means group count, and the "
                              + "deterministic seed.")
                        .accessibilityIdentifier("groups.runProvenance")
                }
            } else {
                // The pane's own hint (`ImagePanes.pendingInstruction`) renders
                // only when NO image is displayed, and a freshly loaded dataset
                // already shows its annulus dark-field — so a first-time user
                // saw three unexplained controls and two buttons and no hint at
                // all (owner's drive 2026-09-06, `drive-groups` defect 6). This
                // one is in the panel, where the emptiness actually is.
                Text("No grouping yet. Run Group Patterns to sort every scan "
                     + "position's diffraction pattern into k groups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("groups.emptyHint")
            }
        }
    }

    private func groupSizes(_ result: DiffractionEmbedding.Result) -> [Int] {
        var counts = [Int](repeating: 0, count: result.groupCount)
        for g in result.groupOf where g >= 0 && g < counts.count { counts[g] += 1 }
        return counts
    }
}

// Mirrors MapSettings.swift's private `intBinding`/`floatBinding` helpers —
// a manual `Binding(get:set:)` over a settings struct held by a reference
// type, clamped to the control's own range so a typed-in TextField value
// (were one added later) can't escape it either.
private func intBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiffractionEmbedding.Settings, Int>,
    in range: ClosedRange<Int>
) -> Binding<Int> {
    Binding(
        get: { appState.diffractionGroups.settings[keyPath: keyPath] },
        set: { value in
            var settings = appState.diffractionGroups.settings
            settings[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diffractionGroups.settings = settings
        }
    )
}

private func binnedSizeBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diffractionGroups.settings.binnedSize },
        set: { value in
            var settings = appState.diffractionGroups.settings
            settings.binnedSize = value
            appState.diffractionGroups.settings = settings
        }
    )
}
