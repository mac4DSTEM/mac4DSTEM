//
//  ACOMMetalMemoryTests.swift
//  Gate D, lane M (2026-10-15), tier 2 (memory behaviour, no number moves): the Metal ACOM matcher's batch loop.
//  DiffractoKit's Metal `matchAll` (formerly the app's `MetalACOMMatcher`) is a long synchronous loop that makes six buffers, a command buffer and two encoders
//  per `runBatch` call (two calls per batch). No autorelease pool drains inside it, so before the fix the device
//  memory grew by about 0.125 MB per batch until `matchAll` returned (measured: 3.8 -> 28.7 MB over 200 batches,
//  lane-M/harness/h2/h2-before.log; flat at 3.7 MB with a pool per `runBatch`, h2-after.log; the 12 800 results
//  byte-identical, FNV64 38bf8a345bb74ce5 both).
//

import XCTest
import Metal
import simd
import DiffractoScattering
import DSTEMCore
import DiffractoCore
@testable import mac4DSTEM
@testable import ShellMetal

final class ACOMMetalMemoryTests: XCTestCase {

    /// 200+ batches of the Metal matcher: device memory must not grow with the batch count. The progress callback runs
    /// once per batch on the matching thread, so `currentAllocatedSize` is sampled between batches. Unfixed: +22.5 MB
    /// from batch 10 to batch 199; fixed: 0.0 MB. The bound (3 MB) is about 24 batches' worth of the leak and 15x the
    /// observed noise (none).
    func testMetalMatchAllDeviceMemoryDoesNotGrowPerBatch() throws {
        let crystal = CrystalPresets.gold
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 96))
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let scale = 0.01
        // 32 distinct positions (a different template and in-plane angle each), cycled over a 128 x 100 scan.
        let distinct: [[BraggPeak]] = (0..<32).map { index in
            let template = (index * 17 + index / 8) % plan.count
            let angle = Double((index * 7) % 64) / 64 * Double.pi
            return OrientationPlan.project(
                reflections: reflections, zoneAxis: plan.zoneAxes[template],
                sgWidth: 0.03, sgMax: 0.1, intensityPower: 1
            ).map { spot in
                BraggPeak(x: 64 + Float(spot.r / scale * cos(spot.azim + angle)),
                          y: 64 + Float(spot.r / scale * sin(spot.azim + angle)),
                          intensity: Float(spot.weight))
            }
        }
        let width = 128, height = 100
        let vectors = BraggVectors(scanWidth: width, scanHeight: height,
                                   peaks: (0..<(width * height)).map { distinct[$0 % distinct.count] })

        let device = MetalEngine.shared.device
        let sampler = AllocationSampler()
        guard let map = OrientationMatching.matchAll(
            bragg: vectors, plan: plan, originX: 64, originY: 64, invAngstromPerPixel: scale, backend: .metal,
            progress: { _ in sampler.record(device.currentAllocatedSize) }
        ) else { throw XCTSkip("Metal matcher unavailable on this machine") }

        let samples = sampler.values
        XCTAssertGreaterThanOrEqual(samples.count, 200, "the scan must run at least 200 batches (got \(samples.count))")
        // From batch 10 on, past the first-use allocations (pipelines, the template buffers).
        let growthMB = Double(samples[samples.count - 1] - samples[10]) / 1_048_576
        XCTAssertLessThan(growthMB, 3.0,
            "device memory grew \(growthMB) MB over \(samples.count - 11) batches (\(growthMB / Double(samples.count - 11)) MB per batch): autoreleased Metal objects survive until matchAll returns")

        // The loop did compute: every position is matched, equal inputs give equal outputs.
        XCTAssertEqual(map.results.count, width * height)
        XCTAssertTrue(map.results.allSatisfy { $0.score > 0 })
        let mismatches = (32..<map.results.count).filter { map.results[$0] != map.results[$0 - 32] }.count
        XCTAssertEqual(mismatches, 0, "\(mismatches) positions differ from the position with the same peaks 32 earlier")
    }
}

/// Lock-guarded record of `currentAllocatedSize` samples (the progress callback is `@Sendable`).
nonisolated private final class AllocationSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Int] = []
    func record(_ value: Int) { lock.withLock { samples.append(value) } }
    var values: [Int] { lock.withLock { samples } }
}
