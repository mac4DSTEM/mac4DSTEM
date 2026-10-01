import Foundation

struct CaseFixture: Decodable {
    let forceTranspose: Bool
    let forcedDegrees: Double?
    let measured: [Double]
    let fitted: [Double]
    let rotationRad: Double
    let c1: Double
    let c12a: Double
    let c12b: Double
    let rms: Double
}

struct HigherFixture: Decodable {
    let method: String
    let terms: [[Int]]
    let gradients: [Double]
    let coefficients: [Double]
    let fitted: [Double]
    let rms: Double
}

struct CorrectionCaseFixture: Decodable {
    let useFull: Bool
    let lowpass: Double?
    let highpass: Double?
    let order: Int
    let chiEven: [Float]
    let chiOdd: [Float]
    let transferReal: [Float]
    let transferImaginary: [Float]
    let padded: [Float]
    let cropped: [Float]
}

struct CorrectionFixture: Decodable {
    let shape: [Int]
    let scanShape: [Int]
    let wavelength: Double
    let alignedBF: [Float]
    let cases: [CorrectionCaseFixture]
}

struct LinearFieldFixture: Decodable {
    let shiftsPixels: [Float]
    let originOffsetMrad: Double
    let py4dstemConventionComa: [Double]
    let consistentComplete: [Double]
}

struct Fixture: Decodable {
    let linearField: LinearFieldFixture
    let anglesMrad: [Float]
    let shiftsPixels: [Float]
    let scanSamplingAngstrom: Double
    let cases: [CaseFixture]
    let higher: [HigherFixture]
    let correction: CorrectionFixture
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(
            domain: "parallax-aberration-test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

func maximumError(_ actual: [Double], _ expected: [Double]) -> Double {
    guard actual.count == expected.count else { return .infinity }
    return zip(actual, expected).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

func preprocessing(_ fixture: Fixture, singular: Bool = false) -> ParallaxPreprocessResult {
    let angles = stride(from: 0, to: fixture.anglesMrad.count, by: 2).map {
        singular
            ? ParallaxVector(qx: fixture.anglesMrad[$0], qy: 0)
            : ParallaxVector(qx: fixture.anglesMrad[$0],
                             qy: fixture.anglesMrad[$0 + 1])
    }
    let count = angles.count
    return ParallaxPreprocessResult(
        scanHeight: 1, scanWidth: 1,
        detectorHeight: 1, detectorWidth: count,
        stackHeight: 1, stackWidth: 1,
        calibration: ParallaxPhysicalCalibration(
            scanSamplingAngstrom: fixture.scanSamplingAngstrom,
            reciprocalSamplingInvAngstrom: 0.01,
            energyEV: 200_000, wavelengthAngstrom: 0.025079,
            originQX: 0, originQY: 0, rotationRad: 0, transpose: false
        ),
        thresholdIntensity: 0.8,
        detectorMask: [Bool](repeating: true, count: count),
        detectorIndices: (0..<count).map { ParallaxDetectorIndex(qx: 0, qy: $0) },
        reciprocalVectors: angles.map {
            ParallaxVector(qx: $0.qx / 25.079, qy: $0.qy / 25.079)
        },
        probeAnglesMrad: angles,
        edgeWindow: [1], normalizedStack: [Float](repeating: 1, count: count),
        unshiftedStack: [Float](repeating: 1, count: count),
        incoherentBF: [1], initialError: 0
    )
}

func alignment(_ fixture: Fixture, complete: Bool = true) -> ParallaxAlignmentResult {
    let shifts = stride(from: 0, to: fixture.shiftsPixels.count, by: 2).map {
        ParallaxScanShift(row: fixture.shiftsPixels[$0],
                          column: fixture.shiftsPixels[$0 + 1])
    }
    return ParallaxAlignmentResult(
        alignmentBin: complete ? 1 : 4,
        alignmentSchedule: [4, 2, 1],
        completedBins: complete ? [4, 2, 1] : [4],
        upsampleFactor: 8, groups: [], groupShifts: [],
        totalShifts: shifts,
        shiftedStack: [], shiftedMasks: [], reconstructionMask: [],
        alignedBF: [], errorHistory: [0],
        scanHeight: 1, scanWidth: 1, stackHeight: 1, stackWidth: 1
    )
}

@main
struct Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "arguments", code: 1)
        }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let prep = preprocessing(fixture)
        let aligned = alignment(fixture)
        for expected in fixture.cases {
            var options = ParallaxLowOrderAberrationOptions()
            options.forceTranspose = expected.forceTranspose
            options.forceRotationAngleDegrees = expected.forcedDegrees
            let actual = try ParallaxAberrationFitter.fitLowOrder(
                preprocessing: prep, alignment: aligned, options: options
            )
            let measured = actual.measuredShifts.flatMap {
                [$0.rowAngstrom, $0.columnAngstrom]
            }
            let fitted = actual.fittedShifts.flatMap {
                [$0.rowAngstrom, $0.columnAngstrom]
            }
            try require(maximumError(measured, expected.measured) < 2e-6,
                        "measured Å shifts differ")
            try require(maximumError(fitted, expected.fitted) < 2e-6,
                        "fitted Å shifts differ")
            try require(abs(actual.rotationRad - expected.rotationRad) < 2e-6,
                        "rotation differs")
            try require(abs(actual.c1Angstrom - expected.c1) < 2e-5,
                        "C1 differs")
            try require(abs(actual.c12aAngstrom - expected.c12a) < 2e-5,
                        "C12a differs")
            try require(abs(actual.c12bAngstrom - expected.c12b) < 2e-5,
                        "C12b differs")
            try require(abs(actual.rmsResidualAngstrom - expected.rms) < 2e-6,
                        "fit RMS differs")
            let forcedDescription = expected.forcedDegrees.map { String($0) } ?? "auto"
            print("PASS: transpose=\(expected.forceTranspose) forced=\(forcedDescription)")
        }

