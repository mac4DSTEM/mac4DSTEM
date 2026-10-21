//
//  ParallaxKitSwitchTests.swift
//  Session 5 (2026-10-21): the parallax stages on CuboKit 0.6.0's CuboParallax. The numbers are pinned against py4DSTEM by the
//  parallax-* harnesses, and against the app's former outputs (position-correction offsets, scores and image, the stored transfer
//  function and phase surfaces, depth planes) by ParallaxGoldenTests and Fixtures/Parallax/pre-switch-outputs.json; these pin what
//  the switch itself changes: where a cancel lands, and what the progress callback sees.
//

import XCTest
import DSTEMCore
import struct CuboParallax.ParallaxPhysicalShift
import struct CuboParallax.ParallaxAberrationFitResult
import struct CuboParallax.ParallaxHigherOrderAberrationFitResult
import struct CuboParallax.ParallaxAberrationTerm
@testable import mac4DSTEM

@MainActor
final class ParallaxKitSwitchTests: XCTestCase {
    private let height = 6, width = 5

    private func preprocessing(unshifted: [Float] = []) -> ParallaxPreprocessResult {
        let angles = [(-2, -3), (-2, 3), (2, -3), (2, 3)].map { ParallaxVector(qx: Float($0.0), qy: Float($0.1)) }
        return ParallaxPreprocessResult(
            scanHeight: height, scanWidth: width, detectorHeight: 1, detectorWidth: 4, stackHeight: height, stackWidth: width,
            calibration: ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 0.5, reciprocalSamplingInvAngstrom: 0.01, energyEV: 200_000,
                wavelengthAngstrom: 0.025079, originQX: 0, originQY: 0, rotationRad: 0, transpose: false),
            thresholdIntensity: 0.8, detectorMask: [Bool](repeating: true, count: 4),
            detectorIndices: (0..<4).map { ParallaxDetectorIndex(qx: 0, qy: $0) },
            reciprocalVectors: angles, probeAnglesMrad: angles,
            edgeWindow: [Float](repeating: 1, count: height * width),
            normalizedStack: [], unshiftedStack: unshifted, incoherentBF: [], initialError: 0)
    }

    private func texture(_ count: Int) -> [Float] {
        (0..<count).map { Float(sin(Double($0) * 1.7) + 0.3 * cos(Double($0) * 0.4) + 2) }
    }

    private func alignment() -> ParallaxAlignmentResult {
        let count = height * width
        return ParallaxAlignmentResult(
            alignmentBin: 1, alignmentSchedule: [1], completedBins: [1], upsampleFactor: 8, groups: [], groupShifts: [],
            totalShifts: [ParallaxScanShift](repeating: ParallaxScanShift(row: 0, column: 0), count: 4),
            shiftedStack: (0..<4).flatMap { _ in texture(count) }, shiftedMasks: [], reconstructionMask: [], alignedBF: texture(count),
            errorHistory: [0], scanHeight: height, scanWidth: width, stackHeight: height, stackWidth: width)
    }

    private func fit(_ c1: Double) -> ParallaxHigherOrderAberrationFitResult {
        let zero = [ParallaxPhysicalShift](repeating: ParallaxPhysicalShift(rowAngstrom: 0, columnAngstrom: 0), count: 4)
        let low = ParallaxAberrationFitResult(
            measuredShifts: zero, fittedShifts: zero, rotationRad: 0, c1Angstrom: c1, c12aAngstrom: 0, c12bAngstrom: 0,
            rmsResidualAngstrom: 0, forceTranspose: false, forcedRotationAngleDegrees: nil)
        return ParallaxHigherOrderAberrationFitResult(
            lowOrder: low, terms: [ParallaxAberrationTerm(radialOrder: 1, angularOrder: 0, component: 0)],
            coefficientsAngstrom: [c1], fittedShifts: zero, rmsResidualAngstrom: 0, fitMethod: .global)
    }

    private final class Ticks: @unchecked Sendable {
        var values = [Double]()
    }

    /// Depth sectioning ticks once per plane and a cancel raised on the first tick stops before the second plane (the kit's
    /// sectioner polls its token before every image of every plane). Mutation: drop `isCancelled` from `plane(atDepth:)`, or build
    /// the whole stack in one call (progress would then tick after the work) -> red.
    func testDepthSectioningTicksPerPlaneAndACancelBetweenPlanesStops() throws {
        var options = ParallaxDepthOptions()
        options.depthsAngstrom = [-20, 0, 35, 60, 90]
        let token = AnalysisCancellationToken()
        let ticks = Ticks()
        XCTAssertThrowsError(try ParallaxDepthSectioner.section(
            preprocessing: preprocessing(), alignment: alignment(), fit: fit(300), options: options, cancellation: token,
            progress: { fraction in ticks.values.append(fraction); token.cancel() })) {
            XCTAssertEqual($0 as? ParallaxDepthSectioner.DepthError, .cancelled)
        }
        XCTAssertEqual(ticks.values, [0.2], "one plane was formed, then the cancel landed")

        let all = Ticks()
        let result = try ParallaxDepthSectioner.section(
            preprocessing: preprocessing(), alignment: alignment(), fit: fit(300), options: options,
            progress: { all.values.append($0) })
        XCTAssertEqual(all.values, [0.2, 0.4, 0.6, 0.8, 1.0])
        XCTAssertEqual(result.planeCount, 5)
    }

    /// Position correction runs in the kit's `.application` loop: progress ticks once per iteration (0.2 + 0.7 * i / n), the scores
    /// record the baseline plus one per iteration, and a cancel on the first tick stops before the second iteration.
    /// Mutation: run the py4DSTEM variant (Double, step floor everywhere) -> ParallaxGoldenTests' position fixture differs;
    /// drop `isCancelled` -> the cancel is only seen after the run -> ticks.count == 3.
    func testPositionCorrectionTicksPerIterationAndACancelStopsIt() throws {
        let count = height * width
        let unshifted = (0..<4).flatMap { b in texture(count).map { $0 + Float(b) * 0.05 } }
        var options = ParallaxSubpixelOptions()
        options.upsampleFactor = 2
        options.positionCorrectionIterations = 3
        let token = AnalysisCancellationToken()
        let ticks = Ticks()
        XCTAssertThrowsError(try ParallaxSubpixelReconstructor.reconstruct(
            preprocessing: preprocessing(unshifted: unshifted), alignment: alignment(), options: options, cancellation: token,
            progress: { ticks.values.append($0); token.cancel() })) {
            XCTAssertEqual($0 as? ParallaxSubpixelReconstructor.ReconstructionError, .cancelled)
        }
        XCTAssertEqual(ticks.values.count, 1)

        let all = Ticks()
        let result = try ParallaxSubpixelReconstructor.reconstruct(
            preprocessing: preprocessing(unshifted: unshifted), alignment: alignment(), options: options,
            progress: { all.values.append($0) })
        XCTAssertEqual(result.positionCorrectionScores.count, 4, "the baseline and one score per iteration")
        XCTAssertEqual(all.values.count, 4, "three iteration ticks and the final one")
        XCTAssertEqual(all.values.first ?? 0, 0.2 + 0.7 / 3, accuracy: 1e-12)
        XCTAssertEqual(all.values.last, 1)
    }

    // MARK: - Alignment: the app's level logic over CuboParallax's shifter and correlation estimate (CuboKit 0.7.0)

    private struct AlignmentFixture: Decodable {
        struct Level: Decodable { let bin: Int; let group: [Double]; let total: [Double]; let aligned: [Double]? }
        let f1: [Level]; let f8: [Level]
    }

    private func levels(factor: Int) throws -> [ParallaxAlignmentResult] {
        let (pre, _) = syntheticParallax()
        var options = ParallaxAlignmentOptions()
        options.upsampleFactor = factor
        var previous: ParallaxAlignmentResult?
        var out = [ParallaxAlignmentResult]()
        while true {
            let next = try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: previous, options: options)
            out.append(next); previous = next
            if next.isComplete { return out }
        }
    }

    /// The app's alignment levels against what `ParallaxFourierShifter` (Double) gives inside the same level logic (the fixture, made
    /// with the kit at 0.6.0), on a textured stack shifted by a known linear field: integer peaks (factor 1) within 1e-6, factor 8
    /// within 2e-4 px, the aligned image within 5e-5. Since 0.7.0 the level logic calls the kit's `shiftedSingle` (this 40 x 40 stack is a
    /// size vDSP takes), `correlationShift` and `shifting`, so this pins the Float32 shifter and the app's Float storage against the
    /// Double reference. Mutation: flip a shift sign or the running-average weights -> red.
    func testTheFloatAlignmentAgreesWithTheKitShifterOnAKnownField() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Parallax/kit-alignment-synthetic.json")
        let fixture = try JSONDecoder().decode(AlignmentFixture.self, from: Data(contentsOf: url))
        for (factor, expected, tolerance, imageTolerance) in [(1, fixture.f1, 1e-6, 5e-5), (8, fixture.f8, 2e-4, 5e-5)] {
            let actual = try levels(factor: factor)
            XCTAssertEqual(actual.map(\.alignmentBin), expected.map(\.bin))
            for (level, kit) in zip(actual, expected) {
                let group = level.groupShifts.flatMap { [Double($0.row), Double($0.column)] }
                let total = level.totalShifts.flatMap { [Double($0.row), Double($0.column)] }
                XCTAssertEqual(group.count, kit.group.count)
                XCTAssertEqual(total.count, kit.total.count)
                XCTAssertLessThanOrEqual(zip(group, kit.group).map { abs($0 - $1) }.max() ?? 0, tolerance, "factor \(factor) bin \(kit.bin) group shifts")
                XCTAssertLessThanOrEqual(zip(total, kit.total).map { abs($0 - $1) }.max() ?? 0, tolerance, "factor \(factor) bin \(kit.bin) total shifts")
                if let image = kit.aligned {
                    XCTAssertLessThanOrEqual(zip(level.alignedBF, image).map { abs(Double($0) - $1) }.max() ?? 0, imageTolerance, "aligned image")
                }
            }
        }
    }
}

