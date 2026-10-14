//
//  PrecipitateObjectTableTests.swift
//  UI audit 2026-10-14, D and E: the object table's rows are computed once per filter/sort change
//  (`PrecipitateObjectReport.visibleRows`), Copy hands over the CSV's own columns and numbers, the Save panel's
//  name follows the dataset, and a failed write is said (`CSVExportOutcome`).
//
//  Mutations these were broken against (each must turn a test red):
//   1. `visibleRows` ignores the phase                                           -> testVisibleRowsFilterAndSort
//   2. `visibleRows` ignores counted-only                                        -> testVisibleRowsFilterAndSort
//   3. `visibleRows` does not sort                                               -> testVisibleRowsFilterAndSort
//   4. `fields(of:)` formats a number differently from the CSV's `number`        -> testCopyCarriesTheCSVColumnsAndNumbers
//   5. `csvFileName` returns the fixed name                                      -> testTheSaveNameFollowsTheDataset
//   6. `failureMessage` returns nil for every failure                            -> testAFailedSaveIsSaidAndACancelIsNot
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PrecipitateObjectTableTests: XCTestCase {

    /// The 8 × 6 fixture of `PrecipitateObjectReportTests`: phase 1 has A (3 px, interior), B (1 px, interior) and
    /// C (2 px on the right edge).
    private func report(minimum: Int = 1, pixelSize: Double? = nil, unit: String? = nil,
                        provenance: [(String, String)] = [], names: [String] = ["Al", "θ′"]) -> PrecipitateObjectReport {
        var labels = [Int32](repeating: 0, count: 8 * 6)
        for x in 2...4 { labels[2 * 8 + x] = 1 }
        labels[4 * 8 + 5] = 1
        labels[1 * 8 + 7] = 1; labels[2 * 8 + 7] = 1
        labels[5 * 8 + 0] = -1
        let objects = PrecipitateSegmentation.classObjects(
            labels: labels, width: 8, height: 6,
            roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [-1]),
            pixelSize: nil, pixelUnit: nil)
        return PrecipitateObjectReport.make(
            objects: objects, phaseNames: names, matrixPhaseIndex: 0,
            pixelSize: pixelSize, pixelUnit: unit, minimumAreaPx: minimum, provenance: provenance)
    }

    private let byID = [KeyPathComparator(\PrecipitateObjectReport.Row.id)]

    func testVisibleRowsFilterAndSort() {
        let r = report(minimum: 2)   // A counted, B small, C on the edge
        XCTAssertEqual(r.rows.count, 3, "precondition: three objects")
        let label = r.rows[0].label

        XCTAssertEqual(r.visibleRows(phase: nil, countedOnly: false, sortedUsing: byID).count, 3)
        XCTAssertEqual(r.visibleRows(phase: label, countedOnly: false, sortedUsing: byID).count, 3)
        XCTAssertTrue(r.visibleRows(phase: label + 7, countedOnly: false, sortedUsing: byID).isEmpty,
                      "another phase shows none of these objects")
        XCTAssertEqual(r.visibleRows(phase: nil, countedOnly: true, sortedUsing: byID).map(\.areaPx), [3],
                       "counted only keeps A")

        let largestFirst = r.visibleRows(phase: nil, countedOnly: false,
                                         sortedUsing: [KeyPathComparator(\PrecipitateObjectReport.Row.areaPx, order: .reverse)])
        XCTAssertEqual(largestFirst.map(\.areaPx), [3, 2, 1])
        let smallestFirst = r.visibleRows(phase: nil, countedOnly: false,
                                          sortedUsing: [KeyPathComparator(\PrecipitateObjectReport.Row.areaPx)])
        XCTAssertEqual(smallestFirst.map(\.areaPx), [1, 2, 3])
    }

    /// Splits the CSV into its header line and rows, dropping the `#` comment lines.
    private func csvTable(_ r: PrecipitateObjectReport) -> [[String]] {
        r.csv().split(separator: "\n").filter { !$0.hasPrefix("#") }.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }

    func testCopyCarriesTheCSVColumnsAndNumbers() {
        let r = report(minimum: 2, pixelSize: 0.25, unit: "nm")
        let csv = csvTable(r)
        let copied = r.tabSeparatedText(of: r.rows).split(separator: "\n")
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(copied, csv, "Copy is the CSV's header and rows, tab-separated: same columns, same numbers")
        XCTAssertEqual(csv.count, 1 + r.rows.count)
        XCTAssertTrue(csv[0].contains("area_nm2"), "the physical columns carry the unit")

        let one = r.tabSeparatedText(of: [r.rows[1]]).split(separator: "\n")
        XCTAssertEqual(one.count, 2, "the header and the one selected row")
        XCTAssertEqual(String(one[1]), csv[2].joined(separator: "\t"))
    }

    func testAPhaseNameWithATabOrALineBreakCannotShiftTheColumns() {
        let columns = csvTable(report())[0].count   // the header of a report with ordinary names (a quoted newline would split the CSV's own lines)
        let r = report(names: ["Al", "θ′\t[1 0 0]\nstacked"])
        let lines = r.tabSeparatedText(of: r.rows).split(separator: "\n")
        XCTAssertEqual(lines.count, 1 + r.rows.count, "a line break in a name must not add a line")
        for line in lines {
            XCTAssertEqual(line.split(separator: "\t", omittingEmptySubsequences: false).count, columns)
        }
    }

    func testTheSaveNameFollowsTheDataset() {
        XCTAssertEqual(report(provenance: [("product", "x"), ("source_file", "Thronsen A.h5")]).csvFileName,
                       "Thronsen A-precipitate-objects.csv")
        XCTAssertEqual(report(provenance: [("source_file", "a/b:c.emd")]).csvFileName,
                       "a-b-c-precipitate-objects.csv", "a path separator or colon cannot split the name")
        XCTAssertEqual(report().csvFileName, "precipitate-objects.csv", "no dataset named, the plain name")
        XCTAssertEqual(report(provenance: [("source_file", "")]).csvFileName, "precipitate-objects.csv")
    }

    func testAFailedSaveIsSaidAndACancelIsNot() {
        let url = URL(fileURLWithPath: "/tmp/x.csv")
        XCTAssertNil(CSVExportOutcome.failureMessage(.success(url)))
        XCTAssertNil(CSVExportOutcome.failureMessage(.failure(CocoaError(.userCancelled))))
        let refused = CocoaError(.fileWriteNoPermission)
        XCTAssertEqual(CSVExportOutcome.failureMessage(.failure(refused)), refused.localizedDescription)
        XCTAssertFalse(refused.localizedDescription.isEmpty)
    }
}
