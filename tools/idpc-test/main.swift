import Foundation

struct Fixture: Decodable {
    let width: Int
    let height: Int
    let rowSamplingAngstrom: Float
    let columnSamplingAngstrom: Float
    let reciprocalAngstromPerDetectorPixel: Float
    let com: [Float]
    let expectedPhase: [Float]
    let periodic: [Float]
    let zeroPadded: [Float]
    let qualitative: [Float]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func maximumError(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count else { return .infinity }
    return zip(lhs, rhs).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

guard CommandLine.arguments.count == 2 else { fail("usage: idpc-test fixture.json") }
let fixture = try JSONDecoder().decode(
    Fixture.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)

let calibration = IDPCPhysicalCalibration(
    rowSamplingAngstrom: fixture.rowSamplingAngstrom,
    columnSamplingAngstrom: fixture.columnSamplingAngstrom,
    reciprocalAngstromPerDetectorPixel: fixture.reciprocalAngstromPerDetectorPixel
)
let periodic = try DPC.integratePhysicalIDPC(
    com: fixture.com, width: fixture.width, height: fixture.height,
    calibration: calibration, regularization: 0,
    boundary: .periodic, paddingFactor: 1
)
let periodicError = maximumError(periodic.pixels, fixture.periodic)
guard periodicError < 3e-5,
      maximumError(periodic.pixels, fixture.expectedPhase) < 3e-5 else {
    fail("anisotropic periodic quantitative phase differs: \(periodicError)")
}
print("PASS: non-square anisotropic quantitative phase in radians")

let padded = try DPC.integratePhysicalIDPC(
    com: fixture.com, width: fixture.width, height: fixture.height,
    calibration: calibration, boundary: .zeroPadded, paddingFactor: 2
)
let paddedError = maximumError(padded.pixels, fixture.zeroPadded)
guard paddedError < 3e-5 else {
    fail("symmetric zero-padded quantitative phase differs: \(paddedError)")
}
guard maximumError(periodic.pixels, padded.pixels) > 1e-3 else {
    fail("periodic and zero-padded boundary conditions were indistinguishable")
}
guard abs(padded.pixels.reduce(0, +)) < 2e-5 else {
    fail("phase gauge was not normalized to zero mean")
}
print("PASS: explicit periodic versus symmetric 2x zero-padded boundary")

let qualitative = try DPC.integrateIDPC(
    com: fixture.com, width: fixture.width, height: fixture.height,
    boundary: .zeroPadded, paddingFactor: 2
)
guard maximumError(qualitative.pixels, fixture.qualitative) < 3e-5 else {
    fail("qualitative fallback changed unexpectedly")
}
print("PASS: explicit qualitative detector-pixel fallback")

guard let angstrom = DPC.physicalIDPCCalibration(
    realPixelSize: 2, realPixelUnits: "A",
    reciprocalPixelSize: 0.025, reciprocalPixelUnits: "A^-1",
    voltageKV: nil
), let nanometer = DPC.physicalIDPCCalibration(
    realPixelSize: 0.2, realPixelUnits: "nm",
    reciprocalPixelSize: 0.25, reciprocalPixelUnits: "1/nm",
    voltageKV: nil
), let unicodeUnits = DPC.physicalIDPCCalibration(
    realPixelSize: 200, realPixelUnits: "pm",
    reciprocalPixelSize: 0.025, reciprocalPixelUnits: "Å⁻¹",
    voltageKV: nil
) else { fail("physical calibration conversion returned nil") }
guard angstrom == nanometer, angstrom == unicodeUnits,
      abs(angstrom.rowSamplingAngstrom - 2) < 1e-7,
      abs(angstrom.reciprocalAngstromPerDetectorPixel - 0.025) < 1e-7 else {
    fail("Å/nm physical calibration conversions differ")
}
guard let angular = DPC.physicalIDPCCalibration(
    realPixelSize: 2, realPixelUnits: "A",
    reciprocalPixelSize: 0.5, reciprocalPixelUnits: "mrad",
    voltageKV: 200
), let wavelength = DPC.electronWavelengthAngstrom(voltageKV: 200),
      abs(Double(angular.reciprocalAngstromPerDetectorPixel)
          - 0.5 / (1_000 * wavelength)) < 1e-7 else {
    fail("mrad reciprocal calibration conversion differs")
}
guard DPC.physicalIDPCCalibration(
    realPixelSize: 2, realPixelUnits: "px",
    reciprocalPixelSize: 0.025, reciprocalPixelUnits: "A^-1",
    voltageKV: 200
) == nil,
DPC.physicalIDPCCalibration(
    realPixelSize: 2, realPixelUnits: "A",
    reciprocalPixelSize: 0.5, reciprocalPixelUnits: "mrad",
    voltageKV: nil
) == nil else { fail("invalid or incomplete calibration was accepted") }
print("PASS: Å/nm/mrad conversion and qualitative readiness boundary")

// Negative controls for the v2 S7 typed-error contract. Each names the
// guard it breaks in Core/Analysis/DPC.swift's `integrateIDPC`: the old
// contract returned a zero-filled image for these inputs — a flat map
// indistinguishable from a computed phase — and these controls fail if
// that behavior ever returns.
do {
    // Breaks the `com.count == n * 2` guard: 0 values offered, 12 required.
    let image = try DPC.integrateIDPC(com: [], width: 3, height: 2)
    fail("an empty CoM field was integrated into a \(image.width)x\(image.height) image instead of refusing")
} catch let error as DPC.IDPCError {
    guard case .invalidInput(let reason) = error, reason.contains("12") else {
        fail("empty CoM refused with the wrong reason: \(error)")
    }
}
do {
    // Breaks the `width > 1, height > 1` guard: a 1-wide scan has no
    // gradient to integrate along its second axis.
    let image = try DPC.integrateIDPC(
        com: [Float](repeating: 0, count: 2), width: 1, height: 1
    )
    fail("a 1x1 scan was integrated into a \(image.width)x\(image.height) image instead of refusing")
} catch let error as DPC.IDPCError {
    guard case .invalidInput = error else {
        fail("1x1 scan refused with the wrong error: \(error)")
    }
}
print("PASS: invalid input throws a typed refusal, never a zero image")
print("idpc-test: all passed")
