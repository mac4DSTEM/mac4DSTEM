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
}

print("virtual-detector-test: all passed")
