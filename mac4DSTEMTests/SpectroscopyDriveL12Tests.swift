//
//  SpectroscopyDriveL12Tests.swift
//  Lane L12 (WP4): the three registered Auto ID rules (`ProposalRules`, Core) on hand-built `ProposalResult`s, and how
//  `AutoIDPresentation.outcome(rules:)` shows them. No compute, no app driving. Every test names the mutation it catches.
//  Registration: docs/registrations/wp4-autoid-velox-preregistration-2026-10-07.md (H1 never Z >= 89 and drop an L/M pick within
//  1.5 FWHM of another proposed candidate's K alpha; H2 an L/M pick needs net / L_D >= 3; H3 a held sum-peak candidate at
//  net / L_D >= 10 is released).
//

import DSTEMCore
import XCTest
@testable import mac4DSTEM
@testable import SpectroCore

@MainActor
final class SpectroscopyDriveL12Tests: XCTestCase {
    /// net / L_D = `significance` exactly (L_D 300).
    private func candidate(_ element: String, _ group: String, energy: Double? = nil, significance: Double,
                           conflicts: [LineConflict] = []) -> ElementCandidate {
        ElementCandidate(element: element, group: group, energyKeV: energy ?? XRayLines.line(group)!.energy, net: significance * 300, sigma: 30, sigmaZero: 90,
                         criticalLevel: 150, detectionLimit: 300, conflicts: conflicts,
                         suggestedRole: .fitOnly, holeRegionNote: nil, misfit: 1)
    }

    /// A candidate the proposer would hold back: its alpha sits on the sum of an Al pair half its energy.
    private func held(_ element: String, _ group: String, significance: Double) -> ElementCandidate {
        let e = XRayLines.line(group)!.energy
        let conflicts = LineConflicts.conflicts(element: element, line: group, lineEnergyKeV: e, parents: [SumParent(element: "Al", energyKeV: e / 2)])
        return candidate(element, group, significance: significance, conflicts: conflicts)
    }

    private func proposal(_ candidates: [ElementCandidate]) -> ProposalResult {
        ProposalResult(candidates: candidates, sumPeaks: [], refused: [], currie: .standard, notes: ["the proposer's own note"], passes: 1, settled: true)
    }

    // MARK: presentation

    /// Mutation: `outcome` ignores `rules` (iterates `r.proposed`), or drops the withheld line from the notes, or keeps a released candidate among the suspects.
    func testOutcomeShowsTheRuledPicksTheirRuleAndWhatWasWithheld() {
        let r = proposal([candidate("Cu", "Cu_Ka", significance: 27), candidate("Ho", "Ho_La", significance: 1.9), held("Ar", "Ar_Ka", significance: 14), held("Zr", "Zr_Ka", significance: 2)])
        let plain = AutoIDPresentation.outcome(r, region: "r")
        XCTAssertEqual(Set(plain.suggestions.map(\.z)), [29, 67], "no rules: the proposer's picks, byte for byte as before")
        XCTAssertEqual(plain.notes, ["the proposer's own note"])
        let o = AutoIDPresentation.outcome(r, region: "r", rules: ProposalRules.registered.apply(r))
        XCTAssertEqual(Set(o.suggestions.map(\.z)), [29, 18], "Cu and the released Ar; Ho (1.9 x L_D, L) is withheld")
        let ar = o.suggestions.first { $0.z == 18 }!
        XCTAssertTrue(ar.reason.contains("Rule R3"), ar.reason)
        XCTAssertTrue(ar.reason.contains("Al+Al sum"), "the sum-peak question stays in the reason: \(ar.reason)")
        XCTAssertEqual(o.suspects.count, 1, "the released candidate leaves the suspects")
        XCTAssertTrue(o.suspects[0].label.contains("Zr"))
        XCTAssertEqual(o.notes.first, "the proposer's own note")
        XCTAssertTrue(o.notes.contains { $0.hasPrefix("Withheld by the rules:") && $0.contains("Ho L\u{03B1} (R2, 1.9 \u{00D7} L_D < 3)") }, "\(o.notes)")
        XCTAssertTrue(o.notes.contains { $0.hasPrefix("Released from the sum-peak hold (R3): Ar K\u{03B1}") }, "\(o.notes)")
        XCTAssertTrue(o.notes.last?.contains("unvalidated") ?? false, "the honesty line stays: \(o.notes)")
        let off = AutoIDPresentation.outcome(r, region: "r", rules: ProposalRules.none.apply(r))
        XCTAssertEqual(off.notes, plain.notes, "no rule on: no rule line")
    }
}
