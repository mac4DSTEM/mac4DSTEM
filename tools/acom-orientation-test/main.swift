import Foundation
import simd

struct Fixture: Decodable {
    let cases: [OrientationCase]
    let ipfCases: [IPFCase]
}
struct OrientationCase: Decodable {
    let name: String
    let matrix: [[Double]]
    let euler: [Double]
    let zoneAxis: [Double]?
    let inPlaneAngle: Float?
}
struct IPFCase: Decodable {
    let name: String
    let direction: [Double]
    let rgb: [Double]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func matrix(_ rows: [[Double]]) -> simd_double3x3 {
    guard rows.count == 3, rows.allSatisfy({ $0.count == 3 }) else {
        fail("matrix must be 3x3")
    }
    return simd_double3x3(columns: (
        SIMD3(rows[0][0], rows[1][0], rows[2][0]),
        SIMD3(rows[0][1], rows[1][1], rows[2][1]),
        SIMD3(rows[0][2], rows[1][2], rows[2][2])
    ))
}

func maximumError(_ lhs: simd_double3x3, _ rhs: simd_double3x3) -> Double {
    var result = 0.0
    for column in 0..<3 {
        for row in 0..<3 { result = max(result, abs(lhs[column][row] - rhs[column][row])) }
    }
    return result
}

guard CommandLine.arguments.count == 2 else { fail("usage: harness expected.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)

for test in fixture.cases {
    let expectedMatrix = matrix(test.matrix)
    let actual = EulerAngles(py4DSTEMOrientationMatrix: expectedMatrix)
    let values = [Double(actual.phi1), Double(actual.Phi), Double(actual.phi2)]
    guard test.euler.count == 3 else { fail("\(test.name) expected Euler must have 3 values") }
    let eulerError = zip(values, test.euler).map { abs($0 - $1) }.max() ?? 0
    guard eulerError <= 2e-6 else {
        fail("\(test.name) Euler \(values), expected \(test.euler), error \(eulerError)")
    }
    let roundTripError = maximumError(actual.py4DSTEMOrientationMatrix, expectedMatrix)
    guard roundTripError <= 2e-6 else {
        fail("\(test.name) matrix round-trip error \(roundTripError)")
    }

    if let zone = test.zoneAxis, let angle = test.inPlaneAngle {
        guard zone.count == 3 else { fail("\(test.name) zoneAxis must have 3 values") }
        let n = simd_normalize(SIMD3(zone[0], zone[1], zone[2]))
        let basis = ACOMOrientation.detectorBasis(zoneAxis: n)
        let composed = ACOMOrientation.matrix(detectorBasis: basis, inPlaneAngle: angle)
        let compositionError = maximumError(composed, expectedMatrix)
        guard compositionError <= 2e-7 else {
            fail("\(test.name) basis/in-plane composition error \(compositionError)")
        }
        guard simd_length(composed.columns.2 - n) <= 1e-12 else {
            fail("\(test.name) composition changed the zone axis")
        }
    }
    print("PASS: \(test.name) Euler error \(eulerError), round-trip \(roundTripError)")
}

guard CubicOrientationSymmetry.operators.count == 24 else {
    fail("cubic group has \(CubicOrientationSymmetry.operators.count) operators, expected 24")
}
for (index, symmetry) in CubicOrientationSymmetry.operators.enumerated() {
    let determinantError = abs(simd_determinant(symmetry) - 1)
    let orthogonalityError = maximumError(simd_transpose(symmetry) * symmetry, matrix([
        [1, 0, 0], [0, 1, 0], [0, 0, 1],
    ]))
    guard determinantError <= 1e-12, orthogonalityError <= 1e-12 else {
        fail("cubic operator \(index) is not a proper rotation")
    }
}
print("PASS: 24 proper cubic symmetry operators")

let orbitSeed = matrix(fixture.cases[1].matrix)
let representative = CubicOrientationSymmetry.reduce(orbitSeed)
guard representative.disorientationRad <= Float(62.9 * Double.pi / 180) else {
    fail("cubic representative exceeds the fundamental-zone angular bound")
}
for (index, symmetry) in CubicOrientationSymmetry.operators.enumerated() {
    let equivalent = CubicOrientationSymmetry.reduce(symmetry * orbitSeed)
    guard maximumError(equivalent.matrix, representative.matrix) <= 2e-12,
          abs(equivalent.disorientationRad - representative.disorientationRad) <= 2e-7 else {
        fail("symmetry-equivalent orientation \(index) reduced differently")
    }
}
print("PASS: cubic reduction is deterministic over a full symmetry orbit")

let sampledAxes = CubicOrientationSymmetry.sampleFundamentalZone(count: 96)
guard sampledAxes.count == 96 else {
    fail("cubic fundamental-zone sampler returned \(sampledAxes.count), expected 96")
}
let expectedVertices = [
    SIMD3<Double>(0, 0, 1),
    simd_normalize(SIMD3<Double>(1, 0, 1)),
    simd_normalize(SIMD3<Double>(1, 1, 1)),
]
for index in expectedVertices.indices where simd_length(sampledAxes[index] - expectedVertices[index]) > 1e-12 {
    fail("cubic sampler omitted canonical vertex \(index)")
}
for (index, axis) in sampledAxes.enumerated() {
    guard abs(simd_length(axis) - 1) <= 1e-12,
          axis.y >= -1e-12, axis.x + 1e-12 >= axis.y,
          axis.z + 1e-12 >= axis.x else {
        fail("sampled axis \(index) lies outside z >= x >= y >= 0")
    }
    for prior in 0..<index where simd_dot(axis, sampledAxes[prior]) > 1 - 1e-10 {
        fail("sampled axes \(prior) and \(index) are symmetry-equivalent duplicates")
    }
}
print("PASS: 96 unique cubic fundamental-zone template axes")

for test in fixture.ipfCases {
    guard test.direction.count == 3, test.rgb.count == 3 else {
        fail("\(test.name) must contain three direction and RGB components")
    }
    let direction = SIMD3(test.direction[0], test.direction[1], test.direction[2])
    let actual = CubicOrientationSymmetry.ipfColor(direction: direction)
    let values = [Double(actual.x), Double(actual.y), Double(actual.z)]
    let error = zip(values, test.rgb).map { abs($0 - $1) }.max() ?? 0
    guard error <= 2e-3 else {
        fail("\(test.name) RGB \(values), expected \(test.rgb), error \(error)")
    }
    let equivalent = CubicOrientationSymmetry.ipfColor(
        direction: SIMD3(-direction.z, direction.x, -direction.y)
    )
    let symmetryError = simd_length(actual - equivalent)
    guard symmetryError <= 1e-6 else {
        fail("\(test.name) direction color changed under cubic symmetry")
    }
    print("PASS: \(test.name) orix RGB error \(error)")
}

let nearA = CubicOrientationSymmetry.ipfColor(direction: SIMD3(0.2, 0.1, 0.97))
let nearB = CubicOrientationSymmetry.ipfColor(direction: SIMD3(0.20001, 0.1, 0.97))
guard simd_length(nearA - nearB) < 0.001 else { fail("IPF color is not locally continuous") }
print("PASS: IPF color is locally continuous")

print("acom-orientation-test: all passed")
