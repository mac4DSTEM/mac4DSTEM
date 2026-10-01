import Foundation

/// D002 (Gate D, 2026-09-09): one scan-position case and the wrong
/// conventions it must NOT match.
struct PositionCase: Decodable {
    let ry: Int, rx: Int, qy: Int, qx: Int
    let rotationDeg: Double
    let transpose: Bool
    let scanSamplingAngstrom: Double
    let qSamplingInvAngstrom: Double
    let expected: [Double]
    let controls: [String: [Double]]
}

/// R1 (2026-09-30): one initial-probe case. `polar` is what py4DSTEM's ComplexProbe was given; `cartesian` is what py4DSTEM's own
/// `polar_aberrations_to_cartesian` derives from it (C10 = -defocus, C12a/C12b, C21a/C21b, ...); `real`/`imag` are the
/// corner-centred unit-norm `ComplexProbe(...).build()._array`.
struct ProbeCase: Decodable {
    let name: String
    let gptsRow: Int, gptsColumn: Int
    let samplingRow: Double, samplingColumn: Double
    let energyEV: Double, semiangleMrad: Double, rolloffMrad: Double
    let polar: [String: Double]
    let cartesian: [String: Double]
    let real: [Double]
    let imag: [Double]
}

/// FNV-1a over the bit patterns: the golden hashes below were captured from the probe code at git 02174c9c, BEFORE R1.
func bitHash(_ values: [Float]) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for value in values {
        var bits = value.bitPattern
        for _ in 0..<4 {
            hash ^= UInt64(bits & 0xff)
            hash = hash &* 0x100000001b3
            bits >>= 8
        }
    }
    return hash
}

/// py4DSTEM's cartesian terms as the app's aberrations: defocus = -C10 (ComplexProbe C10 = -defocus), C12a/C12b, and every other
/// "C{m}{n}[a|b]" as a higher-order term with radial order m = first digit, angular order n = second digit.
func probeAberrations(from cartesian: [String: Double]) -> PtychographyProbeAberrations {
    var aberrations = PtychographyProbeAberrations()
    for (key, value) in cartesian.sorted(by: { $0.key < $1.key }) {
        let digits = Array(key.dropFirst())
        let radial = Int(String(digits[0]))!, angular = Int(String(digits[1]))!
        if radial == 1 && angular == 0 { aberrations.defocusAngstrom = -value; continue }
        if radial == 1 && angular == 2 {
            if digits.count == 3 && digits[2] == "a" { aberrations.c12aAngstrom = value }
            else { aberrations.c12bAngstrom = value }
            continue
        }
        aberrations.higherOrder.append(.init(
            radialOrder: radial, angularOrder: angular,
            component: digits.count == 3 && digits[2] == "b" ? 1 : 0, coefficientAngstrom: value
        ))
    }
    return aberrations
}

struct Fixture: Decodable {
    let probeCases: [ProbeCase]
    let scanShape: [Int]
    let probeShape: [Int]
    let objectShape: [Int]
    let positions: [Float]
    let amplitudes: [Float]
    let initialObjectReal: [Float]
    let initialObjectImag: [Float]
    let initialProbeReal: [Float]
    let initialProbeImag: [Float]
    let iterations: Int
    let stepSize: Float
    let normalizationMinimum: Float
    let errors: [Float]
    let objectReal: [Float]
    let objectImag: [Float]
    let probeReal: [Float]
    let probeImag: [Float]
    let cropShape: [Int]
    let cropPhase: [Float]
    let cropAmplitude: [Float]
    let constrainedErrors: [Float]
    let constrainedObjectReal: [Float]
    let constrainedObjectImag: [Float]
    let constrainedProbeReal: [Float]
    let constrainedProbeImag: [Float]
    let centeredProbePhase: [Float]
    let centeredProbeAmplitude: [Float]
    let dmErrors: [Float]
    let dmObjectReal: [Float]
    let dmObjectImag: [Float]
    let dmProbeReal: [Float]
    let dmProbeImag: [Float]
    let dmCropPhase: [Float]
    let dmCropAmplitude: [Float]
    let positionCases: [PositionCase]
}

/// R3 (2026-10-01): truth.py's fixture - a synthetic cube with a KNOWN object and a DEFOCUSED probe, and py4DSTEM's own
/// SingleslicePtychography runs on bit-identical inputs (positions, float32 amplitudes, the float32 starting probe).
struct TruthScore: Decodable {
    let shiftRow: Double, shiftColumn: Double, phaseOffset: Double, pearson: Double, rms: Double
}

struct TruthRun: Decodable {
    let method: String
    let iterations: Int
    let normalizationMinimum: Float
    let errors: [Float]
    let finalReal: [Float]
    let finalImag: [Float]
    let truth: TruthScore
}

struct TruthFixture: Decodable {
    let name: String
    let defocusAngstrom: Double, energyEV: Double, semiangleMrad: Double, rolloffMrad: Double
    let objectSamplingAngstrom: Double
    let scanShape: [Int], probeShape: [Int], objectShape: [Int]
    let positions: [Float]
    let amplitudes: [Float]
    let probeReal: [Float], probeImag: [Float]
    let truthReal: [Float], truthImag: [Float]
    let py4dstem: [TruthRun]
}

struct TruthDocument: Decodable {
    let fixtures: [TruthFixture]
    let py4dstemVersion: String
}

/// The position-bounds crop `SingleslicePtychographyResult.objectPhase(cropped:)` shows (floor of the minimum, ceil of the maximum).
func cropBounds(_ positions: [PtychographyPosition], height: Int, width: Int) -> (row0: Int, row1: Int, column0: Int, column1: Int) {
    let rows = positions.map(\.row), columns = positions.map(\.column)
    let row0 = max(0, Int(floor(rows.min()!))), column0 = max(0, Int(floor(columns.min()!)))
    return (row0, max(row0 + 1, min(height, Int(ceil(rows.max()!)))), column0, max(column0 + 1, min(width, Int(ceil(columns.max()!)))))
}

