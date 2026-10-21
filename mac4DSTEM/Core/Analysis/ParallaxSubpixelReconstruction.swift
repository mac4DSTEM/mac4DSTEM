//
//  ParallaxSubpixelReconstruction.swift
//  py4DSTEM Parallax.subpixel_alignment. The kernel-density deposition, the factor heuristic and the position-correction loop (the
//  app's Float variant) are CuboKit 0.6.0's CuboParallax.ParallaxSubpixel; this file keeps the options, the memory refusal and the crop.
//

import CuboParallax
import Foundation

package nonisolated struct ParallaxSubpixelOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init() {}

    /// Nil selects py4DSTEM's BF/DF sampling-limit heuristic.
    package var upsampleFactor: Double? = nil
    package var kdeSigmaPixels: Double = 0.125
    package var lowpassFilter = false
    /// Nil selects bilinear deposition. A positive value selects py4DSTEM's
    /// current Lanczos helper, including its checked-in Cartesian weight rule.
    package var lanczosOrder: Int? = nil
    /// Nil disables probe-position correction; zero records the baseline score.
    package var positionCorrectionIterations: Int? = nil
    package var positionCorrectionInitialStep: Float = 1
    package var positionCorrectionMinimumStep: Float = 0.1
    package var positionCorrectionStepFactor: Float = 0.75
    package var positionCorrectionCheckerboard = false
    package var maxWorkingBytes = PhaseContrastMemoryBudget.workingLimitBytes
}

package nonisolated struct ParallaxSubpixelResult: Sendable {
    package let upsampleFactor: Double
    package let brightFieldUpsampleLimit: Double
    package let darkFieldUpsampleLimit: Double
    package let kdeSigmaPixels: Double
    package let lowpassFilter: Bool
    package let lanczosOrder: Int?
    package let paddedHeight: Int
    package let paddedWidth: Int
    package let paddedBF: [Float]
    package let croppedBF: FloatImage
    package let outputSamplingAngstrom: Double
    /// Padded scan-grid shifts in input scan pixels.
    package let probeShiftRows: [Float]
    package let probeShiftColumns: [Float]
    package let positionCorrectionScores: [Float]

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(upsampleFactor: Double, brightFieldUpsampleLimit: Double, darkFieldUpsampleLimit: Double, kdeSigmaPixels: Double, lowpassFilter: Bool, lanczosOrder: Int?, paddedHeight: Int, paddedWidth: Int, paddedBF: [Float], croppedBF: FloatImage, outputSamplingAngstrom: Double, probeShiftRows: [Float], probeShiftColumns: [Float], positionCorrectionScores: [Float]) {
        self.upsampleFactor = upsampleFactor
        self.brightFieldUpsampleLimit = brightFieldUpsampleLimit
        self.darkFieldUpsampleLimit = darkFieldUpsampleLimit
        self.kdeSigmaPixels = kdeSigmaPixels
        self.lowpassFilter = lowpassFilter
        self.lanczosOrder = lanczosOrder
        self.paddedHeight = paddedHeight
        self.paddedWidth = paddedWidth
        self.paddedBF = paddedBF
        self.croppedBF = croppedBF
        self.outputSamplingAngstrom = outputSamplingAngstrom
        self.probeShiftRows = probeShiftRows
        self.probeShiftColumns = probeShiftColumns
        self.positionCorrectionScores = positionCorrectionScores
    }
}

