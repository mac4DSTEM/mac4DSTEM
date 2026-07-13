import Foundation

func milliseconds(_ body: () throws -> Double) rethrows -> (Double, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let checksum = try body()
    let end = DispatchTime.now().uptimeNanoseconds
    return (Double(end - start) / 1_000_000, checksum)
}

func fftBaseline(width: Int, height: Int, repetitions: Int) -> (Double, Double) {
    guard let fft = FFT2D(nx: width, ny: height) else { fatalError("FFT setup failed") }
    var real = (0..<(width * height)).map { sin(Float($0) * 0.017) }
    var imaginary = [Float](repeating: 0, count: real.count)
    return milliseconds {
        for _ in 0..<repetitions {
            fft.transform(re: &real, im: &imaginary, forward: true)
            fft.transform(re: &real, im: &imaginary, forward: false)
        }
        return Double(real.prefix(32).reduce(0, +))
    }
}

func ptychographyBaseline() throws -> (Double, Double) {
    let scanHeight = 8, scanWidth = 8
    let detectorHeight = 32, detectorWidth = 32
    let objectHeight = 64, objectWidth = 64
    let probeCount = detectorHeight * detectorWidth
    let positions = (0..<(scanHeight * scanWidth)).map { index in
        PtychographyPosition(
            row: Float(12 + (index / scanWidth) * 5),
            column: Float(12 + (index % scanWidth) * 5)
        )
    }
    var probe = [Float](repeating: 0, count: probeCount)
    for row in 0..<detectorHeight {
        for column in 0..<detectorWidth {
            let dr = Float(row - detectorHeight / 2)
            let dc = Float(column - detectorWidth / 2)
            probe[row * detectorWidth + column] = exp(-(dr * dr + dc * dc) / 64)
        }
    }
    let input = SingleslicePtychographyInput(
        scanHeight: scanHeight, scanWidth: scanWidth,
        detectorHeight: detectorHeight, detectorWidth: detectorWidth,
        amplitudes: [Float](repeating: 1, count: scanHeight * scanWidth * probeCount),
        positions: positions,
        objectSamplingRowAngstrom: 0.5, objectSamplingColumnAngstrom: 0.5,
        initialObject: PtychographyComplexArray(
            width: objectWidth, height: objectHeight,
            real: [Float](repeating: 1, count: objectWidth * objectHeight),
            imaginary: [Float](repeating: 0, count: objectWidth * objectHeight)
        ),
        initialProbe: PtychographyComplexArray(
            width: detectorWidth, height: detectorHeight, real: probe,
            imaginary: [Float](repeating: 0, count: probeCount)
        )
    )
    var options = SingleslicePtychographyOptions()
    options.iterations = 5
    options.normalizationMinimum = 0.1
    return try milliseconds {
        let result = try SingleslicePtychography.reconstruct(input: input, options: options)
        return Double(result.errorHistory.reduce(0, +))
    }
}

@main
struct Baseline {
    static func main() throws {
        // Warm Accelerate and allocator paths before recording.
        _ = fftBaseline(width: 64, height: 64, repetitions: 1)
        let radix2 = fftBaseline(width: 256, height: 256, repetitions: 20)
        let exact = fftBaseline(width: 96, height: 80, repetitions: 5)
        let ptychography = try ptychographyBaseline()
        let report: [String: Any] = [
            "schema": 1,
            "machine": Host.current().localizedName ?? "unknown",
            "processor_count": ProcessInfo.processInfo.processorCount,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "fft_256x256_20_roundtrips_ms": radix2.0,
            "fft_96x80_5_roundtrips_ms": exact.0,
            "ptychography_8x8x32x32_5_iterations_ms": ptychography.0,
            "checksums": [radix2.1, exact.1, ptychography.1],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
