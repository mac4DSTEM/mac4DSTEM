//
//  PrecipitateClassificationProductTests.swift
//  The Session seam for the pre-registered diffraction-classification route.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// The owner is intentionally only a retained-result seam so far: no UI,
/// export, classifier, or validation claim exists until the registered ship
/// gate has been met. These tests pin its lifetime and AppState composition.
@MainActor
final class PrecipitateClassificationProductTests: XCTestCase {

    private func classMap() -> PrecipitateSegmentation.ClassMapObjects {
        PrecipitateSegmentation.classObjects(
            labels: [0, 1, 1, -1], width: 2, height: 2,
            roles: .init(precipitateClasses: [1], matrix: [0], notIndexed: [-1]),
            pixelSize: nil, pixelUnit: nil
        )
    }

    func testPublishRetainsTheSpatialClassResultUntilDatasetClear() {
        let product = PrecipitateClassificationProduct()
        let result = classMap()

        XCTAssertNil(product.result)
        product.publish(result)
        XCTAssertEqual(product.result, result)

        product.clear()
        XCTAssertNil(product.result, "a classified scan result dies with its dataset")
    }

    func testAppStateOwnsTheClassificationSeamWithoutForwardingProperties() {
        // @Observable underscores stored properties, so normalise the names
        // before looking for a shadow. A computed forwarder remains review's
        // responsibility, as in the established product-seam tests.
        let names = Mirror(reflecting: AppState()).children.compactMap { child in
            child.label.map { $0.hasPrefix("_") ? String($0.dropFirst()) : $0 }
        }
        XCTAssertTrue(names.contains("precipitateClassification"),
                      "AppState composes the Session owner")
        let forwarded = names.filter {
            $0.hasPrefix("precipitateClassification") && $0 != "precipitateClassification"
        }
        XCTAssertTrue(forwarded.isEmpty,
                      "no classification state may shadow the Session owner: \(forwarded)")
    }
}
