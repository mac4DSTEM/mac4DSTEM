import Foundation
import Metal

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

actor SyntheticDataSource: FourDDataSource {
    let descriptor: DatasetDescriptor
    let cube: [Float]
    private(set) var maximumRowsRead = 0

    init(descriptor: DatasetDescriptor, cube: [Float]) {
        self.descriptor = descriptor
        self.cube = cube
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        view.pattern(fromFullCube: cube, ry: ry, rx: rx)
    }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        view.scanRow(fromFullCube: cube, ry: ry)
    }
    func readScanTile(_ view: LoadView,
                      yRange: Range<Int>) throws -> FourDScanTile {
        maximumRowsRead = max(maximumRowsRead, yRange.count)
        return view.scanTile(fromFullCube: cube, yRange: yRange)
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

// Origin measurement against a KNOWN centre (Gate D 2026-09-05). The beam is
// a smooth blob the size of WS2's — plateau ~2 px, soft 1 px edge — centred
// 0.26 px off a pixel centre on a 128 px detector, at three scan positions
// with three different sub-pixel centres. The shipped kernel took a single
// centre of mass in a 1.2 × r window around a BLOCK-BINNED coarse maximum,
// which sits up to bin/2 off; the truncated window then pulled the centre
// toward the block: WS2's 16 384 positions all read 63.986 for a beam at
// 63.738 (scratchpad origin-experiment-ws2-20260905.log). Truth here is
// the centre the blob was drawn at. The tolerance is 0.02 px: the kernel
// reads 0.009 px here, and the Gate B mutation that survived a 0.05 px
// tolerance — a bounding box that clips one side of the window by a pixel
// — reads 0.041 px (mutation log, 2026-09-05).
do {
    let q = 128
    let centres: [(x: Double, y: Double)] = [(63.74, 63.74), (40.30, 70.85), (91.12, 21.58)]
    var beamCube = [Float](repeating: 0, count: centres.count * q * q)
    for (position, centre) in centres.enumerated() {
        for y in 0..<q {
            for x in 0..<q {
                let r = ((Double(x) - centre.x) * (Double(x) - centre.x)
                         + (Double(y) - centre.y) * (Double(y) - centre.y)).squareRoot()
                // flat top to r = 1.5, then a Gaussian shoulder of sigma 0.6
                let value = r <= 1.5 ? 1.0 : exp(-((r - 1.5) * (r - 1.5)) / (2 * 0.6 * 0.6))
                beamCube[position * q * q + y * q + x] = Float(value * 1000 + 0.5)
            }
        }
    }
    guard let beamBuffer = MetalEngine.shared.device.makeBuffer(
        bytes: beamCube, length: beamCube.count * MemoryLayout<Float>.stride,
        options: .storageModeShared
    ) else { fail("could not allocate the synthetic beam cube") }
    let measured = try MetalEngine.shared.measureOrigins(
        cube: beamBuffer,
        params: OriginParams(ry: 1, rx: UInt32(centres.count), qy: UInt32(q), qx: UInt32(q),
                             r: 1.86, rscale: 1.2)
    )
    var worstOffset = 0.0
    for (position, centre) in centres.enumerated() {
        let dx = Double(measured[2 * position]) - centre.x
        let dy = Double(measured[2 * position + 1]) - centre.y
        worstOffset = max(worstOffset, abs(dx), abs(dy))
        guard abs(dx) < 0.02, abs(dy) < 0.02 else {
            fail(String(format: "origin_measurement_truth: position %d measured (%.3f, %.3f) against the drawn centre (%.2f, %.2f) — off by (%.3f, %.3f) px",
                        position, measured[2 * position], measured[2 * position + 1], centre.x, centre.y, dx, dy))
        }
    }
    print(String(format: "PASS: origin_measurement_truth [three sub-pixel centres within 0.02 px] worst offset %.4f px", worstOffset))
}

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

// Selected-area diffraction on a cube TALL enough that the region's mask
// differs from row to row (ry = 4, region rows 1…2, rows 0 and 3 excluded),
// against a ground truth summed here on the CPU — not against the resident
// Metal path, which shares `makeMask` with the tiled one. Gate B 2026-08-27
// showed that with the 2-row fixture above, feeding every tile ROW 0's mask
// slice stayed green on every harness; here row 0 is excluded, so that
// mutation sums nothing and fails. Two more from the 2026-09-05 refuter:
// the scan value is `2^scan`, so every SUBSET of scan positions has a unique
// sum (a value linear in scan index let a row REVERSAL inside a tile pass,
// because 1+2+10+11 = 4+5+7+8); and the region is 1 wide × 2 tall, so an
// x/y swap of the region cannot cancel (docs/open-items.md, "Selected-area
// diffraction's mask-to-tile correspondence is unpinned").
do {
    let tall = DatasetDescriptor(
        filePath: "synthetic-tall", datasetPath: "/synthetic-tall",
        shape: [4, d.rx, d.qy, d.qx], dtypeDescription: "float32", chunkShape: nil
    )
    let tallScanCount = tall.ry * tall.rx
    var tallCube = [Float](repeating: 0, count: tallScanCount * detectorPixels)
    for scan in 0..<tallScanCount {
        for y in 0..<tall.qy {
            for x in 0..<tall.qx {
                tallCube[scan * detectorPixels + y * tall.qx + x] = Float(1 << scan) * 1_000 + Float(y * 100 + x)
            }
        }
    }
    let region = DetectorShape.rectangle(xMin: 1, xMax: 2, yMin: 1, yMax: 3)
    var truth = [Float](repeating: 0, count: detectorPixels)
    for ry in 1..<3 {
        for rx in 1..<2 {
            let scan = ry * tall.rx + rx
            for index in 0..<detectorPixels { truth[index] += tallCube[scan * detectorPixels + index] }
        }
    }
    let tallSource = SyntheticDataSource(descriptor: tall, cube: tallCube)
    let tallData = FourDArray(reader: tallSource, descriptor: tall)
    let tallTiled = try await VirtualDetector.tiledDiffraction(
        data: tallData, descriptor: tall, region: region, maximumTileRows: 1
    )
    compare(tallTiled.pixels, expected: truth,
            caseName: "selected_area_diffraction_partial_rows", path: "forced 1-row tiles vs CPU truth")
    guard await tallSource.maximumRowsRead == 1 else {
        fail("selected_area_diffraction_partial_rows tile reader exceeded the forced one-row bound")
    }
    // Two-row tiles straddle the region's edge rows (tile 0 = rows 0–1, tile
    // 1 = rows 2–3): the slice must be per row inside a tile as well.
    let twoRow = try await VirtualDetector.tiledDiffraction(
        data: tallData, descriptor: tall, region: region, maximumTileRows: 2
    )
    compare(twoRow.pixels, expected: truth,
            caseName: "selected_area_diffraction_partial_rows", path: "forced 2-row tiles vs CPU truth")
}

guard let diskKernel = ProbeKernel.synthetic(
    radius: 1.25, width: 0.75, qy: d.qy, qx: d.qx
) else { fail("could not construct disk kernel for tiled parity") }
var diskParams = DiskDetectionParams()
diskParams.sigmaCC = 0
diskParams.subpixel = .pixel
diskParams.minRelativeIntensity = 0
diskParams.minPeakSpacing = 0
// The maxima detector needs a one-pixel neighborhood; zero was historically
// clamped to one internally and is now rejected by the public contract.
diskParams.edgeBoundary = 1
diskParams.maxNumPeaks = 8
guard let residentDisks = DiskDetection.detectAll(
    cube: cubeBuffer, descriptor: d, kernel: diskKernel, params: diskParams
) else { fail("resident disk detection failed") }
guard let tiledDisks = try await DiskDetection.detectAll(
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
