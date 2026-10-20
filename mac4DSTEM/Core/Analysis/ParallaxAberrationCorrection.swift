//
//  ParallaxAberrationCorrection.swift
//  py4DSTEM-compatible parallax CTF phase correction: the app's options, result and memory/cancellation wrapper around
//  CuboKit 0.4.0's CuboParallax.ParallaxAberrationCorrection.
//

import CuboParallax
import Foundation

package nonisolated struct ParallaxAberrationCorrectionOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init() {}

    package var useFullFit = true
    package var qLowpassInvAngstrom: Double? = nil
    /// High-pass support follows py4DSTEM's shared Butterworth envelope; the
    /// current parallax.py signature exposes this value but does not apply it.
    package var qHighpassInvAngstrom: Double? = nil
    package var butterworthOrder = 2
    package var maxWorkingBytes = PhaseContrastMemoryBudget.workingLimitBytes / 2
}

package nonisolated struct ParallaxAberrationCorrectionResult: Sendable {
    package let paddedPhase: [Float]
    package let correctedPhase: FloatImage
    package let chiEven: [Float]
    package let chiOdd: [Float]
    package let transferReal: [Float]
    package let transferImaginary: [Float]
    package let samplingAngstrom: Double
    package let usedFullFit: Bool
    package let qLowpassInvAngstrom: Double?
    package let qHighpassInvAngstrom: Double?
    package let butterworthOrder: Int

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(paddedPhase: [Float], correctedPhase: FloatImage, chiEven: [Float], chiOdd: [Float], transferReal: [Float], transferImaginary: [Float], samplingAngstrom: Double, usedFullFit: Bool, qLowpassInvAngstrom: Double?, qHighpassInvAngstrom: Double?, butterworthOrder: Int) {
        self.paddedPhase = paddedPhase
        self.correctedPhase = correctedPhase
        self.chiEven = chiEven
        self.chiOdd = chiOdd
        self.transferReal = transferReal
        self.transferImaginary = transferImaginary
        self.samplingAngstrom = samplingAngstrom
        self.usedFullFit = usedFullFit
        self.qLowpassInvAngstrom = qLowpassInvAngstrom
        self.qHighpassInvAngstrom = qHighpassInvAngstrom
        self.butterworthOrder = butterworthOrder
    }
}

