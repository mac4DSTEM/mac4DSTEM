//
//  SpectroscopyAutoIDTests.swift
//  v5.0 WP3 lane W — Auto ID in the Spectroscopy room: the proposer's `ProposalResult` -> suggestions and notes (`AutoIDPresentation`), and the view-model rules around them (`SpectroscopyRoomModel`): manual picks are
//  never touched, a cancelled run changes nothing, the new row fits the inspector column. No compute, no app driving.
//  Every test names the mutation it catches; break each one before trusting it.
//

import AppKit
import DSTEMCore
import DSTEMSession
import SwiftUI
import XCTest
@testable import mac4DSTEM

@MainActor
final class SpectroscopyAutoIDTests: XCTestCase {
    private let Mg = 12, Al = 13, Cu = 29, Ga = 31, Ar = 18, C = 6

    // MARK: Hand-built proposals (the mapping must not depend on the proposer's numerics)

    private func candidate(_ element: String, _ group: String, energy: Double, net: Double = 900, limit: Double = 300,
                           conflicts: [LineConflict] = []) -> ElementCandidate {
        ElementCandidate(element: element, group: group, energyKeV: energy, net: net, sigma: 30, sigmaZero: 90,
                         criticalLevel: 150, detectionLimit: limit, conflicts: conflicts,
                         suggestedRole: .fitOnly, holeRegionNote: nil, misfit: 1)
    }

    private func proposal(_ candidates: [ElementCandidate], refused: [(element: String, reason: String)] = [],
                          notes: [String] = []) -> ProposalResult {
        ProposalResult(candidates: candidates, sumPeaks: [], refused: refused, currie: .standard, notes: notes, passes: 1, settled: true)
    }

    private var alSum: [SumParent] { [SumParent(element: "Al", energyKeV: 1.4865)] }

    /// An Ar K-alpha candidate sitting on the Al+Al pile-up (2.973 keV), as the proposer produces it.
    private var argonOnSum: ElementCandidate {
        candidate("Ar", "Ar_Ka", energy: 2.957, conflicts: LineConflicts.conflicts(element: "Ar", line: "Ar_Ka", lineEnergyKeV: 2.957, parents: alSum))
    }
    private var copper: ElementCandidate {
        candidate("Cu", "Cu_La", energy: 0.930, conflicts: LineConflicts.conflicts(element: "Cu", line: "Cu_La", lineEnergyKeV: 0.930, parents: []))
    }
    private var gallium: ElementCandidate {
        candidate("Ga", "Ga_La", energy: 1.098, conflicts: LineConflicts.conflicts(element: "Ga", line: "Ga_La", lineEnergyKeV: 1.098, parents: []))
    }

    // MARK: Mapping

    /// Mutation: map `result.candidates.filter(\.isProposed)` (the sum-peak ones included) instead of `result.proposed`.
    func testSumPeakQuestionsAreMarkersNeverElementSuggestions() {
        let r = proposal([candidate("Mg", "Mg_Ka", energy: 1.254), argonOnSum])
        XCTAssertEqual(r.sumPeakQuestions.map(\.element), ["Ar"], "precondition: the proposer files Ar as a sum-peak question")
        let o = AutoIDPresentation.outcome(r, region: "Whole map")
        XCTAssertEqual(o.suggestions.map(\.z), [Mg], "only Mg is an element suggestion")
        XCTAssertFalse(o.suggestions.contains { $0.z == Ar })
        let s = try! XCTUnwrap(o.suspects.first)
        XCTAssertEqual(o.suspects.count, 1)
        XCTAssertTrue(s.question.contains("Al+Al sum"), "the conflict's own text is carried: \(s.question)")
        XCTAssertEqual(s.energy, 2.957, accuracy: 1e-9)
        XCTAssertTrue(s.label.hasPrefix("Al+Al sum?"), "R7: the sum leads, the candidate follows in brackets")
    }

