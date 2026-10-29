//
//  OriginNonFiniteRow24Tests.swift
//  Lane F-B row 24 (archived docs/archive/v4/review-2026-09-30-findings.md): neither origin path
//  sanitised non-finite pixels (detection does since D019, DiskDetector.fillNonFinite).
//  Fixture: a flat disk, one NaN inside it; the origin must equal the clean run's. Since CuboKit 0.7.0 the per-position
//  origin is the kit's iterated-window estimator, which reads a non-finite pixel as the median of its finite 8 neighbours,
//  so this pins that the app's path (`VirtualDetector.measureIteratedWindow`, Metal) keeps the property.
//

import XCTest
import CuboCore
import CuboVirtual
import DSTEMCore
@testable import mac4DSTEM

final class OriginNonFiniteRow24Tests: XCTestCase {

    private let size = 40
    private let centre = (x: 19.3, y: 20.6), radius = 6.0

    private func disk() -> [Float] {
        var p = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size
            where hypot(Double(x) - centre.x, Double(y) - centre.y) <= radius {
                p[y * size + x] = 100
            }
        }
        return p
    }

    private func metalOrigin(_ pattern: [Float]) async throws -> (x: Float, y: Float) {
        let cube = try MemoryCube(shape: try CubeShape([1, 1, size, size]), values: pattern)
        let map = try await VirtualDetector.measureIteratedWindow(
            cube, radius: 6, scale: 1.2, tiling: .automatic)
        return (Float(map.column.values[0]), Float(map.row.values[0]))
    }

    /// The NaN sits at the disk's centre pixel, in the beam's coarse block.
    private var nanIndex: Int { 21 * size + 19 }

    func testRow24MetalOriginIgnoresANonFinitePixelInTheBeam() async throws {
        let clean = try await metalOrigin(disk())
        XCTAssertEqual(Double(clean.x), centre.x, accuracy: 0.3, "the clean fixture finds the beam")
        var bad = disk()
        bad[nanIndex] = .nan
        let dirty = try await metalOrigin(bad)
        XCTAssertEqual(dirty.x, clean.x, accuracy: 1e-4)
        XCTAssertEqual(dirty.y, clean.y, accuracy: 1e-4)
        bad[nanIndex] = .infinity
        let inf = try await metalOrigin(bad)
        XCTAssertEqual(inf.x, clean.x, accuracy: 1e-4)
        XCTAssertEqual(inf.y, clean.y, accuracy: 1e-4)
    }
}
