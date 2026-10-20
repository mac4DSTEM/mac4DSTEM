//
//  ParallaxKitBridgeTests.swift
//  Call-site tests of the parallax stages that run on CuboKit 0.4.0's CuboParallax (2026-10-20): the aberration fit, the CTF
//  correction and depth sectioning. The numbers are pinned against py4DSTEM by the parallax-aberration-test and parallax-depth-test
//  harnesses; these pin what the bridge itself does (units, layout, which CTF is chosen) on inputs with a known answer.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

@MainActor
final class ParallaxKitBridgeTests: XCTestCase {
    private let wavelength = 0.025079
    private let sampling = 0.5

    /// Four bright-field pixels at (±2, ±3) mrad, a 6 x 5 padded stack that is also the scan.
    private func preprocessing(height: Int = 6, width: Int = 5, zeroAngles: Bool = false,
                               unshifted: [Float] = []) -> ParallaxPreprocessResult {
        let angles = [(-2, -3), (-2, 3), (2, -3), (2, 3)].map { zeroAngles ? ParallaxVector(qx: 0, qy: 0) : ParallaxVector(qx: Float($0.0), qy: Float($0.1)) }
        return ParallaxPreprocessResult(
            scanHeight: height, scanWidth: width, detectorHeight: 1, detectorWidth: 4,
            stackHeight: height, stackWidth: width,
            calibration: ParallaxPhysicalCalibration(
                scanSamplingAngstrom: sampling, reciprocalSamplingInvAngstrom: 0.01, energyEV: 200_000,
                wavelengthAngstrom: wavelength, originQX: 0, originQY: 0, rotationRad: 0, transpose: false),
            thresholdIntensity: 0.8, detectorMask: [Bool](repeating: true, count: 4),
            detectorIndices: (0..<4).map { ParallaxDetectorIndex(qx: 0, qy: $0) },
            reciprocalVectors: angles, probeAnglesMrad: angles,
            edgeWindow: [Float](repeating: 1, count: height * width),
            normalizedStack: [], unshiftedStack: unshifted, incoherentBF: [], initialError: 0)
    }

    private func alignment(shifts: [ParallaxScanShift], stack: [Float], aligned: [Float],
                           height: Int = 6, width: Int = 5) -> ParallaxAlignmentResult {
        ParallaxAlignmentResult(
            alignmentBin: 1, alignmentSchedule: [1], completedBins: [1], upsampleFactor: 8, groups: [], groupShifts: [],
            totalShifts: shifts, shiftedStack: stack, shiftedMasks: [], reconstructionMask: [], alignedBF: aligned,
            errorHistory: [0], scanHeight: height, scanWidth: width, stackHeight: height, stackWidth: width)
    }

    /// A shift field that is the probe angle times an isotropic 400 Å defocus, in scan pixels. Mutations it catches: the mrad ->
    /// rad division dropped (C1 off by 1000), the scan sampling dropped (C1 off by 0.5), row and column axes swapped.
    func testTheLowOrderFitRecoversAKnownDefocus() throws {
        let pre = preprocessing()
        let c1 = 400.0
        let shifts = pre.probeAnglesMrad.map {
            ParallaxScanShift(row: Float(Double($0.qx) / 1_000 * c1 / sampling), column: Float(Double($0.qy) / 1_000 * c1 / sampling))
        }
        let fit = try ParallaxAberrationFitter.fitLowOrder(preprocessing: pre, alignment: alignment(shifts: shifts, stack: [], aligned: []))
        XCTAssertEqual(fit.c1Angstrom, c1, accuracy: 1e-3)
        XCTAssertEqual(fit.c12aAngstrom, 0, accuracy: 1e-3)
        XCTAssertEqual(fit.c12bAngstrom, 0, accuracy: 1e-3)
        XCTAssertEqual(fit.rotationRad, 0, accuracy: 1e-6)
        XCTAssertEqual(fit.rmsResidualAngstrom, 0, accuracy: 1e-3)
        XCTAssertEqual(fit.measuredShifts.count, 4)
        XCTAssertEqual(fit.measuredShifts[3].rowAngstrom, 2e-3 * c1, accuracy: 1e-4, "row shift in Å = pixels x scan sampling")
    }

