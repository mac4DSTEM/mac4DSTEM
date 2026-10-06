//
//  SpectroscopyAutoIDTests.swift
//  v5.0 WP3 lane W — Auto ID in the Spectroscopy room: the proposer's `ProposalResult` -> suggestions, suspect markers
//  and notes (`AutoIDPresentation`), and the view-model rules around them (`SpectroscopyRoomModel`): manual picks are
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
        XCTAssertEqual(o.suspectMarkers.map(\.kind), [.suspect])
        XCTAssertEqual(o.suspectMarkers[0].energy, 2.957, accuracy: 1e-9)
        XCTAssertTrue(o.suspectMarkers[0].label.hasSuffix("?"))
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

    /// Mutation: suspect markers appended without removing the previous run's, or kind `.line`.
    func testSuspectMarkersAreReplacedByARunAndLeaveLineMarkersAlone() {
        let m = model()
        m.markers = [LineMarker(label: "Mg Kα", energy: 1.254, elementZ: Mg)]
        m.finishAutoID(token: m.beginAutoID(), outcome: AutoIDPresentation.outcome(proposal([argonOnSum]), region: "A"))
        XCTAssertEqual(m.markers.filter { $0.kind == .suspect }.count, 1)
        m.finishAutoID(token: m.beginAutoID(), outcome: AutoIDPresentation.outcome(proposal([]), region: "B"))
        XCTAssertEqual(m.markers.filter { $0.kind == .suspect }.count, 0)
        XCTAssertEqual(m.markers.filter { $0.kind == .line }.map(\.label), ["Mg Kα"])
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
        state.spectroscopyRoom.model.autoIDEnabled = false   // the run is started by hand: Auto ID on open would be a second one
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())
        let c = state.spectroscopyRoom
        c.model.elements.click(Al)
        c.runAutoID()
        XCTAssertFalse(c.model.autoID.running)
        XCTAssertTrue(c.model.autoID.failure?.contains("beam energy") == true, c.model.autoID.failure ?? "no note")
        XCTAssertNil(c.model.autoID.outcome)
    }

    /// Mutation: `refresh()` stops cancelling a running Auto ID (the `if model.autoID.running { cancelAutoID() }` line removed):
    /// the zero-count spectrum then lands an outcome or a failure note.
    func testARunCancelledByRefreshLandsNothingAndLeavesNoNote() async {
        let state = AppState()
        state.spectroscopyRoom.model.autoIDEnabled = false   // the run is started by hand: Auto ID on open would be a second one
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())
        let c = state.spectroscopyRoom
        c.model.elements.click(Al)
        state.spectroscopy.method.beamEnergyKeV = 200
        c.runAutoID()
        XCTAssertTrue(c.model.autoID.running, "precondition: the run started")
        let task = c.autoIDTask
        c.refresh()                                  // an element or region edit
        await task?.value
        for _ in 0..<5 { await Task.yield() }        // a late MainActor hop would land here
        XCTAssertFalse(c.model.autoID.running)
        XCTAssertNil(c.model.autoID.outcome, "nothing landed")
        XCTAssertNil(c.model.autoID.failure, "a cancel is a silent discard, not a failure")
        XCTAssertTrue(c.model.elements.suggestions.isEmpty)
    }
}
