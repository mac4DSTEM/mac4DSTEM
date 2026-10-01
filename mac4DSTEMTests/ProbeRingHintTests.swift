//
//  ProbeRingHintTests.swift
//  The ring-shaped-probe hint (owner, 2026-10-01, card "Kernel", option c):
//  the estimator is nil on a solid disk and reads the outer edge of a
//  bullseye; the click sets the probe radius as a manual value; and nothing
//  moves by default — the estimate `probeSize` gives (what every default
//  derives from) is untouched by the hint.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ProbeRingHintTests: XCTestCase {
    private let q = 128

    /// Radial pattern about (64, 64): `value(r)` per integer radius.
    private func pattern(_ value: (Double) -> Float) -> [Float] {
        var px = [Float](repeating: 0, count: q * q)
        for y in 0..<q { for x in 0..<q {
            px[y * q + x] = value(hypot(Double(y) - 64, Double(x) - 64))
        } }
        return px
    }

    private var solid: [Float] { pattern { $0 < 8 ? 1 : 0 } }
    /// Core to r 4, dark gap to 7, ring 8...11 at 0.8: probeSize stops at the
    /// first shoulder, the outer edge is 12 (bin after the last >= 20 %).
    private var bullseye: [Float] { pattern { $0 < 4 ? 1 : ($0 < 8 ? 0 : ($0 < 12 ? 0.8 : 0)) } }

    /// Mutation: drop the dip test (`dip / peak < 0.25`) -> the solid disk
    /// returns its own edge and this goes red.
    func testSolidDiskReturnsNil() {
        XCTAssertNil(ProbeRingHint.outerEdge(meanDP: solid, qy: q, qx: q))
    }

    /// Mutation: read the first shoulder instead of the last >= 20 % bin (or
    /// return `probe.r`) -> red.
    func testBullseyeReturnsItsOuterEdge() throws {
        let hint = try XCTUnwrap(ProbeRingHint.outerEdge(meanDP: bullseye, qy: q, qx: q))
        XCTAssertEqual(hint.outerRadius, 12, accuracy: 1)
        XCTAssertLessThan(hint.dip, 0.25)
        let probe = try XCTUnwrap(OriginCalibration.probeSize(dp: bullseye, qy: q, qx: q))
        XCTAssertLessThan(probe.r, hint.outerRadius - 2, "the estimator the defaults use reads the shoulder, untouched by the hint")
        XCTAssertTrue(ProbeRingHint.isWorthOffering(hint, current: probe.r))
        XCTAssertFalse(ProbeRingHint.isWorthOffering(hint, current: hint.outerRadius))
    }

    /// Mutation: remove the min(qx, qy)/8 guard -> a 64 px detector with the
    /// same ring (edge 12 > 8) offers a hint and this goes red.
    func testRingTooLargeForTheDetectorReturnsNil() {
        let n = 64
        var px = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let r = hypot(Double(y) - 32, Double(x) - 32)
            px[y * n + x] = r < 4 ? 1 : (r < 8 ? 0 : (r < 12 ? 0.8 : 0))
        } }
        XCTAssertNil(ProbeRingHint.outerEdge(meanDP: px, qy: n, qx: n))
    }

    /// Mutation: not recording `.manual`, or not setting the radius -> red.
    func testClickSetsTheRadiusAsAManualValue() async {
        let state = AppState()
        XCTAssertNil(state.calibrationSession.calibration.probeRadius)
        await state.useProbeRadius(11)
        XCTAssertEqual(state.calibrationSession.calibration.probeRadius, 11)
        XCTAssertEqual(state.calibrationSession.provenance.probe, .manual)
        await state.useProbeRadius(.nan)   // refused
        XCTAssertEqual(state.calibrationSession.calibration.probeRadius, 11)
    }

    /// Nothing moves by default: a fresh state holds no radius, no kernel,
    /// and the stock detection parameters.
    func testNoDefaultMoves() {
        let state = AppState()
        XCTAssertNil(state.calibrationSession.calibration.probeRadius)
        XCTAssertNil(state.probeKernel)
        XCTAssertNil(state.calibrationSession.provenance.probe)
        XCTAssertEqual(state.diskDetection.diskParams, DiskDetectionParams())
    }
}
