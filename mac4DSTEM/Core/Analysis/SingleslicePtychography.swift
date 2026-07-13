//
//  SingleslicePtychography.swift
//  First CPU reference engine: py4DSTEM single-slice complex-object
//  gradient-descent forward/Fourier/adjoint operators, full-batch semantics.
//

import Foundation

nonisolated struct PtychographyPosition: Equatable, Sendable {
    let row: Float
    let column: Float
}

nonisolated struct PtychographyComplexArray: Sendable {
    let width: Int
    let height: Int
    let real: [Float]
    let imaginary: [Float]
}

nonisolated struct SingleslicePtychographyInput: Sendable {
    let scanHeight: Int
    let scanWidth: Int
    let detectorHeight: Int
    let detectorWidth: Int
    /// Corner-centered measured amplitudes `[position,row,column]`.
    let amplitudes: [Float]
    let positions: [PtychographyPosition]
    let objectSamplingRowAngstrom: Double
    let objectSamplingColumnAngstrom: Double
    let initialObject: PtychographyComplexArray
    let initialProbe: PtychographyComplexArray
}

nonisolated struct SingleslicePtychographyOptions: Equatable, Sendable {
    var iterations = 8
    var stepSize: Float = 0.5
    var normalizationMinimum: Float = 1
    var fixProbe = false
    var constrainObjectAmplitude = false
    var purePhaseObject = false
    var fixProbeCenterOfMass = false
    var constrainProbeAmplitude = false
    var probeAmplitudeRelativeRadius: Float = 0.5
    var probeAmplitudeRelativeWidth: Float = 0.05
    var maxWorkingBytes = 1_073_741_824
}

nonisolated struct SingleslicePtychographyResult: Sendable {
    let object: PtychographyComplexArray
    let probe: PtychographyComplexArray
    let positions: [PtychographyPosition]
    let errorHistory: [Float]
    let objectSamplingRowAngstrom: Double
    let objectSamplingColumnAngstrom: Double
    let options: SingleslicePtychographyOptions

    func objectPhase(cropped: Bool = true) -> FloatImage {
        objectImage(cropped: cropped) { atan2($1, $0) }
    }

    func objectAmplitude(cropped: Bool = true) -> FloatImage {
        objectImage(cropped: cropped) { hypot($0, $1) }
    }

    func probePhase(centered: Bool = true) -> FloatImage {
        probeImage(centered: centered) { atan2($1, $0) }
    }

    func probeAmplitude(centered: Bool = true) -> FloatImage {
        probeImage(centered: centered) { hypot($0, $1) }
    }

    private func probeImage(
        centered: Bool, transform: (Float, Float) -> Float
    ) -> FloatImage {
        var pixels = [Float](repeating: 0, count: probe.width * probe.height)
        for row in 0..<probe.height {
            let sourceRow = centered ? (row + (probe.height + 1) / 2) % probe.height : row
            for column in 0..<probe.width {
                let sourceColumn = centered
                    ? (column + (probe.width + 1) / 2) % probe.width : column
                let source = sourceRow * probe.width + sourceColumn
                pixels[row * probe.width + column] = transform(
                    probe.real[source], probe.imaginary[source]
                )
            }
        }
        return FloatImage(width: probe.width, height: probe.height, pixels: pixels)
    }

    private func objectImage(
        cropped: Bool, transform: (Float, Float) -> Float
    ) -> FloatImage {
        let bounds = cropped ? cropBounds() : (0, object.height, 0, object.width)
        let height = max(1, bounds.1 - bounds.0)
        let width = max(1, bounds.3 - bounds.2)
        var pixels = [Float](repeating: 0, count: height * width)
        for row in 0..<height {
            for column in 0..<width {
                let source = (bounds.0 + row) * object.width + bounds.2 + column
                pixels[row * width + column] = transform(
                    object.real[source], object.imaginary[source]
                )
            }
        }
        return FloatImage(width: width, height: height, pixels: pixels)
    }

    private func cropBounds() -> (Int, Int, Int, Int) {
        guard let first = positions.first else { return (0, object.height, 0, object.width) }
        var minRow = first.row, maxRow = first.row
        var minColumn = first.column, maxColumn = first.column
        for position in positions.dropFirst() {
            minRow = min(minRow, position.row); maxRow = max(maxRow, position.row)
            minColumn = min(minColumn, position.column)
            maxColumn = max(maxColumn, position.column)
        }
        let row0 = max(0, min(object.height - 1, Int(floor(minRow))))
        let column0 = max(0, min(object.width - 1, Int(floor(minColumn))))
        let row1 = max(row0 + 1, min(object.height, Int(ceil(maxRow))))
        let column1 = max(column0 + 1, min(object.width, Int(ceil(maxColumn))))
        return (row0, row1, column0, column1)
    }
}

