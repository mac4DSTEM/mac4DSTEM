//
//  ThronsenParityTests.swift
//  Role: the precipitation workflow against Thronsen et al. (Ultramicroscopy 255, 2024, 113861), dataset A, with the PAPER'S metric: the
//        share of positions whose phase label equals the manually built ground truth (Table 3: NMF 98.50, vector matching 98.46,
//        template matching 98.25, ANN 99.04 %), next to the adopted T4 bar (ADR 040, 041: 1.31 % per-position error at stride 3).
//        Then the objects (tasks 39 to 41) of the truth map and of our map through the same pipeline: counts, the Feret length and the
//        edge-corrected areal density, reported as ratios "derived truth, not published". N_V, composition and strain are not
//        checkable here (the dataset has no thickness and no EDS); the paper reports none of the four object quantities.
//  Gate:  heavy, real data (References/mac4DSTEM/thronsen-datasetA, CC BY 4.0, outside the repo): skipped unless MAC4DSTEM_THRONSEN=1
//        (run it with `../tools/memcap.sh --gb 8 -- env TEST_RUNNER_MAC4DSTEM_THRONSEN=1 MAC4DSTEM_UNIT_ONLY=ThronsenParityTests tools/run-tests.sh unit`). The configuration is the T4 run's, as the probe
//        `--thronsen ... --reach 0.68 --rule known-variants --or --min-relative 0.0015 --min-intensity 0` ran it: probe radius 2 px,
//        Q 0.01904 per px, detection floor 0.15 % (ADR 041), the known-variants rule with the paper's orientation relationships.
//  Crystals and phase recipe: the archived probe's `thronsen.swift` (their Table 2), copied here with that provenance.
//

import XCTest
import DSTEMCore
import DSTEMSession
import DiffractoCore
import DiffractoOrientation
import ImagoCore
@testable import mac4DSTEM

private enum ThronsenReference {
    /// T1, Al₂CuLi: P6/mmm, a = 4.94775 Å, c = 14.14499 Å (their Table 2).
    static let t1 = CrystalPresets.structure(
        a: 4.94775, b: 4.94775, c: 14.14499, alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
        sites: [
            AtomSite(z: 13, fractional: [0.333333, 0.000000, 0.000000]), AtomSite(z: 13, fractional: [0.666667, 0.000000, 0.000000]),
            AtomSite(z: 13, fractional: [0.000000, 0.333333, 0.000000]), AtomSite(z: 13, fractional: [0.000000, 0.666667, 0.000000]),
            AtomSite(z: 13, fractional: [0.666667, 0.666667, 0.000000]), AtomSite(z: 13, fractional: [0.333333, 0.333333, 0.000000]),
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.406200]), AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.593800]),
            AtomSite(z: 29, fractional: [0.666667, 0.333333, 0.161200]), AtomSite(z: 29, fractional: [0.333333, 0.666667, 0.838800]),
            AtomSite(z: 29, fractional: [0.333333, 0.666667, 0.161200]), AtomSite(z: 29, fractional: [0.666667, 0.333333, 0.838800]),
            AtomSite(z: 29, fractional: [0.500000, 0.000000, 0.323700]), AtomSite(z: 29, fractional: [0.500000, 0.000000, 0.676300]),
            AtomSite(z: 29, fractional: [0.000000, 0.500000, 0.323700]), AtomSite(z: 29, fractional: [0.000000, 0.500000, 0.676300]),
            AtomSite(z: 29, fractional: [0.500000, 0.500000, 0.323700]), AtomSite(z: 29, fractional: [0.500000, 0.500000, 0.676300]),
            AtomSite(z: 3, fractional: [0.000000, 0.000000, 0.199300]), AtomSite(z: 3, fractional: [0.000000, 0.000000, 0.800700]),
            AtomSite(z: 3, fractional: [0.333333, 0.666667, 0.500000]), AtomSite(z: 3, fractional: [0.666667, 0.333333, 0.500000]),
        ])

    /// θ′, Al₂Cu: I-4m2, a = 4.04 Å, c = 5.80 Å (their Table 2).
    static let thetaPrime = CrystalPresets.structure(
        a: 4.04, b: 4.04, c: 5.80,
        sites: [
            AtomSite(z: 13, fractional: [0.0, 0.0, 0.0]), AtomSite(z: 13, fractional: [0.5, 0.5, 0.5]),
            AtomSite(z: 13, fractional: [0.0, 0.0, 0.5]), AtomSite(z: 13, fractional: [0.5, 0.5, 0.0]),
            AtomSite(z: 29, fractional: [0.0, 0.5, 0.25]), AtomSite(z: 29, fractional: [0.5, 0.0, 0.75]),
        ])

    static func phases() -> [PhaseDefinition] {
        let theta: [OrientationRelationship] = [
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(0, 2, 0))),
        ]
        let face: [OrientationRelationship] = [
            OrientationRelationship(candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(0, 2, 0))),
        ]
        let t1Pairs: [OrientationRelationship] = [
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, -1, 0))),
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, 1, 0))),
        ]
        return [
            PhaseDefinition(id: "al", displayName: "Al", crystal: CrystalPresets.aluminum, role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            PhaseDefinition(id: "theta-edge", displayName: "θ′ edge-on", crystal: thetaPrime, role: .candidate,
                            zoneAxes: [SIMD3(1, 0, 0)], orientationRelationships: theta, excitationSlabInvAngstrom: 0.3),
            PhaseDefinition(id: "theta-face", displayName: "θ′ face-on", crystal: thetaPrime, role: .candidate,
                            zoneAxes: [SIMD3(0, 0, 1)], orientationRelationships: face, excitationSlabInvAngstrom: 0.3),
            PhaseDefinition(id: "t1", displayName: "T1", crystal: t1, role: .candidate,
                            zoneAxes: [SIMD3(0, -4, 1)], orientationRelationships: t1Pairs),
        ]
    }

    /// Their label for the app's verdict: 0 Al, 1 θ′ edge-on, 2 θ′ face-on, 3 T1, -1 not indexed or no data.
    static func label(of result: PhaseVectorResult, phaseNames: [String]) -> Int {
        switch result.verdict {
        case .matrix: return 0
        case .indexed:
            let name = phaseNames.indices.contains(Int(result.phaseIndex)) ? phaseNames[Int(result.phaseIndex)] : ""
            switch name { case "θ′ edge-on": return 1; case "θ′ face-on": return 2; case "T1": return 3; default: return -1 }
        case .notIndexed, .noData: return -1
        }
    }
}

