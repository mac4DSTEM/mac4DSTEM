import XCTest
@testable import mac4DSTEM

/// v2 S8's seam (`App/StrainProduct.swift`): the one owner of the strain
/// product and its run controls. These pin the seam's contracts — publish
/// reconciles the failure state and adopts an automatic basis, a failed
/// re-run keeps the product on screen, activation clears the product but not
/// the controls, and a component switch reaches the display derivation.
@MainActor
final class StrainProductTests: XCTestCase {

    private func syntheticMap() throws -> StrainMap {
        try XCTUnwrap(StrainFrameTests.syntheticStrainMap())
    }

    func testPublishClearsTheFailureAndAdoptsAnAutomaticBasis() throws {
        let strain = StrainProduct()
        strain.recordFailure(.illConditionedBasis)
        XCTAssertEqual(strain.basisMode, .automatic)
        let map = try syntheticMap()

        strain.publish(map)

        XCTAssertNil(strain.failureCause,
                     "a published result and a failure remedy cannot coexist")
        XCTAssertNotNil(strain.map)
        XCTAssertEqual(strain.g1X, map.refG1.x)
        XCTAssertEqual(strain.g1Y, map.refG1.y)
        XCTAssertEqual(strain.g2X, map.refG2.x)
        XCTAssertEqual(strain.g2Y, map.refG2.y)
    }

    func testPublishUnderAManualBasisDoesNotOverwriteTheUsersVectors() throws {
        let strain = StrainProduct()
        strain.basisMode = .manual
        strain.g1X = 3; strain.g1Y = 4; strain.g2X = -4; strain.g2Y = 3

        strain.publish(try syntheticMap())

        XCTAssertEqual(strain.g1X, 3); XCTAssertEqual(strain.g1Y, 4)
        XCTAssertEqual(strain.g2X, -4); XCTAssertEqual(strain.g2Y, 3)
    }

    func testAFailedRerunKeepsTheProductOnScreen() throws {
        let strain = StrainProduct()
        strain.publish(try syntheticMap())

        strain.recordFailure(.starvedInput(medianPeaks: 1, emptyPercent: 50))

        XCTAssertNotNil(strain.map,
                        "a failed re-run must not destroy the existing result")
        XCTAssertEqual(strain.failureCause,
                       .starvedInput(medianPeaks: 1, emptyPercent: 50))
    }

    func testClearDropsTheProductButPreservesTheRunControls() throws {
        let strain = StrainProduct()
        strain.referenceMode = .selectedRegion
        strain.basisMode = .manual
        strain.g1X = 7
        strain.publish(try syntheticMap())
        strain.recordFailure(.illConditionedBasis)

        strain.clear()

        XCTAssertNil(strain.map)
        XCTAssertNil(strain.failureCause)
        XCTAssertEqual(strain.referenceMode, .selectedRegion,
                       "controls survive activation — pre-seam behavior")
        XCTAssertEqual(strain.basisMode, .manual)
        XCTAssertEqual(strain.g1X, 7)
    }

    func testManualInitialBasisIsNilUnderTheAutomaticMode() {
        let strain = StrainProduct()
        strain.g1X = 1; strain.g1Y = 2; strain.g2X = 3; strain.g2Y = 4
        XCTAssertNil(strain.manualInitialBasis)

        strain.basisMode = .manual
        let basis = strain.manualInitialBasis
        XCTAssertEqual(basis?.g1.x, 1); XCTAssertEqual(basis?.g1.y, 2)
        XCTAssertEqual(basis?.g2.x, 3); XCTAssertEqual(basis?.g2.y, 4)
    }

    func testSwitchingTheComponentSignalsThePresentationChange() {
        let strain = StrainProduct()
        var signalled = 0
        strain.onPresentationChange = { signalled += 1 }

        strain.component = .eyy

        XCTAssertEqual(signalled, 1,
                       "the component picker must reach the display derivation")
    }

    /// Through a real AppState (the S5-F8 lesson: wiring must be pinned where
    /// it lives, not on a lookalike): switching the component while a strain
    /// map is displayed re-derives the image.
    func testComponentSwitchRederivesTheDisplayedImageThroughAppState() throws {
        let state = AppState()
        state.strain.publish(try syntheticMap())
        state.showComputedProduct(.strain)
        let before = state.resultVersion

        state.strain.component = .eyy

        XCTAssertGreaterThan(state.resultVersion, before)
        let image = try XCTUnwrap(state.resultImage)
        let expected = try syntheticMap().component(.eyy)
        for i in 0..<expected.pixels.count where !expected.pixels[i].isNaN {
            XCTAssertEqual(image.pixels[i], expected.pixels[i], accuracy: 1e-6)
        }
    }

    /// Activation clears the product through the seam: pinned via the public
    /// demo-fixture path in `ReplayExecutionTests`-style flows; here the seam
    /// contract itself. The AppState `activate` call site is exercised by the
    /// existing activation tests.
    func testAppStateHoldsTheSeamWithoutForwardingProperties() {
        // @Observable underscores stored properties, so strip the prefix
        // before matching — without this the filter can never match and the
        // test is vacuous (verified by planting `strainMapShadow` and
        // watching it fail only with the strip in place).
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("strain"), "the facade holds the seam")
        let forwarded = names.filter { $0.hasPrefix("strain") && $0 != "strain" }
        XCTAssertTrue(
            forwarded.isEmpty,
            "no strain* stored property may shadow the seam: \(forwarded)"
        )
        // Known limit (Gate B finding 8): Mirror enumerates STORED properties
        // only — a computed forwarder (`var strainMap { strain.map }`) would
        // pass this test. That half of the §7 rule is enforced by review.
    }
}
