//
//  FinalPolishMTests.swift
//  Slot 4⅞ lane M (2026-10-04): the status strip's memory figure (P5b), the two
//  File-menu items that need a window (P5d), the fit overlay's legend (P7b) and
//  the parked annulus handle (P7c). Each test names the mutation it catches.
//

import XCTest
import Darwin
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class FinalPolishMTests: XCTestCase {

    // MARK: - P5b: the memory figure is the physical footprint, not resident_size

    /// The old reader's quantity, as the control: `resident_size` in MiB.
    private func residentSizeMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : .nan
    }

    /// Mutation it catches: a reader that returns 0 / a constant, reads a quantity that ignores dirty
    /// memory, or returns the wrong UNIT (decimal MB instead of MiB: 256 MiB would read 268.4, and the
    /// strip, which converts MiB to MB at its call site, would then read 4.9 % high). A deltas test:
    /// the host's own allocations moved the figure by 0.03 MiB in the sibling test's runs, so a
    /// 10 MiB window around the 256 MiB touched is generous and still tells MiB from MB (12.4 apart).
    func testTheMemoryFigureRisesWithDirtyAnonymousPagesInMiB() throws {
        let mib = 256
        let bytes = mib << 20
        let before = SystemMonitor.residentMemoryMB()
        let base = try XCTUnwrap(mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0))
        XCTAssertNotEqual(base, UnsafeMutableRawPointer(bitPattern: -1), "mmap of \(mib) MiB failed")
        defer { _ = munmap(base, bytes) }
        memset(base, 0xA5, bytes)
        let after = SystemMonitor.residentMemoryMB()
        XCTAssertEqual(after - before, Double(mib), accuracy: 10,
                       "\(mib) MiB of touched anonymous memory must show as ~\(mib) in the figure (MiB, not MB): \(before) -> \(after)")
    }

    /// Mutation it catches: the old `resident_size` reader (a 300 MiB file mapping read page by page
    /// raises it by ~300 MiB, and the strip then read "23 GB" for a 16 GiB cube whose footprint was
    /// 3 GB). The control line proves the file pages DID become resident, so the test cannot pass
    /// because the mapping was never touched.
    func testTheMemoryFigureDoesNotCountCleanMappedFilePages() throws {
        let bytes = 300 << 20
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinalPolishM-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        let chunk = Data(repeating: 0x5A, count: 1 << 20)
        for _ in 0..<(bytes >> 20) { try handle.write(contentsOf: chunk) }
        try handle.close()

        let fd = open(url.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        let footprintBefore = SystemMonitor.residentMemoryMB()
        let residentBefore = residentSizeMiB()
        let base = try XCTUnwrap(mmap(nil, bytes, PROT_READ, MAP_PRIVATE, fd, 0))
        XCTAssertNotEqual(base, UnsafeMutableRawPointer(bitPattern: -1), "mmap of the file failed")
        defer { _ = munmap(base, bytes) }
        var sum = 0
        let step = 4096
        for offset in stride(from: 0, to: bytes, by: step) {
            sum &+= Int(base.load(fromByteOffset: offset, as: UInt8.self))
        }
        XCTAssertEqual(sum, (bytes / step) * 0x5A, "every page must have been read")
        let footprintRise = SystemMonitor.residentMemoryMB() - footprintBefore
        let residentRise = residentSizeMiB() - residentBefore
        XCTAssertGreaterThan(residentRise, 200,
                             "control: resident_size must count the mapped file pages (rose \(residentRise) MiB)")
        XCTAssertLessThan(footprintRise, 50,
                          "clean mapped file pages are the page cache's, not the app's (footprint rose \(footprintRise) MiB; resident_size \(residentRise))")
    }

    // MARK: - P5d: Open Dataset… / Preprocess Raw Data… with no window focused

    /// Mutation it catches: `take()` that leaves the action pending (a second window appearing later
    /// would repeat it).
    func testTheRelayHandsAnActionOverOnce() {
        let relay = MenuActionRelay()
        XCTAssertNil(relay.take(), "nothing is pending at the start")
        relay.request(.preprocess)
        XCTAssertEqual(relay.pendingAction, .preprocess)
        XCTAssertEqual(relay.take(), .preprocess)
        XCTAssertNil(relay.take(), "taken once, then gone")
        XCTAssertNil(relay.pendingAction)
    }

    /// Mutation it catches: a request that only sets when nothing is pending (the FIRST gesture wins).
    func testTheLatestRequestWins() {
        let relay = MenuActionRelay()
        relay.request(.openDataset)
        relay.request(.preprocess)
        XCTAssertEqual(relay.take(), .preprocess)
        XCTAssertNil(relay.take())
    }

    /// Mutation it catches: `hasFocusedWindow && !blocked` — the old "appState == nil disables the item"
    /// (no window open, or Settings key, left both greyed out).
    func testTheItemsAreEnabledWithNoFocusedWindowAndBlockedByTheWindowThatHasOne() {
        XCTAssertTrue(MenuActionRelay.isEnabled(hasFocusedWindow: false, blocked: false),
                      "no focused window: the item opens one")
        XCTAssertTrue(MenuActionRelay.isEnabled(hasFocusedWindow: false, blocked: true),
                      "`blocked` describes a window; with none it cannot disable the item")
        XCTAssertTrue(MenuActionRelay.isEnabled(hasFocusedWindow: true, blocked: false))
        XCTAssertFalse(MenuActionRelay.isEnabled(hasFocusedWindow: true, blocked: true),
                       "a loading / busy window still blocks the item")
    }

    /// Mutation it catches: `run` that does nothing, or routes Open Dataset to another request.
    func testRunningOpenDatasetIsTheWindowsOwnOpenRequest() {
        let state = AppState()
        let before = state.openDatasetRequest
        MenuActionRelay.run(.openDataset, in: state)
        XCTAssertEqual(state.openDatasetRequest, before &+ 1, "the open-panel request counter ContentView observes")
        XCTAssertEqual(state.preprocessingExportRequest, 0, "and not the preprocess sheet's")
    }

    // MARK: - P7b: the fit overlay's legend text

    private func strainOverlay(residual: Float?) -> FitOverlays.StrainOverlay {
        let zero = FitOverlays.Vector(fromX: 0, fromY: 0, toX: 1, toY: 0)
        return FitOverlays.StrainOverlay(
            originX: 64, originY: 64, predicted: [], localG1: nil, localG2: nil,
            referenceG1: zero, referenceG2: zero, localResidualPixels: residual)
    }

    private func templateOverlay(reliability: Float) -> FitOverlays.TemplateOverlay {
        FitOverlays.TemplateOverlay(originX: 64, originY: 64, predicted: [], reliability: reliability, score: 0.5)
    }

    /// Mutation it catches: a branch's text changed or dropped (strain with / without a residual,
    /// template), the strain branch no longer winning over the calibration branch, an origin or an
    /// ellipse part lost, the separator changed, or the residual's format changed (1.234 reads 1.23
    /// at `%.3g`, 1.2 at `%.1f`; a round 0.5 could not tell them apart). `String(format:)` is not
    /// locale-aware, so the decimals are the C ones on every Mac.
    func testTheLegendTextBranches() {
        let marker = FitOverlays.Marker(x: 10, y: 10, weight: 1)
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: strainOverlay(residual: 1.234), template: nil,
                                         originPoint: (x: 1, y: 2), ellipse: [marker]),
            "● measured  ✕ local fit  ⇢ reference · residual 1.23 px", "strain with a residual wins (three significant digits)")
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: strainOverlay(residual: nil), template: nil,
                                         originPoint: nil, ellipse: []),
            "● measured · no local fit at this position")
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: nil, template: templateOverlay(reliability: 0.8),
                                         originPoint: (x: 1, y: 2), ellipse: []),
            "● measured  ✕ template · reliability 0.80")
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: nil, template: nil, originPoint: (x: 1, y: 2), ellipse: [marker]),
            "✚ fitted origin · ◌ fitted ellipse")
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: nil, template: nil, originPoint: (x: 1, y: 2), ellipse: []),
            "✚ fitted origin")
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: nil, template: nil, originPoint: nil, ellipse: [marker]),
            "◌ fitted ellipse")
    }

    /// Mutation it catches: a non-empty fallback when nothing is fitted (the pane hides the chip exactly
    /// when this string is empty, and shows the overlay exactly when it is not).
    func testTheLegendTextIsEmptyWhenNothingIsFitted() {
        XCTAssertEqual(
            PatternFitOverlay.legendText(strain: nil, template: nil, originPoint: nil, ellipse: []), "")
    }

    // MARK: - P7c: the parked inner handle sits 1.5 handle diameters out

    /// Mutation it catches: the parking distance back at one diameter (the cyan handle exactly touching
    /// the centre ⊕), or a parking distance that is not carried through the pane's points-per-pixel.
    func testTheParkedInnerHandleSitsOneAndAHalfDiametersFromTheCentre() {
        XCTAssertEqual(ApertureHandleRules.parkingDiameters, 1.5)
        for radiusScale in [CGFloat(0.5), 1, 2.25, 4] {
            let minimum = ApertureHandleRules.parkedMinimum(handleDiameter: 12, radiusScale: radiusScale)
            XCTAssertEqual(Double(minimum), 18 / Double(radiusScale), accuracy: 1e-5, "detector px at scale \(radiusScale)")
            // Drawn at the pane's points: the offset times the scale is 18 pt, a 6 pt gap between two 12 pt handles.
            let parked = ApertureHandleRules.innerHandleOffset(inner: 0, minimum: minimum)
            XCTAssertEqual(Double(parked) * Double(radiusScale), 18, accuracy: 1e-4)
        }
        // A real radius larger than the parking distance is drawn where it is.
        let minimum = ApertureHandleRules.parkedMinimum(handleDiameter: 12, radiusScale: 2)
        XCTAssertEqual(ApertureHandleRules.innerHandleOffset(inner: 20, minimum: minimum), 20)
    }
}
