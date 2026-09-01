//
//  ParallaxSubpixelReconstruction.swift
//  Source-locked KDE and position-correction paths from py4DSTEM
//  Parallax.subpixel_alignment.
//

import Foundation

nonisolated struct ParallaxSubpixelOptions: Equatable, Sendable {
    /// Nil selects py4DSTEM's BF/DF sampling-limit heuristic.
    var upsampleFactor: Double? = nil
    var kdeSigmaPixels: Double = 0.125
    var lowpassFilter = false
    /// Nil selects bilinear deposition. A positive value selects py4DSTEM's
    /// current Lanczos helper, including its checked-in Cartesian weight rule.
    var lanczosOrder: Int? = nil
    /// Nil disables probe-position correction; zero records the baseline score.
    var positionCorrectionIterations: Int? = nil
    var positionCorrectionInitialStep: Float = 1
    var positionCorrectionMinimumStep: Float = 0.1
    var positionCorrectionStepFactor: Float = 0.75
    var positionCorrectionCheckerboard = false
    var maxWorkingBytes = 1_073_741_824
}

nonisolated struct ParallaxSubpixelResult: Sendable {
    let upsampleFactor: Double
    let brightFieldUpsampleLimit: Double
    let darkFieldUpsampleLimit: Double
    let kdeSigmaPixels: Double
    let lowpassFilter: Bool
    let lanczosOrder: Int?
    let paddedHeight: Int
    let paddedWidth: Int
    let paddedBF: [Float]
    let croppedBF: FloatImage
    let outputSamplingAngstrom: Double
    /// Padded scan-grid shifts in input scan pixels.
    let probeShiftRows: [Float]
    let probeShiftColumns: [Float]
    let positionCorrectionScores: [Float]
}

