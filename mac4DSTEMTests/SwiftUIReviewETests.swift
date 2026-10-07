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
                                                   integrated: false, beam: 200, quantify: q)
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

    // MARK: E3 - observation

    /// Counts the changes of whatever `read` reads, each one synchronously as it is made (the tracking re-arms itself).
    private final class ChangeCounter: @unchecked Sendable {
        let read: () -> Void
        var changes = 0
        init(_ read: @escaping () -> Void) { self.read = read }
        func arm() { withObservationTracking(read) { [self] in changes += 1; arm() } }
    }
    private func countChanges(_ read: @escaping () -> Void) -> ChangeCounter {
        let counter = ChangeCounter(read)
        counter.arm()
        return counter
    }

    /// A tile's smoothing change is told to the views once, not twice per tile (values, scale).
    /// Mutation: `smoothingChanged` writing `m.tiles[i]` in the loop again - red (2 per tile).
    func testSmoothingTheTilesIsOneChangeNotOnePerTile() {
        let c = SpectroscopyRoomController(); let m = c.model
        let counts: [Double] = (0..<12).map { Double($0 % 5) - 1 }
        m.tiles = [13, 12, 14].map { MapTile(z: $0, width: 4, height: 3, values: [Float](repeating: 0, count: 12), counts: counts) }
        m.smoothing = .none
        let seen = countChanges { _ = m.tiles }
        c.smoothingChanged()
        XCTAssertEqual(seen.changes, 1, "three tiles, one notification")
        let expected = SpectroscopyRoomController.display(of: counts, width: 4, height: 3, smoothing: m.smoothing)
        XCTAssertTrue(m.tiles.allSatisfy { $0.values == expected.values && $0.scale == expected.scale }, "every tile follows")
    }

    /// The Region section reads the phase only: a spectrum landing and a region edit write nothing it observes.
    /// Mutation: `apply` (or the live tick) writing `m.regionSettings` again - red.
    func testLandingASpectrumDoesNotTouchTheRegionSectionsSettings() async throws {
        let c = openRoom()
        let m = c.model
        try await waitFor("the first spectrum") { ExportSection.canExportSpectrum(m.export) }
        await c.lastRefresh?.value
        let seen = countChanges { _ = m.regionSettings.phase }
        let rect = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 4, y1: 3))
        c.editRegion(rect, final: false)
        c.editRegion(rect, final: true)
        try await waitFor("the region's spectrum") { m.spectrumTitle == "Spectrum \u{00B7} Region 1" && !m.spectrumSubtitle.hasSuffix("live") }
        await c.lastRefresh?.value
        XCTAssertEqual(seen.changes, 0, "no write to regionSettings on a landing")
    }
}
