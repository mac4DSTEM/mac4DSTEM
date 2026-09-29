import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// S23 (2026-09-30 night): the origin fit's robust-trim mask
/// (`OriginMaps.originValidity`, ADR 033) reaches the real-space pane as data.
/// Core turns it into row runs plus a caption (`FitOverlays.originTrimOverlay`);
/// `FitOverlayPresentation.originTrim` gates it; the pane only draws the runs.
/// These pin the pixel rule (exactly the excluded positions, nothing else), the
/// row-wrap edge, the caption's counts, every "no overlay" case, and the gating.
final class OriginValidityOverlayTests: XCTestCase {

    private let descriptor = DatasetDescriptor(
        filePath: "/tmp/trim.h5", datasetPath: "/data",
        shape: [4, 5, 32, 32], dtypeDescription: "float32", chunkShape: nil
    )

    /// 5 wide, 4 high. Excluded: the LAST pixel of row 0 and the FIRST of row 1
    /// (adjacent in memory, not in the image — runs must not merge across the
    /// row wrap), a 3-run in row 2, and one isolated pixel in row 3.
    private func mask() -> [Bool] {
        var kept = [Bool](repeating: true, count: 20)
        for (x, y) in [(4, 0), (0, 1), (1, 2), (2, 2), (3, 2), (2, 3)] { kept[y * 5 + x] = false }
        return kept
    }

    private func maps(validity: [Bool]?, width: Int = 5, height: Int = 4) -> OriginMaps {
        let n = width * height
        return OriginMaps(width: width, height: height, measuredX: nil, measuredY: nil,
                          fittedX: [Float](repeating: 16, count: n),
                          fittedY: [Float](repeating: 16, count: n),
                          excludedFraction: validity.map { v in
                              Float(v.filter { !$0 }.count) / Float(max(v.count, 1)) },
                          originValidity: validity)
    }

    /// Rasterise the overlay the way the pane draws it: every run, nothing else.
    private func drawn(_ overlay: FitOverlays.OriginTrimOverlay) -> [Bool] {
        var greyed = [Bool](repeating: false, count: overlay.width * overlay.height)
        for run in overlay.runs {
            for x in run.x..<(run.x + run.length) { greyed[run.y * overlay.width + x] = true }
        }
        return greyed
    }

    // MARK: The pixel rule

    func testTheOverlayGreysExactlyTheExcludedPositions() throws {
        let kept = mask()
        let overlay = try XCTUnwrap(FitOverlays.originTrimOverlay(
            origins: maps(validity: kept), scanWidth: 5, scanHeight: 4))
        XCTAssertEqual(drawn(overlay), kept.map { !$0 },
                       "a greyed pixel is an excluded position and an excluded position is greyed")
        XCTAssertEqual(overlay.excluded, 6)
        XCTAssertEqual(overlay.total, 20)
    }

    func testARunNeverContinuesAcrossTheRowWrap() throws {
        let overlay = try XCTUnwrap(FitOverlays.originTrimOverlay(
            origins: maps(validity: mask()), scanWidth: 5, scanHeight: 4))
        for run in overlay.runs {
            XCTAssertLessThanOrEqual(run.x + run.length, overlay.width,
                                     "run \(run) leaves its row")
        }
        // (4,0) and (0,1) are memory-adjacent; they are two runs, in two rows.
        XCTAssertEqual(overlay.runs.filter { $0.y <= 1 }.count, 2)
        XCTAssertEqual(overlay.runs.count, 4)
    }

    func testTheCaptionStatesTheCountsTheMaskHolds() throws {
        let overlay = try XCTUnwrap(FitOverlays.originTrimOverlay(
            origins: maps(validity: mask()), scanWidth: 5, scanHeight: 4))
        XCTAssertEqual(overlay.caption,
                       "6 of 20 positions excluded by the origin fit\u{2019}s robust trim")
    }

    // MARK: No mask, no claim