package nonisolated enum ParallaxSubpixelReconstructor {
    package enum ReconstructionError: LocalizedError, Equatable {
        case invalidInput(String)
        case invalidOptions(String)
        case memoryLimit(bytes: Int, limit: Int)
        case cancelled

        package var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot upsample the parallax reconstruction: \(detail)."
            case .invalidOptions(let detail):
                return "Invalid parallax KDE options: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax KDE needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above the \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) working limit. Reduce the factor or crop/bin the dataset first."
            case .cancelled:
                return "Parallax KDE reconstruction was cancelled."
            }
        }
    }

    package static func reconstruct(
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        options: ParallaxSubpixelOptions = ParallaxSubpixelOptions(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ParallaxSubpixelResult {
        guard alignment.isComplete else {
            throw ReconstructionError.invalidInput("alignment is not complete")
        }
        let planeCount = preprocessing.stackHeight * preprocessing.stackWidth
        guard preprocessing.unshiftedStack.count
                == preprocessing.brightFieldPixelCount * planeCount,
              alignment.totalShifts.count == preprocessing.brightFieldPixelCount,
              alignment.stackHeight == preprocessing.stackHeight,
              alignment.stackWidth == preprocessing.stackWidth else {
            throw ReconstructionError.invalidInput("preprocessing and alignment shapes differ")
        }
        guard options.kdeSigmaPixels.isFinite, options.kdeSigmaPixels >= 0,
              options.maxWorkingBytes > 0 else {
            throw ReconstructionError.invalidOptions(
                "sigma must be finite and non-negative, and the memory limit must be positive"
            )
        }
        if let order = options.lanczosOrder, order < 1 {
            throw ReconstructionError.invalidOptions("Lanczos order must be positive")
        }
        if let iterations = options.positionCorrectionIterations, iterations < 0 {
            throw ReconstructionError.invalidOptions(
                "position-correction iterations cannot be negative"
            )
        }
        guard options.positionCorrectionInitialStep.isFinite,
              options.positionCorrectionInitialStep > 0,
              options.positionCorrectionMinimumStep.isFinite,
              options.positionCorrectionMinimumStep > 0,
              options.positionCorrectionStepFactor.isFinite,
              options.positionCorrectionStepFactor > 0,
              options.positionCorrectionStepFactor <= 1 else {
            throw ReconstructionError.invalidOptions(
                "position step sizes must be positive and the reduction factor must be in (0, 1]"
            )
        }
        try checkCancellation(cancellation)

        let maximumK = preprocessing.reciprocalVectors.reduce(0.0) {
            max($0, Double(hypot($1.qx, $1.qy)))
        }
        guard maximumK.isFinite, maximumK > 0 else {
            throw ReconstructionError.invalidInput(
                "the bright-field mask has no non-zero reciprocal-space extent"
            )
        }
        let scanSampling = preprocessing.calibration.scanSamplingAngstrom
        // The factor heuristic is CuboParallax's (py4DSTEM `subpixel_alignment`): bright-field limit, dark-field limit, requested factor.
        let limits: CuboParallax.ParallaxUpsampleLimits
        do {
            limits = try CuboParallax.ParallaxSubpixel.upsampleLimits(
                scanSampling: scanSampling, maxReciprocalVector: maximumK,
                reciprocalSampling: preprocessing.calibration.reciprocalSamplingInvAngstrom,
                detectorRows: preprocessing.detectorHeight, requested: options.upsampleFactor
            )
        } catch {
            throw ReconstructionError.invalidOptions("upsample factor must be at least 1")
        }
        let bfLimit = limits.brightField
        let dfLimit = limits.darkField
        let factor = limits.factor

        let outputHeight = Int(
            (Double(preprocessing.stackHeight) * factor).rounded(.toNearestOrEven)
        )
        let outputWidth = Int(
            (Double(preprocessing.stackWidth) * factor).rounded(.toNearestOrEven)
        )
        guard outputHeight > 0, outputWidth > 0,
              outputHeight <= Int.max / outputWidth else {
            throw ReconstructionError.invalidOptions("upsampled dimensions overflow")
        }
        let outputCount = outputHeight * outputWidth
        // The kit's deposition works in Double: the density and sum accumulators, their blur copies (and the spectrum pair when the
        // low-pass is on), plus the Float output the position-correction scoring reads and the unshifted stack as Double images.
        // Deliberately conservative; it excludes the already-resident Float preprocessing data.
        let doubleArrayCount = options.lowpassFilter ? 8 : 6
        guard outputCount <= Int.max / (MemoryLayout<Double>.stride * doubleArrayCount + MemoryLayout<Float>.stride),
              preprocessing.brightFieldPixelCount <= Int.max / planeCount / MemoryLayout<Double>.stride else {
            throw ReconstructionError.invalidOptions("working dimensions overflow")
        }
        var workingBytes = outputCount * (MemoryLayout<Double>.stride * doubleArrayCount + MemoryLayout<Float>.stride)
            + preprocessing.brightFieldPixelCount * planeCount * MemoryLayout<Double>.stride
        if options.positionCorrectionIterations != nil {
            // The kit's loop holds the offsets, steps, scores, four trial score maps and the fixed-step scores (Float) and the Double offsets it hands to each deposition.
            guard planeCount <= Int.max / (MemoryLayout<Float>.stride * 9 + MemoryLayout<Double>.stride * 2) else {
                throw ReconstructionError.invalidOptions("position work dimensions overflow")
            }
            workingBytes += planeCount * (MemoryLayout<Float>.stride * 9 + MemoryLayout<Double>.stride * 2)
        }
        guard workingBytes <= options.maxWorkingBytes else {
            throw ReconstructionError.memoryLimit(
                bytes: workingBytes, limit: options.maxWorkingBytes
            )
        }

        // The unshifted stack and the shifts as the kit's Double inputs.
        let images: [[Double]] = (0..<preprocessing.brightFieldPixelCount).map { bf in
            preprocessing.unshiftedStack[(bf * planeCount)..<((bf + 1) * planeCount)].map(Double.init)
        }
        let shifts = alignment.totalShifts.map {
            CuboParallax.ParallaxShift(row: Double($0.row), column: Double($0.column))
        }
        let isCancelled: () -> Bool = { cancellation?.isCancelled == true }
        var probeRows = [Float](repeating: 0, count: planeCount)
        var probeColumns = [Float](repeating: 0, count: planeCount)
        var pixelOutput: [Float]
        var correctionScores = [Float]()
        do {
            if let iterations = options.positionCorrectionIterations {
                // The app's Float loop is the kit's `.application` variant (CuboKit 0.6.0): Float offsets, steps and scores, no
                // regularisation, the step floor on rejected sites only, a zero gradient a zero move.
                var correction = CuboParallax.ParallaxPositionCorrectionOptions(iterations: iterations)
                correction.variant = .application
                correction.initialStep = Double(options.positionCorrectionInitialStep)
                correction.minimumStep = Double(options.positionCorrectionMinimumStep)
                correction.stepFactor = Double(options.positionCorrectionStepFactor)
                correction.checkerboard = options.positionCorrectionCheckerboard
                let result = try CuboParallax.ParallaxSubpixel.correctPositions(
                    images: images, rows: preprocessing.stackHeight, columns: preprocessing.stackWidth, shifts: shifts,
                    window: paddedWindow(preprocessing).map(Double.init),
                    scanSampling: CuboParallax.ParallaxShift(row: scanSampling, column: scanSampling), factor: factor,
                    sigmaPixels: options.kdeSigmaPixels, lanczosOrder: options.lanczosOrder, lowpass: options.lowpassFilter,
                    options: correction, isCancelled: isCancelled,
                    progress: { completed, total in progress?(0.2 + 0.7 * Double(completed) / Double(max(total, 1))) }
                )
                pixelOutput = result.image.image.map(Float.init)
                probeRows = result.offsets.rows.map(Float.init)
                probeColumns = result.offsets.columns.map(Float.init)
                correctionScores = result.scores.map(Float.init)
            } else {
                pixelOutput = try CuboParallax.ParallaxSubpixel.kernelDensity(
                    images: images, rows: preprocessing.stackHeight, columns: preprocessing.stackWidth, shifts: shifts,
                    factor: factor, sigmaPixels: options.kdeSigmaPixels, lanczosOrder: options.lanczosOrder,
                    lowpass: options.lowpassFilter,
                    probeOffsets: CuboParallax.ParallaxProbeOffsets(
                        rows: probeRows.map(Double.init), columns: probeColumns.map(Double.init))
                ).image.map(Float.init)
                progress?(0.9)
            }
        } catch is CancellationError {
            throw ReconstructionError.cancelled
        } catch {
            throw ReconstructionError.invalidInput(parallaxKitReason(error))
        }
        try checkCancellation(cancellation)

        let paddingY = preprocessing.stackHeight - preprocessing.scanHeight
        let paddingX = preprocessing.stackWidth - preprocessing.scanWidth
        let cropped = crop(
            pixelOutput, width: outputWidth, height: outputHeight,
            paddingY: paddingY, paddingX: paddingX, factor: factor
        )
        progress?(1)
        return ParallaxSubpixelResult(
            upsampleFactor: factor,
            brightFieldUpsampleLimit: bfLimit,
            darkFieldUpsampleLimit: dfLimit,
            kdeSigmaPixels: options.kdeSigmaPixels,
            lowpassFilter: options.lowpassFilter,
            lanczosOrder: options.lanczosOrder,
            paddedHeight: outputHeight, paddedWidth: outputWidth,
            paddedBF: pixelOutput, croppedBF: cropped,
            outputSamplingAngstrom: scanSampling / factor,
            probeShiftRows: probeRows, probeShiftColumns: probeColumns,
            positionCorrectionScores: correctionScores
        )
    }

    private static func paddedWindow(
        _ preprocessing: ParallaxPreprocessResult
    ) -> [Float] {
        var window = [Float](
            repeating: 0, count: preprocessing.stackHeight * preprocessing.stackWidth
        )
        let top = (preprocessing.stackHeight - preprocessing.scanHeight) / 2
        let left = (preprocessing.stackWidth - preprocessing.scanWidth) / 2
        for row in 0..<preprocessing.scanHeight {
            for column in 0..<preprocessing.scanWidth {
                window[(top + row) * preprocessing.stackWidth + left + column]
                    = preprocessing.edgeWindow[row * preprocessing.scanWidth + column]
            }
        }
        return window
    }

    private static func crop(
        _ pixels: [Float], width: Int, height: Int,
        paddingY: Int, paddingX: Int, factor: Double
    ) -> FloatImage {
        let cropPaddingY = Int((Double(paddingY) * factor).rounded(.toNearestOrEven))
        let cropTop = Int((Double(paddingY) / 2 * factor).rounded(.toNearestOrEven))
        let cropPaddingX = Int((Double(paddingX) * factor).rounded(.toNearestOrEven))
        let cropLeft = Int((Double(paddingX) / 2 * factor).rounded(.toNearestOrEven))
        let cropHeight = height - cropPaddingY
        let cropWidth = width - cropPaddingX
        var cropped = [Float](repeating: 0, count: cropHeight * cropWidth)
        for row in 0..<cropHeight {
            let source = (cropTop + row) * width + cropLeft
            cropped.replaceSubrange(
                row * cropWidth..<(row + 1) * cropWidth,
                with: pixels[source..<(source + cropWidth)]
            )
        }
        return FloatImage(width: cropWidth, height: cropHeight, pixels: cropped)
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true {
            throw ReconstructionError.cancelled
        }
    }
}
