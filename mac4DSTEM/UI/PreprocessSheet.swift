//
//  PreprocessSheet.swift
//  Role: "Preprocess Raw Data…" (X3) — write a reduced py4DSTEM DataCube from a
//        raw file, or from the open dataset's current view, with the load
//        configurator's own previews: crop by dragging, bin, then scan stride
//        and the optional hot-pixel filter, the output's size, a destination.
//
//  One sheet, two hosts. `LoadConfigurator` presents it for a raw file picked
//  in the sheet; `ExportSheet` presents it for the cube that is open. Crop, bin
//  and the size rows are the configurator's, shared (`ReductionSections`); the
//  choices that are only this sheet's live in `PendingLoad.preprocess`. The
//  write is `AppState.writePreprocessed` — the same Core writer and options the
//  open-cube export always used.
//
//  The readiness rows' container is re-authored here rather than shared with
//  `PrepareSettings`: a settings view's body is a bare set of `Section`s
//  belonging to the inspector, and this sheet needs the same *data* in its own
//  `Form`. The row bodies themselves are `CalibrationReadinessRow` — one
//  spelling shared by both hosts — and the filename-conflict parser and
//  manual-editor visibility policy are shared too, as pure statics.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct PreprocessSheet: View {
    @Environment(AppState.self) private var appState
    let pending: PendingLoad
    /// Close the sheet (discard the pending open, or dismiss).
    let close: () -> Void
    /// Pick another source file; nil when the source is the open view.
    let chooseSource: (() -> Void)?
    @State private var showUncalibratedWarning = false

    private var draft: PreprocessDraft {
        pending.preprocess ?? PreprocessDraft(origin: .rawFile)
    }

    private var configuration: LoadConfiguration { pending.configuration }

    private func binding<Value>(_ keyPath: WritableKeyPath<PreprocessDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { pending.preprocess?[keyPath: keyPath] = $0 }
        )
    }

    private var sourceName: String {
        if case .currentView(let name) = draft.origin { return name }
        return pending.url.lastPathComponent
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Divider()
            sourceRow
            ReductionPreviewPanes(pending: pending)
                .padding(.horizontal)
                .padding(.top)
            Form {
                strideSection
                ReductionBinSection(pending: pending)
                hotPixelSection
                if draft.showsCalibrationReadiness {
                    PreprocessReadinessSection()
                }
                sizeSection
                outputSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        // A band, not a fixed size: a short display shrinks the sheet rather
        // than pushing its own footer off screen. The configurator's band.
        .frame(
            minWidth: LayoutPolicy.configuratorSheet.min.width,
            idealWidth: LayoutPolicy.configuratorSheet.ideal.width,
            minHeight: LayoutPolicy.configuratorSheet.min.height,
            idealHeight: LayoutPolicy.configuratorSheet.ideal.height
        )
        // A write in flight is ended by its own Cancel, not by Escape.
        .interactiveDismissDisabled(draft.isWriting)
        .alert("Export with missing calibration?", isPresented: $showUncalibratedWarning) {
            Button("Keep Calibrating", role: .cancel) {}
            Button("Export Uncalibrated Anyway", role: .destructive) { beginWrite() }
        } message: {
            Text("Missing: \(missingCalibrationSummary). Values stay in pixels or are omitted.")
        }
    }

    private var missingCalibrationSummary: String {
        appState.calibrationSession.readiness.missingItems.map(\.kind.rawValue).joined(separator: ", ")
    }

    // MARK: - Title and source

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preprocess \(sourceName)")
                .font(.headline)
            // The one permanent caption: that the source is never touched is a
            // consequence the user cannot infer from the controls.
            Text("Write a reduced py4DSTEM DataCube. The source file is never changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var sourceRow: some View {
        HStack {
            Text("Source file")
            Spacer()
            if case .currentView = draft.origin {
                Text("\(sourceName) · current view")
                    .foregroundStyle(.secondary)
            } else {
                Text(sourceName)
                    .foregroundStyle(.secondary)
            }
            if let chooseSource {
                Button("Choose…", action: chooseSource)
                    .disabled(draft.isWriting)
                    .accessibilityIdentifier("preprocess.chooseSource")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Sections

    private var strideSection: some View {
        Section("Real-space crop") {
            // py4DSTEM thin_data_real: every Nth position, from the first.
            Stepper(
                "Scan stride  \(draft.effectiveStride(for: configuration))×",
                value: binding(\.scanStride),
                in: 1...PreprocessDraft.strideLimit(for: configuration)
            )
            .accessibilityIdentifier("preprocess.stride")
        }
    }

    private var hotPixelSection: some View {
        Section("Hot pixels") {
            Toggle("Filter hot pixels", isOn: binding(\.hotPixelsEnabled))
                .accessibilityIdentifier("preprocess.hotPixels")
            if draft.hotPixelsEnabled {
                LabeledContent("Threshold") {
                    OptionalNumericField(
                        title: "Threshold", value: draft.hotPixelThreshold,
                        format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
                    ) { if $0 > 0 { pending.preprocess?.hotPixelThreshold = $0 } }
                }
                // What the filter does, in py4DSTEM's own terms: a replacement
                // changes counts, so the sheet says which and how many.
                Text("py4DSTEM filter_hot_pixels, after the bin: pixels above their neighbourhood's second brightest by more than the threshold, in the mean pattern, become each pattern's 3×3 median. The positions found are stored in the file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sizeSection: some View {
        Section("Size") {
            ReductionSizeRows(pending: pending)
            ReductionSizeRow("This selection (f32)",
                             displayByteString(draft.outputBytes(for: configuration)))
            ReductionSizeRow("Output shape",
                             draft.outputShape(for: configuration).map(String.init).joined(separator: " × "))
        }
    }

    private var outputSection: some View {
        Section("Output") {
            LabeledContent("Destination") {
                HStack {
                    Text(draft.destinationLabel ?? "not chosen")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(draft.destination?.path ?? "")
                    Button("Choose…") { chooseDestination() }
                        .disabled(draft.isWriting)
                        .accessibilityIdentifier("preprocess.chooseDestination")
                }
            }
            // Not decoration: what the writer produces, and that it is atomic,
            // is the guarantee this sheet is asking the user to rely on.
            Text("Canonical py4DSTEM EMD · float32 · chunked · atomic. The source file is never changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let refusal = pending.refusalReason
        let writing = draft.isWriting
        return VStack(alignment: .leading, spacing: 12) {
            if let refusal {
                // Its own row: these are whole sentences naming detector rows
                // and columns, and a refusal the user cannot read is not one.
                InspectorWarning(refusal, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("preprocess.refusal")
            }
            if let failure = draft.failure {
                InspectorWarning("Not written: \(failure)")
                    .accessibilityIdentifier("preprocess.failure")
            }
            if let fraction = draft.writeProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction)
                    let total = draft.outputBytes(for: configuration)
                    Text("\(Int(fraction * 100)) % · \(displayByteString(Int(fraction * Double(total)))) of \(displayByteString(total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("Atomic: the file appears only when complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("preprocess.progress")
            }
            HStack {
                Button("Reset") { reset() }
                    .disabled(isUnchanged || writing)
                    .accessibilityIdentifier("preprocess.reset")
                Spacer()
                Button("Cancel") {
                    if writing { appState.cancelActiveOperation() } else { close() }
                }
                .keyboardShortcut(.cancelAction)
                Button(draft.destination == nil ? "Write…" : "Write") { write() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pending.view == nil || writing || appState.isBusy)
                    .accessibilityIdentifier("preprocess.write")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private var isUnchanged: Bool {
        pending.configuration.specification.isFullExtent
            && draft.scanStride == 1 && !draft.hotPixelsEnabled
    }

    private func reset() {
        pending.configuration.scanCrop = nil
        pending.configuration.detectorCrop = nil
        pending.configuration.detectorBin = 1
        pending.preprocess?.scanStride = 1
        pending.preprocess?.hotPixelsEnabled = false
    }

    private func chooseDestination() {
        let name = PreprocessDraft.suggestedFileName(forSource: sourceName)
        if let url = appState.choosePreprocessDestination(suggestedName: name) {
            pending.preprocess?.destination = url
        }
    }

    /// The draft as Write reads it. A click on Write does not take focus from a
    /// Mac text field (see `NumberEntryField`), so a Threshold typed but not
    /// yet committed is only registered in `PendingEdits`; it is committed
    /// first — before the readiness check, the alert and the writer's snapshot
    /// of `pending.preprocess` — or the file records the old threshold (Gate D
    /// 2026-10-04: typed 20, mouse-clicked Write, the file said 8). Static so
    /// the order is unit-tested.
    static func draftForWrite(_ pending: PendingLoad) -> PreprocessDraft {
        PendingEdits.commitAll()
        // The same fallback as `draft` above: keep the two in step.
        return pending.preprocess ?? PreprocessDraft(origin: .rawFile)
    }

    private func write() {
        // The rule the alert enforces: nothing is invented to fill a missing
        // calibration field. Only the open view has a session calibration.
        if Self.draftForWrite(pending).showsCalibrationReadiness, !appState.calibrationSession.readiness.isReady {
            showUncalibratedWarning = true
        } else {
            beginWrite()
        }
    }

    private func beginWrite() {
        if draft.destination == nil { chooseDestination() }
        guard let url = draft.destination else { return }
        appState.writePreprocessed(pending: pending, to: url) { outcome in
            guard case .wrote(let message) = outcome else { return }
            close()
            // After the close: discarding a pending open words the status line
            // itself. The sheet leaves the one line, no "Open result" button.
            appState.statusText = message
        }
    }
}

// MARK: - Calibration readiness (the open view only)

/// The session's calibration readiness, as the export sheet always showed it —
/// now only when the source is the open dataset (owner 2026-10-01, answer 1a).
private struct PreprocessReadinessSection: View {
    @Environment(AppState.self) private var appState

    private var readiness: CalibrationReadinessReport {
        appState.calibrationSession.readiness
    }

    var body: some View {
        Section("Calibration readiness") {
            Group {
                ForEach(readiness.items) { item in
                    readinessRow(item)
                }
                // The same verdict the dataset card shows.
                let verdict = appState.calibrationSession.verdict
                Label(verdict.summary,
                      systemImage: verdict.quantitative ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
                    .accessibilityIdentifier(verdict.quantitative ? "calibration.ready" : "calibration.notQuantitative")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calibration.readiness")

            if !readiness.isReady {
                // The rule the destructive alert enforces: nothing is invented
                // to fill a missing field.
                Text("Missing fields are allowed only after an explicit export warning; no value is invented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One calibration's readiness row — shared with `PrepareSettings` as
    /// `CalibrationReadinessRow.row` (hygiene audit row 1 follow-up): a
    /// duplicate copy had silently dropped the "fit anyway" orange warning;
    /// sharing the row prevents that drift from recurring.
    @ViewBuilder
    private func readinessRow(_ item: CalibrationReadinessItem) -> some View {
        CalibrationReadinessRow.row(
            item, appState: appState,
            rScaleFilenameConflict: rScaleFilenameConflict,
            qScaleUnavailableReason: qScaleUnavailableReason
        )
    }

    /// A scan-step token in the filename that disagrees with the R pixel scale
    /// actually in use, if both exist and they differ materially.
    ///
    /// File metadata rightly wins over a filename — but a user reading
    /// `…ss30nm…` while the app quietly uses an imported 49.5 nm/px gets no
    /// hint the two disagree, and R scale silently rescales every real-space
    /// axis and scale bar. This surfaces the disagreement without changing the
    /// precedence. Comparison is done in Å/px so a token in nm and a value in
    /// Å are not reported as a conflict merely for being in different units.
    ///
    /// The parser itself is `PrepareSettings`'s pure static, deliberately
    /// not a second copy: the regex is pinned by a test, and two spellings of
    /// it in UI is exactly the drift that produces a warning on one surface
    /// and silence on the other.
    private var rScaleFilenameConflict: String? {
        guard let path = appState.descriptor?.filePath,
              let size = appState.calibrationSession.calibration.rPixelSize,
              let inUse = CalibrationUnitConversion.realAngstromPerPixel(
                  value: size, units: appState.calibrationSession.calibration.rPixelUnits
              ),
              let token = PrepareSettings.scanStepAngstromPerPixel(inFilename: path)
        else { return nil }

        // 5% absorbs rounding in an abbreviated filename token (a file written
        // as "ss30nm" for a true 30.4 nm step is not a conflict); a genuine
        // mismatch like 30 vs 49.5 nm is 65% out and still reported.
        let tolerance = 0.05
        guard abs(token.angstromPerPixel - inUse) > tolerance * max(token.angstromPerPixel, inUse)
        else { return nil }

        return "Filename says \(token.text) per scan step, but \(CalibrationUnitConversion.isPixelUnit(appState.calibrationSession.calibration.rPixelUnits) ? "the value in use" : "the imported value") is different. File metadata takes precedence — check which is right before trusting real-space scales."
    }

    /// Two-part condition (`hasCurrentBraggVectors && resolvedACOMModel != nil`)
    /// gets a caption naming whichever half is actually missing, so a user who
    /// has already detected disks isn't told to redo a step they've finished.
    private var qScaleUnavailableReason: String {
        if !appState.hasCurrentBraggVectors {
            return "Detect disks and choose a phase model to calibrate Q from a known crystal."
        } else {
            return "Choose a phase model to calibrate Q from a known crystal."
        }
    }
}
