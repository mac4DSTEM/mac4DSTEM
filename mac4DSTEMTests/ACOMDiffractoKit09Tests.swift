// Task 2 (DiffractoKit 0.9): the in-plane refinement switch reaches the matcher and closes on planted off-grid patterns, the mirror
// flag is published as a plane beside the in-plane angle, the recorded recipe carries the switch only when it is on.

import XCTest
import DiffractoOrientation
import DSTEMCore
import DSTEMSession
import DiffractoCore
import simd
@testable import mac4DSTEM

final class ACOMDiffractoKit09Tests: XCTestCase {

    /// Gold library small enough for Debug; planted patterns are template spots rotated by an in-plane angle that is NOT a multiple of
    /// the bin (2 pi / 64 = 5.6 degrees), so the unrefined angle is off by up to half a bin and the vertex refinement is not.
    /// The same 40 patterns go through `matchAll` with the switch off and on (the app's call site).
    func testRefinementIsCloserOnTheSameOffGridPatterns() throws {
        let crystal = CrystalPresets.gold
        let plan = try XCTUnwrap(OrientationPlan.generate(crystal: crystal, kMax: 1.2, nRadial: 12, nAzimuthal: 64,
                                                          zoneAxisCount: 12, wavelengthAngstrom: 0.0251))
        let reflections = try crystal.kinematicReflections(kMax: 1.2).kept
        let scale = 0.01
        let count = 40
        var truth: [Double] = []
        var templates: [Int] = []
        var peaks: [[BraggPeak]] = []
        for i in 0..<count {
            let template = (i * 5 + 1) % plan.count
            // Off-grid: 0.5 to 0.9 of a bin past a grid angle, spread over the circle.
            let bin = 2 * Double.pi / 64
            let angle = (Double((i * 7) % 64) + 0.5 + Double(i % 5) * 0.1) * bin
            truth.append(angle); templates.append(template)
            peaks.append(OrientationPlan.project(reflections: reflections, zoneAxis: plan.zoneAxes[template], sgWidth: 0.03, sgMax: 0.1,
                                                 wavelengthAngstrom: 0.0251, intensityPower: 1).map { spot in
                BraggPeak(x: 64 + Float(spot.r / scale * cos(spot.azim + angle)),
                          y: 64 + Float(spot.r / scale * sin(spot.azim + angle)), intensity: Float(spot.weight))
            })
        }
        let vectors = BraggVectors(scanWidth: count, scanHeight: 1, peaks: peaks)
        func errors(refines: Bool) throws -> [Double] {
            let map = try XCTUnwrap(OrientationMatching.matchAll(
                bragg: vectors, plan: plan, originX: 64, originY: 64, invAngstromPerPixel: scale, backend: .cpu,
                refinesInPlaneAngle: refines))
            return map.results.enumerated().compactMap { index, r -> Double? in
                guard r.templateIndex == templates[index], !r.mirrored else { return nil }
                var d = abs(Double(r.inPlaneAngle) - truth[index]).truncatingRemainder(dividingBy: 2 * .pi)
                if d > .pi { d = 2 * .pi - d }
                return d
            }
        }
        let plain = try errors(refines: false), refined = try errors(refines: true)
        XCTAssertGreaterThan(min(plain.count, refined.count), count / 2, "enough patterns found their template to compare")
        // Compare on the patterns both runs matched to the planted template.
        let n = min(plain.count, refined.count)
        let meanPlain = plain.prefix(n).reduce(0, +) / Double(n), meanRefined = refined.prefix(n).reduce(0, +) / Double(n)
        XCTAssertLessThan(meanRefined, meanPlain, "refined \(meanRefined * 180 / .pi) deg against \(meanPlain * 180 / .pi) deg")
    }

    func testTheMirrorFlagIsAPlaneWithTheInPlaneAngle() {
        var map = OrientationMap(width: 3, height: 1, matchingBackend: .cpu, symmetry: .cubic, templateCount: 1)
        var a = OrientationResult.empty, b = OrientationResult.empty
        a.mirrored = true; b.mirrored = false
        map.results = [a, b, a]
        XCTAssertEqual(map.mirroredImage.pixels, [1, 0, 1])
        XCTAssertTrue(ACOMDisplayMode.allCases.contains(.mirrored))
    }

    func testTheRecipeCarriesTheSwitchOnlyWhenItIsOn() throws {
        let model = try XCTUnwrap(CrystalModelLibrary.models.first)
        let off = ReplayStepPlan.ACOMReplayPlan.recordedParameters(model: model, scale: 0.01, backend: "CPU", scope: .fullScan, quality: .balanced)
        XCTAssertNil(off["refines_in_plane"], "a record without the key is the kit default, off: old recipes replay unchanged")
        let on = ReplayStepPlan.ACOMReplayPlan.recordedParameters(model: model, scale: 0.01, backend: "CPU", scope: .fullScan, quality: .balanced,
                                                                 refinesInPlaneAngle: true)
        XCTAssertEqual(on["refines_in_plane"], "true")
        XCTAssertEqual(ReplayStepPlan.ACOMReplayPlan.currentSignatureIfResolved(
            model: model, scale: 0.01, backend: "CPU", scope: .fullScan, quality: .balanced, refinesInPlaneAngle: true), on)
    }
}
