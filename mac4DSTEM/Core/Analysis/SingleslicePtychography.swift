//
//  SingleslicePtychography.swift
//  py4DSTEM single-slice complex-object gradient descent, full-batch: the app's facade over CuboPtycho.
//
//  The engine is CuboPtycho's (0.7.0); this file keeps the app's Float input/options/result types and the adapter.
//

import CuboPtycho
import Foundation
import ImagoCore

package nonisolated struct PtychographyScanPosition: Equatable, Sendable {
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
    package let positions: [PtychographyScanPosition]
    package let objectSamplingRowAngstrom: Double
    package let objectSamplingColumnAngstrom: Double
    package let initialObject: PtychographyComplexArray
    package let initialProbe: PtychographyComplexArray
    /// The defocus and aberrations `initialProbe` was built with (lane R1; `PtychographyPreparer.prepare` sets it from the
    /// `aberrations` it received, so a reader of the result cannot be told a probe the run did not start from). `.init()` for an
    /// input assembled by hand.
    package let probeAberrations: PtychographyProbeAberrations

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(scanHeight: Int, scanWidth: Int, detectorHeight: Int, detectorWidth: Int, amplitudes: [Float], positions: [PtychographyScanPosition], objectSamplingRowAngstrom: Double, objectSamplingColumnAngstrom: Double, initialObject: PtychographyComplexArray, initialProbe: PtychographyComplexArray, probeAberrations: PtychographyProbeAberrations = PtychographyProbeAberrations()) {
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
        self.probeAberrations = probeAberrations
    }
}

package nonisolated struct SingleslicePtychographyOptions: Equatable, Sendable {
    // Explicit so the default initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init() {}

    package var iterations = 8
    package var stepSize: Float = 0.5
    package var normalizationMinimum: Float = 1
    package var fixProbe = false
    /// |object| <= 1 after every iteration. On by default: py4DSTEM applies it unconditionally to a complex object
    /// (ptychographic_constraints.py `_object_constraints` -> `_object_threshold_constraint`); with it off the app's gradient-descent
    /// error history leaves py4DSTEM's by up to 8.6 % on graphene, with it on by 1.7 % (lane DC, owner card CL a, 2026-10-01).
    package var constrainObjectAmplitude = true
    package var purePhaseObject = false
    package var fixProbeCenterOfMass = false
    package var constrainProbeAmplitude = false
    package var probeAmplitudeRelativeRadius: Float = 0.5
    package var probeAmplitudeRelativeWidth: Float = 0.05
    package var maxWorkingBytes = PhaseContrastMemoryBudget.workingLimitBytes
}

package nonisolated struct SingleslicePtychographyResult: Sendable {
    package let object: PtychographyComplexArray
    package let probe: PtychographyComplexArray
    package let positions: [PtychographyScanPosition]
    package let errorHistory: [Float]
    package let objectSamplingRowAngstrom: Double
    package let objectSamplingColumnAngstrom: Double
    package let options: SingleslicePtychographyOptions
    /// The defocus and aberrations the reconstruction's starting probe was built with - copied from the input, never from settings.
    package let probeAberrations: PtychographyProbeAberrations

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
    package nonisolated init(object: PtychographyComplexArray, probe: PtychographyComplexArray, positions: [PtychographyScanPosition], errorHistory: [Float], objectSamplingRowAngstrom: Double, objectSamplingColumnAngstrom: Double, options: SingleslicePtychographyOptions, probeAberrations: PtychographyProbeAberrations = PtychographyProbeAberrations()) {
        self.object = object
        self.probe = probe
        self.positions = positions
        self.errorHistory = errorHistory
        self.objectSamplingRowAngstrom = objectSamplingRowAngstrom
        self.objectSamplingColumnAngstrom = objectSamplingColumnAngstrom
        self.options = options
        self.probeAberrations = probeAberrations
    }
}