        // Lane R4 (2026-10-01): the production path hands the fitter an EXACTLY linear field (py4DSTEM's reconstruct projects its shifts onto
        // k with no intercept, parallax.py:1380-1384; ours does the same, fitDefaultShiftBasis). On such a field coma and trefoil are not
        // observable, so a consistent basis returns 0 and a zero residual. py4DSTEM's own fit reports 619 / 599 A on the graphene cube only
        // because its basis origin (ROI//2) differs from its angle origin (mean of the bright-field pixels) by 0.325 px; the reference's
        // `py4dstemConventionComa` is that mixed-origin result on this fixture (hundreds of A, proportional to the offset). The pin: ours is 0.
        let linear = fixture.linearField
        let linearFit = try ParallaxAberrationFitter.fitHigherOrder(
            preprocessing: prep,
            alignment: alignment(Fixture(
                linearField: linear, anglesMrad: fixture.anglesMrad, shiftsPixels: linear.shiftsPixels,
                scanSamplingAngstrom: fixture.scanSamplingAngstrom, cases: [], higher: [], correction: fixture.correction))
        )
        try require(linear.py4dstemConventionComa.map(abs).max()! > 20,
                    "the py4DSTEM-convention reference stopped producing a coma (the pin's reason is gone)")
        try require(linearFit.coefficientsAngstrom[3...].map(abs).max()! < 0.5,
                    "an exactly linear field produced a coma/trefoil in the fit")
        try require(maximumError(Array(linearFit.coefficientsAngstrom[0..<3]),
                                 Array(linear.consistentComplete[0..<3])) < 0.05,
                    "low-order terms differ on the linear field")
        try require(linearFit.rmsResidualAngstrom < 1e-3, "an exactly linear field left a residual")
        print("PASS: exactly linear field -> coma/trefoil 0, residual 0 (py4DSTEM-convention coma \(linear.py4dstemConventionComa.map { Int($0) }) A at \(linear.originOffsetMrad) mrad origin offset)")

        for expected in fixture.higher {
            var options = ParallaxHigherOrderAberrationOptions()
            options.fitMethod = ParallaxAberrationFitMethod(rawValue: expected.method)!
            let actual = try ParallaxAberrationFitter.fitHigherOrder(
                preprocessing: prep, alignment: aligned, options: options
            )
            let terms = actual.terms.map {
                [$0.radialOrder, $0.angularOrder, $0.component]
            }
            try require(terms == expected.terms, "higher-order term ordering differs")
            let gradients = try ParallaxAberrationFitter.gradientSamples(
                probeAnglesMrad: prep.probeAnglesMrad,
                rotationRad: actual.lowOrder.rotationRad,
                terms: actual.terms
            ).flatMap { [$0.0, $0.1] }
            try require(maximumError(gradients, expected.gradients) < 2e-9,
                        "gradient basis differs")
            try require(maximumError(actual.coefficientsAngstrom,
                                     expected.coefficients) < 3e-3,
                        "higher-order coefficients differ for \(expected.method)")
            let fitted = actual.fittedShifts.flatMap {
                [$0.rowAngstrom, $0.columnAngstrom]
            }
            try require(maximumError(fitted, expected.fitted) < 2e-6,
                        "higher-order fitted shifts differ")
            try require(abs(actual.rmsResidualAngstrom - expected.rms) < 2e-6,
                        "higher-order RMS differs")
            print("PASS: higher-order \(expected.method) terms/gradients/coefficients")
        }

