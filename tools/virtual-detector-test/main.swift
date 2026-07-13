import Foundation
import Metal

// VirtualDetector.swift normally gets this UI-facing value type from
// AppState.swift. Defining the identical input here avoids compiling the whole
// application into this standalone scientific harness.
struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

actor SyntheticDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let cube: [Float]
    private(set) var maximumRowsRead = 0

    init(descriptor: DatasetDescriptor, cube: [Float]) {
        self.descriptor = descriptor
        self.cube = cube
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float] {
        let count = descriptor.qy * descriptor.qx
        let start = (ry * descriptor.rx + rx) * count
        return Array(cube[start..<start + count])
    }
    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float] {
        let count = descriptor.rx * descriptor.qy * descriptor.qx
        return Array(cube[ry * count..<(ry + 1) * count])
    }
    func readScanTile(_ descriptor: DatasetDescriptor,
                      yRange: Range<Int>) throws -> FourDScanTile {
        maximumRowsRead = max(maximumRowsRead, yRange.count)
        let rowCount = descriptor.rx * descriptor.qy * descriptor.qx
        return FourDScanTile(
            yRange: yRange, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            pixels: Array(cube[yRange.lowerBound * rowCount..<yRange.upperBound * rowCount])
        )
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

struct Fixture: Decodable {
    let dimensions: [Int]
    let cases: [DetectorCase]
}

struct DetectorCase: Decodable {
    let name: String
    let kind: String
    let centerX: Float?
    let centerY: Float?
    let inner: Float?
    let outer: Float?
    let xMin: Int?
    let xMax: Int?
    let yMin: Int?
    let yMax: Int?
    let pointX: Int?
    let pointY: Int?
    let expected: [Float]

    var shape: DetectorShape {
        switch kind {
        case "annulus":
            return .annulus(centerX: centerX!, centerY: centerY!,
                            inner: inner!, outer: outer!)
        case "circle":
            return .circle(centerX: centerX!, centerY: centerY!, radius: outer!)
        case "rectangle":
            return .rectangle(xMin: xMin!, xMax: xMax!, yMin: yMin!, yMax: yMax!)
        case "point":
            return .point(x: pointX!, y: pointY!)
        default:
            fatalError("Unknown detector kind: \(kind)")
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func compare(_ actual: [Float], expected: [Float], caseName: String,
             path: String, tolerance: Float = 1e-4) {
    guard actual.count == expected.count else {
        fail("\(caseName) [\(path)] count \(actual.count), expected \(expected.count)")
    }
    var maxError: Float = 0
    var maxIndex = 0
    for i in actual.indices {
        let error = abs(actual[i] - expected[i])
        if error > maxError { maxError = error; maxIndex = i }
    }
    guard maxError <= tolerance else {
        fail("\(caseName) [\(path)] max error \(maxError) at flat scan index \(maxIndex); "
             + "actual \(actual[maxIndex]), expected \(expected[maxIndex])")
    }
    print("PASS: \(caseName) [\(path)] max error \(maxError)")
}

guard CommandLine.arguments.count == 2 else { fail("usage: harness expected.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
guard fixture.dimensions.count == 4 else { fail("fixture dimensions must be rank 4") }
let d = DatasetDescriptor(
    filePath: "synthetic", datasetPath: "/synthetic",
    shape: fixture.dimensions, dtypeDescription: "float32", chunkShape: nil
)

let detectorPixels = d.qy * d.qx
let scanCount = d.ry * d.rx
var cube = [Float](repeating: 0, count: scanCount * detectorPixels)
for scan in 0..<scanCount {
    for y in 0..<d.qy {
        for x in 0..<d.qx {
            cube[scan * detectorPixels + y * d.qx + x] = Float(scan * 10_000 + y * 100 + x)
        }
    }
}

guard let cubeBuffer = MetalEngine.shared.device.makeBuffer(
    bytes: cube, length: cube.count * MemoryLayout<Float>.stride,
    options: .storageModeShared
) else { fail("could not allocate synthetic cube buffer") }

for test in fixture.cases {
    let general = try VirtualDetector.image(cube: cubeBuffer, descriptor: d, shape: test.shape)
    compare(general.pixels, expected: test.expected, caseName: test.name, path: "mask Metal")

    if test.kind == "annulus" {
        let aperture = Aperture(centerX: test.centerX!, centerY: test.centerY!,
                                inner: test.inner!, outer: test.outer!)
        let analytic = try VirtualDetector.run(cube: cubeBuffer, descriptor: d, aperture: aperture)
        compare(analytic.pixels, expected: test.expected,
                caseName: test.name, path: "analytic Metal")
        compare(analytic.pixels, expected: general.pixels,
                caseName: test.name, path: "analytic vs mask")
    }

    let source = SyntheticDataSource(descriptor: d, cube: cube)
    let tiledData = FourDArray(reader: source, descriptor: d)
    let tiled = try await VirtualDetector.tiledImage(
        data: tiledData, descriptor: d, shape: test.shape, maximumTileRows: 1
    )
    compare(tiled.pixels, expected: test.expected,
            caseName: test.name, path: "forced 1-row tiles")
    guard await source.maximumRowsRead == 1 else {
        fail("\(test.name) tile reader exceeded the forced one-row bound")
    }
}

let fieldSource = SyntheticDataSource(descriptor: d, cube: cube)
let fieldData = FourDArray(reader: fieldSource, descriptor: d)
let residentOrigins = try MetalEngine.shared.measureOrigins(
    cube: cubeBuffer,
    params: OriginParams(ry: UInt32(d.ry), rx: UInt32(d.rx),
                         qy: UInt32(d.qy), qx: UInt32(d.qx),
                         r: 1.5, rscale: 1.2)
)
let tiledOrigins = try await VirtualDetector.tiledMeasuredOrigins(
    data: fieldData, descriptor: d, probeRadius: 1.5,
    maximumTileRows: 1
)
compare(tiledOrigins, expected: residentOrigins,
        caseName: "origin_measurement", path: "forced 1-row tiles")

let residentCoM = try MetalEngine.shared.centerOfMass(
    cube: cubeBuffer,
    params: CoMParams(ry: UInt32(d.ry), rx: UInt32(d.rx),
                      qy: UInt32(d.qy), qx: UInt32(d.qx),
                      cx: 3, cy: 2, useOrigins: 0)
)
let tiledCoM = try await VirtualDetector.tiledCenterOfMass(
    data: fieldData, descriptor: d, center: (3, 2), maximumTileRows: 1
)
compare(tiledCoM, expected: residentCoM,
        caseName: "center_of_mass", path: "forced 1-row tiles")

let scanRegion = DetectorShape.rectangle(xMin: 1, xMax: 3, yMin: 0, yMax: 2)
let residentDiffraction = try VirtualDetector.diffraction(
    cube: cubeBuffer, descriptor: d, region: scanRegion
)
let tiledDiffraction = try await VirtualDetector.tiledDiffraction(
    data: fieldData, descriptor: d, region: scanRegion, maximumTileRows: 1
)
compare(tiledDiffraction.pixels, expected: residentDiffraction.pixels,
        caseName: "selected_area_diffraction", path: "forced 1-row tiles")

guard let diskKernel = ProbeKernel.synthetic(
    radius: 1.25, width: 0.75, qy: d.qy, qx: d.qx
) else { fail("could not construct disk kernel for tiled parity") }
var diskParams = DiskDetectionParams()
diskParams.sigmaCC = 0
diskParams.subpixel = .pixel
diskParams.minRelativeIntensity = 0
diskParams.minPeakSpacing = 0
diskParams.edgeBoundary = 0
diskParams.maxNumPeaks = 8
guard let residentDisks = DiskDetection.detectAll(
    cube: cubeBuffer, descriptor: d, kernel: diskKernel, params: diskParams
) else { fail("resident disk detection failed") }
guard let tiledDisks = await DiskDetection.detectAll(
    data: fieldData, descriptor: d, kernel: diskKernel, params: diskParams,
    maximumTileRows: 1
) else { fail("tiled disk detection failed") }
guard residentDisks.peaks.count == tiledDisks.peaks.count else {
    fail("tiled disk position count differs from resident path")
}
for scan in residentDisks.peaks.indices {
    let expected = residentDisks.peaks[scan]
    let actual = tiledDisks.peaks[scan]
    guard expected.count == actual.count else {
        fail("tiled disk peak count differs at scan index \(scan)")
    }
    for peak in expected.indices {
        guard expected[peak].x == actual[peak].x,
              expected[peak].y == actual[peak].y,
              expected[peak].intensity == actual[peak].intensity else {
            fail("tiled disk value differs at scan \(scan), peak \(peak)")
        }
    }
}
print("PASS: disk_detection [forced 1-row tiles] exact resident parity")

let cancelledSource = SyntheticDataSource(descriptor: d, cube: cube)
let cancelledData = FourDArray(reader: cancelledSource, descriptor: d)
let cancelled = AnalysisCancellationToken()
cancelled.cancel()
do {
    _ = try await VirtualDetector.tiledImage(
        data: cancelledData, descriptor: d, shape: fixture.cases[0].shape,
        maximumTileRows: 1, cancellation: cancelled
    )
    fail("cancelled tiled virtual detector published a result")
} catch is CancellationError {
    print("PASS: forced-tile cancellation returns no partial image")
}

let statisticsSource = SyntheticDataSource(descriptor: d, cube: cube)
let statisticsData = FourDArray(reader: statisticsSource, descriptor: d)
let statistics = try await VirtualDetector.tiledDPStatistics(
    data: statisticsData, descriptor: d, maximumTileRows: 1
)
for q in 0..<detectorPixels {
    let values = (0..<scanCount).map { cube[$0 * detectorPixels + q] }
    let expectedMax = values.max()!
    let expectedMean = values.reduce(0, +) / Float(scanCount)
    guard abs(statistics.maxDP[q] - expectedMax) <= 1e-5,
          abs(statistics.meanDP[q] - expectedMean) <= 1e-3 else {
        fail("forced-tile DP statistics differ at detector index \(q)")
    }
}
print("PASS: forced 1-row DP statistics")

print("virtual-detector-test: all passed")
