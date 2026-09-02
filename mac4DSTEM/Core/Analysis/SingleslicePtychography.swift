//
//  SingleslicePtychography.swift
//  First CPU reference engine: py4DSTEM single-slice complex-object
//  gradient-descent forward/Fourier/adjoint operators, full-batch semantics.
//

import Foundation

package nonisolated struct PtychographyPosition: Equatable, Sendable {
    package let row: Float
    package let column: Float

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(row: Float, column: Float) {
        self.row = row
        self.column = column
    }
}

package nonisolated struct PtychographyComplexArray: Sendable {
    package let width: Int
    package let height: Int
    package let real: [Float]
    package let imaginary: [Float]

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(width: Int, height: Int, real: [Float], imaginary: [Float]) {
        self.width = width
        self.height = height
        self.real = real
        self.imaginary = imaginary
    }
}

package nonisolated struct SingleslicePtychographyInput: Sendable {
    package let scanHeight: Int
    package let scanWidth: Int
    package let detectorHeight: Int
    package let detectorWidth: Int
    /// Corner-centered measured amplitudes `[position,row,column]`.
    package let amplitudes: [Float]
    package let positions: [PtychographyPosition]
    package let objectSamplingRowAngstrom: Double
    package let objectSamplingColumnAngstrom: Double
    package let initialObject: PtychographyComplexArray
    package let initialProbe: PtychographyComplexArray

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(scanHeight: Int, scanWidth: Int, detectorHeight: Int, detectorWidth: Int, amplitudes: [Float], positions: [PtychographyPosition], objectSamplingRowAngstrom: Double, objectSamplingColumnAngstrom: Double, initialObject: PtychographyComplexArray, initialProbe: PtychographyComplexArray) {
        self.scanHeight = scanHeight
        self.scanWidth = scanWidth
        self.detectorHeight = detectorHeight
        self.detectorWidth = detectorWidth
        self.amplitudes = amplitudes
        self.positions = positions
        self.objectSamplingRowAngstrom = objectSamplingRowAngstrom
        self.objectSamplingColumnAngstrom = objectSamplingColumnAngstrom
        self.initialObject = initialObject
        self.initialProbe = initialProbe
    }
}

package nonisolated enum SingleslicePtychographyMethod: String, CaseIterable, Identifiable, Sendable {
    case gradientDescent = "Gradient descent"
    case differenceMapAlternatingProjections = "DM / AP"

    package var id: String { rawValue }
    package var provenanceName: String {
        switch self {
        case .gradientDescent: "gradient-descent"
        case .differenceMapAlternatingProjections:
            "difference-map_alternating-projections"
        }
    }
}

package nonisolated struct SingleslicePtychographyOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init() {}

    package var method: SingleslicePtychographyMethod = .gradientDescent
    package var iterations = 8
    package var stepSize: Float = 0.5
    package var projectionParameter: Float = 1
    package var normalizationMinimum: Float = 1
    package var fixProbe = false
    package var constrainObjectAmplitude = false
    package var purePhaseObject = false
    package var fixProbeCenterOfMass = false
    package var constrainProbeAmplitude = false
    package var probeAmplitudeRelativeRadius: Float = 0.5
    package var probeAmplitudeRelativeWidth: Float = 0.05
    package var maxWorkingBytes = 1_073_741_824
}