        let correctionPrep = ParallaxPreprocessResult(
            scanHeight: fixture.correction.scanShape[0],
            scanWidth: fixture.correction.scanShape[1],
            detectorHeight: prep.detectorHeight, detectorWidth: prep.detectorWidth,
            stackHeight: fixture.correction.shape[0],
            stackWidth: fixture.correction.shape[1],
            calibration: ParallaxPhysicalCalibration(
                scanSamplingAngstrom: fixture.scanSamplingAngstrom,
                reciprocalSamplingInvAngstrom: 0.01,
                energyEV: 200_000,
                wavelengthAngstrom: fixture.correction.wavelength,
                originQX: 0, originQY: 0, rotationRad: 0, transpose: false
            ),
            thresholdIntensity: prep.thresholdIntensity,
            detectorMask: prep.detectorMask,
            detectorIndices: prep.detectorIndices,
            reciprocalVectors: prep.reciprocalVectors,
            probeAnglesMrad: prep.probeAnglesMrad,
            edgeWindow: [Float](
                repeating: 1,
                count: fixture.correction.scanShape[0] * fixture.correction.scanShape[1]
            ),
            normalizedStack: [], unshiftedStack: [],
            incoherentBF: fixture.correction.alignedBF,
            initialError: 0
        )
        let correctionAlignment = ParallaxAlignmentResult(
            alignmentBin: 1, alignmentSchedule: [4, 2, 1],
            completedBins: [4, 2, 1], upsampleFactor: 8,
            groups: [], groupShifts: [], totalShifts: aligned.totalShifts,
            shiftedStack: [], shiftedMasks: [], reconstructionMask: [],
            alignedBF: fixture.correction.alignedBF, errorHistory: [0],
            scanHeight: fixture.correction.scanShape[0],
            scanWidth: fixture.correction.scanShape[1],
            stackHeight: fixture.correction.shape[0],
            stackWidth: fixture.correction.shape[1]
        )
        let correctionFit = try ParallaxAberrationFitter.fitHigherOrder(
            preprocessing: correctionPrep, alignment: correctionAlignment
        )
        for expected in fixture.correction.cases {
            var options = ParallaxAberrationCorrectionOptions()
            options.useFullFit = expected.useFull
            options.qLowpassInvAngstrom = expected.lowpass
            options.qHighpassInvAngstrom = expected.highpass
            options.butterworthOrder = expected.order
            let actual = try ParallaxAberrationCorrector.correct(
                preprocessing: correctionPrep,
                alignment: correctionAlignment,
                fit: correctionFit, options: options
            )
            try require(maximumError(actual.chiEven.map(Double.init),
                                     expected.chiEven.map(Double.init)) < 2e-4,
                        "even CTF phase differs")
            try require(maximumError(actual.chiOdd.map(Double.init),
                                     expected.chiOdd.map(Double.init)) < 2e-4,
                        "odd CTF phase differs")
            try require(maximumError(actual.transferReal.map(Double.init),
                                     expected.transferReal.map(Double.init)) < 3e-4,
                        "CTF real transfer differs")
            try require(maximumError(actual.transferImaginary.map(Double.init),
                                     expected.transferImaginary.map(Double.init)) < 3e-4,
                        "CTF imaginary transfer differs")
            try require(maximumError(actual.paddedPhase.map(Double.init),
                                     expected.padded.map(Double.init)) < 4e-4,
                        "corrected padded phase differs")
            try require(maximumError(actual.correctedPhase.pixels.map(Double.init),
                                     expected.cropped.map(Double.init)) < 4e-4,
                        "corrected cropped phase differs")
            try require(actual.transferReal[0] == 0
                            && actual.transferImaginary[0] == 0,
                        "CTF DC was not removed")
            print("PASS: correction full=\(expected.useFull) low/high filters")
        }

        do {
            _ = try ParallaxAberrationFitter.fitLowOrder(
                preprocessing: prep, alignment: alignment(fixture, complete: false)
            )
            try require(false, "incomplete alignment accepted")
        } catch ParallaxAberrationFitter.FitError.alignmentIncomplete {}
        do {
            _ = try ParallaxAberrationFitter.fitLowOrder(
                preprocessing: preprocessing(fixture, singular: true),
                alignment: aligned
            )
            try require(false, "singular angle geometry accepted")
        } catch ParallaxAberrationFitter.FitError.singularAngleGeometry {}
        var invalidFilter = ParallaxAberrationCorrectionOptions()
        invalidFilter.qLowpassInvAngstrom = -1
        do {
            _ = try ParallaxAberrationCorrector.correct(
                preprocessing: correctionPrep, alignment: correctionAlignment,
                fit: correctionFit, options: invalidFilter
            )
            try require(false, "negative correction cutoff accepted")
        } catch ParallaxAberrationCorrector.CorrectionError.invalidInput {}
        let correctionCancellation = AnalysisCancellationToken()
        correctionCancellation.cancel()
        do {
            _ = try ParallaxAberrationCorrector.correct(
                preprocessing: correctionPrep, alignment: correctionAlignment,
                fit: correctionFit, cancellation: correctionCancellation
            )
            try require(false, "cancelled correction published")
        } catch ParallaxAberrationCorrector.CorrectionError.cancelled {}
        print("PASS: incomplete and singular inputs reject publication")
        print("parallax-aberration-test: all passed")
    }
}
