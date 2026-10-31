import XCTest
import DiffractoCore
import DiffractoOrientation
import DSTEMCore
import simd
@testable import mac4DSTEM

/// The orientation plan's k range is the detector's reach (DiffractoKit#65). At a fixed 1.2 Å⁻¹ on a detector that
/// records only 0.762 Å⁻¹ (the public Al-Mg-Si demo: 128 px at 0.012 Å⁻¹/px), the template rings beyond the edge make the
/// exact zone-axis template lose to one tilted by a few degrees, whose excitation envelope has dimmed the outer
/// reflections the pattern lacks: the beam direction came out 4.3° off [001] and 6.2° off [011] on the demo.
final class ACOMDetectorReachTests: XCTestCase {

    // The demo's detector.
    private let size = 128, scale = 0.012, origin = 63.5

    func testTheKRangeIsTheDistanceToTheNearestDetectorEdge() {
        XCTAssertEqual(OrientationPlan.kMax(originX: 63.5, originY: 63.5, detectorColumns: 128, detectorRows: 128,
                                            invAngstromPerPixel: 0.012), 0.762, accuracy: 1e-12)
        // Off-centre and rectangular: the nearest edge decides (column 100 of 128 is 27 px from the right edge).
        XCTAssertEqual(OrientationPlan.kMax(originX: 100, originY: 40, detectorColumns: 128, detectorRows: 96,
                                            invAngstromPerPixel: 0.01), 0.27, accuracy: 1e-12)
        // A detector that reaches further keeps the plan's 1.2 Å⁻¹.
        XCTAssertEqual(OrientationPlan.kMax(originX: 255.5, originY: 255.5, detectorColumns: 512, detectorRows: 512,
                                            invAngstromPerPixel: 0.012), 1.2)
        // No usable reach: the old fixed range.
        XCTAssertEqual(OrientationPlan.kMax(originX: -3, originY: 10, detectorColumns: 64, detectorRows: 64,
                                            invAngstromPerPixel: 0.02), 1.2)
        XCTAssertEqual(OrientationPlan.kMax(originX: 32, originY: 32, detectorColumns: 64, detectorRows: 64,
                                            invAngstromPerPixel: 0), 1.2)
        XCTAssertEqual(OrientationPlan.kMax(originX: 32, originY: 32, detectorColumns: 64, detectorRows: 64,
                                            invAngstromPerPixel: .nan), 1.2)
    }

    /// Al zone-axis patterns drawn by the kit's own projection (flat sphere, the plan's excitation width) and cut at
    /// the demo's detector edge: the plan at the detector's reach returns the template nearest the true beam direction
    /// for [001], [011] and [111]. At 1.2 Å⁻¹ (red before the fix) [001] came back 5.0° and [011] 6.5° off.
    /// Break it by building the plan at `OrientationPlan.maximumKMax`.
    func testZoneAxisPatternsCutAtTheDetectorEdgeComeBackOnTheirAxis() throws {
        let al = CrystalPresets.aluminum
        let kMax = OrientationPlan.kMax(originX: origin, originY: origin, detectorColumns: size, detectorRows: size,
                                        invAngstromPerPixel: scale)
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: al, kMax: kMax, zoneAxisCount: 200, symmetry: .cubic))
        let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
        let reflections = try al.kinematicReflections(kMax: OrientationPlan.maximumKMax, retainingAll: false).kept
            .map { ACOMReflection(g: $0.g, intensity: $0.intensity) }
        let edge = Double(size - 1) - origin
        for axis in [SIMD3<Double>(0, 0, 1), SIMD3(0, 1, 1), SIMD3(1, 1, 1)] {
            let n = simd_normalize(axis)
            let spots = ACOMTemplateLibrary.project(reflections: reflections, zoneAxis: n,
                                                    settings: ACOMTemplateSettings(sgWidth: 0.03, intensityPower: 1))
            let peaks = spots.compactMap { s -> BraggPeak? in
                let x = origin + s.r * cos(s.azimuth) / scale, y = origin + s.r * sin(s.azimuth) / scale
                return s.r / scale <= edge ? BraggPeak(x: Float(x), y: Float(y), intensity: Float(s.weight)) : nil
            }
            let result = matcher.match(peaks: peaks, originX: Float(origin), originY: Float(origin),
                                       invAngstromPerPixel: scale)
            let got = Self.offAxisDegrees(plan.zoneAxes[result.templateIndex], n)
            let nearest = plan.zoneAxes.map { Self.offAxisDegrees($0, n) }.min() ?? .nan
            XCTAssertEqual(got, nearest, accuracy: 0.01, "\(axis): the winner is \(got)° off, the nearest template \(nearest)°")
        }
    }

    /// The angle between two beam directions after the cubic reduction (sorted absolute components).
    static func offAxisDegrees(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        func reduced(_ v: SIMD3<Double>) -> SIMD3<Double> {
            let s = [abs(v.x), abs(v.y), abs(v.z)].sorted()
            return simd_normalize(SIMD3(s[0], s[1], s[2]))
        }
        return acos(min(1, simd_dot(reduced(a), reduced(b)))) * 180 / .pi
    }
}

