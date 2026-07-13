import Foundation

struct Fixture: Decodable {
    let shape: [Int]
    let cube: [Float]
    let threshold: Float
    let edgeBlend: Float
    let paddingY: Int
    let paddingX: Int
    let qSampling: Double
    let energyEV: Double
    let wavelength: Double
    let detectorMask: [Bool]
    let indices: [[Int]]
    let kVectors: [Float]
    let probeAnglesMrad: [Float]
    let edgeWindow: [Float]
    let stackShape: [Int]
    let normalizedStack: [Float]
    let unshiftedStack: [Float]
    let incoherentBF: [Float]
    let initialError: Float
}

actor FixtureSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let cube: [Float]
    private(set) var largestTileRows = 0

    init(descriptor: DatasetDescriptor, cube: [Float]) {
        self.descriptor = descriptor
        self.cube = cube
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }

    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float] {
        let count = descriptor.qy * descriptor.qx
        let start = (ry * descriptor.rx + rx) * count
        return Array(cube[start..<(start + count)])
    }

    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float] {
        try tile(descriptor, range: ry..<(ry + 1)).pixels
    }

    func readScanTile(
        _ descriptor: DatasetDescriptor, yRange: Range<Int>
    ) throws -> FourDScanTile {
        try tile(descriptor, range: yRange)
    }

    private func tile(
        _ descriptor: DatasetDescriptor, range: Range<Int>
    ) throws -> FourDScanTile {
        largestTileRows = max(largestTileRows, range.count)
        let rowCount = descriptor.rx * descriptor.qy * descriptor.qx
        let start = range.lowerBound * rowCount
        let end = range.upperBound * rowCount
        return FourDScanTile(
            yRange: range, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            pixels: Array(cube[start..<end])
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(
            domain: "parallax-preprocessing-test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

func maximumError(_ actual: [Float], _ expected: [Float]) -> Float {
    guard actual.count == expected.count else { return .infinity }
    return zip(actual, expected).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

@main
struct Harness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "arguments", code: 1)
        }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let descriptor = DatasetDescriptor(
            filePath: "synthetic.h5", datasetPath: "/cube", shape: fixture.shape,
            dtypeDescription: "float32", chunkShape: nil
        )
        let source = FixtureSource(descriptor: descriptor, cube: fixture.cube)

        var appCalibration = Calibration()
        appCalibration.originProvenance = .manual
        appCalibration.rotationRad = 0.3
        appCalibration.transposeQR = true
        appCalibration.rPixelSize = 0.2
        appCalibration.rPixelUnits = "nm"
        appCalibration.qPixelSize = fixture.qSampling * 10
        appCalibration.qPixelUnits = "1/nm"
        let physical = try ParallaxPhysicalCalibration.resolve(
            calibration: appCalibration, apertureCenterX: 3.65,
            apertureCenterY: 2.35,
            acceleratingVoltageKV: fixture.energyEV / 1_000
        )
        try require(abs(physical.scanSamplingAngstrom - 2) < 1e-12,
                    "nm to Å scan conversion differs")
        try require(abs(physical.reciprocalSamplingInvAngstrom - fixture.qSampling) < 1e-12,
                    "nm⁻¹ to Å⁻¹ reciprocal conversion differs")
        try require(abs(physical.wavelengthAngstrom - fixture.wavelength) < 1e-12,
                    "electron wavelength differs")
        try require(abs(physical.originQX - 2.35) < 1e-6
                    && abs(physical.originQY - 3.65) < 1e-6,
                    "app to py4DSTEM origin axes differ")
        print("PASS: physical calibration and electron wavelength")

        var options = ParallaxPreprocessOptions()
        options.thresholdIntensity = fixture.threshold
        options.edgeBlend = fixture.edgeBlend
        options.paddingY = fixture.paddingY
        options.paddingX = fixture.paddingX
        options.tileRows = 1
        options.maxStackBytes = 64 * 1_024 * 1_024
        let result = try await ParallaxPreprocessor.run(
            source: source, descriptor: descriptor, calibration: physical,
            options: options
        )

        try require(result.detectorMask == fixture.detectorMask,
                    "bright-field mask differs")
        try require(result.detectorIndices.map { [$0.qx, $0.qy] } == fixture.indices,
                    "np.argwhere detector index order differs")
        try require(result.stackHeight == fixture.stackShape[1]
                    && result.stackWidth == fixture.stackShape[2],
                    "stack shape differs")
        let actualK = result.reciprocalVectors.flatMap { [$0.qx, $0.qy] }
        let actualAngles = result.probeAnglesMrad.flatMap { [$0.qx, $0.qy] }
        try require(maximumError(actualK, fixture.kVectors) < 2e-7,
                    "reciprocal vectors differ")
        try require(maximumError(actualAngles, fixture.probeAnglesMrad) < 2e-7,
                    "probe angles differ")
        try require(maximumError(result.edgeWindow, fixture.edgeWindow) < 4e-7,
                    "sine-squared edge window differs")
        let stackError = maximumError(result.normalizedStack, fixture.normalizedStack)
        try require(stackError < 4e-6, "normalized BF stack differs: \(stackError)")
        let unshiftedError = maximumError(result.unshiftedStack, fixture.unshiftedStack)
        try require(unshiftedError < 4e-6,
                    "unwindowed normalized BF stack differs: \(unshiftedError)")
        let reconError = maximumError(result.incoherentBF, fixture.incoherentBF)
        try require(reconError < 4e-6, "incoherent BF differs: \(reconError)")
        try require(abs(result.initialError - fixture.initialError) < 4e-6,
                    "initial mismatch differs")
        let largestTileRows = await source.largestTileRows
        try require(largestTileRows == 1,
                    "preprocessor exceeded forced one-row tile bound")
        print("PASS: BF mask/index/k-vector/angle parity")
        print("PASS: edge window and order-0 normalized stack max error \(stackError)")
        print("PASS: unwindowed normalized stack max error \(unshiftedError)")
        print("PASS: incoherent BF initialization max error \(reconError)")

        var angularCalibration = appCalibration
        angularCalibration.qPixelSize = fixture.qSampling * fixture.wavelength * 1_000
        angularCalibration.qPixelUnits = "mrad"
        let angular = try ParallaxPhysicalCalibration.resolve(
            calibration: angularCalibration, apertureCenterX: 3.65,
            apertureCenterY: 2.35,
            acceleratingVoltageKV: fixture.energyEV / 1_000
        )
        try require(abs(angular.reciprocalSamplingInvAngstrom - fixture.qSampling) < 1e-12,
                    "mrad reciprocal conversion differs")
        print("PASS: mrad reciprocal calibration conversion")

        var missingRotation = appCalibration
        missingRotation.rotationRad = nil
        do {
            _ = try ParallaxPhysicalCalibration.resolve(
                calibration: missingRotation, apertureCenterX: 3.65,
                apertureCenterY: 2.35,
                acceleratingVoltageKV: 200
            )
            try require(false, "missing rotation was accepted")
        } catch ParallaxPreprocessor.PreprocessError.missingCalibration {}

        let cancelled = AnalysisCancellationToken()
        cancelled.cancel()
        do {
            _ = try await ParallaxPreprocessor.run(
                source: source, descriptor: descriptor, calibration: physical,
                options: options, cancellation: cancelled
            )
            try require(false, "cancelled preprocessing returned a result")
        } catch ParallaxPreprocessor.PreprocessError.cancelled {}

        let midPassCancellation = AnalysisCancellationToken()
        do {
            _ = try await ParallaxPreprocessor.run(
                source: source, descriptor: descriptor, calibration: physical,
                options: options, cancellation: midPassCancellation
            ) { fraction in
                if fraction >= 0.2 { midPassCancellation.cancel() }
            }
            try require(false, "mid-pass cancellation returned a result")
        } catch ParallaxPreprocessor.PreprocessError.cancelled {}

        var tinyLimit = options
        tinyLimit.maxStackBytes = 1
        do {
            _ = try await ParallaxPreprocessor.run(
                source: source, descriptor: descriptor, calibration: physical,
                options: tinyLimit
            )
            try require(false, "stack memory ceiling was ignored")
        } catch ParallaxPreprocessor.PreprocessError.stackTooLarge {}
        print("PASS: missing calibration, memory ceiling, and cancellation reject publication")

        print("parallax-preprocessing-test: all passed")
    }
}
