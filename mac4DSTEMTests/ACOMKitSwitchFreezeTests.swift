//
//  ACOMKitSwitchFreezeTests.swift
//  Tier 1 (orientation numbers): the app's ACOM scan route (`OrientationMatching.matchAll`, CPU and Metal) and plan
//  (`OrientationPlan.generate`) pinned as FNV-1a digests over the bit patterns of every field of every result. The values
//  were RECORDED from the app's own pre-switch code (the per-chunk [[ACOMPeak]] conversion, the app copies of
//  `selectOrientation` and `makeOrientationResult`) on 2026-10-21, before the switch to DiffractoKit 0.7.x's
//  `matchAll(peaksAt:)` and `ACOMMatcher.result(scores:bins:mirrored:)`, and must be bit-equal after it.
//  Synthetic scans: each position is a template of the plan at an in-plane angle, optionally mirrored (the x-mirror image),
//  plus unmatched positions (no peaks, one peak: `match` needs two).
//

import XCTest
import DiffractoOrientation
import DiffractoScattering
import DiffractoCore
import DSTEMCore
import simd
@testable import mac4DSTEM

final class ACOMKitSwitchFreezeTests: XCTestCase {

    private static func fnv(_ values: [UInt64]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for value in values {
            for shift in stride(from: 0, to: 64, by: 8) {
                hash ^= (value >> UInt64(shift)) & 0xff
                hash = hash &* 0x100000001b3
            }
        }
        return String(format: "%016llx", hash)
    }

    private static func bits(_ r: OrientationResult) -> [UInt64] {
        [UInt64(bitPattern: Int64(r.templateIndex)), UInt64(r.euler.phi1.bitPattern), UInt64(r.euler.Phi.bitPattern),
         UInt64(r.euler.phi2.bitPattern), UInt64(r.inPlaneAngle.bitPattern), UInt64(r.score.bitPattern),
         UInt64(r.secondScore.bitPattern), UInt64(bitPattern: Int64(r.phaseID)),
         UInt64(r.symmetryDisorientationRad.bitPattern), r.mirrored ? 1 : 0]
    }

    private static func digest(_ map: OrientationMap) -> String { fnv(map.results.flatMap(bits)) }

    private static func planDigest(_ plan: OrientationPlan) -> String {
        fnv(plan.templateFFTRe.map { UInt64($0.bitPattern) } + plan.templateFFTIm.map { UInt64($0.bitPattern) }
            + plan.zoneAxes.flatMap { [$0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern] })
    }

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

    // Recorded from the pre-switch code, 2026-10-21 (this machine; the Metal digests are this GPU's).
    private static let planDigests: [String: String] = [
        "gold": "b875e4c5d3185d52", "ws2": "0b73fbc7d6e91a57", "beta": "f552072ff1158ca5",
    ]
    private static let cpuFull: [String: String] = [
        "gold": "8a51188d89a98361", "ws2": "d0921010667479c9", "beta": "0a926f8bab004874",
    ]
    private static let cpuPreview = "c5dc0928b0e4b339", cpuSquare = "262ba16be670334f"

    func testPlansAreBitEqualToTheRecording() throws {
        for c in Self.cases {
            XCTAssertEqual(Self.planDigest(try plan(c)), Self.planDigests[c.key], "\(c.key) plan")
        }
    }

    func testCPUFullScanIsBitEqualToTheRecording() throws {
        for c in Self.cases {
            let map = try run(c, backend: .cpu)
            XCTAssertEqual(Self.digest(map), Self.cpuFull[c.key], "\(c.key) CPU")
            XCTAssertTrue(map.results.contains { $0.templateIndex >= 0 }, "\(c.key) matched something")
            XCTAssertTrue(map.results.contains { $0.templateIndex < 0 }, "\(c.key) kept unmatched positions")
            XCTAssertTrue(map.results.contains { $0.mirrored }, "\(c.key) has a mirrored winner")
        }
    }

    func testPreviewAndSquareSelectionsAreBitEqualToTheRecordingOnCPUAndMatchItOnMetal() throws {
        let gold = Self.cases[0]
        XCTAssertEqual(Self.digest(try run(gold, backend: .cpu, selection: .preview(maxDimension: 3))), Self.cpuPreview)
        XCTAssertEqual(Self.digest(try run(gold, backend: .cpu, selection: .square(centerX: 3, centerY: 2, radius: 1))),
                       Self.cpuSquare)
        // Metal is DiffractoKit's (0.7.1); its digests moved with the switch (D12), so the selections are held to the CPU within Float rounding.
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
