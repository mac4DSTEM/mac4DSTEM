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
        max(1, (detectorMinimum - 1) / 2)
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
            title: "Correlation power",
            value: floatBinding(\.corrPower, in: 0...1),
            range: 0...1,
            step: 0.05,
            valueText: String(format: "%.2f", appState.diskParams.corrPower)
        )
        .help("1 is cross-correlation, 0 is phase-correlation, and intermediate values are hybrid correlation.")

        Picker("Subpixel", selection: parameterBinding(\.subpixel)) {
            ForEach(SubpixelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .help("Pixel is fastest; Parabolic is the interactive default; Fourier (multicorr) is slowest and intended for strain-grade localization.")

        Stepper(value: maximumPeaksBinding, in: 1...500) {
            Text("Maximum peaks  \(appState.diskParams.maxNumPeaks)")
                .font(.caption)
        }
        .help("Maximum number of correlation maxima returned for each diffraction pattern.")

        if appState.probeKernel != nil {
            LabeledContent("Current CBED", value: "\(appState.currentPeaks.count) peaks")
                .font(.caption.monospacedDigit())
                .accessibilityIdentifier("disk.currentPeakCount")
        } else {
            Text("Build a probe kernel to preview detections on the current CBED.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        DisclosureGroup(isExpanded: $showsAdvanced) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signal conditioning")
                    .font(.caption.weight(.semibold))

                parameterSlider(
                    title: "Pattern smoothing σ",
                    value: floatBinding(\.sigmaDP, in: 0...10),
                    range: 0...10,
                    step: 0.1,
                    valueText: String(format: "%.1f px", appState.diskParams.sigmaDP)
                )
                .help("Gaussian σ applied to each diffraction pattern before correlation. It can suppress pixel noise, but excessive smoothing merges nearby features.")

                parameterSlider(
                    title: "Correlation smoothing σ",
                    value: floatBinding(\.sigmaCC, in: 0...10),
                    range: 0...10,
                    step: 0.1,
                    valueText: String(format: "%.1f px", appState.diskParams.sigmaCC)
                )
                .help("Gaussian σ applied to the correlation map before maxima are selected. Zero disables smoothing.")

                Divider()

                Text("Peak acceptance")
                    .font(.caption.weight(.semibold))

                HStack {
                    Text("Minimum absolute")
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
                .help("Minimum correlation-peak intensity on the absolute correlation scale. Zero disables this filter; values depend on the data and probe kernel.")

                HStack {
                    Text("Minimum relative")
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
                .help("Minimum peak intensity as a percentage of the selected reference peak. Zero disables this filter.")

                Stepper(value: relativePeakRankBinding, in: 1...max(1, appState.diskParams.maxNumPeaks)) {
                    Text("Reference peak  #\(appState.diskParams.relativeToPeak + 1)")
                        .font(.caption)
                }
                .help("Rank used by the relative intensity filter: #1 is the brightest correlation maximum, #2 the next brightest, and so on.")

                Stepper(
                    value: floatBinding(\.minPeakSpacing, in: 0...Float(detectorMinimum)),
                    in: 0...Float(detectorMinimum),
                    step: 1
                ) {
                    Text(String(
                        format: "Minimum spacing  %.0f px", appState.diskParams.minPeakSpacing
                    ))
                    .font(.caption)
                }
                .help("Minimum center-to-center separation. When maxima are too close, the brighter candidate is kept.")

                Stepper(
                    value: intBinding(\.edgeBoundary, in: 1...maximumEdgeBoundary),
                    in: 1...maximumEdgeBoundary
                ) {
                    Text("Edge exclusion  \(appState.diskParams.edgeBoundary) px")
                        .font(.caption)
                }
                .help("Reject maxima whose centers lie within this many detector pixels of any pattern edge.")

                if appState.diskParams.subpixel == .multicorr {
                    Divider()

                    Text("Fourier localization")
                        .font(.caption.weight(.semibold))

                    Stepper(
                        value: intBinding(\.upsampleFactor, in: 4...64),
                        in: 4...64,
                        step: 4
                    ) {
                        Text("Upsampling  \(appState.diskParams.upsampleFactor)×")
                            .font(.caption)
                    }
                    .help("Matrix-DFT upsampling used only by Fourier (multicorr) refinement. Higher values improve sampling at increased cost.")
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
        .disabled(appState.isBusy)
        .accessibilityIdentifier("disk.detectAll")

        if appState.diskDetectionSettingsAreStale {
            Label("Full-scan peaks use earlier settings", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Run Detect All Disks again before using the new settings for strain or ACOM.")
        } else if let count = appState.braggPeakCount {
            LabeledContent("Peaks found", value: "\(count)")
                .font(.caption)
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
