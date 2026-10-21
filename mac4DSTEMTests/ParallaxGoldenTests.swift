//
//  ParallaxGoldenTests.swift
//  The parallax stages that moved onto CuboParallax 0.6.0 (position correction, aberration correction, depth sectioning), pinned
//  numerically against the app's own former outputs. Fixtures/Parallax/pre-switch-outputs.json was generated from the parent of
//  commit b9789ed7 (the last tree before the three switches: the app's Float position-correction loop, its own transfer-function
//  recomputation and its one-kit-call-per-plane depth loop) on the deterministic synthetic bright-field stack
//  `syntheticParallax()` (7 x 7 detector, 24 x 24 scan, 40 x 40 padded stack) after the app's Float alignment at factor 8, which the
//  switches did not touch. The fixture is NOT the demo cube: the commit messages' "demo cube" runs were not kept.
//
//  The current code reproduces every array bit for bit (the commits claimed 0 differing values). To regenerate on purpose, run
//  `TEST_RUNNER_PARALLAX_GOLDEN_OUT=<path> xcodebuild test ... -only-testing:mac4DSTEMTests/ParallaxGoldenTests/testWriteGoldenOutputs`
//  and commit the file in its own commit with the reason.
//

import XCTest
import DSTEMCore
import struct CuboParallax.ParallaxAberrationTerm
import struct CuboParallax.ParallaxHigherOrderAberrationFitResult
import struct CuboParallax.ParallaxAberrationFitResult
import struct CuboParallax.ParallaxPhysicalShift
@testable import mac4DSTEM

@MainActor
final class ParallaxGoldenTests: XCTestCase {
    /// Every array the three stages produce on the synthetic stack, by name, as Float (written to JSON through Double: exact).
    private func outputs() throws -> [String: [Float]] {
        let (pre, _) = syntheticParallax()
        var alignOptions = ParallaxAlignmentOptions()
        alignOptions.upsampleFactor = 8
        var previous: ParallaxAlignmentResult?
        while true {
            let next = try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: previous, options: alignOptions)
            previous = next
            if next.isComplete { break }
        }
        let alignment = try XCTUnwrap(previous)
        // A linear shift field leaves the higher orders unobservable (the fitter says so), so the transfer function and the depth
        // planes are taken at a fixed coefficient set with C1, C12a/b, C21a and C23a all non-zero.
        let zero = [ParallaxPhysicalShift](repeating: ParallaxPhysicalShift(rowAngstrom: 0, columnAngstrom: 0), count: 49)
        let low = ParallaxAberrationFitResult(
            measuredShifts: zero, fittedShifts: zero, rotationRad: 0, c1Angstrom: 300, c12aAngstrom: 40, c12bAngstrom: -25,
            rmsResidualAngstrom: 0, forceTranspose: false, forcedRotationAngleDegrees: nil)
        let fit = ParallaxHigherOrderAberrationFitResult(
            lowOrder: low,
            terms: [(1, 0, 0), (1, 2, 0), (1, 2, 1), (2, 1, 0), (2, 3, 0)].map {
                ParallaxAberrationTerm(radialOrder: $0.0, angularOrder: $0.1, component: $0.2) },
            coefficientsAngstrom: [300, 40, -25, 2_000, -1_500], fittedShifts: zero, rmsResidualAngstrom: 0, fitMethod: .global)