/// The public Al-Mg-Si demo through the app's disk detector and matcher. Needs the file: run with
/// `TEST_RUNNER_MAC4DSTEM_DEMO_H5=<path to AlMgSi_demo.h5>`; skipped without it (CI has no data).
///
/// Grain truth (the demo's truth.json): A [001] columns 0...54, B [011] columns 55...99 rows 0...49, C [111] columns
/// 55...99 rows 50...99; the vacuum probe at rows 90...99, columns 0...9. Measured 2026-10-31 on every matrix position
/// with 200 beam directions: at 1.2 Å⁻¹ A 5.0° and B 6.5° off; at the detector's reach A 0.0°, B 1.9°, C 0.0°.
final class AlMgSiDemoACOMTests: XCTestCase {

    func testDemoGrainsComeBackOnTheirZoneAxes() async throws {
        guard let path = ProcessInfo.processInfo.environment["MAC4DSTEM_DEMO_H5"] else {
            throw XCTSkip("MAC4DSTEM_DEMO_H5 not set")
        }
        let reader = try await AppState.makeReader(for: URL(fileURLWithPath: path))
        let d = try await reader.discoverPrimaryDataset()
        let data = FourDArray(reader: reader, descriptor: d)
        let origin: Float = 63.5, scale = 0.012
        let probe = try await data.pattern(ry: 95, rx: 5)
        // The measured-probe sigmoid kernel (radius 3 px, the demo's probe) and the thresholds of the kit check.
        let kernel = try XCTUnwrap(ProbeKernel.measured(pattern: probe, originX: origin, originY: origin, radius: 3))
        let detector = try XCTUnwrap(DiskDetector(kernel: kernel))
        var params = DiskDetectionParams()
        params.minRelativeIntensity = 0.005
        params.minPeakSpacing = 8
        params.edgeBoundary = 4
        params.subpixel = .poly
        let kMax = OrientationPlan.kMax(originX: Double(origin), originY: Double(origin), detectorColumns: d.qx,
                                        detectorRows: d.qy, invAngstromPerPixel: scale)
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: CrystalPresets.aluminum, kMax: kMax,
                                                          zoneAxisCount: 200, symmetry: .cubic))
        let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
        let grains: [(name: String, axis: SIMD3<Double>, row: Int, column: Int)] = [
            ("A", SIMD3(0, 0, 1), 50, 40), ("B", SIMD3(0, 1, 1), 25, 77), ("C", SIMD3(1, 1, 1), 75, 77),
        ]
        for g in grains {
            let nearest = plan.zoneAxes.map { ACOMDetectorReachTests.offAxisDegrees($0, g.axis) }.min() ?? .nan
            for dr in -1...1 { for dc in -1...1 {
                let pattern = try await data.pattern(ry: g.row + dr, rx: g.column + dc)
                let peaks = detector.detect(pattern: pattern.pixels, params: params)
                let result = matcher.match(peaks: peaks, originX: origin, originY: origin, invAngstromPerPixel: scale)
                XCTAssertGreaterThanOrEqual(result.templateIndex, 0)
                guard result.templateIndex >= 0 else { continue }
                let off = ACOMDetectorReachTests.offAxisDegrees(plan.zoneAxes[result.templateIndex], g.axis)
                // 2°: B lands one sampling step (1.88°) from its exact template; at 1.2 Å⁻¹ A is 5.0° and B 6.5° off.
                XCTAssertLessThan(off, 2, "grain \(g.name) at (\(g.row + dr), \(g.column + dc)): \(off)° off, nearest \(nearest)°")
            } }
        }
    }
}
