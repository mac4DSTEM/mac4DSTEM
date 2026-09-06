import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Imaging's "Precipitates" section (docs/ai-ml/precipitates.md §3): propose
/// reflections off the MAX pattern, confirm them, place the virtual detector
/// on one, segment the resulting dark-field image, and read the density.
/// Deliberately a Form section, not a new workspace — the owner wants slow,
/// conservative UI integration, same interaction shape as an existing
/// detector-geometry control (§3).
struct PrecipitateSettingsSection: View {
    @Environment(AppState.self) private var appState

    private var canSegment: Bool {
        guard let product = appState.publishedProduct, product.domain == .scan else { return false }
        if case .scalar = product.payload { return true }
        return false
    }

    var body: some View {
        Section("Precipitates") {
            Button {
                appState.proposePrecipitateReflections()
            } label: {
                Label("Propose Reflections", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("precipitates.proposeReflections")

            if appState.precipitates.reflections.isEmpty {
                Text("Show the Max diffraction pattern, then propose reflections not on the matrix lattice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.precipitates.reflections, id: \.id) { candidate in
                    reflectionRow(candidate)
                }
            }

            Divider()

            Picker("Mode", selection: modeBinding(appState)) {
                Text("Needles").tag(PrecipitateSegmentation.Mode.needles)
                Text("Particles").tag(PrecipitateSegmentation.Mode.particles)
            }
            .accessibilityIdentifier("precipitates.segmentationMode")

            LabeledContent("Ridge sigma") {
                NumericField(
                    "Ridge sigma",
                    value: nonnegativeSegmentationFloatBinding(appState, \.ridgeSigmaPx),
                    format: .number.precision(.fractionLength(1)),
                    unit: "px"
                )
            }
            .accessibilityIdentifier("precipitates.ridgeSigma")

            LabeledContent("Threshold") {
                NumericField(
                    "Threshold",
                    value: nonnegativeSegmentationFloatBinding(appState, \.thresholdSigmas),
                    format: .number.precision(.fractionLength(1)),
                    unit: "σ"
                )
            }
            .accessibilityIdentifier("precipitates.thresholdSigmas")

            LabeledContent("Minimum length") {
                NumericField(
                    "Minimum length",
                    value: nonnegativeSegmentationFloatBinding(appState, \.minimumLengthPx),
                    format: .number.precision(.fractionLength(1)),
                    unit: "px"
                )
            }
            .accessibilityIdentifier("precipitates.minimumLength")

            Button {
                Task { await appState.segmentPrecipitates() }
            } label: {
                Label("Segment Current Image", systemImage: "square.dashed.inset.filled")
            }
            .disabled(appState.isBusy || !canSegment)
            .accessibilityIdentifier("precipitates.segment")
            if !canSegment {
                Text("Show a virtual image first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.precipitates.objects.isEmpty {
                let edgeCount = appState.precipitates.objects.filter(\.touchesEdge).count
                LabeledContent(
                    "Objects",
                    value: "\(appState.precipitates.objects.count) objects, \(edgeCount) on the edge"
                )
                .accessibilityIdentifier("precipitates.objectsReadout")

                objectsTable

                Button {
                    appState.computePrecipitateDensity()
                } label: {
                    Label("Compute Density", systemImage: "chart.dots.scatter")
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("precipitates.computeDensity")

                densityReadout
            }
        }
    }

    @ViewBuilder
    private func reflectionRow(_ candidate: PrecipitateReflections.Candidate) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: confirmedBinding(appState, candidateID: candidate.id)) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityIdentifier("precipitates.confirmReflection.\(candidate.id)")

            Text(String(format: "r%.0f, c%.0f", Double(candidate.row), Double(candidate.col)))
                .font(.caption.monospacedDigit())
            Text(String(format: "%.1f px from beam", Double(candidate.radiusFromBeam)))
                .font(.caption)
                .foregroundStyle(.secondary)
            if candidate.onMatrixLattice {
                Label("Matrix", systemImage: "circle.grid.cross")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("On the matrix lattice — the finder proposed this one, but it is likely a matrix disk.")
            }
            Spacer()
            Button("Place detector here") {
                appState.placeVirtualDetector(on: candidate)
            }
            .controlSize(.small)
            .disabled(appState.isBusy)
            .accessibilityIdentifier("precipitates.placeDetector.\(candidate.id)")
        }
        .accessibilityIdentifier("precipitates.reflectionRow.\(candidate.id)")
    }

    @ViewBuilder
    private var objectsTable: some View {
        let shown = appState.precipitates.objects.prefix(200)
        ForEach(Array(shown), id: \.id) { object in
            HStack(spacing: 6) {
                Toggle(isOn: Binding(
                    get: { appState.precipitates.acceptedIDs.contains(object.id) },
                    set: { _ in appState.precipitates.toggleObject(object.id) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .disabled(object.touchesEdge)
                .accessibilityIdentifier("precipitates.acceptObject.\(object.id)")

                Text("#\(object.id)")
                    .font(.caption.monospacedDigit())
                Text(String(format: "L %.1f · W %.1f · θ %.0f° · A %.0f",
                             Double(object.lengthPx), Double(object.widthPx),
                             Double(object.orientationDegrees), Double(object.area)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if object.touchesEdge {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Touches the scan edge — excluded from the count.")
                }
            }
            .accessibilityIdentifier("precipitates.objectRow.\(object.id)")
        }
        if appState.precipitates.objects.count > 200 {
            Text("Showing the first 200 of \(appState.precipitates.objects.count) objects.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var densityReadout: some View {
        if let density = appState.precipitates.density {
            if let areal = density.arealDensity, let unit = density.pixelUnit {
                LabeledContent(
                    "Density",
                    value: String(format: "%.4g /%@² · %d accepted · %d on edge",
                                  Double(areal), unit as NSString, density.acceptedCount, density.edgeCount)
                )
                .accessibilityIdentifier("precipitates.densityReadout")
            } else {
                LabeledContent(
                    "Density",
                    value: "\(density.acceptedCount) accepted, \(density.edgeCount) on edge · "
                        + "no calibrated pixel size"
                )
                .accessibilityIdentifier("precipitates.densityReadout")
            }
        }
    }
}

// MARK: - Bindings

private func modeBinding(_ appState: AppState) -> Binding<PrecipitateSegmentation.Mode> {
    Binding(
        get: { appState.precipitates.segmentationSettings.mode },
        set: { appState.precipitates.segmentationSettings.mode = $0 }
    )
}

private func nonnegativeSegmentationFloatBinding(
    _ appState: AppState, _ keyPath: WritableKeyPath<PrecipitateSegmentation.Settings, Float>
) -> Binding<Float> {
    Binding(
        get: { appState.precipitates.segmentationSettings[keyPath: keyPath] },
        set: { value in
            var settings = appState.precipitates.segmentationSettings
            settings[keyPath: keyPath] = value.isFinite ? max(0, value) : 0
            appState.precipitates.segmentationSettings = settings
        }
    )
}

private func confirmedBinding(_ appState: AppState, candidateID: Int) -> Binding<Bool> {
    Binding(
        get: { appState.precipitates.confirmedReflectionIDs.contains(candidateID) },
        set: { isOn in
            var ids = appState.precipitates.confirmedReflectionIDs
            if isOn { ids.insert(candidateID) } else { ids.remove(candidateID) }
            appState.precipitates.confirmedReflectionIDs = ids
        }
    )
}
