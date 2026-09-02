//
//  ParallaxAberrationCorrection.swift
//  py4DSTEM-compatible parallax CTF phase correction.
//

import Foundation

package nonisolated struct ParallaxAberrationCorrectionOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init() {}

    package var useFullFit = true
    package var qLowpassInvAngstrom: Double? = nil
    /// High-pass support follows py4DSTEM's shared Butterworth envelope; the
    /// current parallax.py signature exposes this value but does not apply it.
    package var qHighpassInvAngstrom: Double? = nil
    package var butterworthOrder = 2
    package var maxWorkingBytes = 536_870_912
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
    package init(paddedPhase: [Float], correctedPhase: FloatImage, chiEven: [Float], chiOdd: [Float], transferReal: [Float], transferImaginary: [Float], samplingAngstrom: Double, usedFullFit: Bool, qLowpassInvAngstrom: Double?, qHighpassInvAngstrom: Double?, butterworthOrder: Int) {
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
        case fftUnavailable
        case cancelled

        package var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot correct the parallax phase: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax phase correction needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above its \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) limit."
            case .fftUnavailable:
                return "Could not create the exact-shape FFT used for phase correction."
            case .cancelled:
                return "Parallax phase correction was cancelled."
            }
        }
    }

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
        let workingBytes = count * MemoryLayout<Float>.stride * 10
        guard workingBytes <= options.maxWorkingBytes else {
            throw CorrectionError.memoryLimit(
                bytes: workingBytes, limit: options.maxWorkingBytes
            )
        }
        guard let fft = FFT2D(nx: width, ny: height) else {
            throw CorrectionError.fftUnavailable
        }

        var chiEven = [Float](repeating: 0, count: count)
        var chiOdd = [Float](repeating: 0, count: count)
        for row in 0..<height {
            try checkCancellation(cancellation)
            let kRow = Double(FFT2D.fftfreq(row, height)) / sampling
            for column in 0..<width {
                let kColumn = Double(FFT2D.fftfreq(column, width)) / sampling
                let frequency = hypot(kRow, kColumn)
                let alpha = frequency * preprocessing.calibration.wavelengthAngstrom
                let theta = atan2(kColumn, kRow)
                let index = row * width + column
                if options.useFullFit {
                    var even: Double = 0, odd: Double = 0
                    for (term, coefficient) in zip(
                        fit.terms, fit.coefficientsAngstrom
                    ) {
                        let radial = pow(alpha, Double(term.radialOrder + 1))
                            / Double(term.radialOrder + 1)
                        let basis: Double
                        if term.angularOrder == 0 {
                            basis = radial
                        } else if term.component == 0 {
                            basis = radial * cos(Double(term.angularOrder) * theta)
                        } else {
                            basis = radial * sin(Double(term.angularOrder) * theta)
                        }
                        if term.radialOrder.isMultiple(of: 2) {
                            odd += basis * coefficient
                        } else {
                            even += basis * coefficient
                        }
                    }
                    let scale = 2 * Double.pi
                        / preprocessing.calibration.wavelengthAngstrom
                    chiEven[index] = Float(even * scale)
                    chiOdd[index] = Float(odd * scale)
                } else {
                    chiEven[index] = Float(
                        Double.pi * preprocessing.calibration.wavelengthAngstrom
                            * fit.lowOrder.c1Angstrom * frequency * frequency
                    )
                }
            }
        }
        if options.useFullFit && !chiEven.contains(where: { $0 != 0 }) {
            chiEven = [Float](repeating: 1, count: count)
        }

        var transferReal = [Float](repeating: 0, count: count)
        var transferImaginary = [Float](repeating: 0, count: count)
        for row in 0..<height {
            let kRow = Double(FFT2D.fftfreq(row, height)) / sampling
            for column in 0..<width {
                let kColumn = Double(FFT2D.fftfreq(column, width)) / sampling
                let frequency = hypot(kRow, kColumn)
                let index = row * width + column
                let sign: Double = sin(Double(chiEven[index])) > 0 ? 1
                    : (sin(Double(chiEven[index])) < 0 ? -1 : 0)
                var envelope: Double = 1
                if let lowpass = options.qLowpassInvAngstrom {
                    envelope /= 1 + pow(
                        frequency / lowpass,
                        Double(2 * options.butterworthOrder)
                    )
                }
                if let highpass = options.qHighpassInvAngstrom {
                    envelope *= 1 - 1 / (1 + pow(
                        frequency / highpass,
                        Double(2 * options.butterworthOrder)
                    ))
                }
                transferReal[index] = Float(
                    sign * cos(Double(chiOdd[index])) * envelope
                )
                transferImaginary[index] = Float(
                    -sign * sin(Double(chiOdd[index])) * envelope
                )
            }
        }
        transferReal[0] = 0
        transferImaginary[0] = 0

        var real = alignment.alignedBF
        var imaginary = [Float](repeating: 0, count: count)
        fft.transform(re: &real, im: &imaginary, forward: true)
        for index in 0..<count {
            let oldReal = real[index], oldImaginary = imaginary[index]
            real[index] = oldReal * transferReal[index]
                - oldImaginary * transferImaginary[index]
            imaginary[index] = oldReal * transferImaginary[index]
                + oldImaginary * transferReal[index]
        }
        try checkCancellation(cancellation)
        fft.transform(re: &real, im: &imaginary, forward: false,
                      scaleInverse: true)
        try checkCancellation(cancellation)

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
            chiEven: chiEven, chiOdd: chiOdd,
            transferReal: transferReal, transferImaginary: transferImaginary,
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
