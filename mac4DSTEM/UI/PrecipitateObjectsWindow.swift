//
//  PrecipitateObjectsWindow.swift
//  Role: the object table — every precipitate object of one phase map, in a
//        window the reader can sort, filter, keep open beside the map, and
//        export. It shows a SNAPSHOT (`PrecipitateObjectReport`, a value): a
//        new run or a changed minimum size is a new table, opened again from
//        the Precipitates section, and the subtitle says when this one was
//        made.
//
//  The visible rows are cached state, recomputed when the phase filter, the
//  counted-only switch or the sort changes, not on every redraw or row
//  selection (UI audit 2026-10-13/14). Numeric columns are right-aligned,
//  header and cells alike. Edit > Copy copies the selected rows as
//  tab-separated text (`.copyable`, SwiftUI's own; a context-menu Copy would
//  need NSPasteboard, which SwiftUI's copy command makes unnecessary). A save
//  that fails is said in an alert, not dropped.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct PrecipitateObjectsWindow: View {
    let report: PrecipitateObjectReport
    /// The relay to the dataset windows' scan panes: a selected row outlines
    /// its object on the map. Optional so the window also runs without it.
    @Environment(PrecipitateTableSelection.self) private var relay: PrecipitateTableSelection?

    @State private var sortOrder: [KeyPathComparator<PrecipitateObjectReport.Row>]
    @State private var phaseFilter: Int32 = -1          // −1 = every phase
    @State private var countedOnly = false
    @State private var selection = Set<PrecipitateObjectReport.Row.ID>()
    @State private var exportDocument: CSVTextDocument?
    @State private var exportFailure: String?
    /// The rows the table shows, for the filter and sort above; see `refreshRows()`.
    @State private var rows: [PrecipitateObjectReport.Row]

    init(report: PrecipitateObjectReport) {
        self.report = report
        let order = [KeyPathComparator(\PrecipitateObjectReport.Row.id)]
        _sortOrder = State(initialValue: order)
        _rows = State(initialValue: report.visibleRows(phase: nil, countedOnly: false, sortedUsing: order))
    }

    private func refreshRows() {
        rows = report.visibleRows(phase: phaseFilter < 0 ? nil : phaseFilter, countedOnly: countedOnly,
                                  sortedUsing: sortOrder)
    }

    /// What Edit > Copy puts on the clipboard: the selected rows in table order, nothing when none is selected
    /// (the command is then disabled).
    private var copyPayload: [String] {
        let chosen = rows.filter { selection.contains($0.id) }
        return chosen.isEmpty ? [] : [report.tabSeparatedText(of: chosen)]
    }

    private var unit: String { report.pixelUnit ?? "px" }

    var body: some View {
        VStack(spacing: 0) {
            summary
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            table
            let notes = [report.compositionUnavailable.map { "Composition: " + $0 }, report.strainUnavailable.map { "Strain: " + $0 }].compactMap { $0 }
            if !notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(notes, id: \.self) { Text($0) }
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .accessibilityIdentifier("precipitates.objects.joinNotes")
            }
        }
        // Size: the scene's `.defaultSize` (App/mac4DSTEMApp.swift). The
        // summary grid keeps its one-line width (`fixedSize` below), which the
        // window takes as its minimum: a 300 pt frame wrapped "Median length"
        // letter by letter (2026-09-29 drive).
        .navigationTitle("Precipitate Objects")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Picker("Phase", selection: $phaseFilter) {
                    Text("All Phases").tag(Int32(-1))
                    ForEach(report.summaries) { summary in
                        Text(summary.phaseName).tag(summary.label)
                    }
                }
                .help("Show one phase's objects")
            }
            ToolbarItem {
                Toggle(isOn: $countedOnly) {
                    Label("Counted Only", systemImage: "checkmark.circle")
                }
                .help("Hide objects on the scan edge and under the minimum size")
            }
            ToolbarItem {
                Button("Export CSV…", systemImage: "square.and.arrow.up") {
                    exportDocument = CSVTextDocument(text: report.csv())
                }
                .help("Every object and the per-phase summary as CSV, with provenance")
            }
        }
        // A selected row outlines its object on the map. Only rows the reader
        // can see count, and closing the table takes its highlight with it.
        .onChange(of: selection) { pushSelection() }
        .onChange(of: phaseFilter) { refreshRows(); pushSelection() }
        .onChange(of: countedOnly) { refreshRows(); pushSelection() }
        .onChange(of: sortOrder) { refreshRows() }
        .onDisappear { relay?.clear(ifOwnedBy: report.sourceID) }
        .copyable(copyPayload)
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil },
                                 set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: report.csvFileName
        ) { result in
            exportFailure = CSVExportOutcome.failureMessage(result)
        }
        .alert("Could Not Export the Table", item: $exportFailure) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func pushSelection() {
        relay?.select(selection.intersection(rows.map(\.id)), of: report.sourceID)
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Unvalidated — objects from a phase map that has not been scored "
                     + "against a ground truth in this app.")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            .font(.callout)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    Text("Phase")
                    Text("Counted").gridColumnAlignment(.trailing)
                    Text("Edge").gridColumnAlignment(.trailing)
                    Text("Small").gridColumnAlignment(.trailing)
                    Text("Median length").gridColumnAlignment(.trailing)
                    Text("Mean width").gridColumnAlignment(.trailing)
                    Text("Area fraction").gridColumnAlignment(.trailing)
                    Text("Density").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(report.summaries) { s in
                    GridRow {
                        HStack(spacing: 6) {
                            PhaseSwatch(rgb: report.color(of: s.label))
                            Text(s.phaseName)
                        }
                        Text("\(s.countedObjects)")
                        Text("\(s.edgeExcluded)")
                        Text("\(s.belowMinimumExcluded)")
                        Text(length(s.medianLengthPx))
                        Text(length(s.meanWidthPx))
                        Text(s.areaFraction.map { $0.formatted(.percent.precision(.fractionLength(2))) } ?? "—")
                        Text(density(s.arealDensity))
                    }
                    .monospacedDigit()
                }
            }
            // One line per phase: the report is a snapshot, so this width never
            // changes while the window is open, and it is the window's minimum.
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: Table

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("ID", value: \.id) { Text("\($0.id)").monospacedDigit() }
                .width(min: 36, ideal: 44)
                .alignment(.numeric)
            TableColumn("Phase", value: \.phaseName) { row in
                HStack(spacing: 6) {
                    PhaseSwatch(rgb: report.color(of: row.label))
                    Text(row.phaseName)
                }
            }
            // Wide enough for "thetaprime_thronsen2024 [1 0 0]": two copies of
            // one structure differ only in that suffix (seen truncated,
            // 2026-09-28 drive).
            .width(min: 160, ideal: 250)
            TableColumn("Area (\(areaUnit))", value: \.areaPx) { row in
                Text(row.area.map { format($0) } ?? row.areaPx.formatted()).monospacedDigit()
            }
            .width(min: 56, ideal: 80)
            .alignment(.numeric)
            TableColumn("Length (\(unit))", value: \.lengthPx) { row in
                Text(format(row.length ?? row.lengthPx)).monospacedDigit()
            }
            .width(min: 56, ideal: 80)
            .alignment(.numeric)
            TableColumn("Width (\(unit))", value: \.widthPx) { row in
                Text(format(row.width ?? row.widthPx)).monospacedDigit()
            }
            .width(min: 56, ideal: 80)
            .alignment(.numeric)
            TableColumn("Aspect", value: \.aspectRatio) { row in
                Text(format(row.aspectRatio)).monospacedDigit()
            }
            .width(min: 48, ideal: 64)
            .alignment(.numeric)
            Group {
                TableColumn("Axis major (\(unit))", value: \PrecipitateObjectReport.Row.axisMajorSortKey) { row in
                    Text(row.axisMajorLength.map(format) ?? row.axisMajorLengthPx.map(format) ?? "").monospacedDigit()
                }
                .width(min: 72, ideal: 90)
                .alignment(.numeric)
                TableColumn("Perimeter (\(unit))", value: \PrecipitateObjectReport.Row.perimeterSortKey) { row in
                    Text(row.perimeter.map(format) ?? row.perimeterPx.map(format) ?? "").monospacedDigit()
                }
                .width(min: 72, ideal: 90)
                .alignment(.numeric)
                TableColumn("Equiv. diameter (\(unit))", value: \PrecipitateObjectReport.Row.equivalentDiameterSortKey) { row in
                    Text(row.equivalentDiameter.map(format) ?? row.equivalentDiameterPx.map(format) ?? "").monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                .alignment(.numeric)
                TableColumn("Solidity", value: \PrecipitateObjectReport.Row.soliditySortKey) { row in
                    Text(row.solidity.map(format) ?? "").monospacedDigit()
                }
                .width(min: 56, ideal: 70)
                .alignment(.numeric)
            }
            if report.variantGroups != nil {
                TableColumn("Direction", value: \PrecipitateObjectReport.Row.directionSortKey) { row in
                    Text(row.directionText).monospacedDigit().help(row.variantNote ?? "The matrix cube axis the needle lies along.")
                }
                .width(min: 64, ideal: 72)
                TableColumn("Variant", value: \PrecipitateObjectReport.Row.variantSortKey) { row in
                    Text(row.variantText).monospacedDigit().help(row.variantNote ?? "One of the twelve orientation-relationship variants.")
                }
                .width(min: 56, ideal: 64)
                .alignment(.numeric)
            }
            Group {
                TableColumn("Orientation", value: \PrecipitateObjectReport.Row.orientationDegrees) { row in
                    Text(row.orientationDegrees.formatted(.number.precision(.fractionLength(1))) + "°")
                        .monospacedDigit()
                }
                .width(min: 70, ideal: 80)
                .alignment(.numeric)
                TableColumn("Position", value: \PrecipitateObjectReport.Row.centroidY) { row in
                    Text("\(Int(row.centroidX.rounded())), \(Int(row.centroidY.rounded()))").monospacedDigit()
                }
                .width(min: 64, ideal: 76)
                .alignment(.numeric)
                TableColumn("Composition (mean of pixels)") { row in
                    Text(row.compositionSummary).monospacedDigit()
                        .foregroundStyle(row.composition == nil ? .secondary : .primary)
                        .help(report.compositionUnavailable ?? "The mean of the per-pixel at% maps under the object. Not the pooled fit's value, no sigma.")
                }
                .width(min: 140, ideal: 190)
                TableColumn("Strain (mean of pixels)") { row in
                    Text(row.strainSummary).monospacedDigit()
                        .foregroundStyle(row.strain == nil ? .secondary : .primary)
                        .help(report.strainUnavailable ?? "The mean strain under the object, in rows (rr) and columns (cc). Not a fit error.")
                }
                .width(min: 170, ideal: 230)
            }
            TableColumn("Counted", value: \.countedSortKey) { row in
                if let why = row.exclusion {
                    Text("no — \(why)").foregroundStyle(.secondary)
                } else {
                    Label("yes", systemImage: "checkmark").labelStyle(.titleAndIcon)
                }
            }
            .width(min: 110, ideal: 120)
        }
    }

    // MARK: Formatting

    private var areaUnit: String { report.pixelUnit.map { "\($0)²" } ?? "px" }

    private var subtitle: String {
        let counted = report.summaries.reduce(0) { $0 + $1.countedObjects }
        var text = "\(counted) counted of \(report.rows.count)"
        if let stamp = report.provenance.first(where: { $0.first == "created" })?.last,
           let date = try? Date(stamp, strategy: .iso8601) {
            text += " · " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return text
    }

    private func length(_ px: Double?) -> String {
        guard let px else { return "—" }
        if let size = report.pixelSize, let unit = report.pixelUnit {
            return "\(format(px * size)) \(unit)"
        }
        return "\(format(px)) px"
    }

    private func density(_ value: Double?) -> String {
        guard let value, let unit = report.pixelUnit else { return "no scan scale" }
        return PrecipitateFormat.density(value, unit: unit)
    }

    private func format(_ value: Double) -> String { PrecipitateFormat.number(value) }
}

/// What a finished CSV save says when it failed. Cancelling the panel is not a failure.
enum CSVExportOutcome {
    static func failureMessage(_ result: Result<URL, Error>) -> String? {
        guard case .failure(let error) = result else { return nil }
        if let cocoa = error as? CocoaError, cocoa.code == .userCancelled { return nil }
        return error.localizedDescription
    }
}

extension PrecipitateObjectReport.Row {
    /// Counted rows first when sorting ascending.
    var countedSortKey: Int { isCounted ? 0 : 1 }
}
