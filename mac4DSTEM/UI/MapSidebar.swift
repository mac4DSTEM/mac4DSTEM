import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// Strain & ACOM's sidebar (v2.5 step 7c slice 4a, plan §11d): one section
/// per task in pipeline order — disks produce the vectors strain and ACOM
/// consume. The strain section reads `StrainProduct` directly, the model
/// for the other two families; the ACOM controls still go through the
/// `AppState` forwarders until the run functions move into `ACOMSession`
/// (slice 4b). One file per workspace sidebar.
struct MapSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        @Bindable var strain = appState.strain
        switch appState.navigation.analysisMode {
        case .disks:
            Section("Disk detection") {
                DiskDetectionControls()
            }
            AdvancedDiskDetectionSection()
        case .strain:
            Section("Strain") {
                strainFailureRemedy

                Picker("Reference", selection: $strain.referenceMode) {
                    ForEach(StrainReferenceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .accessibilityIdentifier("strain.reference")
                // These two pickers ARE the scientific decision, so
                // they say what they decide rather than only what
                // they are set to (backlog #5).
                Text(appState.strain.referenceMode == .selectedRegion
                     ? "Defines zero strain: the visible \(appState.realSpaceShape.rawValue.lowercased()) ROI around the selected scan point is treated as unstrained."
                     : "Defines zero strain: the whole scan is averaged, so strain is measured relative to the mean lattice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Basis", selection: $strain.basisMode) {
                    ForEach(StrainBasisMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .accessibilityIdentifier("strain.basis")
                .help("The g₁ / g₂ pair every position is indexed against.")
                if appState.strain.basisMode == .manual {
                    // The unit stays *visible* rather than moving
                    // to hover: these are bare numbers, and a
                    // basis vector read in the wrong unit is a
                    // silently wrong strain map. Four rows, one
                    // component each — a row with two fields beside
                    // one label does not fit the column's minimum
                    // width (rule 5).
                    LabeledContent("g₁ x") {
                        NumericField(
                            title: "g₁ x",
                            value: $strain.g1X,
                            format: .number.precision(.fractionLength(3)),
                            unit: "px"
                        )
                    }
                    LabeledContent("g₁ y") {
                        NumericField(
                            title: "g₁ y",
                            value: $strain.g1Y,
                            format: .number.precision(.fractionLength(3)),
                            unit: "px"
                        )
                    }
                    LabeledContent("g₂ x") {
                        NumericField(
                            title: "g₂ x",
                            value: $strain.g2X,
                            format: .number.precision(.fractionLength(3)),
                            unit: "px"
                        )
                    }
                    LabeledContent("g₂ y") {
                        NumericField(
                            title: "g₂ y",
                            value: $strain.g2Y,
                            format: .number.precision(.fractionLength(3)),
                            unit: "px"
                        )
                    }
                    .help("Detector x/y offsets in calibrated pixels.")
                }
                Button {
                    Task { await appState.runStrainMapping() }
                } label: {
                    Label("Compute Strain Map", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(appState.isBusy || !appState.hasCurrentBraggVectors)
                if appState.diskDetectionSettingsAreStale {
                    Text("Detection settings changed — rerun Detect All Disks before strain.")
                        .font(.caption).foregroundStyle(.orange)
                } else if appState.braggVectors == nil {
                    Text("Detect Bragg disks first (Map → Bragg disks).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if appState.strain.map != nil {
                    Picker("Component", selection: $strain.component) {
                        ForEach(StrainComponent.allCases) { component in
                            Text(component.rawValue).tag(component)
                        }
                    }
                    .accessibilityIdentifier("strain.component")
                    // The frame the tensor components are expressed
                    // in — the map is drawn over scan axes, so a
                    // detector-frame εxx read as "along the map's
                    // horizontal" is silently wrong under a large
                    // R–Q rotation (v2 S8). One wording authority:
                    // StrainPresentationFrame.displayLabel.
                    Text(appState.strainPresentationFrame.displayLabel)
                        .font(.caption)
                        .foregroundStyle(
                            appState.strainPresentationFrame == .detector
                                ? AnyShapeStyle(.orange)
                                : AnyShapeStyle(.secondary)
                        )
                        .accessibilityIdentifier("strain.frame")
                    if let map = appState.strain.map {
                        LabeledContent(
                            map.diagnostics.automaticBasis
                                ? "Basis consensus" : "Basis support",
                            value: String(
                                format: "%.0f%% · %d/%d peaks",
                                map.diagnostics.basisSupportFraction * 100,
                                map.diagnostics.basisSupportCount,
                                map.diagnostics.basisObservationCount
                            )
                        )
                        .accessibilityIdentifier("strain.diagnostics.basisSupport")
                        LabeledContent(
                            "Basis fit",
                            value: String(
                                format: "RMS %.3g px · κ %.2f",
                                map.diagnostics.basisResidualPixels,
                                map.diagnostics.basisConditionNumber
                            )
                        )
                        .accessibilityIdentifier("strain.diagnostics.basisFit")
                        LabeledContent(
                            "Local fits",
                            value: String(
                                format: "%.0f%% indexed · median RMS %.3g px",
                                map.indexedFraction * 100,
                                map.diagnostics.localResidualMedianPixels
                            )
                        )
                        .accessibilityIdentifier("strain.diagnostics.localFits")
                        LabeledContent(
                            "Reference inliers",
                            value: "\(map.referencePositionCount)/\(map.diagnostics.referenceCandidateCount)"
                        )
                        .accessibilityIdentifier("strain.diagnostics.referenceInliers")
                    }
                }
            }

        case .acom:
            ACOMControlsView()
        default:
            EmptyView()
        }
    }

    /// After a failed strain run, offer the *one* control that addresses the
    /// cause rather than restating both possibilities (backlog #5b, #8b).
    @ViewBuilder
    private var strainFailureRemedy: some View {
        switch appState.strain.failureCause {
        case .starvedInput(let medianPeaks, let emptyPercent):
            Group {
                Label(
                    String(format: "Too few peaks: median %.1f per pattern, %d%% empty",
                           medianPeaks, emptyPercent),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                Text("Indexing needs the direct beam plus two more reflections. "
                     + "Lower the detection thresholds, not the reference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Go to Bragg Disks") { appState.changeMode(.disks) }
                    .accessibilityIdentifier("strain.remedy.disks")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strain.remedy")

        case .illConditionedBasis:
            Group {
                Label("No single lattice fits the whole reference",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if appState.strain.referenceMode == .wholeScan {
                    Text("The peak population is healthy. Averaging the whole scan "
                         + "mixes regions with different lattices — pick an "
                         + "unstrained region instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use the current ROI as the reference") {
                        appState.strain.referenceMode = .selectedRegion
                    }
                    .accessibilityIdentifier("strain.remedy.useROI")
                } else {
                    Text("Move or resize the reference region onto an unstrained "
                         + "area, or set g₁ and g₂ manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strain.remedy")

        case nil:
            EmptyView()
        }
    }

}