nonisolated enum ParallaxSubpixelReconstructor {
    enum ReconstructionError: LocalizedError, Equatable {
        case invalidInput(String)
        case invalidOptions(String)
        case memoryLimit(bytes: Int, limit: Int)
        case fftUnavailable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot upsample the parallax reconstruction: \(detail)."
            case .invalidOptions(let detail):
                return "Invalid parallax KDE options: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Parallax KDE needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above the \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) working limit. Reduce the factor or crop/bin the dataset first."
            case .fftUnavailable:
                return "Could not create the exact-shape FFT used by the KDE low-pass filter."
            case .cancelled:
                return "Parallax KDE reconstruction was cancelled."
            }
        }
    }

    static func reconstruct(
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
        let bfSampling = 1 / maximumK / 2
        let dfSampling = 1 / (
            preprocessing.calibration.reciprocalSamplingInvAngstrom
                * Double(preprocessing.detectorHeight)
        )
        let bfLimit = scanSampling / bfSampling
        let rawDFLimit = scanSampling / dfSampling
        let dfLimit = max(rawDFLimit, 1)
        let factor: Double
        if let requested = options.upsampleFactor {
            factor = requested
        } else if bfLimit * 1.5 > dfLimit {
            factor = dfLimit
        } else if bfLimit * 1.5 > 1 {
            factor = bfLimit * 1.5
        } else {
            factor = max(dfLimit * 2 / 3, 1)
        }
        guard factor.isFinite, factor >= 1 else {
            throw ReconstructionError.invalidOptions("upsample factor must be at least 1")
        }

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
        // Accumulators plus separable blur/FFT scratch. This is deliberately
        // conservative and excludes the already-resident preprocessing data.
        let outputArrayCount = options.lowpassFilter ? 6 : 4
        guard outputCount <= Int.max / MemoryLayout<Float>.stride / outputArrayCount else {
            throw ReconstructionError.invalidOptions("working dimensions overflow")
        }
        var workingBytes = outputCount * MemoryLayout<Float>.stride * outputArrayCount
        if options.positionCorrectionIterations != nil {
            // dx, dy, step, scores, four trial score maps, and fixed-step scores.
            guard planeCount <= Int.max / MemoryLayout<Float>.stride / 9 else {
                throw ReconstructionError.invalidOptions("position work dimensions overflow")
            }
            workingBytes += planeCount * MemoryLayout<Float>.stride * 9
        }
        guard workingBytes <= options.maxWorkingBytes else {
            throw ReconstructionError.memoryLimit(
                bytes: workingBytes, limit: options.maxWorkingBytes
            )
        }

        var probeRows = [Float](repeating: 0, count: planeCount)
        var probeColumns = [Float](repeating: 0, count: planeCount)
        var pixelOutput = try kernelDensity(
            preprocessing: preprocessing, alignment: alignment,
            probeRows: probeRows, probeColumns: probeColumns,
            factor: Float(factor), outputWidth: outputWidth,
            outputHeight: outputHeight, sigma: Float(options.kdeSigmaPixels * factor),
            lanczosOrder: options.lanczosOrder, lowpass: options.lowpassFilter,
            cancellation: cancellation
        )
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
                pixelOutput = try kernelDensity(
                    preprocessing: preprocessing, alignment: alignment,
                    probeRows: probeRows, probeColumns: probeColumns,
                    factor: Float(factor), outputWidth: outputWidth,
                    outputHeight: outputHeight,
                    sigma: Float(options.kdeSigmaPixels * factor),
                    lanczosOrder: options.lanczosOrder,
                    lowpass: options.lowpassFilter, cancellation: cancellation
                )
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

    private static func kernelDensity(
        preprocessing: ParallaxPreprocessResult,
        alignment: ParallaxAlignmentResult,
        probeRows: [Float], probeColumns: [Float], factor: Float,
        outputWidth: Int, outputHeight: Int, sigma: Float,
        lanczosOrder: Int?, lowpass: Bool,
        cancellation: AnalysisCancellationToken?
    ) throws -> [Float] {
        let planeCount = preprocessing.stackHeight * preprocessing.stackWidth
        let outputCount = outputHeight * outputWidth
        var pixelCount = [Float](repeating: 0, count: outputCount)
        var pixelOutput = [Float](repeating: 0, count: outputCount)
        for bf in 0..<preprocessing.brightFieldPixelCount {
            try checkCancellation(cancellation)
            let shift = alignment.totalShifts[bf]
            let plane = bf * planeCount
            for row in 0..<preprocessing.stackHeight {
                if row & 15 == 0 { try checkCancellation(cancellation) }
                for column in 0..<preprocessing.stackWidth {
                    let position = row * preprocessing.stackWidth + column
                    let shiftedRow = (Float(row) + probeRows[position] + shift.row) * factor
                    let shiftedColumn = (
                        Float(column) + probeColumns[position] + shift.column
                    ) * factor
                    let rowFloor = Int(floor(shiftedRow))
                    let columnFloor = Int(floor(shiftedColumn))
                    let rowFraction = shiftedRow - Float(rowFloor)
                    let columnFraction = shiftedColumn - Float(columnFloor)
                    let intensity = preprocessing.unshiftedStack[plane + position]
                    if let order = lanczosOrder {
                        for i in (-order + 1)...order {
                            let rowWeight = sinc(Float(i) - rowFraction)
                                * sinc((Float(i) - rowFraction) / Float(order))
                            let targetRow = wrapped(rowFloor + i, count: outputHeight)
                            for j in (-order + 1)...order {
                                // Preserve the checked-in py4DSTEM helper's
                                // second-axis window expression (`i - dy`).
                                let columnWeight = sinc(Float(j) - columnFraction)
                                    * sinc((Float(i) - columnFraction) / Float(order))
                                let weight = rowWeight * columnWeight
                                let targetColumn = wrapped(
                                    columnFloor + j, count: outputWidth
                                )
                                let target = targetRow * outputWidth + targetColumn
                                pixelCount[target] += weight
                                pixelOutput[target] += weight * intensity
                            }
                        }
                    } else {
                        let row0 = wrapped(rowFloor, count: outputHeight)
                        let row1 = wrapped(rowFloor + 1, count: outputHeight)
                        let column0 = wrapped(columnFloor, count: outputWidth)
                        let column1 = wrapped(columnFloor + 1, count: outputWidth)
                        let weights = [
                            (1 - rowFraction) * (1 - columnFraction),
                            rowFraction * (1 - columnFraction),
                            (1 - rowFraction) * columnFraction,
                            rowFraction * columnFraction,
                        ]
                        let indices = [
                            row0 * outputWidth + column0,
                            row1 * outputWidth + column0,
                            row0 * outputWidth + column1,
                            row1 * outputWidth + column1,
                        ]
                        for basis in 0..<4 {
                            pixelCount[indices[basis]] += weights[basis]
                            pixelOutput[indices[basis]] += weights[basis] * intensity
                        }
                    }
                }
            }
        }
        pixelCount = try gaussianFilter(
            pixelCount, width: outputWidth, height: outputHeight,
            sigma: sigma, cancellation: cancellation
        )
        pixelOutput = try gaussianFilter(
            pixelOutput, width: outputWidth, height: outputHeight,
            sigma: sigma, cancellation: cancellation
        )
        for index in 0..<outputCount {
            pixelOutput[index] = pixelCount[index] > 1e-3
                ? pixelOutput[index] / pixelCount[index] : 1
        }
        if lowpass {
            guard let fft = FFT2D(nx: outputWidth, ny: outputHeight) else {
                throw ReconstructionError.fftUnavailable
            }
            var imaginary = [Float](repeating: 0, count: outputCount)
            fft.transform(re: &pixelOutput, im: &imaginary, forward: true)
            for row in 0..<outputHeight {
                try checkCancellation(cancellation)
                let rowSinc = sinc(FFT2D.fftfreq(row, outputHeight))
                for column in 0..<outputWidth {
                    let denominator = rowSinc * sinc(FFT2D.fftfreq(column, outputWidth))
                    let index = row * outputWidth + column
                    pixelOutput[index] /= denominator
                    imaginary[index] /= denominator
                }
            }
            fft.transform(re: &pixelOutput, im: &imaginary, forward: false)
        }
        return pixelOutput
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

    private static func gaussianFilter(
        _ source: [Float], width: Int, height: Int, sigma: Float,
        cancellation: AnalysisCancellationToken?
    ) throws -> [Float] {
        guard sigma > 0 else { return source }
        let radius = Int(4 * sigma + 0.5)
        guard radius > 0 else { return source }
        var taps = [Float](repeating: 0, count: radius * 2 + 1)
        var sum: Float = 0
        for offset in -radius...radius {
            let value = exp(-Float(offset * offset) / (2 * sigma * sigma))
            taps[offset + radius] = value
            sum += value
        }
        for index in taps.indices { taps[index] /= sum }
        var temporary = [Float](repeating: 0, count: source.count)
        var output = [Float](repeating: 0, count: source.count)
        for row in 0..<height {
            if row & 15 == 0 { try checkCancellation(cancellation) }
            for column in 0..<width {
                var value: Float = 0
                for offset in -radius...radius {
                    let sample = reflected(column + offset, count: width)
                    value += source[row * width + sample] * taps[offset + radius]
                }
                temporary[row * width + column] = value
            }
        }
        for row in 0..<height {
            if row & 15 == 0 { try checkCancellation(cancellation) }
            for column in 0..<width {
                var value: Float = 0
                for offset in -radius...radius {
                    let sample = reflected(row + offset, count: height)
                    value += temporary[sample * width + column] * taps[offset + radius]
                }
                output[row * width + column] = value
            }
        }
        return output
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

    private static func reflected(_ value: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var index = value
        while index < 0 || index >= count {
            index = index < 0 ? -index - 1 : 2 * count - index - 1
        }
        return index
    }

    private static func sinc(_ value: Float) -> Float {
        if value == 0 { return 1 }
        let argument = Float.pi * value
        return sin(argument) / argument
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true {
            throw ReconstructionError.cancelled
        }
    }
}
