//
//  ParallaxKitSwitchTests.swift
//  Session 5 (2026-10-21): the parallax stages on CuboKit 0.6.0's CuboParallax. The numbers are pinned against py4DSTEM by the
//  parallax-* harnesses; the app's former outputs on the demo cube (commit 18c1516b) are a committed fixture; these pin what the
//  switch itself changes: where a cancel lands, and what the progress callback sees.
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

    private func preprocessing() -> ParallaxPreprocessResult {
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
            normalizedStack: [], unshiftedStack: [], incoherentBF: [], initialError: 0)
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
}