package nonisolated enum ParallaxAberrationCorrector {
    package enum CorrectionError: LocalizedError, Equatable {
        case invalidInput(String)
        case memoryLimit(bytes: Int, limit: Int)
        case cancelled

        package var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot correct the parallax phase: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax phase correction needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above its \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) limit."
            case .cancelled:
                return "Parallax phase correction was cancelled."
            }
        }
    }

    /// CuboParallax's `ParallaxAberrationCorrection.correct` with `highpass: .apply` (this app's behaviour: the Butterworth high-pass
    /// envelope is applied, where the pinned py4DSTEM accepts and ignores it). The kit works in Double on the whole padded image;
    /// the app keeps the memory refusal and the cancellation checks around the call (the kit has no cancellation hook, so a cancel
    /// lands before the kit call or after it, not inside it: delete at a CuboKit with a cancellation token).
    package static func correct(
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        fit: ParallaxHigherOrderAberrationFitResult,
        options: ParallaxAberrationCorrectionOptions = .init(),
        cancellation: AnalysisCancellationToken? = nil
    ) throws -> ParallaxAberrationCorrectionResult {
        try checkCancellation(cancellation)
        let width = alignment.stackWidth
        let height = alignment.stackHeight
        let count = width * height
        guard alignment.isComplete, count > 0,
              alignment.alignedBF.count == count,
              fit.terms.count == fit.coefficientsAngstrom.count else {
            throw CorrectionError.invalidInput("alignment or aberration arrays are inconsistent")
        }
        let sampling = preprocessing.calibration.scanSamplingAngstrom
        guard sampling.isFinite, sampling > 0,
              options.butterworthOrder > 0,
              validCutoff(options.qLowpassInvAngstrom),
              validCutoff(options.qHighpassInvAngstrom),
              options.maxWorkingBytes > 0 else {
            throw CorrectionError.invalidInput("sampling, filters, or memory limit are invalid")
        }
        // The kit holds about twelve Double planes (image, both phase surfaces, frequencies, the transfer pair, the spectrum and its
        // scratch); the Float results (padded phase, both phases, the transfer pair) come on top.
        let (planeBytes, overflow) = count.multipliedReportingOverflow(
            by: 12 * MemoryLayout<Double>.stride + 5 * MemoryLayout<Float>.stride)
        guard !overflow else { throw CorrectionError.invalidInput("padded dimensions overflow") }
        let workingBytes = planeBytes
        guard workingBytes <= options.maxWorkingBytes else {
            throw CorrectionError.memoryLimit(
                bytes: workingBytes, limit: options.maxWorkingBytes
            )
        }
        let wavelength = preprocessing.calibration.wavelengthAngstrom
        let kit: CuboParallax.ParallaxCorrectionResult
        do {
            kit = try CuboParallax.ParallaxAberrationCorrection.correct(
                alignment.alignedBF.map(Double.init), rows: height, columns: width,
                sampling: CuboParallax.ParallaxShift(row: sampling, column: sampling),
                wavelength: wavelength,
                terms: fit.terms,
                coefficients: fit.coefficientsAngstrom,
                defocusOnly: options.useFullFit ? nil : fit.lowOrder.c1Angstrom,
                lowpass: options.qLowpassInvAngstrom, highpass: options.qHighpassInvAngstrom,
                butterworthOrder: options.butterworthOrder, highpassBehavior: .apply
            )
        } catch {
            throw CorrectionError.invalidInput(parallaxKitReason(error))
        }
        try checkCancellation(cancellation)

        // The transfer function the kit applied, from its phase surfaces: sign(sin chi_even) * exp(-i chi_odd) * the Butterworth
        // envelope, DC removed. The kit returns the corrected image and the two phase surfaces but not the transfer pair that the
        // product stores and the harness pins (delete at a CuboKit that returns the transfer function).
        var transferReal = [Float](repeating: 0, count: count)
        var transferImaginary = [Float](repeating: 0, count: count)
        for row in 0..<height {
            let kRow = frequency(row, height) / sampling
            for column in 0..<width {
                let kColumn = frequency(column, width) / sampling
                let q = hypot(kRow, kColumn)
                let index = row * width + column
                let sine = sin(kit.chiEven[index])
                let sign: Double = sine > 0 ? 1 : (sine < 0 ? -1 : 0)
                var envelope: Double = 1
                if let lowpass = options.qLowpassInvAngstrom {
                    envelope /= 1 + pow(q / lowpass, Double(2 * options.butterworthOrder))
                }
                if let highpass = options.qHighpassInvAngstrom {
                    envelope *= 1 - 1 / (1 + pow(q / highpass, Double(2 * options.butterworthOrder)))
                }
                transferReal[index] = Float(sign * cos(kit.chiOdd[index]) * envelope)
                transferImaginary[index] = Float(-sign * sin(kit.chiOdd[index]) * envelope)
            }
        }
        transferReal[0] = 0
        transferImaginary[0] = 0

        let real = kit.image.map(Float.init)
        let top = (height - preprocessing.scanHeight) / 2
        let left = (width - preprocessing.scanWidth) / 2
        var cropped = [Float](repeating: 0,
                              count: preprocessing.scanHeight * preprocessing.scanWidth)
        for row in 0..<preprocessing.scanHeight {
            let source = (top + row) * width + left
            cropped.replaceSubrange(
                (row * preprocessing.scanWidth)..<((row + 1) * preprocessing.scanWidth),
                with: real[source..<(source + preprocessing.scanWidth)]
            )
        }
        return ParallaxAberrationCorrectionResult(
            paddedPhase: real,
            correctedPhase: FloatImage(
                width: preprocessing.scanWidth,
                height: preprocessing.scanHeight,
                pixels: cropped
            ),
            chiEven: kit.chiEven.map(Float.init), chiOdd: kit.chiOdd.map(Float.init),
            transferReal: transferReal, transferImaginary: transferImaginary,
            samplingAngstrom: sampling, usedFullFit: options.useFullFit,
            qLowpassInvAngstrom: options.qLowpassInvAngstrom,
            qHighpassInvAngstrom: options.qHighpassInvAngstrom,
            butterworthOrder: options.butterworthOrder
        )
    }

    private static func frequency(_ index: Int, _ count: Int) -> Double {
        Double(index < (count + 1) / 2 ? index : index - count) / Double(count)
    }

    private static func validCutoff(_ value: Double?) -> Bool {
        value == nil || (value!.isFinite && value! > 0)
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true { throw CorrectionError.cancelled }
    }
}