        var out = [String: [Float]]()
        var correction = ParallaxAberrationCorrectionOptions()
        correction.qLowpassInvAngstrom = 1.2
        correction.qHighpassInvAngstrom = 0.05
        let corrected = try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: alignment, fit: fit, options: correction)
        out["aberration.corrected"] = corrected.correctedPhase.pixels
        out["aberration.chiEven"] = corrected.chiEven
        out["aberration.chiOdd"] = corrected.chiOdd
        out["aberration.transferReal"] = corrected.transferReal
        out["aberration.transferImaginary"] = corrected.transferImaginary

        var depth = ParallaxDepthOptions()
        depth.depthsAngstrom = [-60, 0, 90]
        let sectioned = try ParallaxDepthSectioner.section(preprocessing: pre, alignment: alignment, fit: fit, options: depth)
        out["depth.paddedStack"] = sectioned.paddedStack

        // Position correction starts from shifts that are off by a deterministic fraction of a pixel, so it has something to move:
        // on the exact alignment every offset stays zero and the offsets would pin nothing.
        let off = alignment.totalShifts.enumerated().map { index, shift in
            ParallaxScanShift(row: shift.row + Float(0.35 * sin(Double(index) * 1.3)), column: shift.column + Float(0.35 * cos(Double(index) * 0.9)))
        }
        let perturbed = ParallaxAlignmentResult(
            alignmentBin: alignment.alignmentBin, alignmentSchedule: alignment.alignmentSchedule, completedBins: alignment.completedBins,
            upsampleFactor: alignment.upsampleFactor, groups: alignment.groups, groupShifts: alignment.groupShifts, totalShifts: off,
            shiftedStack: alignment.shiftedStack, shiftedMasks: alignment.shiftedMasks, reconstructionMask: alignment.reconstructionMask,
            alignedBF: alignment.alignedBF, errorHistory: alignment.errorHistory, scanHeight: alignment.scanHeight,
            scanWidth: alignment.scanWidth, stackHeight: alignment.stackHeight, stackWidth: alignment.stackWidth)
        for (name, checkerboard, lanczos) in [("gradient", false, Int?.none), ("checkerboard", true, Int?(2))] {
            var options = ParallaxSubpixelOptions()
            options.upsampleFactor = 2
            options.positionCorrectionIterations = 3
            options.positionCorrectionCheckerboard = checkerboard
            options.lanczosOrder = lanczos
            let result = try ParallaxSubpixelReconstructor.reconstruct(preprocessing: pre, alignment: perturbed, options: options)
            out["position.\(name).probeShiftRows"] = result.probeShiftRows
            out["position.\(name).probeShiftColumns"] = result.probeShiftColumns
            out["position.\(name).scores"] = result.positionCorrectionScores
            out["position.\(name).croppedBF"] = result.croppedBF.pixels
        }
        return out
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Parallax/pre-switch-outputs.json")
    }

    /// Regeneration entry point (skipped unless TEST_RUNNER_PARALLAX_GOLDEN_OUT is set); not an assertion.
    func testWriteGoldenOutputs() throws {
        guard let path = ProcessInfo.processInfo.environment["PARALLAX_GOLDEN_OUT"] else {
            throw XCTSkip("set TEST_RUNNER_PARALLAX_GOLDEN_OUT to write the fixture")
        }
        let encoded = try outputs().mapValues { $0.map(Double.init) }
        let data = try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Bit-equal to the app's former outputs: position-correction offsets, scores and image; the stored transfer function and phase
    /// surfaces; the depth planes. Mutation: the py4DSTEM (Double, step floor) variant in the position loop, a sign flip in the
    /// transfer function, or the depth list reordered -> red.
    func testTheKitStagesReproduceTheFormerAppOutputsBitForBit() throws {
        let stored = try JSONDecoder().decode([String: [Double]].self, from: Data(contentsOf: fixtureURL))
        let actual = try outputs()
        XCTAssertEqual(Set(stored.keys), Set(actual.keys))
        for (name, values) in actual.sorted(by: { $0.key < $1.key }) {
            let expected = try XCTUnwrap(stored[name], name)
            XCTAssertEqual(values.count, expected.count, name)
            let differing = zip(values, expected).filter { Double($0) != $1 }.count
            XCTAssertEqual(differing, 0, "\(name): \(differing) of \(values.count) values differ")
            XCTAssertTrue(values.contains { $0 != 0 }, "\(name) is all zero: the fixture would pin nothing")
        }
    }
}