package nonisolated enum PtychographyReconstructor {
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

    /// The reconstruction is CuboPtycho's `SingleslicePtychography`: Float32 on vDSP's DFT where the detector size allows it
    /// (`reconstructSingle`, no position correction, as before), otherwise the kit's Double path (about twice the memory, so the
    /// working-set check is repeated for it). The app keeps its Float façade (input, options, result, error text) and the
    /// cancellation token and progress fraction the UI is wired to.
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
              options.maxWorkingBytes > 0 else {
            throw ReconstructionError.invalidOptions(
                "iterations/step, normalization, or constraint parameters are invalid"
            )
        }
        // Float32 working set of the kit's single path: the caller's stack plus the kit's transposed copy of it, the object and probe
        // buffers. The Double fallback holds the Float stack, a Double copy of it and the kit's Double copy: five Float-widths a value.
        let floatBytes = MemoryLayout<Float>.stride
        let workingBytes = (input.amplitudes.count * 2 + objectCount * 7 + probeCount * 12) * floatBytes
        let fallbackBytes = (input.amplitudes.count * 5 + objectCount * 14 + probeCount * 24) * floatBytes
        guard workingBytes <= options.maxWorkingBytes else {
            throw ReconstructionError.memoryLimit(bytes: workingBytes, limit: options.maxWorkingBytes)
        }
        let measuredIntensity = input.amplitudes.reduce(0.0) { $0 + Double($1 * $1) }
        guard measuredIntensity.isFinite, measuredIntensity > 0 else {
            throw ReconstructionError.invalidInput("measured diffraction intensity is zero")
        }
        if cancellation?.isCancelled == true { throw ReconstructionError.cancelled }

        let positions = input.positions.map {
            PtychographyPosition(row: Double($0.row), column: Double($0.column))
        }
        let object = try kitArray(input.initialObject)
        let probe = try kitArray(input.initialProbe)
        let isCancelled: () -> Bool = { cancellation?.isCancelled == true }
        let kitProgress: (Int, Int) -> Void = { completed, total in progress?(Double(completed) / Double(total)) }
        let kit: SingleslicePtychography.Result
        do {
            do {
                kit = try SingleslicePtychography.reconstructSingle(
                    amplitudes: input.amplitudes, positions: positions, object: object, probe: probe,
                    iterations: options.iterations, stepSize: Double(options.stepSize),
                    normalizationMinimum: Double(options.normalizationMinimum), fixProbe: options.fixProbe,
                    purePhaseObject: options.purePhaseObject, constrainObjectAmplitude: options.constrainObjectAmplitude,
                    fixProbeCenterOfMass: options.fixProbeCenterOfMass,
                    constrainProbeAmplitude: options.constrainProbeAmplitude,
                    probeAmplitudeRelativeRadius: Double(options.probeAmplitudeRelativeRadius),
                    probeAmplitudeRelativeWidth: Double(options.probeAmplitudeRelativeWidth),
                    isCancelled: isCancelled, progress: kitProgress
                )
            } catch PtychographyError.invalidInput {
                // The input was validated above, so this is a detector size vDSP's DFT does not take (2^n x {1, 3, 5, 15}, >= 16):
                // the kit's Double path, about twice the memory.
                guard fallbackBytes <= options.maxWorkingBytes else {
                    throw ReconstructionError.memoryLimit(bytes: fallbackBytes, limit: options.maxWorkingBytes)
                }
                kit = try SingleslicePtychography.reconstruct(
                    amplitudes: input.amplitudes.map { Double($0) }, positions: positions, object: object, probe: probe,
                    iterations: options.iterations, stepSize: Double(options.stepSize),
                    normalizationMinimum: Double(options.normalizationMinimum), fixProbe: options.fixProbe,
                    purePhaseObject: options.purePhaseObject, constrainObjectAmplitude: options.constrainObjectAmplitude,
                    fixProbeCenterOfMass: options.fixProbeCenterOfMass,
                    constrainProbeAmplitude: options.constrainProbeAmplitude,
                    probeAmplitudeRelativeRadius: Double(options.probeAmplitudeRelativeRadius),
                    probeAmplitudeRelativeWidth: Double(options.probeAmplitudeRelativeWidth),
                    isCancelled: isCancelled, progress: kitProgress
                )
            }
        } catch is CancellationError {
            throw ReconstructionError.cancelled
        } catch PtychographyError.invalidInput {
            throw ReconstructionError.invalidInput("array shapes, values, or sampling are inconsistent")
        }
        if cancellation?.isCancelled == true { throw ReconstructionError.cancelled }
        return SingleslicePtychographyResult(
            object: appArray(kit.object), probe: appArray(kit.probe),
            positions: input.positions, errorHistory: kit.errors.map { Float($0) },
            objectSamplingRowAngstrom: input.objectSamplingRowAngstrom,
            objectSamplingColumnAngstrom: input.objectSamplingColumnAngstrom,
            options: options, probeAberrations: input.probeAberrations
        )
    }

    private static func kitArray(_ array: PtychographyComplexArray) throws -> PtychographyArray {
        do {
            return try PtychographyArray(
                rows: array.height, columns: array.width,
                real: array.real.map { Double($0) }, imaginary: array.imaginary.map { Double($0) }
            )
        } catch {
            throw ReconstructionError.invalidInput("array shapes, values, or sampling are inconsistent")
        }
    }

    private static func appArray(_ array: PtychographyArray) -> PtychographyComplexArray {
        PtychographyComplexArray(
            width: array.columns, height: array.rows,
            real: array.real.map { Float($0) }, imaginary: array.imaginary.map { Float($0) }
        )
    }
}
