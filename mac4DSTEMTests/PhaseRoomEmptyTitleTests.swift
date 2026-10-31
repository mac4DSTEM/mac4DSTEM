//
//  PhaseRoomEmptyTitleTests.swift
//  An empty phase-contrast room is titled for its own product, not the other
//  room's: the single-slice ptychography pane read "Parallax aligned BF"
//  before any run, after a parallax alignment.
//
//  The two rooms share one remembered product (`parallaxResultProduct`). With
//  no product on screen the pane title falls back to the mode's metadata,
//  which read that shared value whatever the room.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class PhaseRoomEmptyTitleTests: XCTestCase {

    private func parallaxProduct() -> DisplayedProduct {
        DisplayedProduct(
            kind: "parallax_alignment", displayName: "Parallax aligned BF",
            payload: .scalar(FloatImage(width: 2, height: 2, pixels: [0, 0, 0, 0])), domain: .scan,
            validityMask: nil, qualityFields: [],
            sampling: ProductSampling(row: nil, column: nil, units: nil),
            valueUnits: "normalized_intensity", quantitativeStatus: .relative, provenance: [:], overlays: [])
    }

    /// Mutation it catches: the metadata reads the shared remembered product
    /// in the single-slice room (the pane says "Parallax aligned BF").
    func testTheSingleSliceRoomBeforeARunIsTitledForPtychography() {
        let state = AppState()
        state.phaseContrast.parallaxResultProduct = .alignment
        state.resultPresentation.publish(parallaxProduct())
        state.changeMode(.singleslicePtychography)

        XCTAssertNil(state.resultPresentation.product, "no ptychography yet: the pane is empty")
        XCTAssertFalse(state.displayedResultName.hasPrefix("Parallax"), "title was \(state.displayedResultName)")
        XCTAssertEqual(state.displayedResultName, "Ptychography object phase")
        XCTAssertTrue(state.currentResultKind.hasPrefix("ptychography_"), state.currentResultKind)
        XCTAssertEqual(state.phaseContrast.parallaxResultProduct, .alignment,
                       "the parallax room keeps its remembered product for the way back")
    }

    /// The other direction: an iterative product remembered from the
    /// single-slice room does not title the empty parallax room.
    func testTheParallaxRoomBeforeARunIsTitledForParallax() {
        let state = AppState()
        state.phaseContrast.parallaxResultProduct = .iterativeAmplitude
        state.changeMode(.ptychography)

        XCTAssertNil(state.resultPresentation.product)
        XCTAssertTrue(state.displayedResultName.hasPrefix("Parallax"), "title was \(state.displayedResultName)")
        XCTAssertTrue(state.currentResultKind.hasPrefix("parallax_"), state.currentResultKind)
    }
}