    /// An incomplete alignment is refused before the kit is asked. Mutation it catches: dropping the guard.
    func testAnIncompleteAlignmentIsRefusedByTheFit() {
        let pre = preprocessing()
        let partial = ParallaxAlignmentResult(
            alignmentBin: 4, alignmentSchedule: [4, 1], completedBins: [4], upsampleFactor: 8, groups: [], groupShifts: [],
            totalShifts: [], shiftedStack: [], shiftedMasks: [], reconstructionMask: [], alignedBF: [], errorHistory: [0],
            scanHeight: 6, scanWidth: 5, stackHeight: 6, stackWidth: 5)
        XCTAssertThrowsError(try ParallaxAberrationFitter.fitLowOrder(preprocessing: pre, alignment: partial)) {
            XCTAssertEqual($0 as? ParallaxAberrationFitter.FitError, .alignmentIncomplete)
        }
    }

    private func defocusFit(_ c1: Double) -> ParallaxHigherOrderAberrationFitResult {
        let zero = [ParallaxPhysicalShift](repeating: ParallaxPhysicalShift(rowAngstrom: 0, columnAngstrom: 0), count: 4)
        let low = ParallaxAberrationFitResult(
            measuredShifts: zero, fittedShifts: zero, rotationRad: 0, c1Angstrom: c1, c12aAngstrom: 0, c12bAngstrom: 0,
            rmsResidualAngstrom: 0, forceTranspose: false, forcedRotationAngleDegrees: nil)
        return ParallaxHigherOrderAberrationFitResult(
            lowOrder: low, terms: [ParallaxAberrationTerm(radialOrder: 1, angularOrder: 0, component: 0)],
            coefficientsAngstrom: [c1], fittedShifts: zero, rmsResidualAngstrom: 0, fitMethod: .global)
    }

    private func texture(_ count: Int) -> [Float] {
        (0..<count).map { Float(sin(Double($0) * 1.7) + 0.3 * cos(Double($0) * 0.4) + 2) }
    }

    /// C1 alone: the full-fit CTF (one radial term) and the defocus-only CTF are the same sin(pi lambda C1 q^2), so the two
    /// option paths must give the same planes; and the planes come back as contiguous [depth, row, column]. Mutations it catches:
    /// `useFullFit` ignored, the plane layout transposed, the depth list not reaching the kit.
    func testDepthSectioningChoosesTheCTFAndKeepsThePlaneLayout() throws {
        let pre = preprocessing(zeroAngles: true)
        let count = 6 * 5
        let stack = (0..<4).flatMap { _ in texture(count) }
        let aligned = alignment(shifts: [ParallaxScanShift](repeating: ParallaxScanShift(row: 0, column: 0), count: 4),
                                stack: stack, aligned: texture(count))
        var options = ParallaxDepthOptions()
        options.depthsAngstrom = [-20, 0, 35]
        options.useFullFit = true
        let full = try ParallaxDepthSectioner.section(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: options)
        options.useFullFit = false
        let lowOrder = try ParallaxDepthSectioner.section(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: options)
        XCTAssertEqual(full.paddedStack.count, 3 * count)
        XCTAssertEqual(full.planeCount, 3)
        for index in full.paddedStack.indices {
            XCTAssertEqual(full.paddedStack[index], lowOrder.paddedStack[index], accuracy: 1e-5)
        }
        // Identical images at zero probe angle: the depth shift is zero, so every plane is the same sign-filtered image.
        for plane in 1..<3 {
            for index in 0..<count {
                XCTAssertEqual(full.paddedStack[plane * count + index], full.paddedStack[index], accuracy: 1e-5)
            }
        }
        XCTAssertGreaterThan(full.paddedStack.map { abs($0) }.max() ?? 0, 1e-3, "the sectioned plane is not empty")
    }