    /// Mutation: the reason is the generic "n x L_D" text for every candidate (conflict text dropped), or the Cu question
    /// is taken from the Ga conflict.
    func testCuAndGaCarryTheirNamedQuestionAndPlainElementsTheirSignificance() {
        let o = AutoIDPresentation.outcome(proposal([copper, gallium, candidate("Mg", "Mg_Ka", energy: 1.254)]), region: "r")
        let byZ = Dictionary(uniqueKeysWithValues: o.suggestions.map { ($0.z, $0) })
        XCTAssertTrue(try XCTUnwrap(byZ[Cu]).reason.contains("grid"), byZ[Cu]?.reason ?? "no Cu")
        XCTAssertTrue(try XCTUnwrap(byZ[Ga]).reason.contains("FIB"), byZ[Ga]?.reason ?? "no Ga")
        XCTAssertFalse(try XCTUnwrap(byZ[Cu]).reason.contains("FIB"))
        XCTAssertTrue(try XCTUnwrap(byZ[Mg]).reason.contains("L_D"), "no conflict: the reason is the significance")
        // Brief: role Quantify; the one decided exception is a FIB question, whose own remedy says "keep Ga fitted but excluded from Quantify".
        XCTAssertEqual(byZ[Cu]?.proposedRole, .quantify)
        XCTAssertEqual(byZ[Mg]?.proposedRole, .quantify)
        XCTAssertEqual(byZ[Ga]?.proposedRole, .fitOnly)
    }

    /// Mutation: list every refusal (H, He, Li, Be included) or drop the filter on `LineConflicts.refusedElements`.
    func testRefusalsShowOnlyWhatThePeriodicTableDoesNotAlreadyGrey() {
        let r = proposal([], refused: [("H", "no line"), ("Be", "below window"), ("C", "Its line at 0.28 keV lies below the proposer's lowest tested line (0.45 keV)")])
        let o = AutoIDPresentation.outcome(r, region: "r")
        XCTAssertEqual(o.notTested.map(\.element), ["C"])
        XCTAssertTrue(o.suggestions.isEmpty)
    }

    /// Mutation: unavailable elements (Z <= 4) kept as suggestions, or the proposer's notes dropped.
    func testNotesAreCarriedAndUnclickableElementsNeverSuggested() {
        let r = proposal([candidate("Be", "Be_Ka", energy: 0.108)], notes: ["Look-elsewhere: 114 line groups tested"])
        let o = AutoIDPresentation.outcome(r, region: "r")
        XCTAssertTrue(o.suggestions.isEmpty)
        XCTAssertEqual(o.notes, ["Look-elsewhere: 114 line groups tested"])
    }

    // MARK: R7 (wp3e): sum-first markers, beside-a-line excesses, net / L_D and chi-square on every suggestion

    private func proposal(_ candidates: [ElementCandidate], chi: Double) -> ProposalResult {
        ProposalResult(candidates: candidates, sumPeaks: [], refused: [], currie: .standard, notes: [], passes: 1, settled: true, reducedChiSquared: chi)
    }

