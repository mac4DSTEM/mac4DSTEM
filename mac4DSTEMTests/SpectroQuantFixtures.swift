//
//  SpectroQuantFixtures.swift
//  The demo-edx-tiny fixture helpers SpectroGoldenTests reads (they were SpectroscopyQuantifyTests', retired with the old room 2026-10-23).
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore
@testable import SpectroEDX

@MainActor
enum SpectroQuantFixtures {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    /// The six tables as the app reads them: SpectroKit's own copy (`Bundle.module`, inside the app bundle) since S4.
    static let tables = QuantificationTables.bundled()!

    static func image() throws -> LoadedSpectrumImage {
        try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: fixtures.appendingPathComponent("demo-edx-tiny.dm4").path, fourD: nil))
    }

    static func method(elements: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify), ("Cu", .quantify), ("O", .fitOnly), ("Ga", .fitOnly)]) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = elements.map { QuantificationMethod.ElementState(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200          // the GMS EDS object does not state it
        return m
    }

    static func input(_ method: QuantificationMethod, image: LoadedSpectrumImage) -> PooledQuantificationInput {
        PooledQuantificationInput(counts: image.sum(mask: nil), axis: image.energyAxis, method: method, metadata: image.metadata,
                                  regionName: "Whole map", pixelCount: image.metadata.pixelCount)
    }

}