final class ThronsenParityTests: XCTestCase {
    private static let organization = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static var references: URL {
        let root = ProcessInfo.processInfo.environment["MACEM_REFERENCES"].map { URL(fileURLWithPath: $0) }
            ?? organization.appendingPathComponent("References")
        return root.appendingPathComponent("mac4DSTEM/thronsen-datasetA")
    }
    private static let stridePixelNm = 2.4943 * 3

    private struct Truth: Decodable { let labels: [[Int]] }

    private func loadTruth() throws -> (labels: [Int], width: Int, height: Int) {
        let data = try Data(contentsOf: Self.references.appendingPathComponent("truth_stride3.json"))
        let rows = try JSONDecoder().decode(Truth.self, from: data).labels
        return (rows.flatMap { $0 }, rows.first?.count ?? 0, rows.count)
    }

    /// The T4 run's pipeline on the stride-3 cube: detect at 0.15 %, measure the origin, match with the paper's relationships.
    private func ourLabels(width: Int, height: Int) async throws -> (labels: [Int], peaks: Int) {
        let path = Self.references.appendingPathComponent("datasetA_stride3.h5").path
        let reader = try H5Reader(path: path)
        let primary = try await reader.discoverPrimaryDataset()
        XCTAssertEqual([primary.ry, primary.rx], [height, width])
        let qPerPixel = 0.01904
        let kernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 2, qy: primary.qy, qx: primary.qx))
        let detector = try XCTUnwrap(DiskDetector(kernel: kernel))
        var params = DiskDetectionParams()
        params.minPeakSpacing = 3
        params.edgeBoundary = 2
        params.minRelativeIntensity = 0.0015
        let view = LoadView(fullExtentOf: primary)
        var peaks: [[BraggPeak]] = []
        peaks.reserveCapacity(width * height)
        for ry in 0..<primary.ry { for rx in 0..<primary.rx {
            peaks.append(detector.detect(pattern: try await reader.readPattern(view, ry: ry, rx: rx), params: params))
        } }
        // The origin: centre of mass of the mean of 20 sampled patterns inside the direct beam (the probe's rule).
        var mean = [Double](repeating: 0, count: primary.qy * primary.qx)
        for ry in stride(from: 0, to: primary.ry, by: max(1, primary.ry / 20)) {
            let pattern = try await reader.readPattern(view, ry: ry, rx: primary.rx / 2)
            for i in 0..<min(mean.count, pattern.count) { mean[i] += Double(pattern[i]) }
        }
        var sum = 0.0, sx = 0.0, sy = 0.0
        let cy = Double(primary.qy - 1) / 2, cx = Double(primary.qx - 1) / 2
        for y in 0..<primary.qy { for x in 0..<primary.qx {
            guard ((Double(y) - cy) * (Double(y) - cy) + (Double(x) - cx) * (Double(x) - cx)).squareRoot() <= 6 else { continue }
            let w = mean[y * primary.qx + x]; sum += w; sy += w * Double(y); sx += w * Double(x)
        } }
        let originX = sum > 0 ? Float(sx / sum) : Float(cx), originY = sum > 0 ? Float(sy / sum) : Float(cy)

        var reference = PhaseReferenceSettings()
        reference.kMaxInvAngstrom = 0.70
        reference.inPlaneStepDeg = 2
        reference.minimumIntensityFraction = 0
        var matching = PhaseVectorSettings()
        matching.classificationRule = .knownVariants
        matching.maximumVectorInvAngstrom = 0.68
        let library = try PhaseReferenceLibrary.build(phases: ThronsenReference.phases(), settings: reference)
        let bragg = BraggVectors(scanWidth: width, scanHeight: height, peaks: peaks)
        let map = try XCTUnwrap(PhaseVectorMatcher.map(
            scan: bragg.phaseScan, scanWidth: width, scanHeight: height, library: library, settings: matching,
            originX: originX, originY: originY, invAngstromPerPixel: qPerPixel))
        return (map.results.map { ThronsenReference.label(of: $0, phaseNames: map.phaseNames) }, peaks.reduce(0) { $0 + $1.count })
    }

    private func objectRows(_ labels: [Int], width: Int, height: Int) -> [Int: (counted: Int, edge: Int, medianNm: Double?, densityPerUm2: Double?)] {
        let kit: [Int32] = labels.map { $0 < 0 ? 9 : ($0 == 4 ? 9 : Int32($0)) }
        let objects = PrecipitateSegmentation.classObjects(
            labels: kit, width: width, height: height,
            roles: .init(precipitateClasses: [1, 2, 3], matrix: [0], notIndexed: [9]), pixelSize: Self.stridePixelNm, pixelUnit: "nm")
        var out: [Int: (counted: Int, edge: Int, medianNm: Double?, densityPerUm2: Double?)] = [:]
        for c in objects.classes {
            out[Int(c.label)] = (c.density.counted, c.density.edgeExcluded, c.density.medianLength.map { $0 * Self.stridePixelNm },
                                 c.density.arealDensity.map { $0 * 1e6 })
        }
        return out
    }

    func testDatasetAAgainstThePapersMetricAndTheT4Bar() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MAC4DSTEM_THRONSEN"] == "1", "heavy real-data run: set MAC4DSTEM_THRONSEN=1 (command in this file's header)")
        let truth = try loadTruth()
        XCTAssertEqual(truth.labels.count, 171 * 171)
        let ours = try await ourLabels(width: truth.width, height: truth.height)
        let n = truth.labels.count
        let wrong = zip(ours.labels, truth.labels).filter { $0 != $1 }.count
        let accuracy = 100 * Double(n - wrong) / Double(n)
        print(String(format: "THRONSEN accuracy %.4f %% (%d of %d positions differ), %d peaks", accuracy, wrong, n, ours.peaks))
        var confusion: [String: Int] = [:]
        for (o, t) in zip(ours.labels, truth.labels) where o != t { confusion["truth \(t) -> ours \(o)", default: 0] += 1 }
        print("THRONSEN confusion \(confusion.sorted { $0.value > $1.value })")
        // The paper's four methods at full resolution span 98.25 to 99.04 %; "match, not exceed" (D17) is agreement inside that spread.
        XCTAssertGreaterThanOrEqual(accuracy, 98.25, "below the weakest of the paper's four methods")
        XCTAssertLessThanOrEqual(accuracy, 99.04 + 0.5, "better than the best published method by more than the metric can tell: check the truth is not leaking")
        // The T4 run's recorded per-position error was 1.31 %; a change that moves it needs a reason.
        XCTAssertEqual(100 - accuracy, 1.31, accuracy: 0.05)

        let theirs = objectRows(truth.labels, width: truth.width, height: truth.height)
        let mine = objectRows(ours.labels, width: truth.width, height: truth.height)
        for (label, name) in [(1, "θ′ edge-on"), (2, "θ′ face-on"), (3, "T1")] {
            let t = try XCTUnwrap(theirs[label]), m = try XCTUnwrap(mine[label])
            print("THRONSEN objects \(name): truth \(t) ours \(m)")
            if let tl = t.medianNm, let ml = m.medianNm, let td = t.densityPerUm2, let md = m.densityPerUm2 {
                print(String(format: "THRONSEN ratio %@ (ours / derived truth, raw, no cleanup): count %.2f, median Feret %.2f, density %.2f",
                             name, Double(m.counted) / Double(t.counted), ml / tl, md / td))
            }
        }
        // Derived truth, not published (the paper reports no object statistics): the truth map through tasks 39 to 41 at the
        // stride-3 step, raw (no minimum size). Pinned so a change in the object pipeline shows here; ours pinned the same way.
        XCTAssertEqual(theirs[1]?.counted, 70); XCTAssertEqual(theirs[2]?.counted, 3); XCTAssertEqual(theirs[3]?.counted, 21)
        XCTAssertEqual(theirs[3]?.edge, 16)
        XCTAssertEqual(try XCTUnwrap(theirs[3]?.densityPerUm2), 17.0566, accuracy: 1e-3)
        XCTAssertEqual(mine[1]?.counted, 75); XCTAssertEqual(mine[2]?.counted, 35); XCTAssertEqual(mine[3]?.counted, 26)
    }
}