package nonisolated struct SingleslicePtychographyResult: Sendable {
    package let object: PtychographyComplexArray
    package let probe: PtychographyComplexArray
    package let positions: [PtychographyPosition]
    package let errorHistory: [Float]
    package let objectSamplingRowAngstrom: Double
    package let objectSamplingColumnAngstrom: Double
    package let options: SingleslicePtychographyOptions

    package func objectPhase(cropped: Bool = true) -> FloatImage {
        objectImage(cropped: cropped) { atan2($1, $0) }
    }

    package func objectAmplitude(cropped: Bool = true) -> FloatImage {
        objectImage(cropped: cropped) { hypot($0, $1) }
    }

    package func probePhase(centered: Bool = true) -> FloatImage {
        probeImage(centered: centered) { atan2($1, $0) }
    }

    package func probeAmplitude(centered: Bool = true) -> FloatImage {
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

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(object: PtychographyComplexArray, probe: PtychographyComplexArray, positions: [PtychographyPosition], errorHistory: [Float], objectSamplingRowAngstrom: Double, objectSamplingColumnAngstrom: Double, options: SingleslicePtychographyOptions) {
        self.object = object
        self.probe = probe
        self.positions = positions
        self.errorHistory = errorHistory
        self.objectSamplingRowAngstrom = objectSamplingRowAngstrom
        self.objectSamplingColumnAngstrom = objectSamplingColumnAngstrom
        self.options = options
    }
}

package nonisolated enum SingleslicePtychography {
    package enum ReconstructionError: LocalizedError, Equatable {
        case invalidInput(String)
        case invalidOptions(String)
        case memoryLimit(bytes: Int, limit: Int)
        case fftUnavailable
        case cancelled

        package var errorDescription: String? {
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

    /// Fixed geometry portion of the forward operator. A fractional probe
    /// shift is separable in row/column frequency, so cache compact complex
    /// ramps once instead of evaluating sin/cos for every pixel and iteration.
    private struct FractionalShiftPlan {
        package let rowReal: [Float]
        package let rowImaginary: [Float]
        package let columnReal: [Float]
        package let columnImaginary: [Float]
        package let height: Int
        package let width: Int

        package init(input: SingleslicePtychographyInput) {
            height = input.detectorHeight
            width = input.detectorWidth
            let patternCount = input.scanHeight * input.scanWidth
            var rowReal = [Float](repeating: 0, count: patternCount * height)
            var rowImaginary = [Float](repeating: 0, count: patternCount * height)
            var columnReal = [Float](repeating: 0, count: patternCount * width)
            var columnImaginary = [Float](repeating: 0, count: patternCount * width)
            for pattern in 0..<patternCount {
                let position = input.positions[pattern]
                let centerRow = Int(Double(position.row).rounded(.toNearestOrEven))
                let centerColumn = Int(Double(position.column).rounded(.toNearestOrEven))
                let fractionalRow = position.row - Float(centerRow)
                let fractionalColumn = position.column - Float(centerColumn)
                for row in 0..<height {
                    let phase = -2 * Float.pi
                        * FFT2D.fftfreq(row, height) * fractionalRow
                    rowReal[pattern * height + row] = cos(phase)
                    rowImaginary[pattern * height + row] = sin(phase)
                }
                for column in 0..<width {
                    let phase = -2 * Float.pi
                        * FFT2D.fftfreq(column, width) * fractionalColumn
                    columnReal[pattern * width + column] = cos(phase)
                    columnImaginary[pattern * width + column] = sin(phase)
                }
            }
            self.rowReal = rowReal
            self.rowImaginary = rowImaginary
            self.columnReal = columnReal
            self.columnImaginary = columnImaginary
        }

        package func factor(pattern: Int, row: Int, column: Int) -> (real: Float, imaginary: Float) {
            let rowIndex = pattern * height + row
            let columnIndex = pattern * width + column
            let rr = rowReal[rowIndex], ri = rowImaginary[rowIndex]
            let cr = columnReal[columnIndex], ci = columnImaginary[columnIndex]
            return (rr * cr - ri * ci, ri * cr + rr * ci)
        }
    }

    package static func reconstruct(
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
              options.projectionParameter.isFinite,
              options.projectionParameter >= 0,
              options.projectionParameter <= 1,
              options.maxWorkingBytes > 0 else {
            throw ReconstructionError.invalidOptions(
                "iterations/step, normalization, or constraint parameters are invalid"
            )
        }
        let floatBytes = MemoryLayout<Float>.stride
        var workingBytes = (
            input.amplitudes.count + objectCount * 7 + probeCount * 12
        ) * floatBytes
        let shiftValuesPerPattern = (input.detectorHeight + input.detectorWidth) * 2
        guard patternCount <= Int.max / max(1, shiftValuesPerPattern),
              patternCount * shiftValuesPerPattern <= (Int.max - workingBytes) / floatBytes
        else { throw ReconstructionError.invalidOptions("shift-plan dimensions overflow") }
        workingBytes += patternCount * shiftValuesPerPattern * floatBytes
        if options.method == .differenceMapAlternatingProjections {
            guard input.amplitudes.count <= Int.max / floatBytes / 2 else {
                throw ReconstructionError.invalidOptions("exit-wave dimensions overflow")
            }
            let exitWaveBytes = input.amplitudes.count * floatBytes * 2
            guard workingBytes <= Int.max - exitWaveBytes else {
                throw ReconstructionError.invalidOptions("working byte size overflow")
            }
            workingBytes += exitWaveBytes
        }
        guard workingBytes <= options.maxWorkingBytes else {
            throw ReconstructionError.memoryLimit(
                bytes: workingBytes, limit: options.maxWorkingBytes
            )
        }
        guard let fft = FFT2D(nx: input.detectorWidth, ny: input.detectorHeight) else {
            throw ReconstructionError.fftUnavailable
        }
        try checkCancellation(cancellation)
        let shiftPlan = FractionalShiftPlan(input: input)

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
        var retainedExitReal = options.method == .differenceMapAlternatingProjections
            ? [Float](repeating: 0, count: input.amplitudes.count) : []
        var retainedExitImaginary = options.method == .differenceMapAlternatingProjections
            ? [Float](repeating: 0, count: input.amplitudes.count) : []
        // Pattern-local arrays have fixed shapes. Reuse them across every scan
        // position and iteration instead of allocating/zeroing 7–9 arrays per
        // diffraction pattern. Every element is overwritten before it is read.
        var shiftedProbeReal = [Float](repeating: 0, count: probeCount)
        var shiftedProbeImaginary = [Float](repeating: 0, count: probeCount)
        var patchReal = [Float](repeating: 0, count: probeCount)
        var patchImaginary = [Float](repeating: 0, count: probeCount)
        var fourierReal = [Float](repeating: 0, count: probeCount)
        var fourierImaginary = [Float](repeating: 0, count: probeCount)
        var objectIndices = [Int](repeating: 0, count: probeCount)
        var previousReal = options.method == .differenceMapAlternatingProjections
            ? [Float](repeating: 0, count: probeCount) : []
        var previousImaginary = options.method == .differenceMapAlternatingProjections
            ? [Float](repeating: 0, count: probeCount) : []

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
                for row in 0..<input.detectorHeight {
                    for column in 0..<input.detectorWidth {
                        let factor = shiftPlan.factor(
                            pattern: pattern, row: row, column: column
                        )
                        let index = row * input.detectorWidth + column
                        let oldReal = probeSpectrumReal[index]
                        let oldImaginary = probeSpectrumImaginary[index]
                        shiftedProbeReal[index] = oldReal * factor.real
                            - oldImaginary * factor.imaginary
                        shiftedProbeImaginary[index] = oldReal * factor.imaginary
                            + oldImaginary * factor.real
                    }
                }
                fft.transform(
                    re: &shiftedProbeReal, im: &shiftedProbeImaginary,
                    forward: false
                )
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
                let amplitudeBase = pattern * probeCount
                switch options.method {
                case .gradientDescent:
                    fft.transform(
                        re: &fourierReal, im: &fourierImaginary, forward: true
                    )
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
                        fourierImaginary[index] = projectedImaginary
                            - fourierImaginary[index]
                    }
                    fft.transform(
                        re: &fourierReal, im: &fourierImaginary, forward: false
                    )
                case .differenceMapAlternatingProjections:
                    let alpha = options.projectionParameter
                    let projectionA = -alpha
                    let projectionB: Float = 1
                    let projectionC = 1 + alpha
                    let projectionX = 1 - projectionA - projectionB
                    let projectionY = 1 - projectionC
                    for index in 0..<probeCount {
                        let retained = amplitudeBase + index
                        previousReal[index] = iteration == 0
                            ? fourierReal[index] : retainedExitReal[retained]
                        previousImaginary[index] = iteration == 0
                            ? fourierImaginary[index] : retainedExitImaginary[retained]
                        fourierReal[index] = projectionC * fourierReal[index]
                            + projectionY * previousReal[index]
                        fourierImaginary[index] = projectionC * fourierImaginary[index]
                            + projectionY * previousImaginary[index]
                    }
                    fft.transform(
                        re: &fourierReal, im: &fourierImaginary, forward: true
                    )
                    for index in 0..<probeCount {
                        let magnitude = hypot(fourierReal[index], fourierImaginary[index])
                        let measured = input.amplitudes[amplitudeBase + index]
                        let residual = Double(measured - magnitude)
                        iterationError += residual * residual
                        if magnitude > 0 {
                            fourierReal[index] = measured * fourierReal[index] / magnitude
                            fourierImaginary[index] = measured
                                * fourierImaginary[index] / magnitude
                        } else {
                            fourierReal[index] = measured
                            fourierImaginary[index] = 0
                        }
                    }
                    fft.transform(
                        re: &fourierReal, im: &fourierImaginary, forward: false
                    )
                    for index in 0..<probeCount {
                        let overlapReal = shiftedProbeReal[index] * patchReal[index]
                            - shiftedProbeImaginary[index] * patchImaginary[index]
                        let overlapImaginary = shiftedProbeReal[index] * patchImaginary[index]
                            + shiftedProbeImaginary[index] * patchReal[index]
                        fourierReal[index] = projectionX * previousReal[index]
                            + projectionA * overlapReal + projectionB * fourierReal[index]
                        fourierImaginary[index] = projectionX * previousImaginary[index]
                            + projectionA * overlapImaginary
                            + projectionB * fourierImaginary[index]
                        let retained = amplitudeBase + index
                        retainedExitReal[retained] = fourierReal[index]
                        retainedExitImaginary[retained] = fourierImaginary[index]
                    }
                }
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
            switch options.method {
            case .gradientDescent:
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
            case .differenceMapAlternatingProjections:
                for index in 0..<objectCount {
                    let inverse = normalizationInverse(
                        local: probeNormalization[index], maximum: maximumProbeNormalization,
                        minimum: options.normalizationMinimum
                    )
                    objectReal[index] = objectNumeratorReal[index] * inverse
                    objectImaginary[index] = objectNumeratorImaginary[index] * inverse
                }
                if !options.fixProbe {
                    for index in 0..<probeCount {
                        let inverse = normalizationInverse(
                            local: objectNormalization[index],
                            maximum: maximumObjectNormalization,
                            minimum: options.normalizationMinimum
                        )
                        probeReal[index] = probeNumeratorReal[index] * inverse
                        probeImaginary[index] = probeNumeratorImaginary[index] * inverse
                    }
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
