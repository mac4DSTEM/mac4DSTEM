import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

let origin = (x: Float(50), y: Float(50))
func latticePeaks(g1: (Float, Float), g2: (Float, Float)) -> [BraggPeak] {
    let hk: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1)]
    return hk.map { h, k in
        BraggPeak(
            x: origin.x + h * g1.0 + k * g2.0,
            y: origin.y + h * g1.1 + k * g2.1,
            intensity: 1
        )
    }
}

let reference = latticePeaks(g1: (10, 0), g2: (0, 10))
let strained = latticePeaks(g1: (9, 0), g2: (0, 11))
let vectors = BraggVectors(
    scanWidth: 4, scanHeight: 1,
    peaks: [reference, reference, strained, strained]
)

guard let whole = StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y
) else { fail("whole-scan reference failed") }
guard whole.referencePositionCount == 4,
      abs(whole.exx[2] - (1 - 9 / 9.5)) < 1e-5,
      abs(whole.eyy[2] - (1 - 11 / 10.5)) < 1e-5 else {
    fail("whole-scan reference values differ")
}
print("PASS: whole-scan mean reference")

guard let selected = StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    referenceMask: [true, true, false, false]
) else { fail("selected reference failed") }
guard selected.referencePositionCount == 2,
      abs(selected.exx[0]) < 1e-6, abs(selected.eyy[0]) < 1e-6,
      abs(selected.exx[2] - 0.1) < 1e-6,
      abs(selected.eyy[2] + 0.1) < 1e-6 else {
    fail("selected reference strain values differ")
}
print("PASS: selected unstrained reference region")

guard let manual = StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    referenceMask: [true, true, false, false],
    initialBasis: (g1: (x: 10, y: 0), g2: (x: 0, y: 10))
) else { fail("manual reciprocal basis failed") }
guard abs(manual.exx[2] - 0.1) < 1e-6,
      abs(manual.eyy[2] + 0.1) < 1e-6 else {
    fail("manual reciprocal basis changed the expected strain")
}
guard StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    initialBasis: (g1: (x: 10, y: 0), g2: (x: 20, y: 0))
) == nil else { fail("collinear manual reciprocal basis should fail") }
print("PASS: manual reciprocal basis and collinearity validation")

guard StrainMapping.compute(
    bragg: vectors, originX: origin.x, originY: origin.y,
    referenceMask: [false, false, false, false]
) == nil else { fail("empty reference region should fail") }
print("PASS: empty reference rejected")

let qRadii: [Float] = [10, 10.2, 9.8, 3, 20]
let qVectors = BraggVectors(
    scanWidth: qRadii.count, scanHeight: 1,
    peaks: qRadii.map { radius in
        [BraggPeak(x: origin.x + radius, y: origin.y, intensity: 1)]
    }
)
guard let qEstimate = KnownCrystalQCalibration.estimate(
    bragg: qVectors, origin: origin, referenceRadiusInvAngstrom: 0.25
) else { fail("known-crystal Q calibration failed") }
guard abs(qEstimate.observedRadiusPixels - 10) < 1e-6,
      abs(qEstimate.invAngstromPerPixel - 0.025) < 1e-9,
      qEstimate.sampleCount == 5 else {
    fail("known-crystal median Q calibration differs")
}
print("PASS: robust known-crystal Q calibration")

guard let wavelength = DPC.electronWavelengthAngstrom(voltageKV: 200),
      let angularScale = DPC.milliradiansPerDetectorPixel(
        voltageKV: 200, invAngstromPerPixel: 0.01
      ) else { fail("physical DPC scale returned nil") }
guard abs(wavelength - 0.025079) < 1e-5,
      abs(angularScale - 0.25079) < 1e-4 else {
    fail("relativistic DPC angular scale differs: \(wavelength) Å, \(angularScale) mrad/px")
}
let physicalDPC = DPC.physicalMagnitudeImage(
    com: [3, 4], width: 1, height: 1, milliradiansPerPixel: angularScale
)
guard abs(physicalDPC.pixels[0] - 5 * angularScale) < 1e-6 else {
    fail("physical DPC magnitude scaling differs")
}
print("PASS: relativistic DPC mrad conversion")
print("strain-test: all passed")