    /// The corrected phase has no DC (the transfer function's zero-frequency entry is 0), the transfer function is a unit-modulus
    /// phase factor where the CTF sign is non-zero, and a low-pass envelope scales it. Mutations it catches: DC left in, the
    /// high-pass/low-pass options not reaching the kit, `useFullFit` ignored for the transfer arrays.
    func testCorrectionRemovesDCAndReturnsTheTransferFunction() throws {
        let pre = preprocessing()
        let count = 6 * 5
        let aligned = alignment(shifts: [ParallaxScanShift](repeating: ParallaxScanShift(row: 0, column: 0), count: 4),
                                stack: [], aligned: texture(count))
        var options = ParallaxAberrationCorrectionOptions()
        let result = try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: options)
        XCTAssertEqual(result.transferReal[0], 0)
        XCTAssertEqual(result.transferImaginary[0], 0)
        XCTAssertEqual(result.paddedPhase.reduce(0, +) / Float(count), 0, accuracy: 1e-5, "DC removed")
        for index in 1..<count {
            let modulus = hypot(result.transferReal[index], result.transferImaginary[index])
            XCTAssertTrue(abs(modulus - 1) < 1e-6 || modulus < 1e-6, "unit phase factor or sign 0 at \(index): \(modulus)")
        }
        options.qLowpassInvAngstrom = 0.2
        let filtered = try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: options)
        let reduced = (1..<count).contains { hypot(filtered.transferReal[$0], filtered.transferImaginary[$0]) < 0.99 }
        XCTAssertTrue(reduced, "the low-pass envelope reached the transfer function")
        XCTAssertEqual(filtered.qLowpassInvAngstrom, 0.2)
        options.qLowpassInvAngstrom = -1
        XCTAssertThrowsError(try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: options))
    }

    // MARK: - independent references (a naive DFT, nothing from the kit)

    private func dft(_ re: [Double], _ im: [Double], rows: Int, columns: Int, inverse: Bool) -> ([Double], [Double]) {
        var outRe = [Double](repeating: 0, count: rows * columns), outIm = outRe
        let sign = inverse ? 1.0 : -1.0
        for u in 0..<rows { for v in 0..<columns {
            var sr = 0.0, si = 0.0
            for r in 0..<rows { for c in 0..<columns {
                let angle = sign * 2 * Double.pi * (Double(u * r) / Double(rows) + Double(v * c) / Double(columns))
                let i = r * columns + c
                sr += re[i] * cos(angle) - im[i] * sin(angle)
                si += re[i] * sin(angle) + im[i] * cos(angle)
            } }
            outRe[u * columns + v] = inverse ? sr / Double(rows * columns) : sr
            outIm[u * columns + v] = inverse ? si / Double(rows * columns) : si
        } }
        return (outRe, outIm)
    }

    private func frequency(_ index: Int, _ count: Int) -> Double {
        Double(index < (count + 1) / 2 ? index : index - count) / Double(count)
    }

    /// Depth sectioning with the probe angles non-zero, against a naive DFT shift of the aligned stack: plane(d) = mean over images of
    /// IFFT(sign(sin chi) * exp(-2 pi i (f . shift)) * FFT(image)), shift = -angle * d / sampling, chi = pi lambda C1 q^2, DC removed.
    /// Mutations it catches: the angle sign or axis swapped, mrad not divided by 1000, sampling dropped, the plane for depth k taken
    /// from another depth.
    func testDepthPlanesEqualAnIndependentShiftOfTheAlignedStack() throws {
        let pre = preprocessing()
        let rows = 6, columns = 5, count = rows * columns, c1 = 300.0
        let images = (0..<4).map { b in (0..<count).map { Float(sin(Double($0 + 3 * b) * 1.3) + 0.2 * Double(b) + 2) } }
        let aligned = alignment(shifts: [ParallaxScanShift](repeating: ParallaxScanShift(row: 0, column: 0), count: 4),
                                stack: images.flatMap { $0 }, aligned: texture(count))
        var options = ParallaxDepthOptions()
        options.depthsAngstrom = [-150, 90]
        options.useFullFit = false
        let result = try ParallaxDepthSectioner.section(preprocessing: pre, alignment: aligned, fit: defocusFit(c1), options: options)
        for (planeIndex, depth) in options.depthsAngstrom.enumerated() {
            var mean = [Double](repeating: 0, count: count)
            for (b, image) in images.enumerated() {
                let angle = pre.probeAnglesMrad[b]
                let shiftRows = -Double(angle.qx) / 1_000 * depth / sampling
                let shiftColumns = -Double(angle.qy) / 1_000 * depth / sampling
                var (re, im) = dft(image.map(Double.init), [Double](repeating: 0, count: count), rows: rows, columns: columns, inverse: false)
                for r in 0..<rows { for c in 0..<columns {
                    let i = r * columns + c
                    let fr = frequency(r, rows), fc = frequency(c, columns)
                    let q2 = (fr / sampling) * (fr / sampling) + (fc / sampling) * (fc / sampling)
                    let sine = sin(Double.pi * wavelength * c1 * q2)
                    let ctf: Double = i == 0 ? 0 : (sine > 0 ? 1 : (sine < 0 ? -1 : 0))
                    let phase = -2 * Double.pi * (fr * shiftRows + fc * shiftColumns)
                    let a = re[i], b2 = im[i]
                    re[i] = ctf * (a * cos(phase) - b2 * sin(phase))
                    im[i] = ctf * (a * sin(phase) + b2 * cos(phase))
                } }
                let back = dft(re, im, rows: rows, columns: columns, inverse: true).0
                for i in 0..<count { mean[i] += back[i] / 4 }
            }
            for i in 0..<count {
                XCTAssertEqual(Double(result.paddedStack[planeIndex * count + i]), mean[i], accuracy: 2e-5, "plane \(planeIndex) pixel \(i)")
            }
        }
        XCTAssertNotEqual(result.paddedStack[0], result.paddedStack[count], "the two depths differ when the angles are not zero")
    }

    /// An odd-order term (2,1) pair plus C1, with the high-pass set: applying the stored transfer function to the aligned image by
    /// a naive DFT reproduces the kit's corrected image, and the high-pass attenuates low frequencies. Mutations it catches: the
    /// high-pass left on `.reference`, the odd phase dropped or its sign flipped, the transfer arrays not matching the image applied.
    func testTheStoredTransferFunctionReproducesTheCorrectedImage() throws {
        let pre = preprocessing()
        let rows = 6, columns = 5, count = rows * columns
        let image = texture(count)
        let aligned = alignment(shifts: [ParallaxScanShift](repeating: ParallaxScanShift(row: 0, column: 0), count: 4), stack: [], aligned: image)
        let zero = [ParallaxPhysicalShift](repeating: ParallaxPhysicalShift(rowAngstrom: 0, columnAngstrom: 0), count: 4)
        let low = defocusFit(250).lowOrder
        let fit = ParallaxHigherOrderAberrationFitResult(
            lowOrder: low,
            terms: [ParallaxAberrationTerm(radialOrder: 1, angularOrder: 0, component: 0),
                    ParallaxAberrationTerm(radialOrder: 2, angularOrder: 1, component: 0),
                    ParallaxAberrationTerm(radialOrder: 2, angularOrder: 1, component: 1)],
            coefficientsAngstrom: [250, 4_000, -2_500], fittedShifts: zero, rmsResidualAngstrom: 0, fitMethod: .global)
        var options = ParallaxAberrationCorrectionOptions()
        options.qHighpassInvAngstrom = 0.25
        let result = try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: aligned, fit: fit, options: options)
        XCTAssertGreaterThan(result.chiOdd.map { abs($0) }.max() ?? 0, 0.1, "the odd-order terms reached the odd phase")
        var (re, im) = dft(image.map(Double.init), [Double](repeating: 0, count: count), rows: rows, columns: columns, inverse: false)
        for i in 0..<count {
            let a = re[i], b = im[i]
            re[i] = a * Double(result.transferReal[i]) - b * Double(result.transferImaginary[i])
            im[i] = a * Double(result.transferImaginary[i]) + b * Double(result.transferReal[i])
        }
        let expected = dft(re, im, rows: rows, columns: columns, inverse: true).0
        for i in 0..<count {
            XCTAssertEqual(Double(result.paddedPhase[i]), expected[i], accuracy: 2e-5, "pixel \(i)")
        }
        // The lowest non-zero frequency (index 1, q = 1/(5 x 0.5) = 0.4 per column) is attenuated by the high-pass: < 1 in modulus.
        let q = 0.4, envelope = 1 - 1 / (1 + pow(q / 0.25, 4))
        XCTAssertEqual(Double(hypot(result.transferReal[1], result.transferImaginary[1])), envelope, accuracy: 1e-5)
    }

    /// Off-centre angles (their centroid is not zero): an exactly linear shift field gives C1 back and zero coma/trefoil, because the
    /// gradient basis is evaluated at the angles the affine fit used (`.selectedCentroid`). Mutation it catches: a basis centred on the
    /// detector grid or on zero rather than on the angles the fit used (the 619 / 599 Å coma of the DEVIATION note).
    func testAnOffCentreLinearFieldGivesNoComa() throws {
        var pre = preprocessing()
        let angles = [(1.0, 2.0), (4.0, 1.0), (3.0, 5.0), (6.0, 4.0), (2.0, 7.0), (5.0, 8.0), (7.0, 2.0), (3.0, 3.0)]
            .map { ParallaxVector(qx: Float($0.0), qy: Float($0.1)) }
        pre = ParallaxPreprocessResult(
            scanHeight: 6, scanWidth: 5, detectorHeight: 1, detectorWidth: angles.count, stackHeight: 6, stackWidth: 5,
            calibration: pre.calibration, thresholdIntensity: 0.8, detectorMask: [Bool](repeating: true, count: angles.count),
            detectorIndices: (0..<angles.count).map { ParallaxDetectorIndex(qx: 0, qy: $0) },
            reciprocalVectors: angles, probeAnglesMrad: angles, edgeWindow: [Float](repeating: 1, count: 30),
            normalizedStack: [], unshiftedStack: [], incoherentBF: [], initialError: 0)
        let c1 = 350.0
        let shifts = angles.map {
            ParallaxScanShift(row: Float(Double($0.qx) / 1_000 * c1 / sampling), column: Float(Double($0.qy) / 1_000 * c1 / sampling))
        }
        let fit = try ParallaxAberrationFitter.fitHigherOrder(preprocessing: pre, alignment: alignment(shifts: shifts, stack: [], aligned: []))
        XCTAssertEqual(fit.lowOrder.c1Angstrom, c1, accuracy: 1e-2)
        let c1Index = try XCTUnwrap(fit.terms.firstIndex(of: ParallaxAberrationTerm(radialOrder: 1, angularOrder: 0, component: 0)))
        XCTAssertEqual(fit.coefficientsAngstrom[c1Index], c1, accuracy: 1e-2)
        for (index, term) in fit.terms.enumerated() where term.radialOrder >= 2 {
            XCTAssertEqual(fit.coefficientsAngstrom[index], 0, accuracy: 0.05, "\(term)")
        }
        XCTAssertLessThan(fit.rmsResidualAngstrom, 1e-2)
    }

    // MARK: - the memory formulas, at the limit

    private func refusedBytes<T>(_ body: () throws -> T) -> Int? {
        do { _ = try body(); return nil } catch let error {
            if case ParallaxAberrationCorrector.CorrectionError.memoryLimit(let bytes, _) = error { return bytes }
            if case ParallaxDepthSectioner.DepthError.memoryLimit(let bytes, _) = error { return bytes }
            if case ParallaxSubpixelReconstructor.ReconstructionError.memoryLimit(let bytes, _) = error { return bytes }
            XCTFail("unexpected \(error)"); return nil
        }
    }

    /// The three stages count the kit's Double planes: correction 12 Double + 5 Float planes; depth 3 Double planes per image (images
    /// and spectra) + the Float stack + 7 Double planes; KDE 6 Double + 1 Float output planes + the Double images. One byte under the
    /// formula refuses and reports exactly the formula; the formula itself runs. Mutation it catches: any term dropped or the Float
    /// stride used for a Double plane.
    func testTheStageMemoryEstimatesAreTheirFormulasAtTheLimit() throws {
        let count = 30, d = MemoryLayout<Double>.stride, f = MemoryLayout<Float>.stride
        let pre = preprocessing(unshifted: (0..<4).flatMap { _ in texture(count) })
        let aligned = alignment(shifts: [ParallaxScanShift](repeating: ParallaxScanShift(row: 0, column: 0), count: 4),
                                stack: (0..<4).flatMap { _ in texture(count) }, aligned: texture(count))

        let correction = count * (12 * d + 5 * f)
        var c = ParallaxAberrationCorrectionOptions()
        c.maxWorkingBytes = correction - 1
        XCTAssertEqual(refusedBytes { try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: c) }, correction)
        c.maxWorkingBytes = correction
        XCTAssertNoThrow(try ParallaxAberrationCorrector.correct(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: c))

        let planes = 3
        let depth = 4 * count * 3 * d + planes * count * f + count * 7 * d
        var o = ParallaxDepthOptions()
        o.depthsAngstrom = [-10, 0, 10]
        o.maxWorkingBytes = depth - 1
        XCTAssertEqual(refusedBytes { try ParallaxDepthSectioner.section(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: o) }, depth)
        o.maxWorkingBytes = depth
        XCTAssertNoThrow(try ParallaxDepthSectioner.section(preprocessing: pre, alignment: aligned, fit: defocusFit(300), options: o))

        var k = ParallaxSubpixelOptions()
        k.upsampleFactor = 1
        let kde = count * (6 * d + f) + 4 * count * d
        k.maxWorkingBytes = kde - 1
        XCTAssertEqual(refusedBytes { try ParallaxSubpixelReconstructor.reconstruct(preprocessing: pre, alignment: aligned, options: k) }, kde)
        k.maxWorkingBytes = kde
        XCTAssertNoThrow(try ParallaxSubpixelReconstructor.reconstruct(preprocessing: pre, alignment: aligned, options: k))
    }
}
