//
//  ParallaxSubpixelReconstruction.swift
//  py4DSTEM Parallax.subpixel_alignment. The kernel-density deposition and the factor heuristic are CuboKit 0.4.0's
//  CuboParallax.ParallaxSubpixel; the position-correction loop (the app's Float variant, cancellation and progress) stays here:
//  delete at a CuboKit whose correctPositions offers the app's variant.
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
            // dx, dy, step, scores, four trial score maps, and fixed-step scores (Float), and the Double probe offsets handed to the kit.
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

        var probeRows = [Float](repeating: 0, count: planeCount)
        var probeColumns = [Float](repeating: 0, count: planeCount)
        // The unshifted stack and the shifts as the kit's Double inputs, converted once for every deposition below.
        let images: [[Double]] = (0..<preprocessing.brightFieldPixelCount).map { bf in
            preprocessing.unshiftedStack[(bf * planeCount)..<((bf + 1) * planeCount)].map(Double.init)
        }
        let shifts = alignment.totalShifts.map {
            CuboParallax.ParallaxShift(row: Double($0.row), column: Double($0.column))
        }
        func deposit() throws -> [Float] {
            try checkCancellation(cancellation)
            return try kernelDensity(
                images: images, shifts: shifts, rows: preprocessing.stackHeight, columns: preprocessing.stackWidth,
                probeRows: probeRows, probeColumns: probeColumns, factor: factor,
                sigmaPixels: options.kdeSigmaPixels, lanczosOrder: options.lanczosOrder, lowpass: options.lowpassFilter
            )
        }
        var pixelOutput = try deposit()
        progress?(options.positionCorrectionIterations == nil ? 0.9 : 0.2)

        var correctionScores = [Float]()
        if let iterations = options.positionCorrectionIterations {
            var step = [Float](
                repeating: options.positionCorrectionInitialStep, count: planeCount
            )
            let window = paddedWindow(preprocessing)
            var scores = try scoreMap(
                image: pixelOutput, outputWidth: outputWidth, outputHeight: outputHeight,
                preprocessing: preprocessing, alignment: alignment,
                probeRows: probeRows, probeColumns: probeColumns,
                factor: Float(factor), window: window, cancellation: cancellation
            )
            correctionScores.append(mean(scores))
            let directions: [(Float, Float)] = options.positionCorrectionCheckerboard
                ? [(-1, 0), (1, 0), (0, -1), (0, 1)]
                : [(-0.5, 0), (0.5, 0), (0, -0.5), (0, 0.5)]
            for iteration in 0..<iterations {
                try checkCancellation(cancellation)
                var trials = [[Float]]()
                for direction in directions {
                    let trialRows = zip(probeRows, step).map {
                        $0.0 + direction.0 * $0.1
                    }
                    let trialColumns = zip(probeColumns, step).map {
                        $0.0 + direction.1 * $0.1
                    }
                    trials.append(try scoreMap(
                        image: pixelOutput, outputWidth: outputWidth,
                        outputHeight: outputHeight, preprocessing: preprocessing,
                        alignment: alignment, probeRows: trialRows,
                        probeColumns: trialColumns, factor: Float(factor),
                        window: nil, cancellation: cancellation
                    ))
                }
                var update = [Bool](repeating: false, count: planeCount)
                if options.positionCorrectionCheckerboard {
                    for index in 0..<planeCount {
                        var best = 0
                        var bestScore = trials[0][index] * window[index]
                        for direction in 1..<4 {
                            let value = trials[direction][index] * window[index]
                            if value < bestScore { best = direction; bestScore = value }
                        }
                        if bestScore < scores[index] {
                            update[index] = true
                            probeRows[index] += directions[best].0 * step[index] * window[index]
                            probeColumns[index] += directions[best].1 * step[index] * window[index]
                        }
                    }
                } else {
                    var deltaRows = [Float](repeating: 0, count: planeCount)
                    var deltaColumns = [Float](repeating: 0, count: planeCount)
                    for index in 0..<planeCount {
                        let gradientRow = trials[0][index] - trials[1][index]
                        let gradientColumn = trials[2][index] - trials[3][index]
                        let denominator = hypot(gradientRow, gradientColumn) / step[index]
                        if denominator.isFinite, denominator > 0 {
                            deltaRows[index] = gradientRow * window[index] / denominator
                            deltaColumns[index] = gradientColumn * window[index] / denominator
                        }
                    }
                    let trialRows = zip(probeRows, deltaRows).map(+)
                    let trialColumns = zip(probeColumns, deltaColumns).map(+)
                    let fixed = try scoreMap(
                        image: pixelOutput, outputWidth: outputWidth,
                        outputHeight: outputHeight, preprocessing: preprocessing,
                        alignment: alignment, probeRows: trialRows,
                        probeColumns: trialColumns, factor: Float(factor),
                        window: window, cancellation: cancellation
                    )
                    for index in 0..<planeCount where fixed[index] < scores[index] {
                        update[index] = true
                        probeRows[index] += deltaRows[index]
                        probeColumns[index] += deltaColumns[index]
                    }
                }
                for index in 0..<planeCount where !update[index] {
                    step[index] = max(
                        step[index] * options.positionCorrectionStepFactor,
                        options.positionCorrectionMinimumStep
                    )
                }
                pixelOutput = try deposit()
                scores = try scoreMap(
                    image: pixelOutput, outputWidth: outputWidth,
                    outputHeight: outputHeight, preprocessing: preprocessing,
                    alignment: alignment, probeRows: probeRows,
                    probeColumns: probeColumns, factor: Float(factor),
                    window: window, cancellation: cancellation
                )
                correctionScores.append(mean(scores))
                progress?(0.2 + 0.7 * Double(iteration + 1) / Double(max(iterations, 1)))
            }
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

    /// CuboParallax's `ParallaxSubpixel.kernelDensity` (bilinear or Lanczos deposition, Gaussian blur, density division, optional
    /// pixel-sinc low-pass) with the current probe-position offsets, back to the Float image the scoring reads.
    private static func kernelDensity(
        images: [[Double]], shifts: [CuboParallax.ParallaxShift], rows: Int, columns: Int,
        probeRows: [Float], probeColumns: [Float], factor: Double,
        sigmaPixels: Double, lanczosOrder: Int?, lowpass: Bool
    ) throws -> [Float] {
        do {
            let result = try CuboParallax.ParallaxSubpixel.kernelDensity(
                images: images, rows: rows, columns: columns, shifts: shifts, factor: factor,
                sigmaPixels: sigmaPixels, lanczosOrder: lanczosOrder, lowpass: lowpass,
                probeOffsets: CuboParallax.ParallaxProbeOffsets(
                    rows: probeRows.map(Double.init), columns: probeColumns.map(Double.init))
            )
            return result.image.map(Float.init)
        } catch {
            throw ReconstructionError.invalidInput(parallaxKitReason(error))
        }
    }

    private static func scoreMap(
        image: [Float], outputWidth: Int, outputHeight: Int,
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        probeRows: [Float], probeColumns: [Float], factor: Float,
        window: [Float]?, cancellation: AnalysisCancellationToken?
    ) throws -> [Float] {
        let width = preprocessing.stackWidth
        let height = preprocessing.stackHeight
        let planeCount = width * height
        var scores = [Float](repeating: 0, count: planeCount)
        for row in 0..<height {
            if row & 7 == 0 { try checkCancellation(cancellation) }
            for column in 0..<width {
                let position = row * width + column
                var score: Float = 0
                for bf in 0..<preprocessing.brightFieldPixelCount {
                    let coordinateRow = (
                        Float(row) + probeRows[position] + alignment.totalShifts[bf].row
                    ) * factor
                    let coordinateColumn = (
                        Float(column) + probeColumns[position]
                            + alignment.totalShifts[bf].column
                    ) * factor
                    let sampled = bilinearSample(
                        image, width: outputWidth, height: outputHeight,
                        row: coordinateRow, column: coordinateColumn
                    )
                    score += abs(sampled - preprocessing.unshiftedStack[
                        bf * planeCount + position
                    ])
                }
                score /= Float(preprocessing.brightFieldPixelCount)
                scores[position] = score * (window?[position] ?? 1)
            }
        }
        return scores
    }

    private static func bilinearSample(
        _ image: [Float], width: Int, height: Int, row: Float, column: Float
    ) -> Float {
        let rowFloor = Int(floor(row)), columnFloor = Int(floor(column))
        let rowFraction = row - Float(rowFloor)
        let columnFraction = column - Float(columnFloor)
        let row0 = wrapped(rowFloor, count: height)
        let row1 = wrapped(rowFloor + 1, count: height)
        let column0 = wrapped(columnFloor, count: width)
        let column1 = wrapped(columnFloor + 1, count: width)
        return image[row0 * width + column0] * (1 - rowFraction) * (1 - columnFraction)
            + image[row1 * width + column0] * rowFraction * (1 - columnFraction)
            + image[row0 * width + column1] * (1 - rowFraction) * columnFraction
            + image[row1 * width + column1] * rowFraction * columnFraction
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

    private static func mean(_ values: [Float]) -> Float {
        values.reduce(0, +) / Float(values.count)
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

    private static func wrapped(_ value: Int, count: Int) -> Int {
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true {
            throw ReconstructionError.cancelled
        }
    }
}
