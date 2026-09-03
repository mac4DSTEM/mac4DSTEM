import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Source-faithful controls for py4DSTEM-style Bragg-disk detection: the
/// compact defaults stay visible as rows of the "Disk detection" section
/// (`MapSidebar`); the less commonly changed signal/filter parameters live in
/// the sibling `AdvancedDiskDetectionSection`, a collapsed section of its own
/// (presentation contract rule 4 — a `DisclosureGroup` inside a Form section
/// does not fit the grouped-Form contract, so the disclosure is the section).
struct DiskDetectionControls: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            Task { await appState.generateProbeKernel() }
        } label: {
            Label("Generate Probe Kernel", systemImage: "circle.circle")
        }
        .disabled(appState.isBusy)
        .accessibilityIdentifier("disk.generateSyntheticKernel")

        Button {
            Task { await appState.generateMeasuredProbeKernel() }
        } label: {
            Label("Use Current CBED / ROI", systemImage: "scope")
        }
        .disabled(appState.isBusy || appState.displayedPattern == nil)
        .accessibilityIdentifier("disk.generateMeasuredKernel")
        .help("Select a vacuum point or real-space ROI, then build the disk-correlation kernel from its displayed diffraction pattern.")

        if let kernel = appState.probeKernel {
            LabeledContent(
                "Kernel",
                value: String(
                    format: "%@ · %.1f px", kernel.source.rawValue, kernel.probeRadius
                )
            )
        }

        parameterSliderRow(
            title: DiskDetectionParameterID.correlationPower.title,
            value: floatBinding(
                appState, \.corrPower, in: floatEditorRange(.correlationPower)
            ),
            range: floatEditorRange(.correlationPower),
            step: Float(DiskDetectionParameterID.correlationPower.editorStep!),
            valueText: String(format: "%.2f", appState.diskParams.corrPower)
        )
        .help(DiskDetectionParameterID.correlationPower.explanation)

        Picker(
            DiskDetectionParameterID.subpixel.title,
            selection: parameterBinding(appState, \.subpixel)
        ) {
            ForEach(SubpixelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .help(DiskDetectionParameterID.subpixel.explanation)

        Stepper(value: maximumPeaksBinding(appState), in: 1...500) {
            Text("\(DiskDetectionParameterID.maximumPeaks.title)  \(appState.diskParams.maxNumPeaks)")
        }
        .help(DiskDetectionParameterID.maximumPeaks.explanation)

        if appState.probeKernel != nil {
            LabeledContent("Current CBED", value: "\(appState.currentPeaks.count) peaks")
                .monospacedDigit()
                .accessibilityIdentifier("disk.currentPeakCount")
            if let diagnostics = appState.currentDiskDiagnostics {
                LabeledContent(
                    "Acceptance funnel",
                    value: "\(diagnostics.localMaximumCount) candidates → \(diagnostics.acceptedCount) accepted"
                )
                .monospacedDigit()
                .help("Edge-qualified local maxima before filters, followed by the final accepted peak count.")
                Text(
                    "absolute \(diagnostics.afterAbsoluteThresholdCount) · relative \(diagnostics.afterRelativeThresholdCount) · spacing \(diagnostics.afterSpacingCount)"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                if diagnostics.wasCountLimited {
                    Label(
                        "This pattern was truncated to the configured maximum peak count.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if appState.diskParams.minRelativeIntensity > 0,
                   !diagnostics.relativeReferenceWasAvailable {
                    Label(
                        "The selected reference-peak rank is absent in this pattern; the relative filter cannot be evaluated.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        } else {
            Text("Build a probe kernel to preview detections on the current CBED.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ForEach(
            Array(appState.diskDetectionValidationIssues.enumerated()), id: \.offset
        ) { _, issue in
            Label(
                issue.message,
                systemImage: issue.severity == .error
                    ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
        }

        Text("Use the workspace action to run full-scan detection.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if appState.diskDetectionSettingsAreStale {
            Label("Full-scan peaks use earlier settings", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Run Detect All Disks again before using the new settings for strain or ACOM.")
        } else if let count = appState.braggPeakCount {
            LabeledContent("Peaks found", value: "\(count)")
            if let summary = appState.completedDiskSummary {
                LabeledContent(
                    "Per pattern",
                    value: String(
                        format: "median %.1f · range %d–%d",
                        summary.medianPeakCount,
                        summary.minimumPeakCount,
                        summary.maximumPeakCount
                    )
                )
                .monospacedDigit()
                ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// The less commonly changed signal/filter parameters, as their own collapsed
/// section (presentation contract rule 4: a `Section("Title", isExpanded:)`
/// of the column's Form, not a `DisclosureGroup` nested inside one). A
/// sibling of `DiskDetectionControls`'s basic-rows section, not a child of it
/// — `MapSidebar`'s `.disks` case emits both.
struct AdvancedDiskDetectionSection: View {
    @Environment(AppState.self) private var appState
    @State private var showsAdvanced = false

    private var detectorMinimum: Int {
        guard let descriptor = appState.descriptor else { return 1 }
        return max(1, min(descriptor.qx, descriptor.qy))
    }

    private var maximumEdgeBoundary: Int {
        appState.diskDetectionContext?.maximumEdgeBoundary
            ?? max(1, (detectorMinimum - 1) / 2)
    }

    var body: some View {
        Section("Advanced detection", isExpanded: $showsAdvanced) {
            // Signal conditioning.
            parameterSliderRow(
                title: DiskDetectionParameterID.patternSigma.title,
                value: floatBinding(
                    appState, \.sigmaDP, in: floatEditorRange(.patternSigma)
                ),
                range: floatEditorRange(.patternSigma),
                step: Float(DiskDetectionParameterID.patternSigma.editorStep!),
                valueText: String(format: "%.1f px", appState.diskParams.sigmaDP)
            )
            .help(DiskDetectionParameterID.patternSigma.explanation)

            parameterSliderRow(
                title: DiskDetectionParameterID.correlationSigma.title,
                value: floatBinding(
                    appState, \.sigmaCC, in: floatEditorRange(.correlationSigma)
                ),
                range: floatEditorRange(.correlationSigma),
                step: Float(DiskDetectionParameterID.correlationSigma.editorStep!),
                valueText: String(format: "%.1f px", appState.diskParams.sigmaCC)
            )
            .help(DiskDetectionParameterID.correlationSigma.explanation)

            // Peak acceptance.
            LabeledContent(DiskDetectionParameterID.minimumAbsoluteIntensity.title) {
                NumericField(
                    title: DiskDetectionParameterID.minimumAbsoluteIntensity.title,
                    value: nonnegativeFloatBinding(appState, \.minAbsoluteIntensity),
                    format: .number.precision(.significantDigits(1...5)),
                    unit: "CC"
                )
            }
            .help(DiskDetectionParameterID.minimumAbsoluteIntensity.explanation)

            LabeledContent(DiskDetectionParameterID.minimumRelativeIntensity.title) {
                NumericField(
                    title: DiskDetectionParameterID.minimumRelativeIntensity.title,
                    value: relativeIntensityPercentBinding(appState),
                    format: .number.precision(.fractionLength(0...3)),
                    unit: "%"
                )
            }
            .help(DiskDetectionParameterID.minimumRelativeIntensity.explanation)

            Stepper(value: relativePeakRankBinding(appState), in: 1...max(1, appState.diskParams.maxNumPeaks)) {
                Text("\(DiskDetectionParameterID.relativeReferencePeak.title)  #\(appState.diskParams.relativeToPeak + 1)")
            }
            .help(DiskDetectionParameterID.relativeReferencePeak.explanation)

            Stepper(
                value: floatBinding(appState, \.minPeakSpacing, in: 0...Float(detectorMinimum)),
                in: 0...Float(detectorMinimum),
                step: 1
            ) {
                Text(String(
                    format: "%@  %.0f px",
                    DiskDetectionParameterID.minimumPeakSpacing.title,
                    appState.diskParams.minPeakSpacing
                ))
            }
            .help(DiskDetectionParameterID.minimumPeakSpacing.explanation)

            Stepper(
                value: intBinding(appState, \.edgeBoundary, in: 1...maximumEdgeBoundary),
                in: 1...maximumEdgeBoundary
            ) {
                Text("\(DiskDetectionParameterID.edgeBoundary.title)  \(appState.diskParams.edgeBoundary) px")
            }
            .help(DiskDetectionParameterID.edgeBoundary.explanation)

            // Fourier localization.
            if appState.diskParams.subpixel == .multicorr {
                Stepper(
                    value: intBinding(appState, \.upsampleFactor, in: 4...64),
                    in: 4...64,
                    step: 4
                ) {
                    Text("\(DiskDetectionParameterID.upsampleFactor.title)  \(appState.diskParams.upsampleFactor)×")
                }
                .help(DiskDetectionParameterID.upsampleFactor.explanation)
            }

            Text("Changes update the rings on the current CBED. Run the full-scan action to apply them to strain and ACOM.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                appState.resetDiskDetectionParams()
            } label: {
                Label("Reset Recommended Settings", systemImage: "arrow.counterclockwise")
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("disk.resetParameters")
        }
        .accessibilityIdentifier("disk.advancedDisclosure")
    }
}

// MARK: - Shared rows and bindings

/// A parameter slider row: the title and current value as the slider's own
/// label. Not a `LabeledContent` — as a trailing value a slider collapses
/// to its knob at 250 pt (measured 2026-09-03).
private func parameterSliderRow(
    title: String,
    value: Binding<Float>,
    range: ClosedRange<Float>,
    step: Float,
    valueText: String
) -> some View {
    Slider(value: value, in: range, step: step) {
        Text("\(title), \(valueText)")
    }
}

private func floatEditorRange(
    _ parameter: DiskDetectionParameterID
) -> ClosedRange<Float> {
    let range = parameter.editorRange ?? 0...1
    return Float(range.lowerBound)...Float(range.upperBound)
}

private func parameterBinding<Value>(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Value>
) -> Binding<Value> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = value
            appState.diskParams = params
        }
    )
}

private func floatBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Float>,
    in range: ClosedRange<Float>
) -> Binding<Float> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diskParams = params
        }
    )
}

private func nonnegativeFloatBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Float>
) -> Binding<Float> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = value.isFinite ? max(0, value) : 0
            appState.diskParams = params
        }
    )
}

private func intBinding(
    _ appState: AppState,
    _ keyPath: WritableKeyPath<DiskDetectionParams, Int>,
    in range: ClosedRange<Int>
) -> Binding<Int> {
    Binding(
        get: { appState.diskParams[keyPath: keyPath] },
        set: { value in
            var params = appState.diskParams
            params[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
            appState.diskParams = params
        }
    )
}

private func maximumPeaksBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diskParams.maxNumPeaks },
        set: { value in
            var params = appState.diskParams
            params.maxNumPeaks = min(max(value, 1), 500)
            params.relativeToPeak = min(params.relativeToPeak, params.maxNumPeaks - 1)
            appState.diskParams = params
        }
    )
}

/// py4DSTEM stores this value as a fraction. Percent is easier to reason
/// about in a compact UI while preserving the exact underlying parameter.
private func relativeIntensityPercentBinding(_ appState: AppState) -> Binding<Double> {
    Binding(
        get: { Double(appState.diskParams.minRelativeIntensity) * 100 },
        set: { value in
            var params = appState.diskParams
            let finite = value.isFinite ? value : 0
            params.minRelativeIntensity = Float(min(max(finite, 0), 100) / 100)
            appState.diskParams = params
        }
    )
}

private func relativePeakRankBinding(_ appState: AppState) -> Binding<Int> {
    Binding(
        get: { appState.diskParams.relativeToPeak + 1 },
        set: { rank in
            var params = appState.diskParams
            params.relativeToPeak = min(
                max(0, rank - 1), max(0, params.maxNumPeaks - 1)
            )
            appState.diskParams = params
        }
    )
}