    func testNoOverlayWithoutAMaskOrWithNothingExcluded() {
        XCTAssertNil(FitOverlays.originTrimOverlay(origins: nil, scanWidth: 5, scanHeight: 4))
        XCTAssertNil(FitOverlays.originTrimOverlay(
            origins: maps(validity: nil), scanWidth: 5, scanHeight: 4),
                     "an imported or restored origin has no trim history: no mask, nothing drawn")
        XCTAssertNil(FitOverlays.originTrimOverlay(
            origins: maps(validity: [Bool](repeating: true, count: 20)),
            scanWidth: 5, scanHeight: 4),
                     "excluding nothing draws nothing")
    }

    func testNoOverlayWhenTheMaskDoesNotMatchTheScan() {
        XCTAssertNil(FitOverlays.originTrimOverlay(
            origins: maps(validity: mask()), scanWidth: 4, scanHeight: 5),
                     "same count, transposed scan: a wrong picture is worse than none")
        XCTAssertNil(FitOverlays.originTrimOverlay(
            origins: maps(validity: [false, true, true]), scanWidth: 5, scanHeight: 4),
                     "a mask of the wrong length is not the scan's mask")
    }

    // MARK: From a real robust fit

    func testARealTrimmedFitsMaskIsWhatTheOverlayDraws() throws {
        let width = 8, height = 6
        var x = [Float](repeating: 0, count: width * height)
        var y = x
        for row in 0..<height {
            for col in 0..<width {
                x[row * width + col] = 20 + 0.1 * Float(col)
                y[row * width + col] = 30 + 0.2 * Float(row)
            }
        }
        for index in [3, 17, 40] { x[index] += 9; y[index] -= 7 }   // gross outliers
        let fit = OriginCalibration.fitOriginTrimmed(
            measuredX: x, measuredY: y, width: width, height: height)
        let origins = OriginMaps(
            width: width, height: height, measuredX: x, measuredY: y,
            fittedX: fit.fittedX, fittedY: fit.fittedY,
            excludedFraction: fit.excludedFraction, robustResidual: fit.keptResidual,
            originValidity: fit.kept)
        let overlay = try XCTUnwrap(FitOverlays.originTrimOverlay(
            origins: origins, scanWidth: width, scanHeight: height))
        XCTAssertEqual(drawn(overlay), fit.kept.map { !$0 })
        for planted in [3, 17, 40] {
            XCTAssertTrue(drawn(overlay)[planted], "planted outlier \(planted) must be greyed")
        }
        let fraction = try XCTUnwrap(fit.excludedFraction)
        XCTAssertEqual(Float(overlay.excluded) / Float(overlay.total), fraction,
                       accuracy: 1e-6, "the drawing and the disclosed fraction cannot disagree")
    }

    // MARK: Gating (Prepare, the Fit-overlay toggle, the calibration's own maps)

    private func snapshot(enabled: Bool = true, inPrepare: Bool = true,
                          origins: OriginMaps?) -> FitOverlayPresentation {
        var calibration = Calibration()
        calibration.origin = origins
        return FitOverlayPresentation(
            enabled: enabled, analysis: .other, inPrepare: inPrepare,
            showsCurrentPattern: true, pointSelection: true,
            descriptor: descriptor, selectedX: 0, selectedY: 0,
            calibration: calibration)
    }

    func testThePresentationHandsThePaneTheCalibrationsOwnMask() throws {
        let kept = mask()
        let shown = try XCTUnwrap(snapshot(origins: maps(validity: kept)).originTrim)
        XCTAssertEqual(drawn(shown), kept.map { !$0 })
    }

    func testTheWashFollowsTheFitOverlayToggleAndThePrepareWorkspace() {
        let origins = maps(validity: mask())
        XCTAssertNil(snapshot(enabled: false, origins: origins).originTrim,
                     "the user's Fit overlay toggle turns it off")
        XCTAssertNil(snapshot(inPrepare: false, origins: origins).originTrim,
                     "the trim is judged in Prepare; other workspaces show their own products unmarked")
        XCTAssertNotNil(snapshot(origins: origins).originTrim)
        XCTAssertNil(snapshot(origins: maps(validity: nil)).originTrim)
    }
}
