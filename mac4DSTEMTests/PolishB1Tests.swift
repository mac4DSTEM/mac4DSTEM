//
//  PolishB1Tests.swift
//  Polish lane B1 (2026-10-02): the map panes' categorical legends and the phase-mapping inspector's
//  number format. Each test names the mutation it catches.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PolishB1Tests: XCTestCase {
    private let german = Locale(identifier: "de_DE")

    private func shown(_ printf: String, _ value: Double) -> String {
        DecimalEntryFormat(PhaseMappingSections.displayFormat(printf), locale: german).format(value)
    }

    /// Mutation: `displayFormat` ignores the printf precision (the old hard-coded 3 decimals) — "1,600"
    /// would read as sixteen hundred to an English eye.
    func testGermanDisplayKeepsTheCallersPrecision() {
        XCTAssertEqual(shown("%.2f", 1.6), "1,60")
        XCTAssertEqual(shown("%.1f", 2.0), "2,0")
        XCTAssertEqual(shown("%.3f", 0.5), "0,500")
    }

    /// Mutation: the format's maximum drops to the minimum (`fractionLength(p...p)`) — the field commits what
    /// it shows on focus loss, so a stored 0.0275 would be re-stored as 0.028.
    func testDisplayNeverRoundsBelowTheStoredDigits() throws {
        for value in [0.0275, 1.234, 0.123456] {
            let text = shown("%.2f", value)
            let entry = DecimalEntryFormat(PhaseMappingSections.displayFormat("%.2f"), locale: german)
            XCTAssertEqual(try entry.parseStrategy.parse(text), value, accuracy: 1e-12, "\(value) shown as \(text)")
        }
    }

    private func map() -> PhaseMap {
        var map = PhaseMap(width: 4, height: 1, matrixEntryIndex: 0,
                           phaseNames: ["Al", "beta 0 1 0", "beta 0 0 1"], matrixPhaseIndex: 0)
        map.results[0].verdict = .matrix; map.results[0].phaseIndex = 0
        map.results[1].verdict = .indexed; map.results[1].phaseIndex = 1
        map.results[2].verdict = .notIndexed
        map.results[3].verdict = .noData
        return map
    }

    /// Mutation: the rows drop the "Not indexed" entry (the hatched swatch the map paints) or keep the
    /// "of which challenged" subset row.
    func testPhaseLegendRowsNameEveryPhaseAndTheHatchedUnmatched() {
        let rows = CategoricalLegendRows.phaseMap(map())
        XCTAssertEqual(rows.map(\.label), ["Al (matrix)", "beta 0 1 0", "beta 0 0 1", "Not indexed", "No peaks"])
        XCTAssertEqual(Set(rows.map(\.label)).count, rows.count, "no two rows read the same")
        XCTAssertNotNil(rows.first { $0.label == "Not indexed" }?.stripe, "the hatched swatch")
        XCTAssertNil(rows[0].stripe)
    }

    /// Mutation: group g paints with the colormap's start for every group, or the labels are 0-based.
    func testGroupLegendHasOneDistinctSwatchPerGroupInTheMapsColours() {
        let rows = CategoricalLegendRows.groups(count: 4, colormap: .viridis, low: 0, high: 3, gamma: 1)
        XCTAssertEqual(rows.map(\.label), ["1", "2", "3", "4"])
        let lut = Colormaps.lutRGBA(.viridis, count: 256)
        XCTAssertEqual(rows[0].color.r, lut[0]); XCTAssertEqual(rows[0].color.b, lut[2])
        XCTAssertEqual(rows[3].color.r, lut[255 * 4]); XCTAssertEqual(rows[3].color.g, lut[255 * 4 + 1])
        XCTAssertEqual(Set(rows.map { "\($0.color.r),\($0.color.g),\($0.color.b)" }).count, 4)
        XCTAssertTrue(CategoricalLegendRows.groups(count: 0, colormap: .viridis, low: 0, high: 0, gamma: 1).isEmpty)
    }
}
