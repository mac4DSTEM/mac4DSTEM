//
//  ACOMKitCallSiteTests.swift
//  Tier 1 (orientation numbers): the app's call sites of DiffractoKit's ACOM route. `OrientationMatching.matchAll` feeds the
//  kit's scan loop in chunks of 8192 positions, and `OrientationPlan.generate` maps the beam wavelength to the kit's
//  excitation model. Both are the app's own glue, so both are pinned here.
//

import XCTest
import DiffractoOrientation
import DSTEMCore
import simd
@testable import mac4DSTEM

final class ACOMKitCallSiteTests: XCTestCase {

    /// A scan of more than one chunk (91 x 91 = 8281 > 8192): the chunked CPU path gives, position by position, exactly the
    /// results of one kit call over the whole scan. Mutation (scatter a chunk's results to the wrong positions or restart
    /// something per chunk): a position of the second chunk differs and this goes red.
    func testChunkedCPUScanEqualsOneKitCallOverTheWholeScan() throws {
        let crystal = Crystal.gold
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, nRadial: 12, nAzimuthal: 64,
                                                          zoneAxisCount: 12, wavelengthAngstrom: 0.0251))
        // A small library: the tests build in Debug, where the kit's scalar correlation is slow, and what is under test is
        // the chunking over 8281 positions, not the library.
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let scale = 0.01
        let distinct: [[BraggPeak]] = (0..<24).map { index in
            if index % 11 == 10 { return [] }                 // an unmatched position, kept as .empty
            let template = (index * 7 + index / 3) % plan.count
            let angle = Double((index * 5) % 64) / 64 * 2 * Double.pi
            return OrientationPlan.project(
                reflections: reflections, zoneAxis: plan.zoneAxes[template], sgWidth: 0.03, sgMax: 0.1,
                wavelengthAngstrom: 0.0251, intensityPower: 1
            ).map { spot in
                BraggPeak(x: 64 + Float(spot.r / scale * cos(spot.azim + angle)),
                          y: 64 + Float(spot.r / scale * sin(spot.azim + angle)),
                          intensity: Float(spot.weight))
            }
        }
        let width = 91, height = 91
        let peaks = (0..<(width * height)).map { distinct[($0 * 5 + $0 / width) % distinct.count] }
        let vectors = BraggVectors(scanWidth: width, scanHeight: height, peaks: peaks)

        let fractions = FractionLog()
        let app = try XCTUnwrap(OrientationMatching.matchAll(
            bragg: vectors, plan: plan, originX: 64, originY: 64, invAngstromPerPixel: scale, backend: .cpu,
            progress: { fractions.record($0) }))
        let matcher = try XCTUnwrap(ACOMMatcher(library: plan.library))
        let kit = try XCTUnwrap(matcher.matchAll(
            peaks: peaks.map { $0.map(ACOMPeak.init) }, width: width, height: height,
            originX: 64, originY: 64, invAngstromPerPixel: scale))

        XCTAssertEqual(app.results.count, width * height)
        var differing = 0
        for index in app.results.indices where app.results[index] != kit.results[index] { differing += 1 }
        XCTAssertEqual(differing, 0, "\(differing) positions differ between the chunked run and one kit call")
        XCTAssertTrue(app.results.contains { $0.templateIndex >= 0 }, "the scan must have matched something")
        XCTAssertTrue(app.results.contains { $0.templateIndex < 0 }, "the empty positions stay unmatched")
        let seen = fractions.values
        XCTAssertEqual(seen.last ?? 0, 1, accuracy: 1e-9, "progress ends at 1 over the whole selection")
        XCTAssertTrue(zip(seen, seen.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 }, "progress never goes back across chunks")
    }

    /// The beam wavelength reaches the kit as the app's curved Ewald sphere; without one (or with a non-positive one) the
    /// sphere is flat. A curved plan's templates differ from the flat plan's.
    /// Mutation (drop the `excitation:` argument in `OrientationPlan.generate`): both plans are flat and this goes red.
    func testWavelengthSelectsTheAppCurvatureModel() throws {
        let crystal = Crystal.gold
        let curved = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 24,
                                                            wavelengthAngstrom: 0.0251))
        let flat = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 24))
        let zero = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 24,
                                                          wavelengthAngstrom: 0))
        XCTAssertEqual(curved.library.settings.excitation, .appCurvature(wavelengthAngstrom: 0.0251))
        XCTAssertEqual(flat.library.settings.excitation, .flat)
        XCTAssertEqual(zero.library.settings.excitation, .flat)
        XCTAssertEqual(flat.templates, zero.templates)
        XCTAssertNotEqual(curved.templateFFTRe, flat.templateFFTRe, "curvature must change the templates")
    }
}

nonisolated private final class FractionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [Double] = []
    func record(_ v: Double) { lock.withLock { all.append(v) } }
    var values: [Double] { lock.withLock { all } }
}
