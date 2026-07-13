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
