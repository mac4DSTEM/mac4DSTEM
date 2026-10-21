import XCTest
import Metal
import simd
import DiffractoScattering
import DSTEMCore
import DiffractoCore
@testable import mac4DSTEM

/// Refuter D, item 6: the autorelease pool in the Metal ACOM batch loop (DiffractoKit's since 2026-10-21), tried on a plan the lane did not use (hexagonal WS2,
/// 24 x 256 polar grid, 150 templates, a 150 x 80 scan with empty positions among them) and on an early cancel mid-loop.
/// Output equality is held against the CPU reference within Float rounding.
final class ACOMMetalPoolRefuterTests: XCTestCase {
    func testHexagonalPlanMemoryFlatAndOutputsUnchanged() throws {
        let crystal = CrystalPresets.tungstenDisulfide
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.6, nRadial: 24, nAzimuthal: 256,
                                                          zoneAxisCount: 150, symmetry: .hexagonal))
        let reflections = try crystal.kinematicReflections(kMax: 1.6).kept
        let scale = 0.01
        let distinct: [[BraggPeak]] = (0..<40).map { index in
            if index % 9 == 8 { return [] }            // an empty position: the matcher's invalid-position branch
            let template = (index * 13 + index / 5) % plan.count
            let angle = Double((index * 5) % 64) / 64 * Double.pi
            return OrientationPlan.project(reflections: reflections, zoneAxis: plan.zoneAxes[template],
                                           sgWidth: 0.03, sgMax: 0.1, intensityPower: 1).map { spot in
                BraggPeak(x: 80 + Float(spot.r / scale * cos(spot.azim + angle)),
                          y: 80 + Float(spot.r / scale * sin(spot.azim + angle)), intensity: Float(spot.weight))
            }
        }
        let width = 150, height = 80
        let vectors = BraggVectors(scanWidth: width, scanHeight: height, peaks: (0..<(width * height)).map { distinct[$0 % distinct.count] })
        let device = MetalEngine.shared.device
        let sampler = Sampler()
        guard let map = OrientationMatching.matchAll(bragg: vectors, plan: plan, originX: 80, originY: 80, invAngstromPerPixel: scale,
                                                     backend: .metal, progress: { _ in sampler.record(device.currentAllocatedSize) })
        else { throw XCTSkip("Metal matcher unavailable") }
        let s = sampler.values
        let growthMB = s.count > 12 ? Double(s[s.count - 1] - s[10]) / 1_048_576 : -1
        XCTAssertGreaterThanOrEqual(s.count, 180)
        XCTAssertLessThan(growthMB, 3.0, "device memory grew \(growthMB) MB over \(s.count) batches")
        // The pool moves no output: Metal equals the CPU reference within Float rounding (the digest recorded on the app's own matcher moved with the kit's, D12).
        let cpu = try XCTUnwrap(OrientationMatching.matchAll(bragg: vectors, plan: plan, originX: 80, originY: 80, invAngstromPerPixel: scale, backend: .cpu))
        for (a, b) in zip(cpu.results, map.results) {
            XCTAssertEqual(a.templateIndex, b.templateIndex)
            XCTAssertEqual(a.score, b.score, accuracy: 1e-5)
        }
    }

    /// An early cancel returns nil from inside the batch loop (between pools): no crash, and the next full run is unaffected.
    func testCancelMidLoopReturnsNilAndALaterRunStillWorks() throws {
        let crystal = CrystalPresets.gold
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 40))
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let spots = OrientationPlan.project(reflections: reflections, zoneAxis: plan.zoneAxes[3], sgWidth: 0.03, sgMax: 0.1, intensityPower: 1)
        let peaks = spots.map { BraggPeak(x: 64 + Float($0.r / 0.01 * cos($0.azim)), y: 64 + Float($0.r / 0.01 * sin($0.azim)), intensity: Float($0.weight)) }
        let vectors = BraggVectors(scanWidth: 64, scanHeight: 64, peaks: [[BraggPeak]](repeating: peaks, count: 64 * 64))
        let token = AnalysisCancellationToken()
        let count = Counter()
        let cancelled = OrientationMatching.matchAll(bragg: vectors, plan: plan, originX: 64, originY: 64, invAngstromPerPixel: 0.01,
                                                     backend: .metal, cancellation: token, progress: { _ in if count.bump() == 3 { token.cancel() } })
        XCTAssertNil(cancelled)
        let full = OrientationMatching.matchAll(bragg: vectors, plan: plan, originX: 64, originY: 64, invAngstromPerPixel: 0.01, backend: .metal)
        XCTAssertEqual(full?.results.count, 64 * 64)
        XCTAssertTrue(full?.results.allSatisfy { $0.templateIndex == 3 } ?? false)
    }
}

nonisolated private final class Sampler: @unchecked Sendable {
    private let lock = NSLock(); private var samples: [Int] = []
    func record(_ v: Int) { lock.withLock { samples.append(v) } }
    var values: [Int] { lock.withLock { samples } }
}
nonisolated private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() -> Int { lock.withLock { n += 1; return n } }
}
