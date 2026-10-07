//
//  SwiftUIReviewETests.swift
//  SwiftUI review fixes, lane E (the Spectroscopy room controller): a superseded recompute is cancelled between its stages (E1),
//  the spectrum CSV is built when it is exported (E2), the observed settings carry only what a view reads (E3).
//  Every test names the mutation it catches; each was broken once and seen red (the lane report lists them).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Counts how often the compute polls for cancellation (the stages that ask).
private final class PollCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    private var trueAt: Int?
    init(cancelAtPoll: Int? = nil) { trueAt = cancelAtPoll }
    var polls: Int { lock.lock(); defer { lock.unlock() }; return n }
    func poll() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = n; n += 1
        return trueAt.map { now >= $0 } ?? false
    }
}

@MainActor
final class SwiftUIReviewETests: XCTestCase {
    /// The states stay alive for the test: the controller holds its session weakly.
    private var keep: [AppState] = []

    // MARK: E1 - a superseded recompute is cancelled

    private func request(quantify: Bool, region: Int = 0) throws -> (SpectroscopyRoomController.Request, SpectrumComputeCache) {
        let image = try SpectroscopyQuantifyTests.image()
        var sel = ElementSelection()
        for z in [13, 12, 14, 29] { sel.set(z, .quantify) }
        var q: SpectroscopyRoomController.QuantifyRequest?
        if quantify {
            q = SpectroscopyRoomController.QuantifyRequest(method: SpectroscopyQuantifyTests.method(), metadata: image.metadata,
                                                           regionName: "Whole map", pixelCount: image.metadata.pixelCount)
        }
        let r = SpectroscopyRoomController.Request(source: image, region: region, mask: nil, picks: SpectroscopyRoomController.picks(for: sel),
                                                   integrated: false, beam: 200, firstPass: true, quantify: q)
        return (r, SpectrumComputeCache())
    }

    /// A recompute that is cancelled lands nothing, and it is asked at every stage: sum, maps, fit, comparison fit, the end.
    /// A cancel at poll k (for every k the recompute makes) returns nil; one that is never cancelled returns its output.
    /// Mutation: any one `cancelled()` poll in `compute` removed (or all of them) - red.
    func testACancelledRecomputeReturnsNothingAtEveryStage() throws {
        for withFit in [false, true] {
            let (r, cache) = try request(quantify: withFit)
            let counter = PollCounter()
            XCTAssertNotNil(SpectroscopyRoomController.compute(r, cache: cache, cancelled: counter.poll), "never cancelled: the output")
            let stages = counter.polls
            XCTAssertGreaterThanOrEqual(stages, 4, "start, after the sums, after the maps, the end")
            for k in 0..<stages {
                let (r2, cache2) = try request(quantify: withFit)
                let c = PollCounter(cancelAtPoll: k)
                XCTAssertNil(SpectroscopyRoomController.compute(r2, cache: cache2, cancelled: c.poll), "cancelled at poll \(k) of \(stages) (fit: \(withFit))")
            }
        }
    }

    /// The comparison fit of a region (the whole map under the same method) is a stage of its own: it is not started once cancelled.
    /// Mutation: the `!cancelled()` guard on the whole-map comparison removed - red.
    func testACancelledRecomputeSkipsTheComparisonFit() throws {
        // Count the polls of a region recompute with a fit: there is one more poll than for the whole map (the comparison guard).
        let (whole, c1) = try request(quantify: true, region: 0)
        let wc = PollCounter(); _ = SpectroscopyRoomController.compute(whole, cache: c1, cancelled: wc.poll)
        let (region, c2) = try request(quantify: true, region: 3)
        let rc = PollCounter(); _ = SpectroscopyRoomController.compute(region, cache: c2, cancelled: rc.poll)
        XCTAssertEqual(rc.polls, wc.polls + 1, "the comparison fit asks before it starts")
    }

    /// An edit during the Quantify verb cancels the fit in flight; the verb waits for the newest recompute and reports the fit
    /// that stands (the edit's), with `isFitting` cleared by that one landing, not left on by the cancelled one.
    /// Mutation: the verb stops waiting after the first task (`awaitNewestRefresh` without its loop) - red.
    func testTheVerbReportsTheNewestFitAfterAnEditCancelledTheFirst() async throws {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(try SpectroscopyQuantifyTests.image())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        let c = state.spectroscopyRoom
        for z in [13, 12, 14, 29] { c.model.elements.set(z, .quantify) }
        c.elementsChanged()
        c.model.quantify.beamEnergy = 200
        let verb = Task { await c.quantify() }
        await Task.yield()   // the verb has started its fit and waits on it
        let first = try XCTUnwrap(c.lastRefresh)
        c.model.elements.set(29, .off)   // the edit: a new recompute, which cancels the first
        c.elementsChanged()
        XCTAssertTrue(first.isCancelled, "the superseded recompute was cancelled")
        let ok = await verb.value
        XCTAssertTrue(ok, c.model.fitFailure ?? "the verb reports the fit that stands")
        XCTAssertFalse(c.model.isFitting)
        await c.checkTask?.value
        let symbols = c.model.results.map { PeriodicLayout.symbol($0.z) }
        XCTAssertFalse(symbols.contains("Cu"), "the standing fit is the edit's: \(symbols)")
        XCTAssertTrue(symbols.contains("Al"))
    }

    /// Unbinding cancels the recompute in flight.
    /// Mutation: `lastRefresh?.cancel()` removed from `unbind` - red.
    func testUnbindCancelsTheRecomputeInFlight() throws {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        let c = state.spectroscopyRoom
        c.autoIDOnOpen?.cancel()
        let task = try XCTUnwrap(c.lastRefresh)
        c.unbind()
        XCTAssertTrue(task.isCancelled)
    }

    // MARK: E2 - the spectrum CSV is built when it is exported

    private func openRoom() -> SpectroscopyRoomController {
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        return state.spectroscopyRoom
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The export is the CSV of the series shown when the button is pressed, with the file and region of the label: the same text
    /// `SpectrumCSV.text` gives for the shown series (no stored copy to go stale), off until a spectrum is shown.
    /// Mutation: `spectrumExport` handing out a text captured earlier (a stored copy) instead of the shown series - red;
    /// `canExportSpectrum` always true - red.
    func testTheSpectrumCSVIsBuiltFromTheShownSeriesWhenExported() async throws {
        let c = openRoom()
        XCTAssertFalse(ExportSection.canExportSpectrum(SpectroscopyRoomController().model.export), "no spectrum, no export")
        XCTAssertNil(ExportSection.spectrumExport(SpectroscopyRoomController().model))
        try await waitFor("the first spectrum") { ExportSection.canExportSpectrum(c.model.export) }
        let m = c.model
        let first = try XCTUnwrap(ExportSection.spectrumExport(m))
        XCTAssertEqual(first.text, SpectrumCSV.text(m.series, imageName: "synthetic", regionName: "Whole map"))
        XCTAssertEqual(first.name, "synthetic_Whole_map-spectrum")
        // The series changes with no controller call (a live tick lands only the series): the next export is the changed series.
        m.series.data[0] += 7
        let second = try XCTUnwrap(ExportSection.spectrumExport(m))
        XCTAssertNotEqual(second.text, first.text)
        XCTAssertEqual(second.text, SpectrumCSV.text(m.series, imageName: "synthetic", regionName: "Whole map"))
    }
}
