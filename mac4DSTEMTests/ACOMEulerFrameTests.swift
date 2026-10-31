import XCTest
import simd
import DiffractoScattering
import DSTEMCore
import DSTEMSession
import DiffractoOrientation
import DiffractoCore
@testable import mac4DSTEM

/// The Euler angles of an ACOM map are py4DSTEM's (f050d207): SciPy `from_matrix(G.T).as_euler("zxz")` of the orientation
/// matrix G in py4DSTEM's lab frame, x along the detector rows (py4DSTEM qx), y along the columns (qy), z = x cross y.
/// The matcher works in the app's detector frame (x along the columns, y along the rows, z = x cross y), whose
/// matrix differs from py4DSTEM's by the lab-side relabelling F (x and y swapped, z reversed). Before 2026-10-31 the map
/// carried the matcher's frame: on the public Al-Mg-Si demo, grain C [111] read (-135.0, 54.7, 130.3) deg against
/// py4DSTEM's (45.0, 54.7, -40.0) on the same peaks, 50 deg apart after symmetry; with F, 0.3 deg.
final class ACOMEulerFrameTests: XCTestCase {

    private static let wavelength = 0.02508      // 200 kV
    private static let scale = 0.008, origin = 256.0

    nonisolated private static func properCubicOperators() -> [simd_double3x3] {
        var result: [simd_double3x3] = []
        for p in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] {
                var rows = [SIMD3<Double>](repeating: .zero, count: 3)
                for i in 0..<3 { rows[i][p[i]] = [x, y, z][i] }
                let m = simd_double3x3(rows: rows)
                if simd_determinant(m) > 0.5 { result.append(m) }
            } } }
        }
        return result
    }

    /// Misorientation in degrees between two lab-to-crystal matrices, the crystal's 24 rotations applied on the left.
    nonisolated private static func misorientationDeg(_ a: simd_double3x3, _ b: simd_double3x3) -> Double {
        properCubicOperators().map { op in
            let m = op * a * b.transpose
            return acos(max(-1, min(1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2))) * 180 / .pi
        }.min()!
    }

    /// A pattern planted in py4DSTEM's frame: G has columns py4DSTEM lab x, y, z in crystal coordinates (z the beam
    /// axis `axis`), a reflection g lands at qx = g.x_lab (detector row) and qy = g.y_lab (detector column). Built here,
    /// independent of the matcher's projection. The excitation follows the matcher's model in its own frame, whose z is
    /// the reverse of py4DSTEM's.
    nonisolated private static func plantedInPy4DSTEMFrame(axis: SIMD3<Double>, inPlaneDeg: Double,
                                                         reflections: [KinematicReflection])
        -> (truth: simd_double3x3, peaks: [BraggPeak]) {
        let n = simd_normalize(axis)
        let seed: SIMD3<Double> = abs(n.z) < 0.8 ? [0, 0, 1] : [1, 0, 0]
        let f0 = simd_normalize(seed - simd_dot(seed, n) * n)
        let a = inPlaneDeg * .pi / 180
        let x = simd_normalize(f0 * cos(a) + simd_cross(n, f0) * sin(a))
        let y = simd_cross(n, x)
        let peaks: [BraggPeak] = reflections.compactMap { r in
            let sg = -simd_dot(r.g, n) + 0.5 * wavelength * simd_length_squared(r.g)
            let intensity = r.intensity * exp(-pow(sg / 0.03, 2))
            guard abs(sg) <= 0.1 && intensity > 0 else { return nil }
            return BraggPeak(x: Float(origin + simd_dot(r.g, y) / scale),     // detector column: py4DSTEM qy
                             y: Float(origin + simd_dot(r.g, x) / scale),     // detector row: py4DSTEM qx
                             intensity: Float(intensity))
        }
        return (simd_double3x3(columns: (x, y, n)), peaks)
    }

    /// A known non-symmetric orientation, planted in py4DSTEM's frame, comes back as itself through the app's scan
    /// matcher. Break it by dropping the frame change in `OrientationMatching.matchAll`: 34, 57 and 34 degrees off.
    func testAPlantedOrientationInPy4DSTEMsFrameComesBackAsItself() throws {
        let crystal = CrystalPresets.aluminum
        let plan = try XCTUnwrap(OrientationPlan.generate(
            crystal: crystal, kMax: 1.2, zoneAxisCount: 600, symmetry: .cubic, wavelengthAngstrom: Self.wavelength))
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let cases: [(axis: SIMD3<Double>, inPlane: Double)] = [([5, 2, 7], 17.3), ([1, 4, 6], 17.3), ([7, 3, 9], 52.0)]
        let planted = cases.map { Self.plantedInPy4DSTEMFrame(axis: $0.axis, inPlaneDeg: $0.inPlane, reflections: reflections) }
        let vectors = BraggVectors(scanWidth: planted.count, scanHeight: 1, peaks: planted.map(\.peaks))
        let map = try XCTUnwrap(OrientationMatching.matchAll(
            bragg: vectors, plan: plan, originX: Float(Self.origin), originY: Float(Self.origin),
            invAngstromPerPixel: Self.scale, backend: .cpu))
        for (index, p) in planted.enumerated() {
            let result = map.results[index]
            XCTAssertGreaterThanOrEqual(result.templateIndex, 0, "case \(index) matched nothing")
            let error = Self.misorientationDeg(result.euler.py4DSTEMOrientationMatrix, p.truth)
            XCTAssertLessThan(error, 3, "case \(index) (\(cases[index].axis)): \(error) deg from the planted orientation")
            // The reported FZ angle is the rotation angle of the reported matrix.
            let m = result.euler.py4DSTEMOrientationMatrix
            let angle = acos(max(-1, min(1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2)))
            XCTAssertEqual(Double(result.symmetryDisorientationRad), angle, accuracy: 1e-5)
        }
    }

    /// The relabelling itself: G in py4DSTEM's frame is the matcher's G times F, F swapping x and y and reversing z
    /// (a proper half turn about the in-plane diagonal), then reduced to the fundamental zone again.
    func testTheFrameChangeIsTheDiagonalHalfTurn() throws {
        let f = ACOMEulerFrame.py4DSTEMFromMatcher
        XCTAssertEqual(simd_determinant(f), 1, accuracy: 1e-15)
        XCTAssertEqual(f * f, matrix_identity_double3x3)
        // The demo's grain C at row 51, column 57: the matcher's angles, and py4DSTEM's on the same peaks.
        let matcher = EulerAngles(phi1: Float(-135.0 * Double.pi / 180), Phi: Float(54.7356 * Double.pi / 180),
                                  phi2: Float(130.312 * Double.pi / 180))
        let converted = ACOMEulerFrame.py4DSTEM(fromMatcher: matcher, symmetry: .cubic)
        let py4DSTEM = EulerAngles(phi1: Float(45.0 * Double.pi / 180), Phi: Float(54.7356 * Double.pi / 180),
                                   phi2: Float(-40.008 * Double.pi / 180))
        let error = Self.misorientationDeg(converted.euler.py4DSTEMOrientationMatrix, py4DSTEM.py4DSTEMOrientationMatrix)
        XCTAssertLessThan(error, 0.4, "the demo sample: \(error) deg")   // the matcher and py4DSTEM differ by 0.30 deg there
        XCTAssertEqual(Double(converted.euler.degrees.0), 45.0, accuracy: 0.01)
        XCTAssertEqual(Double(converted.euler.degrees.1), 54.7356, accuracy: 0.01)
        XCTAssertEqual(Double(converted.euler.degrees.2), -40.312, accuracy: 0.01)
    }

    /// The public Al-Mg-Si demo through the app's route (open, origin, disks, ACOM with the Al library model): grain C
    /// [111] agrees with py4DSTEM's orientation on the same peaks (`Fixtures/ACOM/acom_euler_frame_reference.py`: py4DSTEM
    /// f050d207 `match_single_pattern`, 255 grain C positions, median 0.30 deg; py4DSTEM jumps 60 deg at some positions,
    /// so the median is the check). Needs `TEST_RUNNER_MAC4DSTEM_DEMO_H5=<path to a copy of AlMgSi_demo.h5>`; skipped without.
    @MainActor
    func testTheDemoGrainCAgreesWithPy4DSTEM() async throws {
        guard let path = ProcessInfo.processInfo.environment["MAC4DSTEM_DEMO_H5"] else {
            throw XCTSkip("MAC4DSTEM_DEMO_H5 not set")
        }
        let state = AppState()
        await state.openFileAsync(url: URL(fileURLWithPath: path))
        let d = try XCTUnwrap(state.descriptor, state.statusText)
        await state.calibrateOrigin()
        state.navigation.analysisMode = .disks
        _ = await state.runDiskDetection()
        state.acomSession.modelSelection = .library("al_fcc")
        state.acomSession.scope = .fullScan
        _ = await state.runACOM()
        let map = try XCTUnwrap(state.acomSession.orientationMap, state.statusText)
        // py4DSTEM's grain C orientation (lab to crystal, rows; the median of its reduced matrices, re-orthonormalised):
        // Euler (45.0, 54.7355, -40.013) deg. The matcher's frame read (-135.0, 54.7, 130.3) here, 50 deg away.
        let py4DSTEM = simd_double3x3(rows: [
            SIMD3(0.804061, -0.141965, 0.577349), SIMD3(-0.279083, 0.76732, 0.57735), SIMD3(-0.524975, -0.625353, 0.577352),
        ])
        var errors: [Double] = []
        for y in 51..<99 { for x in 56..<99 {   // grain C without its border rows and columns
            let r = map[x, y]
            guard r.templateIndex >= 0 else { continue }
            errors.append(Self.misorientationDeg(r.euler.py4DSTEMOrientationMatrix, py4DSTEM))
        } }
        XCTAssertGreaterThan(errors.count, 1800, "grain C positions matched: \(errors.count) of \(48 * 43)")
        let median = errors.sorted()[errors.count / 2]
        XCTAssertLessThan(median, 1, "grain C: median \(median) deg from py4DSTEM")
        XCTAssertEqual(d.ry, 100)
    }

    /// Every ACOM product and the scientific bundle say which frame their angles are in; a file without the key was
    /// written before the change and holds the matcher's frame, which `py4DSTEM(fromMatcher:)` converts.
    func testTheRunProvenanceNamesTheFrame() {
        let semantics = ACOMRunSemantics(
            materialModelID: "al_fcc", materialDescription: "Aluminium (FCC)",
            scale: ACOMScaleSemantics(invAngstromPerPixel: 0.012, provenance: .manual))
        XCTAssertEqual(semantics.provenance[ACOMEulerFrame.provenanceKey], ACOMEulerFrame.py4DSTEMMarker)
        XCTAssertEqual(ACOMEulerFrame.frame(ofProvenance: semantics.provenance), .py4DSTEM)
        XCTAssertEqual(ACOMEulerFrame.frame(ofProvenance: [:]), .matcherBefore20261031)
        XCTAssertEqual(ACOMEulerFrame.frame(ofProvenance: [ACOMEulerFrame.provenanceKey: "other"]), .unknown)
    }
}
