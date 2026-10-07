//
//  SwiftUIReviewATests.swift
//  SwiftUI review fixes 2026-10-07, lane A (Metal engine, Metal image view).
//
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

final class SwiftUIReviewATests: XCTestCase {

    /// A1: the six compute pipelines are built once in `MetalEngine.init`
    /// (immutable `let`s, no `lazy var` first-touch race). On this Mac every
    /// shipped kernel must have built; a nil would be refused by name at use.
    func testEveryComputePipelineIsBuiltAtEngineInit() {
        let e = MetalEngine.shared
        XCTAssertNotNil(e.virtualAperturePSO, "virtualAperture")
        XCTAssertNotNil(e.virtualMaskPSO, "virtualMaskSum")
        XCTAssertNotNil(e.virtualDiffractionPSO, "virtualDiffraction")
        XCTAssertNotNil(e.dpStatisticsPSO, "dpStatistics")
        XCTAssertNotNil(e.measureOriginPSO, "measureOrigin")
        XCTAssertNotNil(e.centerOfMassPSO, "centerOfMass")
    }

    // MARK: A2 - MetalImageView update gating

    private func view(version: Int = 1, width: Int = 4, height: Int = 3,
                      colormap: ColormapKind = .viridis, lo: Float = 0, hi: Float = 1,
                      gamma: Float = 1, rgba: [UInt8]? = nil) -> MetalImageView {
        MetalImageView(pixels: [], width: width, height: height, contentVersion: version,
                       colormap: colormap, rgba: rgba, displayLo: lo, displayHi: hi, gamma: gamma)
    }

    /// An update that changes nothing the pane shows must compare equal (no
    /// redraw); each field that does change what is drawn must break equality.
    func testAppliedStateIsEqualOnlyWhenNothingDrawnChanged() {
        let base = view().appliedState
        XCTAssertEqual(base, view().appliedState, "identical update: skip the redraw")
        XCTAssertNotEqual(base, view(version: 2).appliedState, "new texture content")
        XCTAssertNotEqual(base, view(width: 5).appliedState, "width")
        XCTAssertNotEqual(base, view(height: 4).appliedState, "height")
        XCTAssertNotEqual(base, view(colormap: .gray).appliedState, "colormap")
        XCTAssertNotEqual(base, view(lo: 0.1).appliedState, "display low")
        XCTAssertNotEqual(base, view(hi: 0.9).appliedState, "display high")
        XCTAssertNotEqual(base, view(gamma: 2).appliedState, "gamma")
        XCTAssertNotEqual(base, view(rgba: [0, 0, 0, 0]).appliedState, "scalar to RGBA")
    }

    /// The shader sees `max(gamma, 0.05)`, so two raw gammas that clamp to the
    /// same value draw the same frame and compare equal.
    func testAppliedStateUsesTheClampedGamma() {
        XCTAssertEqual(view(gamma: 0.01).appliedState, view(gamma: 0.0).appliedState)
        XCTAssertNotEqual(view(gamma: 0.01).appliedState, view(gamma: 0.2).appliedState)
    }

    /// The coordinator starts with no applied state, so the first update draws.
    func testCoordinatorStartsWithNoAppliedStateSoTheFirstUpdateDraws() {
        let c = MetalImageView.Coordinator()
        XCTAssertNil(c.lastApplied)
        XCTAssertNotEqual(c.lastApplied, view().appliedState)
    }

    /// Re-assigning the colormap SwiftUI already handed over (every update
    /// does) must not mark the LUT dirty; a real change must.
    func testSameColormapDoesNotDirtyTheLUT() {
        let c = MetalImageView.Coordinator()
        c.rebuildLUTIfNeeded()
        XCTAssertFalse(c.lutDirty, "built once")
        c.colormap = .viridis
        XCTAssertFalse(c.lutDirty, "same value: no rebuild, no new texture")
        c.colormap = .gray
        XCTAssertTrue(c.lutDirty, "a real change rebuilds")
    }
}
