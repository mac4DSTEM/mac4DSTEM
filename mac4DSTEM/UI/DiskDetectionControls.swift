import SwiftUI

/// Source-faithful controls for py4DSTEM-style Bragg-disk detection. The
/// compact defaults stay visible; less commonly changed signal/filter
/// parameters live in the same disclosure pattern used by the rest of the
/// tools sidebar.
struct DiskDetectionControls: View {
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
            .font(.caption)
        }

        parameterSlider(
            title: DiskDetectionParameterID.correlationPower.title,
            value: floatBinding(
                \.corrPower, in: floatEditorRange(.correlationPower)
            ),
            range: floatEditorRange(.correlationPower),
            step: Float(DiskDetectionParameterID.correlationPower.editorStep!),
            valueText: String(format: "%.2f", appState.diskParams.corrPower)
        )
        .help(DiskDetectionParameterID.correlationPower.explanation)

        Picker(
            DiskDetectionParameterID.subpixel.title,
            selection: parameterBinding(\.subpixel)
        ) {
            ForEach(SubpixelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .help(DiskDetectionParameterID.subpixel.explanation)

        Stepper(value: maximumPeaksBinding, in: 1...500) {
            Text("\(DiskDetectionParameterID.maximumPeaks.title)  \(appState.diskParams.maxNumPeaks)")
                .font(.caption)
        }
        .help(DiskDetectionParameterID.maximumPeaks.explanation)

        if appState.probeKernel != nil {
            LabeledContent("Current CBED", value: "\(appState.currentPeaks.count) peaks")
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier("disk.currentPeakCount")
            if let diagnostics = appState.currentDiskDiagnostics {
                LabeledContent(
                    "Acceptance funnel",
                    value: "\(diagnostics.localMaximumCount) candidates → \(diagnostics.acceptedCount) accepted"
                )
                .font(.caption2.monospacedDigit())
                .help("Edge-qualified local maxima before filters, followed by the final accepted peak count.")
                Text(
                    "absolute \(diagnostics.afterAbsoluteThresholdCount) · relative \(diagnostics.afterRelativeThresholdCount) · spacing \(diagnostics.afterSpacingCount)"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if diagnostics.wasCountLimited {
                    Label(
                        "This pattern was truncated to the configured maximum peak count.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if appState.diskParams.minRelativeIntensity > 0,
                   !diagnostics.relativeReferenceWasAvailable {
                    Label(
                        "The selected reference-peak rank is absent in this pattern; the relative filter cannot be evaluated.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("Build a probe kernel to preview detections on the current CBED.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        ForEach(
            Array(appState.diskDetectionValidationIssues.enumerated()), id: \.offset
        ) { _, issue in
            Label(
                issue.message,
                systemImage: issue.severity == .error
                    ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption2)
            .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signal conditioning")
                    .font(.caption.weight(.semibold))

                parameterSlider(
                    title: DiskDetectionParameterID.patternSigma.title,
                    value: floatBinding(
                        \.sigmaDP, in: floatEditorRange(.patternSigma)
                    ),
                    range: floatEditorRange(.patternSigma),
                    step: Float(DiskDetectionParameterID.patternSigma.editorStep!),
                    valueText: String(format: "%.1f px", appState.diskParams.sigmaDP)
                )
                .help(DiskDetectionParameterID.patternSigma.explanation)

                parameterSlider(
                    title: DiskDetectionParameterID.correlationSigma.title,
                    value: floatBinding(
                        \.sigmaCC, in: floatEditorRange(.correlationSigma)
                    ),
                    range: floatEditorRange(.correlationSigma),
                    step: Float(DiskDetectionParameterID.correlationSigma.editorStep!),
                    valueText: String(format: "%.1f px", appState.diskParams.sigmaCC)
                )
                .help(DiskDetectionParameterID.correlationSigma.explanation)

                Divider()

                Text("Peak acceptance")
                    .font(.caption.weight(.semibold))

                HStack {
                    Text(DiskDetectionParameterID.minimumAbsoluteIntensity.title)
                        .font(.caption)
                    Spacer()
                    TextField(
                        "0",
                        value: nonnegativeFloatBinding(\.minAbsoluteIntensity),
                        format: .number.precision(.significantDigits(1...5))
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                    Text("CC")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .help(DiskDetectionParameterID.minimumAbsoluteIntensity.explanation)

                HStack {
                    Text(DiskDetectionParameterID.minimumRelativeIntensity.title)
                        .font(.caption)
                    Spacer()
                    TextField(
                        "0",
                        value: relativeIntensityPercentBinding,
                        format: .number.precision(.fractionLength(0...3))
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    Text("%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .help(DiskDetectionParameterID.minimumRelativeIntensity.explanation)

                Stepper(value: relativePeakRankBinding, in: 1...max(1, appState.diskParams.maxNumPeaks)) {
                    Text("\(DiskDetectionParameterID.relativeReferencePeak.title)  #\(appState.diskParams.relativeToPeak + 1)")
                        .font(.caption)
                }
                .help(DiskDetectionParameterID.relativeReferencePeak.explanation)

                Stepper(
                    value: floatBinding(\.minPeakSpacing, in: 0...Float(detectorMinimum)),
                    in: 0...Float(detectorMinimum),
                    step: 1
                ) {
                    Text(String(
                        format: "%@  %.0f px",
                        DiskDetectionParameterID.minimumPeakSpacing.title,
                        appState.diskParams.minPeakSpacing
                    ))
                    .font(.caption)
                }
                .help(DiskDetectionParameterID.minimumPeakSpacing.explanation)

                Stepper(
                    value: intBinding(\.edgeBoundary, in: 1...maximumEdgeBoundary),
                    in: 1...maximumEdgeBoundary
                ) {
                    Text("\(DiskDetectionParameterID.edgeBoundary.title)  \(appState.diskParams.edgeBoundary) px")
                        .font(.caption)
                }
                .help(DiskDetectionParameterID.edgeBoundary.explanation)

                if appState.diskParams.subpixel == .multicorr {
                    Divider()

                    Text("Fourier localization")
                        .font(.caption.weight(.semibold))

                    Stepper(
                        value: intBinding(\.upsampleFactor, in: 4...64),
                        in: 4...64,
                        step: 4
                    ) {
                        Text("\(DiskDetectionParameterID.upsampleFactor.title)  \(appState.diskParams.upsampleFactor)×")
                            .font(.caption)
                    }
                    .help(DiskDetectionParameterID.upsampleFactor.explanation)
                }

                Text("Changes update the rings on the current CBED. Run the full-scan action to apply them to strain and ACOM.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    appState.resetDiskDetectionParams()
                } label: {
                    Label("Reset Recommended Settings", systemImage: "arrow.counterclockwise")
                }
                .disabled(appState.isBusy)
                .accessibilityIdentifier("disk.resetParameters")
            }
            .padding(.top, 6)
        } label: {
            Label("Advanced Detection", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("disk.advancedDisclosure")

        Button {
            Task { await appState.runDiskDetection() }
        } label: {
            Label("Detect All Disks", systemImage: "rays")
        }
        .disabled(appState.isBusy || !appState.diskDetectionConfigurationIsValid)
        .accessibilityIdentifier("disk.detectAll")

        if appState.diskDetectionSettingsAreStale {
            Label("Full-scan peaks use earlier settings", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Run Detect All Disks again before using the new settings for strain or ACOM.")
        } else if let count = appState.braggPeakCount {
            LabeledContent("Peaks found", value: "\(count)")
                .font(.caption)
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
                .font(.caption2.monospacedDigit())
                ForEach(Array(summary.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func parameterSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: value, in: range, step: step)
        }
    }

    private func floatEditorRange(
        _ parameter: DiskDetectionParameterID
    ) -> ClosedRange<Float> {
        let range = parameter.editorRange ?? 0...1
        return Float(range.lowerBound)...Float(range.upperBound)
    }

    private func parameterBinding<Value>(
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

    private var maximumPeaksBinding: Binding<Int> {
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
    private var relativeIntensityPercentBinding: Binding<Double> {
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

    private var relativePeakRankBinding: Binding<Int> {
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
}