    /// The beside rule on the quant panel's own settings: Al listed, a 10 eV/channel axis, the default continuum.
    private var alListedBeside: (Double, String) -> String? {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 2000)
        let settings = FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, beamEnergy: 200)
        return AutoIDPresentation.besideCheck(settings: settings, axis: axis)
    }

    /// Mutation: `AutoIDSuspect.label` back to `ElementWindows.label(ofLineID: c.group) + "?"` (the candidate leads) - red.
    func testASumPeakSuspectLeadsWithTheSum() throws {
        let o = AutoIDPresentation.outcome(proposal([argonOnSum]), region: "r")
        let s = try XCTUnwrap(o.suspects.first)
        XCTAssertTrue(s.label.hasPrefix("Al+Al sum?"), s.label)
        XCTAssertTrue(s.label.hasSuffix("(or Ar K\u{03B1})"), s.label)
    }

    /// A candidate 94 eV above Al K-alpha (Lu M-alpha, the WP3d excess) with Al listed is named as an excess beside Al K-alpha,
    /// with no suggestion; one clear of every listed line stays a suggestion.
    /// Mutation: drop the `continue` after the excess is appended (the same candidate also becomes a suggestion) - red.
    func testACandidateBesideAListedLineIsAnExcessNeverASuggestion() throws {
        let lu = candidate("Lu", "Lu_Ma", energy: 1.581, net: 4513, limit: 2073)
        let mg = candidate("Mg", "Mg_Ka", energy: 1.254)
        let o = AutoIDPresentation.outcome(proposal([lu, mg], chi: 54.8), region: "r", beside: alListedBeside)
        XCTAssertEqual(o.suggestions.map(\.z), [Mg], "Lu is not offered as an element")
        let e = try XCTUnwrap(o.excesses.first)
        XCTAssertEqual(o.excesses.count, 1)
        XCTAssertEqual(e.title, "unexplained excess beside Al K\u{03B1}")
        XCTAssertEqual(e.proposerLabel, "Lu M\u{03B1}")
        XCTAssertTrue(e.detail.contains("net 4 513 counts"), e.detail)
        XCTAssertTrue(o.hasDetails)
        // The default (no check supplied) changes nothing: both are suggestions.
        XCTAssertEqual(AutoIDPresentation.outcome(proposal([lu, mg]), region: "r").suggestions.count, 2)
    }

    /// Every suggestion (a plain one, one with a named conflict) and every suspect carries net, net / L_D and the fit's chi-square.
    /// Mutation: `stats` dropped from the conflict branch of `reason` (Cu keeps only its question) - red.
    func testEverySuggestionCarriesNetOverLDAndTheFitsChiSquared() throws {
        let o = AutoIDPresentation.outcome(proposal([candidate("Mg", "Mg_Ka", energy: 1.254), copper, argonOnSum], chi: 54.8), region: "r")
        let byZ = Dictionary(uniqueKeysWithValues: o.suggestions.map { ($0.z, $0) })
        for z in [Mg, Cu] {
            let r = try XCTUnwrap(byZ[z]).reason
            XCTAssertTrue(r.contains("net 900 counts, 3.0 \u{00D7} L_D"), r)
            XCTAssertTrue(r.contains("\u{03C7}\u{00B2}\u{1D63} 54.8 (Pearson)"), r)
        }
        XCTAssertTrue(try XCTUnwrap(byZ[Cu]).reason.contains("grid"), "the question stays")
        XCTAssertTrue(try XCTUnwrap(o.suspects.first).stats.contains("\u{03C7}\u{00B2}\u{1D63} 54.8 (Pearson)"))
        // A hand-built result has no chi-square: the clause is absent, not "nil".
        XCTAssertFalse(try XCTUnwrap(AutoIDPresentation.outcome(proposal([candidate("Mg", "Mg_Ka", energy: 1.254)]), region: "r").suggestions.first).reason.contains("\u{03C7}"))
    }

    // MARK: D3 (wp3e Gate D2): suggestions, excesses and suspects are ordered by net / L_D, strongest first

    /// A hand-built result may list a 1.2 x L_D candidate before a 3.0 x one; the room shows the strong one first in each list, and
    /// equal significance keeps the proposer's order (a stable sort).
    /// Mutation: drop the sort in `AutoIDPresentation.outcome` (iterate `r.proposed` and `r.sumPeakQuestions` as given) - red.
    func testSuggestionsExcessesAndSuspectsAreSortedBySignificanceStably() throws {
        func sumQ(_ el: String, net: Double) -> ElementCandidate {
            candidate(el, "\(el)_Ka", energy: 2.957, net: net,
                      conflicts: LineConflicts.conflicts(element: el, line: "\(el)_Ka", lineEnergyKeV: 2.957, parents: alSum))
        }
        let weakMg = candidate("Mg", "Mg_Ka", energy: 1.254, net: 360)             // 1.2 x L_D
        let strongSi = candidate("Si", "Si_Ka", energy: 1.740, net: 900)           // 3.0 x
        let tieP = candidate("P", "P_Ka", energy: 2.013, net: 900)                 // 3.0 x, after Si in the input
        let weakLu = candidate("Lu", "Lu_Ma", energy: 1.581, net: 360)
        let strongTm = candidate("Tm", "Tm_Ma", energy: 1.462, net: 900)
        let r = proposal([weakMg, strongSi, tieP, weakLu, strongTm, sumQ("Ar", net: 360), sumQ("K", net: 900)], chi: 2)
        let o = AutoIDPresentation.outcome(r, region: "r", beside: { e, _ in (e > 1.45 && e < 1.6) ? "Al K\u{03B1}" : nil })
        XCTAssertEqual(o.suggestions.map(\.z), [14, 15, 12], "Si and P (3.0 x, input order) before Mg (1.2 x)")
        XCTAssertEqual(o.excesses.map(\.proposerLabel), ["Tm M\u{03B1}", "Lu M\u{03B1}"], "3.0 x before 1.2 x")
        XCTAssertEqual(o.suspects.map(\.energy).count, 2)
        XCTAssertTrue(o.suspects[0].label.hasSuffix("(or K K\u{03B1})"), "3.0 x first: \(o.suspects[0].label)")
        XCTAssertTrue(o.suspects[1].label.hasSuffix("(or Ar K\u{03B1})"), o.suspects[1].label)
    }

    // MARK: Model rules

    private func model() -> SpectroscopyRoomModel {
        SpectroscopyRoomModel(series: SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [1, 2, 3], background: [], model: [], overlay: nil))
    }

    /// Mutation: `finishAutoID` assigns `elements.suggestions` directly (no `rerunAutoID`), or `rerunAutoID` stops
    /// filtering the manual set.
    func testManualPicksAreUntouchedByARunAndByARerun() {
        let m = model()
        m.elements.set(Mg, .fitOnly)            // a person's choice
        m.elements.click(Al)                    // another
        let before = m.elements
        let t1 = m.beginAutoID()
        m.finishAutoID(token: t1, outcome: AutoIDPresentation.outcome(proposal([candidate("Mg", "Mg_Ka", energy: 1.254), gallium, copper]), region: "A"))
        XCTAssertEqual(m.elements.role(Mg), .fitOnly, "a manual Fit only is not turned into Quantify nor suggested again")
        XCTAssertEqual(m.elements.role(Al), .quantify)
        XCTAssertEqual(m.elements.manual, before.manual)
        XCTAssertEqual(m.elements.suggestions.map(\.z).sorted(), [Cu, Ga], "Mg was decided by a person: not suggested")
        // Rerun on another region: the earlier suggestions are replaced, still nothing manual moves.
        let t2 = m.beginAutoID()
        m.finishAutoID(token: t2, outcome: AutoIDPresentation.outcome(proposal([candidate("Mg", "Mg_Ka", energy: 1.254), argonOnSum]), region: "B"))
        XCTAssertEqual(m.elements.suggestions.map(\.z), [], "the rerun replaced the pending suggestions (Mg is manual, Ar a sum question)")
        XCTAssertEqual(m.elements.role(Mg), .fitOnly)
        XCTAssertEqual(m.elements.role(Al), .quantify)
        XCTAssertEqual(m.elements.manual, before.manual)
        XCTAssertEqual(m.autoID.outcome?.region, "B")
    }

    /// Mutation: accepting through `set` forgets `manual`, or a click on a suggested element toggles to Off.
    func testOneClickAcceptsASuggestionWithItsProposedRole() {
        let m = model()
        let t = m.beginAutoID()
        m.finishAutoID(token: t, outcome: AutoIDPresentation.outcome(proposal([copper, gallium]), region: "A"))
        XCTAssertEqual(m.elements.cellState(Cu), .suggested(m.elements.suggestions.first { $0.z == Cu }!.reason))
        m.elements.click(Cu)
        XCTAssertEqual(m.elements.role(Cu), .quantify)
        XCTAssertTrue(m.elements.manual.contains(Cu))
        m.elements.click(Ga)
        XCTAssertEqual(m.elements.role(Ga), .fitOnly)
        XCTAssertTrue(m.elements.suggestions.isEmpty)
    }

    /// Mutation: `cancelAutoID` leaves `running` on, or `finishAutoID` ignores the token.
    func testCancellationLeavesEverythingAsItWasAndALateResultIsDropped() {
        let m = model()
        m.elements.click(Mg)
        m.markers = [LineMarker(label: "Mg Kα", energy: 1.254, elementZ: Mg)]
        let first = m.beginAutoID()
        m.finishAutoID(token: first, outcome: AutoIDPresentation.outcome(proposal([gallium, argonOnSum]), region: "A"))
        let elementsBefore = m.elements, markersBefore = m.markers, outcomeBefore = m.autoID.outcome

        let t = m.beginAutoID()
        XCTAssertTrue(m.autoID.running)
        m.cancelAutoID()
        XCTAssertFalse(m.autoID.running)
        let landed = m.finishAutoID(token: t, outcome: AutoIDPresentation.outcome(proposal([copper]), region: "B"))
        XCTAssertFalse(landed, "the cancelled run's result is not applied")
        XCTAssertEqual(m.elements, elementsBefore)
        XCTAssertEqual(m.markers, markersBefore)
        XCTAssertEqual(m.autoID.outcome, outcomeBefore)
        XCTAssertFalse(m.autoID.running)
    }

    /// Mutation: a newer `beginAutoID` does not invalidate the older token.
    func testOnlyTheNewestRunLands() {
        let m = model()
        let old = m.beginAutoID(), new = m.beginAutoID()
        XCTAssertFalse(m.finishAutoID(token: old, outcome: AutoIDPresentation.outcome(proposal([copper]), region: "old")))
        XCTAssertTrue(m.autoID.running, "the newer run is still running")
        XCTAssertTrue(m.finishAutoID(token: new, outcome: AutoIDPresentation.outcome(proposal([gallium]), region: "new")))
        XCTAssertEqual(m.elements.suggestions.map(\.z), [Ga])
    }

    /// A run draws no marker of its own: the sum-peak questions stay in the outcome (the Picked row's hover), the markers are the picks'.
    /// Mutation: `finishAutoID` appending the suspects as markers - red.
    func testARunLeavesTheMarkersAlone() {
        let m = model()
        m.markers = [LineMarker(label: "Mg Kα", energy: 1.254, elementZ: Mg)]
        m.finishAutoID(token: m.beginAutoID(), outcome: AutoIDPresentation.outcome(proposal([argonOnSum]), region: "A"))
        XCTAssertEqual(m.autoID.outcome?.suspects.count, 1)
        XCTAssertEqual(m.markers.map(\.label), ["Mg Kα"])
    }

    /// Mutation: `failAutoID` leaves `running` set, or clears the earlier outcome.
    func testAFailedRunKeepsTheEarlierOutcomeAndSaysWhy() {
        let m = model()
        m.finishAutoID(token: m.beginAutoID(), outcome: AutoIDPresentation.outcome(proposal([gallium]), region: "A"))
        let t = m.beginAutoID()
        m.failAutoID(token: t, message: "Auto ID needs the beam energy")
        XCTAssertFalse(m.autoID.running)
        XCTAssertEqual(m.autoID.failure, "Auto ID needs the beam energy")
        XCTAssertEqual(m.elements.suggestions.map(\.z), [Ga])
    }

    // MARK: Width

    /// Mutation: the Auto ID row's button label gets a fixed 300-pt text, or the running state grows a second fixed-size text.
    func testTheInspectorStillFitsTheNarrowestColumnWhileIdleRunningAndAfterARun() {
        let budget = LayoutPolicy.inspectorWidth.min - 2 * 16
        func width(_ m: SpectroscopyRoomModel) -> CGFloat {
            let state = AppState()
            let host = NSHostingController(rootView: SpectroscopyInspectorSections(model: m, startOpen: true).environment(state).environment(state.preferences))
            return host.sizeThatFits(in: CGSize(width: 1, height: 10_000)).width
        }
        let m = model()
        m.isLive = true
        m.onAutoID = {}
        XCTAssertLessThanOrEqual(width(m), budget, "idle")
        let t = m.beginAutoID()
        XCTAssertLessThanOrEqual(width(m), budget, "running")
        let notes = ["Look-elsewhere: 114 line groups were tested, so about 114 × 5.0e-04 = 0.06 chance proposals per spectrum are expected; a candidate near net/L_D = 1 is as likely a chance one as an element."]
        m.finishAutoID(token: t, outcome: AutoIDPresentation.outcome(proposal([copper, gallium, argonOnSum, candidate("Mg", "Mg_Ka", energy: 1.254)],
                                                                             refused: [("C", "Its line lies below the proposer's lowest tested line")], notes: notes), region: "β″ precipitates (drawn)"))
        XCTAssertLessThanOrEqual(width(m), budget, "after a run")
    }

    // MARK: Controller (SpectroscopyRoomTests.StubSpectrumImage: zero counts, no beam energy in the file)

    /// Mutation: runAutoID drops the beam guard (proposes with beam 0 or 200 regardless).
    func testWithoutABeamEnergyAutoIDSaysSoAndProposesNothing() {
        let state = AppState()
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()   // these tests drive Auto ID by hand, or not at all
        let c = state.spectroscopyRoom
        c.model.elements.click(Al)
        c.runAutoID()
        XCTAssertFalse(c.model.autoID.running)
        XCTAssertTrue(c.model.autoID.failure?.contains("beam energy") == true, c.model.autoID.failure ?? "no note")
        XCTAssertNil(c.model.autoID.outcome)
    }

    /// The refresh cancels the run at once and the cancelled run is a silent discard. (Auto ID is always on, so the refresh also
    /// restarts it when it lands: `testAClickDuringARunRestartsIt`; only the state at the cancel is asserted here.)
    /// Mutation: `refresh()` stops cancelling a running Auto ID (the `if model.autoID.running { cancelAutoID() }` line removed):
    /// the run is still going right after the refresh.
    func testARunCancelledByRefreshLandsNothingAndLeavesNoNote() async {
        let state = AppState()
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()   // these tests drive Auto ID by hand, or not at all
        let c = state.spectroscopyRoom
        c.model.elements.click(Al)
        state.spectroscopy.method.beamEnergyKeV = 200
        c.runAutoID()
        XCTAssertTrue(c.model.autoID.running, "precondition: the run started")
        let task = c.autoIDTask
        c.refresh()                                  // an element or region edit
        XCTAssertFalse(c.model.autoID.running)
        XCTAssertNil(c.model.autoID.outcome, "nothing landed")
        XCTAssertNil(c.model.autoID.failure, "a cancel is a silent discard, not a failure")
        await task?.value
        XCTAssertTrue(c.model.elements.suggestions.isEmpty)
    }

    // MARK: R8

    /// Fresh open, nothing listed: Al K-alpha sits at the Al split edge and is a SUGGESTION, not an excess.
    /// Mutation: `besideCheck` passes `nil` instead of `element` to `neighbour` - Al becomes an excess, red.
    func testR8AlOnItsOwnEdgeIsASuggestionWithNothingListed() {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 2000)
        let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, beamEnergy: 200)
        let o = AutoIDPresentation.outcome(proposal([candidate("Al", "Al_Ka", energy: 1.4865)], chi: 2),
                                           region: "r", beside: AutoIDPresentation.besideCheck(settings: settings, axis: axis))
        XCTAssertEqual(o.suggestions.map(\.z), [Al]); XCTAssertTrue(o.excesses.isEmpty)
    }

    /// The note under Proposed follows the picks: an excess judged against one list is not shown once the list changes.
    /// Mutation: `autoIDExcesses` returns `o.excesses` unconditionally - red.
    func testR8ExcessNoteGoesStaleWhenPicksChange() {
        let m = model()
        m.elements.click(Al)
        let lu = candidate("Lu", "Lu_Ma", energy: 1.581, net: 4513, limit: 2073)
        let t = m.beginAutoID()
        m.finishAutoID(token: t, outcome: AutoIDPresentation.outcome(proposal([lu], chi: 2), region: "r", beside: alListedBeside))
        XCTAssertEqual(m.autoIDExcesses.count, 1)
        m.elements.click(Mg)
        XCTAssertTrue(m.autoIDExcesses.isEmpty)
        m.elements.click(Mg)
        XCTAssertEqual(m.autoIDExcesses.count, 1, "back to the list it was judged against")
    }
}