private struct SynthLCG { var s: UInt64
  mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

/// Bright-field images of a periodic texture shifted by a linear aberration field: 7x7 detector pixels, 40x40 padded stack.
func syntheticParallax() -> (pre: ParallaxPreprocessResult, truth: [ParallaxScanShift]) {
  let h = 40, w = 40, scan = 24, n = 7
  var g = SynthLCG(s: 99)
  var waves: [(kr: Double, kc: Double, a: Double, p: Double)] = []
  for _ in 0..<14 { waves.append((Double(Int(g.next() * 7) - 3), Double(Int(g.next() * 7) - 3), 0.2 + g.next(), g.next() * 2 * .pi)) }
  var indices: [ParallaxDetectorIndex] = [], vectors: [ParallaxVector] = [], truth: [ParallaxScanShift] = []
  var stack: [Float] = []
  for qx in 0..<n { for qy in 0..<n {
    let cx = Double(qx - 3), cy = Double(qy - 3)
    let sr = 0.62 * cx + 0.21 * cy, sc = -0.18 * cx + 0.55 * cy
    indices.append(ParallaxDetectorIndex(qx: qx, qy: qy)); vectors.append(ParallaxVector(qx: Float(cx), qy: Float(cy)))
    truth.append(ParallaxScanShift(row: Float(sr), column: Float(sc)))
    for r in 0..<h { for c in 0..<w {
      var v = 2.0
      for wv in waves { v += wv.a * cos(2 * .pi * (wv.kr * (Double(r) - sr) / Double(h) + wv.kc * (Double(c) - sc) / Double(w)) + wv.p) }
      stack.append(Float(v))
    } }
  } }
  let plane = h * w, count = n * n
  var mean = [Float](repeating: 0, count: plane)
  for b in 0..<count { for p in 0..<plane { mean[p] += stack[b * plane + p] / Float(count) } }
  let pre = ParallaxPreprocessResult(
    scanHeight: scan, scanWidth: scan, detectorHeight: n, detectorWidth: n, stackHeight: h, stackWidth: w,
    calibration: ParallaxPhysicalCalibration(scanSamplingAngstrom: 0.5, reciprocalSamplingInvAngstrom: 0.01, energyEV: 200_000, wavelengthAngstrom: 0.025079, originQX: 0, originQY: 0, rotationRad: 0, transpose: false),
    thresholdIntensity: 0.8, detectorMask: [Bool](repeating: true, count: count), detectorIndices: indices,
    reciprocalVectors: vectors, probeAnglesMrad: vectors, edgeWindow: [Float](repeating: 1, count: scan * scan),
    normalizedStack: stack, unshiftedStack: stack, incoherentBF: mean, initialError: 0.1)
  return (pre, truth)
}
