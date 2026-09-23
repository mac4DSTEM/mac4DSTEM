//
//  PrecipitateObjectsWindow.swift
//  Role: the object table — every precipitate object of one phase map, in a
//        window the reader can sort, filter, keep open beside the map, and
//        export. It shows a SNAPSHOT (`PrecipitateObjectReport`, a value): a
//        new run or a changed minimum size is a new table, opened again from
//        the Precipitates section, and the subtitle says when this one was
//        made.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct PrecipitateObjectsWindow: View {
    let report: PrecipitateObjectReport

    @State private var sortOrder = [KeyPathComparator(\PrecipitateObjectReport.Row.id)]
    @State private var phaseFilter: Int32 = -1          // −1 = every phase
    @State private var countedOnly = false
    @State private var selection = Set<PrecipitateObjectReport.Row.ID>()
    @State private var exportDocument: CSVTextDocument?

    private var rows: [PrecipitateObjectReport.Row] {
        report.rows
            .filter { phaseFilter < 0 || $0.label == phaseFilter }
            .filter { !countedOnly || $0.isCounted }
            .sorted(using: sortOrder)
    }

    private var unit: String { report.pixelUnit ?? "px" }

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            table
        }
        // Size: the scene's `.defaultSize` (App/mac4DSTEMApp.swift); the
        // columns' own minimum widths keep the table readable when narrowed.
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
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil },
                                 set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "precipitate-objects.csv"
        ) { _ in }
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
        }
    }

    // MARK: Table

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("ID", value: \.id) { Text("\($0.id)").monospacedDigit() }
                .width(min: 40, ideal: 50)
            TableColumn("Phase", value: \.phaseName) { row in
                HStack(spacing: 6) {
                    PhaseSwatch(rgb: report.color(of: row.label))
                    Text(row.phaseName)
                }
            }
            .width(min: 120, ideal: 190)
            TableColumn("Area (\(areaUnit))", value: \.areaPx) { row in
                Text(row.area.map { format($0) } ?? row.areaPx.formatted()).monospacedDigit()
            }
            TableColumn("Length (\(unit))", value: \.lengthPx) { row in
                Text(format(row.length ?? row.lengthPx)).monospacedDigit()
            }
            TableColumn("Width (\(unit))", value: \.widthPx) { row in
                Text(format(row.width ?? row.widthPx)).monospacedDigit()
            }
            TableColumn("Aspect", value: \.aspectRatio) { row in
                Text(format(row.aspectRatio)).monospacedDigit()
            }
            TableColumn("Orientation", value: \.orientationDegrees) { row in
                Text(row.orientationDegrees.formatted(.number.precision(.fractionLength(1))) + "°")
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            TableColumn("Position", value: \.centroidY) { row in
                Text("\(Int(row.centroidX.rounded())), \(Int(row.centroidY.rounded()))").monospacedDigit()
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

extension PrecipitateObjectReport.Row {
    /// Counted rows first when sorting ascending.
    var countedSortKey: Int { isCounted ? 0 : 1 }
}
