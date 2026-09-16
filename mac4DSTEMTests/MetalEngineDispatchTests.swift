//
//  MetalEngineDispatchTests.swift
//  Hygiene audit row 10-lite (2026-09-16): `MetalEngine.virtualDiffraction`
//  and `MetalEngine.dpStatistics` had zero test references (code-metrics.md
//  table D2), despite both being GPU dispatches with a plain CPU definition
//  (selected-area sum; per-pixel max/mean over scan positions). A tiny
//  synthetic cube with hand-picked values lets the expected result be
//  written out by hand and checked against `MetalEngine.shared`.
//
//  TOLERANCE: every value below is a small integer (< 100), exactly
//  representable in float32, and each output is a sum of at most 4 such
//  values — so the GPU and CPU sums are bit-identical in principle. The
//  assertions nonetheless use `accuracy: 1e-4` rather than exact equality,
//  because the GPU may accumulate in a different order than the CPU loop
//  below; 1e-4 absorbs any such reordering of these O(1)-O(100) magnitude
//  values while still catching a wrong-pixel or wrong-count mistake, which
//  would be off by whole units.
//

import XCTest
import Metal
import DSTEMCore
@testable import mac4DSTEM

final class MetalEngineDispatchTests: XCTestCase {

    /// A 2×2 scan of 2×2 patterns, each pattern's 4 pixels a distinct value
    /// so a swapped axis or dropped pixel changes the result, not merely
    /// permutes values that would otherwise coincide.
    ///
    /// Pattern at scan (ry,rx), detector (qy,qx):
    ///   value = (ry*2 + rx) * 100 + (qy*2 + qx)
    /// scan (0,0): [0, 1, 2, 3]      scan (0,1): [100, 101, 102, 103]
    /// scan (1,0): [200, 201, 202, 203]  scan (1,1): [300, 301, 302, 303]
    private func makeCube() throws -> (buffer: MTLBuffer, dims: CubeDims, patterns: [[Float]]) {
        let ry = 2, rx = 2, qy = 2, qx = 2
        var patterns: [[Float]] = []
        var flat: [Float] = []
        flat.reserveCapacity(ry * rx * qy * qx)
        for scan in 0..<(ry * rx) {
            var pattern: [Float] = []
            for p in 0..<(qy * qx) {
                pattern.append(Float(scan * 100 + p))
            }
            patterns.append(pattern)
            flat.append(contentsOf: pattern)
        }
        let descriptor = DatasetDescriptor(
            filePath: "/synthetic/metal-engine-dispatch-test", datasetPath: "/data",
            shape: [ry, rx, qy, qx], dtypeDescription: "float32", chunkShape: nil
        )
        let dims = CubeDims(descriptor)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let buffer = try XCTUnwrap(device.makeBuffer(
            bytes: flat, length: flat.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ))
        return (buffer, dims, patterns)
    }

    /// Selects two of the four scan positions (indices 1 and 2 — scan (0,1)
    /// and (1,0)) and checks the summed pattern against the CPU sum of those
    /// two patterns, elementwise.
    func testVirtualDiffractionSumsOnlySelectedScanPositions() throws {
        let (buffer, dims, patterns) = try makeCube()
        let scanMask: [Float] = [0, 1, 1, 0]

        let result = try MetalEngine.shared.virtualDiffraction(
            cube: buffer, dims: dims, scanMask: scanMask
        )

        var expected = [Float](repeating: 0, count: patterns[0].count)
        for (scan, weight) in scanMask.enumerated() where weight != 0 {
            for p in 0..<expected.count {
                expected[p] += patterns[scan][p]
            }
        }

        XCTAssertEqual(result.count, expected.count)
        for i in 0..<expected.count {
            XCTAssertEqual(result[i], expected[i], accuracy: 1e-4, "pixel \(i)")
        }
    }

    /// Max and mean per detector pixel over ALL four scan positions,
    /// checked against the same reduction done on the CPU.
    func testDPStatisticsMatchesCPUMaxAndMean() throws {
        let (buffer, dims, patterns) = try makeCube()

        let (maxDP, meanDP) = try MetalEngine.shared.dpStatistics(cube: buffer, dims: dims)

        let pixelCount = patterns[0].count
        var expectedMax = [Float](repeating: -.infinity, count: pixelCount)
        var expectedSum = [Float](repeating: 0, count: pixelCount)
        for pattern in patterns {
            for p in 0..<pixelCount {
                expectedMax[p] = max(expectedMax[p], pattern[p])
                expectedSum[p] += pattern[p]
            }
        }
        let expectedMean = expectedSum.map { $0 / Float(patterns.count) }

        XCTAssertEqual(maxDP.count, pixelCount)
        XCTAssertEqual(meanDP.count, pixelCount)
        for i in 0..<pixelCount {
            XCTAssertEqual(maxDP[i], expectedMax[i], accuracy: 1e-4, "max pixel \(i)")
            XCTAssertEqual(meanDP[i], expectedMean[i], accuracy: 1e-4, "mean pixel \(i)")
        }
    }
}
