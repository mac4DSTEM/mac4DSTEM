import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Lane R4 (2026-10-01), the aligned bright field's "edge vignette" on py4DSTEM's graphene cube: `ParallaxAligner.alignNextLevel` took the
/// whole-stack mean as `Double(stack.reduce(0, +)) / n`, whose `reduce` sums in Float and stalls at 2^24 - the freeze D021 fixed in
/// `ParallaxPreprocessor.stackMean` and left here. Every pixel the shifted masks do not cover (the padding, the window's zero edge) is
/// `(stackMean * maskInv + ...) / (mask + maskInv)` = stackMean, so the padding read 0.79375 where py4DSTEM's `_stack_mean` is 1.0
/// (graphene: 1961 x 133 x 133 = 34.7 M elements; parallax.py:806, :1425-1429).
final class ParallaxAlignedMeanTests: XCTestCase {

    /// 4 200 bright-field images of a 64 x 64 padded plane = 17.2 M elements, past 2^24 = 16 777 216. Every image is the same texture,
    /// so the alignment moves nothing and the padding (mask 0) must read exactly the stack's true mean (Double accumulation).
    /// A Float32 sum of this stack stalls near 16 777 216 and reads ~0.975.
    func testTheAlignedBrightFieldPaddingReadsTheTrueStackMeanPastTheFloatStall() throws {
        let scan = 32, pad = 32, side = scan + pad, plane = side * side, count = 4_200
        XCTAssertGreaterThan(count * plane, 1 << 24, "the premise: the stack is longer than Float32's integer range")
        var texture = [Float](repeating: 1, count: plane)
        let top = pad / 2
        for y in 0..<scan { for x in 0..<scan {
            texture[(top + y) * side + top + x] = 1 + 0.2 * Float(sin(0.9 * Double(y) + 0.3 * Double(x)) * cos(0.4 * Double(y)))
        } }
        var stack = [Float](); stack.reserveCapacity(count * plane)
        for _ in 0..<count { stack.append(contentsOf: texture) }
        let indices = (0..<count).map { ParallaxDetectorIndex(qx: $0 / 65, qy: $0 % 65) }
        let vectors = indices.map { ParallaxVector(qx: Float($0.qx - 32) * 0.01, qy: Float($0.qy - 32) * 0.01) }
        let preprocessing = ParallaxPreprocessResult(
            scanHeight: scan, scanWidth: scan, detectorHeight: 65, detectorWidth: 65, stackHeight: side, stackWidth: side,
            calibration: ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 1, reciprocalSamplingInvAngstrom: 0.01, energyEV: 80_000, wavelengthAngstrom: 0.0418,
                originQX: 32, originQY: 32, rotationRad: 0, transpose: false),
            thresholdIntensity: 0.8, detectorMask: [Bool](repeating: true, count: 65 * 65), detectorIndices: indices,
            reciprocalVectors: vectors, probeAnglesMrad: vectors,
            edgeWindow: [Float](repeating: 1, count: scan * scan), normalizedStack: stack, unshiftedStack: [],
            incoherentBF: texture, initialError: 0)
        var truth = 0.0
        for value in stack { truth += Double(value) }
        truth /= Double(stack.count)

        let aligned = try ParallaxAligner.alignNextLevel(preprocessing: preprocessing)
        for (row, column) in [(0, 0), (0, side - 1), (side - 1, 0), (3, 40)] {
            XCTAssertEqual(Double(aligned.alignedBF[row * side + column]), truth, accuracy: 1e-4,
                           "padding pixel (\(row), \(column)) must read the true stack mean, not a Float-stalled one")
        }
    }
}
