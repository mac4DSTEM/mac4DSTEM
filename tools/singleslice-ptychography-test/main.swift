import Foundation

struct Fixture: Decodable {
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
    static func main() throws {
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
        print("singleslice-ptychography-test: all passed")
    }
}
