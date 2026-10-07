//
//  SpectroscopySpec2ETests.swift
//  Spec 2 lane E (the controller): Auto ID applies its picks (D-3), Quantify and Auto ID run as operations (D-12), the
//  quantification step's readable provenance (D-11), the spectrum CSV (D-14) and `MapTile.scale` (D-13). Every test names the
//  mutation it catches; each was broken once and seen red (the lane report lists them).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SpectroscopySpec2ETests: XCTestCase {
    private let Al = 13, Cu = 29, Eu = 63

    /// The states stay alive for the test: the controller holds its session weakly.
    private var keep: [AppState] = []

    private func open(autoID: Bool = false) -> (AppState, SpectroscopyRoomController) {
        let state = AppState()
        keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        if !autoID { state.spectroscopyRoom.autoIDOnOpen?.cancel() }   // Auto ID on open always runs; a test about something else stops it
        return (state, state.spectroscopyRoom)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func outcome(_ zs: [Int]) -> AutoIDOutcome {
        AutoIDOutcome(region: "Whole map", suggestions: zs.map { ElementSuggestion(z: $0, reason: "net 900 counts") },
                      suspects: [], notTested: [], notes: [])
    }

    // MARK: D-3 Auto ID applies its picks

    /// A suggestion becomes a pick through the table's click; an element the person set Off by hand is never re-added, by this
    /// run or the next, and a pick the person removed is not brought back.
    /// Mutations: `applyAutoIDPicks` not clicking (Al stays a suggestion) - red; its `manual` guard removed while the model still
    /// lists Eu as a suggestion (the selection below) - red.
    func testApplyingTheRunsPicksLeavesAPersonsOffAlone() {
        let c = SpectroscopyRoomController(); let m = c.model
        m.elements.set(Eu, .off)
        var t = m.beginAutoID()
        XCTAssertTrue(m.finishAutoID(token: t, outcome: outcome([Al, Eu])))
        XCTAssertEqual(m.elements.suggestions.map(\.z), [Al], "the person's Off is not even suggested")
        XCTAssertTrue(c.applyAutoIDPicks())
        XCTAssertEqual(m.elements.role(Al), .quantify); XCTAssertEqual(m.elements.role(Eu), .off)
        XCTAssertTrue(m.elements.suggestions.isEmpty)
        // a second run offers both again; Al is already the person's (a click made it a pick), Eu is still Off
        t = m.beginAutoID()
        m.finishAutoID(token: t, outcome: outcome([Al, Eu]))
        XCTAssertFalse(c.applyAutoIDPicks(), "nothing new to apply")
        XCTAssertEqual(m.elements.role(Al), .quantify); XCTAssertEqual(m.elements.role(Eu), .off)
        // the guard itself: a suggestion for an element the selection records as decided is left alone
        m.elements = ElementSelection(roles: [Eu: .off], manual: [Eu], suggestions: [ElementSuggestion(z: Eu, reason: "x"), ElementSuggestion(z: Cu, reason: "y")])
        XCTAssertTrue(c.applyAutoIDPicks())
        XCTAssertEqual(m.elements.role(Eu), .off); XCTAssertEqual(m.elements.role(Cu), .quantify)
    }

    /// A FIB question proposes Fit only: applying keeps the proposed role, not a blanket Quantify.
    /// Mutation: `applyAutoIDPicks` setting `.quantify` for every suggestion - red.
    func testTheProposedRoleIsKept() {
        let c = SpectroscopyRoomController(); let m = c.model
        let t = m.beginAutoID()
        m.finishAutoID(token: t, outcome: AutoIDOutcome(region: "r", suggestions: [ElementSuggestion(z: 31, reason: "Ga: from FIB?", proposedRole: .fitOnly),
                                                                                    ElementSuggestion(z: Cu, reason: "Cu")],
                                                        suspects: [], notTested: [], notes: []))
        c.applyAutoIDPicks()
        XCTAssertEqual(m.elements.role(31), .fitOnly); XCTAssertEqual(m.elements.role(Cu), .quantify)
    }

    /// The whole run on a real spectrum: the planted Cu line is picked at once, its row and tile exist, nothing is left suggested.
    /// Mutation: the landing never calls `applyAutoIDPicks()` - red.
    func testARunPicksWhatItFoundAndMapsItAtOnce() async throws {
        let (_, c) = open(autoID: true)
        try await waitFor("Auto ID's outcome") { c.model.autoID.outcome != nil || c.model.autoID.failure != nil }
        XCTAssertNil(c.model.autoID.failure)
        XCTAssertTrue(c.model.elements.quantified.contains(Cu), "the planted Cu line is picked")
        XCTAssertTrue(c.model.elements.suggestions.isEmpty)
        try await waitFor("Cu's tile and row") { c.model.tiles.contains { $0.z == self.Cu } && c.model.results.contains { $0.z == self.Cu } }
        XCTAssertTrue(c.model.mixed.contains(Cu), "a picked element goes into the mix")
    }

    /// The person's Off survives the run on a real spectrum and the re-run.
    /// Mutation: `applyAutoIDPicks` clicking every suggestion without `finishAutoID`'s filter (the model offering Cu again) - red.
    func testAnElementSwitchedOffByHandIsNotPickedByTheRunOrTheNextOne() async throws {
        let (_, c) = open(autoID: false)
        c.model.elements.set(Cu, .off); c.elementsChanged()
        c.runAutoID()
        try await waitFor("the outcome") { c.model.autoID.outcome != nil || c.model.autoID.failure != nil }
        XCTAssertNil(c.model.autoID.failure)
        XCTAssertEqual(c.model.elements.role(Cu), .off)
        XCTAssertFalse(c.model.elements.suggestions.contains { $0.z == Cu })
        XCTAssertFalse(c.model.tiles.contains { $0.z == Cu }, "a person's Off gets no tile")
        c.runAutoID()
        XCTAssertTrue(c.model.autoID.running)
        try await waitFor("the second run") { !c.model.autoID.running }
        XCTAssertEqual(c.model.elements.role(Cu), .off, "a second run does not re-add it")
    }

    // MARK: D-12 operations

    private final class Recorder {
        var begun: [(name: String, status: String, token: AnalysisCancellationToken)] = []
        var finished: [AnalysisCancellationToken] = []
        var cancelOnBegin = false
        var paired: Bool { begun.count == finished.count && zip(begun, finished).allSatisfy { $0.token === $1 } }
    }

    private func record(_ c: SpectroscopyRoomController) -> Recorder {
        let r = Recorder()
        c.operation = { name, status in
            let t = AnalysisCancellationToken()
            if r.cancelOnBegin { t.cancel() }
            r.begun.append((name, status, t)); return t
        }
        c.finishOperation = { r.finished.append($0) }
        return r
    }

    /// Quantify is an operation: begun once, finished once with the same token, on success...
    /// Mutations: `beginOperation` not called in `quantify()` - red; `endOperation` not called - red.
    func testQuantifyBeginsAndFinishesOneOperation() async throws {
        let (_, c) = open()
        c.model.elements.set(Al, .quantify); c.elementsChanged()
        let r = record(c)
        let ok = await c.quantify()
        XCTAssertTrue(ok, c.model.fitFailure ?? "")
        XCTAssertEqual(r.begun.map(\.name), ["Quantify"]); XCTAssertTrue(r.paired)
        XCTAssertEqual(r.begun.first?.status.isEmpty, false)
    }

    /// ... and on failure (a file with no beam energy: the verb answers false, the token is still finished).
    /// Mutation: the finish moved after the failure `return` (no `defer`) - red.
    func testAFailedQuantifyStillFinishesItsOperation() async {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()   // these tests drive Auto ID by hand, or not at all
        let c = state.spectroscopyRoom
        c.model.elements.set(Al, .quantify); c.elementsChanged()
        let r = record(c)
        let ok = await c.quantify()
        XCTAssertFalse(ok)
        XCTAssertEqual(r.begun.count, 1); XCTAssertTrue(r.paired)
    }

    /// The infobar's Stop (the token cancelled) during the verb: it answers false, records nothing, and the room is back to the
    /// window numbers; the operation is finished.
    /// Mutation: the watcher never calls `stopQuantify` - red (the fit lands and the verb answers true).
    func testStoppingQuantifyDropsTheFitAndRecordsNothing() async {
        let (_, c) = open()
        c.model.elements.set(Al, .quantify); c.elementsChanged()
        let r = record(c); r.cancelOnBegin = true
        let ok = await c.quantify()
        XCTAssertFalse(ok); XCTAssertFalse(c.quantifyActive); XCTAssertFalse(c.model.hasFit)
        XCTAssertTrue(r.paired)
    }

    /// Auto ID is an operation too: begun with the run, finished when its outcome lands.
    /// Mutations: no `beginOperation` in `runAutoID` - red; the landing not ending it - red.
    func testAutoIDBeginsAnOperationAndFinishesItWhenTheOutcomeLands() async throws {
        let (_, c) = open(autoID: false)
        let r = record(c)
        c.runAutoID()
        XCTAssertEqual(r.begun.map(\.name), ["Auto ID"]); XCTAssertTrue(r.finished.isEmpty, "still running")
        try await waitFor("the outcome") { c.model.autoID.outcome != nil || c.model.autoID.failure != nil }
        XCTAssertTrue(r.paired)
    }

    /// An edit that cancels the run (refresh) finishes its operation; a new run starts a second pair.
    /// Mutation: `cancelAutoID` not ending the operation - red (a token left open: the infobar would stay busy).
    func testACancelledAutoIDFinishesItsOperation() async throws {
        let (_, c) = open(autoID: false)
        let r = record(c)
        c.runAutoID()
        XCTAssertEqual(r.begun.count, 1)
        c.cancelAutoID()
        XCTAssertTrue(r.paired); XCTAssertFalse(c.model.autoID.running)
    }

    /// Stop in the infobar cancels the token; the controller turns that into the run's own cancel: nothing lands, no note.
    /// Mutation: the watcher dropped (`run.watcher = nil`) - red (the run goes on to land its outcome).
    func testStopOnTheInfobarCancelsAnAutoIDRun() async throws {
        let (_, c) = open(autoID: false)
        let r = record(c)
        c.runAutoID()
        try XCTUnwrap(r.begun.first).token.cancel()
        try await waitFor("the run to stop") { !c.model.autoID.running }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(c.model.autoID.outcome); XCTAssertNil(c.model.autoID.failure)
        XCTAssertTrue(r.paired)
    }

    /// Without the beam energy the run fails at once and never begins an operation (nothing to show or stop).
    func testAnInstantFailureBeginsNoOperation() {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomTests.StubSpectrumImage())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()   // these tests drive Auto ID by hand, or not at all
        let c = state.spectroscopyRoom
        let r = record(c)
        c.runAutoID()
        XCTAssertTrue(r.begun.isEmpty); XCTAssertNotNil(c.model.autoID.failure)
    }

    /// `AppState` wires the two hooks to the infobar's operation: begun, the app is busy and names it; finished, it is not, and the
    /// status line is put back.
    /// Mutation: `wireSpectroscopyOperations` not called in `attachSpectrumImage` - red.
    func testTheWindowWiresTheHooksToItsOperationCenter() throws {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()   // these tests drive Auto ID by hand, or not at all
        let c = state.spectroscopyRoom
        let before = state.statusText
        let token = try XCTUnwrap(c.operation)("Quantify", "Fitting the spectrum…")
        XCTAssertTrue(state.isBusy); XCTAssertEqual(state.activeOperation, "Quantify"); XCTAssertEqual(state.statusText, "Fitting the spectrum…")
        try XCTUnwrap(c.finishOperation)(token)
        XCTAssertFalse(state.isBusy); XCTAssertEqual(state.statusText, before)
    }

    // MARK: D-11 provenance

    private func richSession() -> SpectroscopySession {
        let s = SpectroscopySession()
        var m = QuantificationMethod()
        m.estimator = .poissonMaximumLikelihood
        m.background = .wholeRangePolynomial6; m.polynomialOrder = 4
        m.elements = [.init(symbol: "Mg", role: .quantify, isManual: true), .init(symbol: "Al", role: .quantify, isManual: false),
                      .init(symbol: "Si", role: .quantify, isManual: false), .init(symbol: "Cu", role: .fitOnly, isManual: false),
                      .init(symbol: "Eu", role: .off, isManual: true)]
        m.kFactorSource = .typed; m.kSource = "Williams & Carter"; m.kDate = "2026-10-06"; m.kReference = "Si"
        m.typedK = [.init(element: "Mg", k: 1.12), .init(element: "Si", k: 1)]
        m.absorptionCorrection = false
        m.thickness = .init(nanometres: 55, sigmaNanometres: 5)
        m.beamEnergyKeV = 200; m.fitToKeV = 12.5
        s.method = m
        return s
    }

    /// The step carries readable keys beside what the restore needs; `method` is the short hash, the JSON sits under `method_json`.
    /// Mutations: a key dropped or renamed - red; `method` left as the JSON blob - red.
    func testTheStepIsWrittenAsReadableKeys() {
        let s = richSession()
        let p = s.quantificationParameters(regionKind: "drawn", regionName: "Region 1")
        XCTAssertEqual(p["background"], "Polynomial"); XCTAssertEqual(p["k_factors"], "Typed"); XCTAssertEqual(p["absorption"], "off")
        XCTAssertEqual(p["estimator"], "Poisson ML"); XCTAssertEqual(p["beam_energy_kev"], "200"); XCTAssertEqual(p["fit_to_kev"], "12.5")
        XCTAssertEqual(p["thickness_nm"], "55 ± 5"); XCTAssertEqual(p["polynomial_order"], "4")
        XCTAssertEqual(p["elements"], "Mg, Al, Si, Cu", "the listed ones, not the Off")
        XCTAssertEqual(p["region_kind"], "drawn"); XCTAssertEqual(p["region_name"], "Region 1")
        XCTAssertEqual(p["method"], SpectroscopyExport.shortHash(s.method)); XCTAssertEqual(p["method"]?.count, 8)
        XCTAssertEqual(p["method_hash"], s.method.hash)
        XCTAssertTrue(p["method_json"]?.hasPrefix("{") == true)
        // defaults: Empirical, Computed, absorption on, no thickness, no fit-to, no polynomial order
        let d = SpectroscopySession().quantificationParameters()
        XCTAssertEqual(d["background"], "Empirical"); XCTAssertEqual(d["k_factors"], "Computed"); XCTAssertEqual(d["absorption"], "on")
        XCTAssertEqual(d["estimator"], "Least squares")
        for k in ["thickness_nm", "fit_to_kev", "polynomial_order", "elements", "beam_energy_kev"] { XCTAssertNil(d[k], k) }
    }

    /// The file's own beam energy is named when the method does not type one.
    /// Mutation: the file's value ignored - red.
    func testTheBeamEnergyFallsBackToTheFilesOwn() {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        XCTAssertNil(state.spectroscopy.method.beamEnergyKeV)
        XCTAssertEqual(state.spectroscopy.quantificationParameters()["beam_energy_kev"], "200")
    }

    /// The restore contract holds for the recorded form, for a step recorded before this wrote readable keys, and still refuses a
    /// tampered one.
    /// Mutations: `restoreQuantification` not reading `method_json` - red; the hash comparison skipped in Core - red (MethodTests).
    func testTheRestoreRoundTripsBothRecordedForms() throws {
        let s = richSession()
        let original = s.method
        let replay = SessionReplay()
        let id = s.recordQuantification(in: replay, regionKind: "drawn", regionName: "Region 1")
        let recorded = try XCTUnwrap(replay.lineage.node(id: id)).parameters
        XCTAssertEqual(recorded["background"], "Polynomial")
        s.method = QuantificationMethod()
        XCTAssertNotNil(s.restoreQuantification(parameters: recorded)); XCTAssertEqual(s.method, original)
        // older form: the full JSON under `method`
        s.method = QuantificationMethod()
        XCTAssertNotNil(s.restoreQuantification(parameters: QuantificationStep(method: original).parameters)); XCTAssertEqual(s.method, original)
        // tampered
        var bad = recorded; bad["method_hash"] = String(repeating: "0", count: 64)
        s.method = QuantificationMethod()
        XCTAssertNil(s.restoreQuantification(parameters: bad)); XCTAssertEqual(s.method, QuantificationMethod())
    }

    // MARK: D-14 spectrum CSV

    private func series(model: Bool, fit: Range<Int>? = nil) -> SpectrumSeries {
        var s = SpectrumSeries(energyStart: 0.5, energyStep: 0.01, data: [3, 4, 5, 6], background: [], model: [], overlay: nil)
        if model { s.model = [2.5, 3.5, 4.5, 5.5]; s.background = [1, 1, 1, 1]; s.fitChannels = fit }
        return s
    }

    /// No fit: two columns, a header naming the region and the file, one row per channel.
    /// Mutations: the file or region line dropped; the model columns written without a fit - red.
    func testTheSpectrumCSVWithoutAFit() {
        let lines = SpectrumCSV.text(series(model: false), imageName: "a.emd", regionName: "Region 1").split(separator: "\n").map(String.init)
        XCTAssertEqual(Array(lines.prefix(2)), ["# mac4DSTEM Spectroscopy spectrum, region: Region 1", "# file: a.emd"])
        XCTAssertEqual(lines[2], "energy_kev,counts")
        XCTAssertEqual(Array(lines.dropFirst(3)), ["0.5,3", "0.51,4", "0.52,5", "0.53,6"])
    }

    /// Fitted: model and background columns, empty where the fit did not cover the channel.
    /// Mutation: the `fitChannels` test dropped (every row carries values) - red.
    func testTheSpectrumCSVWithAFit() {
        let lines = SpectrumCSV.text(series(model: true, fit: 1..<3), imageName: "a.emd", regionName: "Whole map").split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains { $0.hasPrefix("# model and background") })
        XCTAssertTrue(lines.contains("energy_kev,counts,model,background"))
        let rows = Array(lines.drop { $0 != "energy_kev,counts,model,background" }.dropFirst())
        XCTAssertEqual(rows, ["0.5,3,,", "0.51,4,3.5,1", "0.52,5,4.5,1", "0.53,6,,"])
    }

    /// The room fills it with no fit, follows the region, and keeps it (four columns) after Quantify rebuilds the export.
    /// Mutations: `updateSpectrumStems` not called in `apply` - red; not called in `present` - red (Quantify wipes the label).
    func testTheRoomKeepsTheSpectrumCSVCurrentFromTheFirstSpectrum() async throws {
        let (_, c) = open()
        let csv = { ExportSection.spectrumExport(c.model)?.text }   // built when exported
        try await waitFor("the first spectrum") { csv() != nil }
        let first = try XCTUnwrap(csv())
        XCTAssertTrue(first.contains("region: Whole map")); XCTAssertTrue(first.contains("# file: synthetic"))
        XCTAssertTrue(first.contains("energy_kev,counts\n"), "no fit, two columns")
        XCTAssertEqual(first.split(separator: "\n").count, 3 + c.model.series.data.count)
        XCTAssertEqual(c.model.export.fileStem, "synthetic_Whole_map")
        let a = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 4, y1: 3))
        c.editRegion(a, final: true)
        try await waitFor("the region's spectrum") { csv()?.contains("region: Region 1") == true }
        XCTAssertNotEqual(csv(), first)
        c.model.elements.set(Al, .quantify); c.elementsChanged()
        let ok = await c.quantify()
        XCTAssertTrue(ok, c.model.fitFailure ?? "")
        await c.checkTask?.value
        let fitted = try XCTUnwrap(csv(), "Quantify rebuilds `export`; the spectrum survives it")
        XCTAssertTrue(fitted.contains("energy_kev,counts,model,background\n"))
        XCTAssertNotNil(c.model.export.csv, "the results CSV is there too")
    }

    // MARK: D-13 MapTile.scale

    /// A tile's scale is the map's maximum: what 1.0 stands for.
    /// Mutation: `scale(of:)` returning 1, or the minimum - red.
    func testTheScaleIsTheMapsMaximum() {
        XCTAssertEqual(SpectroscopyRoomController.scale(of: [-2, 5, 3]), 5)
        XCTAssertEqual(SpectroscopyRoomController.scale(of: [-1, -3]), 0, "no positive pixel: drawn all zeros, scale 0")
        XCTAssertEqual(SpectroscopyRoomController.scale(of: []), 0)
    }

    /// The room sets it on each tile, in the map's own unit: integrated counts are at least the net ones.
    /// Mutation: `scale:` not passed in `apply` (stays 1) - red.
    func testTilesCarryTheirScaleInTheMapsUnit() async throws {
        let (_, c) = open()
        c.model.elements.set(Al, .quantify); c.elementsChanged()
        try await waitFor("Al's tile") { c.model.tiles.contains { $0.z == self.Al } }
        let net = try XCTUnwrap(c.model.tiles.first { $0.z == Al })
        XCTAssertGreaterThan(net.scale, 1, "counts, not the default 1")
        XCTAssertEqual(net.values.max() ?? 0, 1, accuracy: 1e-6, "the picture is normalised to that maximum")
        c.model.mapMode = .integrated
        c.refresh()
        try await waitFor("the integrated tile") { (c.model.tiles.first { $0.z == self.Al }?.scale ?? 0) > net.scale }
        let integrated = try XCTUnwrap(c.model.tiles.first { $0.z == Al })
        XCTAssertGreaterThanOrEqual(integrated.scale, net.scale)
    }
}
