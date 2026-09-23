//
//  PrecipitateObjectsSection.swift
//  Role: the phase-mapping room's "Precipitates" section — per-phase object
//        counts, lengths and densities from the phase map, the reader's
//        minimum object size, and the three ways out: draw the objects,
//        open the object table, export CSV. Layout is the inspector kit's
//        (`InspectorRows.swift`); numbers come from
//        `AppState.precipitateObjectReport`, never computed here.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

struct PrecipitateObjectsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var exportDocument: CSVTextDocument?

    var body: some View {
        let classification = appState.precipitateClassification
        InspectorSection("Precipitates") {
            if let report = appState.precipitateObjectReport {
                content(report, classification: classification)
            } else if classification.isComputing {
                InspectorRow("Objects") {
                    ProgressView().controlSize(.small).labelsHidden()
                }
            } else {
                InspectorNote("Map phases to find precipitate objects.")
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil },
                                 set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: defaultFilename
        ) { result in
            switch result {
            case .success(let url):
                appState.statusText = "Exported precipitate objects → \(url.lastPathComponent)"
            case .failure(let error):
                appState.statusText = "Could not export precipitate objects: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func content(_ report: PrecipitateObjectReport,
                         classification: PrecipitateClassificationProduct) -> some View {
        @Bindable var classification = classification

        Label {
            Text("From the unvalidated phase map above.")
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        .font(.caption)

        ForEach(report.summaries) { summary in
            InspectorRow(summary.phaseName) {
                VStack(alignment: .trailing, spacing: 1) {
                    // The phase map's own colour: the only thing that tells two
                    // phases apart when their names coincide.
                    HStack(spacing: 6) {
                        PhaseSwatch(rgb: report.color(of: summary.label))
                        Text("\(summary.countedObjects) object\(summary.countedObjects == 1 ? "" : "s")")
                            .monospacedDigit()
                    }
                    // One fact per line: a long phase name leaves the value
                    // column narrow, and a joined line wrapped mid-unit.
                    ForEach(detailLines(summary, report: report), id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .labelsHidden()
            }
            .help(helpText(summary, report: report))
        }

        if let excluded = exclusionNote(report) {
            InspectorNote(excluded)
        }

        InspectorRow("Minimum size") {
            NumericField("Minimum size", value: $classification.minimumObjectAreaPx,
                         format: .number, unit: "px")
                .labelsHidden()
        }
        .help("Objects smaller than this many scan pixels stay in the table and on the "
              + "map (dimmed) but are not counted. 1 keeps every object. A property of "
              + "this dataset for you to judge — the published Thronsen truth used cuts of "
              + "4, 782 and 10 px on its own data.")
        .onChange(of: classification.minimumObjectAreaPx) {
            appState.refreshPrecipitateObjectsProductIfShown()
        }

        InspectorActionRow {
            InspectorAdaptiveButton("Show Objects", systemImage: "circle.hexagongrid",
                                    help: "Draw the objects over the scan: counted objects in their "
                                        + "phase colour, edge and small objects dimmed.") {
                appState.publishPrecipitateObjectsProduct()
            }
            .accessibilityIdentifier("precipitates.showObjects")
            InspectorAdaptiveButton("Object Table", systemImage: "tablecells",
                                    help: "Every object with its size, shape and orientation, "
                                        + "in a window you can sort and keep open.") {
                openWindow(value: report)
            }
            .accessibilityIdentifier("precipitates.table")
            InspectorAdaptiveButton("Export CSV…", systemImage: "square.and.arrow.up",
                                    help: "Every object and the per-phase summary as CSV, with "
                                        + "the settings and provenance in its header.") {
                exportDocument = CSVTextDocument(text: report.csv())
            }
            .accessibilityIdentifier("precipitates.exportCSV")
        }
        .disabled(appState.isBusy)
    }

    /// ["median 23,1 nm", "12,3 /µm²"] (locale digits), or pixels and "no scan scale".
    private func detailLines(_ summary: PrecipitateObjectReport.ClassSummary,
                             report: PrecipitateObjectReport) -> [String] {
        var parts: [String] = []
        if let median = summary.medianLengthPx {
            if let size = report.pixelSize, let unit = report.pixelUnit {
                parts.append("median \(PrecipitateFormat.number(median * size)) \(unit)")
            } else {
                parts.append("median \(PrecipitateFormat.number(median)) px")
            }
        }
        if let areal = summary.arealDensity, let unit = report.pixelUnit {
            parts.append(PrecipitateFormat.density(areal, unit: unit))
        } else if !report.hasPhysicalScale {
            parts.append("no scan scale")
        }
        return parts.isEmpty ? ["—"] : parts
    }

    private func helpText(_ summary: PrecipitateObjectReport.ClassSummary,
                          report: PrecipitateObjectReport) -> String {
        var text = "\(summary.countedObjects) counted of \(summary.totalObjects) objects "
            + "(8-connected). \(summary.edgeExcluded) touch the scan edge, "
            + "\(summary.belowMinimumExcluded) are under \(report.minimumAreaPx) px."
        if let fraction = summary.areaFraction {
            text += " Area fraction \(fraction.formatted(.percent.precision(.fractionLength(2))))."
        }
        return text + " Density is over the analysed area: \(report.analysedAreaRule)"
    }

    private func exclusionNote(_ report: PrecipitateObjectReport) -> String? {
        let edge = report.summaries.reduce(0) { $0 + $1.edgeExcluded }
        let small = report.summaries.reduce(0) { $0 + $1.belowMinimumExcluded }
        var parts: [String] = []
        if edge > 0 { parts.append("\(edge) on the scan edge") }
        if small > 0 { parts.append("\(small) under \(report.minimumAreaPx) px") }
        return parts.isEmpty ? nil : "Not counted: " + parts.joined(separator: ", ") + "."
    }

    private var defaultFilename: String {
        let base = appState.descriptor.map { ($0.fileName as NSString).deletingPathExtension }
            ?? "precipitates"
        return "\(base)-precipitate-objects.csv"
    }
}

/// A phase's map colour, drawn as the Result legend draws it.
struct PhaseSwatch: View {
    let rgb: PhaseMapPresentation.RGB

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255))
            .frame(width: LayoutPolicy.legendSwatch, height: LayoutPolicy.legendSwatch)
            .accessibilityHidden(true)
    }
}

/// Numbers as the reader's locale writes them (the inspector's fields do),
/// three significant digits, never an exponent. The CSV keeps its own
/// locale-independent format.
enum PrecipitateFormat {
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.significantDigits(3)))
    }

    /// µm² reads better than nm² for a precipitate density; converted only
    /// for nm, the unit the loader normalizes to.
    static func density(_ perUnit2: Double, unit: String) -> String {
        unit.lowercased() == "nm"
            ? "\(number(perUnit2 * 1e6)) /µm²"
            : "\(number(perUnit2)) /\(unit)²"
    }
}

/// A CSV the save panel writes. Plain UTF-8 text; the report builds it.
struct CSVTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
