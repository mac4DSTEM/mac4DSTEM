//
//  ParallaxAberrationCorrection.swift
//  py4DSTEM-compatible parallax CTF phase correction: the app's options, result and memory/cancellation wrapper around
//  CuboKit 0.6.0's CuboParallax.ParallaxAberrationCorrection.
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
    /// the app keeps the memory refusal and the cancellation checks around the call (the kit call is one transform pair with no
    /// hook, so a cancel lands before it or after it). The transfer function the product stores is the kit's (`transferReal`,
    /// `transferImaginary`, CuboKit 0.6.0).
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
            transferReal: kit.transferReal.map(Float.init), transferImaginary: kit.transferImaginary.map(Float.init),
            samplingAngstrom: sampling, usedFullFit: options.useFullFit,
            qLowpassInvAngstrom: options.qLowpassInvAngstrom,
            qHighpassInvAngstrom: options.qHighpassInvAngstrom,
            butterworthOrder: options.butterworthOrder
        )
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
