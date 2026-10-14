import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
import SpectroCore
@testable import mac4DSTEM

/// Lane S (UI audit 2026-10-14, Spectroscopy rows): every test names the mutation that turns it red.
@MainActor
final class SpectroscopyLaneSTests: XCTestCase {

    // MARK: Row 1 - caveats are read, not hovered

    private func outcome(reasons: [String] = [], notes: [String] = [], suspects: [AutoIDSuspect] = []) -> AutoIDOutcome {
        AutoIDOutcome(region: "r", suggestions: reasons.enumerated().map { ElementSuggestion(z: 29 + $0.offset, reason: $0.element) },
                      suspects: suspects, notTested: [], notes: notes)
    }

    /// The Details disclosure is drawn exactly when the proposer said something, and holds every line the hover used to hold.
    /// Mutation: `showsDetails` returns false, or `noteLines` drops `o.notes` - red.
    func testAutoIDDetailsHoldEveryReasonAndNote() {
        let o = outcome(reasons: ["Cu: net 900 counts"], notes: ["look-elsewhere: 3 of 40 tested"],
                        suspects: [AutoIDSuspect(label: "Al+Al sum?", energy: 3.0, question: "sum peak or Ar", stats: "net 8 counts")])
        XCTAssertTrue(ElementsSection.showsDetails(o))
        let lines = ElementsSection.noteLines(o, o.suggestions)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Cu: ") && lines[0].contains("net 900 counts"))
        XCTAssertTrue(lines.contains("look-elsewhere: 3 of 40 tested"))
        XCTAssertTrue(lines.contains { $0.contains("Al+Al sum?") && $0.contains("sum peak or Ar") })
        XCTAssertFalse(ElementsSection.showsDetails(outcome()), "nothing said: no disclosure")
    }

    /// The Found row's tip is the definition and the help only: the reasons it used to carry are now on screen.
    /// Mutation: `foundHover` appends `notes(...)` again - red.
    func testFoundHoverNoLongerCarriesTheReasons() {
        let o = outcome(reasons: ["Cu: a very particular reason"], notes: ["a very particular note"])
        let tip = ElementsSection.foundHover(o, locale: Locale(identifier: "en_US"))
        XCTAssertFalse(tip.contains("a very particular"))
        XCTAssertTrue(tip.contains(ElementsSection.foundHelp) && tip.contains("Currie"))
    }

    /// The row sentence under a results row: the failure, else the conflict note, else nothing; the icon's tip is a short kind.
    /// Mutation: `rowNote` prefers the conflict over the failure, or `rowNoteKind` returns the sentence - red.
    func testResultRowNotePrefersTheFailureAndTheIconTipIsShort() {
        var row = ResultRow(z: 12, netCounts: 27, netSigma: 10, kFreeRatio: 0.06, kFreeSigma: 0.02, atPercent: 0, atSigma: 0,
                            wtPercent: 0, wtSigma: 0, sigmaTerms: "")
        XCTAssertNil(ResultsSection.rowNote(row))
        row.conflictNote = "background overlaps Si Kα"
        XCTAssertEqual(ResultsSection.rowNote(row), "background overlaps Si Kα")
        row.failure = "no line on the axis"
        XCTAssertEqual(ResultsSection.rowNote(row), "no line on the axis")
        XCTAssertEqual(ResultsSection.rowNoteKind(row), "Fit failed")
        row.failure = nil
        XCTAssertEqual(ResultsSection.rowNoteKind(row), "Fit note")
        XCTAssertLessThan(ResultsSection.rowNoteKind(row).count, (row.conflictNote ?? "").count)
    }
}
