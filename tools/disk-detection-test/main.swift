import Foundation

struct Fixture: Decodable {
    let dimensions: [Int]
    let radius: Float
    let width: Float
    let trenchRadii: [Float]
    let pattern: [Float]
    let kernel: [Float]
    let cases: [DetectionCase]
}

struct DetectionCase: Decodable {
    let name: String
    let params: Parameters
    let expected: [ExpectedPeak]
}

struct Parameters: Decodable {
    let corrPower: Float
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

guard let detector = DiskDetector(kernel: kernel) else {
    fail("production DiskDetector returned nil")
}

for test in fixture.cases {
    var params = DiskDetectionParams()
    params.corrPower = test.params.corrPower
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

    let actual = detector.detect(pattern: fixture.pattern, params: params)
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

print("disk-detection-test: all passed")