nonisolated enum SingleslicePtychography {
    enum ReconstructionError: LocalizedError, Equatable {
        case invalidInput(String)
        case invalidOptions(String)
        case memoryLimit(bytes: Int, limit: Int)
        case fftUnavailable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidInput(let detail):
                return "Cannot run single-slice ptychography: \(detail)."
            case .invalidOptions(let detail):
                return "Invalid ptychography options: \(detail)."
            case .memoryLimit(let bytes, let limit):
                return "Single-slice ptychography needs about \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)), above its \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) limit. Crop/bin the dataset first."
            case .fftUnavailable:
                return "Could not create the exact-shape ptychography FFT."
            case .cancelled:
                return "Single-slice ptychography was cancelled."
            }
        }
    }

    static func reconstruct(
        input: SingleslicePtychographyInput,
        options: SingleslicePtychographyOptions = .init(),
        cancellation: AnalysisCancellationToken? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> SingleslicePtychographyResult {
        let patternCount = input.scanHeight * input.scanWidth
        let probeCount = input.detectorHeight * input.detectorWidth
        let objectCount = input.initialObject.height * input.initialObject.width
        guard patternCount > 0, probeCount > 0, objectCount > 0,
              input.amplitudes.count == patternCount * probeCount,
              input.positions.count == patternCount,
              input.initialProbe.height == input.detectorHeight,
              input.initialProbe.width == input.detectorWidth,
              input.initialProbe.real.count == probeCount,
              input.initialProbe.imaginary.count == probeCount,
              input.initialObject.real.count == objectCount,
              input.initialObject.imaginary.count == objectCount,
              input.amplitudes.allSatisfy({ $0.isFinite && $0 >= 0 }),
              input.positions.allSatisfy({ $0.row.isFinite && $0.column.isFinite }),
              input.objectSamplingRowAngstrom.isFinite,
              input.objectSamplingRowAngstrom > 0,
              input.objectSamplingColumnAngstrom.isFinite,
              input.objectSamplingColumnAngstrom > 0 else {
            throw ReconstructionError.invalidInput("array shapes, values, or sampling are inconsistent")
        }
        guard options.iterations > 0, options.stepSize.isFinite,
              options.stepSize > 0, options.normalizationMinimum.isFinite,
              options.normalizationMinimum >= 0,
              options.normalizationMinimum <= 1,
              options.probeAmplitudeRelativeRadius.isFinite,
              options.probeAmplitudeRelativeRadius >= 0,
              options.probeAmplitudeRelativeRadius <= 0.5,
              options.probeAmplitudeRelativeWidth.isFinite,
              options.probeAmplitudeRelativeWidth > 0,
              options.probeAmplitudeRelativeWidth <= 0.5,
              options.maxWorkingBytes > 0 else {
            throw ReconstructionError.invalidOptions(
                "iterations/step, normalization, or constraint parameters are invalid"
            )
        }
        let floatBytes = MemoryLayout<Float>.stride
        let workingBytes = (
            input.amplitudes.count + objectCount * 7 + probeCount * 12
        ) * floatBytes
        guard workingBytes <= options.maxWorkingBytes else {
            throw ReconstructionError.memoryLimit(
                bytes: workingBytes, limit: options.maxWorkingBytes
            )
        }
        guard let fft = FFT2D(nx: input.detectorWidth, ny: input.detectorHeight) else {
            throw ReconstructionError.fftUnavailable
        }
        try checkCancellation(cancellation)

        let measuredIntensity = input.amplitudes.reduce(0.0) {
            $0 + Double($1 * $1)
        }
        guard measuredIntensity.isFinite, measuredIntensity > 0 else {
            throw ReconstructionError.invalidInput("measured diffraction intensity is zero")
        }
        var objectReal = input.initialObject.real
        var objectImaginary = input.initialObject.imaginary
        var probeReal = input.initialProbe.real
        var probeImaginary = input.initialProbe.imaginary
        var errors = [Float]()
        errors.reserveCapacity(options.iterations)
        let rowOffsets = frequencyIndices(input.detectorHeight)
        let columnOffsets = frequencyIndices(input.detectorWidth)

        for iteration in 0..<options.iterations {
            try checkCancellation(cancellation)
            var objectNumeratorReal = [Float](repeating: 0, count: objectCount)
            var objectNumeratorImaginary = [Float](repeating: 0, count: objectCount)
            var probeNormalization = [Float](repeating: 0, count: objectCount)
            var probeNumeratorReal = [Float](repeating: 0, count: probeCount)
            var probeNumeratorImaginary = [Float](repeating: 0, count: probeCount)
            var objectNormalization = [Float](repeating: 0, count: probeCount)
            var probeSpectrumReal = probeReal
            var probeSpectrumImaginary = probeImaginary
            fft.transform(
                re: &probeSpectrumReal, im: &probeSpectrumImaginary, forward: true
            )
            var iterationError: Double = 0

            for pattern in 0..<patternCount {
                if pattern & 7 == 0 { try checkCancellation(cancellation) }
                let position = input.positions[pattern]
                let centerRow = Int(Double(position.row).rounded(.toNearestOrEven))
                let centerColumn = Int(Double(position.column).rounded(.toNearestOrEven))
                let fractionalRow = position.row - Float(centerRow)
                let fractionalColumn = position.column - Float(centerColumn)
                var shiftedProbeReal = probeSpectrumReal
                var shiftedProbeImaginary = probeSpectrumImaginary
                for row in 0..<input.detectorHeight {
                    let frequencyRow = FFT2D.fftfreq(row, input.detectorHeight)
                    for column in 0..<input.detectorWidth {
                        let frequencyColumn = FFT2D.fftfreq(column, input.detectorWidth)
                        let phase = -2 * Float.pi * (
                            frequencyRow * fractionalRow
                                + frequencyColumn * fractionalColumn
                        )
                        let cosine = cos(phase), sine = sin(phase)
                        let index = row * input.detectorWidth + column
                        let oldReal = shiftedProbeReal[index]
                        let oldImaginary = shiftedProbeImaginary[index]
                        shiftedProbeReal[index] = oldReal * cosine - oldImaginary * sine
                        shiftedProbeImaginary[index] = oldReal * sine + oldImaginary * cosine
                    }
                }
                fft.transform(
                    re: &shiftedProbeReal, im: &shiftedProbeImaginary,
                    forward: false
                )
                var patchReal = [Float](repeating: 0, count: probeCount)
                var patchImaginary = [Float](repeating: 0, count: probeCount)
                var fourierReal = [Float](repeating: 0, count: probeCount)
                var fourierImaginary = [Float](repeating: 0, count: probeCount)
                var objectIndices = [Int](repeating: 0, count: probeCount)
                for row in 0..<input.detectorHeight {
                    let objectRow = wrapped(
                        centerRow + rowOffsets[row], count: input.initialObject.height
                    )
                    for column in 0..<input.detectorWidth {
                        let objectColumn = wrapped(
                            centerColumn + columnOffsets[column],
                            count: input.initialObject.width
                        )
                        let index = row * input.detectorWidth + column
                        let objectIndex = objectRow * input.initialObject.width + objectColumn
                        objectIndices[index] = objectIndex
                        let objReal = objectReal[objectIndex]
                        let objImaginary = objectImaginary[objectIndex]
                        patchReal[index] = objReal
                        patchImaginary[index] = objImaginary
                        let pReal = shiftedProbeReal[index]
                        let pImaginary = shiftedProbeImaginary[index]
                        fourierReal[index] = pReal * objReal - pImaginary * objImaginary
                        fourierImaginary[index] = pReal * objImaginary + pImaginary * objReal
                    }
                }
                fft.transform(re: &fourierReal, im: &fourierImaginary, forward: true)
                let amplitudeBase = pattern * probeCount
                for index in 0..<probeCount {
                    let magnitude = hypot(fourierReal[index], fourierImaginary[index])
                    let measured = input.amplitudes[amplitudeBase + index]
                    let residual = Double(measured - magnitude)
                    iterationError += residual * residual
                    let projectedReal: Float
                    let projectedImaginary: Float
                    if magnitude > 0 {
                        projectedReal = measured * fourierReal[index] / magnitude
                        projectedImaginary = measured * fourierImaginary[index] / magnitude
                    } else {
                        projectedReal = measured
                        projectedImaginary = 0
                    }
                    fourierReal[index] = projectedReal - fourierReal[index]
                    fourierImaginary[index] = projectedImaginary - fourierImaginary[index]
                }
                fft.transform(re: &fourierReal, im: &fourierImaginary, forward: false)
                for index in 0..<probeCount {
                    let objectIndex = objectIndices[index]
                    let pReal = shiftedProbeReal[index]
                    let pImaginary = shiftedProbeImaginary[index]
                    let exitReal = fourierReal[index]
                    let exitImaginary = fourierImaginary[index]
                    objectNumeratorReal[objectIndex] += pReal * exitReal
                        + pImaginary * exitImaginary
                    objectNumeratorImaginary[objectIndex] += pReal * exitImaginary
                        - pImaginary * exitReal
                    probeNormalization[objectIndex] += pReal * pReal
                        + pImaginary * pImaginary
                    let objReal = patchReal[index], objImaginary = patchImaginary[index]
                    probeNumeratorReal[index] += objReal * exitReal
                        + objImaginary * exitImaginary
                    probeNumeratorImaginary[index] += objReal * exitImaginary
                        - objImaginary * exitReal
                    objectNormalization[index] += objReal * objReal
                        + objImaginary * objImaginary
                }
            }

            let maximumProbeNormalization = probeNormalization.max() ?? 0
            let maximumObjectNormalization = objectNormalization.max() ?? 0
            for index in 0..<objectCount {
                let inverse = normalizationInverse(
                    local: probeNormalization[index], maximum: maximumProbeNormalization,
                    minimum: options.normalizationMinimum
                )
                objectReal[index] += options.stepSize
                    * objectNumeratorReal[index] * inverse
                objectImaginary[index] += options.stepSize
                    * objectNumeratorImaginary[index] * inverse
            }
            if !options.fixProbe {
                for index in 0..<probeCount {
                    let inverse = normalizationInverse(
                        local: objectNormalization[index],
                        maximum: maximumObjectNormalization,
                        minimum: options.normalizationMinimum
                    )
                    probeReal[index] += options.stepSize
                        * probeNumeratorReal[index] * inverse
                    probeImaginary[index] += options.stepSize
                        * probeNumeratorImaginary[index] * inverse
                }
            }
            if options.constrainObjectAmplitude || options.purePhaseObject {
                constrainObject(
                    real: &objectReal, imaginary: &objectImaginary,
                    purePhase: options.purePhaseObject
                )
            }
            if !options.fixProbe {
                if options.fixProbeCenterOfMass {
                    try centerProbe(
                        real: &probeReal, imaginary: &probeImaginary,
                        width: input.detectorWidth, height: input.detectorHeight,
                        fft: fft
                    )
                }
                if options.constrainProbeAmplitude {
                    constrainProbeAmplitude(
                        real: &probeReal, imaginary: &probeImaginary,
                        width: input.detectorWidth, height: input.detectorHeight,
                        relativeRadius: options.probeAmplitudeRelativeRadius,
                        relativeWidth: options.probeAmplitudeRelativeWidth
                    )
                }
            }
            errors.append(Float(iterationError / measuredIntensity))
            progress?(Double(iteration + 1) / Double(options.iterations))
        }
        try checkCancellation(cancellation)
        return SingleslicePtychographyResult(
            object: PtychographyComplexArray(
                width: input.initialObject.width, height: input.initialObject.height,
                real: objectReal, imaginary: objectImaginary
            ),
            probe: PtychographyComplexArray(
                width: input.detectorWidth, height: input.detectorHeight,
                real: probeReal, imaginary: probeImaginary
            ),
            positions: input.positions, errorHistory: errors,
            objectSamplingRowAngstrom: input.objectSamplingRowAngstrom,
            objectSamplingColumnAngstrom: input.objectSamplingColumnAngstrom,
            options: options
        )
    }

    private static func constrainObject(
        real: inout [Float], imaginary: inout [Float], purePhase: Bool
    ) {
        for index in real.indices {
            let amplitude = hypot(real[index], imaginary[index])
            guard amplitude > 0 else {
                real[index] = purePhase ? 1 : 0
                imaginary[index] = 0
                continue
            }
            let constrained = purePhase ? Float(1) : min(amplitude, 1)
            let scale = constrained / amplitude
            real[index] *= scale
            imaginary[index] *= scale
        }
    }

    private static func centerProbe(
        real: inout [Float], imaginary: inout [Float], width: Int, height: Int,
        fft: FFT2D
    ) throws {
        var intensity: Double = 0
        var weightedRow: Double = 0, weightedColumn: Double = 0
        for row in 0..<height {
            let rowCoordinate = Double(FFT2D.fftfreq(row, height) * Float(height))
            for column in 0..<width {
                let index = row * width + column
                let value = Double(real[index] * real[index]
                    + imaginary[index] * imaginary[index])
                intensity += value
                weightedRow += rowCoordinate * value
                weightedColumn += Double(
                    FFT2D.fftfreq(column, width) * Float(width)
                ) * value
            }
        }
        guard intensity > 0, intensity.isFinite else { return }
        let shiftRow = Float(-weightedRow / intensity)
        let shiftColumn = Float(-weightedColumn / intensity)
        fft.transform(re: &real, im: &imaginary, forward: true)
        for row in 0..<height {
            let frequencyRow = FFT2D.fftfreq(row, height)
            for column in 0..<width {
                let frequencyColumn = FFT2D.fftfreq(column, width)
                let phase = -2 * Float.pi * (
                    frequencyRow * shiftRow + frequencyColumn * shiftColumn
                )
                let cosine = cos(phase), sine = sin(phase)
                let index = row * width + column
                let oldReal = real[index], oldImaginary = imaginary[index]
                real[index] = oldReal * cosine - oldImaginary * sine
                imaginary[index] = oldReal * sine + oldImaginary * cosine
            }
        }
        fft.transform(re: &real, im: &imaginary, forward: false)
    }

    private static func constrainProbeAmplitude(
        real: inout [Float], imaginary: inout [Float], width: Int, height: Int,
        relativeRadius: Float, relativeWidth: Float
    ) {
        let originalIntensity = zip(real, imaginary).reduce(0.0) {
            $0 + Double($1.0 * $1.0 + $1.1 * $1.1)
        }
        let sigma = sqrt(Double.pi) / Double(relativeWidth)
        var updatedIntensity: Double = 0
        for row in 0..<height {
            let y = Double(FFT2D.fftfreq(row, height))
            for column in 0..<width {
                let x = Double(FFT2D.fftfreq(column, width))
                let radius = hypot(y, x) - Double(relativeRadius)
                let denominator = 1 - radius * radius
                let mask = 0.5 * (1 - erf(sigma * radius / denominator))
                let index = row * width + column
                real[index] *= Float(mask)
                imaginary[index] *= Float(mask)
                updatedIntensity += Double(
                    real[index] * real[index] + imaginary[index] * imaginary[index]
                )
            }
        }
        guard originalIntensity > 0, updatedIntensity > 0 else { return }
        let scale = Float(sqrt(originalIntensity / updatedIntensity))
        for index in real.indices {
            real[index] *= scale
            imaginary[index] *= scale
        }
    }

    private static func normalizationInverse(
        local: Float, maximum: Float, minimum: Float
    ) -> Float {
        1 / sqrt(
            1e-16 + pow((1 - minimum) * local, 2)
                + pow(minimum * maximum, 2)
        )
    }

    private static func frequencyIndices(_ count: Int) -> [Int] {
        (0..<count).map { $0 <= (count - 1) / 2 ? $0 : $0 - count }
    }

    private static func wrapped(_ value: Int, count: Int) -> Int {
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private static func checkCancellation(
        _ cancellation: AnalysisCancellationToken?
    ) throws {
        if cancellation?.isCancelled == true { throw ReconstructionError.cancelled }
    }
}
