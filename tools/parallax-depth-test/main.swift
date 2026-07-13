import Foundation

struct Expected: Decodable {
    let full: Bool
    let limit: Double?
    let power: Double
    let stack: [Float]
    let cropped: [Float]
}

struct Fixture: Decodable {
    let shape: [Int]
    let scanShape: [Int]
    let sampling: Double
    let wavelength: Double
    let depths: [Double]
    let anglesMrad: [Float]
    let terms: [Int]
    let coefficients: [Double]
    let shiftedStack: [Float]
    let full: Expected
    let fallback: Expected
    let filtered: Expected
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "parallax-depth-test", code: 1,
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
        let angles = stride(from: 0, to: fixture.anglesMrad.count, by: 2).map {
            ParallaxVector(qx: fixture.anglesMrad[$0], qy: fixture.anglesMrad[$0 + 1])
        }
        let terms = stride(from: 0, to: fixture.terms.count, by: 3).map {
            ParallaxAberrationTerm(
                radialOrder: fixture.terms[$0], angularOrder: fixture.terms[$0 + 1],
                component: fixture.terms[$0 + 2]
            )
        }
        let count = fixture.shape[0] * fixture.shape[1]
        let calibration = ParallaxPhysicalCalibration(
            scanSamplingAngstrom: fixture.sampling,
            reciprocalSamplingInvAngstrom: 0.1,
            energyEV: 200_000, wavelengthAngstrom: fixture.wavelength,
            originQX: 0, originQY: 0, rotationRad: 0, transpose: false
        )
        let preprocessing = ParallaxPreprocessResult(
            scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1],
            detectorHeight: 3, detectorWidth: 3,
            stackHeight: fixture.shape[0], stackWidth: fixture.shape[1],
            calibration: calibration, thresholdIntensity: 0.8,
            detectorMask: [true, true, true],
            detectorIndices: (0..<3).map { ParallaxDetectorIndex(qx: 0, qy: $0) },
            reciprocalVectors: angles.map {
                ParallaxVector(qx: $0.qx / Float(fixture.wavelength * 1_000),
                               qy: $0.qy / Float(fixture.wavelength * 1_000))
            },
            probeAnglesMrad: angles,
            edgeWindow: [Float](repeating: 1, count: fixture.scanShape[0] * fixture.scanShape[1]),
            normalizedStack: fixture.shiftedStack, unshiftedStack: fixture.shiftedStack,
            incoherentBF: [Float](repeating: 1, count: count), initialError: 0
        )
        let alignment = ParallaxAlignmentResult(
            alignmentBin: 1, alignmentSchedule: [1], completedBins: [1],
            upsampleFactor: 8, groups: [], groupShifts: [],
            totalShifts: [ParallaxScanShift](
                repeating: ParallaxScanShift(row: 0, column: 0), count: 3
            ),
            shiftedStack: fixture.shiftedStack, shiftedMasks: [],
            reconstructionMask: [], alignedBF: [Float](repeating: 1, count: count),
            errorHistory: [0], scanHeight: fixture.scanShape[0],
            scanWidth: fixture.scanShape[1], stackHeight: fixture.shape[0],
            stackWidth: fixture.shape[1]
        )
        let physical = [ParallaxPhysicalShift](
            repeating: ParallaxPhysicalShift(rowAngstrom: 0, columnAngstrom: 0),
            count: 3
        )
        let low = ParallaxAberrationFitResult(
            measuredShifts: physical, fittedShifts: physical, rotationRad: 0,
            c1Angstrom: fixture.coefficients[0], c12aAngstrom: 0,
            c12bAngstrom: 0, rmsResidualAngstrom: 0,
            forceTranspose: false, forcedRotationAngleDegrees: nil
        )
        let fit = ParallaxHigherOrderAberrationFitResult(
            lowOrder: low, terms: terms, coefficientsAngstrom: fixture.coefficients,
            fittedShifts: physical, rmsResidualAngstrom: 0, fitMethod: .global
        )

        for expected in [fixture.full, fixture.fallback, fixture.filtered] {
            var options = ParallaxDepthOptions()
            options.depthsAngstrom = fixture.depths
            options.useFullFit = expected.full
            options.informationLimitInvAngstrom = expected.limit
            options.informationPower = expected.power
            let actual = try ParallaxDepthSectioner.section(
                preprocessing: preprocessing, alignment: alignment,
                fit: fit, options: options
            )
            let stackError = maximumError(actual.paddedStack, expected.stack)
            var cropped = [Float]()
            for index in fixture.depths.indices {
                cropped += actual.croppedPlane(at: index)!.pixels
            }
            let cropError = maximumError(cropped, expected.cropped)
            try require(stackError < 7e-6 && cropError < 7e-6,
                        "depth stack differs: \(stackError), \(cropError)")
            let limitLabel = expected.limit.map { String($0) } ?? "off"
            print("PASS: depth full=\(expected.full) limit=\(limitLabel)")
        }
        try require(ParallaxDepthResult(
            depthsAngstrom: [], paddedStack: [], paddedHeight: 1, paddedWidth: 1,
            scanHeight: 1, scanWidth: 1, samplingAngstrom: 1,
            usedFullFit: true, informationLimitInvAngstrom: nil,
            informationPower: 1
        ).croppedPlane(at: 0) == nil, "invalid plane index was accepted")

        var limited = ParallaxDepthOptions()
        limited.depthsAngstrom = fixture.depths
        limited.maxWorkingBytes = 1
        do {
            _ = try ParallaxDepthSectioner.section(
                preprocessing: preprocessing, alignment: alignment,
                fit: fit, options: limited
            )
            try require(false, "depth memory ceiling was ignored")
        } catch ParallaxDepthSectioner.DepthError.memoryLimit {}
        let cancellation = AnalysisCancellationToken()
        do {
            var options = ParallaxDepthOptions()
            options.depthsAngstrom = fixture.depths
            _ = try ParallaxDepthSectioner.section(
                preprocessing: preprocessing, alignment: alignment,
                fit: fit, options: options, cancellation: cancellation
            ) { fraction in
                if fraction > 0 { cancellation.cancel() }
            }
            try require(false, "between-plane cancellation was ignored")
        } catch ParallaxDepthSectioner.DepthError.cancelled {}
        print("PASS: crop/index, memory rejection, and between-plane cancellation")
        print("parallax-depth-test: all passed")
    }
}