/// truth.py's `score`, in Swift: the truth is registered onto the object (subpixel shift from the FFT cross-correlation of the
/// mean-removed phase maps on the crop, parabolic peak; then the global phase offset arg sum(o conj(t)) on the crop), then the
/// Pearson correlation of the two phase maps and the RMS of the offset-removed wrapped phase difference, both on the crop.
func scoreAgainstTruth(
    objectReal: [Float], objectImag: [Float], truthReal: [Float], truthImag: [Float],
    height: Int, width: Int, positions: [PtychographyPosition]
) throws -> TruthScore {
    guard let fft = FFT2D(nx: width, ny: height) else {
        throw NSError(domain: "singleslice-ptychography-test", code: 3, userInfo: [NSLocalizedDescriptionKey: "no FFT for the object canvas"])
    }
    let count = height * width
    let bounds = cropBounds(positions, height: height, width: width)
    var phaseObject = [Float](repeating: 0, count: count), phaseTruth = [Float](repeating: 0, count: count)
    for index in 0..<count {
        phaseObject[index] = atan2(objectImag[index], objectReal[index])
        phaseTruth[index] = atan2(truthImag[index], truthReal[index])
    }
    var meanObject = 0.0, meanTruth = 0.0, cropCount = 0.0
    for row in bounds.row0..<bounds.row1 {
        for column in bounds.column0..<bounds.column1 {
            meanObject += Double(phaseObject[row * width + column]); meanTruth += Double(phaseTruth[row * width + column]); cropCount += 1
        }
    }
    meanObject /= cropCount; meanTruth /= cropCount
    var windowedObject = [Float](repeating: 0, count: count), windowedObjectImag = [Float](repeating: 0, count: count)
    var windowedTruth = [Float](repeating: 0, count: count), windowedTruthImag = [Float](repeating: 0, count: count)
    for row in bounds.row0..<bounds.row1 {
        for column in bounds.column0..<bounds.column1 {
            let index = row * width + column
            windowedObject[index] = phaseObject[index] - Float(meanObject)
            windowedTruth[index] = phaseTruth[index] - Float(meanTruth)
        }
    }
    fft.transform(re: &windowedObject, im: &windowedObjectImag, forward: true)
    fft.transform(re: &windowedTruth, im: &windowedTruthImag, forward: true)
    var correlationReal = [Float](repeating: 0, count: count), correlationImag = [Float](repeating: 0, count: count)
    for index in 0..<count {   // object * conj(truth)
        correlationReal[index] = windowedObject[index] * windowedTruth[index] + windowedObjectImag[index] * windowedTruthImag[index]
        correlationImag[index] = windowedObjectImag[index] * windowedTruth[index] - windowedObject[index] * windowedTruthImag[index]
    }
    fft.transform(re: &correlationReal, im: &correlationImag, forward: false)
    var best = 0
    for index in 1..<count where correlationReal[index] > correlationReal[best] { best = index }
    let peakRow = best / width, peakColumn = best % width
    func refine(_ k: Int, _ n: Int, _ value: (Int) -> Float) -> Double {
        let before = Double(value((k - 1 + n) % n)), at = Double(value(k)), after = Double(value((k + 1) % n))
        let denominator = before - 2 * at + after
        var shift = Double(k) + (denominator != 0 ? 0.5 * (before - after) / denominator : 0)
        if shift > Double(n) / 2 { shift -= Double(n) }
        return shift
    }
    let shiftRow = refine(peakRow, height) { correlationReal[$0 * width + peakColumn] }
    let shiftColumn = refine(peakColumn, width) { correlationReal[peakRow * width + $0] }
    var shiftedReal = truthReal, shiftedImag = truthImag
    fft.transform(re: &shiftedReal, im: &shiftedImag, forward: true)
    for row in 0..<height {
        for column in 0..<width {
            let phase = -2 * Double.pi * (Double(FFT2D.fftfreq(row, height)) * shiftRow + Double(FFT2D.fftfreq(column, width)) * shiftColumn)
            let cosine = Float(cos(phase)), sine = Float(sin(phase))
            let index = row * width + column
            let oldReal = shiftedReal[index], oldImag = shiftedImag[index]
            shiftedReal[index] = oldReal * cosine - oldImag * sine
            shiftedImag[index] = oldReal * sine + oldImag * cosine
        }
    }
    fft.transform(re: &shiftedReal, im: &shiftedImag, forward: false)
    var sumReal = 0.0, sumImag = 0.0
    for row in bounds.row0..<bounds.row1 {
        for column in bounds.column0..<bounds.column1 {
            let index = row * width + column
            sumReal += Double(objectReal[index] * shiftedReal[index] + objectImag[index] * shiftedImag[index])
            sumImag += Double(objectImag[index] * shiftedReal[index] - objectReal[index] * shiftedImag[index])
        }
    }
    let phaseOffset = atan2(sumImag, sumReal)
    var differences = [Double](), phasesObject = [Double](), phasesTruth = [Double]()
    for row in bounds.row0..<bounds.row1 {
        for column in bounds.column0..<bounds.column1 {
            let index = row * width + column
            let productReal = Double(objectReal[index] * shiftedReal[index] + objectImag[index] * shiftedImag[index])
            let productImag = Double(objectImag[index] * shiftedReal[index] - objectReal[index] * shiftedImag[index])
            differences.append(atan2(productImag, productReal) - phaseOffset)
            phasesObject.append(atan2(Double(objectImag[index]), Double(objectReal[index])) - phaseOffset)
            phasesTruth.append(atan2(Double(shiftedImag[index]), Double(shiftedReal[index])))
        }
    }
    differences = differences.map { atan2(sin($0), cos($0)) }
    phasesObject = phasesObject.map { atan2(sin($0), cos($0)) }
    let meanDifference = differences.reduce(0, +) / Double(differences.count)
    let rms = sqrt(differences.reduce(0.0) { $0 + ($1 - meanDifference) * ($1 - meanDifference) } / Double(differences.count))
    let meanA = phasesObject.reduce(0, +) / Double(phasesObject.count), meanB = phasesTruth.reduce(0, +) / Double(phasesTruth.count)
    var covariance = 0.0, varianceA = 0.0, varianceB = 0.0
    for index in phasesObject.indices {
        let a = phasesObject[index] - meanA, b = phasesTruth[index] - meanB
        covariance += a * b; varianceA += a * a; varianceB += b * b
    }
    let pearson = varianceA > 0 && varianceB > 0 ? covariance / sqrt(varianceA * varianceB) : .nan
    return TruthScore(shiftRow: shiftRow, shiftColumn: shiftColumn, phaseOffset: phaseOffset, pearson: pearson, rms: rms)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "singleslice-ptychography-test", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func maximumError(_ actual: [Float], _ expected: [Float]) -> Float {
    guard actual.count == expected.count else { return .infinity }
    return zip(actual, expected).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

func maximumPhaseError(
    _ actual: [Float], _ expected: [Float], amplitudes: [Float]
) -> Float {
    guard actual.count == expected.count, actual.count == amplitudes.count else {
        return .infinity
    }
    return zip(zip(actual, expected), amplitudes).reduce(0) {
        guard $1.1 > 1e-4 else { return $0 }
        return max($0, abs(atan2(sin($1.0.0 - $1.0.1), cos($1.0.0 - $1.0.1))))
    }
}

@main
struct Harness {
    static func main() async throws {
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let positions = stride(from: 0, to: fixture.positions.count, by: 2).map {
            PtychographyPosition(row: fixture.positions[$0],
                                 column: fixture.positions[$0 + 1])
        }
        let input = SingleslicePtychographyInput(
            scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1],
            detectorHeight: fixture.probeShape[0], detectorWidth: fixture.probeShape[1],
            amplitudes: fixture.amplitudes, positions: positions,
            objectSamplingRowAngstrom: 0.5, objectSamplingColumnAngstrom: 0.75,
            initialObject: PtychographyComplexArray(
                width: fixture.objectShape[1], height: fixture.objectShape[0],
                real: fixture.initialObjectReal, imaginary: fixture.initialObjectImag
            ),
            initialProbe: PtychographyComplexArray(
                width: fixture.probeShape[1], height: fixture.probeShape[0],
                real: fixture.initialProbeReal, imaginary: fixture.initialProbeImag
            )
        )
        var options = SingleslicePtychographyOptions()
        options.iterations = fixture.iterations
        options.stepSize = fixture.stepSize
        options.normalizationMinimum = fixture.normalizationMinimum
        let result = try SingleslicePtychography.reconstruct(input: input, options: options)
        let errors = maximumError(result.errorHistory, fixture.errors)
        let objectReal = maximumError(result.object.real, fixture.objectReal)
        let objectImag = maximumError(result.object.imaginary, fixture.objectImag)
        let probeReal = maximumError(result.probe.real, fixture.probeReal)
        let probeImag = maximumError(result.probe.imaginary, fixture.probeImag)
        try require(errors < 2e-5, "iteration errors differ: \(errors)")
        try require(max(objectReal, objectImag) < 3e-5,
                    "final object differs: \(objectReal), \(objectImag)")
        try require(max(probeReal, probeImag) < 3e-5,
                    "final probe differs: \(probeReal), \(probeImag)")
        let phase = result.objectPhase()
        let amplitude = result.objectAmplitude()
        try require(phase.height == fixture.cropShape[0]
                    && phase.width == fixture.cropShape[1], "object crop shape differs")
        try require(maximumError(phase.pixels, fixture.cropPhase) < 3e-5,
                    "cropped phase differs")
        try require(maximumError(amplitude.pixels, fixture.cropAmplitude) < 3e-5,
                    "cropped amplitude differs")
        try require(input.initialObject.real == fixture.initialObjectReal
                    && input.initialProbe.real == fixture.initialProbeReal,
                    "input checkpoint was mutated")
        print("PASS: every GD error, final complex object/probe, and crop")

        var constrainedOptions = options
        constrainedOptions.constrainObjectAmplitude = true
        constrainedOptions.fixProbeCenterOfMass = true
        constrainedOptions.constrainProbeAmplitude = true
        constrainedOptions.probeAmplitudeRelativeRadius = 0.42
        constrainedOptions.probeAmplitudeRelativeWidth = 0.09
        let constrained = try SingleslicePtychography.reconstruct(
            input: input, options: constrainedOptions
        )
        try require(maximumError(constrained.errorHistory, fixture.constrainedErrors) < 2e-5,
                    "constrained iteration errors differ")
        try require(maximumError(constrained.object.real, fixture.constrainedObjectReal) < 3e-5
                    && maximumError(constrained.object.imaginary, fixture.constrainedObjectImag) < 3e-5,
                    "constrained object differs")
        try require(maximumError(constrained.probe.real, fixture.constrainedProbeReal) < 3e-5
                    && maximumError(constrained.probe.imaginary, fixture.constrainedProbeImag) < 3e-5,
                    "constrained probe differs")
        try require(maximumError(constrained.probePhase().pixels, fixture.centeredProbePhase) < 3e-5,
                    "centered probe phase differs")
        try require(maximumError(constrained.probeAmplitude().pixels,
                                 fixture.centeredProbeAmplitude) < 3e-5,
                    "centered probe amplitude differs")
        try require(constrained.options == constrainedOptions,
                    "completed result did not retain exact options")
        print("PASS: object/probe constraints and centered probe diagnostics")

        var dmOptions = options
        dmOptions.method = .differenceMapAlternatingProjections
        dmOptions.projectionParameter = 0.8
        let dm = try SingleslicePtychography.reconstruct(input: input, options: dmOptions)
        try require(maximumError(dm.errorHistory, fixture.dmErrors) < 2e-5,
                    "DM/AP iteration errors differ")
        try require(maximumError(dm.object.real, fixture.dmObjectReal) < 3e-5
                    && maximumError(dm.object.imaginary, fixture.dmObjectImag) < 3e-5,
                    "DM/AP object differs")
        try require(maximumError(dm.probe.real, fixture.dmProbeReal) < 3e-5
                    && maximumError(dm.probe.imaginary, fixture.dmProbeImag) < 3e-5,
                    "DM/AP probe differs")
        let dmPhaseError = maximumPhaseError(
            dm.objectPhase().pixels, fixture.dmCropPhase,
            amplitudes: fixture.dmCropAmplitude
        )
        try require(dmPhaseError < 3e-4,
                    "DM/AP object crop differs: \(dmPhaseError)")
        try require(maximumError(dm.objectAmplitude().pixels,
                                 fixture.dmCropAmplitude) < 3e-5,
                    "DM/AP object amplitude crop differs")
        try require(dm.options.method == .differenceMapAlternatingProjections
                    && dm.options.projectionParameter == 0.8,
                    "DM/AP result options differ")
        print("PASS: retained-exit-wave DM/AP projection method")

        var limited = options
        limited.maxWorkingBytes = 1
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: limited)
            try require(false, "memory ceiling was ignored")
        } catch SingleslicePtychography.ReconstructionError.memoryLimit {}
        var invalid = options
        invalid.iterations = 0
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: invalid)
            try require(false, "zero iterations were accepted")
        } catch SingleslicePtychography.ReconstructionError.invalidOptions {}
        invalid = options
        invalid.probeAmplitudeRelativeWidth = 0
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: invalid)
            try require(false, "invalid probe support width was accepted")
        } catch SingleslicePtychography.ReconstructionError.invalidOptions {}
        invalid = dmOptions
        invalid.projectionParameter = 1.1
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: invalid)
            try require(false, "invalid DM/AP alpha was accepted")
        } catch SingleslicePtychography.ReconstructionError.invalidOptions {}
        let cancellation = AnalysisCancellationToken()
        do {
            _ = try SingleslicePtychography.reconstruct(
                input: input, options: options, cancellation: cancellation
            ) { fraction in
                if fraction > 0 { cancellation.cancel() }
            }
            try require(false, "mid-reconstruction cancellation was ignored")
        } catch SingleslicePtychography.ReconstructionError.cancelled {}
        print("PASS: immutable input, invalid options, memory, and cancellation")

        // R1 (2026-09-30) — the initial probe against py4DSTEM's `ComplexProbe(...).build()._array`, on a NON-square grid with
        // different row/column samplings, through py4DSTEM's own polar -> cartesian helper. Pins three conventions at once: the
        // defocus sign (C10 = -defocus), the C12a/C12b <-> C12/phi12 mapping, and phi = arctan2(second axis, first axis).
        do {
            var worst = 0.0
            var separations = [String: Double]()
            var plantedControlsRejected = 0
            var inFocus: [Double]?
            for probeCase in fixture.probeCases {
                guard let fft = FFT2D(nx: probeCase.gptsColumn, ny: probeCase.gptsRow) else {
                    throw NSError(domain: "singleslice-ptychography-test", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "no FFT for the probe grid"])
                }
                let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: probeCase.energyEV)
                let aberrations = probeAberrations(from: probeCase.cartesian)
                func built(_ aberrations: PtychographyProbeAberrations) throws -> (real: [Double], imag: [Double]) {
                    let probe = try PtychographyProbe.build(
                        detectorHeight: probeCase.gptsRow, detectorWidth: probeCase.gptsColumn,
                        rowSamplingAngstrom: probeCase.samplingRow, columnSamplingAngstrom: probeCase.samplingColumn,
                        wavelengthAngstrom: wavelength, cutoffRad: probeCase.semiangleMrad / 1_000,
                        rolloffRad: probeCase.rolloffMrad / 1_000, aberrations: aberrations, fft: fft
                    )
                    return (probe.real.map(Double.init), probe.imaginary.map(Double.init))
                }
                func distance(_ other: (real: [Double], imag: [Double])) -> Double {
                    max(zip(other.real, probeCase.real).reduce(0.0) { max($0, abs($1.0 - $1.1)) },
                        zip(other.imag, probeCase.imag).reduce(0.0) { max($0, abs($1.0 - $1.1)) })
                }
                let amplitude = zip(probeCase.real, probeCase.imag).reduce(0.0) { max($0, hypot($1.0, $1.1)) }
                let actual = try built(aberrations)
                let error = distance(actual)
                worst = max(worst, error / amplitude)
                try require(error <= 1e-5 * amplitude,
                            "probe case `\(probeCase.name)`: max |delta| = \(error) against py4DSTEM's ComplexProbe (limit \(1e-5 * amplitude))")
                if probeCase.name == "in-focus" { inFocus = probeCase.real }
                // Anti-vacuity: the aberrated cases must be far from the in-focus probe, and every planted wrong convention
                // must be far from py4DSTEM's answer - otherwise the comparison above proves nothing about them.
                if !aberrations.isZero, let inFocus {
                    let gap = zip(inFocus, probeCase.real).reduce(0.0) { max($0, abs($1.0 - $1.1)) }
                    try require(gap > 100 * 1e-5 * amplitude,
                                "probe case `\(probeCase.name)` is indistinguishable from the in-focus probe (gap \(gap))")
                }
                var controls = [(String, PtychographyProbeAberrations)]()
                var flipped = aberrations; flipped.defocusAngstrom = -flipped.defocusAngstrom
                if aberrations.defocusAngstrom != 0 { controls.append(("defocus sign", flipped)) }
                var astigmatismFlipped = aberrations
                astigmatismFlipped.c12aAngstrom = -astigmatismFlipped.c12aAngstrom
                astigmatismFlipped.c12bAngstrom = -astigmatismFlipped.c12bAngstrom
                if aberrations.c12aAngstrom != 0 || aberrations.c12bAngstrom != 0 {
                    controls.append(("astigmatism sign", astigmatismFlipped))
                    var swapped = aberrations
                    swapped.c12aAngstrom = aberrations.c12bAngstrom
                    swapped.c12bAngstrom = aberrations.c12aAngstrom
                    controls.append(("C12a and C12b swapped", swapped))
                }
                if aberrations.higherOrder.contains(where: { $0.angularOrder > 0 }) {
                    var cosineSine = aberrations
                    cosineSine.higherOrder = aberrations.higherOrder.map {
                        var term = $0
                        if term.angularOrder > 0 { term.component = 1 - term.component }
                        return term
                    }
                    controls.append(("cosine and sine swapped", cosineSine))
                    var higherFlipped = aberrations
                    higherFlipped.higherOrder = aberrations.higherOrder.map {
                        var term = $0; term.coefficientAngstrom = -term.coefficientAngstrom; return term
                    }
                    controls.append(("higher-order sign", higherFlipped))
                }
                for (name, control) in controls {
                    let separation = distance(try built(control))
                    separations[name] = min(separations[name] ?? .infinity, separation / amplitude)
                    try require(separation > 100 * 1e-5 * amplitude,
                                "probe case `\(probeCase.name)`: the planted wrong convention `\(name)` is within \(separation) of py4DSTEM's probe - the fixture cannot tell it from the right one")
                    plantedControlsRejected += 1
                }
            }
            try require(plantedControlsRejected >= 14,
                        "only \(plantedControlsRejected) planted wrong conventions were checked - the probe controls have gone vacuous")
            let summary = separations.sorted { $0.key < $1.key }
                .map { "\($0.key) >= \(String(format: "%.2g", $0.value))" }.joined(separator: ", ")
            print("PASS: the initial probe equals py4DSTEM's ComplexProbe over \(fixture.probeCases.count) cases (worst |delta| / max|probe| = \(String(format: "%.2g", worst))); \(plantedControlsRejected) planted wrong conventions each rejected (relative separations: \(summary))")
        }

        // D002 — the preparer's scan positions against py4DSTEM's
        // `_calculate_scan_positions_in_pixels`. Before the fix the preparer
        // built an axis-aligned raster and never read `rotationRad` or
        // `transpose`, so a 0 deg and a 30 deg calibration were bit-identical.
        //
        // Every case is a crop of the demo cube. The 12x12x64x64 full extent is
        // SQUARE with equal row/column object sampling, which makes transpose a
        // no-op by geometry and hides a wrong convention — it is here only as a
        // control, and the cases that decide anything are non-square.
        let source = DemoFourDDataSource()
        let fullDescriptor = try await source.discoverPrimaryDataset()
        var controlsThatBit = 0
        for (index, testCase) in fixture.positionCases.enumerated() {
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0,
                                   height: testCase.ry, width: testCase.rx),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0,
                                       height: testCase.qy, width: testCase.qx)
            )
            let view = try LoadView(source: fullDescriptor, specification: specification)
            try require(view.descriptor.ry == testCase.ry && view.descriptor.rx == testCase.rx
                        && view.descriptor.qy == testCase.qy && view.descriptor.qx == testCase.qx,
                        "position case \(index): the crop is \(view.descriptor.ry)x\(view.descriptor.rx)x\(view.descriptor.qy)x\(view.descriptor.qx), not the case's shape")
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000)
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: testCase.scanSamplingAngstrom,
                reciprocalSamplingInvAngstrom: testCase.qSamplingInvAngstrom,
                energyEV: 80_000, wavelengthAngstrom: wavelength,
                originQX: 0, originQY: 0,
                rotationRad: testCase.rotationDeg * .pi / 180,
                transpose: testCase.transpose
            )
            let prepared = try await PtychographyPreparer.prepare(
                source: source, view: view, calibration: calibration, probeRadiusPixels: 8
            )
            var actual = [Double]()
            actual.reserveCapacity(prepared.positions.count * 2)
            for position in prepared.positions {
                actual.append(Double(position.row))
                actual.append(Double(position.column))
            }
            try require(actual.count == testCase.expected.count,
                        "position case \(index): \(actual.count) values, expected \(testCase.expected.count)")
            func maximumDifference(_ other: [Double]) -> Double {
                zip(actual, other).reduce(0.0) { max($0, abs($1.0 - $1.1)) }
            }
            // Float positions built from Double arithmetic: 1e-3 object pixels
            // is far below the smallest control here (1.73 px) and far above
            // Float rounding on values of order 100.
            let tolerance = 1e-3
            let delta = maximumDifference(testCase.expected)
            try require(delta < tolerance,
                        "position case \(index) (rot \(testCase.rotationDeg) deg, transpose \(testCase.transpose), q \(testCase.qy)x\(testCase.qx)): max |delta| = \(delta) object px against py4DSTEM's convention")
            // Anti-vacuity: every control that is itself distinguishable from
            // the reference must be distinguishable from the real code too.
            for (name, control) in testCase.controls.sorted(by: { $0.key < $1.key }) {
                let separation = zip(testCase.expected, control)
                    .reduce(0.0) { max($0, abs($1.0 - $1.1)) }
                guard separation > tolerance else { continue }
                controlsThatBit += 1
                try require(maximumDifference(control) > tolerance,
                            "position case \(index): the preparer matches the WRONG convention `\(name)`")
            }
        }
        // A reference.py that emitted controls identical to the reference would
        // make every check above vacuous.
        try require(controlsThatBit >= 12,
                    "only \(controlsThatBit) negative controls were distinguishable — the position controls have gone vacuous")
        print("PASS: scan positions match py4DSTEM's rotate/transpose/clip convention over \(fixture.positionCases.count) cases; \(controlsThatBit) planted wrong conventions each rejected")

        // Gate B, 2026-09-11. `calibration.originQX`/`originQY` shift the
        // detector resample (PtychographyPreparation.swift:70, :76) and NOTHING
        // asserted them: the only thing this harness read from `prepare` was
        // `positions`, which the origin does not touch, so deleting both fields
        // left the whole gate green. A position case cannot close that — the
        // origin moves AMPLITUDES — so this is an analytic invariant instead.
        // At an INTEGER shift the bilinear resample reduces exactly to a
        // circular shift (`rowFraction`/`columnFraction` are 0), so the shifted
        // amplitudes must equal the unshifted ones rolled by that many rows
        // (originQX) or columns (originQY). Ground truth is the arithmetic, not
        // the code's own output.
        //
        // It also pins, in an executable place, the naming trap in that file:
        // `originQX` is added to the ROW and `originQY` to the COLUMN, which is
        // correct — `ParallaxPreprocessing.swift:98-99` sets
        // `originQX: Double(apertureCenterY)` — but it is the opposite sense to
        // the `cx` = COLUMN convention documented a few lines below it. Anyone
        // who "corrects" the naming must fail here.
        do {
            let shiftRows = 2
            let shiftColumns = 3
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 3, width: 4),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 16, width: 24)
            )
            let view = try LoadView(source: fullDescriptor, specification: specification)
            let descriptor = view.descriptor
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000)
            func amplitudes(originQX: Double, originQY: Double) async throws -> [Float] {
                let calibration = ParallaxPhysicalCalibration(
                    scanSamplingAngstrom: 1.0,
                    reciprocalSamplingInvAngstrom: 0.05,
                    energyEV: 80_000, wavelengthAngstrom: wavelength,
                    originQX: originQX, originQY: originQY,
                    rotationRad: 0, transpose: false
                )
                return try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration,
                    probeRadiusPixels: 8
                ).amplitudes
            }
            let base = try await amplitudes(originQX: 0, originQY: 0)
            let shifted = try await amplitudes(originQX: Double(shiftRows),
                                               originQY: Double(shiftColumns))
            let detectorCount = descriptor.qy * descriptor.qx
            try require(base.count == detectorCount * descriptor.ry * descriptor.rx
                        && shifted.count == base.count,
                        "origin-shift invariant: unexpected amplitude count")
            var maximumDelta: Float = 0
            var maximumSeparation: Float = 0
            for pattern in 0..<(descriptor.ry * descriptor.rx) {
                for row in 0..<descriptor.qy {
                    for column in 0..<descriptor.qx {
                        let sourceRow = (row + shiftRows) % descriptor.qy
                        let sourceColumn = (column + shiftColumns) % descriptor.qx
                        let here = pattern * detectorCount + row * descriptor.qx + column
                        let there = pattern * detectorCount
                            + sourceRow * descriptor.qx + sourceColumn
                        maximumDelta = max(maximumDelta, abs(shifted[here] - base[there]))
                        maximumSeparation = max(maximumSeparation,
                                                abs(base[there] - base[here]))
                    }
                }
            }
            // Anti-vacuity: on patterns flat along these axes the roll would be
            // a no-op and the assertion below would pass on anything at all.
            try require(maximumSeparation > 1e-3,
                        "the origin-shift invariant is VACUOUS: rolling by (\(shiftRows), \(shiftColumns)) moves the amplitudes by only \(maximumSeparation)")
            try require(maximumDelta < 1e-5,
                        "an integer origin shift is not a circular shift of the resampled amplitudes: max |delta| = \(maximumDelta) against a separation of \(maximumSeparation) — originQX must roll ROWS and originQY COLUMNS")
            print("PASS: an integer origin shift equals a circular shift of the resampled amplitudes (rows by \(shiftRows), columns by \(shiftColumns); separation \(maximumSeparation))")
        }
        // R1 (2026-09-30) — through the preparer. (1) No aberrations reproduce, bit for bit, the probe this code built
        // before R1 (the hashes were captured from git 02174c9c's PtychographyPreparation.swift on these two crops). (2) With
        // aberrations the prepared probe is the builder's probe up to the mean-intensity scale, i.e. `prepare` really hands them
        // on. (3) Non-finite or malformed aberrations are refused.
        do {
            struct Golden {
                let ry: Int, rx: Int, qy: Int, qx: Int
                let q: Double, radius: Float, originQX: Double, originQY: Double
                let real: UInt64, imaginary: UInt64
            }
            let goldens = [
                Golden(ry: 3, rx: 4, qy: 16, qx: 24, q: 0.05, radius: 8, originQX: 0, originQY: 0,
                       real: 0xa2f70f0ec0ff6fbd, imaginary: 0x3fc1df107866e72b),
                Golden(ry: 2, rx: 3, qy: 24, qx: 32, q: 0.0213, radius: 7.5, originQX: 1.25, originQY: 0.5,
                       real: 0x1c82119693445fab, imaginary: 0x2051128dad3f47bb),
            ]
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000)
            for (index, golden) in goldens.enumerated() {
                let specification = LoadSpecification(
                    scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: golden.ry, width: golden.rx),
                    detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: golden.qy, width: golden.qx)
                )
                let view = try LoadView(source: fullDescriptor, specification: specification)
                let calibration = ParallaxPhysicalCalibration(
                    scanSamplingAngstrom: 1.0, reciprocalSamplingInvAngstrom: golden.q,
                    energyEV: 80_000, wavelengthAngstrom: wavelength,
                    originQX: golden.originQX, originQY: golden.originQY, rotationRad: 0, transpose: false
                )
                let plain = try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius
                )
                try require(bitHash(plain.initialProbe.real) == golden.real
                            && bitHash(plain.initialProbe.imaginary) == golden.imaginary,
                            "golden crop \(index): the aberration-free probe is no longer bit-identical to the pre-R1 probe (real \(String(bitHash(plain.initialProbe.real), radix: 16)), imaginary \(String(bitHash(plain.initialProbe.imaginary), radix: 16)))")
                let explicitZero = try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius,
                    aberrations: PtychographyProbeAberrations()
                )
                try require(explicitZero.initialProbe.real == plain.initialProbe.real
                            && explicitZero.initialProbe.imaginary == plain.initialProbe.imaginary,
                            "golden crop \(index): explicit zero aberrations differ from the default")

                let aberrated = PtychographyProbeAberrations(
                    defocusAngstrom: -400, c12aAngstrom: 35, c12bAngstrom: -20,
                    higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 0, coefficientAngstrom: 1500)]
                )
                let prepared = try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius,
                    aberrations: aberrated
                )
                guard let fft = FFT2D(nx: golden.qx, ny: golden.qy) else { fatalError("no FFT") }
                let expected = try PtychographyProbe.build(
                    detectorHeight: golden.qy, detectorWidth: golden.qx,
                    rowSamplingAngstrom: 1 / (golden.q * Double(golden.qy)),
                    columnSamplingAngstrom: 1 / (golden.q * Double(golden.qx)),
                    wavelengthAngstrom: wavelength, cutoffRad: Double(golden.radius) * golden.q * wavelength,
                    rolloffRad: 0.002, aberrations: aberrated, fft: fft
                )
                let preparedNorm = sqrt(zip(prepared.initialProbe.real, prepared.initialProbe.imaginary)
                    .reduce(0.0) { $0 + Double($1.0 * $1.0 + $1.1 * $1.1) })
                var deviation = 0.0
                var peak = 0.0
                for pixel in 0..<expected.real.count {
                    deviation = max(deviation,
                                    abs(Double(prepared.initialProbe.real[pixel]) / preparedNorm - Double(expected.real[pixel])),
                                    abs(Double(prepared.initialProbe.imaginary[pixel]) / preparedNorm - Double(expected.imaginary[pixel])))
                    peak = max(peak, hypot(Double(expected.real[pixel]), Double(expected.imaginary[pixel])))
                }
                try require(deviation < 1e-5 * peak,
                            "crop \(index): the prepared probe is not the aberrated probe (max |delta| \(deviation), peak \(peak))")
                let gap = zip(prepared.initialProbe.imaginary, plain.initialProbe.imaginary)
                    .reduce(0.0) { max($0, Double(abs($1.0 - $1.1))) }
                try require(gap > 0, "crop \(index): the aberrations changed nothing in the prepared probe")
                // The input records what it was built with, and the reconstruction carries the record through (the app publishes
                // the defocus from the RESULT, so it cannot name a probe the run did not start from).
                try require(prepared.probeAberrations == aberrated && plain.probeAberrations == PtychographyProbeAberrations(),
                            "crop \(index): `prepare` did not record the aberrations it built the probe with")
                var oneIteration = SingleslicePtychographyOptions()
                oneIteration.iterations = 1
                let carried = try SingleslicePtychography.reconstruct(input: prepared, options: oneIteration)
                try require(carried.probeAberrations == aberrated,
                            "crop \(index): the reconstruction did not carry the input's probe aberrations")
            }
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 2, width: 2),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 16, width: 16)
            )
            let view = try LoadView(source: fullDescriptor, specification: specification)
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 1.0, reciprocalSamplingInvAngstrom: 0.05,
                energyEV: 80_000, wavelengthAngstrom: wavelength,
                originQX: 0, originQY: 0, rotationRad: 0, transpose: false
            )
            let malformed: [PtychographyProbeAberrations] = [
                PtychographyProbeAberrations(defocusAngstrom: .nan),
                PtychographyProbeAberrations(c12aAngstrom: .infinity),
                PtychographyProbeAberrations(higherOrder: [.init(radialOrder: 0, angularOrder: 0, component: 0, coefficientAngstrom: 1)]),
                PtychographyProbeAberrations(higherOrder: [.init(radialOrder: 2, angularOrder: 0, component: 1, coefficientAngstrom: 1)]),
                PtychographyProbeAberrations(higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 0, coefficientAngstrom: .nan)]),
            ]
            for aberrations in malformed {
                do {
                    _ = try await PtychographyPreparer.prepare(
                        source: source, view: view, calibration: calibration, probeRadiusPixels: 4,
                        aberrations: aberrations
                    )
                    try require(false, "malformed aberrations were accepted: \(aberrations)")
                } catch SingleslicePtychography.ReconstructionError.invalidInput {}
            }
            print("PASS: zero aberrations are bit-identical to the pre-R1 probe on \(goldens.count) crops; aberrations reach the prepared probe; \(malformed.count) malformed sets refused")
        }

        // R3 (2026-10-01) — ground truth. truth.py simulates a cube from a KNOWN pure-phase object with a DEFOCUSED probe (200 / 400 /
        // 600 A) and runs py4DSTEM's own SingleslicePtychography on bit-identical inputs; here the app's engine runs on the same
        // inputs and both are scored against the truth. Bars come from the measured distribution over the three defocus values and two
        // more seeds (lane R report, 2026-10-01: GD truth Pearson 0.980-0.987 at 32 iterations, rms 0.017-0.018 rad; app-py4DSTEM
        // GD error histories within 1.8e-2, final phase within 1.5e-2 rad; wrong-sign probe 0.12-0.21; DM over 8 iterations within
        // 2.7e-2 (norm-min 1) and 5.2e-3 (0.02)); each bar sits >= 2.8x outside what was measured. The difference map's convergence
        // is NOT pinned: on both sides it diverges at norm-min 1 from the first iteration and past ~16 iterations at any
        // normalization (py4DSTEM's own DM_AP included) - its truth scores are printed for the reader.
        // Parity needs `constrainObjectAmplitude = true`: py4DSTEM clamps |object| <= 1 on every iteration of a complex object
        // (ptychographic_constraints.py `_object_constraints` -> `_object_threshold_constraint`, unconditional); the app exposes
        // that clamp as an option. The clamp-off run is the anti-vacuity control: the parity bar must tell it apart.
        do {
            let truth = try JSONDecoder().decode(
                TruthDocument.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            )
            try require(truth.fixtures.count >= 3, "the truth fixture has \(truth.fixtures.count) cases, not >= 3 defocus values")
            var rows = [String]()
            var defocusValues = Set<Double>()
            for fixture in truth.fixtures {
                let det = fixture.probeShape[0], canvas = fixture.objectShape[0]
                defocusValues.insert(fixture.defocusAngstrom)
                let positions = stride(from: 0, to: fixture.positions.count, by: 2).map {
                    PtychographyPosition(row: fixture.positions[$0], column: fixture.positions[$0 + 1])
                }
                guard let pyGD = fixture.py4dstem.first(where: { $0.method == "gd" }),
                      let pyDM1 = fixture.py4dstem.first(where: { $0.method == "dm" && $0.normalizationMinimum == 1 }),
                      let pyDMSmall = fixture.py4dstem.first(where: { $0.method == "dm" && $0.normalizationMinimum < 1 }) else {
                    throw NSError(domain: "singleslice-ptychography-test", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "\(fixture.name): truth.py did not run GD, DM(1) and DM(<1)"])
                }
                func input(probeReal: [Float], probeImag: [Float]) -> SingleslicePtychographyInput {
                    SingleslicePtychographyInput(
                        scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1], detectorHeight: det, detectorWidth: det,
                        amplitudes: fixture.amplitudes, positions: positions,
                        objectSamplingRowAngstrom: fixture.objectSamplingAngstrom, objectSamplingColumnAngstrom: fixture.objectSamplingAngstrom,
                        initialObject: PtychographyComplexArray(width: canvas, height: canvas,
                                                                real: [Float](repeating: 1, count: canvas * canvas),
                                                                imaginary: [Float](repeating: 0, count: canvas * canvas)),
                        initialProbe: PtychographyComplexArray(width: det, height: det, real: probeReal, imaginary: probeImag)
                    )
                }
                func run(_ input: SingleslicePtychographyInput, _ method: SingleslicePtychographyMethod, iterations: Int,
                         normalizationMinimum: Float, clamp: Bool) throws -> SingleslicePtychographyResult {
                    var options = SingleslicePtychographyOptions()
                    options.method = method
                    options.iterations = iterations
                    options.stepSize = 0.5
                    options.projectionParameter = 1
                    options.normalizationMinimum = normalizationMinimum
                    options.constrainObjectAmplitude = clamp
                    return try SingleslicePtychography.reconstruct(input: input, options: options)
                }
                func score(_ result: SingleslicePtychographyResult) throws -> TruthScore {
                    try scoreAgainstTruth(objectReal: result.object.real, objectImag: result.object.imaginary,
                                          truthReal: fixture.truthReal, truthImag: fixture.truthImag,
                                          height: canvas, width: canvas, positions: positions)
                }
                func relativeGap(_ actual: [Float], _ reference: [Float]) -> Float {
                    guard actual.count == reference.count else { return .infinity }
                    return zip(actual, reference).reduce(0) { max($0, abs($1.0 - $1.1) / abs($1.1)) }
                }
                func phaseGap(_ result: SingleslicePtychographyResult, _ reference: TruthRun) -> Float {
                    let bounds = cropBounds(positions, height: canvas, width: canvas)
                    var worst: Float = 0
                    for row in bounds.row0..<bounds.row1 {
                        for column in bounds.column0..<bounds.column1 {
                            let index = row * canvas + column
                            let real = result.object.real[index] * reference.finalReal[index] + result.object.imaginary[index] * reference.finalImag[index]
                            let imag = result.object.imaginary[index] * reference.finalReal[index] - result.object.real[index] * reference.finalImag[index]
                            worst = max(worst, abs(atan2(imag, real)))
                        }
                    }
                    return worst
                }
                // The app's own probe at +/- the fixture's defocus, scaled to the mean diffraction intensity as `prepare` does.
                func appProbe(sign: Double) throws -> (real: [Float], imag: [Float]) {
                    guard let fft = FFT2D(nx: det, ny: det) else { throw NSError(domain: "singleslice-ptychography-test", code: 2) }
                    var probe = try PtychographyProbe.build(
                        detectorHeight: det, detectorWidth: det,
                        rowSamplingAngstrom: fixture.objectSamplingAngstrom, columnSamplingAngstrom: fixture.objectSamplingAngstrom,
                        wavelengthAngstrom: ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: fixture.energyEV),
                        cutoffRad: fixture.semiangleMrad / 1_000, rolloffRad: fixture.rolloffMrad / 1_000,
                        aberrations: PtychographyProbeAberrations(defocusAngstrom: sign * fixture.defocusAngstrom), fft: fft
                    )
                    let meanIntensity = fixture.amplitudes.reduce(0.0) { $0 + Double($1 * $1) } / Double(positions.count)
                    var spectrumReal = probe.real, spectrumImag = probe.imaginary
                    fft.transform(re: &spectrumReal, im: &spectrumImag, forward: true)
                    let probeIntensity = zip(spectrumReal, spectrumImag).reduce(0.0) { $0 + Double($1.0 * $1.0 + $1.1 * $1.1) }
                    let scale = Float(sqrt(meanIntensity / probeIntensity))
                    for index in probe.real.indices { probe.real[index] *= scale; probe.imaginary[index] *= scale }
                    return (probe.real, probe.imaginary)
                }
                let fixtureInput = input(probeReal: fixture.probeReal, probeImag: fixture.probeImag)

                // (1) The Swift scorer agrees with truth.py's on py4DSTEM's own final object (float32 FFT vs float64).
                let pyScore = try scoreAgainstTruth(objectReal: pyGD.finalReal, objectImag: pyGD.finalImag,
                                                    truthReal: fixture.truthReal, truthImag: fixture.truthImag,
                                                    height: canvas, width: canvas, positions: positions)
                try require(abs(pyScore.pearson - pyGD.truth.pearson) < 2e-3 && abs(pyScore.rms - pyGD.truth.rms) < 1e-3
                            && abs(pyScore.shiftRow - pyGD.truth.shiftRow) < 0.05 && abs(pyScore.shiftColumn - pyGD.truth.shiftColumn) < 0.05,
                            "\(fixture.name): the Swift scorer disagrees with truth.py's on py4DSTEM's object (Pearson \(pyScore.pearson) vs \(pyGD.truth.pearson), rms \(pyScore.rms) vs \(pyGD.truth.rms), shift (\(pyScore.shiftRow), \(pyScore.shiftColumn)) vs (\(pyGD.truth.shiftRow), \(pyGD.truth.shiftColumn)))")

                // (2) Gradient descent on the fixture's probe: the same operator as py4DSTEM's, and it reaches the truth.
                let gd = try run(fixtureInput, .gradientDescent, iterations: pyGD.iterations, normalizationMinimum: 1, clamp: true)
                let gdGap = relativeGap(gd.errorHistory, pyGD.errors)
                try require(gdGap < 5e-2, "\(fixture.name): GD error history differs from py4DSTEM's by \(gdGap) (limit 5e-2)")
                let gdPhaseGap = phaseGap(gd, pyGD)
                try require(gdPhaseGap < 5e-2, "\(fixture.name): GD final object phase differs from py4DSTEM's by \(gdPhaseGap) rad (limit 5e-2)")
                let gdScore = try score(gd)
                try require(gdScore.pearson >= 0.95 && gdScore.rms <= 0.03,
                            "\(fixture.name): GD does not reach the truth: Pearson \(gdScore.pearson) (>= 0.95), rms \(gdScore.rms) rad (<= 0.03)")
                try require(abs(gdScore.shiftRow) < 0.2 && abs(gdScore.shiftColumn) < 0.2,
                            "\(fixture.name): GD object is displaced from the truth by (\(gdScore.shiftRow), \(gdScore.shiftColumn)) px (limit 0.2)")

                // (3) The app's own probe builder at the fixture's defocus gives the same reconstruction; (4) the wrong sign does not.
                let plus = try appProbe(sign: 1)
                let gdApp = try run(input(probeReal: plus.real, probeImag: plus.imag), .gradientDescent, iterations: pyGD.iterations,
                                    normalizationMinimum: 1, clamp: true)
                let gdAppScore = try score(gdApp)
                try require(gdAppScore.pearson >= 0.95 && abs(gdAppScore.pearson - gdScore.pearson) < 0.01,
                            "\(fixture.name): the app-built probe reconstructs differently: Pearson \(gdAppScore.pearson) vs \(gdScore.pearson) with py4DSTEM's probe")
                let minus = try appProbe(sign: -1)
                let gdWrongSign = try run(input(probeReal: minus.real, probeImag: minus.imag), .gradientDescent, iterations: pyGD.iterations,
                                          normalizationMinimum: 1, clamp: true)
                let wrongScore = try score(gdWrongSign)
                try require(wrongScore.pearson < 0.5 && wrongScore.pearson < gdScore.pearson - 0.4,
                            "\(fixture.name): the WRONG-SIGN defocus probe still reaches the truth (Pearson \(wrongScore.pearson) vs \(gdScore.pearson)) - the defocus sign is not being tested")

                // (5) Anti-vacuity: without the clamp the GD history must fail the parity bar (measured 0.20-0.31).
                let gdOff = try run(fixtureInput, .gradientDescent, iterations: pyGD.iterations, normalizationMinimum: 1, clamp: false)
                let offGap = relativeGap(gdOff.errorHistory, pyGD.errors)
                try require(offGap > 0.1, "\(fixture.name): the GD parity bar is VACUOUS - the clamp-off run is within \(offGap) of py4DSTEM")

                // (6) Difference map: the same operator as py4DSTEM's DM_AP over 8 iterations, at the app's default normalization and
                // at a small one; its truth score is reported, not pinned.
                var dmRows = [String]()
                for pyDM in [pyDM1, pyDMSmall] {
                    let dm = try run(fixtureInput, .differenceMapAlternatingProjections, iterations: pyDM.iterations,
                                     normalizationMinimum: pyDM.normalizationMinimum, clamp: true)
                    let gap = relativeGap(dm.errorHistory, pyDM.errors)
                    // Pinned at the small normalization only (measured <= 5.2e-3 over 8 iterations on 5 fixtures, 10x margin). At
                    // norm-min 1 the map expands from iteration 1 (2.7e-2 by it 8, 0.27 by it 16 on df200; 25 % at it 3 on graphene),
                    // so that gap is printed, not pinned (refuter, 2026-10-01): a bar on a chaotic trajectory can go red on a
                    // different Accelerate build without any port change.
                    if pyDM.normalizationMinimum < 1 {
                        try require(gap < 0.05,
                                    "\(fixture.name): DM (norm-min \(pyDM.normalizationMinimum), \(pyDM.iterations) it) error history differs from py4DSTEM's by \(gap) (limit 0.05)")
                    }
                    let dmScore = try score(dm)
                    dmRows.append(String(format: "DM nm %g: app Pearson %.3f rms %.3f / py4DSTEM %.3f %.3f, histories within %.1e",
                                         pyDM.normalizationMinimum, dmScore.pearson, dmScore.rms, pyDM.truth.pearson, pyDM.truth.rms, gap))
                }
                rows.append(String(format: "  %@: GD Pearson %.4f rms %.4f rad shift (%.3f, %.3f) px [py4DSTEM %.4f %.4f]; app-built probe %.4f; wrong sign %.3f; app-py4DSTEM GD histories within %.1e, phase within %.1e rad (clamp off: %.2f); %@",
                                   fixture.name, gdScore.pearson, gdScore.rms, gdScore.shiftRow, gdScore.shiftColumn, pyGD.truth.pearson, pyGD.truth.rms,
                                   gdAppScore.pearson, wrongScore.pearson, gdGap, gdPhaseGap, offGap, dmRows.joined(separator: "; ")))
            }
            try require(defocusValues.count >= 3, "only \(defocusValues.count) distinct defocus values - the truth fixture has gone narrow")
            print("PASS: against a known object with a defocused probe (py4DSTEM \(truth.py4dstemVersion) on bit-identical inputs), \(truth.fixtures.count) fixtures:")
            rows.forEach { print($0) }
        }
        print("singleslice-ptychography-test: all passed")
    }
}
