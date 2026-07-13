import Foundation

struct Expected: Decodable {
    let factor: Double
    let shape: [Int]
    let padded: [Float]
    let cropShape: [Int]
    let cropped: [Float]
    let lowpass: Bool
    let probeRows: [Float]?
    let probeColumns: [Float]?
    let scores: [Float]?
}

struct Fixture: Decodable {
    let scanShape: [Int]
    let padding: [Int]
    let stackShape: [Int]
    let stack: [Float]
    let shifts: [Float]
    let kVectors: [Float]
    let scanSampling: Double
    let qSampling: Double
    let detectorHeight: Int
    let bfLimit: Double
    let dfLimit: Double
    let auto: Expected
    let filtered: Expected
    let lanczos: Expected
    let position: Expected
    let checkerboard: Expected
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "parallax-subpixel-test", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func maximumError(_ actual: [Float], _ expected: [Float]) -> Float {
    guard actual.count == expected.count else { return .infinity }
    return zip(actual, expected).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

func makeInputs(_ fixture: Fixture, complete: Bool = true)
    -> (ParallaxPreprocessResult, ParallaxAlignmentResult) {
    let vectors = stride(from: 0, to: fixture.kVectors.count, by: 2).map {
        ParallaxVector(qx: fixture.kVectors[$0], qy: fixture.kVectors[$0 + 1])
    }
    let shifts = stride(from: 0, to: fixture.shifts.count, by: 2).map {
        ParallaxScanShift(row: fixture.shifts[$0], column: fixture.shifts[$0 + 1])
    }
    let count = vectors.count
    let plane = fixture.stackShape[0] * fixture.stackShape[1]
    let calibration = ParallaxPhysicalCalibration(
        scanSamplingAngstrom: fixture.scanSampling,
        reciprocalSamplingInvAngstrom: fixture.qSampling,
        energyEV: 200_000, wavelengthAngstrom: 0.025079,
        originQX: 0, originQY: 0, rotationRad: 0, transpose: false
    )
    let preprocessing = ParallaxPreprocessResult(
        scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1],
        detectorHeight: fixture.detectorHeight, detectorWidth: fixture.detectorHeight,
        stackHeight: fixture.stackShape[0], stackWidth: fixture.stackShape[1],
        calibration: calibration, thresholdIntensity: 0.8,
        detectorMask: [Bool](repeating: true, count: count),
        detectorIndices: (0..<count).map { ParallaxDetectorIndex(qx: 0, qy: $0) },
        reciprocalVectors: vectors,
        probeAnglesMrad: vectors.map {
            ParallaxVector(qx: $0.qx * 25.079, qy: $0.qy * 25.079)
        },
        edgeWindow: [Float](repeating: 1, count: fixture.scanShape[0] * fixture.scanShape[1]),
        normalizedStack: fixture.stack, unshiftedStack: fixture.stack,
        incoherentBF: [Float](repeating: 1, count: plane), initialError: 0
    )
    let completed = complete ? [1] : []
    let alignment = ParallaxAlignmentResult(
        alignmentBin: 1, alignmentSchedule: [1], completedBins: completed,
        upsampleFactor: 8, groups: [], groupShifts: [], totalShifts: shifts,
        shiftedStack: [], shiftedMasks: [], reconstructionMask: [],
        alignedBF: [Float](repeating: 1, count: plane), errorHistory: [0],
        scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1],
        stackHeight: fixture.stackShape[0], stackWidth: fixture.stackShape[1]
    )
    return (preprocessing, alignment)
}

