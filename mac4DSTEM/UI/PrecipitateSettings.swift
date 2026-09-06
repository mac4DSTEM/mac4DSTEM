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
                // Names WHERE the control lives. The old wording ("Show the Max
                // diffraction pattern…") sent the user looking for a button
                // this room does not have: `Compute Mean / Max` is in Prepare
                // (`PatternStatisticsSection`), and nothing here said so
                // (owner's drive 2026-09-06, `drive-precipitates` defect 2).
                // No compute action is offered here — that is the owner's call.
                Text("Needs the scan's Max pattern: Prepare → \"Compute Mean / Max\". "
                     + "Then propose reflections not on the matrix lattice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("precipitates.reflectionsHint")
            } else {
                // Keyed on `rowIdentity`, NOT `\.id`: this ForEach and the
                // objects table below live in one `Section`, a SwiftUI
                // container identifies rows by id value across both, and the
                // two `Int` id spaces overlap — the reflection rows claimed
                // ids 1…23 and hid objects #1…#23 (`fix-b/gateD-P6.md`).
                ForEach(appState.precipitates.reflections, id: \.rowIdentity) { candidate in
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
            // Short enough to survive the inspector's column: "Place detector
            // here" truncated to "Place dete…" on every row (owner's drive
            // 2026-09-06, `drive-precipitates` defect 11). The full sentence is
            // on `.help`, the choice this repo makes everywhere a row is
            // narrower than its text. No `.fixedSize()` — a changing label may
            // not set a column's minimum width (CLAUDE.md / open-items).
            Button("Place here") {
                appState.placeVirtualDetector(on: candidate)
            }
            .controlSize(.small)
            .disabled(appState.isBusy)
            .help("Place the virtual detector on this reflection and recompute "
                  + "the dark-field image. Stays in the Precipitates task.")
            .accessibilityIdentifier("precipitates.placeDetector.\(candidate.id)")
        }
        .accessibilityIdentifier("precipitates.reflectionRow.\(candidate.id)")
    }

    @ViewBuilder
    private var objectsTable: some View {
        let shown = appState.precipitates.objects.prefix(200)
        // `rowIdentity`, not `\.id` — see the reflection ForEach above and
        // `fix-b/gateD-P6.md`.
        ForEach(Array(shown), id: \.rowIdentity) { object in
            HStack(spacing: 6) {
                Toggle(isOn: Binding(
                    // `countedIDs`, not `acceptedIDs`: the toggle shows whether
                    // this object is COUNTED, and an edge object never is.
                    get: { appState.precipitates.countedIDs.contains(object.id) },
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

    /// One string, from the type that owns the numbers
    /// (`PrecipitateStatistics.densitySummary`): it names the pixel size the
    /// density was computed AT, and says the readout is stale once the session's
    /// calibration has moved away from it. Defects 7 and 8 of the 2026-09-06
    /// drive are both in that sentence.
    @ViewBuilder
    private var densityReadout: some View {
        if let density = appState.precipitates.density {
            LabeledContent(
                "Density",
                value: PrecipitateStatistics.densitySummary(
                    density,
                    currentPixelSize: appState.calibrationSession.calibration.rPixelSize
                )
            )
            .accessibilityIdentifier("precipitates.densityReadout")
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
