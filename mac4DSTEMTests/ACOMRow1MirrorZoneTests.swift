import XCTest
import simd
import DSTEMCore

/// Review 2026-09-30 row 1. The ACOM bank samples the mirror-reduced direction
/// triangle (cubic z ≥ x ≥ y ≥ 0), but orientation equivalence is the proper
/// rotation group, whose zone is twice that: a beam axis in the other triangle
/// produces the 2-D MIRROR of a template's pattern, which no in-plane rotation
/// reproduces. py4DSTEM covers it with `inversion_symmetry` (a conjugated
/// correlation pass; crystal_ACOM.py:877, :1272-1323, :1548-1550). Before the
/// port carried that pass, (1,2,3) came back 57° wrong at score 0.90 while its
/// mirror image (2,1,3) came back right — half of generic orientations.
///
/// Truth is independent of the production projection: peak positions are dot
/// products onto a right-handed basis built here, and the returned matrix is
/// compared under an independent operator list (as tools/acom-convention-test).
/// The harness `tools/acom-mirror-test` runs the same check over 200 random
/// directions, WS2, and measures the cost.
final class ACOMRow1MirrorZoneTests: XCTestCase {

    private static let wavelength = 0.02508      // 200 kV, what the app passes
    private static let scale = 0.008, origin = 256.0

    nonisolated private static func properCubicOperators() -> [simd_double3x3] {
        var result: [simd_double3x3] = []
        for p in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
            for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
                var rows = [SIMD3<Double>](repeating: .zero, count: 3)
                for i in 0..<3 { rows[i][p[i]] = [x, y, z][i] }
                let m = simd_double3x3(rows: rows)
                if simd_determinant(m) > 0.5 { result.append(m) }
            } } }
        }
        return result
    }

    nonisolated private static func misorientationDeg(_ a: simd_double3x3, _ b: simd_double3x3,
                                                      _ ops: [simd_double3x3]) -> Double {
        ops.map { op in
            let m = op * a * b.transpose
            return acos(max(-1, min(1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2))) * 180 / .pi
        }.min()!
    }

    /// Independent pattern for beam `axis` rotated in-plane by `angleDeg`.
    nonisolated private static func pattern(axis: SIMD3<Double>, angleDeg: Double,
                                            reflections: [Reflection])
        -> (truth: simd_double3x3, peaks: [BraggPeak]) {
        let n = simd_normalize(axis)
        let seed: SIMD3<Double> = abs(n.z) < 0.8 ? [0, 0, 1] : [1, 0, 0]
        let f0 = simd_normalize(seed - simd_dot(seed, n) * n)
        let a = angleDeg * .pi / 180
        let f1 = simd_normalize(f0 * cos(a) + simd_cross(n, f0) * sin(a))
        let f2 = simd_cross(n, f1)
        let peaks: [BraggPeak] = reflections.compactMap { r in
            let sg = simd_dot(r.g, n) + 0.5 * wavelength * simd_length_squared(r.g)
            let intensity = r.intensity * exp(-pow(sg / 0.03, 2))
            guard abs(sg) <= 0.1 && intensity > 0 else { return nil }
            return BraggPeak(x: Float(origin + simd_dot(r.g, f1) / scale),
                             y: Float(origin + simd_dot(r.g, f2) / scale), intensity: Float(intensity))
        }
        return (simd_double3x3(columns: (f1, f2, n)), peaks)
    }

    /// Three mirror-triangle axes and two sampled-triangle controls, each at an
    /// off-grid in-plane angle. Mutations this catches: dropping the conjugated
    /// pass (mirror trials 27–55° off, `mirrored` never set); negating only one
    /// column on a mirrored win (an improper matrix — the reducer still returns
    /// one, 90°+ off); omitting py4DSTEM's +π on the in-plane angle of a
    /// mirrored win (right template and flag, orientation 26–35° off — the
    /// first fix attempt, mirror-fixed.log 2026-10-01).
    func testMirrorTriangleAxesAreRecoveredAndFlaggedSampledOnesAreNot() throws {
        let crystal = Crystal.aluminum
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: crystal, kMax: 1.2, zoneAxisCount: 600, symmetry: .cubic,
            wavelengthAngstrom: Self.wavelength))
        let matcher = try XCTUnwrap(OrientationMatcher(plan: plan, symmetry: .cubic))
        let reflections = crystal.reflections(kMax: 1.2)
        let ops = Self.properCubicOperators()
        XCTAssertEqual(ops.count, 24)
        // Not (1,2,3) / (2,1,3): at 17.3° that pair is in the known in-plane
        // modulo-π class (both halves 37–38° off on HEAD and after; the
        // harness logs it), which is not this row.
        let cases: [(axis: SIMD3<Double>, mirror: Bool)] = [
            ([1, 4, 6], true), ([1, 3, 5], true), ([2, 5, 7], true),
            ([5, 2, 7], false), ([7, 3, 9], false),
        ]
        var peaksForMetal: [[BraggPeak]] = []
        var cpuResults: [OrientationResult] = []
        for (axis, expectMirror) in cases {
            let (truth, peaks) = Self.pattern(axis: axis, angleDeg: 17.3, reflections: reflections)
            let result = matcher.match(peaks: peaks, originX: Float(Self.origin),
                                       originY: Float(Self.origin), invAngstromPerPixel: Self.scale)
            XCTAssertTrue(plan.zoneAxes.indices.contains(result.templateIndex), "\(axis) matched nothing")
            let error = Self.misorientationDeg(result.euler.py4DSTEMOrientationMatrix, truth, ops)
            XCTAssertLessThan(error, 3, "\(axis): misorientation \(error)° (score \(result.score))")
            XCTAssertEqual(result.mirrored, expectMirror,
                           "\(axis) \(expectMirror ? "needs" : "must not need") the conjugated pass")
            peaksForMetal.append(peaks)
            cpuResults.append(result)
        }

        // The Metal path carries the same pass: same template, flag and angle.
        let vectors = BraggVectors(scanWidth: cases.count, scanHeight: 1, peaks: peaksForMetal)
        guard let metal = OrientationMatching.matchAll(
            bragg: vectors, plan: plan, originX: Float(Self.origin), originY: Float(Self.origin),
            invAngstromPerPixel: Self.scale, backend: .metal
        ) else { throw XCTSkip("Metal matcher unavailable on this machine") }
        for (index, cpu) in cpuResults.enumerated() {
            let gpu = metal.results[index]
            XCTAssertEqual(gpu.templateIndex, cpu.templateIndex, "Metal template at \(index)")
            XCTAssertEqual(gpu.mirrored, cpu.mirrored, "Metal mirrored flag at \(index)")
            XCTAssertEqual(gpu.inPlaneAngle, cpu.inPlaneAngle, accuracy: 1e-6, "Metal angle at \(index)")
            XCTAssertEqual(gpu.score, cpu.score, accuracy: 2e-4, "Metal score at \(index)")
        }
    }
}