@main
struct Harness {
    static func main() throws {
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let (preprocessing, alignment) = makeInputs(fixture)
        let automatic = try ParallaxSubpixelReconstructor.reconstruct(
            preprocessing: preprocessing, alignment: alignment
        )
        try require(abs(automatic.upsampleFactor - fixture.auto.factor) < 1e-12,
                    "automatic factor differs")
        try require(abs(automatic.brightFieldUpsampleLimit - fixture.bfLimit) < 2e-7,
                    "BF sampling limit differs")
        try require(abs(automatic.darkFieldUpsampleLimit - fixture.dfLimit) < 2e-12,
                    "DF sampling limit differs")
        try require(automatic.paddedHeight == fixture.auto.shape[0]
                    && automatic.paddedWidth == fixture.auto.shape[1],
                    "automatic padded shape differs")
        let autoError = maximumError(automatic.paddedBF, fixture.auto.padded)
        let autoCropError = maximumError(automatic.croppedBF.pixels, fixture.auto.cropped)
        try require(autoError < 3e-6, "automatic KDE differs: \(autoError)")
        try require(autoCropError < 3e-6, "automatic crop differs: \(autoCropError)")
        print("PASS: auto BF/DF factor and bilinear KDE max error \(autoError)")

        var options = ParallaxSubpixelOptions()
        options.upsampleFactor = fixture.filtered.factor
        options.lowpassFilter = true
        let filtered = try ParallaxSubpixelReconstructor.reconstruct(
            preprocessing: preprocessing, alignment: alignment, options: options
        )
        let filterError = maximumError(filtered.paddedBF, fixture.filtered.padded)
        let filterCropError = maximumError(filtered.croppedBF.pixels, fixture.filtered.cropped)
        try require(filterError < 6e-6, "sinc-filtered KDE differs: \(filterError)")
        try require(filterCropError < 6e-6, "filtered crop differs: \(filterCropError)")
        try require(filtered.croppedBF.height == fixture.filtered.cropShape[0]
                    && filtered.croppedBF.width == fixture.filtered.cropShape[1],
                    "filtered crop shape differs")
        print("PASS: exact-shape sinc low-pass and py4DSTEM crop max error \(filterError)")

        var lanczosOptions = ParallaxSubpixelOptions()
        lanczosOptions.upsampleFactor = fixture.lanczos.factor
        lanczosOptions.lanczosOrder = 2
        let lanczos = try ParallaxSubpixelReconstructor.reconstruct(
            preprocessing: preprocessing, alignment: alignment,
            options: lanczosOptions
        )
        let lanczosError = maximumError(lanczos.paddedBF, fixture.lanczos.padded)
        try require(lanczosError < 6e-6, "Lanczos KDE differs: \(lanczosError)")
        print("PASS: source-locked order-2 Lanczos KDE max error \(lanczosError)")

        for (expected, checkerboard) in [
            (fixture.position, false), (fixture.checkerboard, true),
        ] {
            var positionOptions = ParallaxSubpixelOptions()
            positionOptions.upsampleFactor = expected.factor
            positionOptions.positionCorrectionIterations = 2
            positionOptions.positionCorrectionCheckerboard = checkerboard
            let actual = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: alignment,
                options: positionOptions
            )
            let paddedError = maximumError(actual.paddedBF, expected.padded)
            let rowError = maximumError(actual.probeShiftRows, expected.probeRows!)
            let columnError = maximumError(
                actual.probeShiftColumns, expected.probeColumns!
            )
            let scoreError = maximumError(
                actual.positionCorrectionScores, expected.scores!
            )
            try require(paddedError < 8e-6,
                        "position-corrected KDE differs: \(paddedError)")
            try require(rowError < 3e-5 && columnError < 3e-5,
                        "position shift fields differ: \(rowError), \(columnError)")
            try require(scoreError < 3e-6,
                        "position score history differs: \(scoreError)")
            print("PASS: \(checkerboard ? "checkerboard" : "gradient") position correction")
        }

        var invalid = options
        invalid.upsampleFactor = 0.5
        do {
            _ = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: alignment, options: invalid
            )
            try require(false, "factor below one was accepted")
        } catch ParallaxSubpixelReconstructor.ReconstructionError.invalidOptions {}
        invalid = options
        invalid.lanczosOrder = 0
        do {
            _ = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: alignment, options: invalid
            )
            try require(false, "zero Lanczos order was accepted")
        } catch ParallaxSubpixelReconstructor.ReconstructionError.invalidOptions {}
        var limited = options
        limited.maxWorkingBytes = 1
        do {
            _ = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: alignment, options: limited
            )
            try require(false, "memory ceiling was ignored")
        } catch ParallaxSubpixelReconstructor.ReconstructionError.memoryLimit {}
        let cancelled = AnalysisCancellationToken()
        cancelled.cancel()
        do {
            _ = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: alignment,
                cancellation: cancelled
            )
            try require(false, "cancellation was ignored")
        } catch ParallaxSubpixelReconstructor.ReconstructionError.cancelled {}
        let midIteration = AnalysisCancellationToken()
        var iterative = ParallaxSubpixelOptions()
        iterative.positionCorrectionIterations = 3
        do {
            _ = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: alignment,
                options: iterative, cancellation: midIteration
            ) { fraction in
                if fraction >= 0.2 { midIteration.cancel() }
            }
            try require(false, "mid-iteration cancellation was ignored")
        } catch ParallaxSubpixelReconstructor.ReconstructionError.cancelled {}
        let (_, incomplete) = makeInputs(fixture, complete: false)
        do {
            _ = try ParallaxSubpixelReconstructor.reconstruct(
                preprocessing: preprocessing, alignment: incomplete
            )
            try require(false, "incomplete alignment was accepted")
        } catch ParallaxSubpixelReconstructor.ReconstructionError.invalidInput {}
        print("PASS: prerequisites, option validation, memory bound, and cancellation")
        print("parallax-subpixel-test: all passed")
    }
}
