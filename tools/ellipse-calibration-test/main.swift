import Foundation

struct Fixture: Decodable { let cases: [RingCase] }
struct RingCase: Decodable {
    let name: String
    let height: Int
    let width: Int
    let centerQX: Double
    let centerQY: Double
    let a: Double
    let b: Double
    let theta: Double
    let innerRadius: Double
    let outerRadius: Double
    let pixels: [Float]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func angleError(_ lhs: Double, _ rhs: Double) -> Double {
    let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi)
    return min(raw, .pi - raw)
}

guard CommandLine.arguments.count == 2 else { fail("usage: harness expected.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
for test in fixture.cases {
    let pattern = DiffractionPattern(qy: test.height, qx: test.width, pixels: test.pixels)
    let fit = try EllipseCalibration.fit1D(
        pattern: pattern, centerQX: test.centerQX + 0.8, centerQY: test.centerQY - 0.6,
        innerRadius: test.innerRadius, outerRadius: test.outerRadius
    )
    guard abs(fit.centerQX - test.centerQX) < 0.08,
          abs(fit.centerQY - test.centerQY) < 0.08,
          abs(fit.a - test.a) < 0.18,
          abs(fit.b - test.b) < 0.18,
          angleError(fit.theta, test.theta) < 0.008,
          fit.normalizedResidual < 0.12 else {
        fail("\(test.name) differs: \(fit)")
    }
    print("PASS: \(test.name) center/axes/theta residual \(fit.normalizedResidual)")
}

let convention = fixture.cases[0]
var calibration = Calibration()
calibration.ellipseA = convention.a
calibration.ellipseB = convention.b
calibration.ellipseTheta = convention.theta
// py4DSTEM major-axis point is (qx=a cosθ, qy=a sinθ); app offset is
// (dx=qy, dy=qx). Correction must circularize it to radius b.
let rawDX = Float(convention.a * sin(convention.theta))
let rawDY = Float(convention.a * cos(convention.theta))
let corrected = calibration.ellipseCorrectedOffset(dx: rawDX, dy: rawDY)
guard abs(hypot(corrected.x, corrected.y) - Float(convention.b)) < 1e-5 else {
    fail("py4DSTEM qx/qy to app x/y ellipse transform differs")
}
print("PASS: py4DSTEM/app detector-axis correction convention")

let blank = DiffractionPattern(qy: 40, qx: 60, pixels: [Float](repeating: 1, count: 2400))
do {
    _ = try EllipseCalibration.fit1D(
        pattern: blank, centerQX: 20, centerQY: 30, innerRadius: 8, outerRadius: 18
    )
    fail("constant input unexpectedly fitted")
} catch EllipseCalibration.FitError.insufficientSignal {}
print("PASS: blank annulus rejected")

var spots = [Float](repeating: 0, count: 60 * 80)
for (qx, qy) in [(15, 40), (45, 40), (30, 25), (30, 55)] {
    spots[qx * 80 + qy] = 10
}
do {
    _ = try EllipseCalibration.fit1D(
        pattern: DiffractionPattern(qy: 60, qx: 80, pixels: spots),
        centerQX: 30, centerQY: 40, innerRadius: 10, outerRadius: 20
    )
    fail("four-spot degeneracy unexpectedly fitted")
} catch EllipseCalibration.FitError.insufficientAngularCoverage {}
print("PASS: angularly degenerate input rejected")
print("ellipse-calibration-test: all passed")
