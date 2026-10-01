//
//  OriginNonFiniteRow24Tests.swift
//  Lane F-B row 24 (docs/archive/v4/review-2026-09-30-findings.md): neither origin path
//  sanitised non-finite pixels (detection does since D019, DiskDetector.fillNonFinite).
//  Fixture: a flat disk, one NaN inside it; the origin must equal the clean run's.
//

import XCTest
import Metal
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

    private func metalOrigin(_ pattern: [Float]) throws -> (x: Float, y: Float) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let buffer = try XCTUnwrap(device.makeBuffer(
            bytes: pattern, length: pattern.count * MemoryLayout<Float>.stride,
            options: .storageModeShared))
        let out = try MetalEngine.shared.measureOrigins(
            cube: buffer,
            params: OriginParams(ry: 1, rx: 1, qy: UInt32(size), qx: UInt32(size), r: 6, rscale: 1.2))
        return (out[0], out[1])
    }

    /// The NaN sits at the disk's centre pixel, in the beam's coarse block.
    private var nanIndex: Int { 21 * size + 19 }

    func testRow24MetalOriginIgnoresANonFinitePixelInTheBeam() throws {
        let clean = try metalOrigin(disk())
        XCTAssertEqual(Double(clean.x), centre.x, accuracy: 0.3, "the clean fixture finds the beam")
        var bad = disk()
        bad[nanIndex] = .nan
        let dirty = try metalOrigin(bad)
        XCTAssertEqual(dirty.x, clean.x, accuracy: 1e-4)
        XCTAssertEqual(dirty.y, clean.y, accuracy: 1e-4)
        bad[nanIndex] = .infinity
        let inf = try metalOrigin(bad)
        XCTAssertEqual(inf.x, clean.x, accuracy: 1e-4)
        XCTAssertEqual(inf.y, clean.y, accuracy: 1e-4)
    }

    func testRow24FriedelOriginIgnoresANonFinitePixelInTheBeam() throws {
        // Even-sized pattern, disk centred on a pixel-symmetric point.
        let n = 32
        var pattern = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n where hypot(Double(x) - 15.5, Double(y) - 15.5) <= 6 {
                pattern[y * n + x] = 100
            }
        }
        let clean = try XCTUnwrap(FriedelOrigin.origin(pattern: pattern, height: n, width: n))
        XCTAssertEqual(Double(clean.col), 15.5, accuracy: 0.2)
        XCTAssertEqual(Double(clean.row), 15.5, accuracy: 0.2)
        var bad = pattern
        bad[16 * n + 15] = .nan
        let dirty = try XCTUnwrap(FriedelOrigin.origin(pattern: bad, height: n, width: n))
        XCTAssertEqual(dirty.col, clean.col, accuracy: 1e-4)
        XCTAssertEqual(dirty.row, clean.row, accuracy: 1e-4)
    }
}
