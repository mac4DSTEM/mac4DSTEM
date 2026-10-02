//
//  PolishHTests.swift
//  Lane H (Slot 4½ polish, owner card S7a): wording in the frozen shell.
//

import XCTest
@testable import mac4DSTEM

final class PolishHTests: XCTestCase {
    func testDPCVerbIsReRunOnceDPCRan() {
        XCTAssertEqual(PrimaryActionButton.dpcActionTitle(hasRun: false), "Run DPC")
        XCTAssertEqual(PrimaryActionButton.dpcActionTitle(hasRun: true), "Re-run DPC")
    }

    func testOnePositionIsSingular() {
        XCTAssertEqual(ToolbarDisplayFormat.idle(file: "a.h5", room: "Prepare", positions: 1), "a.h5 · Prepare · 1 position")
        XCTAssertTrue(ToolbarDisplayFormat.idle(file: "a.h5", room: "Prepare", positions: 2).hasSuffix("2 positions"))
    }

    /// The glance is Finder-style (1000-based): 1000 decimal MB is "1.0 GB", not "1000 MB".
    func testGlanceUsesTheDecimalBase() {
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1000, residency: true), "1.0 GB · resident")
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 999, residency: false), "999 MB · streaming")
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 16965, residency: true), "17.0 GB · resident")
        XCTAssertEqual(OperationMetricsFormat.glance(residentMB: 1_200_000, residency: true), "1.2 TB · resident")
    }
}
