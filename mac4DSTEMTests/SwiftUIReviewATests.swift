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
}
