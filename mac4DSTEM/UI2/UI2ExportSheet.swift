//
//  UI2ExportSheet.swift
//  Role: the guided front end for the bounded canonical DataCube writer, in
//        UI2. Defaults are deliberately lossless (full scan, Q bin 1); every
//        destructive reduction is visible in the output preview before the
//        save panel appears.
//
//  The migration of `UI/PreprocessingExportSheet` (and, for its readiness
//  block, `UI/CalibrationReadinessView`) into UI2. Every number, every unit,
//  every provenance word, the uncalibrated-export warning and its wording, and
//  every accessibility identifier are carried over unchanged.
//
//  WHY THE READINESS ROWS ARE RE-AUTHORED HERE rather than shared with
//  `UI2PrepareSettings`: a settings view's body is a bare set of `Section`s
//  belonging to the inspector, and this sheet needs the same *data* in its own
//  `Form`. The rows are therefore the same shape, read the same
//  `appState.calibrationSession.readiness`, and print the same strings; only
//  the filename-conflict parser is shared, as a pure static, so the regex
//  `CalibrationReadinessFilenameTests` pins has one spelling in UI2.
//

import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct UI2ExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let descriptor: DatasetDescriptor

    @State private var cropEnabled = false
    @State private var xStart: Int
    @State private var xEnd: Int
    @State private var yStart: Int
    @State private var yEnd: Int
    @State private var qBin = 1
    @State private var showUncalibratedWarning = false

    init(descriptor: DatasetDescriptor) {
        self.descriptor = descriptor
        _xStart = State(initialValue: 0)
        _xEnd = State(initialValue: max(0, descriptor.rx - 1))
        _yStart = State(initialValue: 0)
        _yEnd = State(initialValue: max(0, descriptor.ry - 1))
    }

    // MARK: - What would be written

    private var scanX: Range<Int> {
        cropEnabled ? xStart..<(xEnd + 1) : 0..<descriptor.rx
    }

    private var scanY: Range<Int> {
        cropEnabled ? yStart..<(yEnd + 1) : 0..<descriptor.ry
    }

    private var outputShape: [Int] {
        [scanY.count, scanX.count, descriptor.qy / qBin, descriptor.qx / qBin]
    }

    private var estimatedBytes: Double {
        outputShape.reduce(Double(MemoryLayout<Float>.size)) { $0 * Double($1) }
    }

    private var readiness: CalibrationReadinessReport {
        appState.calibrationSession.readiness
    }

    private var missingCalibrationSummary: String {
        readiness.missingItems.map(\.kind.rawValue).joined(separator: ", ")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            Divider()
            Form {
                calibrationSection
                cropSection
                binningSection
                outputSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        // A band, not a fixed size: a short display must shrink the sheet
        // rather than push its own footer off screen.
        .frame(
            minWidth: UI2Metrics.exportSheet.min.width,
            idealWidth: UI2Metrics.exportSheet.ideal.width,
            minHeight: UI2Metrics.exportSheet.min.height,
            idealHeight: UI2Metrics.exportSheet.ideal.height
        )
        .alert("Export with missing calibration?", isPresented: $showUncalibratedWarning) {
            Button("Keep Calibrating", role: .cancel) {}
            Button("Export Uncalibrated Anyway", role: .destructive) {
                beginExport()
            }
        } message: {
            Text("Missing: \(missingCalibrationSummary). Values stay in pixels or are omitted.")
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preprocess & Export DataCube")
                .font(.headline)
            // Not decoration: what the writer produces, and that it is atomic,
            // is the guarantee this sheet is asking the user to rely on.
            Text("Canonical py4DSTEM EMD · float32 · chunked · atomic")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    // MARK: - Sections

    private var calibrationSection: some View {
        Section("Calibration readiness") {
            Group {
                ForEach(readiness.items) { item in
                    readinessRow(item)
                }
                // v2.5 step 4b: the same verdict the dataset card shows.
                let verdict = appState.calibrationSession.verdict
                Label(verdict.summary,
                      systemImage: verdict.quantitative ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    .foregroundStyle(verdict.quantitative ? Color.green : Color.orange)
                    .accessibilityIdentifier(verdict.quantitative ? "calibration.ready" : "calibration.notQuantitative")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calibration.readiness")

            if !readiness.isReady {
                // The rule the destructive alert below enforces: nothing is
                // invented to fill a missing field.
                Text("Missing fields are allowed only after an explicit export warning; no value is invented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cropSection: some View {
        Section("Real-space crop") {
            Toggle("Crop scan", isOn: $cropEnabled)
            if cropEnabled {
                Stepper("X start  \(xStart)", value: $xStart,
                        in: 0...max(0, xEnd))
                Stepper("X end  \(xEnd)", value: $xEnd,
                        in: xStart...max(xStart, descriptor.rx - 1))
                Stepper("Y start  \(yStart)", value: $yStart,
                        in: 0...max(0, yEnd))
                Stepper("Y end  \(yEnd)", value: $yEnd,
                        in: yStart...max(yStart, descriptor.ry - 1))
            }
        }
    }

    private var binningSection: some View {
        Section("Diffraction binning") {
            Stepper("Integer Q bin  \(qBin)×", value: $qBin,
                    in: 1...max(1, min(descriptor.qy, descriptor.qx)))
            // How the bin is reduced, and what happens to the remainder, are
            // both scientific consequences of the number above.
            Text("Bins are summed to preserve detector counts. Incomplete bottom/right blocks are trimmed, matching py4DSTEM bin_Q.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var outputSection: some View {
        Section("Output preview") {
            LabeledContent("Shape", value: outputShape.map(String.init).joined(separator: " × "))
            LabeledContent("Float32 data", value: ByteCountFormatter.string(
                fromByteCount: Int64(estimatedBytes), countStyle: .file
            ))
            if descriptor.qy % qBin != 0 || descriptor.qx % qBin != 0 {
                Label(
                    "Trims \(descriptor.qy % qBin) detector row(s) and \(descriptor.qx % qBin) column(s)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Choose Destination…") {
                if readiness.isReady {
                    beginExport()
                } else {
                    showUncalibratedWarning = true
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(appState.isBusy)
        }
        .padding()
    }

    private func beginExport() {
        let options = CalibratedDataCubeExportOptions(
            scanY: scanY, scanX: scanX, qBin: qBin, tileRows: 1
        )
        dismiss()
        appState.exportCalibratedDataCube(options: options)
    }

    // MARK: - Readiness rows

    /// One calibration as a `LabeledContent` row — the kind with its status
    /// glyph and the calibrated value under it as the label, the provenance
    /// ("From file" / "Measured" / …, never demoted) as the content —
    /// followed by its warning and its action. Inside a `Form` the label
    /// stacks and the detail wraps to the column on its own.
    @ViewBuilder
    private func readinessRow(_ item: CalibrationReadinessItem) -> some View {
        LabeledContent {
            Text(item.status.displayName)
                .foregroundStyle(item.status.isReady ? Color.secondary : Color.orange)
                .fixedSize()
        } label: {
            Label {
                Text(item.kind.rawValue)
                    .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
            } icon: {
                Image(systemName: item.status.isReady
                        ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(item.status.isReady ? Color.green : Color.orange)
            }
            // The calibrated value and its units — the scientific content of
            // the row, on screen unconditionally, wrapping never truncating
            // (S22d: the tail is the caveat).
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // `unlockSummary` says what this calibration *enables*: on hover and
        // in the accessibility description, not permanently under six rows.
        .help("\(item.detail)\n\n\(item.kind.unlockSummary)")
        .accessibilityElement(children: .contain)
        .accessibilityHint(item.kind.unlockSummary)
        .accessibilityIdentifier("calibration.item.\(item.kind.id)")

        // Outside the `!isReady` branch: an imported R scale that disagrees
        // with the filename is *ready*, and exactly the case worth a warning.
        if item.kind == .rScale, let conflict = rScaleFilenameConflict {
            Label(conflict, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("calibration.rScale.filenameConflict")
        }
        if !item.status.isReady {
            readinessAction(for: item.kind)
        }
    }

    @ViewBuilder
    private func readinessAction(for kind: CalibrationReadinessKind) -> some View {
        switch kind {
        case .originProbe:
            Button("Measure Origin & Probe") {
                Task { await appState.calibrateOrigin() }
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.originProbe")
        case .ellipse:
            Button("Fit Detector Ellipse") {
                Task { await appState.calibrateEllipse() }
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.ellipse")
        case .rotation:
            Button("Measure R–Q Rotation") {
                Task { await appState.calibrateRotation() }
            }
            .disabled(appState.isBusy)
            .accessibilityIdentifier("calibration.action.rotation")
        case .qScale:
            if appState.hasCurrentBraggVectors, let model = appState.resolvedACOMModel {
                Button("Calibrate from Selected Material") {
                    Task { await appState.calibrateQFromCrystal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isBusy)
                .accessibilityIdentifier("calibration.action.qCrystal")
                .help("Selected ACOM phase model: \(model.displayName)")
                manualScaleRows(
                    value: appState.manualQPixelSize,
                    units: appState.manualQPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                    identifier: "calibration.action.qManual",
                    help: "Or enter the reciprocal pixel size by hand.",
                    onChange: appState.setManualQPixelSize,
                    onUnitChange: appState.setManualQPixelUnits
                )
            } else {
                // Why the crystal route is unavailable is guidance about a
                // path you cannot take yet: on hover and in the hint.
                manualScaleRows(
                    value: appState.manualQPixelSize,
                    units: appState.manualQPixelUnits,
                    unitOptions: CalibrationUnitConversion.editableReciprocalUnits,
                    identifier: "calibration.action.qManual",
                    help: qScaleUnavailableReason,
                    onChange: appState.setManualQPixelSize,
                    onUnitChange: appState.setManualQPixelUnits
                )
            }
        case .rScale:
            // R scale is the one calibration with no measurement path in the
            // app; the field is the only control offered, and the sentence is
            // on hover.
            manualScaleRows(
                value: appState.manualRPixelSize,
                units: appState.manualRPixelUnits,
                unitOptions: CalibrationUnitConversion.editableRealUnits,
                identifier: "calibration.action.rManual",
                help: "R pixel scale cannot be measured from the data — enter it from the acquisition parameters.",
                onChange: appState.setManualRPixelSize,
                onUnitChange: appState.setManualRPixelUnits
            )
        }
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
    /// The parser itself is `UI2PrepareSettings`'s pure static, deliberately
    /// not a second copy: the regex is pinned by a test, and two spellings of
    /// it in UI2 is exactly the drift that produces a warning on one surface
    /// and silence on the other.
    private var rScaleFilenameConflict: String? {
        guard let path = appState.descriptor?.filePath,
              let size = appState.calibrationSession.calibration.rPixelSize,
              let inUse = CalibrationUnitConversion.realAngstromPerPixel(
                  value: size, units: appState.calibrationSession.calibration.rPixelUnits
              ),
              let token = UI2PrepareSettings.scanStepAngstromPerPixel(inFilename: path)
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

    /// The manual scale as two rows — the value, then its unit per pixel —
    /// because value, unit menu and suffix together do not fit the column's
    /// minimum width.
    @ViewBuilder
    private func manualScaleRows(
        value: Double?, units: String, unitOptions: [String], identifier: String,
        help: String,
        onChange: @escaping (Double) -> Void,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        LabeledContent("Manual") {
            UI2NumericField(
                "Manual scale",
                value: Binding(get: { value ?? 0 }, set: onChange),
                format: .number.precision(.fractionLength(0...6))
            )
            .accessibilityIdentifier(identifier)
        }
        .help(help)
        .accessibilityHint(help)
        Picker("Unit per pixel", selection: Binding(get: { units }, set: onUnitChange)) {
            ForEach(unitOptions, id: \.self) { unit in
                Text(unit).tag(unit)
            }
        }
        .accessibilityIdentifier(identifier + ".units")
    }
}
