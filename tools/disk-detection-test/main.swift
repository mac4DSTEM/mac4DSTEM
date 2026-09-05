import Foundation

struct Fixture: Decodable {
    let dimensions: [Int]
    let radius: Float
    let width: Float
    let trenchRadii: [Float]
    let pattern: [Float]
    let kernel: [Float]
    let flatProbe: [Float]
    let flatCentre: [Float]
    let flatKernel: [Float]
    let fracProbe: [Float]
    let fracCentre: [Float]
    let fracKernel: [Float]
    let fracFTImag: [Float]
    let cases: [DetectionCase]
}

struct DetectionCase: Decodable {
    let name: String
    let params: Parameters
    let expected: [ExpectedPeak]
}

struct Parameters: Decodable {
    let corrPower: Float
    let sigmaDP: Float?
    let sigmaCC: Float
    let subpixel: String
    let upsampleFactor: Int
    let minAbsoluteIntensity: Float
    let minRelativeIntensity: Float
    let relativeToPeak: Int
    let minPeakSpacing: Float
    let edgeBoundary: Int
    let maxNumPeaks: Int
}

struct ExpectedPeak: Decodable {
    let qx: Float
    let qy: Float
    let intensity: Float
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: harness expected.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
guard fixture.dimensions.count == 2 else { fail("dimensions must be [Qy,Qx]") }
let qy = fixture.dimensions[0]
let qx = fixture.dimensions[1]
guard fixture.pattern.count == qy * qx, fixture.kernel.count == qy * qx else {
    fail("pattern/kernel size does not match detector")
}
guard fixture.trenchRadii.count == 2 else { fail("trenchRadii must contain two values") }

guard let kernel = ProbeKernel.synthetic(
    radius: fixture.radius,
    width: fixture.width,
    qy: qy,
    qx: qx,
    trenchRadii: (fixture.trenchRadii[0], fixture.trenchRadii[1])
) else { fail("production ProbeKernel.synthetic returned nil") }
guard kernel.px == qx, kernel.py == qy else {
    fail("fixture must avoid padding; production grid is \(kernel.py)x\(kernel.px)")
}

var maximumKernelError: Float = 0
var maximumKernelIndex = 0
for index in kernel.kernel.indices {
    let error = abs(kernel.kernel[index] - fixture.kernel[index])
    if error > maximumKernelError {
        maximumKernelError = error
        maximumKernelIndex = index
    }
}
guard maximumKernelError <= 2e-6 else {
    fail("synthetic kernel max error \(maximumKernelError) at \(maximumKernelIndex)")
}
print("PASS: synthetic_probe_sigmoid_kernel max error \(maximumKernelError)")

// FLAT measured kernel (get_probe_kernel_flat): a bullseye-like probe at an
// integer centre, so the pinned Fourier shift is an exact roll of the
// normalised probe. Pins the normalisation, the shift DIRECTION and the axis
// order at once — a transposed or sign-flipped shift lands the rings elsewhere.
guard fixture.flatProbe.count == qy * qx, fixture.flatKernel.count == qy * qx, fixture.flatCentre.count == 2 else {
    fail("flat fixture size does not match detector")
}
guard let flat = ProbeKernel.flat(
    pattern: DiffractionPattern(qy: qy, qx: qx, pixels: fixture.flatProbe),
    originX: fixture.flatCentre[0], originY: fixture.flatCentre[1], radius: 8
) else { fail("production ProbeKernel.flat returned nil") }
var maximumFlatError: Float = 0
for index in flat.kernel.indices {
    maximumFlatError = max(maximumFlatError, abs(flat.kernel[index] - fixture.flatKernel[index]))
}
guard maximumFlatError <= 2e-6 else { fail("flat kernel max error \(maximumFlatError) against the rolled normalised probe") }
guard abs(flat.kernel.reduce(0, +) - 1) <= 1e-4 else { fail("flat kernel sum \(flat.kernel.reduce(0, +)), expected 1") }
print("PASS: flat_measured_kernel max error \(maximumFlatError)")

// FRACTIONAL centre, asymmetric probe: pins the fftfreq wrapping of the shift
// phase (an unwrapped index survived the integer case) and, through the
// imaginary part of conj(FFT(kernel)), the conjugation the detector relies on
// (dropping it survived every real-space check). Gate B refuter, 2026-09-05.
guard let frac = ProbeKernel.flat(
    pattern: DiffractionPattern(qy: qy, qx: qx, pixels: fixture.fracProbe),
    originX: fixture.fracCentre[0], originY: fixture.fracCentre[1], radius: 3
) else { fail("production ProbeKernel.flat returned nil for the fractional centre") }
var maximumFracError: Float = 0
for index in frac.kernel.indices {
    maximumFracError = max(maximumFracError, abs(frac.kernel[index] - fixture.fracKernel[index]))
}
guard maximumFracError <= 2e-6 else { fail("fractional-centre flat kernel max error \(maximumFracError) against get_shifted_ar") }
var maximumFTError: Float = 0
for index in frac.ftIm.indices {
    maximumFTError = max(maximumFTError, abs(frac.ftIm[index] - fixture.fracFTImag[index]))
}
guard maximumFTError <= 1e-5 else { fail("conj(FFT(kernel)) imaginary part max error \(maximumFTError) — the detector would convolve, not correlate") }
print("PASS: flat_kernel_fractional_centre max error \(maximumFracError), conjugate transform \(maximumFTError)")

guard let detector = DiskDetector(kernel: kernel) else {
    fail("production DiskDetector returned nil")
}

for test in fixture.cases {
    var params = DiskDetectionParams()
    params.corrPower = test.params.corrPower
    params.sigmaDP = test.params.sigmaDP ?? 0
    params.sigmaCC = test.params.sigmaCC
    switch test.params.subpixel {
    case "pixel": params.subpixel = .pixel
    case "poly": params.subpixel = .poly
    case "multicorr": params.subpixel = .multicorr
    default: fail("\(test.name) unsupported subpixel mode \(test.params.subpixel)")
    }
    params.upsampleFactor = test.params.upsampleFactor
    params.minAbsoluteIntensity = test.params.minAbsoluteIntensity
    params.minRelativeIntensity = test.params.minRelativeIntensity
    params.relativeToPeak = test.params.relativeToPeak
    params.minPeakSpacing = test.params.minPeakSpacing
    params.edgeBoundary = test.params.edgeBoundary
    params.maxNumPeaks = test.params.maxNumPeaks

    let validation = params.validationIssues(
        in: DiskDetectionContext(qy: qy, qx: qx, probeRadius: kernel.probeRadius)
    )
    guard !validation.contains(where: { $0.severity == .error }) else {
        fail("\(test.name) configuration failed validation: \(validation)")
    }
    let detected = detector.detectWithDiagnostics(
        pattern: fixture.pattern, params: params
    )
    let actual = detected.peaks
    let actualDescription = actual.map {
        "(x=\($0.x),y=\($0.y),i=\($0.intensity))"
    }.joined(separator: ", ")
    guard actual.count == test.expected.count else {
        fail("\(test.name) peak count \(actual.count), expected \(test.expected.count); "
             + "actual [\(actualDescription)]")
    }

    var maximumIntensityError: Float = 0
    for index in actual.indices {
        let expected = test.expected[index]
        // py4DSTEM qx is the detector row; app coordinates are x=column,y=row.
        let coordinateError = max(
            abs(actual[index].x - expected.qy),
            abs(actual[index].y - expected.qx)
        )
        guard coordinateError <= 2e-4 else {
            fail("\(test.name) peak \(index) coordinate "
                 + "(x=\(actual[index].x),y=\(actual[index].y)), expected "
                 + "(x=\(expected.qy),y=\(expected.qx))")
        }
        maximumIntensityError = max(
            maximumIntensityError,
            abs(actual[index].intensity - expected.intensity)
        )
    }
    guard maximumIntensityError <= 2e-4 else {
        fail("\(test.name) max intensity error \(maximumIntensityError)")
    }
    guard detected.diagnostics.acceptedCount == actual.count,
          detected.diagnostics.localMaximumCount >= actual.count,
          detected.diagnostics.correlationMaximum.isFinite else {
        fail("\(test.name) diagnostics do not describe the accepted peaks")
    }
    print("PASS: \(test.name) peaks \(actual.count), max intensity error \(maximumIntensityError)")
}

var vectorCalibration = Calibration()
vectorCalibration.origin = OriginMaps(
    width: 2, height: 1, measuredX: nil, measuredY: nil,
    fittedX: [10, 20], fittedY: [30, 40]
)
vectorCalibration.ellipseA = 2
vectorCalibration.ellipseB = 1
vectorCalibration.ellipseTheta = 0
let rawVectors = BraggVectors(
    scanWidth: 2, scanHeight: 1,
    peaks: [
        [BraggPeak(x: 14, y: 34, intensity: 2)],
        [BraggPeak(x: 25, y: 46, intensity: 3)]
    ]
)
let correctedVectors = rawVectors.calibrated(
    with: vectorCalibration, referenceOrigin: (x: 15, y: 35)
)
guard correctedVectors.peaks[0][0].x == 19,
      correctedVectors.peaks[0][0].y == 37,
      correctedVectors.peaks[1][0].x == 20,
      correctedVectors.peaks[1][0].y == 38 else {
    fail("per-position origin + ellipse vector calibration differs: \(correctedVectors.peaks)")
}
guard rawVectors.peaks[0][0].x == 14, rawVectors.peaks[0][0].y == 34 else {
    fail("calibrating vectors mutated raw export/overlay coordinates")
}
print("PASS: py4DSTEM ellipse + per-position origin vector calibration")

// Exact native-shape circular correlation on a non-radix-2 detector. A
// circularly shifted copy of the kernel must autocorrelate at that shift with
// intensity sum(kernel²); the former power-of-two padding path cannot satisfy
// both the native grid assertion and this wrapped-edge invariant.
let nativeQY = 24, nativeQX = 40
guard let nativeKernel = ProbeKernel.synthetic(
    radius: 3, width: 1.5, qy: nativeQY, qx: nativeQX
) else { fail("non-radix native probe kernel returned nil") }
guard nativeKernel.py == nativeQY, nativeKernel.px == nativeQX else {
    fail("non-radix kernel was padded to \(nativeKernel.py)x\(nativeKernel.px)")
}
let shiftY = 7, shiftX = 13
var shiftedKernel = [Float](repeating: 0, count: nativeQY * nativeQX)
for y in 0..<nativeQY {
    for x in 0..<nativeQX {
        let sourceY = (y - shiftY + nativeQY) % nativeQY
        let sourceX = (x - shiftX + nativeQX) % nativeQX
        shiftedKernel[y * nativeQX + x] = nativeKernel.kernel[sourceY * nativeQX + sourceX]
    }
}
guard let nativeDetector = DiskDetector(kernel: nativeKernel) else {
    fail("non-radix native detector returned nil")
}
var nativeParams = DiskDetectionParams()
nativeParams.sigmaCC = 0
nativeParams.subpixel = .pixel
nativeParams.minRelativeIntensity = 0
nativeParams.minPeakSpacing = 0
nativeParams.edgeBoundary = 1
nativeParams.maxNumPeaks = 1
let nativePeaks = nativeDetector.detect(pattern: shiftedKernel, params: nativeParams)
let expectedAutocorrelation = nativeKernel.kernel.reduce(Float(0)) { $0 + $1 * $1 }
guard nativePeaks.count == 1,
      nativePeaks[0].x == Float(shiftX), nativePeaks[0].y == Float(shiftY),
      abs(nativePeaks[0].intensity - expectedAutocorrelation) < 2e-5 else {
    fail("non-radix native circular correlation differs: \(nativePeaks)")
}
print("PASS: non-radix-2 native circular correlation")

// vDSP's general DFT omits pure radix-3/5 sizes such as 27 and 125. Verify
// selected analytic bins, not only a round trip, so a radix/exponent mismatch
// cannot pass by applying two inverse mistakes.
func verifyExactRadixFFT(size: Int, impulseRow: Int, impulseColumn: Int) {
    var real = [Float](repeating: 0, count: size * size)
    var imaginary = [Float](repeating: 0, count: real.count)
    real[impulseRow * size + impulseColumn] = 1
    guard let fft = FFT2D(nx: size, ny: size) else {
        fail("\(size)×\(size) exact-radix FFT setup returned nil")
    }
    fft.transform(re: &real, im: &imaginary, forward: true)
    let bins = [(0, 0), (1, 2), (size / 7, size / 4),
                (size / 2, size / 2), (size - 1, size * 3 / 4)]
    for (frequencyRow, frequencyColumn) in bins {
        let phase = -2 * Float.pi * (
            Float(frequencyRow * impulseRow + frequencyColumn * impulseColumn)
            / Float(size)
        )
        let index = frequencyRow * size + frequencyColumn
        guard abs(real[index] - cos(phase)) < 2e-5,
              abs(imaginary[index] - sin(phase)) < 2e-5 else {
            fail("\(size)×\(size) exact-radix analytic bin mismatch at \(frequencyRow),\(frequencyColumn)")
        }
    }
    fft.transform(re: &real, im: &imaginary, forward: false)
    for index in real.indices {
        let expected: Float = index == impulseRow * size + impulseColumn ? 1 : 0
        guard abs(real[index] - expected) < 2e-5,
              abs(imaginary[index]) < 2e-5 else {
            fail("\(size)×\(size) exact-radix round-trip mismatch at \(index)")
        }
    }
}
verifyExactRadixFFT(size: 27, impulseRow: 5, impulseColumn: 8)
verifyExactRadixFFT(size: 125, impulseRow: 7, impulseColumn: 11)
print("PASS: 27×27 radix-3 and 125×125 radix-5 FFT analytic parity")

var measuredPixels = [Float](repeating: 0, count: 8 * 8)
measuredPixels[4 * 8 + 3] = 7
let measuredPattern = DiffractionPattern(qy: 8, qx: 8, pixels: measuredPixels)
guard let measuredKernel = ProbeKernel.measured(
    pattern: measuredPattern, originX: 3, originY: 4, radius: 2
) else { fail("measured probe kernel returned nil") }
guard measuredKernel.source == .measured,
      measuredKernel.kernel[0] > 0,
      abs(measuredKernel.kernel.reduce(0, +)) < 1e-6 else {
    fail("measured probe was not centered and zero-normalized")
}
print("PASS: measured vacuum probe kernel centering and normalization")

let provenance = nativeParams.provenance(
    kernel: nativeKernel, qy: nativeQY, qx: nativeQX
)
guard provenance["detection_algorithm"] == DiskDetectionParams.algorithmID,
      provenance["subpixel"] == "pixel",
      provenance["kernel_source"] == "synthetic",
      provenance["detector_qy"] == String(nativeQY),
      provenance["detector_qx"] == String(nativeQX) else {
    fail("disk-detection provenance is incomplete: \(provenance)")
}
print("PASS: validated parameter contract, diagnostics, and provenance")

print("disk-detection-test: all passed")
