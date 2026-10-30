//
//  ACOMScanRouteTests.swift
//  The app's ACOM scan route (`OrientationMatching.matchAll`, CPU and Metal) on synthetic scans: each position is a
//  template of the plan at an in-plane angle, optionally mirrored (the x-mirror image), plus unmatched positions (no
//  peaks, one peak: `match` needs two). Metal is held to the CPU within Float rounding. The orientation numbers
//  themselves are DiffractoKit's and its parity tests own them (bit-pattern digests of a pre-switch recording were here
//  until 2026-10-30; they turned the app red on any kit change).
//

import XCTest
import DiffractoOrientation
import DiffractoScattering
import DiffractoCore
import DSTEMCore
import simd
@testable import mac4DSTEM

final class ACOMScanRouteTests: XCTestCase {

    private struct Case {
        let key: String
        let crystal: CrystalStructure
        let symmetry: ACOMCrystalSymmetry
    }

    private static let cases: [Case] = [
        Case(key: "gold", crystal: CrystalPresets.gold, symmetry: .cubic),
        Case(key: "ws2", crystal: CrystalPresets.tungstenDisulfide, symmetry: .hexagonal),
        Case(key: "beta", crystal: CrystalPresets.betaDoublePrime, symmetry: .monoclinic),
    ]

    private let wavelength = 0.0251
    private let scale = 0.01
    private let width = 7, height = 5

    private func plan(_ c: Case) throws -> OrientationPlan {
        try XCTUnwrap(OrientationPlan.generate(
            crystal: c.crystal, kMax: 1.2, nRadial: 12, nAzimuthal: 64, zoneAxisCount: 40,
            symmetry: c.symmetry, wavelengthAngstrom: wavelength), c.key)
    }

    private func scan(_ c: Case, plan: OrientationPlan) throws -> BraggVectors {
        let reflections = try c.crystal.kinematicReflections(kMax: 1.2).kept
        let positions = width * height
        let peaks: [[BraggPeak]] = (0..<positions).map { index in
            if index % 9 == 8 { return [] }                         // no peaks
            if index % 9 == 7 {                                      // one peak: below the matcher's two
                return [BraggPeak(x: 70, y: 64, intensity: 1)]
            }
            let template = (index * 7 + index / 3) % plan.count
            let angle = Double((index * 5) % 64) / 64 * 2 * Double.pi
            let mirror = index % 3 == 2
            return OrientationPlan.project(
                reflections: reflections, zoneAxis: plan.zoneAxes[template], sgWidth: 0.03, sgMax: 0.1,
                wavelengthAngstrom: wavelength, intensityPower: 1
            ).map { spot in
                let x = spot.r / scale * cos(spot.azim + angle)
                let y = spot.r / scale * sin(spot.azim + angle)
                return BraggPeak(x: 64 + Float(mirror ? -x : x), y: 64 + Float(y), intensity: Float(spot.weight))
            }
        }
        return BraggVectors(scanWidth: width, scanHeight: height, peaks: peaks)
    }

    private func run(_ c: Case, backend: ACOMMatchingBackend, selection: ACOMScanSelection = .full) throws -> OrientationMap {
        let p = try plan(c)
        return try XCTUnwrap(OrientationMatching.matchAll(
            bragg: try scan(c, plan: p), plan: p, originX: 64, originY: 64, invAngstromPerPixel: scale,
            backend: backend, selection: selection), "\(c.key) \(backend) \(selection)")
    }

    /// The synthetic scan exercises every branch of the route: matched, unmatched (no peak, one peak) and mirrored winners.
    func testTheCPUScanMatchesKeepsUnmatchedPositionsAndFindsAMirror() throws {
        for c in Self.cases {
            let map = try run(c, backend: .cpu)
            XCTAssertTrue(map.results.contains { $0.templateIndex >= 0 }, "\(c.key) matched something")
            XCTAssertTrue(map.results.contains { $0.templateIndex < 0 }, "\(c.key) kept unmatched positions")
            XCTAssertTrue(map.results.contains { $0.mirrored }, "\(c.key) has a mirrored winner")
        }
    }

    /// The preview and square selections agree between Metal and CPU within Float rounding.
    func testPreviewAndSquareSelectionsAgreeOnMetalAndCPU() throws {
        let gold = Self.cases[0]
        for selection in [ACOMScanSelection.preview(maxDimension: 3), .square(centerX: 3, centerY: 2, radius: 1)] {
            let cpu = try run(gold, backend: .cpu, selection: selection), gpu = try run(gold, backend: .metal, selection: selection)
            for (a, b) in zip(cpu.results, gpu.results) {
                XCTAssertEqual(a.templateIndex, b.templateIndex)
                XCTAssertEqual(a.score, b.score, accuracy: 1e-5)
            }
        }
    }

    /// The Metal route's scores equal the CPU route's within Float rounding; the template agrees (the mirror flag is
    /// not compared: a mirror-symmetric pattern scores both passes alike and the two backends may break that tie differently).
    func testMetalAgreesWithCPUOnTheSyntheticScan() throws {
        for c in Self.cases {
            let cpu = try run(c, backend: .cpu), gpu = try run(c, backend: .metal)
            for (a, b) in zip(cpu.results, gpu.results) {
                XCTAssertEqual(a.templateIndex, b.templateIndex, c.key)
                XCTAssertEqual(a.score, b.score, accuracy: 1e-5, c.key)
            }
        }
    }
}
